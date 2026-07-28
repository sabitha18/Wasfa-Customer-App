import 'dart:io';
import '../../core/network/api_client.dart';
import '../../core/network/api_config.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/json_utils.dart';
import '../models/address.dart';
import '../models/order.dart';

class OrderService {
  OrderService._();
  static final OrderService instance = OrderService._();
  final ApiClient _client = ApiClient.instance;

  /// Places an order. [items] is `[{id: sellerProductId, qty: n}, ...]` —
  /// the `id` must be the *seller's* product_id from the PDP, not the
  /// catalog product id (see [ApiConfig] notes on `/orders`).
  ///
  /// ✅ [deliveryDate]/[deliverySlot]/`device` are confirmed live in the
  /// Postman collection's "Place order" example (`delivery_date`,
  /// `delivery_slot`, `device`) — these were missing from this method
  /// entirely before, meaning every order placed through this app never
  /// sent a chosen delivery date/slot at all, regardless of what the
  /// checkout screen's own ASAP/Scheduled + calendar + slot-time UI had
  /// the person pick. [deliverySlot] is only sent when set — the confirmed
  /// example only shows the "Scheduled" case; whether/what value ASAP
  /// orders should send for this field isn't confirmed, so it's omitted
  /// rather than guessed for that case. Flag this with the backend team.
  Future<PlaceOrderResult> placeOrder({
    required int userId,
    required String customerName,
    required String customerPhone,
    required Address address,
    required String payment, // cod | knet | wallet
    bool walletRedeem = false,
    String coupon = '',
    required List<Map<String, dynamic>> items,
    String? deliveryDate, // 'yyyy-MM-dd'
    int? deliverySlot,
    // Device GPS position at the time of ordering — sent alongside the
    // structured address (not instead of it) so the rider has the exact
    // pin location regardless of which saved address the order used. Field
    // names ('lat'/'lng') are a best guess and NOT confirmed with backend
    // yet — flag this if the order-placement Postman example doesn't show
    // these being accepted/stored.
    double? latitude,
    double? longitude,
  }) async {
    // The server's `payment` enum is strictly cod|knet|wallet. The checkout UI
    // also offers a "Card" option — Kuwait card payments run through the KNET
    // gateway, so map it to `knet` here rather than sending an invalid value
    // that the server rejects. Anything unexpected also falls back to `knet`.
    const validPayments = {'cod', 'knet', 'wallet'};
    final normalizedPayment = validPayments.contains(payment) ? payment : 'knet';
    final res = await withFallbackMessage(
          () => _client.post(ApiConfig.orders, body: {
        'user_id': userId,
        'customer': {'name': customerName, 'phone': customerPhone},
        'address': {
          'governorate_id': address.governorateId,
          'area_id': address.areaId,
          'block': address.block,
          'street': address.street,
          'building': address.building,
          'floor': address.floor,
          'flat': address.apt,
          'note': '',
          if (latitude != null) 'lat': latitude,
          if (longitude != null) 'lng': longitude,
        },
        if (deliveryDate != null && deliveryDate.isNotEmpty) 'delivery_date': deliveryDate,
        if (deliverySlot != null) 'delivery_slot': deliverySlot,
        'device': Platform.isIOS ? 'ios' : 'android',
        'payment': normalizedPayment,
        'wallet_redeem': walletRedeem,
        'coupon': coupon,
        'items': items,
      }),
      'Couldn\'t place your order. Please try again.',
    );
    return PlaceOrderResult.fromJson(res as Map<String, dynamic>);
  }

  /// `GET /track?code=&mobile=`.
  ///
  /// ⚠ Not documented in the Postman collection (it only shows `code`), but
  /// confirmed live via logcat: without a mobile number the endpoint returns
  /// `{ ok:false, msg:"Enter your order code and mobile number" }`. Sending
  /// both `mobile` and `phone` since the exact key wasn't confirmed either —
  /// harmless if the backend only reads one of them.
  Future<TrackInfo> track(String code, {required String mobile}) async {
    final res = await _client.get(ApiConfig.track, query: {'code': code, 'mobile': mobile, 'phone': mobile});
    return TrackInfo.fromJson(res as Map<String, dynamic>);
  }

