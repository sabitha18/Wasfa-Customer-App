import '../../core/utils/json_utils.dart';

class Address {
  /// Server-side id. Null = not yet saved (new address / local mock).
  int? id;
  String title; // Home/Apartment, Work, Other
  String first;
  String last;
  String email;
  String phone;
  String alt;

  /// Foreign keys into `/areas` — the source of truth once the person picks
  /// from the real governorate/area lists. [gov]/[area] below are just the
  /// display names, kept in sync locally by AddressState so existing UI code
  /// that reads them doesn't need to change.
  int? governorateId;
  int? areaId;
  String gov;
  String area;

  String block;
  String street;
  String building;
  String apt;
  String floor;

  Address({
    this.id,
    this.title = 'Home/Apartment',
    this.first = '',
    this.last = '',
    this.email = '',
    this.phone = '',
    this.alt = '',
    this.governorateId,
    this.areaId,
    this.gov = '',
    this.area = '',
    this.block = '',
    this.street = '',
    this.building = '',
    this.apt = '',
    this.floor = '',
  });

  String get formatted => [
        area,
        if (block.isNotEmpty) 'Block $block',
        street,
        if (building.isNotEmpty) 'Bldg $building',
        if (apt.isNotEmpty) 'Apt $apt',
      ].where((s) => s.isNotEmpty).join(' · ');

  /// From `GET /acct/addresses` list items.
  factory Address.fromJson(Map<String, dynamic> json) => Address(
        id: asIntOrNull(json, const ['id']),
        title: asString(json, const ['title'], fallback: 'Home/Apartment'),
        first: asString(json, const ['first_name', 'first']),
        last: asString(json, const ['last_name', 'last']),
        email: asString(json, const ['email']),
        phone: asString(json, const ['phone']),
        governorateId: asIntOrNull(json, const ['governorate_id']),
        areaId: asIntOrNull(json, const ['area_id']),
        gov: asString(json, const ['governorate_name', 'governorate']),
        area: asString(json, const ['area_name', 'area']),
        block: asString(json, const ['block']),
        street: asString(json, const ['street']),
        building: asString(json, const ['building']),
        apt: asString(json, const ['flat', 'apt']),
        floor: asString(json, const ['floor']),
      );

  /// Body for `POST /acct/address-save`. `id: null` = create.
  Map<String, dynamic> toSaveJson(int userId) => {
        'user_id': userId,
        'id': id,
        'title': title,
        'governorate_id': governorateId,
        'area_id': areaId,
        'block': block,
        'street': street,
        'building': building,
        'floor': floor,
        'flat': apt,
        'phone': phone,
      };
}
