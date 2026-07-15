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

  /// Live store marketplace from `GET /app/stores`. Starts empty and stays
  /// empty until that endpoint is implemented server-side — the Home screen
  /// falls back to its empty state rather than showing invented stores.
  List<PharmacyStore> stores = const [];

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
    }
    // Stores are fetched separately so a store-list failure (or the endpoint
    // simply not existing yet) never blanks out the home feed. On any error
    // we keep the list empty — the screen then shows its empty state instead
    // of inventing data.
    try {
      stores = await _service.stores();
    } catch (_) {
      stores = const [];
    }
    isLoading = false;
    notifyListeners();
  }

  void toggleFilter(String key) {
    storeFilters[key] = !(storeFilters[key] ?? false);
    notifyListeners();
  }

  /// Matches the HTML's `nearestStoresHTML()`: pharmacy-category stores,
  /// sorted by the low end of their ETA range, top 4. Sourced from the live
  /// [stores] list (empty until `/app/stores` ships server-side).
  List<PharmacyStore> get nearestStores {
    int etaLow(PharmacyStore s) => int.tryParse(s.eta.split('-').first) ?? 99;
    final list = stores.where((s) => s.category == 'pharmacy').toList()
      ..sort((a, b) => etaLow(a).compareTo(etaLow(b)));
    return list.take(4).toList();
  }

  /// Store marketplace list from the live [stores] fetch. Empty until the
  /// `/app/stores` endpoint is implemented server-side.
  List<PharmacyStore> get filteredStores {
    var list = List<PharmacyStore>.from(stores);
    if (storeCategory != 'all') list = list.where((s) => s.category == storeCategory).toList();
    if (storeFilters['offers'] == true) list = list.where((s) => s.offer != null).toList();
    if (storeFilters['under30'] == true) list = list.where((s) => s.fast).toList();
    if (storeFilters['free'] == true) list = list.where((s) => s.freeDelivery).toList();
    if (storeFilters['pro'] == true) list = list.where((s) => s.pro).toList();
    return list;
  }
}
