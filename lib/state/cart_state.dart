import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import '../core/network/api_exception.dart';
import '../core/utils/auth_gate.dart';
import '../core/widgets/async_state_view.dart';
import '../data/models/cart_line.dart';
import '../data/models/coupon_result.dart';
import '../data/models/area_catalog.dart';
import '../data/models/prescription.dart';
import '../data/models/product.dart';
import '../data/models/promo.dart';
import '../data/repositories/catalog_repository.dart';
import '../data/services/account_service.dart';
import '../data/services/cart_service.dart';
import '../data/services/catalog_service.dart';
import 'auth_state.dart';

/// Holds the shopping cart (CART), the prescription cart (RXCART), and the
/// wishlist. This is the Flutter analogue of the JS globals `CART`, `RXCART`,
/// `WISH` plus the pure functions `cartGroups/lineCharge/groupSub/phFee/
/// deliveryTotal/computeTotals` from the HTML prototype — kept together here
/// because in the source they all operate on the same cart state.
class CartState extends ChangeNotifier {
  final Map<String, CartLine> cart = {}; // "productId_seller" -> line
  final Map<String, CartLine> rxCart = {}; // "rxId#idx" -> line
  final Set<int> wishlist = {};

  String cartTab = 'my'; // 'my' | 'rx'
  bool deliverTogether = false;
  /// Only ever set by a real, server-validated `/coupon` check (see
  /// [applyCoupon]) — never auto-picked from a local list. There used to be
  /// a hardcoded set of "promos" (WASFA15/SAVE2/FREEDEL/NEW10) that
  /// auto-applied whichever saved the most, entirely client-side, with no
  /// backend involvement at all — meaning the discount shown in the app
  /// had no guarantee of matching what the backend would actually charge,
  /// since `/orders`' `coupon` field was just sent as a free-text string
  /// with nothing having confirmed the backend recognized it. Removed
  /// entirely; a discount now only ever shows here if the real `/coupon`
  /// endpoint confirmed it.
  CouponResult? appliedCoupon;

  Map<String, CartLine> get activeStore => cartTab == 'rx' ? rxCart : cart;

  /// Whether an Rx cart line is CURRENTLY in stock — re-checked live against
  /// whatever [CatalogRepository] has cached for that prescription, rather
  /// than trusting [CartLine.inStock] (captured once, at add time). Pricing
  /// and stock for a prescription item are set by a pharmacist, often well
  /// after the item was first added to the Rx cart, so it's genuinely
  /// possible for a line to go stale in a way the regular shop cart mostly
  /// isn't exposed to. Falls back to the line's own captured [CartLine.inStock]
  /// if this prescription (or this specific item index) isn't cached right
  /// now — e.g. the person added it, then the app was restarted before ever
  /// reopening that prescription again this session.
  bool isRxLineInStock(CartLine line) {
    if (line.rxId == null) return line.inStock;
    final idx = int.tryParse(line.key.split('#').last);
    if (idx == null) return line.inStock;
    final rx = CatalogRepository.instance.findPrescription(line.rxId!);
    if (rx == null || idx < 0 || idx >= rx.items.length) return line.inStock;
    final sellers = rx.items[idx].sellers;
    if (sellers.isEmpty) return line.inStock;
    return sellers.any((s) => s.stock);
  }

  // ---------------------------------------------------------------- cart ops
  void addToCart(Product p, {required String seller, required double price, double? was, int? apiProductId, bool inStock = true}) {
    final key = lineKey(apiProductId: apiProductId, productId: p.id, seller: seller);
    if (cart.containsKey(key)) {
      cart[key]!.qty++;
      cart[key]!.recomputeBogoLocally();
    } else {
      cart[key] = CartLine(
        key: key,
        productId: p.id,
        apiProductId: apiProductId,
        seller: seller,
        price: price,
        was: was,
        imageOverride: p.imageUrl,
        bogoStatus: p.bogoStatus,
        bogoLabel: p.bogoLabel,
        inStock: inStock,
      )..recomputeBogoLocally();
    }
    _locallyToggledCartKeys.add(key);
    notifyListeners();
  }

  final Set<String> _locallyToggledCartKeys = {};

  /// Cart line keys with a network call currently in flight (add/update/
  /// remove). The stepper shows a small loader for a key while it's in
  /// here — see [isSyncingCart] — AND a second tap on that same key is
  /// ignored rather than firing an overlapping request (see
  /// [addToCartRemote]/[setQtyRemote]). Every tap still goes straight to
  /// the network with no artificial delay; this only ever blocks a second
  /// tap that lands *while the first one's call is still in flight*.
  final Set<String> pendingSyncKeys = {};

  bool isSyncingCart(String key) => pendingSyncKeys.contains(key);

  /// Tracks, per cart-line key, the identity of the last [Product] instance
  /// whose `cart_qty` was already applied via [syncQtyFromListing] — see
  /// that method's doc for why this exists.
  final Map<String, int> _listingSyncedProductIdentity = {};

