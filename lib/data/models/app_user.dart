/// From OTP verify: `{ ok:true, user:{ id, name, phone, email, ... } }`.
/// Everything past `email` mirrors the HTML's `PROFILE` object — all
/// nullable, since none of it exists until the person fills in the
/// profile screen. Field names on the wire (`saveProfile` in
/// AuthService) are a best guess following the existing snake_case
/// pattern (`first_name`, `civil_id`, etc.) — worth confirming
/// `weight`/`height`/`blood_type`/`emergency_*` with backend since,
/// unlike the rest, those were never part of the original API contract.
class AppUser {
  final int id;
  final String name;
  final String phone;
  final String? email;
  final String? civilId;
  final String? dob; // ISO yyyy-MM-dd
  final String? gender; // 'Male' | 'Female' | 'Other'
  final String? nationality;
  final double? weight; // kg
  final double? height; // cm
  final String? bloodType;
  final String? emergName;
  final String? emergRel;
  final String? emergPhone;
  /// ✅ Confirmed live (2026-09-28, real `GET /acct/profile` response):
  /// `profile_pic` — none of the earlier guessed candidates (`image`,
  /// `photo`, `photo_url`, `avatar`, `profile_photo`) were actually right.
  final String? photoUrl;

  const AppUser({
    required this.id,
    required this.name,
    required this.phone,
    this.email,
    this.civilId,
    this.dob,
    this.gender,
    this.nationality,
    this.weight,
    this.height,
    this.bloodType,
    this.emergName,
    this.emergRel,
    this.emergPhone,
    this.photoUrl,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: _asInt(json['id']),
        name: (json['name'] ?? '').toString(),
        phone: (json['phone'] ?? '').toString(),
        email: _asStringOrNull(json['email']),
        civilId: _asStringOrNull(json['civil_id']),
        dob: _asStringOrNull(json['date_of_birth'] ?? json['dob']),
        gender: _asStringOrNull(json['gender']),
        nationality: _asStringOrNull(json['nationality']),
        weight: _asDoubleOrNull(json['weight']),
        height: _asDoubleOrNull(json['height']),
        bloodType: _asStringOrNull(json['blood_type']),
        emergName: _asStringOrNull(json['emergency_name']),
        emergRel: _asStringOrNull(json['emergency_relation']),
        emergPhone: _asStringOrNull(json['emergency_phone']),
        photoUrl: _asStringOrNull(json['profile_pic']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
        if (email != null) 'email': email,
        if (civilId != null) 'civil_id': civilId,
        if (dob != null) 'date_of_birth': dob,
        if (gender != null) 'gender': gender,
        if (nationality != null) 'nationality': nationality,
        if (weight != null) 'weight': weight,
        if (height != null) 'height': height,
        if (bloodType != null) 'blood_type': bloodType,
        if (emergName != null) 'emergency_name': emergName,
        if (emergRel != null) 'emergency_relation': emergRel,
        if (emergPhone != null) 'emergency_phone': emergPhone,
        if (photoUrl != null) 'profile_pic': photoUrl,
      };

  static int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is String) return int.tryParse(v) ?? 0;
    if (v is double) return v.toInt();
    return 0;
  }

  static String? _asStringOrNull(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  static double? _asDoubleOrNull(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString());
  }
}
