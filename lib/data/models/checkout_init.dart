import '../../core/utils/json_utils.dart';
import 'address.dart';

/// `GET /app/checkout?user_id=` — confirmed live. Consolidates everything
/// the checkout screen needs into one call: cart items (with real
/// pharmacy names — something the plain `/app/cart` response doesn't
/// include), saved addresses, delivery time slots, which payment methods
/// are enabled (finally a real source for this — see AppSettingsState's
/// doc about the old `/app/settings` guess), wallet balance, available
/// promotions, and server-computed totals.
/// Result of `POST /app/promotion/apply`, `/app/promo-code/apply`, or
/// `/app/promotion/remove` — confirmed live. All three return this same
/// small shape (not the full [CheckoutInitData] I'd originally assumed) —
/// `{ success, promotion_id?, title?, promo_discount?, message }`. Since
/// this doesn't include updated totals/cart/etc., the caller needs to
/// re-fetch [CheckoutInitData] afterward to get the refreshed summary.
class PromoApplyResult {
  final bool success;
  final int? promotionId;
  final String? title;
  final double? promoDiscount;
  final String? message;

  const PromoApplyResult({required this.success, this.promotionId, this.title, this.promoDiscount, this.message});

  factory PromoApplyResult.fromJson(Map<String, dynamic> json) => PromoApplyResult(
        success: asBool(json, const ['success']),
        promotionId: asIntOrNull(json, const ['promotion_id']),
        title: asStringOrNull(json, const ['title']),
        promoDiscount: asDoubleOrNull(json, const ['promo_discount']),
        message: asStringOrNull(json, const ['message']),
      );
}

class CheckoutInitData {
  final List<CheckoutCartItem> items;
  final int itemCount;
  final List<Address> addresses;
  final List<DeliverySlot> deliverySlots;
  final double freeDeliveryOver;
  final PaymentMethodsInfo paymentMethods;
  final double walletBalance;
  final List<Promotion> promotions;
  /// The currently-applied coupon code, if any (`coupon` in the response).
  final String? appliedCouponCode;
  /// The currently auto-applied promotion, if any (`applied_promo`) —
  /// distinct from [appliedCouponCode]: a promotion can apply automatically
  /// based on cart conditions (see [Promotion.conditionType]) without the
  /// person ever typing a code.
  final Promotion? appliedPromo;
  final CheckoutSummary summary;

  const CheckoutInitData({
    required this.items,
    required this.itemCount,
    required this.addresses,
    required this.deliverySlots,
    required this.freeDeliveryOver,
    required this.paymentMethods,
    required this.walletBalance,
    required this.promotions,
    required this.appliedCouponCode,
    required this.appliedPromo,
    required this.summary,
  });

  factory CheckoutInitData.fromJson(Map<String, dynamic> json) {
    // Confirmed live: the whole payload sits under a `data` key, with a
    // sibling `success: true` — unwrap it here so callers just get the
    // actual content.
    final data = (json['data'] is Map) ? json['data'] as Map<String, dynamic> : json;
    return CheckoutInitData(
      items: asList(data, const ['items']).map((e) => CheckoutCartItem.fromJson(e as Map<String, dynamic>)).toList(),
      itemCount: asInt(data, const ['item_count']),
      addresses: asList(data, const ['addresses']).map((e) => Address.fromJson(e as Map<String, dynamic>)).toList(),
      deliverySlots: asList(data, const ['delivery_slots']).map((e) => DeliverySlot.fromJson(e as Map<String, dynamic>)).toList(),
      freeDeliveryOver: asDouble(data, const ['free_delivery_over']),
      paymentMethods: PaymentMethodsInfo.fromJson((data['payment_methods'] as Map?)?.cast<String, dynamic>() ?? const {}),
      walletBalance: asDouble(data, const ['wallet_balance']),
      promotions: asList(data, const ['promotions']).map((e) => Promotion.fromJson(e as Map<String, dynamic>)).toList(),
      appliedCouponCode: asStringOrNull(data, const ['coupon']),
      appliedPromo: (data['applied_promo'] is Map) ? Promotion.fromJson((data['applied_promo'] as Map).cast<String, dynamic>()) : null,
      summary: CheckoutSummary.fromJson((data['summary'] as Map?)?.cast<String, dynamic>() ?? const {}),
    );
  }
}

/// A cart line as seen from the checkout endpoint specifically — includes
/// `pharmacy_id`/`pharmacy_name` directly, which the plain `/app/cart`
/// response doesn't (or didn't, as of the last confirmed check) — kept
/// separate from [CartLine] since this is a read-only snapshot for
/// display/validation at checkout time, not the mutable cart itself.
class CheckoutCartItem {
  final int cartId;
  final int productId;
  final String name;
  final String? imageUrl;
  final double price;
  final double? comparePrice;
  final int? discountPct;
  final int qty;
  final double lineTotal;
  final int? pharmacyId;
  final String pharmacyName;

  const CheckoutCartItem({
    required this.cartId,
    required this.productId,
    required this.name,
    this.imageUrl,
    required this.price,
    this.comparePrice,
    this.discountPct,
    required this.qty,
    required this.lineTotal,
    this.pharmacyId,
    required this.pharmacyName,
  });

