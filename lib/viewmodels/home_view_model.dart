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

  /// Live store marketplace from `GET /app/stores` (confirmed live — see
  /// CatalogService.stores). Starts empty; populated on [load], falling
  /// back to empty on failure rather than showing invented stores.
  List<PharmacyStore> stores = const [];

  String storeCategory = 'all';
  final Map<String, bool> storeFilters = {
    'offers': false,
    'under30': false,
    'free': false,
    'pro': false,
  };

  HomeViewModel({double? lat, double? lng, int? governorateId, int? areaId}) {
    _lastLat = lat;
    _lastLng = lng;
    _lastGovId = governorateId;
    _lastAreaId = areaId;
    load(lat: lat, lng: lng, governorateId: governorateId, areaId: areaId);
  }

  double? _lastLat;
  double? _lastLng;
  int? _lastGovId;
  int? _lastAreaId;

  Future<void> load({double? lat, double? lng, int? governorateId, int? areaId}) async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      feed = await _service.home();
      _repo.cacheProducts([...feed.deals, ...feed.best, ...feed.recent]);
    } catch (e) {
      error = describeError(e);
    }
    // `/app/categories` is the real category tree (parents with nested
    // `children[]`) — prefer it over `/app/home`'s flat `cats[]`, which
    // has no hierarchy. Fetched separately, same reasoning as `stores`
    // below: a failure here shouldn't blank out the rest of the home feed.
    try {
      final tree = await _service.categories();
      _repo.cacheProductCategories(tree);
    } catch (_) {
      // Best-effort fallback so category chips still show *something* —
      // flat, no subcategories, until /app/categories succeeds.
      if (_repo.liveProductCategories.isEmpty) _repo.cacheProductCategories(feed.categories);
    }
    // Stores are fetched separately so a transient store-list failure never
    // blanks out the home feed. On any error we keep the list empty — the
    // screen then shows its empty state instead of inventing data.
    // ✅ Confirmed live: GET /app/stores?lat=..&lng=.. — the device's actual
    // current GPS position (there's no coordinate data on a saved address
    // at all — see Address's fields — so this is always the device's live
    // position regardless of which address is selected for delivery).
    try {
      stores = await _service.stores(lat: lat, lng: lng, governorateId: governorateId, areaId: areaId);
      _repo.cacheStores(stores);
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

  /// Re-fetches ONLY the store list (not the whole home feed/categories,
  /// which don't depend on location at all) when the effective location
  /// actually changed since the last fetch — either the device's raw GPS
  /// position, OR the selected delivery address's governorate/area (a
  /// saved address has no coordinates, but does have these — see
  /// CatalogService.stores' doc for why both get sent). No-ops if nothing
  /// relevant changed, so this is cheap to call opportunistically (e.g. on
  /// every Home rebuild) without spamming the API. Previously this only
  /// ever considered GPS position, so switching which saved delivery
  /// address was selected never refreshed the store list at all — the app
  /// bar's "Deliver to" label would change, but the stores shown
  /// underneath silently kept reflecting whatever was true at the moment
  /// this ViewModel first loaded.
  Future<void> refreshStoresIfLocationChanged(double? lat, double? lng, {int? governorateId, int? areaId}) async {
    if (lat == _lastLat && lng == _lastLng && governorateId == _lastGovId && areaId == _lastAreaId) return;
    _lastLat = lat;
    _lastLng = lng;
    _lastGovId = governorateId;
    _lastAreaId = areaId;
    try {
      stores = await _service.stores(lat: lat, lng: lng, governorateId: governorateId, areaId: areaId);
      _repo.cacheStores(stores);
      notifyListeners();
    } catch (_) {
      // Keep whatever store list is already showing rather than wiping it
      // out over a transient failure on this specific re-fetch.
    }
  }

  /// Matches the HTML's `nearestStoresHTML()`: pharmacy-category stores,
  /// sorted by the low end of their ETA range, top 4. Sourced from the live
  /// [stores] list.
  List<PharmacyStore> get nearestStores {
    int etaLow(PharmacyStore s) => int.tryParse(s.eta.split('-').first) ?? 99;
    final list = stores.where((s) => s.category == 'pharmacy').toList()
      ..sort((a, b) => etaLow(a).compareTo(etaLow(b)));
    return list.take(4).toList();
  }

  /// Store marketplace list from the live [stores] fetch.
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
