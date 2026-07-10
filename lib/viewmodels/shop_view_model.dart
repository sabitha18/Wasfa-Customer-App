import 'package:flutter/foundation.dart';
import '../core/network/api_exception.dart';
import '../data/models/product.dart';
import '../data/repositories/catalog_repository.dart';
import '../data/services/catalog_service.dart';

/// Initial filter state a caller can seed the Shop (PLP) screen with —
/// e.g. opening from a storefront (pharmacy set), a category tile, or a
/// brand tile. Mirrors how JS mutates the global `SHOP` object before
/// calling `go('shop')`.
class ShopFilter {
  final String? pharmacy;
  final String? category;
  final String? brand;
  const ShopFilter({this.pharmacy, this.category, this.brand});
}

class ShopViewModel extends ChangeNotifier {
  final CatalogRepository _repo = CatalogRepository.instance;
  final CatalogService _service = CatalogService.instance;

  bool isLoading = true;
  String? error;
  List<Product> _fetched = [];

  String? pharmacy;
  String? category;
  String? concern;
  String query = '';
  String view = 'grid'; // grid | list
  String sort = 'pop'; // pop | low | high | rated
  List<String> brands = [];
  bool inStock = false;
  bool offersOnly = false;

  ShopViewModel({ShopFilter? initial}) {
    if (initial != null) {
      pharmacy = initial.pharmacy;
      category = initial.category;
      if (initial.brand != null) brands = [initial.brand!];
    }
    load();
  }

  /// `pharmacy`/`concern`/`brand`/`offersOnly` aren't filtered server-side —
  /// they're applied client-side against a wide page (`per_page: 100`)
  /// fetched from the server, same as `sort=rated` which the API also
  /// doesn't support. `brand` used to be sent as a server query param, but
  /// the API's exact-match behavior on real brand names (spaces, dashes,
  /// mixed case) was unreliable and could come back with zero results —
  /// filtering client-side against the already-loaded page is more robust.
  Future<void> load() async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      final page = await _service.products(
        query: query,
        category: category,
        sort: sort == 'rated' ? 'pop' : sort,
        inStock: inStock,
        page: 1,
        perPage: 100,
      );
      _fetched = page.items;
      _repo.cacheProducts(_fetched);
    } catch (e) {
      error = describeError(e);
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// Top always-visible category chip row — matches HTML's `setCat()`:
  /// plain set, never toggles off by tapping the same chip again.
  void setCategory(String? c) {
    category = c;
    load();
  }

  /// Filter sheet's Categories section — matches HTML's `setFilterCat()`:
  /// tapping the already-selected category clears it back to "All".
  void toggleFilterCategory(String? c) {
    category = category == c ? null : c;
    load();
  }

  void setPharmacy(String? nm) {
    pharmacy = nm;
    notifyListeners();
  }

  void setConcern(String? c) {
    concern = concern == c ? null : c;
    notifyListeners();
  }

  void setQuery(String q) {
    query = q;
    load();
  }

  void setView(String v) {
    view = v;
    notifyListeners();
  }

  void setSort(String s) {
    sort = s;
    load();
  }

  void toggleBrand(String b) {
    if (brands.contains(b)) {
      brands.remove(b);
    } else {
      brands.add(b);
    }
    notifyListeners();
  }

  void toggleInStock() {
    inStock = !inStock;
    load();
  }

  void toggleOffersOnly() {
    offersOnly = !offersOnly;
    notifyListeners();
  }

  void clearFilters() {
    brands = [];
    inStock = false;
    offersOnly = false;
    pharmacy = null;
    category = null;
    load();
  }

  void clearPharmacy() {
    pharmacy = null;
    notifyListeners();
  }

  bool get hasActiveFilters => brands.isNotEmpty || inStock || offersOnly;

  /// Matches HTML's `sellerNames()` — unique seller names for the Filter
  /// sheet's Pharmacy chips. Sourced from [CatalogRepository]'s global
  /// product cache (accumulated across every Shop/Home/PDP fetch so far),
  /// NOT from [_fetched] — the current query's results can legitimately be
  /// empty (e.g. a category with no matches), and the chip list must stay
  /// populated so the person can still change their filter instead of
  /// getting stuck looking at an empty sheet with no way out but "Clear all".
  List<String> get sellerNames {
    final names = <String>{};
    for (final p in _repo.products) {
      for (final s in p.sellers) {
        if (s.name.isNotEmpty) names.add(s.name);
      }
    }
    return names.toList()..sort();
  }

  /// Real brands seen so far across the global product cache — see
  /// [sellerNames] for why this reads from the cache and not [_fetched].
  List<String> get realBrands {
    final names = <String>{};
    for (final p in _repo.products) {
      if (p.brand.isNotEmpty) names.add(p.brand);
    }
    return names.toList()..sort();
  }

  List<Product> get results {
    var list = List<Product>.from(_fetched);
    if (pharmacy != null) list = list.where((p) => p.sellers.any((s) => s.name == pharmacy)).toList();
    if (concern != null) list = list.where((p) => p.concern == concern).toList();
    if (brands.isNotEmpty) list = list.where((p) => brands.contains(p.brand)).toList();
    if (offersOnly) list = list.where((p) => p.isOffer).toList();
    if (sort == 'rated') list.sort((a, b) => b.rating.compareTo(a.rating));
    return list;
  }
}
