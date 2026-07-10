import '../../core/utils/json_utils.dart';

class OrderItemLine {
  final int? productId;
  final String name;
  final int qty;
  final double price;
  const OrderItemLine({this.productId, this.name = '', required this.qty, required this.price});

  factory OrderItemLine.fromJson(Map<String, dynamic> json) => OrderItemLine(
        productId: asIntOrNull(json, const ['product_id', 'id']),
        name: asString(json, const ['name']),
        qty: asInt(json, const ['qty'], fallback: 1),
        price: asDouble(json, const ['price']),
      );
}

class OrderGroup {
  final String pharmacy;
  final List<OrderItemLine> items;
  const OrderGroup({required this.pharmacy, required this.items});

  factory OrderGroup.fromJson(Map<String, dynamic> json) => OrderGroup(
        pharmacy: asString(json, const ['pharmacy', 'seller', 'pharmacy_name']),
        items: asList(json, const ['items']).map((e) => OrderItemLine.fromJson(e as Map<String, dynamic>)).toList(),
      );
}

class OrderRequest {
  String status; // pending, approved, rejected
  String reason;
  String note;
  DateTime ts;
  OrderRequest({this.status = 'pending', this.reason = '', this.note = '', DateTime? ts})
      : ts = ts ?? DateTime.now();
}

class Order {
  /// Order code from the backend, e.g. "APM30995" — used as the primary key
  /// everywhere (`/track?code=`, `/acct/order/{code}`).
  final String id;
  final DateTime ts;
  final double total;
  final String pay; // knet, card, wallet, cod
  String status; // prep, way, done — normalized from whatever the server sends
  final String rawStatus; // server's own status string, for display if needed
  final List<OrderGroup> groups;
  int? rating;
  String? review;
  OrderRequest? cancelRequest;
  OrderRequest? returnRequest;
  final double insuranceCover;

  Order({
    required this.id,
    required this.ts,
    required this.total,
    required this.pay,
    this.status = 'prep',
    this.rawStatus = '',
    required this.groups,
    this.rating,
    this.review,
    this.cancelRequest,
    this.returnRequest,
    this.insuranceCover = 0,
  });

  int get itemCount =>
      groups.fold(0, (sum, g) => sum + g.items.fold(0, (s, i) => s + i.qty));

  static String _normalizeStatus(String raw) {
    final s = raw.toLowerCase();
    if (['done', 'delivered', 'completed', 'complete'].contains(s)) return 'done';
    if (['way', 'out_for_delivery', 'on_the_way', 'shipping', 'dispatched'].contains(s)) return 'way';
    return 'prep';
  }

  /// From `GET /my-orders` list items or `GET /acct/order/{code}` detail.
  /// NOTE: field names are inferred (not documented in the collection) —
  /// confirm against a real response the same way the Rider app's order
  /// shapes were confirmed, then trim the candidate-key lists below.
  factory Order.fromJson(Map<String, dynamic> json) {
    final raw = asString(json, const ['status']);
    return Order(
      id: asString(json, const ['code', 'id']),
      ts: DateTime.tryParse(asString(json, const ['created_at', 'date', 'ts'])) ?? DateTime.now(),
      total: asDouble(json, const ['total']),
      pay: asString(json, const ['payment', 'pay'], fallback: 'cod'),
      status: _normalizeStatus(raw),
      rawStatus: raw,
      groups: asList(json, const ['groups']).map((e) => OrderGroup.fromJson(e as Map<String, dynamic>)).toList(),
      insuranceCover: asDouble(json, const ['insurance_cover']),
    );
  }
}

/// From `POST /orders` success: `{ ok:true, coId, code, total }`.
class PlaceOrderResult {
  final int? coId;
  final String code;
  final double total;
  const PlaceOrderResult({this.coId, required this.code, required this.total});

  factory PlaceOrderResult.fromJson(Map<String, dynamic> json) => PlaceOrderResult(
        coId: asIntOrNull(json, const ['coId']),
        code: asString(json, const ['code']),
        total: asDouble(json, const ['total']),
      );
}

/// From `GET /track?code=`.
class TrackInfo {
  final String code;
  final String status;
  final String rawStatus;
  final String? riderName;
  final String? eta;
  final double? lat;
  final double? lng;

  const TrackInfo({
    required this.code,
    required this.status,
    required this.rawStatus,
    this.riderName,
    this.eta,
    this.lat,
    this.lng,
  });

  factory TrackInfo.fromJson(Map<String, dynamic> json) {
    final raw = asString(json, const ['status']);
    return TrackInfo(
      code: asString(json, const ['code']),
      status: Order._normalizeStatus(raw),
      rawStatus: raw,
      riderName: asStringOrNull(json, const ['rider_name', 'driver_name']),
      eta: asStringOrNull(json, const ['eta']),
      lat: asDoubleOrNull(json, const ['lat', 'latitude']),
      lng: asDoubleOrNull(json, const ['lng', 'longitude']),
    );
  }
}
