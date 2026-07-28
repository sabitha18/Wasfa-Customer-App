import '../../core/utils/json_utils.dart';
import 'seller.dart';

class RxItem {
  /// This item's own id within the prescription — confirmed needed by
  /// `POST /app/acct/rx/add-to-cart`'s `item_ids[]` array (e.g. `item_ids[0]=27`).
  /// Not the same thing as the prescription's own [Prescription.id].
  final String id;
  final String name;
  final String nameAr;
  final String emoji;
  /// Confirmed live field (`image`) — a real product photo URL. Falls back
  /// to [emoji] when absent, same pattern as [Product.imageUrl].
  final String? imageUrl;
  final String dosage;
  final String dosageAr;
  final bool refillable;
  String? refillStatus; // null | 'pending'
  /// Per-item note/instruction from the doctor — separate from [dosage]
  /// (which is the composed dosage/dose_time/duration line). ✅ Confirmed
  /// live (2026-07-27): the real field is `item_note` (e.g. `"dgdthfy"`).
  /// Only rendered when non-empty.
  final String note;
  final List<Seller> sellers; // empty while status == 'review'
  /// Confirmed live field: `is_restricted` (a real bool). A restricted item
  /// can't be priced or added to cart at all — it must be picked up in
  /// person instead.
  final bool restricted;
  /// Only present when this item came from the Rx *cart list* response
  /// (`GET /app/acct/rx/cart`), not the prescription detail response —
  /// this item's own server-side cart-line id (needed for any future
  /// remove/update-quantity call) and how many of it are actually in the
  /// cart. Field names/shape are an unconfirmed guess (`cart_id`,
  /// `quantity`) since that endpoint's response has no saved example yet —
  /// modeled on the regular cart's confirmed shape, which uses the same
  /// two field names for the same purpose.
  final int? cartId;
  final int? cartQuantity;

  RxItem({
    required this.id,
    required this.name,
    required this.nameAr,
    required this.emoji,
    this.imageUrl,
    required this.dosage,
    required this.dosageAr,
    required this.refillable,
    this.refillStatus,
    this.note = '',
    this.sellers = const [],
    this.restricted = false,
    this.cartId,
    this.cartQuantity,
  });

  String displayName(bool arabic) => arabic ? nameAr : name;
  String displayDosage(bool arabic) => arabic ? dosageAr : dosage;

  /// Confirmed live: `dosage` ("15"), `dose_time` ("Before Meal"), and
  /// `duration` ("3 Day") are three SEPARATE fields, not one already-
  /// composed descriptive sentence like an earlier assumption had it.
  /// Composes them into one line for display; if some other response
  /// shape ever sends a single pre-composed `dosage` string instead (and
  /// no separate dose_time/duration), this still works — it just joins
  /// whichever of the three parts are actually present.
  static String _composeDosage(Map<String, dynamic> json, {required bool arabic}) {
    final parts = arabic
        ? [asString(json, const ['dosage_ar', 'dosage']), asString(json, const ['dose_time_ar', 'dose_time']), asString(json, const ['duration_ar', 'duration'])]
        : [asString(json, const ['dosage']), asString(json, const ['dose_time']), asString(json, const ['duration'])];
    return parts.where((s) => s.trim().isNotEmpty).join(' · ');
  }

  factory RxItem.fromJson(Map<String, dynamic> json) {
    final sellersJson = asList(json, const ['sellers']);
    // Falls back to synthesizing a single seller from flat fields directly
    // on the item — confirmed live: a real item has `seller` (name),
    // `price`, and `product_id` sitting at the top level, not nested in a
    // `sellers[]` array at all. Same pattern already confirmed necessary
    // for `/app/products`.
    final sellers = sellersJson.isNotEmpty
        ? sellersJson.map((e) => Seller.fromJson(e as Map<String, dynamic>)).toList()
        : <Seller>[
            if (json.containsKey('price'))
              Seller(
                productId: asIntOrNull(json, const ['product_id']),
                name: asString(json, const ['seller', 'pharmacy_name', 'pharmacy'], fallback: 'WASFA'),
                price: asDouble(json, const ['price']),
                was: asDoubleOrNull(json, const [
                  'compare_price', 'was', 'old_price', 'compare_at_price', 'original_price', 'list_price', 'mrp', 'regular_price', 'strike_price',
                ]),
                eta: asString(json, const ['eta', 'delivery_eta']),
                stock: asBool(json, const ['in_stock', 'stock'], fallback: true),
              ),
          ];
    return RxItem(
      id: asString(json, const ['id', 'item_id']),
      name: asString(json, const ['name', 'name_en']),
      nameAr: asString(json, const ['name_ar']),
      emoji: asStringOrNull(json, const ['emoji']) ?? '💊',
      imageUrl: asStringOrNull(json, const ['image', 'image_url']),
      dosage: _composeDosage(json, arabic: false),
      dosageAr: _composeDosage(json, arabic: true),
      refillable: asBool(json, const ['refillable']),
      refillStatus: asStringOrNull(json, const ['refill_status']),
      note: asString(json, const ['note', 'item_note', 'instructions', 'remarks']),
      sellers: sellers,
      restricted: asBool(json, const ['restricted', 'is_restricted', 'pickup_only']),
      cartId: asIntOrNull(json, const ['cart_id']),
      cartQuantity: asIntOrNull(json, const ['quantity']),
    );
  }
}

