import 'package:flutter/foundation.dart';
import '../core/network/api_exception.dart';
import '../data/models/home_feed.dart';
import '../data/models/pharmacy_store.dart';
import '../data/repositories/catalog_repository.dart';
import '../data/services/catalog_service.dart';

class HomeViewModel extends ChangeNotifier {
  final CatalogRepository _repo = CatalogRepository.instance;
  final CatalogService _service = CatalogService.instance;

  bool isLoading = true;
  String? error;
  HomeFeed feed = HomeFeed.empty;

  String storeCategory = 'all';
  final Map<String, bool> storeFilters = {
    'offers': false,
    'under30': false,
    'free': false,
    'pro': false,
  };

  HomeViewModel() {
    load();
  }

  Future<void> load() async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      feed = await _service.home();
      _repo.cacheProducts([...feed.deals, ...feed.best, ...feed.recent]);
    } catch (e) {
      error = describeError(e);
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  void toggleFilter(String key) {
    storeFilters[key] = !(storeFilters[key] ?? false);
    notifyListeners();
  }

  /// Matches the HTML's `nearestStoresHTML()`: pharmacy-category stores,
  /// sorted by the low end of their ETA range, top 4. Still mock — same
  /// `/app/stores` limitation as [filteredStores].
  List<PharmacyStore> get nearestStores {
    int etaLow(PharmacyStore s) => int.tryParse(s.eta.split('-').first) ?? 99;
    final list = _repo.stores.where((s) => s.category == 'pharmacy').toList()
      ..sort((a, b) => etaLow(a).compareTo(etaLow(b)));
    return list.take(4).toList();
  }

  /// Store marketplace list — still mock; the `/app/stores` endpoint isn't
  /// implemented server-side yet (see CatalogRepository doc comment).
  List<PharmacyStore> get filteredStores {
    var list = List<PharmacyStore>.from(_repo.stores);
    if (storeCategory != 'all') list = list.where((s) => s.category == storeCategory).toList();
    if (storeFilters['offers'] == true) list = list.where((s) => s.offer != null).toList();
    if (storeFilters['under30'] == true) list = list.where((s) => s.fast).toList();
    if (storeFilters['free'] == true) list = list.where((s) => s.freeDelivery).toList();
    if (storeFilters['pro'] == true) list = list.where((s) => s.pro).toList();
    return list;
  }
}
