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
  /// Confirmed live (`in_stock`) across product/cart/order/rx responses
  /// (2026-07-29). Mainly matters for the Reorder action (orders_screen.dart)
  /// — a delivered order's own items were already fulfilled regardless of
  /// whether they're in stock NOW, so this doesn't change how the order
  /// itself displays, only whether reordering a given line is offered.
  /// Defaults true so an order predating this field (or a response that
  /// simply omits it for an in-stock item) doesn't wrongly block reordering.
  final bool inStock;
  /// ✅ Confirmed live on `GET /acct/order/{code}` (2026-09-18) — needed to
  /// call `POST /app/product/{sku}/review` from here (order_detail_screen.dart's
  /// "Review this item"), a second, inherently-verified way to leave a
  /// product review: getting here at all means this item is in an order
  /// that's actually this person's own, no separate `can_review` check
  /// needed the way the PDP's own review button does.
  final String? sku;
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
    this.inStock = true,
    this.sku,
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
        inStock: asBool(json, const ['in_stock', 'stock'], fallback: true),
        sku: asStringOrNull(json, const ['sku']),
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

/// The delivery address embedded directly on `GET /acct/order/{code}`'s own
/// response — confirmed live (2026-07-31), never parsed before. This is a
/// SNAPSHOT of where the order was actually sent (worth keeping distinct
/// from [AddressState]'s current saved addresses, which can be edited or
/// deleted after the fact — this is what the order itself recorded).
class OrderAddress {
  final String name;
  final String phone;
  final String? email;
  final double? lat;
  final double? lng;
  final int? governorateId;
  final int? areaId;
  /// Confirmed live as the literal camelCase key `areaName` — NOT
  /// `area_name`/`area`/`gov`, the forms seen on other address-bearing
  /// endpoints (see Address.fromJson's own doc on that inconsistency).
  /// Every address-shaped response so far has used a different key for
  /// this same concept.
  final String areaName;
  final String block;
  final String street;
  final String building;
  final String floor;
  final String flat;

  const OrderAddress({
    required this.name,
    required this.phone,
    this.email,
    this.lat,
    this.lng,
    this.governorateId,
    this.areaId,
    this.areaName = '',
    this.block = '',
    this.street = '',
    this.building = '',
    this.floor = '',
    this.flat = '',
  });

  /// e.g. "Abu Halifa, Block sfsgf, Street tttþ, Building cbgfhfgh, Floor
  /// fgddf, Flat gf" — skips any part that's blank, same join pattern as
  /// Address.formatted elsewhere.
  String get formatted {
    final parts = <String>[
      if (areaName.trim().isNotEmpty) areaName.trim(),
      if (block.trim().isNotEmpty) 'Block ${block.trim()}',
      if (street.trim().isNotEmpty) 'Street ${street.trim()}',
      if (building.trim().isNotEmpty) 'Building ${building.trim()}',
      if (floor.trim().isNotEmpty) 'Floor ${floor.trim()}',
      if (flat.trim().isNotEmpty) 'Flat ${flat.trim()}',
    ];
    return parts.join(', ');
  }

  factory OrderAddress.fromJson(Map<String, dynamic> json) => OrderAddress(
        name: asString(json, const ['name']),
        phone: asString(json, const ['phone']),
        email: asStringOrNull(json, const ['email']),
        lat: asDoubleOrNull(json, const ['lat', 'latitude']),
        lng: asDoubleOrNull(json, const ['lng', 'longitude']),
        // A real `/acct/order/{code}` response (2026-09-18) sends
        // `governorate`/`area` as BARE NUMERIC ids — no `_id` suffix, and
        // no name string anywhere in this object at all. That's a genuine
        // ambiguity: other address-bearing responses (e.g. checkout-init's
        // `addresses[]`) use the SAME key `area` to hold an actual NAME
        // string ("Salwa"). asIntOrNull/asString can't tell these apart by
        // key name alone, so this checks the raw value's actual type
        // instead — a number means an id with no name given at all; a
        // string means a real name. Silently returning the string "12"
        // (from a naive `.toString()`) as if it were the area's NAME was
        // the actual bug this replaced — it would have shown as the
        // literal digits "12" in the delivery address instead of a place
        // name.
        governorateId: asIntOrNull(json, const ['governorate_id']) ?? (json['governorate'] is num ? (json['governorate'] as num).toInt() : null),
        areaId: asIntOrNull(json, const ['area_id']) ?? (json['area'] is num ? (json['area'] as num).toInt() : null),
        areaName: asStringOrNull(json, const ['areaName', 'area_name']) ?? (json['area'] is String ? json['area'] as String : ''),
        block: asString(json, const ['block']),
        street: asString(json, const ['street']),
        building: asString(json, const ['building']),
        floor: asString(json, const ['floor']),
        // Confirmed live typo on the real response: "appartment" (double
        // p), not "apartment" — kept as a fallback candidate alongside the
        // correctly-spelled form and "flat" in case it's ever fixed
        // server-side.
        flat: asString(json, const ['flat', 'appartment', 'apartment']),
      );
}

