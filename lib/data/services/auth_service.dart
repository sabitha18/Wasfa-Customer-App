import '../../core/network/api_client.dart';
import '../../core/network/api_config.dart';
import '../models/app_user.dart';

/// Everything the OTP-request response can tell the UI before the code is
/// even verified: the sandbox dev code (if any), and whether this phone
/// already belongs to a signed-up person — see [AuthService.requestOtp].
class OtpRequestResult {
  const OtpRequestResult({this.devCode, required this.isNewUser, this.existingName});
  final String? devCode;
  final bool isNewUser;
  final String? existingName;
}

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();
  final ApiClient _client = ApiClient.instance;

  /// Requests an OTP for [phone]. The backend response can carry three
  /// independent pieces of info: `dev_code` (sandbox/dev mode, before the
  /// SMS gateway is live — the UI pre-fills it for faster testing), and
  /// `is_new_user` + `name` (whether this phone already has an account,
  /// and their saved name if so) — this second pair is what lets the OTP
  /// screen skip asking for a name and show "Welcome back, X" instead for
  /// a returning person, rather than asking every time as if it might be
  /// a first signup. `is_new_user` defaults to true (today's behavior —
  /// always ask for a name) if the backend doesn't send it yet.
  Future<OtpRequestResult> requestOtp(String phone) async {
    final res = await _client.post(ApiConfig.otpRequest, body: {'phone': phone});
    final map = res is Map ? res : const {};
    return OtpRequestResult(
      devCode: map['dev_code']?.toString(),
      isNewUser: map['is_new_user'] is bool ? map['is_new_user'] as bool : true,
      existingName: map['name']?.toString(),
    );
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
  /// blood type, emergency contact, profile_pic). ✅ Confirmed live
  /// (2026-09-28): wraps in `{"user": {...}}`, same as the save response.
  Future<AppUser> fetchProfile(int userId) async {
    final res = await _client.get(ApiConfig.acctProfile, query: {'user_id': userId});
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
  ///
  /// ✅ Confirmed live (2026-09-28): this same endpoint now takes an
  /// optional `image` file as part of a real `multipart/form-data`
  /// request (previously plain JSON) — not a separate upload endpoint.
  /// [imagePath] (a local file path from image_picker) uploads/replaces
  /// the profile photo in the same call as any other profile edit.
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
    String? imagePath,
  }) async {
    final res = await _client.postMultipart(
      ApiConfig.acctProfile,
      fields: {
        'user_id': userId.toString(),
        'first_name': firstName,
        'last_name': lastName,
        if (email != null) 'email': email,
        if (phone != null) 'phone': phone,
        if (civilId != null) 'civil_id': civilId,
        if (dateOfBirth != null) 'date_of_birth': dateOfBirth,
        if (gender != null) 'gender': gender,
        if (nationality != null) 'nationality': nationality,
        if (weight != null) 'weight': weight.toString(),
        if (height != null) 'height': height.toString(),
        if (bloodType != null) 'blood_type': bloodType,
        if (emergName != null) 'emergency_name': emergName,
        if (emergRel != null) 'emergency_relation': emergRel,
        if (emergPhone != null) 'emergency_phone': emergPhone,
      },
      filePath: imagePath,
      fileField: 'image',
    );
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
      photoUrl: server?.photoUrl,
    );
  }
}
