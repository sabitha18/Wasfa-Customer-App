import 'package:flutter/foundation.dart';

class LocaleState extends ChangeNotifier {
  String lang = 'en'; // 'en' | 'ar'

  bool get isArabic => lang == 'ar';

  void toggle() {
    lang = lang == 'en' ? 'ar' : 'en';
    notifyListeners();
  }
}
