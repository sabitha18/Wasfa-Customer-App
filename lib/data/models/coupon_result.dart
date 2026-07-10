import '../../core/utils/json_utils.dart';

/// From `GET /coupon?code=&subtotal=`. Exact shape isn't documented in the
/// collection — parsed defensively; `valid`/`ok` and `discount`/`amount` are
/// the most likely key names. Confirm against a real response and trim.
class CouponResult {
  final bool valid;
  final String code;
  final double discount;
  final bool freeDelivery;
  final String? message;

  const CouponResult({
    required this.valid,
    required this.code,
    required this.discount,
    required this.freeDelivery,
    this.message,
  });

  factory CouponResult.fromJson(Map<String, dynamic> json, {required String requestedCode}) => CouponResult(
        valid: json.containsKey('valid') ? asBool(json, const ['valid']) : asBool(json, const ['ok'], fallback: true),
        code: asString(json, const ['code'], fallback: requestedCode),
        discount: asDouble(json, const ['discount', 'amount', 'savings']),
        freeDelivery: asBool(json, const ['free_delivery', 'freeDelivery']),
        message: asStringOrNull(json, const ['msg', 'message']),
      );
}
