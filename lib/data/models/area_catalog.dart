import '../../core/utils/json_utils.dart';

/// One area/neighborhood inside a governorate, with its flat delivery fee.
class AreaInfo {
  final int id;
  final String name;
  final String nameAr;
  final double fee;

  const AreaInfo({required this.id, required this.name, required this.nameAr, required this.fee});

  String label(bool arabic) => arabic ? nameAr : name;

  factory AreaInfo.fromJson(Map<String, dynamic> json) => AreaInfo(
        id: asInt(json, const ['id']),
        name: asString(json, const ['name']),
        nameAr: asString(json, const ['arabic_name', 'name_ar']),
        fee: asDouble(json, const ['fee']),
      );
}

class Governorate {
  final int id;
  final String name;
  final String nameAr;
  final List<AreaInfo> areas;

  const Governorate({required this.id, required this.name, required this.nameAr, required this.areas});

  String label(bool arabic) => arabic ? nameAr : name;

  factory Governorate.fromJson(Map<String, dynamic> json) => Governorate(
        id: asInt(json, const ['id']),
        name: asString(json, const ['name']),
        nameAr: asString(json, const ['arabic_name', 'name_ar']),
        areas: asList(json, const ['areas']).map((e) => AreaInfo.fromJson(e as Map<String, dynamic>)).toList(),
      );
}

/// From `GET /areas`: `{ govs:[{ id, name, arabic_name, areas:[{ id, name,
/// arabic_name, fee }] }], free_enabled, free_over }`.
class AreaCatalog {
  final List<Governorate> governorates;
  final bool freeDeliveryEnabled;
  final double freeDeliveryOver;

  const AreaCatalog({required this.governorates, required this.freeDeliveryEnabled, required this.freeDeliveryOver});

  factory AreaCatalog.fromJson(Map<String, dynamic> json) => AreaCatalog(
        governorates: asList(json, const ['govs', 'governorates']).map((e) => Governorate.fromJson(e as Map<String, dynamic>)).toList(),
        freeDeliveryEnabled: asBool(json, const ['free_enabled']),
        freeDeliveryOver: asDouble(json, const ['free_over']),
      );

  static const empty = AreaCatalog(governorates: [], freeDeliveryEnabled: false, freeDeliveryOver: 0);

  AreaInfo? findArea(int areaId) {
    for (final g in governorates) {
      for (final a in g.areas) {
        if (a.id == areaId) return a;
      }
    }
    return null;
  }

  Governorate? findGov(int govId) {
    for (final g in governorates) {
      if (g.id == govId) return g;
    }
    return null;
  }

  /// Delivery fee for [areaId], applying the free-delivery threshold against
  /// [subtotal] when enabled.
  double feeFor(int? areaId, double subtotal) {
    if (freeDeliveryEnabled && subtotal >= freeDeliveryOver && freeDeliveryOver > 0) return 0;
    if (areaId == null) return 0;
    return findArea(areaId)?.fee ?? 0;
  }
}
