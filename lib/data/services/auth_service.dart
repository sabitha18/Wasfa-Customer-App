import '../../core/network/api_client.dart';
import '../../core/network/api_config.dart';
import '../models/app_user.dart';

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();
  final ApiClient _client = ApiClient.instance;

  /// Requests an OTP for [phone]. Returns the `dev_code` when the backend
  /// includes one (sandbox/dev mode, before the SMS gateway is live) so the
  /// UI can pre-fill it for faster testing — null in production.
  Future<String?> requestOtp(String phone) async {
    final res = await _client.post(ApiConfig.otpRequest, body: {'phone': phone});
    if (res is Map && res['dev_code'] != null) return res['dev_code'].toString();
    return null;
  }

  /// Verifies [code] for [phone]. [name] is only used the first time a phone
  /// number signs up. Returns the logged-in [AppUser].
  Future<AppUser> verifyOtp({required String phone, required String code, String? name}) async {
    final res = await _client.post(ApiConfig.otpVerify, body: {
      'phone': phone,
      'code': code,
      if (name != null && name.isNotEmpty) 'name': name,
    });
    final userJson = (res as Map)['user'] as Map<String, dynamic>? ?? {};
    return AppUser.fromJson(userJson);
  }

  /// Fetches the full profile — same shape as the `user` object `saveProfile`
  /// returns/sends (civil id, dob, gender, nationality, weight, height,
  /// blood type, emergency contact). ✅ confirmed live in the updated
  /// Postman collection (`GET /acct/profile?user_id=`) — this was built
  /// earlier as a best-guess but never actually called anywhere; now wired
  /// into the profile screen's initState so it shows real server data
  /// instead of only whatever's cached on this device.
  Future<AppUser> fetchProfile(int userId) async {
    final res = await _client.get(ApiConfig.acctProfile, query: {'user_id': userId});
    // Not confirmed by the collection (no saved example) whether this wraps
    // in {"user": {...}} like the POST response does, or returns the
    // fields directly — handle both.
    final userJson = (res is Map && res['user'] is Map) ? res['user'] as Map<String, dynamic> : (res as Map<String, dynamic>);
    return AppUser.fromJson(userJson);
  }

  /// Saves personal info for the account/profile screen. Returns the
  /// updated [AppUser] so the caller can refresh [AuthState] — previously
  /// this returned nothing, so a newly-entered email was sent to the
  /// server and then immediately discarded locally, meaning the Account
  /// header could never show it even after a successful save.
  ///
  /// `weight`/`height`/`bloodType`/`emergency*` weren't part of the
  /// original API contract (only civil id/dob/gender/nationality were) —
  /// sent here as best-guess snake_case keys matching the rest; confirm
  /// with backend if the profile save doesn't end up round-tripping them.
  Future<AppUser> saveProfile({
    required int userId,
    required String firstName,
    required String lastName,
    String? email,
    String? phone,
    String? civilId,
    String? dateOfBirth,
    String? gender,
    String? nationality,
    double? weight,
    double? height,
    String? bloodType,
    String? emergName,
    String? emergRel,
    String? emergPhone,
  }) async {
    final res = await _client.post(ApiConfig.acctProfile, body: {
      'user_id': userId,
      'first_name': firstName,
      'last_name': lastName,
      if (email != null) 'email': email,
      if (phone != null) 'phone': phone,
      if (civilId != null) 'civil_id': civilId,
      if (dateOfBirth != null) 'date_of_birth': dateOfBirth,
      if (gender != null) 'gender': gender,
      if (nationality != null) 'nationality': nationality,
      if (weight != null) 'weight': weight,
      if (height != null) 'height': height,
      if (bloodType != null) 'blood_type': bloodType,
      if (emergName != null) 'emergency_name': emergName,
      if (emergRel != null) 'emergency_relation': emergRel,
      if (emergPhone != null) 'emergency_phone': emergPhone,
    });
    // Confirmed live: the server only ever echoes back {id, name, phone,
    // email} in `user`, even when civil_id/dob/gender/nationality/weight/
    // height/blood_type/emergency_* were sent and accepted (200 OK). Since
    // `res['user']` is never null, the old code took it as the *whole*
    // truth and returned it as-is — silently wiping every other field back
    // to null on every single save, right after the person just typed
    // them in. Merge instead: prefer whatever the server actually echoes
    // for a field, otherwise keep what was just submitted.
    final userJson = (res is Map ? res['user'] : null) as Map<String, dynamic>?;
    final server = userJson != null ? AppUser.fromJson(userJson) : null;
    final name = server?.name.isNotEmpty == true ? server!.name : [firstName, lastName].where((s) => s.isNotEmpty).join(' ');
    return AppUser(
      id: server?.id ?? userId,
      name: name,
      phone: server?.phone.isNotEmpty == true ? server!.phone : (phone ?? ''),
      email: server?.email ?? email,
      civilId: server?.civilId ?? civilId,
      dob: server?.dob ?? dateOfBirth,
      gender: server?.gender ?? gender,
      nationality: server?.nationality ?? nationality,
      weight: server?.weight ?? weight,
      height: server?.height ?? height,
      bloodType: server?.bloodType ?? bloodType,
      emergName: server?.emergName ?? emergName,
      emergRel: server?.emergRel ?? emergRel,
      emergPhone: server?.emergPhone ?? emergPhone,
    );
  }
}
