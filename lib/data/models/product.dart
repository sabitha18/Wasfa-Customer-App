import '../../core/utils/json_utils.dart';
import 'seller.dart';

class Product {
  final int id;
  /// Canonical `apix_sku` — required for the PDP endpoint
  /// (`GET /app/product/{sku}`) and useful as a stable key across catalog
  /// refreshes even if the numeric `id` were ever to change.
  final String sku;
  final String nameEn;
  final String nameAr;
  final String brand;
  final String category; // Medicine, Skin care, Vitamins, Mom & baby, ...
  final String concern; // pain, skin, energy, hair, baby, oral
  final String form; // "24 tablets"
  final String scientificName;
  final String emoji; // placeholder "photo" (emoji) — swap for real asset later
  final String? imageUrl; // real product photo, once the API returns one
  /// `seller_count` from the PLP — the listing endpoint only ever gives us
  /// a single synthesized [Seller] (see [Product.fromJson]), so this is what
  /// the "🏪 N pharmacies" UI should show instead of `sellers.length`. Null
  /// once a full PDP fetch has replaced [sellers] with the real list.
  final int? apiSellerCount;
  final double rating;
  final int reviews;
  final List<String> flags; // offer, best, new
  final String? tag; // "1+1"
  final List<Seller> sellers;

  const Product({
    required this.id,
    this.sku = '',
    required this.nameEn,
    required this.nameAr,
    required this.brand,
    required this.category,
    required this.concern,
    required this.form,
    required this.scientificName,
    required this.emoji,
    this.imageUrl,
    this.apiSellerCount,
    required this.rating,
    required this.reviews,
    this.flags = const [],
    this.tag,
    required this.sellers,
  });

  String name(bool arabic) => arabic ? nameAr : nameEn;

  bool get isOffer => flags.contains('offer') || sellers.any((s) => s.was != null);
  bool get isBestSeller => flags.contains('best');
  bool get isNew => flags.contains('new');
  bool get isBogo => tag == '1+1';

  /// Lowest in-stock price across sellers (falls back to any seller).
  double get bestPrice {
    if (sellers.isEmpty) return 0;
    final inStock = sellers.where((s) => s.stock).toList();
    final pool = inStock.isNotEmpty ? inStock : sellers;
    return pool.map((s) => s.price).reduce((a, b) => a < b ? a : b);
  }

  /// Strike-through price associated with the best-price seller, if any.
  double? get bestWasPrice {
    if (sellers.isEmpty) return null;
    final s = sellers.firstWhere(
      (s) => s.price == bestPrice,
      orElse: () => sellers.first,
    );
    return s.was;
  }

  Seller sellerByName(String name) =>
      sellers.firstWhere((s) => s.name == name, orElse: () => sellers.first);

  /// Cheapest in-stock seller, matching JS `selSeller()` default behaviour.
  Seller get defaultSeller {
    final inStock = sellers.where((s) => s.stock).toList()
      ..sort((a, b) => a.price.compareTo(b.price));
    return inStock.isNotEmpty ? inStock.first : sellers.first;
  }

  int get sellerCount => apiSellerCount ?? sellers.length;

  static const Map<String, String> _categoryEmoji = {
    'Medicine': '💊',
    'Hair care': '💇',
    'Skin care': '🧴',
    'Vitamins': '🟡',
    'Mom & baby': '🍼',
    'Personal care': '🪥',
    'Health': '❤️',
  };

  /// PLP item (grouped by `apix_sku`): `{ apix_sku, name, name_ar, brand,
  /// category, ... }`, optionally without a full `sellers[]` (that's added
  /// on the PDP). When there's no sellers array, a single seller is
  /// synthesized from the item's own price/was/stock fields so every other
  /// getter (bestPrice, isOffer, etc.) keeps working unchanged.
  ///
  /// NOTE: field names below are our best guess from the collection's prose
  /// description ("grouped by apix_sku") — confirm against a real `/app/
  /// products` response and trim the candidate-key lists in json_utils calls
  /// if the backend uses different names.
  factory Product.fromJson(Map<String, dynamic> json) {
    final sku = asString(json, const ['apix_sku', 'sku', 'id']);
    final category = asString(json, const ['category']);
    final sellersJson = asList(json, const ['sellers']);
    final sellers = sellersJson.isNotEmpty
        ? sellersJson.map((e) => Seller.fromJson(e as Map<String, dynamic>)).toList()
        : <Seller>[
            if (json.containsKey('price'))
              Seller(
                productId: asIntOrNull(json, const ['product_id']),
                name: asString(json, const ['seller', 'pharmacy', 'pharmacy_name'], fallback: 'WASFA'),
                price: asDouble(json, const ['price']),
                was: asDoubleOrNull(json, const [
                  'was', 'old_price', 'compare_at_price', 'compare_price', 'original_price', 'list_price', 'mrp', 'regular_price', 'strike_price',
                ]),
                eta: asString(json, const ['eta', 'delivery_eta']),
                stock: asBool(json, const ['in_stock', 'stock'], fallback: true),
              ),
          ];
    return Product(
      id: asInt(json, const ['id'], fallback: int.tryParse(sku) ?? sku.hashCode),
      sku: sku,
      nameEn: asString(json, const ['name_en', 'name']),
      nameAr: asString(json, const ['name_ar', 'nameAr']),
      brand: asString(json, const ['brand']),
      category: category,
      concern: asString(json, const ['concern']),
      form: asString(json, const ['form', 'pack_size']),
      scientificName: asString(json, const ['scientific_name', 'generic_name']),
      emoji: asStringOrNull(json, const ['emoji']) ?? _categoryEmoji[category] ?? '💊',
      imageUrl: asStringOrNull(json, const ['image', 'image_url', 'photo']),
      // Only trust `seller_count` as a display hint when this came from the
      // PLP (no full `sellers[]` array) — a PDP response's own sellers list
      // is the real, authoritative count.
      apiSellerCount: sellersJson.isEmpty ? asIntOrNull(json, const ['seller_count']) : null,
      rating: asDouble(json, const ['rating', 'avg_rating']),
      reviews: asInt(json, const ['reviews', 'reviews_count']),
      flags: asList(json, const ['flags']).map((e) => e.toString()).toList(),
      tag: asStringOrNull(json, const ['tag', 'promo_tag']),
      sellers: sellers,
    );
  }
}