  /// Upserts a line's quantity straight from a fresh product-listing
  /// response's own `cart_qty` (Shop/Home/Store) — a REAL number the
  /// backend now sends per row, not a guess. Unlike the old seed-once
  /// mechanism this replaces, a genuinely fresh fetch (a revisit, a new
  /// page) always gets applied — it doesn't freeze after the first check.
  ///
  /// BUT it only applies once per *actual fetch*, not once per widget
  /// rebuild: a product card rebuilds constantly for reasons that have
  /// nothing to do with new data arriving (the person tapping the stepper
  /// itself, another card's wishlist toggling, etc.), and the widget calls
  /// this from a `build()`-time postFrameCallback every single time. Each
  /// `ShopViewModel.load()` creates brand-new [Product] objects, so
  /// "already applied for this exact object" (tracked via
  /// [_listingSyncedProductIdentity]) is what distinguishes "a real new
  /// fetch landed" from "the same fetch's card just rebuilt again" —
  /// without it, this stomped the real post-tap quantity back to the
  /// stale listing value the instant a tap's own sync finished (loader
  /// shows, then the number reverts to the old one).
  ///
  /// Also skips a key that's currently mid-sync ([pendingSyncKeys]) so a
  /// listing fetch that started before the person's own tap can't land
  /// after it and stomp the tap while it's still in flight — AND skips a
  /// key already in `_locallyToggledCartKeys` (the person changed it
  /// locally this session), for the same reason [loadCartRemote]'s merge
  /// does: their own tap's own request already told the server the truth,
  /// so their local quantity is trusted over a listing response that could
  /// just as easily be a stale read from before that tap landed. Only ever
  /// touches the ONE key given — never clears the rest of [cart] — because
  /// a listing response is a partial/paginated view, not the full cart
  /// (that's what [loadCartRemote] is for, which is also still needed here
  /// to learn each line's real `serverCartId` so +/- taps can actually
  /// reach the server).
  void syncQtyFromListing(Product p, {required String seller, required double price, double? was, int? apiProductId, required int qty, bool inStock = true}) {
    final key = lineKey(apiProductId: apiProductId, productId: p.id, seller: seller);
    if (pendingSyncKeys.contains(key)) return; // don't record identity yet — retry once the in-flight tap's sync clears
    if (_locallyToggledCartKeys.contains(key)) return; // the person's own tap already told the server the truth for this line

    final identity = identityHashCode(p);
    if (_listingSyncedProductIdentity[key] == identity) return; // same fetch, already applied
    _listingSyncedProductIdentity[key] = identity;

    final existing = cart[key];
    if (qty <= 0) {
      if (existing != null) {
        cart.remove(key);
        notifyListeners();
      }
      return;
    }
    if (existing != null && existing.qty == qty) return; // already correct — no-op

    cart[key] = CartLine(
      key: key,
      productId: p.id,
      apiProductId: apiProductId,
      seller: seller,
      price: price,
      was: was,
      qty: qty,
      serverCartId: existing?.serverCartId, // preserve if a fuller sync already learned it
      imageOverride: p.imageUrl,
      bogoStatus: p.bogoStatus,
      bogoLabel: p.bogoLabel,
      inStock: inStock,
    )..recomputeBogoLocally();
    notifyListeners();
  }

  /// The ONE canonical way to build a cart-line key — every call site that
  /// needs one (here, [loadCartRemote], and both product-card widgets)
  /// MUST go through this rather than building the string inline.
  ///
  /// `apiProductId` (the seller-specific listing id) is used when known,
  /// because it's confirmed to be the SAME id space `/app/products`,
  /// `/app/cart`, and order placement all use (see [addToCartRemote]'s
  /// docs) — unlike `productId` (the catalog id), which `/app/cart`'s own
  /// `product_id` field does NOT refer to, despite the name. Falls back to
  /// `productId_seller` only when no apiProductId is available yet.
  ///
  /// Before this existed, a line added locally from the Shop grid got the
  /// key `productId_seller`, while [loadCartRemote] mostly built
  /// `cart_<cartId>` for the exact same real line — two different keys for
  /// one cart line. That's why the shop grid's stepper could show "Add to
  /// cart" for something that genuinely was in the cart (a synced line
  /// living under a key the grid never looked up), and why a local add
  /// could end up duplicating a synced line instead of updating it.
  static String lineKey({int? apiProductId, int? productId, required String seller}) {
    if (apiProductId != null) return 'ap_$apiProductId';
    return '${productId}_$seller';
  }

  void setQty(String key, int delta, {bool rx = false}) {
    final store = rx ? rxCart : cart;
    final line = store[key];
    if (line == null) return;
    line.qty += delta;
    if (line.qty <= 0) {
      store.remove(key);
    } else {
      line.recomputeBogoLocally();
    }
    if (!rx) _locallyToggledCartKeys.add(key);
    notifyListeners();
  }

  void removeLine(String key, {bool rx = false}) {
    (rx ? rxCart : cart).remove(key);
    if (!rx) _locallyToggledCartKeys.add(key);
    notifyListeners();
  }

  void clearCart() {
    cart.clear();
    notifyListeners();
  }

  /// Clears the local cart AND best-effort removes each line's server-side
  /// copy — call this after a successful order via `/orders`, not just
  /// [clearCart] alone. Needed because order placement still sends its own
  /// fully itemized body (see OrderService.placeOrder) rather than
  /// referencing the server-side cart at all — the two are independent
  /// data stores right now, so completing an order does NOT automatically
  /// empty `/app/cart` server-side. Without this, items already purchased
  /// would still show up next time the cart syncs from the server.
  Future<void> clearCartRemote(int userId) async {
    final linesWithServerIds = cart.values.where((l) => l.serverCartId != null).toList();
    clearCart();
    for (final line in linesWithServerIds) {
      try {
        await CartService.instance.remove(userId, line.serverCartId!, line.qty);
      } catch (_) {
        // Best-effort — the local cart is already cleared either way; a
        // leftover server-side line will just get cleaned up next sync.
      }
    }
  }

