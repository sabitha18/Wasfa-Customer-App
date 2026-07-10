import 'package:flutter/foundation.dart';
import '../data/models/pharmacy_store.dart';
import '../data/models/product.dart';
import '../data/repositories/catalog_repository.dart';

class StoreViewModel extends ChangeNotifier {
  final PharmacyStore store;
  final CatalogRepository _repo = CatalogRepository.instance;

  StoreViewModel(this.store);

  List<Product> get products => _repo.productsByPharmacy(store.seller);

  List<Product> get offers =>
      products.where((p) => p.isOffer || p.sellers.any((s) => s.name == store.seller && s.was != null)).toList();

  List<Product> get bestSellers => products.where((p) => p.isBestSeller).toList();

  List<Map<String, String>> get categoriesInStore => CatalogRepository.productCategories
      .where((c) => products.any((p) => p.category == c['cat']))
      .toList();

  List<String> get brandsInStore => products.map((p) => p.brand).toSet().toList();
}
