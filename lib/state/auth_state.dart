import 'package:flutter/foundation.dart';
import '../core/network/api_exception.dart';
import '../core/notifications/notification_service.dart';
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

  Future<void>? _restoreFuture;

  /// Call once at app start (see main.dart) to restore a saved session.
  /// Idempotent — safe to call again from anywhere that needs to actually
  /// wait for restoration to finish (e.g. Splash, before building Home)
  /// without re-running the whole thing a second time. Returns the SAME
  /// in-flight/completed Future every time, rather than kicking off a
  /// fresh [SessionStore.load] call on every call site.
  Future<void> restore() => _restoreFuture ??= _doRestore();

  Future<void> _doRestore() async {
    final saved = await SessionStore.load();
    user = saved;
    status = saved != null ? AuthStatus.signedIn : AuthStatus.signedOut;
    if (saved != null) NotificationService.instance.registerTokenForUser(saved.id);
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
  /// True until proven otherwise — matches today's "always ask for a name"
  /// behavior if the backend response doesn't include `is_new_user` yet.
  /// Once it does, false + [knownName] set is what lets the OTP screen
  /// show "Welcome back, X" instead of a name field.
  bool isNewUser = true;
  String? knownName;

  Future<bool> requestOtp(String phone) async {
    otpSending = true;
    otpError = null;
    devOtpCode = null;
    isNewUser = true;
    knownName = null;
    notifyListeners();
    try {
      final result = await _service.requestOtp(phone);
      devOtpCode = result.devCode;
      isNewUser = result.isNewUser;
      knownName = result.existingName;
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
      NotificationService.instance.registerTokenForUser(u.id);
      return true;
    } catch (e) {
      otpError = describeError(e);
      return false;
    } finally {
      otpVerifying = false;
      notifyListeners();
    }
  }

  /// Call after a successful profile save so the newly-entered fields
  /// (e.g. email) show up immediately in the Account header without
  /// needing to sign out/in again.
  Future<void> refreshUser(AppUser u) async {
    user = u;
    await SessionStore.save(u);
    notifyListeners();
  }

  Future<void> logout() async {
    user = null;
    status = AuthStatus.signedOut;
    await SessionStore.clear();
    NotificationService.instance.clearRegisteredUser();
    notifyListeners();
  }
}