  bool cartLoading = false;
  bool rxCartLoading = false;

  /// Replaces the local cart with the server's copy — call when opening the
  /// Cart screen (mirrors [loadWishlistRemote]'s pattern/reasoning).
  ///
  /// Confirmed live response: `{ items: [{ cart_id, product_id, sku,
  /// apix_sku, name, image, unit, pharmacy_name, price, compare_price,
  /// discount_pct, quantity, subtotal }], subtotal, count }` — note the
  /// field is `quantity`, not `qty`. `pharmacy_name` is now confirmed
  /// always present, so every line builds directly from this response
  /// alone — no PDP fetch needed at all anymore. The PDP-fallback branch
  /// below is now dead in practice (kept only in case some future response
  /// is ever missing it) rather than the primary path it used to be.
  Future<void> loadCartRemote(int userId) async {
    if (cartLoading) return;
    cartLoading = true;
    notifyListeners();
    try {
      final res = await CartService.instance.cart(userId);
      final list = (res is Map ? res['items'] ?? res['cart'] ?? res['data'] : null) ?? (res is List ? res : const []);
      final entries = (list as List).whereType<Map>().toList();

      final newCart = <String, CartLine>{};
      await Future.wait(entries.map((e) async {
        final productIdRaw = e['product_id'] ?? e['id'];
        if (productIdRaw == null) return;
        final qty = int.tryParse((e['quantity'] ?? e['qty'] ?? 1).toString()) ?? 1;
        final cartId = int.tryParse((e['cart_id'] ?? '').toString());
        // ✅ Confirmed live (2026-07-24): `GET /app/product/{id}` wants the
        // real `sku`, NOT `apix_sku` — passing apix_sku 404s. This was
        // backwards before (apix_sku first), which is why cart loads with
        // an incomplete cart response (missing pharmacy_name — see below)
        // were silently 404ing against the wrong identifier on every
        // single cart load, with no product tap involved at all.
        final skuFromCart = e['sku']?.toString();
        final apixSkuFromCart = e['apix_sku']?.toString();
        final fallbackPrice = double.tryParse((e['price'] ?? 0).toString()) ?? 0;
        final fallbackWas = double.tryParse((e['compare_price'] ?? '').toString());
        final pharmacyNameFromCart = e['pharmacy_name']?.toString();
        final imageFromCart = e['image']?.toString();
        // Confirmed live (`in_stock`) across product/cart/order/rx responses
        // (2026-07-29). Defaults true — a response that omits this for an
        // in-stock item shouldn't wrongly label it out of stock.
        final inStockFromCart = e['in_stock'] == null ? true : e['in_stock'] == true;
        // Confirmed live on /app/cart per line (2026-07-29) — the real
        // BOGO math for this exact line, not a client-side guess.
        final bogoStatus = e['bogo_status'] == true;
        final bogoLabel = e['bogo_label']?.toString();
        final freeQty = int.tryParse((e['free_qty'] ?? '').toString());
        final paidQty = int.tryParse((e['paid_qty'] ?? '').toString());
        final bogoSaved = double.tryParse((e['bogo_saved'] ?? '').toString());

        // Confirmed always present now — builds the line from the cart
        // response alone, no PDP fetch needed.
        if (pharmacyNameFromCart != null && pharmacyNameFromCart.isNotEmpty) {
          // `productIdRaw` here IS the seller-specific listing id (same
          // space as `apiProductId`/`s.productId` — see [lineKey]'s doc),
          // so this key lines up with whatever the shop grid already has
          // for this exact product+seller, instead of living under its own
          // `cart_<cartId>` key that nothing else would ever look up.
          final apiProductId = int.tryParse(productIdRaw.toString());
          final key = lineKey(apiProductId: apiProductId, seller: pharmacyNameFromCart);
          newCart[key] = CartLine(
            key: key,
            apiProductId: apiProductId,
            seller: pharmacyNameFromCart,
            price: fallbackPrice,
            was: fallbackWas,
            qty: qty,
            serverCartId: cartId,
            nameOverride: e['name']?.toString(),
            nameOverrideAr: e['name']?.toString(),
            imageOverride: imageFromCart,
            inStock: inStockFromCart,
            bogoStatus: bogoStatus,
            bogoLabel: bogoLabel,
            freeQty: freeQty,
            paidQty: paidQty,
            bogoSaved: bogoSaved,
          );
          return;
        }

        try {
          final product = await CatalogService.instance.product(
            (skuFromCart != null && skuFromCart.isNotEmpty)
                ? skuFromCart
                : ((apixSkuFromCart != null && apixSkuFromCart.isNotEmpty) ? apixSkuFromCart : productIdRaw.toString()),
            userId: userId,
          );
          if (product.sellers.isEmpty) throw Exception('no sellers on PDP response');
          // Best match: the seller entry whose own product id is what
          // /app/cart actually referenced.
          final seller = product.sellers.firstWhere(
            (s) => s.productId?.toString() == productIdRaw.toString(),
            orElse: () => product.sellers.first,
          );
          final key = lineKey(apiProductId: seller.productId, productId: product.id, seller: seller.name);
          newCart[key] = CartLine(
            key: key,
            productId: product.id,
            apiProductId: seller.productId,
            seller: seller.name,
            price: seller.price,
            was: seller.was,
            qty: qty,
            serverCartId: cartId,
            imageOverride: product.imageUrl,
            inStock: seller.stock,
            bogoStatus: bogoStatus,
            bogoLabel: bogoLabel,
            freeQty: freeQty,
            paidQty: paidQty,
            bogoSaved: bogoSaved,
          );
        } catch (_) {
          // Couldn't resolve which pharmacy this is from — still show it
          // rather than dropping it, using the cart response's own fields
          // directly. Grouped under a placeholder seller name since we
          // genuinely don't know the real one here.
          final apiProductId = int.tryParse(productIdRaw.toString());
          final key = lineKey(apiProductId: apiProductId, seller: 'WASFA');
          newCart[key] = CartLine(
            key: key,
            apiProductId: apiProductId,
            seller: 'WASFA',
            price: fallbackPrice,
            qty: qty,
            serverCartId: cartId,
            nameOverride: e['name']?.toString(),
            nameOverrideAr: e['name']?.toString(),
            imageOverride: imageFromCart,
            inStock: inStockFromCart,
            bogoStatus: bogoStatus,
            bogoLabel: bogoLabel,
            freeQty: freeQty,
            paidQty: paidQty,
            bogoSaved: bogoSaved,
          );
        }
      }));
      // Merge, don't blindly replace: this fetch can be in flight for a
      // while, and an individual +/- tap's own immediate `/app/cart/update`
      // call can easily land BEFORE this one does even though this one
      // started first (this call does per-line work and sometimes a PDP
      // fallback fetch; a single tap's update does not). If this response
      // is stale relative to that tap, `cart..clear()..addAll(newCart)`
      // used to stomp the just-confirmed quantity straight back to the old
      // one — the fix succeeds server-side (see the `/cart/update` log),
      // the tap's own optimistic UI is briefly correct, and then THIS
      // response arrives and reverts it, which is exactly the bug this
      // fixes.
      //
      // A key already in `_locallyToggledCartKeys` (the person has changed
      // it locally this session) keeps its own quantity — its own request
      // already told the server the truth — and only picks up this
      // response's `serverCartId` if it didn't already have one (needed
      // for that key's future +/- taps to reach the server at all).
      // Anything not locally touched this session is fully trusted from
      // this response, same as before.
      for (final entry in newCart.entries) {
        final key = entry.key;
        final serverLine = entry.value;
        final localLine = cart[key];
        if (localLine != null && _locallyToggledCartKeys.contains(key)) {
          localLine.serverCartId ??= serverLine.serverCartId;
          // BOGO math isn't exposed to the same staleness race qty is (see
          // this method's own doc above) — /app/cart/update's own response
          // doesn't return it at all, so recomputeBogoLocally's "1 free
          // per 2 units" guess is the best available until a full reload
          // like this one lands with the server's real numbers. Only
          // trusted when this response's own qty for the line still
          // matches what's showing locally — if it doesn't, this response
          // reflects a different quantity than the one currently on
          // screen (a newer tap arrived since this fetch started), so its
          // bogo numbers wouldn't correspond to the current qty either.
          if (serverLine.qty == localLine.qty) {
            localLine.freeQty = serverLine.freeQty;
            localLine.paidQty = serverLine.paidQty;
            localLine.bogoSaved = serverLine.bogoSaved;
          }
        } else {
          cart[key] = serverLine;
        }
      }
      // Drop anything the server no longer has — unless it's a line the
      // person touched locally this session, which stays (its own sync may
      // still be in flight, or about to be sent).
      cart.removeWhere((key, _) => !newCart.containsKey(key) && !_locallyToggledCartKeys.contains(key));
    } catch (_) {
      // Non-fatal — keep whatever was already there locally.
    } finally {
      cartLoading = false;
      notifyListeners();
    }
  }

