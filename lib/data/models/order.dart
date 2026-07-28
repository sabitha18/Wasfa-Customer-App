import '../../core/utils/json_utils.dart';

class OrderItemLine {
  final int? productId;
  /// The order line's own row id — this, not [productId], is what
  /// `/orders/{code}/cancel` and `/return` want in `detail_ids[]` (confirmed
  /// in the updated Postman collection). Previously conflated with
  /// [productId] by treating a bare `id` as a product-id fallback, which
  /// would have sent the wrong id to those endpoints.
  final int? detailId;
  final String name;
  final int qty;
  final double price;
  /// Confirmed live on `GET /acct/order/{code}`'s `items[]` — a real
  /// product photo URL (`image`). Was never parsed at all before, so the
  /// detail screen had nothing to show but a generic package emoji for
  /// every single line, regardless of whether the API actually had a
  /// photo for it.
  final String? imageUrl;
  /// Confirmed live on the same response — each ITEM carries its own
  /// `pharmacy_name` (e.g. "Royal Pharmacy"), not just something sitting
  /// once at the top of the whole order. [OrderGroup.fromJson]'s flat-item
  /// fallback used to look for a top-level `pharmacy`/`pharmacy_name` key
  /// on the *order* object itself, which this response shape doesn't have
  /// at all — so the group heading rendered blank. See [Order.fromJson]
  /// for how this is now used to actually group flat items by pharmacy.
  final String pharmacyName;
  /// ✅ Confirmed live on `GET /acct/order/{code}` (2026-07-24) — the
  /// per-line status the earlier version of this app had no way to see at
  /// all, so "already requested" tracking was purely client-side/in-memory
  /// and didn't survive an app restart. These now let [Order.remainingFor]
  /// treat the SERVER as the source of truth instead.
  final String? itemStatus; // e.g. "pending" — this line's own fulfillment status, separate from the order-level `status`
  final bool cancelRequested;
  final String? cancelStatus; // e.g. "pending"/"approved"/"rejected" — null if cancelRequested is false
  final bool returnRequested;
  final String? returnStatus;
  final int returnQty;
  /// Not currently confirmed in any saved `/acct/order/{code}` example (the
  /// field IS confirmed on the equivalent Rx item shape as `is_restricted`
  /// — see [RxItem.restricted]), but this is the same underlying concept
  /// (pickup-only, can't be added to cart/reordered) so it's parsed the
  /// same way as a best-effort guess pending a confirmed order-item
  /// example that actually has a restricted item in it.
  final bool restricted;
  const OrderItemLine({
    this.productId,
    this.detailId,
    this.name = '',
    required this.qty,
    required this.price,
    this.imageUrl,
    this.pharmacyName = '',
    this.itemStatus,
    this.cancelRequested = false,
    this.cancelStatus,
    this.returnRequested = false,
    this.returnStatus,
    this.returnQty = 0,
    this.restricted = false,
  });

  factory OrderItemLine.fromJson(Map<String, dynamic> json) => OrderItemLine(
        productId: asIntOrNull(json, const ['product_id', 'seller_product_id']),
        detailId: asIntOrNull(json, const ['id', 'detail_id']),
        name: asString(json, const ['name', 'product_name', 'title']),
        qty: asInt(json, const ['qty', 'quantity', 'qnty'], fallback: 1),
        // Unit price first; fall back to a line total only if no unit price is
        // sent (the detail screen multiplies price × qty for the line figure).
        price: asDouble(json, const ['price', 'unit_price', 'unit', 'line_total', 'total']),
        imageUrl: asStringOrNull(json, const ['image', 'image_url', 'photo']),
        pharmacyName: asString(json, const ['pharmacy_name', 'seller', 'seller_name', 'store', 'store_name']),
        itemStatus: asStringOrNull(json, const ['item_status']),
        cancelRequested: asBool(json, const ['cancel_requested']),
        cancelStatus: asStringOrNull(json, const ['cancel_status']),
        returnRequested: asBool(json, const ['return_requested']),
        returnStatus: asStringOrNull(json, const ['return_status']),
        returnQty: asInt(json, const ['return_qty'], fallback: 0),
        restricted: asBool(json, const ['restricted', 'is_restricted', 'pickup_only']),
      );
}

class OrderGroup {
  final String pharmacy;
  final List<OrderItemLine> items;
  const OrderGroup({required this.pharmacy, required this.items});

