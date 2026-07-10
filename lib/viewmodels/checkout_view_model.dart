import 'package:flutter/foundation.dart';

class CheckoutViewModel extends ChangeNotifier {
  String pay = 'knet'; // knet | card | wallet | cod
  bool together = false;
  String slot = 'asap'; // asap | sched
  int slotTimeIndex = 0;
  String note = '';
  String? promoCode; // null = auto-best, '__none__' = none
  DateTime? scheduledDate;

  /// Which month the inline calendar is currently showing — matches
  /// `CHK.calY`/`CHK.calM`. Starts on the current month.
  DateTime calendarMonth = DateTime(DateTime.now().year, DateTime.now().month);

  void calNav(int delta) {
    calendarMonth = DateTime(calendarMonth.year, calendarMonth.month + delta);
    notifyListeners();
  }

  void setPay(String p) {
    pay = p;
    notifyListeners();
  }

  void setSlot(String s) {
    slot = s;
    notifyListeners();
  }

  void setSlotTime(int i) {
    slotTimeIndex = i;
    notifyListeners();
  }

  void setNote(String n) {
    note = n;
  }

  void setPromo(String? code) {
    promoCode = code;
    notifyListeners();
  }

  void setScheduledDate(DateTime d) {
    scheduledDate = d;
    notifyListeners();
  }
}