  /// Replaces the local Rx cart with the server's copy — call when opening
  /// the Cart screen, same as [loadCartRemote] does for the regular cart.
  ///
  /// Confirmed live (2026-07-31): `{"groups":[{"prescription_id",
  /// "subtotal","out_of_stock_count","items":[{cart_id,product_id,name,
  /// image,price,quantity,pharmacy_name,stock,in_stock,is_restricted,
  /// dosage,duration,dose_time}]}],"total","out_of_stock_count","count"}`.
  ///
  /// Each group is its own prescription, and — confirmed against the
  /// reference web app — checkout happens PER GROUP, not combined into one
  /// cart-wide checkout: each prescription gets its own "Checkout" button.
  /// See checkout_screen.dart's `rxScope` param, and [rxGroupsFor] (groups
  /// by `line.rxId` directly, unlike the regular cart's [groupsFor] which
  /// groups by pharmacy — a prescription's own "pharmacy" grouping doesn't
  /// apply the same way here).
  ///
  /// `pharmacy_name` was added to this endpoint's items on 2026-07-31 —
  /// used directly now. The cross-reference-against-cached-prescription
  /// fallback (matching `product_id` against whatever prescription detail
  /// is already cached in [CatalogRepository]) only kicks in if a response
  /// genuinely omits it.
  ///
  /// Also has no item `id` field at all, only `cart_id` — the cart-line
  /// key here uses `cart_id` instead of the `rxId#itemId` pattern used
  /// when first adding a line via the prescription detail screen.
  Future<void> loadRxCartRemote(int userId) async {
    if (rxCartLoading) return;
    rxCartLoading = true;
    notifyListeners();
    try {
      final res = await AccountService.instance.rxCartList(userId);
      final groupsJson = (res is Map && res['groups'] is List) ? (res['groups'] as List) : const [];
      final newRxCart = <String, CartLine>{};
      for (final g in groupsJson.whereType<Map>()) {
        final group = g.cast<String, dynamic>();
        final rxId = group['prescription_id']?.toString();
        if (rxId == null || rxId.isEmpty) continue;
        final cachedRx = CatalogRepository.instance.findPrescription(rxId);
        final itemsJson = group['items'] is List ? (group['items'] as List) : const [];
        for (final it in itemsJson.whereType<Map>()) {
          final item = it.cast<String, dynamic>();
          final cartId = int.tryParse((item['cart_id'] ?? '').toString());
          if (cartId == null) continue;
          final apiProductId = int.tryParse((item['product_id'] ?? '').toString());
          // Confirmed live as of 2026-07-31 — the backend added
          // pharmacy_name directly to this endpoint's items, so the
          // cross-reference-against-cached-prescription fallback below is
          // now only needed for a response that genuinely omits it (or an
          // older cached response shape).
          String sellerName = item['pharmacy_name']?.toString() ?? '';
          if (sellerName.isEmpty && cachedRx != null) {
            for (final cachedItem in cachedRx.items) {
              if (cachedItem.sellers.isNotEmpty && cachedItem.sellers.first.productId == apiProductId) {
                sellerName = cachedItem.sellers.first.name;
                break;
              }
            }
          }
          if (sellerName.isEmpty) sellerName = 'WASFA';
          final key = 'cart_$cartId';
          newRxCart[key] = CartLine(
            key: key,
            apiProductId: apiProductId,
            seller: sellerName,
            price: double.tryParse((item['price'] ?? 0).toString()) ?? 0,
            qty: int.tryParse((item['quantity'] ?? 1).toString()) ?? 1,
            rxId: rxId,
            nameOverride: item['name']?.toString(),
            nameOverrideAr: item['name']?.toString(),
            imageOverride: item['image']?.toString(),
            serverCartId: cartId,
            inStock: item['in_stock'] == null ? true : item['in_stock'] == true,
          );
        }
      }
      rxCart
        ..clear()
        ..addAll(newRxCart);
    } catch (_) {
      // Non-fatal — keep whatever was already there locally.
    } finally {
      rxCartLoading = false;
      notifyListeners();
    }
  }

