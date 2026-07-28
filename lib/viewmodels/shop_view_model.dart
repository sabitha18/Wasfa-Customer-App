import 'package:flutter/foundation.dart';
import '../core/network/api_exception.dart';
import '../data/models/home_feed.dart';
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
  /// Store id (the shop's `user_id`) to filter the listing to a single store
  /// via `GET /app/products?shop=<id>`. Null = browse the whole catalogue.
  final int? shopId;
  /// Pre-apply the "Offers only" / best-sellers-only client-side filters —
  /// e.g. the Store screen's "Special offers"/"Best sellers" "See all"
  /// links use these so the Shop screen opens already narrowed to that
  /// section's products, instead of the full store catalogue.
  final bool offersOnly;
  final bool bestSellersOnly;
  const ShopFilter({this.pharmacy, this.category, this.brand, this.shopId, this.offersOnly = false, this.bestSellersOnly = false});
}

class ShopViewModel extends ChangeNotifier {
  final CatalogRepository _repo = CatalogRepository.instance;
  final CatalogService _service = CatalogService.instance;

  bool isLoading = true;
  String? error;
  List<Product> _fetched = [];
  int _page = 1;
  int _totalPages = 1;
  bool isLoadingMore = false;

  /// Whether another page exists beyond what's already loaded — drives the
  /// infinite-scroll trigger and the "Loading more…" footer.
  bool get hasMore => _page < _totalPages;

  String? pharmacy;
  int? shopId; // store filter -> GET /app/products?shop=<id>
  int? userId; // so wishlist_status/cart_status reflect this person, not a default
  String? category;
  /// Numeric id of [category] — this, not the name, is what the API
  /// actually filters on (confirmed with backend: `category` as a string
  /// doesn't reliably match). Set alongside [category] whenever the
  /// selection comes from the real tree ([selectParentCategory]/
  /// [selectSubCategory]) — and also backfilled by [_resolveSelectedCategory]
  /// for the name-only deep links (`ShopFilter.category` from store/
  /// pharmacy/brand screens), so those filter correctly server-side too
  /// once the real tree is loaded, not just the older name-string fallback.
  int? categoryId;
  /// Which top-level category is "expanded" in the Shop screen's first
  /// chip row — drives which subcategories show in the second row. Purely
  /// a UI concern; [category]/[categoryId] (the actual filter sent to the
  /// API) can independently be this parent's or one of its children's.
  HomeCategory? selectedParent;
  String? concern;
  String query = '';
  String view = 'grid'; // grid | list
  String sort = 'pop'; // pop | low | high | rated
  List<String> brands = [];
  bool inStock = false;
  bool offersOnly = false;
  /// Client-side "show only this store's best sellers" filter — same idea
  /// as [offersOnly]. There's no server support for either; both filter
  /// against whatever's already been fetched (see [results]).
  bool bestSellersOnly = false;

  /// Maps the UI sort keys (pop/low/high/rated) to the API's expected values
  /// (pop/plow/phigh). 'rated' has no server equivalent, so it's fetched as
  /// 'pop' and sorted client-side by rating in [results].
  String get _apiSort {
    switch (sort) {
      case 'low':
        return 'plow';
      case 'high':
        return 'phigh';
      case 'rated':
        return 'pop';
      default:
        return 'pop';
    }
  }

  ShopViewModel({ShopFilter? initial, this.userId}) {
    if (initial != null) {
      pharmacy = initial.pharmacy;
      shopId = initial.shopId;
      category = initial.category;
      if (initial.brand != null) brands = [initial.brand!];
      offersOnly = initial.offersOnly;
      bestSellersOnly = initial.bestSellersOnly;
    }
    // A caller (Store screen's category tile, a deep link, etc.) only ever
    // hands us a category *name* — resolve it against the chip list so the
    // matching chip highlights, not just the underlying filter. Without
    // this, `category`/products were filtered correctly but no chip ever
    // showed as selected, since the chip row checks `selectedParent`/
    // `categoryId`, not the plain name string.
    _resolveSelectedCategory();
    if (_repo.liveProductCategories.isEmpty) _loadCategories();
    load();
  }

  /// Fetches the real category tree (see [CatalogRepository.liveProductCategories])
  /// if nothing has cached it yet — e.g. the person opened Shop directly
  /// without visiting Home first. Best-effort: on failure the screen just
  /// keeps using the static placeholder list.
  Future<void> _loadCategories() async {
    try {
      final tree = await _service.categories();
      _repo.cacheProductCategories(tree);
      // Re-resolve now that the real tree (with real ids) is in — if the
      // constructor only had the id:0 placeholder list to match against,
      // this upgrades `selectedParent`/`categoryId` to the real entry.
      _resolveSelectedCategory();
      notifyListeners();
    } catch (_) {
      // Ignore — falls back to the static placeholder list.
    }
  }