/// One entry in a delivered order's `building_photos[]` — confirmed live
/// on `GET /acct/order/{code}` (2026-09-18): `{ url, note, by, date }`.
/// Reference photos of the delivery location (building/entrance), likely
/// taken by the rider on a previous delivery — never parsed or shown
/// anywhere before this.
class OrderBuildingPhoto {
  final String url;
  final String? note;
  final String? by;
  final DateTime? date;
  const OrderBuildingPhoto({required this.url, this.note, this.by, this.date});

  factory OrderBuildingPhoto.fromJson(Map<String, dynamic> json) => OrderBuildingPhoto(
        url: asString(json, const ['url']),
        note: asStringOrNull(json, const ['note']),
        by: asStringOrNull(json, const ['by']),
        date: DateTime.tryParse(asString(json, const ['date'])),
      );
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
  /// that case). This is the real, authoritative item count — [itemCount]
  /// uses it directly rather than deriving one; it's genuinely an ITEM
  /// count (how many distinct items), not a quantity count (how many
  /// units total), and the API already knows the difference even when
  /// this class has to guess from a detail response's line entries.
  ///
  /// Mutable, not `final`: the detail endpoint's response has no
  /// equivalent field at all (its `items` is the line-objects array, not a
  /// number), so a detail fetch's own [Order] always parses this as null.
  /// [OrdersState._preserveLocalState] carries the list's original value
  /// forward onto the freshly-fetched detail copy — without that, opening
  /// an order's detail screen and going back would permanently replace a
  /// correct count with however many line entries the detail response
  /// happens to break the order into, which needn't be the same number.
  int? apiItemCount;
  /// ✅ Confirmed live on `GET /my-orders`: `"pharmacies": 1` — same
  /// situation as [apiItemCount] above: the list endpoint gives a bare
  /// count instead of the detail endpoint's actual per-pharmacy [groups]
  /// array. Mutable for the same reason as [apiItemCount] — see its doc.
  int? apiPharmacyCount;
  /// Confirmed live (2026-07-31): `delivery_charge` and top-level
  /// `discount` — neither was parsed before, so the order total (which
  /// already includes both) had no breakdown to show alongside it. Only
  /// on the detail endpoint, same situation as [apiItemCount] — mutable so
  /// [OrdersState._preserveLocalState] can carry them forward across a
  /// list re-fetch, which would otherwise wipe them back to 0.
  double deliveryCharge;
  double discount;
  /// Confirmed live — a direct signal for whether ANY cancel/return
  /// request is currently pending on this order, distinct from
  /// [cancelRequests]/[returnRequests] (the actual per-request list, only
  /// populated once those are separately fetched/submitted this session).
  /// Not yet used to change any display logic — just captured for now.
  /// Detail-only, mutable for the same reason as above.
  bool hasPendingCancel;
  bool hasPendingReturn;
  /// Confirmed live as `"unpaid"`/presumably `"paid"` on the detail
  /// endpoint — a payment STATUS, not a payment METHOD like [pay] (knet/
  /// card/wallet/cod) claims to hold. The same JSON key (`payment`) is used
  /// for both concepts depending on which endpoint sends it (or possibly
  /// this detail endpoint simply doesn't expose the method at all) — kept
  /// as its own field rather than overloading [pay], which nothing
  /// currently displays but shouldn't be fed a status string regardless.
  /// Detail-only, mutable for the same reason as above.
  String? paymentStatus;
  /// The delivery address embedded directly on `GET /acct/order/{code}`'s
  /// response (confirmed live, 2026-07-31) — see [OrderAddress]'s own doc.
  /// Null on the list endpoint's lighter shape, which doesn't include this
  /// — mutable for the same reason as above.
  OrderAddress? deliveryAddress;
  List<OrderBuildingPhoto> buildingPhotos;

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
    this.deliveryCharge = 0,
    this.discount = 0,
    this.hasPendingCancel = false,
    this.hasPendingReturn = false,
    this.paymentStatus,
    this.deliveryAddress,
    this.buildingPhotos = const [],
  })  : cancelRequests = cancelRequests ?? [],
        returnRequests = returnRequests ?? [];

  List<OrderItemLine> get allItems => groups.expand((g) => g.items).toList();

  /// Confirmed live as `payment_method`/`payment_type` on the order detail
  /// endpoint (2026-07-31) — same short codes checkout_screen.dart already
  /// uses when placing an order (knet/card/wallet/cod), formatted for
  /// display here rather than showing the raw code.
  /// Was a plain `switch` with `default: return 'Cash on delivery'` — a
  /// real order (2026-09-18) has `payment_method: "go_tap"` (a real
  /// payment gateway/POS provider, GoTap), which fell straight into that
  /// default and showed "Cash on delivery" for an order that was actually
  /// paid online (`payment: "paid"` on that same response). Confirmed,
  /// actively misleading — showing 'go_tap' as a real button as a real
  /// case now, and any OTHER unrecognized value shows its own raw name
  /// (title-cased) instead of defaulting to a specific, possibly-wrong
  /// claim like that. Also now localized — this whole screen otherwise
  /// is, and a hardcoded English label here was the one inconsistency.
  String payLabel(bool ar) {
    switch (pay) {
      case 'knet':
        return 'KNET';
      case 'card':
        return ar ? 'بطاقة' : 'Card';
      case 'wallet':
        return ar ? 'المحفظة' : 'Wallet';
      case 'go_tap':
        return 'GoTap';
      case 'cod':
        return ar ? 'الدفع عند الاستلام' : 'Cash on delivery';
      default:
        return pay.isEmpty ? (ar ? 'الدفع عند الاستلام' : 'Cash on delivery') : pay[0].toUpperCase() + pay.substring(1).replaceAll('_', ' ');
    }
  }

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

  /// The API's own item count — not something derived from summing line
  /// quantities, which conflates "how many distinct items" with "how many
  /// units total" (an order of 8 units of ONE product is 1 item, not 8).
  /// [allItems.length] (a plain count of line entries, still not a
  /// quantity sum) is only a last resort for the rare case where no API
  /// count is known at all — e.g. an order somehow viewed on its detail
  /// screen without ever having come from the list first.
  int get itemCount => apiItemCount ?? allItems.length;

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
      pay: asString(json, const ['payment_method', 'payment_type', 'pay'], fallback: 'cod'),
      status: _normalizeStatus(raw),
      rawStatus: raw,
      groups: groups,
      // Only meaningful when `items` is actually a bare number (the list
      // endpoint's shape) — when it's the detail endpoint's array of line
      // objects instead, that's already been consumed above into `groups`.
      apiItemCount: (json['items'] is num) ? (json['items'] as num).toInt() : null,
      apiPharmacyCount: (json['pharmacies'] is num) ? (json['pharmacies'] as num).toInt() : null,
      insuranceCover: asDouble(json, const ['insurance_cover']),
      deliveryCharge: asDouble(json, const ['delivery_charge', 'delivery_fee']),
      discount: asDouble(json, const ['discount']),
      hasPendingCancel: asBool(json, const ['has_pending_cancel']),
      hasPendingReturn: asBool(json, const ['has_pending_return']),
      paymentStatus: asStringOrNull(json, const ['payment_status']) ?? (json['payment'] is String && (json['payment'] == 'paid' || json['payment'] == 'unpaid') ? json['payment'] as String : null),
      deliveryAddress: (json['address'] is Map) ? OrderAddress.fromJson((json['address'] as Map).cast<String, dynamic>()) : null,
      buildingPhotos: asList(json, const ['building_photos']).map((e) => OrderBuildingPhoto.fromJson(e as Map<String, dynamic>)).toList(),
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
  /// Confirmed live (2026-07-30): nested under a `driver` object
  /// (`{id, name, phone, vehicle_type, plate_number}`), not flat
  /// `rider_phone`/`driver_phone` fields on the root — those never
  /// existed, which is why "Call rider" could never actually place a call
  /// before this (see track_screen.dart's `_callRider`, which already had
  /// the real `tel:` dialing logic ready and waiting on this).
  final String? riderPhone;
  final String? vehicleType;
  final String? plateNumber;
  final String? eta;
  final double? lat;
  final double? lng;

  const TrackInfo({
    required this.code,
    required this.status,
    required this.rawStatus,
    this.riderName,
    this.riderPhone,
    this.vehicleType,
    this.plateNumber,
    this.eta,
    this.lat,
    this.lng,
  });

  factory TrackInfo.fromJson(Map<String, dynamic> json) {
    final raw = asString(json, const ['status']);
    final driver = (json['driver'] is Map) ? (json['driver'] as Map).cast<String, dynamic>() : const <String, dynamic>{};
    return TrackInfo(
      code: asString(json, const ['code']),
      status: Order._normalizeStatus(raw),
      rawStatus: raw,
      riderName: asStringOrNull(driver, const ['name']),
      riderPhone: asStringOrNull(driver, const ['phone']),
      vehicleType: asStringOrNull(driver, const ['vehicle_type']),
      plateNumber: asStringOrNull(driver, const ['plate_number']),
      eta: asStringOrNull(json, const ['eta']),
      lat: asDoubleOrNull(json, const ['lat', 'latitude']),
      lng: asDoubleOrNull(json, const ['lng', 'longitude']),
    );
  }
}
