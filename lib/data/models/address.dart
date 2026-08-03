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

  /// Whether this is the account's default delivery address (confirmed
  /// live in `GET /acct/addresses` as `is_default: 1/0`).
  bool isDefault;
  /// Optional delivery note for this address (confirmed live as `note`,
  /// can be `null`).
  String note;

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
    this.isDefault = false,
    this.note = '',
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
        // Confirmed live via the checkout endpoint: the real field is
        // `alternate_phone`, not `alt_phone` — kept both since the address
        // list endpoint hasn't been double-checked for which one it uses.
        alt: asString(json, const ['alternate_phone', 'alt_phone', 'alt']),
        governorateId: asIntOrNull(json, const ['governorate_id']),
        areaId: asIntOrNull(json, const ['area_id']),
        // 'gov' was confirmed live earlier (a response using the literal
        // abbreviated key). checkout-init's addresses[] was later confirmed
        // to send the full word instead — 'governorate'/'area' — so both
        // forms are tried; keeping 'gov'/'area_name' too in case some other
        // address source still uses the shorter/older form.
        gov: asString(json, const ['gov', 'governorate_name', 'governorate']),
        area: asString(json, const ['area', 'area_name']),
        block: asString(json, const ['block']),
        street: asString(json, const ['street']),
        building: asString(json, const ['building']),
        apt: asString(json, const ['flat', 'apt']),
        floor: asString(json, const ['floor']),
        isDefault: asBool(json, const ['is_default']),
        note: asString(json, const ['note']),
      );

  /// Body for `POST /acct/address-save`. `id: null` = create.
  ///
  /// This was silently dropping `first_name`/`last_name`/`email`/`alt_phone`
  /// — the form collects all four, but they never made it into the request
  /// body, so the server never had them to save. That's why editing an
  /// address later showed them blank: it's not a display bug, the save
  /// itself never sent them in the first place.
  Map<String, dynamic> toSaveJson(int userId) => {
        'user_id': userId,
        'id': id,
        'title': title,
        'first_name': first,
        'last_name': last,
        'email': email,
        'phone': phone,
        'alt_phone': alt,
        'governorate_id': governorateId,
        'area_id': areaId,
        'block': block,
        'street': street,
        'building': building,
        'floor': floor,
        'flat': apt,
        'note': note,
        'is_default': isDefault,
      };
}
