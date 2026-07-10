import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/models/app_user.dart';

/// Add to pubspec.yaml:
///   shared_preferences: ^2.2.0
///
/// The API is stateless (no bearer token) — the only thing that makes a
/// request "authenticated" is sending `user_id`. We still persist the whole
/// user object locally so the account UI (name, phone) doesn't need a
/// network round trip just to render the Account tab header.
class SessionStore {
  SessionStore._();
  static const _key = 'wasfa_user_v1';

  static Future<void> save(AppUser user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(user.toJson()));
  }

  static Future<AppUser?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    try {
      return AppUser.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
