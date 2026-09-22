import 'package:flutter/foundation.dart';

/// Which of RootShell's 4 tabs (Home/Shop/Wishlist/Account) is active —
/// shared app-wide rather than kept as RootShell's own local State, so a
/// screen PUSHED on top of RootShell (Store, which isn't itself one of
/// the 4 tabs) can show the identical-looking bottom nav and actually
/// switch tabs from there too: pop back to RootShell, then set this,
/// and RootShell (which now just reads this instead of owning the index
/// itself) shows the newly-selected tab immediately.
class NavTabState extends ChangeNotifier {
  int index = 0;

  void setTab(int i) {
    if (index == i) return;
    index = i;
    notifyListeners();
  }
}
