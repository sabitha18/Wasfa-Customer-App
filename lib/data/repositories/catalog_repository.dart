import '../models/product.dart';
import '../models/pharmacy_store.dart';
import '../models/prescription.dart';
import '../models/home_feed.dart';

/// Reference/static catalog data (categories, concerns, delivery slots) plus
/// a synchronous in-memory *cache* of products/prescriptions.
///
/// Product/prescription data comes entirely from the API (see
/// CatalogService/AccountService + the ViewModels that call them) — but a
/// few places in the app (CartState's BOGO math, deep-link "open product by
/// id" flows) need to look a product up synchronously without awaiting a
/// network call. Whenever a ViewModel fetches products from the API, it
/// calls [cacheProducts] so those lookups keep working. `products` and
/// `prescriptions` below start empty and are populated only from real
/// fetches — no mock/dummy data ships in the app.
class CatalogRepository {
  CatalogRepository._();
  static final CatalogRepository instance = CatalogRepository._();

  /// Merges freshly-fetched products into the synchronous lookup cache.
  void cacheProducts(List<Product> fetched) {
    for (final p in fetched) {
      final idx = products.indexWhere((existing) => existing.id == p.id);
      if (idx >= 0) {
        products[idx] = p;
      } else {
        products.add(p);
      }
    }
  }

  /// Full-list replace — use this ONLY when [fetched] is the complete,
  /// authoritative list (e.g. the initial `GET /acct/rx` load). Wipes
  /// everything else in the cache first.
  void cachePrescriptions(List<Prescription> fetched) {
    prescriptions
      ..clear()
      ..addAll(fetched);
  }

  /// Updates (or adds) ONE prescription in place, leaving every other
  /// cached prescription untouched. Use this after refreshing a single
  /// prescription's data (e.g. after "Get Prices" succeeds) — NOT
  /// [cachePrescriptions], which was being called with a single-item list
  /// here before and was wiping the entire cache down to just that one
  /// prescription every time, since it always does a full clear() first.
  /// That's what caused `My Rx`'s list to suddenly shrink mid-layout
  /// (`RangeError: Only valid value is 0: 3`) the instant someone tapped
  /// "Get Prices" on any card — the shared `prescriptions` list list is
  /// read directly (not copied) by `MyRxScreen`, so it shrank out from
  /// under the ListView while it was still trying to build the other,
  /// now-gone rows.
  void upsertPrescription(Prescription fresh) {
    final idx = prescriptions.indexWhere((r) => r.id == fresh.id);
    if (idx >= 0) {
      prescriptions[idx] = fresh;
    } else {
      prescriptions.add(fresh);
    }
  }

  /// Real product-category taxonomy, sourced from `GET /app/home`'s
  /// `cats[]` (see [HomeCategory]) — populated by [HomeViewModel.load] and
  /// consumed by the Shop screen's category chips/filter. This is
  /// deliberately kept separate from the static [productCategories] list
  /// below: that list is invented placeholder copy (Medicine, Hair care,
  /// ...) that was never confirmed against the real backend taxonomy, so
  /// sending it as the `category` query param on `GET /app/products` was
  /// silently matching nothing. Once this cache has real entries, the Shop
  /// screen should prefer it over the static list.
  List<HomeCategory> liveProductCategories = [];

  void cacheProductCategories(List<HomeCategory> cats) {
    if (cats.isEmpty) return;
    liveProductCategories = cats;
  }

  static const categories = <StoreCategory>[
    StoreCategory('all', '🏬', 'All stores', 'كل المتاجر'),
    StoreCategory('pharmacy', '💊', 'Pharmacy', 'صيدلية'),
    StoreCategory('beauty', '💄', 'Beauty', 'تجميل'),
    StoreCategory('eyecare', '👁️', 'Eyecare', 'العناية بالعين'),
    StoreCategory('nutrition', '🥤', 'Nutrition', 'تغذية'),
  ];

  static const productCategories = <Map<String, String>>[
    {'emoji': '💊', 'cat': 'Medicine'},
    {'emoji': '💇', 'cat': 'Hair care'},
    {'emoji': '🧴', 'cat': 'Skin care'},
    {'emoji': '🟡', 'cat': 'Vitamins'},
    {'emoji': '🍼', 'cat': 'Mom & baby'},
    {'emoji': '🪥', 'cat': 'Personal care'},
    {'emoji': '❤️', 'cat': 'Health'},
  ];

  static const concerns = <Map<String, String>>[
    {'k': 'pain', 'en': 'Pain relief', 'ar': 'تسكين الألم'},
    {'k': 'skin', 'en': 'Skin', 'ar': 'البشرة'},
    {'k': 'energy', 'en': 'Energy', 'ar': 'الطاقة'},
    {'k': 'hair', 'en': 'Hair', 'ar': 'الشعر'},
    {'k': 'baby', 'en': 'Baby', 'ar': 'الطفل'},
    {'k': 'oral', 'en': 'Oral', 'ar': 'الفم'},
  ];

  static const brands = <String>[
    'Panadol', 'CeraVe', 'Centrum', 'Nordic', 'Vichy', 'Eucerin', 'Sebamed', 'Nivea',
  ];

  /// Mutable cache — populated via [cacheProducts] from real `/app/products`
  /// / `/app/product/{sku}` responses. Starts empty; no mock/dummy data.
  final List<Product> products = [];

  static const deliverySlots = <List<String>>[
    ['8:00 AM', '12:00 PM'], ['12:00 PM', '4:00 PM'], ['4:00 PM', '8:00 PM'], ['8:00 PM', '12:00 AM'],
  ];

  Product? findProduct(int id) {
    try {
      return products.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  List<Product> productsByPharmacy(String seller) =>
      products.where((p) => p.sellers.any((s) => s.name == seller)).toList();

  /// {pharmacyName: {count, minPrice}} — mirrors JS `pharmList()`.
  List<Map<String, dynamic>> pharmacyList() {
    final map = <String, Map<String, dynamic>>{};
    for (final p in products) {
      for (final s in p.sellers) {
        final entry = map.putIfAbsent(s.name, () => {'name': s.name, 'n': 0, 'min': double.infinity});
        entry['n'] = (entry['n'] as int) + 1;
        if (s.price < (entry['min'] as double)) entry['min'] = s.price;
      }
    }
    return map.values.toList();
  }

  /// Mutable cache — populated via [cachePrescriptions] from the real
  /// `GET /acct/rx` response. Starts empty; no mock/dummy data.
  final List<Prescription> prescriptions = [];

  Prescription? findPrescription(String id) {
    try {
      return prescriptions.firstWhere((r) => r.id == id);
    } catch (_) {
      return null;
    }
  }
}
