import 'package:flutter/foundation.dart';
import '../core/network/api_exception.dart';
import '../data/models/address.dart';
import '../data/models/order.dart';
import '../data/models/cart_line.dart';
import '../data/models/wallet_transaction.dart';
import '../data/repositories/catalog_repository.dart';
import '../data/services/account_service.dart';
import '../data/services/catalog_service.dart';
import '../data/services/order_service.dart';
import 'cart_state.dart';

class OrdersState extends ChangeNotifier {
  final OrderService _orderService = OrderService.instance;
  final AccountService _accountService = AccountService.instance;
  final CatalogService _catalogService = CatalogService.instance;

  /// Populated by [loadMyOrders] — starts empty, no mock/dummy data.
  final List<Order> orders = [];

  bool ordersLoading = false;
  String? ordersError;

  bool walletLoading = false;
  String? walletError;
  double wallet = 0;
  double walletCredited = 0;
  double walletUsed = 0;
  /// UNCONFIRMED — there is no rewards/points field anywhere in
  /// `GET /acct/wallet`'s confirmed response shape (`balance`, `credited`,
  /// `used`, `tx[]` only). This used to be hardcoded to a fake `120` and
  /// never actually synced from anything real. Left at 0 (honest empty
  /// state) until backend adds a real field for this — ask them whether
  /// rewards/loyalty points are even a planned feature before building UI
  /// around a made-up number again.
  int rewards = 0;
  String? trackingOrderId;

  /// Populated by [loadWallet] — starts empty, no mock/dummy data.
  List<WalletTransaction> transactions = const [];

  /// Updates just the balance from another source that already fetched it
  /// (the checkout-init endpoint returns this too) — doesn't touch
  /// credited/used/transactions, which only [loadWallet] itself knows.
  void syncWalletBalance(double balance) {
    wallet = balance;
    notifyListeners();
  }