class Prescription {
  final String id;
  final String date; // display string, e.g. "Jun 17, 2026"
  final String doctor;
  final String specialty;
  final String clinic;
  final String diagnosis;
  /// Prescription-level note (distinct from each item's own [RxItem.note])
  /// — e.g. general instructions from the doctor covering the whole
  /// prescription. ✅ Confirmed live (2026-07-27): the real field is
  /// `prescription_note`. Only rendered when non-empty.
  final String note;
  /// Confirmed from the existing native app's real fields (both come back
  /// as the strings "1"/"0", not real booleans): `request_price_submitted`
  /// and `price_request`. Exactly 3 states, matching the client's own
  /// wording precisely — no "pending"/"pharmacist review"/"ordered" labels:
  /// - neither set → "Get Prices" (an action, not just a label — tapping it
  ///   calls [AccountService.requestPricing])
  /// - priceRequested only → "Prices Requested"
  /// - priceSubmitted → "Price Submitted" (sellers/pricing now available)
  final bool priceSubmitted;
  final bool priceRequested;
  final List<RxItem> items;

  const Prescription({
    required this.id,
    required this.date,
    required this.doctor,
    required this.specialty,
    required this.clinic,
    required this.diagnosis,
    this.note = '',
    required this.priceSubmitted,
    required this.priceRequested,
    required this.items,
  });

  bool get isPriced => priceSubmitted;
  bool get isPending => !priceSubmitted && !priceRequested;
  bool get isInReview => !priceSubmitted && priceRequested;

  /// Exactly the client's 3 labels — "Get Prices" doubles as the action
  /// button's own text where this is shown as a tappable element (the My Rx
  /// list card's status pill, and the detail page's dock button), not just
  /// a passive status word like the other two.
  String get statusLabel {
    if (isPriced) return 'Price Submitted';
    if (isInReview) return 'Prices Requested';
    return 'Get Prices';
  }

  /// Joins doctor + specialty — matches the existing native app's exact
  /// separator (" - ", not " · ") for consistency across platforms.
  String get doctorLine => specialty.trim().isNotEmpty ? '$doctor - $specialty' : doctor;

  /// From `GET /app/acct/rx/{id}` (single-prescription detail — the path
  /// changed from the old `/acct/rx?user_id=` list-style endpoint) or
  /// `GET /app/acct/rx` (list — path unconfirmed to actually return a list
  /// rather than 404; see AccountService.prescriptions).
  factory Prescription.fromJson(Map<String, dynamic> json) => Prescription(
        // Confirmed live: the detail endpoint (`GET /app/acct/rx/{id}`)
        // calls this `rx_id`, but the LIST endpoint (`GET /app/acct/rx`
        // with no id — returns a bare array) calls the exact same thing
        // `rx` instead. Two different field names for the same value on
        // two endpoints that otherwise share this same model — this is
        // what was causing every prescription from the list to have an
        // empty `.id`, which cascaded into the detail screen hitting a
        // malformed URL (missing the id entirely) and landing on the list
        // endpoint by accident.
        id: asString(json, const ['rx_id', 'rx', 'id', 'code', 'prescription_id']),
        date: asString(json, const ['date']),
        doctor: asString(json, const ['doctor']),
        specialty: asString(json, const ['specialty', 'doctor_speciality']),
        clinic: asString(json, const ['clinic', 'clinic_name']),
        diagnosis: asString(json, const ['diagnosis']),
        note: asString(json, const ['note', 'prescription_note', 'notes', 'instructions']),
        priceSubmitted: asString(json, const ['request_price_submitted']) == '1',
        priceRequested: asString(json, const ['price_request']) == '1',
        items: asList(json, const ['items']).map((e) => RxItem.fromJson(e as Map<String, dynamic>)).toList(),
      );
}