  /// Groups the Rx cart by prescription (`line.rxId`) — NOT by pharmacy
  /// like [groupsFor]. Confirmed against the reference web app (2026-07-31):
  /// Rx cart items are organized per-prescription with their own subtotal
  /// and their own "Checkout" button, not grouped by pharmacy at all.
  Map<String, List<CartLine>> rxGroupsFor() {
    final g = <String, List<CartLine>>{};
    for (final line in rxCart.values) {
      g.putIfAbsent(line.rxId ?? '', () => []).add(line);
    }
    return g;
  }

  /// Adds to the cart optimistically (instant, always works), then syncs to
  /// the server right away — no delay, no batching. Skips the sync
  /// entirely if signed out, same allowance as the rest of the app
  /// (browsing/cart use doesn't require an account; only checkout does).
  /// Uses `update` instead of `add` when the line already existed, since
  /// `/app/cart/add` reads like an incremental "add N more" rather than
  /// "set quantity to N" — sending the *new total* to `add` again for an
  /// existing line risked double-counting server-side.
  ///
  /// If a sync for this exact key is already in flight, this call is
  /// ignored rather than firing a second overlapping request — see
  /// [isSyncingCart]. No artificial wait either way: the very first tap
  /// always goes straight to the network.
  Future<void> addToCartRemote(BuildContext context, Product p, {required String seller, required double price, double? was, int? apiProductId, bool inStock = true}) async {
    final auth = context.read<AuthState>();
    final key = lineKey(apiProductId: apiProductId, productId: p.id, seller: seller);
    if (pendingSyncKeys.contains(key)) return; // previous tap's call still in flight
    final existedAlready = cart.containsKey(key);
    addToCart(p, seller: seller, price: price, was: was, apiProductId: apiProductId, inStock: inStock); // instant, local — unchanged
    if (!auth.isSignedIn) return;
    final line = cart[key];
    if (line == null) return;

    pendingSyncKeys.add(key);
    notifyListeners();
    try {
      if (existedAlready) {
        // Needs this line's own cart_id (confirmed: /app/cart/update takes
        // cart_id, not product_id) — normally already known from the
        // original add response or a /app/cart sync. If it's genuinely not
        // known yet, there's nothing to target server-side, so this stays
        // a local-only bump until the next sync picks up the real id.
        if (line.serverCartId != null) {
          await CartService.instance.update(auth.userId!, line.serverCartId!, line.qty);
          // Same reasoning as setQtyRemote's own update call — see its
          // comment on why this isn't awaited and what it corrects.
          loadCartRemote(auth.userId!);
        }
      } else {
        // Confirmed: a real `/app/products` response has `product_id`
        // sitting alongside `pharmacy_name`/`price` at the top level of
        // each row (not nested under a generic catalog id) — i.e.
        // `product_id` IS the seller-specific listing id, same as
        // `apiProductId`/`items[].id` elsewhere in this app (order
        // placement). Confirms this is the right id for a first-time add,
        // where there's no cart_id yet at all.
        final productIdForServer = apiProductId ?? p.id;
        final cartId = await CartService.instance.add(auth.userId!, productIdForServer, line.qty);
        if (cartId != null) line.serverCartId = cartId;
      }
    } catch (e) {
      if (context.mounted) showErrorToast(context, 'Added, but couldn\'t sync to your account: ${describeError(e)}');
    } finally {
      pendingSyncKeys.remove(key);
      notifyListeners();
    }
  }