  Future<List<Order>> myOrders(int userId) async {
    final res = await _client.get(ApiConfig.myOrders, query: {'user_id': userId});
    final list = (res is Map ? res['orders'] ?? res['data'] ?? res['items'] : null) ?? (res is List ? res : const []);
    return (list as List).map((e) => Order.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Order> orderDetail({required String code, required int userId}) async {
    final res = await _client.get(ApiConfig.acctOrder(code), query: {'user_id': userId});
    final map = (res is Map && res['order'] is Map) ? res['order'] as Map<String, dynamic> : res as Map<String, dynamic>;
    return Order.fromJson(map);
  }

  /// `GET /return-reasons?type=cancel|return` — ✅ confirmed live:
  /// `[{"id":1,"reason":"...","type":"both"}]`. Already parses correctly
  /// (the label key really is `reason`, already in the fallback list).
  Future<List<Reason>> returnReasons(String type) async {
    final res = await _client.get(ApiConfig.returnReasons, query: {'type': type});
    final list = (res is Map ? res['reasons'] ?? res['data'] ?? res['items'] : null) ?? (res is List ? res : const []);
    return (list as List).map((e) => Reason.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// `POST /orders/{code}/cancel` — ✅ confirmed live (2026-07-27) as
  /// `multipart/form-data` (NOT JSON — this changed from an earlier
  /// confirmed version that was JSON): `user_id`, `reason_id`, `note`,
  /// `detail_ids[0]`, `detail_ids[1]`, ... (bracket-indexed, same style as
  /// [returnOrder]), and `qty[<detail_id>]` per item — e.g. `qty[137]=2`.
  /// [detailIds] must be the order line's own row id
  /// ([OrderItemLine.detailId]), not a product id. `qty[<detail_id>]` was
  /// an unconfirmed guess before — now proven correct against a real
  /// response (`{"ok": true}`) in the confirmed Postman example.
  Future<void> cancelOrder({
    required String code,
    required int userId,
    required int reasonId,
    String note = '',
    required List<int> detailIds,
    Map<int, int>? qtyByDetailId,
  }) async {
    final fields = <String, String>{
      'user_id': userId.toString(),
      'reason_id': reasonId.toString(),
      'note': note,
    };
    for (var i = 0; i < detailIds.length; i++) {
      fields['detail_ids[$i]'] = detailIds[i].toString();
    }
    if (qtyByDetailId != null) {
      for (final e in qtyByDetailId.entries) {
        fields['qty[${e.key}]'] = e.value.toString();
      }
    }
    await withFallbackMessage(
      () => _client.postMultipart(ApiConfig.orderCancel(code), fields: fields),
      "Couldn't submit your cancellation request. Please try again.",
    );
  }

  /// `POST /orders/{code}/return` — ✅ confirmed live, but as
  /// `multipart/form-data` (not JSON) since it carries an optional image
  /// file — matches the collection's form-data fields exactly, including
  /// the repeated `detail_ids[0]`, `detail_ids[1]`, ... shape.
  /// [qtyByDetailId]'s `qty[<detail_id>]` field name is now confirmed
  /// correct for [cancelOrder] (2026-07-27, real `{"ok":true}` response) —
  /// return isn't separately confirmed in that same example, but almost
  /// certainly follows the same convention since it's the same backend.
  Future<void> returnOrder({
    required String code,
    required int userId,
    required int reasonId,
    String note = '',
    required List<int> detailIds,
    Map<int, int>? qtyByDetailId,
    String? imagePath,
  }) async {
    final fields = <String, String>{
      'user_id': userId.toString(),
      'reason_id': reasonId.toString(),
      'note': note,
    };
    for (var i = 0; i < detailIds.length; i++) {
      fields['detail_ids[$i]'] = detailIds[i].toString();
    }
    if (qtyByDetailId != null) {
      for (final e in qtyByDetailId.entries) {
        fields['qty[${e.key}]'] = e.value.toString();
      }
    }
    await withFallbackMessage(
      () => _client.postMultipart(ApiConfig.orderReturn(code), fields: fields, filePath: imagePath),
      "Couldn't submit your return request. Please try again.",
    );
  }

  /// `POST /orders/{code}/rate` — ✅ confirmed live:
  /// `{ user_id, rating, review }`.
  Future<void> rateOrder({required String code, required int userId, required int rating, String review = ''}) async {
    await withFallbackMessage(
      () => _client.post(ApiConfig.orderRate(code), body: {
        'user_id': userId,
        'rating': rating,
        'review': review,
      }),
      "Couldn't submit your rating. Please try again.",
    );
  }

  /// `GET /acct/my-requests?user_id=` — ✅ confirmed live; response shape
  /// wasn't confirmed (no saved example), so this parses defensively.
  /// Each entry needs its own order code + type (cancel/return) since one
  /// call covers every request across every order.
  /// `GET /acct/my-requests?user_id=` — ✅ confirmed live response:
  /// `[{ type, code, amount, reason, status (numeric), status_label,
  /// refunded, date }]` — a flat array, no wrapper. Notably: `status` is a
  /// bare number with no confirmed mapping (so [OrderRequest.status] is
  /// derived from [statusLabel]'s text instead), there's no line-item
  /// breakdown at all (no `items`/`details`), and `reason` already has any
  /// custom note appended to it server-side (e.g. "Ordered by mistake —
  /// hfghfghf") rather than sending note separately.
  Future<List<({String orderCode, String type, OrderRequest request})>> myRequests(int userId) async {
    final res = await _client.get(ApiConfig.acctMyRequests, query: {'user_id': userId});
    final list = (res is Map ? res['requests'] ?? res['data'] ?? res['items'] : null) ?? (res is List ? res : const []);
    final out = <({String orderCode, String type, OrderRequest request})>[];
    for (final e in (list as List)) {
      if (e is! Map) continue;
      final json = e as Map<String, dynamic>;
      final orderCode = asString(json, const ['code', 'order_id', 'order_code']);
      final type = asString(json, const ['type'], fallback: 'cancel');
      final statusLabel = asString(json, const ['status_label'], fallback: 'Pending');
      final req = OrderRequest(
        status: _normalizeStatus(statusLabel),
        statusLabel: statusLabel,
        reasonId: asIntOrNull(json, const ['reason_id']),
        reason: asString(json, const ['reason', 'reason_label']),
        note: asString(json, const ['note']),
        amount: asDoubleOrNull(json, const ['amount']),
        refunded: asBool(json, const ['refunded']),
        items: asList(json, const ['items', 'details']).map((it) => OrderItemLine.fromJson(it as Map<String, dynamic>)).toList(),
        ts: DateTime.tryParse(asString(json, const ['date'])) ?? DateTime.now(),
      );
      out.add((orderCode: orderCode, type: type, request: req));
    }
    return out;
  }

  /// Best-effort color category from the server's human-readable status
  /// text — safer than trusting the unconfirmed numeric `status` code.
  String _normalizeStatus(String label) {
    final l = label.toLowerCase();
    if (l.contains('approv') || l.contains('accept')) return 'approved';
    if (l.contains('reject') || l.contains('declin') || l.contains('denied')) return 'rejected';
    return 'pending';
  }
}
