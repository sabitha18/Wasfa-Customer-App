import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// A random UUID that identifies this phone's guest cart on the server
/// (`device_token` in the `/app/cart*` APIs). Generated once, saved in
/// SharedPreferences, and reused for the life of the install.
///
/// Guest (not signed in): cart APIs send this instead of `user_id`.
/// Signed in: cart APIs send only `user_id` (confirmed by backend).
/// After login, `POST /app/cart/assign` moves every cart row under this
/// token to the user.
class DeviceTokenStore {
  DeviceTokenStore._();

  static const _key = 'wasfa_device_token_v1';
  static String? _cached;

  static Future<String> get() async {
    if (_cached != null) return _cached!;
    final prefs = await SharedPreferences.getInstance();
    var token = prefs.getString(_key);
    if (token == null || token.isEmpty) {
      token = const Uuid().v4();
      await prefs.setString(_key, token);
    }
    _cached = token;
    return token;
  }
}
