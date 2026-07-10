/// From OTP verify: `{ ok:true, user:{ id, name, phone } }`.
class AppUser {
  final int id;
  final String name;
  final String phone;

  const AppUser({required this.id, required this.name, required this.phone});

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: _asInt(json['id']),
        name: (json['name'] ?? '').toString(),
        phone: (json['phone'] ?? '').toString(),
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'phone': phone};

  static int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is String) return int.tryParse(v) ?? 0;
    if (v is double) return v.toInt();
    return 0;
  }
}