  factory CheckoutCartItem.fromJson(Map<String, dynamic> json) => CheckoutCartItem(
        cartId: asInt(json, const ['cart_id']),
        productId: asInt(json, const ['product_id']),
        name: asString(json, const ['product_name', 'name']),
        imageUrl: asStringOrNull(json, const ['image']),
        price: asDouble(json, const ['price']),
        comparePrice: asDoubleOrNull(json, const ['compare_price']),
        discountPct: asIntOrNull(json, const ['discount_pct']),
        qty: asInt(json, const ['qty', 'quantity'], fallback: 1),
        lineTotal: asDouble(json, const ['line_total']),
        pharmacyId: asIntOrNull(json, const ['pharmacy_id']),
        pharmacyName: asString(json, const ['pharmacy_name'], fallback: 'WASFA'),
      );
}

class DeliverySlot {
  final int id;
  final String title;
  final double amount;
  /// `free_or_paid` — confirmed present but always null in every example
  /// seen so far; meaning/values unconfirmed. Kept as a raw string in case
  /// it turns out to matter (e.g. a label override) once a non-null
  /// example shows up.
  final String? freeOrPaid;

  const DeliverySlot({required this.id, required this.title, required this.amount, this.freeOrPaid});

  factory DeliverySlot.fromJson(Map<String, dynamic> json) => DeliverySlot(
        id: asInt(json, const ['id']),
        title: asString(json, const ['title']),
        amount: asDouble(json, const ['amount']),
        freeOrPaid: asStringOrNull(json, const ['free_or_paid']),
      );
}

/// Which payment methods are actually enabled — this is the real source
/// for what `AppSettingsState`'s old `/app/settings` guess was standing in
/// for. `knetConfig` carries the actual KNET payment-gateway credentials
/// needed to initiate a real KNET payment (not just a yes/no flag).
class PaymentMethodsInfo {
  final bool cod;
  final bool knet;
  final bool wallet;
  final KnetConfig? knetConfig;

  const PaymentMethodsInfo({required this.cod, required this.knet, required this.wallet, this.knetConfig});

  factory PaymentMethodsInfo.fromJson(Map<String, dynamic> json) => PaymentMethodsInfo(
        cod: asBool(json, const ['cod']),
        knet: asBool(json, const ['knet']),
        wallet: asBool(json, const ['wallet']),
        knetConfig: (json['knet_config'] is Map) ? KnetConfig.fromJson((json['knet_config'] as Map).cast<String, dynamic>()) : null,
      );

  /// Matches the keys [CartState]/checkout already use ('knet','card',
  /// 'wallet','cod'). 'card' isn't a field this endpoint sends at all —
  /// this used to carry it through as always-enabled regardless (to avoid
  /// silently hiding a payment option nobody had confirmed should be
  /// hidden), but that turned out to be wrong: confirmed directly
  /// (2026-08-03) that Card genuinely isn't an available option here, and
  /// showing it anyway let people select a payment method the backend
  /// can't actually process. Omitted entirely now unless/until the API
  /// adds a real `card` field to gate it on.
  List<String> get enabledKeys => [
        if (knet) 'knet',
        if (wallet) 'wallet',
        if (cod) 'cod',
      ];
}

/// Real KNET gateway credentials — treat as sensitive: don't log this
/// object's contents anywhere, and don't persist it to local storage.
class KnetConfig {
  final String clientId;
  final String secretKey;
  final String encryptionKey;
  final String baseUrl;

  const KnetConfig({required this.clientId, required this.secretKey, required this.encryptionKey, required this.baseUrl});

  factory KnetConfig.fromJson(Map<String, dynamic> json) => KnetConfig(
        clientId: asString(json, const ['client_id']),
        secretKey: asString(json, const ['secret']),
        encryptionKey: asString(json, const ['encrp_key']),
        baseUrl: asString(json, const ['base_url']),
      );
}

