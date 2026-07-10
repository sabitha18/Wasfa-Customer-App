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

  /// Saves personal info for the account/profile screen.
  Future<void> saveProfile({
    required int userId,
    required String firstName,
    required String lastName,
    String? email,
    String? phone,
    String? civilId,
    String? dateOfBirth,
    String? gender,
    String? nationality,
  }) async {
    await _client.post(ApiConfig.acctProfile, body: {
      'user_id': userId,
      'first_name': firstName,
      'last_name': lastName,
      if (email != null) 'email': email,
      if (phone != null) 'phone': phone,
      if (civilId != null) 'civil_id': civilId,
      if (dateOfBirth != null) 'date_of_birth': dateOfBirth,
      if (gender != null) 'gender': gender,
      if (nationality != null) 'nationality': nationality,
    });
  }
}