  /// Rx cart lines share the same server-side `cart_id` system as the
  /// regular cart (confirmed: the cart_ids seen on Rx cart entries come
  /// from the same sequence as regular cart entries) — so this uses the
  /// exact same `/app/cart/update`/`/app/cart/remove` endpoints for both,
  /// just operating on [rxCart] instead of [cart] when [rx] is true.
  ///
  /// Same no-delay behaviour as [addToCartRemote]: calls the API
  /// immediately, and ignores a tap if this key's previous call hasn't
  /// finished yet rather than overlapping it.
  Future<void> setQtyRemote(BuildContext context, String key, int delta, {bool rx = false}) async {
    if (pendingSyncKeys.contains(key)) return; // previous tap's call still in flight
    final auth = context.read<AuthState>();
    final store = rx ? rxCart : cart;
    final line = store[key];
    if (line == null) return;
    final cartId = line.serverCartId;

    setQty(key, delta, rx: rx); // instant, local — unchanged
    if (!auth.isSignedIn) return;

    pendingSyncKeys.add(key);
    notifyListeners();
    final stillPresent = store.containsKey(key);
    try {
      if (!stillPresent) {
        // Quantity dropped to 0 and [setQty] already removed it locally —
        // mirror that server-side if we know this line's real cart_id.
        if (cartId != null) {
          await CartService.instance.remove(auth.userId!, cartId, 0);
        }
      } else if (cartId != null) {
        await CartService.instance.update(auth.userId!, cartId, store[key]!.qty);
        // /app/cart/update's own response doesn't return updated
        // free_qty/paid_qty/bogo_saved for this line (just {"ok","action"})
        // — recomputeBogoLocally's "1 free per 2 units" guess is what's
        // showing right now. Not awaited: this runs in the background and
        // corrects it via loadCartRemote's merge (see that method's doc on
        // why a locally-toggled line's bogo fields specifically get
        // updated from this, unlike its qty) shortly after, without
        // delaying this tap's own already-instant feedback.
        if (!rx) loadCartRemote(auth.userId!);
      }
    } catch (e) {
      if (context.mounted) showErrorToast(context, 'Couldn\'t sync that quantity change: ${describeError(e)}');
    } finally {
      pendingSyncKeys.remove(key);
      notifyListeners();
    }
  }


  Future<void> removeLineRemote(BuildContext context, String key, {bool rx = false}) async {
    final auth = context.read<AuthState>();
    final store = rx ? rxCart : cart;
    final line = store[key];
    removeLine(key, rx: rx);
    if (!auth.isSignedIn || line == null) return;
    if (line.serverCartId == null) return; // never synced a real cart_id for this line — nothing to remove server-side
    try {
      await CartService.instance.remove(auth.userId!, line.serverCartId!, line.qty);
    } catch (e) {
      if (context.mounted) showErrorToast(context, 'Removed locally, but couldn\'t sync to your account: ${describeError(e)}');
    }
  }

  void clearRxCart() {
    rxCart.clear();
    notifyListeners();
  }

  void setCartTab(String tab) {
    cartTab = tab;
    notifyListeners();
  }

  void toggleDeliverTogether() {
    deliverTogether = !deliverTogether;
    notifyListeners();
  }

  void toggleWish(int productId) {
    if (wishlist.contains(productId)) {
      wishlist.remove(productId);
    } else {
      wishlist.add(productId);
    }
    _locallyToggledWish.add(productId);
    notifyListeners();
  }

  bool isWished(int productId) => wishlist.contains(productId);

  /// True once [productId]'s wishlist state is known for certain this
  /// session — either a full sync has happened ([loadWishlistRemote]) or
  /// the person toggled it locally themselves. Everything else has to fall
  /// back to whatever a specific product's own `wishlist_status` says.
  bool _wishlistFullySynced = false;
  final Set<int> _locallyToggledWish = {};

  /// Whether [productId] is wished — prefers local session state (trusted
  /// once [_wishlistFullySynced] or this id was toggled locally), falling
  /// back to [fallbackFromApi] (that specific product's own confirmed-live
  /// `wishlist_status` field from `/app/products`) otherwise. This is what
  /// lets a product card show the correct heart state immediately from its
  /// own list-response data, without waiting on a separate wishlist fetch
  /// to finish first — see [loadWishlistRemote] for why a full sync still
  /// matters (it's the only source that knows about a wish from a product
  /// this device hasn't happened to browse yet).
  bool isWishedOrFallback(int productId, bool fallbackFromApi) {
    if (_wishlistFullySynced || _locallyToggledWish.contains(productId)) return wishlist.contains(productId);
    return fallbackFromApi;
  }

  bool wishlistLoading = false;

