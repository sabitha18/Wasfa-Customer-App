import '../../core/utils/json_utils.dart';

/// `GET /app/delivery-charge?area_id=` and `GET /app/delivery-charge/address/{id}`
/// — confirmed live (2026-09-17), both return this same shape.
///
/// [effectiveCharge] is the one real number to ever display or use in a
/// total — it's the server's own final delivery charge with its
/// free-delivery rule already applied. [deliveryCharge] is the area's base
/// rate BEFORE that rule and [freeOverAmount] is the free-delivery
/// threshold — both kept for completeness/messaging (e.g. "free over X"),
/// but the app never compares a subtotal against [freeOverAmount] itself
/// to decide the fee; that comparison is exactly what [effectiveCharge]
/// already did, server-side.
class DeliveryCharge {
  final int areaId;
  final String area;
  final int governorateId;
  final double deliveryCharge;
  final double effectiveCharge;
  final bool freeDeliveryApplied;
  final double freeOverAmount;
  /// Only present on the by-address variant.
  final int? addressId;

  /// The AREA's centre point (backend confirmed 2026-10-16 — area lat/lng,
  /// not the address's own). Null until filled for that area in the admin.
  /// Used only for the Home store list's ETA/distance when a saved address
  /// is selected — never for the fee, checkout or orders (those use ids).
  final double? latitude;
  final double? longitude;

  const DeliveryCharge({
    required this.areaId,
    required this.area,
    required this.governorateId,
    required this.deliveryCharge,
    required this.effectiveCharge,
    required this.freeDeliveryApplied,
    required this.freeOverAmount,
    this.addressId,
    this.latitude,
    this.longitude,
  });

  factory DeliveryCharge.fromJson(Map<String, dynamic> json) => DeliveryCharge(
        areaId: asInt(json, const ['area_id']),
        area: asString(json, const ['area']),
        governorateId: asInt(json, const ['governorate_id']),
        deliveryCharge: asDouble(json, const ['delivery_charge']),
        effectiveCharge: asDouble(json, const ['effective_charge']),
        freeDeliveryApplied: asBool(json, const ['free_delivery_applied']),
        freeOverAmount: asDouble(json, const ['free_over_amount']),
        addressId: asIntOrNull(json, const ['address_id']),
        latitude: asDoubleOrNull(json, const ['latitude']),
        longitude: asDoubleOrNull(json, const ['longitude']),
      );

  /// True only for usable coordinates inside Kuwait — guards against an
  /// empty/0,0 or mis-entered value ever reaching /app/stores.
  bool get hasKuwaitCoordinates =>
      latitude != null && longitude != null && latitude! > 28.4 && latitude! < 30.2 && longitude! > 46.5 && longitude! < 48.7;
}
