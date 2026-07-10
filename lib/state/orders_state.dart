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

  /// Seeded with a couple of demo orders so the Orders screen isn't blank
  /// before the first `/my-orders` fetch — replaced wholesale by [loadMyOrders].
  final List<Order> orders = [
    Order(
      id: 'APM30995',
      ts: DateTime.now().subtract(const Duration(days: 1)),
      total: 5.700,
      pay: 'knet',
      status: 'done',
      groups: [
        OrderGroup(pharmacy: 'Royal Pharmacy', items: const [
          OrderItemLine(productId: 1, qty: 2, price: 1.250),
          OrderItemLine(productId: 2, qty: 1, price: 3.200),
        ]),
      ],
    ),
    Order(
      id: 'APM31402',
      ts: DateTime.now().subtract(const Duration(hours: 2)),
      total: 5.050,
      pay: 'wallet',
      status: 'prep',
      groups: [
        OrderGroup(pharmacy: 'City Pharmacy', items: const [
          OrderItemLine(productId: 2, qty: 1, price: 3.350),
          OrderItemLine(productId: 1, qty: 1, price: 1.350),
        ]),
      ],
    ),
  ];

  bool ordersLoading = false;
  String? ordersError;

  bool walletLoading = false;
  String? walletError;
  double wallet = 12.500;
  double walletCredited = 0;
  double walletUsed = 0;
  int rewards = 120;
  String? trackingOrderId;

  List<WalletTransaction> transactions = const [
    WalletTransaction(label: 'Refund · Order APM30995', labelAr: 'استرداد · طلب APM30995', amount: 0.750, dateDisplay: 'Jun 18'),
    WalletTransaction(label: 'Reward · Welcome bonus', labelAr: 'مكافأة · هدية الترحيب', amount: 5.000, dateDisplay: 'Jun 10'),
    WalletTransaction(label: 'Top-up · KNET', labelAr: 'شحن · كي نت', amount: 10.000, dateDisplay: 'Jun 5'),
  ];

  Order? byId(String id) {
    try {
      return orders.firstWhere((o) => o.id == id);
    } catch (_) {
      return null;
    }
  }

  int get pendingRequestCount => orders
      .where((o) => (o.cancelRequest?.status == 'pending') || (o.returnRequest?.status == 'pending'))
      .length;

  // -------------------------------------------------------------- fetching
  Future<void> loadMyOrders(int userId) async {
    ordersLoading = true;
    ordersError = null;
    notifyListeners();
    try {
      final fetched = await _orderService.myOrders(userId);
      orders
        ..clear()
        ..addAll(fetched);
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
      final detail = await _orderService.orderDetail(code: code, userId: userId);
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
  Future<Map<String, dynamic>> _resolveOrderItem(CartLine line) async {
    var apiId = line.apiProductId;
    if (apiId == null && line.productId != null) {
      final cached = CatalogRepository.instance.findProduct(line.productId!);
      if (cached != null && cached.sku.isNotEmpty) {
        try {
          final fresh = await _catalogService.product(cached.sku);
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
  }) async {
    // Resolved concurrently rather than one at a time — with several items
    // each needing their own PDP lookup, resolving them sequentially could
    // take a very long time (each with its own network round-trip), making
    // the checkout spinner sit for a long time before anything visibly happens.
    final allLines = totals.groups.values.expand((g) => g).toList();
    final items = await Future.wait(allLines.map(_resolveOrderItem));
    final result = await _orderService.placeOrder(
      userId: userId,
      customerName: customerName,
      customerPhone: customerPhone,
      address: address,
      payment: pay,
      walletRedeem: pay == 'wallet',
      coupon: coupon,
      items: items,
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

  void reorderInto(CartState cartState, String orderId) {
    final o = byId(orderId);
    if (o == null) return;
    for (final g in o.groups) {
      for (final it in g.items) {
        if (it.productId == null) continue;
        final key = '${it.productId}_${g.pharmacy}';
        final existing = cartState.cart[key];
        if (existing != null) {
          existing.qty += it.qty;
        } else {
          cartState.cart[key] = CartLine(
            key: key,
            productId: it.productId,
            seller: g.pharmacy,
            price: it.price,
            qty: it.qty,
          );
        }
      }
    }
    cartState.cartTab = 'my';
    cartState.notifyListeners();
  }

  void startRequest(String orderId, String type, {required String reason, String note = ''}) {
    final o = byId(orderId);
    if (o == null) return;
    final req = OrderRequest(status: 'pending', reason: reason, note: note);
    if (type == 'return') {
      o.returnRequest = req;
    } else {
      o.cancelRequest = req;
    }
    notifyListeners();
  }

  void rateOrder(String orderId, int stars, {String review = ''}) {
    final o = byId(orderId);
    if (o == null) return;
    o.rating = stars;
    o.review = review;
    notifyListeners();
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