/// A promotion/offer as defined in the dashboard — a real, rich model
/// replacing the earlier fully-fake, entirely client-side `Promo` list
/// (WASFA15/SAVE2/etc. — see CartState.appliedCoupon's doc for that
/// history). Two ways a promotion applies: entering [promoCode] by hand
/// (via `POST /app/promo-code/apply`), or automatically once the cart
/// meets [conditionType]/[conditionValue] (via `POST /app/promotion/apply`
/// with this promotion's [id] — e.g. `condition_type: "min_items"`).
class Promotion {
  final int id;
  final String title;
  final String arabicTitle;
  /// 'fixed_amount' | 'percent' | null (some seed/demo rows in a real
  /// response had this null with an unrelated-looking `offer_type` string
  /// like "A percent amount discount" — treat any value outside
  /// fixed_amount/percent as "unknown/inactive", not a third real type).
  final String? offerType;
  final double offerValue;
  /// The ACTUAL savings this promotion would apply to the CURRENT cart —
  /// confirmed live, distinct from [offerValue] (the promo's raw config
  /// number, e.g. `2` for a fixed KWD-2 promo or `20` for a 20% one).
  /// [offerValue] alone can't tell you what a percent promo actually saves
  /// on a specific cart without redoing the math (and getting subtotal/cap
  /// rules wrong is easy); this is the server's own pre-computed answer.
  final double discount;
  /// Ready-made display text (e.g. "KWD 2.000 off", "20% off") — confirmed
  /// live, sitting right there unused while the promo sheet reconstructed
  /// the same kind of string itself from [offerType]/[offerValue].
  final String? label;
  final double? maxDiscount;
  final String? promoCode;
  /// 'min_items' | 'promo_code' | null — a null condition_type alongside a
  /// null offer_type in real data seems to mean "not actually a
  /// functioning promotion yet" (a draft/disabled row from the dashboard)
  /// rather than a real applicable one — see [isActive].
  final String? conditionType;
  final String? conditionValue;
  final String? applicableFor;
  final String? applicableOn;
  final int? buyQuantity;
  final String? startDate;
  final String? endDate;
  final int? usageLimitPerUser;
  final int? usageLimitTotal;
  final int usedCount;

  const Promotion({
    required this.id,
    required this.title,
    required this.arabicTitle,
    this.offerType,
    required this.offerValue,
    this.discount = 0,
    this.label,
    this.maxDiscount,
    this.promoCode,
    this.conditionType,
    this.conditionValue,
    this.applicableFor,
    this.applicableOn,
    this.buyQuantity,
    this.startDate,
    this.endDate,
    this.usageLimitPerUser,
    this.usageLimitTotal,
    required this.usedCount,
  });

  /// A real response had several rows with `offer_type: null`,
  /// `condition_type: null`, `offer_value: 0` — these look like disabled/
  /// draft dashboard entries rather than live offers. Filters those out of
  /// any "available offers" list shown to a person, rather than showing a
  /// promo tile that does nothing if tapped.
  bool get isActive => (offerType == 'fixed_amount' || offerType == 'percent') && offerValue > 0;

  /// Whether this needs the person to type a code, vs. applying
  /// automatically once the cart qualifies.
  bool get requiresCode => conditionType == 'promo_code' && promoCode != null && promoCode!.isNotEmpty;

  String title_(bool arabic) => arabic ? arabicTitle : title;

  factory Promotion.fromJson(Map<String, dynamic> json) => Promotion(
        id: asInt(json, const ['id']),
        title: asString(json, const ['title']),
        arabicTitle: asString(json, const ['arabic_title']),
        offerType: asStringOrNull(json, const ['offer_type']),
        offerValue: asDouble(json, const ['offer_value']),
        discount: asDouble(json, const ['discount']),
        label: asStringOrNull(json, const ['label']),
        maxDiscount: asDoubleOrNull(json, const ['max_discount']),
        promoCode: asStringOrNull(json, const ['promo_code']),
        conditionType: asStringOrNull(json, const ['condition_type']),
        conditionValue: asStringOrNull(json, const ['condition_value']),
        applicableFor: asStringOrNull(json, const ['applicable_for']),
        applicableOn: asStringOrNull(json, const ['applicable_on']),
        buyQuantity: asIntOrNull(json, const ['buy_quantity']),
        startDate: asStringOrNull(json, const ['start_date']),
        endDate: asStringOrNull(json, const ['end_date']),
        usageLimitPerUser: asIntOrNull(json, const ['usage_limit_per_user']),
        usageLimitTotal: asIntOrNull(json, const ['usage_limit_total']),
        usedCount: asInt(json, const ['used_count']),
      );
}

/// Server-computed totals — confirmed live via the checkout endpoint.
/// Once this has loaded, prefer these over any local computation
/// ([CartState.computeTotals]) for what's actually shown/charged, since
/// this reflects the server's own promo/delivery-fee logic exactly rather
/// than the client trying to replicate it.
class CheckoutSummary {
  final double subtotal;
  final double deliveryFee;
  /// Confirmed live (2026-07-29), distinct from [couponDiscount] — a
  /// separate savings figure baked into checkout's own totals (matches
  /// `bogo_saved` seen on individual `/app/cart` lines: subtotal 11.70,
  /// discount 5.85, grand_total 5.85 — the BOGO free unit accounted for
  /// server-side here too, not just per-line in the cart).
  final double discount;
  final double couponDiscount;
  final double grandTotal;
  final String currency;

  const CheckoutSummary({
    required this.subtotal,
    required this.deliveryFee,
    required this.discount,
    required this.couponDiscount,
    required this.grandTotal,
    required this.currency,
  });

  factory CheckoutSummary.fromJson(Map<String, dynamic> json) => CheckoutSummary(
        subtotal: asDouble(json, const ['subtotal']),
        deliveryFee: asDouble(json, const ['delivery_fee']),
        discount: asDouble(json, const ['discount']),
        couponDiscount: asDouble(json, const ['coupon_discount']),
        grandTotal: asDouble(json, const ['grand_total']),
        currency: asString(json, const ['currency'], fallback: 'KWD'),
      );
}
