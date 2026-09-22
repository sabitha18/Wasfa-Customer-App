import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocaleState extends ChangeNotifier {
  static const _key = 'wasfa_locale_v1';

  String lang = 'en'; // 'en' | 'ar'

  bool get isArabic => lang == 'ar';

  /// Loads the saved language choice from disk, if any. Call once at app
  /// boot (see SplashScreen._boot, alongside AuthState.restore()) — without
  /// this, [lang] always started back at 'en' on every cold launch,
  /// regardless of what the person had picked in a previous session, since
  /// this was never persisted anywhere at all before.
  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    if (saved == 'ar' || saved == 'en') {
      lang = saved!;
      notifyListeners();
    }
  }

  void toggle() {
    lang = lang == 'en' ? 'ar' : 'en';
    notifyListeners();
    SharedPreferences.getInstance().then((prefs) => prefs.setString(_key, lang));
  }
}
