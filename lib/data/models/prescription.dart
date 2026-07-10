import '../../core/utils/json_utils.dart';
import 'seller.dart';

class RxItem {
  final String name;
  final String nameAr;
  final String emoji;
  final String dosage;
  final String dosageAr;
  final bool refillable;
  String? refillStatus; // null | 'pending'
  final List<Seller> sellers; // empty while status == 'review'

  RxItem({
    required this.name,
    required this.nameAr,
    required this.emoji,
    required this.dosage,
    required this.dosageAr,
    required this.refillable,
    this.refillStatus,
    this.sellers = const [],
  });

  String displayName(bool arabic) => arabic ? nameAr : name;
  String displayDosage(bool arabic) => arabic ? dosageAr : dosage;

  factory RxItem.fromJson(Map<String, dynamic> json) => RxItem(
        name: asString(json, const ['name', 'name_en']),
        nameAr: asString(json, const ['name_ar']),
        emoji: asStringOrNull(json, const ['emoji']) ?? '💊',
        dosage: asString(json, const ['dosage', 'dosage_en']),
        dosageAr: asString(json, const ['dosage_ar']),
        refillable: asBool(json, const ['refillable']),
        refillStatus: asStringOrNull(json, const ['refill_status']),
        sellers: asList(json, const ['sellers']).map((e) => Seller.fromJson(e as Map<String, dynamic>)).toList(),
      );
}

class Prescription {
  final String id;
  final String date; // display string, e.g. "Jun 17, 2026"
  final String doctor;
  final String specialty;
  final String clinic;
  final String diagnosis;
  final String status; // priced | review
  final List<RxItem> items;

  const Prescription({
    required this.id,
    required this.date,
    required this.doctor,
    required this.specialty,
    required this.clinic,
    required this.diagnosis,
    required this.status,
    required this.items,
  });

  bool get isPriced => status == 'priced';

  /// From `GET /acct/rx` list items.
  factory Prescription.fromJson(Map<String, dynamic> json) => Prescription(
        id: asString(json, const ['id', 'code']),
        date: asString(json, const ['date']),
        doctor: asString(json, const ['doctor']),
        specialty: asString(json, const ['specialty']),
        clinic: asString(json, const ['clinic']),
        diagnosis: asString(json, const ['diagnosis']),
        status: asString(json, const ['status'], fallback: 'review'),
        items: asList(json, const ['items']).map((e) => RxItem.fromJson(e as Map<String, dynamic>)).toList(),
      );
}