  factory OrderGroup.fromJson(Map<String, dynamic> json) => OrderGroup(
        pharmacy: asString(json, const ['pharmacy', 'seller', 'pharmacy_name', 'seller_name', 'store', 'store_name']),
        items: asList(json, const ['items', 'lines', 'products', 'order_items'])
            .map((e) => OrderItemLine.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// One entry from `GET /return-reasons?type=cancel|return`.
/// ✅ Confirmed live response: `[{"id":1,"reason":"...","type":"both"}]` —
/// the label key really is `reason`, already covered by the fallback list.
class Reason {
  final int id;
  final String label;
  const Reason({required this.id, required this.label});
  factory Reason.fromJson(Map<String, dynamic> json) => Reason(
        id: asInt(json, const ['id']),
        label: asString(json, const ['label', 'name', 'reason', 'title']),
      );
}

class OrderRequest {
  /// Normalized category derived from [statusLabel] — 'pending'/'approved'/
  /// 'rejected' — used only to pick a badge color. The real response sends
  /// `status` as a bare numeric code (e.g. `0`) with no confirmed mapping,
  /// so this is derived by keyword-matching [statusLabel] instead of
  /// trusting an unconfirmed number.
  String status;
  /// The actual human-readable status text from the server (e.g.
  /// "Pending") — confirmed live as `status_label`. Show this directly
  /// rather than re-deriving English wording from [status].
  String statusLabel;
  /// Numeric id from [Reason] — this, not [reason] (the display text), is
  /// what `/orders/{code}/cancel`/`/return` actually want as `reason_id`.
  int? reasonId;
  String reason;
  String note;
  /// Order amount tied to this request — confirmed live as `amount`.
  /// `/acct/my-requests` doesn't send a line-item breakdown at all (no
  /// `items`/`details` array), so this is the only concrete figure
  /// available to show on that screen.
  double? amount;
  bool refunded;
  DateTime ts;
  /// Which line items this request covers — only ever populated locally
  /// right after submitting (from the request flow's checkbox selection);
  /// `/acct/my-requests` itself doesn't return a per-item breakdown.
  List<OrderItemLine> items;
  OrderRequest({this.status = 'pending', this.statusLabel = 'Pending', this.reasonId, this.reason = '', this.note = '', this.amount, this.refunded = false, this.items = const [], DateTime? ts})
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
  /// A person can submit a cancel/return request for a SUBSET of an order's
  /// items, then come back later and request the rest — each submission is
  /// its own [OrderRequest] with its own `items`. This is a list (not a
  /// single nullable request) specifically to support that: "cancel 2 of 5
  /// items now" shouldn't block requesting the remaining 3 later, and the
  /// "Cancel order"/"Return / Refund request" button needs to stay usable
  /// until every item has been covered by SOME request, not disappear after
  /// the first partial one.
  List<OrderRequest> cancelRequests;
  List<OrderRequest> returnRequests;
  final double insuranceCover;
  /// ✅ Confirmed live on `GET /my-orders` (the ORDER LIST — not detail):
  /// `items` there is a bare integer count (e.g. `"items": 1`), completely
  /// different in shape from the detail endpoint's `items` (a full array
  /// of line objects that this SAME model also parses into [groups] for
  /// that case). Since this class is shared between both responses, and
  /// the list response has no groups/line-items to actually sum a real
  /// quantity from, [itemCount] used to always compute 0 for any order
  /// loaded via the list endpoint — this holds that raw count as a
  /// fallback for exactly that case.
  final int? apiItemCount;
  /// ✅ Confirmed live on `GET /my-orders`: `"pharmacies": 1` — same
  /// situation as [apiItemCount] above: the list endpoint gives a bare
  /// count instead of the detail endpoint's actual per-pharmacy [groups]
  /// array, so `groups.length` alone can't tell how many pharmacies an
  /// order loaded via the list endpoint actually has.
  final int? apiPharmacyCount;

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
    this.apiItemCount,
    this.apiPharmacyCount,
    List<OrderRequest>? cancelRequests,
    List<OrderRequest>? returnRequests,
    this.insuranceCover = 0,
  })  : cancelRequests = cancelRequests ?? [],
        returnRequests = returnRequests ?? [];

  List<OrderItemLine> get allItems => groups.expand((g) => g.items).toList();

  /// Items from [allItems] not yet covered by ANY request in [requests] —
  /// matched by [OrderItemLine.detailId], the item's own stable row id.
  /// An item with no detailId at all (shouldn't normally happen, but data
  /// can be messy) is always treated as still-remaining rather than being
  /// silently un-requestable forever.
  ///
  /// [it.cancelRequested]/[it.returnRequested] (confirmed live on
  /// `GET /acct/order/{code}` as of 2026-07-24) are checked FIRST and are
  /// authoritative — they come straight from the server, so they're
  /// correct even after an app restart. [requests] (the client-side,
  /// in-memory list built right after a successful submit) is only an
  /// optimistic overlay for the moment between submitting and the next
  /// re-fetch, in case that re-fetch hasn't happened yet.
  List<OrderItemLine> _remaining(List<OrderRequest> requests, {required bool isReturn}) {
    final coveredIds = requests.expand((r) => r.items).map((it) => it.detailId).whereType<int>().toSet();
    return allItems.where((it) {
      final serverCovered = isReturn ? it.returnRequested : it.cancelRequested;
      if (serverCovered) return false;
      if (it.detailId != null && coveredIds.contains(it.detailId)) return false;
      return true;
    }).toList();
  }

  List<OrderItemLine> get remainingForCancel => _remaining(cancelRequests, isReturn: false);
  List<OrderItemLine> get remainingForReturn => _remaining(returnRequests, isReturn: true);

  /// Groups items that have an active cancel/return request by their
  /// status (e.g. "pending"/"approved"/"rejected"), for the detail
  /// screen's banners. Merges two sources so this is both durable AND
  /// immediate:
  /// - Server-confirmed per-item `cancel_requested`/`cancel_status`/
  ///   `return_requested`/`return_status` fields — survive an app restart.
  /// - [cancelRequests]/[returnRequests] (this session's local, optimistic
  ///   state right after a successful submit) — covers the gap between
  ///   submitting and the next time this order gets re-fetched, so the
  ///   banner doesn't lag a beat behind the button disappearing.
  /// Items already counted from the server are not double-counted from the
  /// local list.
  Map<String, List<OrderItemLine>> _statusGroups(List<OrderRequest> localRequests, {required bool isReturn}) {
    final map = <String, List<OrderItemLine>>{};
    final coveredIds = <int>{};
    for (final it in allItems) {
      final requested = isReturn ? it.returnRequested : it.cancelRequested;
      if (!requested) continue;
      final status = (isReturn ? it.returnStatus : it.cancelStatus) ?? 'pending';
      map.putIfAbsent(status, () => []).add(it);
      if (it.detailId != null) coveredIds.add(it.detailId!);
    }
    for (final req in localRequests) {
      for (final it in req.items) {
        if (it.detailId != null && coveredIds.contains(it.detailId)) continue; // already reflected server-side
        map.putIfAbsent('pending', () => []).add(it);
      }
    }
    return map;
  }

  Map<String, List<OrderItemLine>> get cancelStatusGroups => _statusGroups(cancelRequests, isReturn: false);
  Map<String, List<OrderItemLine>> get returnStatusGroups => _statusGroups(returnRequests, isReturn: true);

  int get itemCount {
    final summed = groups.fold(0, (sum, g) => sum + g.items.fold(0, (s, i) => s + i.qty));
    return summed > 0 ? summed : (apiItemCount ?? 0);
  }

  int get pharmacyCount => groups.isNotEmpty ? groups.length : (apiPharmacyCount ?? 0);

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
    // Preferred shape: line items already split into per-pharmacy `groups`.
    var groups = asList(json, const ['groups'])
        .map((e) => OrderGroup.fromJson(e as Map<String, dynamic>))
        .toList();
    // Fallback: some responses (esp. `/acct/order/{code}`) return a single
    // flat items list at the top level with no grouping — build groups from
    // each item's OWN `pharmacy_name` instead of looking for one top-level
    // `pharmacy` field on the order (this response shape has no such field
    // at all — every item carries its own `pharmacy_name` instead — so that
    // lookup used to always come back empty and the group heading rendered
    // blank). Preserves first-seen order of pharmacies rather than sorting.
    if (groups.isEmpty) {
      final flat = asList(json, const ['items', 'lines', 'products', 'order_items'])
          .map((e) => OrderItemLine.fromJson(e as Map<String, dynamic>))
          .toList();
      if (flat.isNotEmpty) {
        final byPharmacy = <String, List<OrderItemLine>>{};
        for (final item in flat) {
          byPharmacy.putIfAbsent(item.pharmacyName, () => []).add(item);
        }
        groups = byPharmacy.entries.map((e) => OrderGroup(pharmacy: e.key, items: e.value)).toList();
      }
    }
    return Order(
      id: asString(json, const ['code', 'id']),
      ts: DateTime.tryParse(asString(json, const ['created_at', 'date', 'ts'])) ?? DateTime.now(),
      total: asDouble(json, const ['total']),
      pay: asString(json, const ['payment', 'pay'], fallback: 'cod'),
      status: _normalizeStatus(raw),
      rawStatus: raw,
      groups: groups,
      // Only meaningful when `items` is actually a bare number (the list
      // endpoint's shape) — when it's the detail endpoint's array of line
      // objects instead, that's already been consumed above into `groups`.
      apiItemCount: (json['items'] is num) ? (json['items'] as num).toInt() : null,
      apiPharmacyCount: (json['pharmacies'] is num) ? (json['pharmacies'] as num).toInt() : null,
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
  /// Field name is an unconfirmed guess (`rider_phone`/`driver_phone`) —
  /// confirm against a real response once an order actually has a rider
  /// assigned. Needed so "Call rider" can place a real call instead of
  /// just showing a "Calling rider…" toast that doesn't call anyone.
  final String? riderPhone;
  final String? eta;
  final double? lat;
  final double? lng;

  const TrackInfo({
    required this.code,
    required this.status,
    required this.rawStatus,
    this.riderName,
    this.riderPhone,
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
      riderPhone: asStringOrNull(json, const ['rider_phone', 'driver_phone']),
      eta: asStringOrNull(json, const ['eta']),
      lat: asDoubleOrNull(json, const ['lat', 'latitude']),
      lng: asDoubleOrNull(json, const ['lng', 'longitude']),
    );
  }
}
