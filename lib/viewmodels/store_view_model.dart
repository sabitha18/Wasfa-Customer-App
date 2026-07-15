import 'package:flutter/foundation.dart';
import '../core/network/api_exception.dart';
import '../data/models/pharmacy_store.dart';
import '../data/models/product.dart';
import '../data/repositories/catalog_repository.dart';
import '../data/services/catalog_service.dart';

class StoreViewModel extends ChangeNotifier {
  final PharmacyStore store;
  final CatalogRepository _repo = CatalogRepository.instance;
  final CatalogService _service = CatalogService.instance;

  bool isLoading = false;
  String? error;
  List<Product>? _fetched;

  StoreViewModel(this.store) {
    // When the store carries a backend id, load its catalogue from the server
    // (`GET /app/products?shop=<id>`). Mock/local stores (no id) fall back to
    // the seller-name match against the shared product cache.
    if (store.id != null) _load();
  }

  Future<void> _load() async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      final page = await _service.products(shop: store.id, perPage: 100);
      _fetched = page.items;
      _repo.cacheProducts(page.items);
    } catch (e) {
      error = describeError(e);
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// Products in this store: the server-scoped fetch when we have a store id,
  /// otherwise the seller-name match against the shared cache (mock stores).
  List<Product> get products => _fetched ?? _repo.productsByPharmacy(store.seller);

  List<Product> get offers =>
      products.where((p) => p.isOffer || p.sellers.any((s) => s.name == store.seller && s.was != null)).toList();

  List<Product> get bestSellers => products.where((p) => p.isBestSeller).toList();

  List<Map<String, String>> get categoriesInStore => CatalogRepository.productCategories
      .where((c) => products.any((p) => p.category == c['cat']))
      .toList();

  List<String> get brandsInStore => products.map((p) => p.brand).toSet().toList();
}