  /// Replaces the local wishlist with the server's copy — call after login
  /// and whenever the Wishlist tab is opened, matching skus back to catalog
  /// product ids via [CatalogRepository]'s cache.
  /// Was: matched wishlisted SKUs against whatever happened to already be
  /// sitting in [CatalogRepository.products] from browsing elsewhere this
  /// session. That only ever "worked" because the mock catalog coincidentally
  /// covered common demo SKUs — for a real SKU the person hasn't happened to
  /// view yet, there'd be nothing to match against and it would silently
  /// vanish from the wishlist. Now fetches each wishlisted item's real detail
  /// directly (same `/app/product/{apix_sku}` PDP endpoint), so this doesn't
  /// depend on incidental cache state — and it also seeds the cache for any
  /// other screen (Store, Shop) that looks these products up later.
  /// [AccountService.wishlist] already prefers `apix_sku` over `sku` per
  /// item, so what arrives here should be the right identifier for the PDP
  /// fetch below.
  Future<void> loadWishlistRemote(int userId) async {
    wishlistLoading = true;
    notifyListeners();
    try {
      final skus = await AccountService.instance.wishlist(userId);
      final repo = CatalogRepository.instance;
      final fetched = await Future.wait(skus.map((sku) async {
        try {
          return await CatalogService.instance.product(sku, userId: userId);
        } catch (_) {
          return null; // one bad/removed SKU shouldn't blank the whole wishlist
        }
      }));
      final products = fetched.whereType<Product>().toList();
      repo.cacheProducts(products);
      wishlist
        ..clear()
        ..addAll(products.map((p) => p.id));
      _wishlistFullySynced = true;
    } catch (_) {
      // Non-fatal — keep whatever was already there locally.
    } finally {
      wishlistLoading = false;
      notifyListeners();
    }
  }

  /// Toggles the wishlist optimistically, then syncs to the server —
  /// requires sign-in (per the `/acct/wish-toggle` endpoint). Reverts and
  /// shows an error toast if the request fails.
  Future<void> toggleWishRemote(BuildContext context, Product product) async {
    if (!await requireLogin(context)) return;
    if (!context.mounted) return;
    final auth = context.read<AuthState>();
    toggleWish(product.id);
    try {
      await AccountService.instance.toggleWish(auth.userId!, product.sku.isNotEmpty ? product.sku : product.pdpIdentifier);
    } catch (e) {
      toggleWish(product.id); // revert
      if (context.mounted) showErrorToast(context, describeError(e));
    }
  }

  /// Number of distinct items/lines in the cart — NOT the sum of
  /// quantities. Confirmed against a real `/app/cart` response: 3 distinct
  /// items with quantities 3/1/1 (summing to 5) came back as `"count": 3`,
  /// matching this, not the summed quantity.
  int get cartCount => cart.length;
  int get rxCartCount => rxCart.length;

  // ------------------------------------------------------------ pure totals
  /// Free-of-charge units for BOGO ("1+1") lines. Prefers the real
  /// `free_qty` confirmed live on `/app/cart` (2026-07-29) — the old guess
  /// below (half the quantity, only if [CatalogRepository] happens to have
  /// this line's product cached by catalog id) is now just a fallback for
  /// a line that hasn't been through a real `/app/cart` sync yet. That old
  /// guess was also fragile in its own right: a line built by
  /// [loadCartRemote]'s confirmed-live branch never carries a catalog
  /// `productId` at all (only `apiProductId`), so the lookup it depends on
  /// silently found nothing for exactly the lines that matter most.
  int _freeUnits(CartLine line) {
    if (line.freeQty != null) return line.freeQty!;
    if (line.productId == null) return 0;
    final p = CatalogRepository.instance.findProduct(line.productId!);
    if (p == null || !p.isBogo) return 0;
    return line.qty ~/ 2;
  }

  double lineCharge(CartLine line) => line.price * (line.qty - _freeUnits(line));

  /// Groups a store's lines by seller/pharmacy name.
  Map<String, List<CartLine>> groupsFor(Map<String, CartLine> store) {
    final g = <String, List<CartLine>>{};
    for (final line in store.values) {
      g.putIfAbsent(line.seller, () => []).add(line);
    }
    return g;
  }

  double groupSubtotal(List<CartLine> items) =>
      items.fold(0.0, (s, l) => s + lineCharge(l));

  /// Was `sub >= 3 ? 0 : 0.750` unconditionally — a flat rule straight out
  /// of the HTML prototype, applied regardless of which real delivery area
  /// the order is actually going to. This is the SAME bug already fixed
  /// once in checkout_screen.dart's own order-summary display (which reads
  /// `AreaCatalog.feeFor` directly instead of touching this method at
  /// all) — but this method itself, which [computeTotals] actually uses,
  /// was never fixed, so every OTHER caller of [computeTotals] was still
  /// silently getting the fake flat rate: the Cart screen's own bottom-bar
  /// total (100% of the time — Cart has no server checkout data to fall
  /// back from at all) and Checkout's own wallet-balance check and
  /// "Place order" button amount, in the brief window before its real
  /// `/app/checkout` fetch resolves. Now uses the real per-area
  /// `free_enabled`/`free_over`/per-area `fee` data when the caller can
  /// supply it — see [computeTotals]'s new `areaCatalog`/`areaId` params —
  /// falling back to the old flat rule only when a caller genuinely has no
  /// area context at all (e.g. before AddressState has loaded anything).
  double pharmacyFee(double sub, {AreaCatalog? areaCatalog, int? areaId}) {
    if (areaCatalog != null) return areaCatalog.feeFor(areaId, sub);
    return sub >= 3 ? 0 : 0.750;
  }

