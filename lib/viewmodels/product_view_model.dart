import 'package:flutter/foundation.dart';
import '../core/network/api_exception.dart';
import '../data/models/product.dart';
import '../data/models/seller.dart';
import '../data/repositories/catalog_repository.dart';
import '../data/services/catalog_service.dart';

class ProductViewModel extends ChangeNotifier {
  final CatalogRepository _repo = CatalogRepository.instance;
  final CatalogService _service = CatalogService.instance;
  final int productId;
  /// Always true — matches the HTML's `openPDP()`, the only place that ever
  /// sets `PDP.locked`, and it always sets it to `true`. There is no code
  /// path in the source that ever shows a multi-seller "choose pharmacy"
  /// picker with radio buttons; every product page always shows a single
  /// locked "Sold by X" row. [lockedToSeller] still matters — it's how the
  /// *which* seller gets picked (matching `SHOP.pharma`, i.e. arriving from
  /// a specific pharmacy's storefront) — it just no longer controls whether
  /// a picker UI shows, because that UI is never shown.
  static const bool locked = true;
  String? _selectedSellerName;

  bool isLoading = true;
  String? error;
  late Product product;

  ProductViewModel({required this.productId, String? lockedToSeller}) {
    _selectedSellerName = lockedToSeller;
    // Show whatever's cached immediately (from the Shop/Home rail the person
    // tapped), then refresh from the PDP endpoint for the full seller
    // price-comparison list.
    product = _repo.findProduct(productId) ??
        Product(id: productId, nameEn: '', nameAr: '', brand: '', category: '', concern: '', form: '', scientificName: '', emoji: '💊', rating: 0, reviews: 0, sellers: const []);
    load();
  }

  Future<void> load() async {
    final sku = product.sku.isNotEmpty ? product.sku : productId.toString();
    isLoading = product.sellers.isEmpty; // only block the UI if we have nothing to show yet
    error = null;
    notifyListeners();
    try {
      final fresh = await _service.product(sku);
      product = fresh;
      _repo.cacheProducts([fresh]);
    } catch (e) {
      error = describeError(e);
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// Matches `openPDP()`'s priority exactly: the pharmacy already in
  /// context (`lockedToSeller`, i.e. `SHOP.pharma`) first, else the
  /// cheapest in-stock seller, else just the first seller.
  Seller get selectedSeller {
    if (product.sellers.isEmpty) {
      return const Seller(name: '', price: 0, eta: '', stock: false);
    }
    if (_selectedSellerName != null) {
      return product.sellerByName(_selectedSellerName!);
    }
    return product.defaultSeller;
  }
}