  /// Finds the chip-list entry matching [category]'s name (case-insensitive)
  /// and sets [selectedParent]/[categoryId] to it, so the top chip row
  /// highlights correctly for a category that arrived as a plain string
  /// rather than through [selectParentCategory]. No-op if [category] is
  /// null or nothing matches.
  void _resolveSelectedCategory() {
    if (category == null) return;
    for (final c in categories) {
      if (c.name.toLowerCase() == category!.toLowerCase()) {
        selectedParent = c;
        categoryId = c.id == 0 ? categoryId : c.id;
        return;
      }
    }
  }

  /// Real, server-driven categories when available; falls back to the
  /// static placeholder list (see [CatalogRepository.productCategories])
  /// only until the real list has loaded.
  List<HomeCategory> get categories {
    if (_repo.liveProductCategories.isNotEmpty) return _repo.liveProductCategories;
    return CatalogRepository.productCategories
        .where((c) => c['cat'] != 'Health')
        .map((c) => HomeCategory(id: 0, name: c['cat']!, nameAr: c['cat']!, slug: c['cat']!, iconUrl: ''))
        .toList();
  }

  /// `pharmacy`/`concern`/`brand`/`offersOnly`/`bestSellersOnly` aren't
  /// filtered server-side — they're applied client-side against whatever's
  /// been fetched so far (see [loadMore] for how more gets appended page by
  /// page), same as `sort=rated` which the API also doesn't support.
  /// `brand` used to be sent as a server query param, but the API's
  /// exact-match behavior on real brand names (spaces, dashes, mixed case)
  /// was unreliable and could come back with zero results — filtering
  /// client-side against the already-loaded pages is more robust.
  Future<void> load() async {
    isLoading = true;
    error = null;
    _page = 1;
    notifyListeners();
    try {
      final page = await _service.products(
        query: query,
        category: category,
        categoryId: categoryId,
        sort: _apiSort, // map UI sort -> API sort (plow/phigh/pop)
        inStock: inStock,
        page: 1,
        perPage: 100,
        shop: shopId, // when set, the server returns only this store's items
        userId: userId,
      );
      _fetched = page.items;
      _totalPages = page.pages;
      _repo.cacheProducts(_fetched);
    } catch (e) {
      error = describeError(e);
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// Fetches the next page and appends it — this is what was missing
  /// before: [load] always requested `page: 1` and nothing after it ever
  /// got fetched, so anything past the first 100 matches was permanently
  /// unreachable. Called from the Shop screen's scroll listener once the
  /// person nears the bottom of the (already client-filtered) list.
  Future<void> loadMore() async {
    if (isLoadingMore || isLoading || !hasMore) return;
    isLoadingMore = true;
    notifyListeners();
    try {
      final next = _page + 1;
      final page = await _service.products(
        query: query,
        category: category,
        categoryId: categoryId,
        sort: _apiSort,
        inStock: inStock,
        page: next,
        perPage: 100,
        shop: shopId,
        userId: userId,
      );
      _fetched = [..._fetched, ...page.items];
      _page = next;
      _totalPages = page.pages;
      _repo.cacheProducts(page.items);
    } catch (_) {
      // Silent — keep showing whatever's already loaded; the person can
      // just scroll again to retry.
    } finally {
      isLoadingMore = false;
      notifyListeners();
    }
  }

  /// Top always-visible category chip row — matches HTML's `setCat()`:
  /// plain set, never toggles off by tapping the same chip again. Also
  /// expands this category's children into the second row so the person
  /// can narrow further (null clears both — the "All" chip).
  void selectParentCategory(HomeCategory? c) {
    selectedParent = c;
    category = c?.name;
    categoryId = c?.id;
    load();
  }

  /// Second row's subcategory chips — narrows the filter to this specific
  /// child without collapsing the row (so the person can flip between
  /// siblings under the same parent).
  void selectSubCategory(HomeCategory c) {
    category = c.name;
    categoryId = c.id;
    load();
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

  void toggleBestSellersOnly() {
    bestSellersOnly = !bestSellersOnly;
    notifyListeners();
  }

  void clearFilters() {
    brands = [];
    inStock = false;
    offersOnly = false;
    bestSellersOnly = false;
    pharmacy = null;
    category = null;
    categoryId = null;
    selectedParent = null;
    load();
  }

  void clearPharmacy() {
    pharmacy = null;
    notifyListeners();
  }

  bool get hasActiveFilters => brands.isNotEmpty || inStock || offersOnly || bestSellersOnly || category != null || pharmacy != null;

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
    // When a store id is set the server already scoped the page to that shop,
    // so don't re-filter by seller name — the store's real seller names on
    // the page may not exactly match the `pharmacy` display string passed
    // in, which would wrongly empty the list for no reason.
    if (pharmacy != null && shopId == null) list = list.where((p) => p.sellers.any((s) => s.name == pharmacy)).toList();
    if (concern != null) list = list.where((p) => p.concern == concern).toList();
    if (brands.isNotEmpty) list = list.where((p) => brands.contains(p.brand)).toList();
    if (offersOnly) list = list.where((p) => p.isOffer).toList();
    if (bestSellersOnly) list = list.where((p) => p.isBestSeller).toList();
    if (sort == 'rated') list.sort((a, b) => b.rating.compareTo(a.rating));
    return list;
  }
}