  Order? byId(String id) {
    try {
      return orders.firstWhere((o) => o.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Cancel/return requests and ratings (see [startRequest]/[rateOrder]) are
  /// tracked entirely client-side — there's no `/orders` endpoint yet that
  /// accepts or echoes them back, so [Order.fromJson] never sets them. That
  /// means any raw re-fetch (`loadMyOrders`, `loadOrderDetail`) was replacing
  /// the whole [Order] object and silently wiping them out: submit a
  /// cancellation, then simply open that order's detail screen again (which
  /// re-fetches it), and the request would vanish. This carries those
  /// fields forward from whatever's already in [orders] onto the freshly
  /// fetched copy before it replaces the old one.
  Order _preserveLocalState(Order fresh) {
    final prev = byId(fresh.id);
    if (prev != null) {
      fresh.cancelRequests = prev.cancelRequests;
      fresh.returnRequests = prev.returnRequests;
      fresh.rating = prev.rating;
      fresh.review = prev.review;
      // The list endpoint's bare item/pharmacy counts (see
      // Order.apiItemCount's doc) have no equivalent on the detail
      // endpoint's response — a detail fetch's own copy always parses
      // these as null. Without carrying the list's original values
      // forward, opening this order's detail screen and going back would
      // permanently replace a correct item count with however many line
      // entries the detail response happens to break the order into.
      fresh.apiItemCount ??= prev.apiItemCount;
      fresh.apiPharmacyCount ??= prev.apiPharmacyCount;
      // Detail-only fields (see Order.deliveryCharge's doc) — the list
      // endpoint doesn't send any of these at all, so a fresh list re-fetch
      // would otherwise wipe them back to their defaults (0/false/null)
      // even though the detail screen already confirmed real values.
      if (fresh.deliveryCharge == 0) fresh.deliveryCharge = prev.deliveryCharge;
      if (fresh.discount == 0) fresh.discount = prev.discount;
      if (!fresh.hasPendingCancel) fresh.hasPendingCancel = prev.hasPendingCancel;
      if (!fresh.hasPendingReturn) fresh.hasPendingReturn = prev.hasPendingReturn;
      fresh.paymentStatus ??= prev.paymentStatus;
      fresh.deliveryAddress ??= prev.deliveryAddress;
    }
    return fresh;
  }

  int get pendingRequestCount => orders
      .where((o) => o.cancelRequests.any((r) => r.status == 'pending') || o.returnRequests.any((r) => r.status == 'pending'))
      .length;

  // -------------------------------------------------------------- fetching
  Future<void> loadMyOrders(int userId) async {
    ordersLoading = true;
    ordersError = null;
    notifyListeners();
    try {
      final fetched = await _orderService.myOrders(userId);
      final merged = fetched.map(_preserveLocalState).toList();
      orders
        ..clear()
        ..addAll(merged);
    } catch (e) {
      ordersError = describeError(e);
    } finally {
      ordersLoading = false;
      notifyListeners();
    }
  }

  /// Fetches full detail for one order and merges it into the local list
  /// (the my-orders list response may be a lighter summary than the detail
  /// endpoint — this is what backs the Order Detail screen).
  Future<Order?> loadOrderDetail({required String code, required int userId}) async {
    try {
      final detail = _preserveLocalState(await _orderService.orderDetail(code: code, userId: userId));
      final idx = orders.indexWhere((o) => o.id == code);
      if (idx >= 0) {
        orders[idx] = detail;
      } else {
        orders.add(detail);
      }
      notifyListeners();
      return detail;
    } catch (e) {
      ordersError = describeError(e);
      notifyListeners();
      return byId(code);
    }
  }

  Future<void> loadWallet(int userId) async {
    walletLoading = true;
    walletError = null;
    notifyListeners();
    try {
      final summary = await _accountService.wallet(userId);
      wallet = summary.balance;
      walletCredited = summary.credited;
      walletUsed = summary.used;
      transactions = summary.transactions;
    } catch (e) {
      walletError = describeError(e);
    } finally {
      walletLoading = false;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------- place order
  /// Places an order via the API. Throws [ApiException] on failure — the
  /// caller (checkout screen) shows that message directly rather than a
  /// generic error, e.g. "Insufficient wallet balance" straight from the
  /// server.
  /// Resolves a single cart line to `{id, qty}` for the order payload.
  /// `id` must be the *seller's* product_id (see the class doc above) — if
  /// the line doesn't already carry one, this fetches the PDP once to find
  /// it. Throws [ApiException.business] naming the specific item if it
  /// truly can't be resolved, so the checkout screen can show exactly what
  /// to remove rather than a generic failure.
  Future<Map<String, dynamic>> _resolveOrderItem(CartLine line, {int? userId}) async {
    var apiId = line.apiProductId;
    if (apiId == null && line.productId != null) {
      final cached = CatalogRepository.instance.findProduct(line.productId!);
      if (cached != null && cached.pdpIdentifier.isNotEmpty) {
        try {
          final fresh = await _catalogService.product(cached.pdpIdentifier, userId: userId);
          CatalogRepository.instance.cacheProducts([fresh]);
          final matchingSeller = fresh.sellers.where((s) => s.name == line.seller).toList();
          final chosen = matchingSeller.isNotEmpty
              ? matchingSeller.first
              : (fresh.sellers.isNotEmpty ? fresh.sellers.first : null);
          apiId = chosen?.productId;
        } catch (_) {
          // fall through — apiId stays null, handled below
        }
      }
    }
    if (apiId == null) {
      throw ApiException.business(
        'Couldn\'t prepare "${line.nameOverride ?? 'an item'}" for checkout — please remove it from the cart and re-add it, then try again.',
      );
    }
    return {'id': apiId, 'qty': line.qty};
  }

  Future<String> placeOrderRemote({
    required int userId,
    required String customerName,
    required String customerPhone,
    required Address address,
    required String pay, // cod | knet | wallet
    required CheckoutTotals totals,
    String coupon = '',
    String? deliveryDate,
    int? deliverySlot,
    double? latitude,
    double? longitude,
  }) async {
    // Resolved concurrently rather than one at a time — with several items
    // each needing their own PDP lookup, resolving them sequentially could
    // take a very long time (each with its own network round-trip), making
    // the checkout spinner sit for a long time before anything visibly happens.
    final allLines = totals.groups.values.expand((g) => g).toList();
    final items = await Future.wait(allLines.map((line) => _resolveOrderItem(line, userId: userId)));
    final result = await _orderService.placeOrder(
      userId: userId,
      customerName: customerName,
      customerPhone: customerPhone,
      address: address,
      payment: pay,
      walletRedeem: pay == 'wallet',
      coupon: coupon,
      items: items,
      deliveryDate: deliveryDate,
      deliverySlot: deliverySlot,
      latitude: latitude,
      longitude: longitude,
    );
    final groups = totals.groups.entries
        .map((e) => OrderGroup(
              pharmacy: e.key,
              items: e.value.map((l) => OrderItemLine(productId: l.productId, qty: l.qty, price: l.price)).toList(),
            ))
        .toList();
    orders.insert(
      0,
      Order(id: result.code, ts: DateTime.now(), total: result.total > 0 ? result.total : totals.due, pay: pay, status: 'prep', groups: groups),
    );
    trackingOrderId = result.code;
    notifyListeners();
    return result.code;
  }

  /// Checks out the Rx cart via `POST /app/acct/rx/checkout` — a completely
  /// separate flow from [placeOrderRemote]/`/orders`. That endpoint takes
  /// ONE `prescription_id` at a time (plus `address_id`/`payment`), not an
  /// itemized cart body, so a person with items from more than one
  /// prescription in their Rx cart needs one call per prescription — this
  /// groups [rxCart] by [CartLine.rxId] and does exactly that, sequentially
  /// (not parallel, so a mid-way failure leaves it obvious which
  /// prescriptions actually went through vs which didn't, rather than a
  /// jumble of concurrent results).
  ///
  /// Returns one result per prescription attempted, in order, so the caller
  /// can show a clear "some of these didn't go through" message rather than
  /// only ever seeing the first result.
  Future<List<RxCheckoutResult>> placeRxOrdersRemote({
    required int userId,
    required int addressId,
    required String payment,
    required Map<String, CartLine> rxCart,
  }) async {
    final byRx = <String, List<CartLine>>{};
    for (final line in rxCart.values) {
      final rxId = line.rxId;
      if (rxId == null) continue;
      byRx.putIfAbsent(rxId, () => []).add(line);
    }

    final results = <RxCheckoutResult>[];
    for (final rxId in byRx.keys) {
      try {
        final code = await _accountService.rxCheckout(userId, rxId, addressId, payment);
        results.add(RxCheckoutResult(prescriptionId: rxId, orderCode: code, success: true));
      } catch (e) {
        results.add(RxCheckoutResult(prescriptionId: rxId, error: describeError(e), success: false));
      }
    }
    if (results.any((r) => r.success)) {
      trackingOrderId = results.firstWhere((r) => r.success).orderCode;
    }
    notifyListeners();
    return results;
  }

  /// Re-adds a completed order's line items to the shopping cart. Returns how
  /// many lines were added vs. skipped so the caller can toast honestly (an
  /// item is skipped when it carries no backend product id and therefore can't
  /// be ordered again — e.g. it's no longer sold).
  ({int added, int skipped}) reorderInto(CartState cartState, String orderId) {
    final o = byId(orderId);
    if (o == null) return (added: 0, skipped: 0);
    var added = 0;
    var skipped = 0;
    for (final g in o.groups) {
      for (final it in g.items) {
        // Restricted items can never be added to cart — pickup only. Was
        // previously not checked here at all, so "Reorder" would happily
        // re-add a restricted item, silently contradicting the same rule
        // already enforced for Rx items (see RequestFlowScreen/_addItem).
        if (it.restricted) {
          skipped++;
          continue;
        }
        // Confirmed live (`in_stock`) across product/cart/order/rx
        // responses (2026-07-29) — an order line that's gone out of stock
        // since it was fulfilled can't be reordered, same principle as
        // [restricted] above.
        if (!it.inStock) {
          skipped++;
          continue;
        }
        // An order line's `product_id` is the *seller* product id — exactly
        // what checkout must send as `items[].id`. Without it the line can't
        // be re-ordered, so skip it rather than adding a dead cart entry.
        final sellerProductId = it.productId;
        if (sellerProductId == null) {
          skipped++;
          continue;
        }
        // Best-effort catalog match (for display name/emoji + BOGO math);
        // null is fine — the name falls back to the order line's own name.
        final cached = CatalogRepository.instance.findProduct(sellerProductId);
        // Canonical key (see CartState.lineKey's doc) — this used to build
        // its own `<id>_<pharmacy>` string here instead, which doesn't
        // match what the shop grid/cart screen look up when apiProductId
        // is known, so a reordered line's stepper could silently fail to
        // show on the shop grid despite genuinely being in the cart.
        final key = CartState.lineKey(apiProductId: sellerProductId, productId: cached?.id, seller: g.pharmacy);
        final existing = cartState.cart[key];
        if (existing != null) {
          existing.qty += it.qty;
        } else {
          cartState.cart[key] = CartLine(
            key: key,
            productId: cached?.id,
            apiProductId: sellerProductId,
            seller: g.pharmacy,
            price: it.price,
            qty: it.qty,
            nameOverride: it.name.isNotEmpty ? it.name : null,
          );
        }
        added++;
      }
    }
    if (added > 0) {
      cartState.cartTab = 'my';
      cartState.notifyListeners();
    }
    return (added: added, skipped: skipped);
  }

  /// ✅ Now calls the real `/orders/{code}/cancel` or `/return` endpoint
  /// (confirmed live in the updated Postman collection) — this used to
  /// only touch local state, so nothing ever reached the server at all.
  /// [detailIds] should come from each item's [OrderItemLine.detailId],
  /// not a product id — that's a different field the backend also expects.
  Future<void> startRequest(
    String orderId,
    String type, {
    required int userId,
    required int reasonId,
    required String reasonLabel,
    String note = '',
    List<OrderItemLine> items = const [],
    Map<int, int>? qtyByDetailId,
    String? imagePath,
  }) async {
    final o = byId(orderId);
    if (o == null) return;
    final detailIds = items.map((it) => it.detailId).whereType<int>().toList();
    if (type == 'return') {
      await _orderService.returnOrder(code: orderId, userId: userId, reasonId: reasonId, note: note, detailIds: detailIds, qtyByDetailId: qtyByDetailId, imagePath: imagePath);
    } else {
      await _orderService.cancelOrder(code: orderId, userId: userId, reasonId: reasonId, note: note, detailIds: detailIds, qtyByDetailId: qtyByDetailId);
    }
    final req = OrderRequest(status: 'pending', reasonId: reasonId, reason: reasonLabel, note: note, items: items);
    if (type == 'return') {
      o.returnRequests = [...o.returnRequests, req];
    } else {
      o.cancelRequests = [...o.cancelRequests, req];
    }
    notifyListeners();
  }

  /// ✅ Now calls the real `/orders/{code}/rate` endpoint (confirmed live) —
  /// previously only set the rating/review on local state.
  Future<void> rateOrder(String orderId, int stars, {required int userId, String review = ''}) async {
    final o = byId(orderId);
    if (o == null) return;
    await _orderService.rateOrder(code: orderId, userId: userId, rating: stars, review: review);
    o.rating = stars;
    o.review = review;
    notifyListeners();
  }

  /// `GET /acct/my-requests` — the real, server-side list of every
  /// cancel/return request across all orders. Replaces deriving this
  /// purely from whatever's cached in [orders] locally, which only ever
  /// reflected requests made in the current app session.
  Future<List<({String orderCode, String type, OrderRequest request})>> fetchMyRequests(int userId) {
    return _orderService.myRequests(userId);
  }

  /// `GET /return-reasons?type=cancel|return` — real reason list with ids,
  /// replacing the hardcoded reason strings the request flow used before.
  Future<List<Reason>> fetchReturnReasons(String type) {
    return _orderService.returnReasons(type);
  }

  void topUp(double amount) {
    wallet = double.parse((wallet + amount).toStringAsFixed(3));
    notifyListeners();
  }

  void openTracking(String id) {
    trackingOrderId = id;
    notifyListeners();
  }
}

/// Result of checking out one prescription via [OrdersState.placeRxOrdersRemote].
class RxCheckoutResult {
  final String prescriptionId;
  final String? orderCode;
  final String? error;
  final bool success;
  const RxCheckoutResult({required this.prescriptionId, this.orderCode, this.error, required this.success});
}