  double cartSubtotal(Map<String, CartLine> store) =>
      store.values.fold(0.0, (s, l) => s + lineCharge(l));

  /// Flat combined-delivery fee when "Deliver together" is on and the cart
  /// spans more than one pharmacy (see [deliveryTotal]) — matches the HTML
  /// prototype's own `deliveryTotal()` exactly. Worth being explicit about:
  /// this can cost MORE than delivery would without the toggle, if every
  /// pharmacy group already qualifies for free delivery on its own — it's
  /// trading that off for one consolidated delivery instead of several
  /// separate ones, not a discount. The UI shows this amount directly next
  /// to the toggle so that trade-off isn't a surprise after switching it on.
  static const double togetherDeliveryFee = 1.250;

  double deliveryTotal(Map<String, List<CartLine>> groups, {AreaCatalog? areaCatalog, int? areaId}) {
    if (deliverTogether && groups.keys.length > 1) return togetherDeliveryFee;
    return groups.values.fold(0.0, (s, items) => s + pharmacyFee(groupSubtotal(items), areaCatalog: areaCatalog, areaId: areaId));
  }

  /// Validates [code] against the real `/coupon` endpoint for the given
  /// [subtotal]. Sets [appliedCoupon] and returns null on success; on
  /// failure (invalid code, or a network error) leaves any previously
  /// applied coupon untouched and returns a message to show the person —
  /// so a bad attempt at replacing an already-valid code doesn't silently
  /// clear the good one.
  Future<String?> applyCoupon(String code, double subtotal) async {
    try {
      final result = await CatalogService.instance.checkCoupon(code: code, subtotal: subtotal);
      if (!result.valid) return result.message ?? 'That code isn\'t valid for this order.';
      appliedCoupon = result;
      notifyListeners();
      return null;
    } catch (e) {
      return describeError(e);
    }
  }

  void removeCoupon() {
    appliedCoupon = null;
    notifyListeners();
  }

  /// Full checkout totals — mirrors JS `computeTotals()`, minus the old
  /// auto-applied-fake-promo behaviour (see [appliedCoupon]'s doc).
  /// [storeOverride] lets a caller compute totals for a SUBSET of the
  /// active store — used by Rx checkout scoped to one specific
  /// prescription (see checkout_screen.dart's `rxScope`), since each
  /// prescription checks out separately rather than the whole Rx cart at
  /// once (confirmed against the reference web app, 2026-07-31).
  /// [areaCatalog]/[areaId] — see [pharmacyFee]'s doc for why passing these
  /// (when the caller has AddressState in scope) matters: without them,
  /// the delivery fee here silently reverts to a fake flat rate that has
  /// nothing to do with the order's real delivery area.
  CheckoutTotals computeTotals({Map<String, CartLine>? storeOverride, AreaCatalog? areaCatalog, int? areaId}) {
    final store = storeOverride ?? (cartTab == 'rx' ? rxCart : cart);
    final groups = groupsFor(store);
    final before = store.values.fold(0.0, (s, l) => s + l.lineTotalBeforeDiscount);
    final sub = cartSubtotal(store);
    final itemDiscount = double.parse((before - sub).toStringAsFixed(3));
    final fee = deliveryTotal(groups, areaCatalog: areaCatalog, areaId: areaId);

    final coupon = appliedCoupon;
    Promo? promoDisplay;
    double promoDiscount = 0;
    // A coupon that no longer meets its own conditions once the cart
    // changes (e.g. an item got removed and the subtotal dropped) just
    // silently contributes nothing further, rather than clearing itself —
    // the person can still see it's "applied" and remove it manually if
    // it's no longer doing anything.
    if (coupon != null && coupon.valid) {
      promoDiscount = coupon.freeDelivery ? fee : coupon.discount;
      promoDisplay = Promo(
        code: coupon.code,
        type: coupon.freeDelivery ? PromoType.freeDelivery : PromoType.flat,
        value: promoDiscount,
        min: 0,
        labelEn: coupon.message ?? (coupon.freeDelivery ? 'Free delivery' : 'Discount applied'),
        labelAr: coupon.message ?? (coupon.freeDelivery ? 'توصيل مجاني' : 'خصم مطبق'),
      );
    }
    final total = double.parse((sub + fee - promoDiscount).toStringAsFixed(3));
    return CheckoutTotals(
      groups: groups,
      before: before,
      subtotal: sub,
      itemDiscount: itemDiscount,
      deliveryFee: fee,
      promo: promoDisplay,
      promoDiscount: promoDiscount,
      total: total,
      due: total,
    );
  }
}

class CheckoutTotals {
  final Map<String, List<CartLine>> groups;
  final double before;
  final double subtotal;
  final double itemDiscount;
  final double deliveryFee;
  final Promo? promo;
  final double promoDiscount;
  final double total;
  final double due;

  const CheckoutTotals({
    required this.groups,
    required this.before,
    required this.subtotal,
    required this.itemDiscount,
    required this.deliveryFee,
    required this.promo,
    required this.promoDiscount,
    required this.total,
    required this.due,
  });
}
