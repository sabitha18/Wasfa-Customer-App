import '../../core/network/api_client.dart';
import '../../core/network/api_config.dart';
import '../../core/network/api_exception.dart';
import '../models/area_catalog.dart';
import '../models/coupon_result.dart';
import '../models/home_feed.dart';
import '../models/pharmacy_store.dart';
import '../models/product.dart';

/// Product listing/detail, home feed, areas, coupon check. `products()` and
/// `product()` take an optional `user_id` — without it, the backend has no
/// user to compute `wishlist_status`/`cart_status` against, so those come
/// back false/default regardless of the real state. Every other endpoint
/// here is genuinely anonymous.
class CatalogService {
  CatalogService._();
  static final CatalogService instance = CatalogService._();
  final ApiClient _client = ApiClient.instance;

  Future<HomeFeed> home() async {
    final res = await _client.get(ApiConfig.home);
    return HomeFeed.fromJson(res as Map<String, dynamic>);
  }

  /// Full nested category tree — `GET /app/categories`. Response is a bare
  /// JSON array (falls back to `{categories:[]}`/`{data:[]}` just in case
  /// that ever changes) of [HomeCategory], each with its `children[]`
  /// nested recursively.
  Future<List<HomeCategory>> categories() async {
    final res = await _client.get(ApiConfig.categories);
    final list = res is List ? res : (res is Map ? (res['categories'] ?? res['data'] ?? const []) : const []);
    return (list as List).map((e) => HomeCategory.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Product listing (PLP). All filters optional, matching the query params
  /// documented on the "Product listing" request.
  ///
  /// `category` filtering expects the category's numeric **id** (from the
  /// real `/app/categories` tree, confirmed with backend) — a name string
  /// doesn't reliably match. Pass [categoryId] wherever a [HomeCategory]
  /// is available; [category] (name) is kept only as a fallback for the
  /// handful of call sites that only have a plain string (store/pharmacy/
  /// brand screens deep-linking into Shop) and haven't been wired to the
  /// real tree yet — those still won't filter correctly server-side until
  /// they are.
  Future<ProductPage> products({
    String query = '',
    String? category,
    int? categoryId,
    String? brand,
    String sort = 'pop',
    bool inStock = false,
    int page = 1,
    int perPage = 24,
    int? shop, // filter to a single store's catalogue (store id = shop user_id)
    int? userId, // needed so wishlist_status/cart_status come back correct per-person, not just defaulted
  }) async {
    final res = await _client.get(ApiConfig.products, query: {
      'q': query,
      'category': categoryId ?? category,
      'brand': brand,
      'sort': sort,
      if (inStock) 'in_stock': 1,
      if (shop != null) 'shop': shop,
      if (userId != null) 'user_id': userId,
      'page': page,
      'per_page': perPage,
    });
    return ProductPage.fromJson(res as Map<String, dynamic>);
  }

  Future<Product> product(String sku, {int? userId}) async {
    final res = await _client.get(ApiConfig.product(sku), query: userId != null ? {'user_id': userId} : null);
    return Product.fromJson(res as Map<String, dynamic>);
  }

  /// Store marketplace list (home "Nearest / Browse all stores").
  ///
  /// ✅ Confirmed live: `GET /app/stores` returns `{ stores: [...] }`. Kept
  /// the `data`/`items` fallbacks and try/catch at the call site (see
  /// [HomeViewModel.load]) in case the shape ever changes or the request
  /// fails transiently.
  /// [lat]/[lng] confirmed live. [governorateId]/[areaId] are an
  /// educated-but-UNCONFIRMED addition: a saved [Address] has no
  /// coordinates at all, but does have real governorate_id/area_id — the
  /// same geographic key confirmed elsewhere in this app (`/orders`,
  /// address save). Sending both here so the store list can reflect
  /// whichever delivery address is actually selected, not just the
  /// device's raw GPS position, on the assumption this endpoint recognizes
  /// them the same way. If it doesn't, these are simply ignored — no harm
  /// either way — but confirm with the backend team whether it does.
  Future<List<PharmacyStore>> stores({double? lat, double? lng, int? governorateId, int? areaId}) async {
    final res = await _client.get(ApiConfig.stores, query: {
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
      if (governorateId != null) 'governorate_id': governorateId,
      if (areaId != null) 'area_id': areaId,
    });
    final list = (res is Map ? res['stores'] ?? res['data'] ?? res['items'] : null) ?? (res is List ? res : const []);
    return (list as List).map((e) => PharmacyStore.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<AreaCatalog> areas() async {
    final res = await _client.get(ApiConfig.areas);
    return AreaCatalog.fromJson(res as Map<String, dynamic>);
  }

  Future<CouponResult> checkCoupon({required String code, required double subtotal}) async {
    final res = await withFallbackMessage(
          () => _client.get(ApiConfig.coupon, query: {
        'code': code,
        'subtotal': subtotal.toStringAsFixed(3),
      }),
      'That coupon code doesn\'t seem to work.',
    );
    return CouponResult.fromJson(res as Map<String, dynamic>, requestedCode: code);
  }

  /// `GET /app/settings` — PROPOSED, not confirmed live yet (see
  /// [ApiConfig.appSettings]). Expected shape is a guess:
  /// `{ payment_methods: ["knet","cod",...] }` (or `enabled_payment_methods`
  /// as a fallback key). Returns an empty list on any failure/missing key —
  /// [AppSettingsState] treats that as "keep all methods enabled" rather
  /// than hiding everything.
  Future<List<String>> paymentMethods() async {
    final res = await _client.get(ApiConfig.appSettings);
    final list = (res is Map ? res['payment_methods'] ?? res['enabled_payment_methods'] : null);
    if (list is List) return list.map((e) => e.toString()).toList();
    return const [];
  }
}

/// `GET /app/products` → `{ total, page, per_page, pages, items[] }`.
class ProductPage {
  final int total;
  final int page;
  final int perPage;
  final int pages;
  final List<Product> items;

  const ProductPage({required this.total, required this.page, required this.perPage, required this.pages, required this.items});

  static const empty = ProductPage(total: 0, page: 1, perPage: 24, pages: 0, items: []);

  factory ProductPage.fromJson(Map<String, dynamic> json) => ProductPage(
    total: (json['total'] as num?)?.toInt() ?? 0,
    page: (json['page'] as num?)?.toInt() ?? 1,
    perPage: (json['per_page'] as num?)?.toInt() ?? 24,
    pages: (json['pages'] as num?)?.toInt() ?? 1,
    items: ((json['items'] as List?) ?? const [])
        .map((e) => Product.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}
