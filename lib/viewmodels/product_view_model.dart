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
  final int? userId; // so wishlist_status/cart_status in the response reflect this person, not a default
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

  ProductViewModel({required this.productId, String? lockedToSeller, this.userId}) {
    _selectedSellerName = lockedToSeller;
    // Show whatever's cached immediately (from the Shop/Home rail the person
    // tapped), then refresh from the PDP endpoint for the full seller
    // price-comparison list.
    product = _repo.findProduct(productId) ??
        Product(id: productId, nameEn: '', nameAr: '', brand: '', category: '', concern: '', form: '', scientificName: '', emoji: '💊', rating: 0, reviews: 0, sellers: const []);
    load();
  }

  Future<void> load() async {
    final identifier = product.pdpIdentifier;
    isLoading = product.sellers.isEmpty; // only block the UI if we have nothing to show yet
    error = null;
    notifyListeners();
    try {
      final fresh = await _service.product(identifier, userId: userId);
      product = fresh;
      _repo.cacheProducts([fresh]);
    } catch (e) {
      error = describeError(e);
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// Initial selection priority: the pharmacy already in context
  /// (`lockedToSeller`, i.e. `SHOP.pharma`) first, else the cheapest in-stock
  /// seller, else just the first seller. Once the person taps a different
  /// pharmacy in the PDP's seller list, [selectSeller] overrides this.
  Seller get selectedSeller {
    if (product.sellers.isEmpty) {
      return const Seller(name: '', price: 0, eta: '', stock: false);
    }
    if (_selectedSellerName != null) {
      return product.sellerByName(_selectedSellerName!);
    }
    return product.defaultSeller;
  }

  /// All sellers for this product, cheapest in-stock first — this is the
  /// price-comparison list shown on the PDP so the person can choose which
  /// pharmacy to buy from. The chosen seller's `product_id` is what goes into
  /// the cart/order.
  List<Seller> get sellers {
    final list = List<Seller>.from(product.sellers);
    list.sort((a, b) {
      if (a.stock != b.stock) return a.stock ? -1 : 1; // in-stock first
      return a.price.compareTo(b.price); // then cheapest first
    });
    return list;
  }

  /// Selects which pharmacy the person is buying from.
  void selectSeller(String name) {
    _selectedSellerName = name;
    notifyListeners();
  }
}
