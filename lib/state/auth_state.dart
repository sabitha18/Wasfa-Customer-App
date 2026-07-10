import 'package:flutter/foundation.dart';
import '../core/network/api_exception.dart';
import '../core/utils/session_store.dart';
import '../data/models/app_user.dart';
import '../data/services/auth_service.dart';

enum AuthStatus { unknown, signedOut, signedIn }

/// Mirrors the other cross-screen "state" classes (CartState, OrdersState).
/// The API has no bearer token — being "signed in" just means we have a
/// `user_id` to attach to account calls, persisted locally via
/// [SessionStore] so the person doesn't have to OTP every launch.
class AuthState extends ChangeNotifier {
  final AuthService _service = AuthService.instance;

  AuthStatus status = AuthStatus.unknown;
  AppUser? user;

  bool get isSignedIn => status == AuthStatus.signedIn && user != null;
  int? get userId => user?.id;

  /// Call once at app start (see main.dart) to restore a saved session.
  Future<void> restore() async {
    final saved = await SessionStore.load();
    user = saved;
    status = saved != null ? AuthStatus.signedIn : AuthStatus.signedOut;
    notifyListeners();
  }

  // ------------------------------------------------------------ OTP login
  bool otpSending = false;
  bool otpVerifying = false;
  String? otpError;
  String phoneInFlight = '';
  /// The code itself, ONLY when the backend's `/otp/request` response
  /// includes a `dev_code` field (their sandbox/testing mode, before the SMS
  /// gateway is live in production). Null the moment that field is absent —
  /// so this naturally disappears on its own once they go live with real SMS.
  String? devOtpCode;

  Future<bool> requestOtp(String phone) async {
    otpSending = true;
    otpError = null;
    devOtpCode = null;
    notifyListeners();
    try {
      devOtpCode = await _service.requestOtp(phone);
      phoneInFlight = phone;
      return true;
    } catch (e) {
      otpError = describeError(e);
      return false;
    } finally {
      otpSending = false;
      notifyListeners();
    }
  }

  Future<bool> verifyOtp({required String code, String? name}) async {
    otpVerifying = true;
    otpError = null;
    notifyListeners();
    try {
      final u = await _service.verifyOtp(phone: phoneInFlight, code: code, name: name);
      user = u;
      status = AuthStatus.signedIn;
      await SessionStore.save(u);
      return true;
    } catch (e) {
      otpError = describeError(e);
      return false;
    } finally {
      otpVerifying = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    user = null;
    status = AuthStatus.signedOut;
    await SessionStore.clear();
    notifyListeners();
  }
}
