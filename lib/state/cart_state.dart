import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import '../core/network/api_exception.dart';
import '../core/utils/auth_gate.dart';
import '../core/widgets/async_state_view.dart';
import '../data/models/cart_line.dart';
import '../data/models/coupon_result.dart';
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

  // ---------------------------------------------------------------- cart ops
  void addToCart(Product p, {required String seller, required double price, double? was, int? apiProductId}) {
    final key = '${p.id}_$seller';
    if (cart.containsKey(key)) {
      cart[key]!.qty++;
    } else {
      cart[key] = CartLine(key: key, productId: p.id, apiProductId: apiProductId, seller: seller, price: price, was: was);
    }
    _locallyToggledCartKeys.add(key);
    notifyListeners();
  }

  /// True once a specific cart line's real state is known for certain this
  /// session — a full sync ([loadCartRemote]) has happened, or the person
  /// added/changed/removed this exact line locally themselves. Everything
  /// else has to fall back to a one-time seed from that product's own
  /// `cart_status` (see [seedCartStatusOnce]) — which only knows "yes/no",
  /// not a real quantity, unlike a full sync.
  bool _cartFullySynced = false;
  final Set<String> _locallyToggledCartKeys = {};
  final Set<String> _cartStatusSeeded = {};

  /// Seeds a placeholder line (qty 1) the first time a product whose own
  /// `cart_status` says "already in cart" is seen, and nothing local knows
  /// about it yet — so the stepper (not an "Add" button) shows immediately
  /// from list-response data, instead of only after a full cart sync. Only
  /// ever runs once per key per session: a real [loadCartRemote] sync (or
  /// the person changing the quantity themselves) is what corrects the
  /// placeholder qty to the real one, not repeated reseeding — otherwise a
  /// stale `cart_status: true` on a re-rendered product could stomp back
  /// over a quantity the person already changed or removed.
  void seedCartStatusOnce(Product p, {required String seller, required double price, double? was, int? apiProductId, required bool cartStatus}) {
    final key = '${p.id}_$seller';
    if (_cartFullySynced || _cartStatusSeeded.contains(key) || _locallyToggledCartKeys.contains(key)) return;
    _cartStatusSeeded.add(key);
    if (cartStatus && !cart.containsKey(key)) {
      cart[key] = CartLine(key: key, productId: p.id, apiProductId: apiProductId, seller: seller, price: price, was: was, qty: 1);
      notifyListeners();
    }
  }

  void setQty(String key, int delta, {bool rx = false}) {
    final store = rx ? rxCart : cart;
    final line = store[key];
    if (line == null) return;
    line.qty += delta;
    if (line.qty <= 0) store.remove(key);
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

        // Confirmed always present now — builds the line from the cart
        // response alone, no PDP fetch needed.
        if (pharmacyNameFromCart != null && pharmacyNameFromCart.isNotEmpty) {
          final key = 'cart_${cartId ?? productIdRaw}';
          newCart[key] = CartLine(
            key: key,
            apiProductId: int.tryParse(productIdRaw.toString()),
            seller: pharmacyNameFromCart,
            price: fallbackPrice,
            was: fallbackWas,
            qty: qty,
            serverCartId: cartId,
            nameOverride: e['name']?.toString(),
            nameOverrideAr: e['name']?.toString(),
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
          final key = '${product.id}_${seller.name}';
          newCart[key] = CartLine(
            key: key,
            productId: product.id,
            apiProductId: seller.productId,
            seller: seller.name,
            price: seller.price,
            was: seller.was,
            qty: qty,
            serverCartId: cartId,
          );
        } catch (_) {
          // Couldn't resolve which pharmacy this is from — still show it
          // rather than dropping it, using the cart response's own fields
          // directly. Grouped under a placeholder seller name since we
          // genuinely don't know the real one here.
          final key = 'cart_${cartId ?? productIdRaw}';
          newCart[key] = CartLine(
            key: key,
            apiProductId: int.tryParse(productIdRaw.toString()),
            seller: 'WASFA',
            price: fallbackPrice,
            qty: qty,
            serverCartId: cartId,
            nameOverride: e['name']?.toString(),
            nameOverrideAr: e['name']?.toString(),
          );
        }
      }));
      cart
        ..clear()
        ..addAll(newCart);
      _cartFullySynced = true;
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
  /// Confirmed live response:
  /// `{ groups: [{ prescription_id, subtotal, items: [{ cart_id,
  /// product_id, name, image, price, quantity, dosage, duration,
  /// dose_time }] }], total, count }`.
  ///
  /// Two things worth calling out since they differ from the prescription
  /// *detail* endpoint's item shape (which this still reuses
  /// [Prescription.fromJson]/[RxItem.fromJson] for, since the group's own
  /// `prescription_id` + `items` line up with what that parser already
  /// expects):
  /// - Each group has no doctor/clinic/diagnosis/date/status fields at
  ///   all — those come back empty here, which is fine, this only needs
  ///   `.id` and `.items` from it.
  /// - Each item has no `seller` field and no `id` field — only `cart_id`.
  ///   No seller name means there's no real pharmacy to group these lines
  ///   by for display, so each group is shown under its *prescription* id
  ///   instead of a pharmacy name (which also happens to match reality
  ///   better here, since Rx checkout is per-prescription, not
  ///   per-pharmacy). No item `id` means the cart-line key uses `cart_id`
  ///   instead of the `rxId#itemId` pattern used when first adding a line.
  Future<void> loadRxCartRemote(int userId) async {
    rxCartLoading = true;
    notifyListeners();
    try {
      final res = await AccountService.instance.rxCartList(userId);
      final list = (res is Map ? res['groups'] ?? res['prescriptions'] ?? res['items'] ?? res['data'] : null) ?? (res is List ? res : const []);
      final groups = (list as List).whereType<Map>().map((e) => Prescription.fromJson(e.cast<String, dynamic>())).toList();

      final newRxCart = <String, CartLine>{};
      for (final rx in groups) {
        // Keeps the Rx detail screen's cache warm too, so opening a
        // prescription that's already in the cart doesn't show stale data
        // — best-effort only, since this group carries none of the
        // doctor/clinic/etc fields the detail screen actually needs, so
        // don't overwrite a richer cached copy with this thinner one.
        if (CatalogRepository.instance.findPrescription(rx.id) == null) {
          CatalogRepository.instance.upsertPrescription(rx);
        }
        for (final item in rx.items) {
          if (item.sellers.isEmpty || item.cartId == null) continue;
          final seller = item.sellers.first; // price/product_id only — no real seller name here
          final key = 'cart_${item.cartId}';
          newRxCart[key] = CartLine(
            key: key,
            apiProductId: seller.productId,
            seller: rx.id, // groups this line by prescription, not a (nonexistent) pharmacy name
            price: seller.price,
            qty: item.cartQuantity ?? 1,
            rxId: rx.id,
            nameOverride: item.name,
            nameOverrideAr: item.nameAr,
            emojiOverride: item.emoji,
            serverCartId: item.cartId,
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

  /// Adds to the cart optimistically (instant, always works), then syncs to
  /// the server in the background — skips the sync entirely if signed out,
  /// same allowance as the rest of the app (browsing/cart use doesn't
  /// require an account; only checkout does). Uses `update` instead of
  /// `add` when the line already existed, since `/app/cart/add` reads like
  /// an incremental "add N more" rather than "set quantity to N" — sending
  /// the *new total* to `add` again for an existing line risked double-
  /// counting server-side.
  Future<void> addToCartRemote(BuildContext context, Product p, {required String seller, required double price, double? was, int? apiProductId}) async {
    final auth = context.read<AuthState>();
    final key = '${p.id}_$seller';
    final existedAlready = cart.containsKey(key);
    addToCart(p, seller: seller, price: price, was: was, apiProductId: apiProductId);
    if (!auth.isSignedIn) return;
    final line = cart[key];
    if (line == null) return;
    try {
      if (existedAlready) {
        // Needs this line's own cart_id (confirmed: /app/cart/update takes
        // cart_id, not product_id) — normally already known from the
        // original add response or a /app/cart sync. If it's genuinely not
        // known yet, there's nothing to target server-side, so this stays
        // a local-only bump until the next sync picks up the real id.
        if (line.serverCartId != null) {
          await CartService.instance.update(auth.userId!, line.serverCartId!, line.qty);
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
    }
  }

  /// Rx cart lines share the same server-side `cart_id` system as the
  /// regular cart (confirmed: the cart_ids seen on Rx cart entries come
  /// from the same sequence as regular cart entries) — so this uses the
  /// exact same `/app/cart/update`/`/app/cart/remove` endpoints for both,
  /// just operating on [rxCart] instead of [cart] when [rx] is true.
  Future<void> setQtyRemote(BuildContext context, String key, int delta, {bool rx = false}) async {
    final auth = context.read<AuthState>();
    final store = rx ? rxCart : cart;
    final line = store[key];
    if (line == null) return;
    final cartId = line.serverCartId;
    setQty(key, delta, rx: rx);
    if (!auth.isSignedIn) return;
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
      }
    } catch (e) {
      if (context.mounted) showErrorToast(context, 'Couldn\'t sync that quantity change: ${describeError(e)}');
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
  /// Free-of-charge units for BOGO ("1+1") lines.
  int _freeUnits(CartLine line) {
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

  double pharmacyFee(double sub) => sub >= 3 ? 0 : 0.750;

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

  double deliveryTotal(Map<String, List<CartLine>> groups) {
    if (deliverTogether && groups.keys.length > 1) return togetherDeliveryFee;
    return groups.values.fold(0.0, (s, items) => s + pharmacyFee(groupSubtotal(items)));
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
  CheckoutTotals computeTotals() {
    final store = cartTab == 'rx' ? rxCart : cart;
    final groups = groupsFor(store);
    final before = store.values.fold(0.0, (s, l) => s + l.lineTotalBeforeDiscount);
    final sub = cartSubtotal(store);
    final itemDiscount = double.parse((before - sub).toStringAsFixed(3));
    final fee = deliveryTotal(groups);

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
