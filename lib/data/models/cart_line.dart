/// A single cart line. Mirrors the JS `CART[key] = {id, seller, price, was, qty}`
/// shape. `key` is `"<productId>_<seller>"` for shop items or `"<rxId>#<idx>"`
/// for prescription-cart items (see [rxId]/[nameOverride]).
class CartLine {
  final String key;
  final int? productId; // null for RX-only lines that aren't a catalog product
  /// The *seller's* product id from the PDP `sellers[]` — what must be sent
  /// as `items[].id` when placing the order via the API. Null for local/mock
  /// sellers that don't carry a real backend id yet.
  final int? apiProductId;
  final String seller;
  final double price;
  final double? was;
  int qty;
  final String? rxId; // set when this line came from a prescription
  final String? nameOverride; // RX item display name when productId is null
  final String? nameOverrideAr;
  final String? emojiOverride;
  /// The server's own id for this cart line — confirmed needed by
  /// `POST /app/cart/remove` (`cart_id`, not `product_id`). Null until
  /// either a successful `/app/cart/add` response supplies one or a
  /// `/app/cart` sync does — both response shapes are unconfirmed, so this
  /// stays best-effort (see CartService).
  int? serverCartId;

  CartLine({
    required this.key,
    this.productId,
    this.apiProductId,
    required this.seller,
    required this.price,
    this.was,
    this.qty = 1,
    this.rxId,
    this.nameOverride,
    this.nameOverrideAr,
    this.emojiOverride,
    this.serverCartId,
  });

  double get lineTotalBeforeDiscount => (was ?? price) * qty;
}
