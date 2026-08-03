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
  /// The image straight off `/app/cart`'s own `image` field (or the
  /// product's `imageUrl` when this line came from a local add/listing
  /// sync that already had the full Product). NOT resolved via
  /// `CatalogRepository.findProduct(productId)` — a server-synced line's
  /// `productId` is usually null (see [CartState.lineKey]'s doc on
  /// apiProductId vs productId), so that lookup silently found nothing
  /// and the cart/checkout/order-review thumbnail just came up blank.
  final String? imageOverride;
  /// The server's own id for this cart line — confirmed needed by
  /// `POST /app/cart/remove` (`cart_id`, not `product_id`). Null until
  /// either a successful `/app/cart/add` response supplies one or a
  /// `/app/cart` sync does — both response shapes are unconfirmed, so this
  /// stays best-effort (see CartService).
  int? serverCartId;
  /// Confirmed live on `/app/cart` per line (2026-07-29): the real BOGO
  /// state and math for this exact line, straight from the server — NOT
  /// a client-side guess. [freeQty]/[paidQty]/[bogoSaved] start out this
  /// way, from whatever the last full `/app/cart` sync said. They're
  /// mutable (not `final`) because [recomputeBogoLocally] has to update
  /// them the instant the person taps +/-: `/app/cart/update`'s own
  /// response doesn't come back with fresh free_qty/paid_qty, so without
  /// this the "🎁 ... free" line would keep showing whatever was true at
  /// the OLD quantity until the next full sync — e.g. drop from qty 3 to
  /// qty 1 and it would incorrectly keep showing "1 free" instead of
  /// disappearing.
  final bool bogoStatus;
  final String? bogoLabel;
  int? freeQty;
  int? paidQty;
  double? bogoSaved;
  /// Confirmed live (`in_stock`) across product/cart/order/rx responses
  /// (2026-07-29). Regular shop/cart lines can't normally go stale on this
  /// — the shop grid/PDP already refuse to add an out-of-stock seller in
  /// the first place (see ProductCard/product_screen.dart), so a line that
  /// made it into the cart was in stock at add time, and the far shorter
  /// shop-to-checkout window makes a change in between unlikely. Rx lines
  /// are the case this actually matters for: pricing/stock gets set by a
  /// pharmacist, possibly well after the item was first added, so it's
  /// genuinely plausible for a line to go stale between being added to the
  /// Rx cart and checkout. Captured at add time (rx_detail_screen.dart);
  /// there's no equivalent to the regular cart's [CartState.loadCartRemote]
  /// to refresh it from, so this is the best available freshness — see
  /// CartScreen's Rx tab (labels it) and checkout's Rx submission (excludes
  /// it) for where this is actually enforced.
  bool inStock;

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
    this.imageOverride,
    this.serverCartId,
    this.bogoStatus = false,
    this.bogoLabel,
    this.freeQty,
    this.paidQty,
    this.bogoSaved,
    this.inStock = true,
  });

  /// What the badge should actually say — the backend's own [bogoLabel]
  /// when present, falling back to a generic "Buy 1 Get 1" only if
  /// [bogoStatus] is true but the label itself is missing.
  String? get bogoDisplayLabel => bogoStatus ? (bogoLabel ?? 'Buy 1 Get 1') : null;

  /// Re-derives free/paid units for the CURRENT [qty] right after a local
  /// +/- change, so the badge reflects the new quantity immediately
  /// instead of the stale numbers from the last server sync. Uses "1 free
  /// per 2 units" — confirmed against three real `/app/cart` responses
  /// (qty 1 → free 0/paid 1; qty 3 → free 1/paid 2) — as the best
  /// approximation available client-side for a plain "Buy 1 Get 1"; the
  /// next full [CartState.loadCartRemote] sync remains the authoritative
  /// correction if the server's actual rule is ever more specific than
  /// that (e.g. a minimum-spend condition).
  void recomputeBogoLocally() {
    if (!bogoStatus) return;
    freeQty = qty ~/ 2;
    paidQty = qty - freeQty!;
    bogoSaved = freeQty! * price;
  }

  double get lineTotalBeforeDiscount => (was ?? price) * qty;
}
