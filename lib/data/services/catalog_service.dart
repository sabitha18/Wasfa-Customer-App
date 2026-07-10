import '../../core/network/api_client.dart';
import '../../core/network/api_config.dart';
import '../../core/network/api_exception.dart';
import '../models/area_catalog.dart';
import '../models/coupon_result.dart';
import '../models/home_feed.dart';
import '../models/product.dart';

/// Anonymous browsing endpoints — home feed, product listing/detail, areas,
/// coupon check. None of these require `user_id`.
class CatalogService {
  CatalogService._();
  static final CatalogService instance = CatalogService._();
  final ApiClient _client = ApiClient.instance;

  Future<HomeFeed> home() async {
    final res = await _client.get(ApiConfig.home);
    return HomeFeed.fromJson(res as Map<String, dynamic>);
  }

  /// Product listing (PLP). All filters optional, matching the query params
  /// documented on the "Product listing" request.
  Future<ProductPage> products({
    String query = '',
    String? category,
    String? brand,
    String sort = 'pop',
    bool inStock = false,
    int page = 1,
    int perPage = 24,
  }) async {
    final res = await _client.get(ApiConfig.products, query: {
      'q': query,
      'category': category,
      'brand': brand,
      'sort': sort,
      if (inStock) 'in_stock': 1,
      'page': page,
      'per_page': perPage,
    });
    return ProductPage.fromJson(res as Map<String, dynamic>);
  }

  Future<Product> product(String sku) async {
    final res = await _client.get(ApiConfig.product(sku));
    return Product.fromJson(res as Map<String, dynamic>);
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
