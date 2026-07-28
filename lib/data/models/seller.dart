import '../../core/utils/json_utils.dart';

class Seller {
  /// Backend's `product_id` for this seller's listing of the product —
  /// this is what must be sent as `items[].id` when placing an order
  /// (per the "Place order" endpoint notes: "items[].id = seller product_id
  /// from PDP sellers[]"). Null for mock/local-only sellers.
  final int? productId;
  final String name;
  final double price;
  final double? was; // strike-through / original price, null if no discount
  final String eta; // e.g. "45 min"
  final bool stock;

  const Seller({
    this.productId,
    required this.name,
    required this.price,
    this.was,
    required this.eta,
    required this.stock,
  });

  bool get hasDiscount => was != null && was! > price;
  int get discountPercent => hasDiscount ? (100 - (price / was! * 100)).round() : 0;

  /// From PDP `sellers[]`: `{ product_id, name, price, in_stock, qty }` —
  /// ✅ confirmed live (2026-07-24): the real field is `in_stock`, not
  /// `stock`. `qty` is kept only as a fallback for shapes that omit
  /// `in_stock` entirely.
  factory Seller.fromJson(Map<String, dynamic> json) => Seller(
        productId: asIntOrNull(json, const ['product_id', 'id']),
        name: asString(json, const ['name', 'seller', 'pharmacy', 'pharmacy_name']),
        price: asDouble(json, const ['price']),
        was: asDoubleOrNull(json, const [
          'was', 'old_price', 'compare_at_price', 'compare_price', 'original_price', 'list_price', 'mrp', 'regular_price', 'strike_price',
        ]),
        eta: asString(json, const ['eta', 'delivery_eta']),
        stock: (json.containsKey('in_stock') || json.containsKey('stock'))
            ? asBool(json, const ['in_stock', 'stock'])
            : asInt(json, const ['qty'], fallback: 1) > 0,
      );
}
