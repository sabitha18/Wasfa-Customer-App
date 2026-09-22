import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/cart_state.dart';
import '../../state/locale_state.dart';
import '../../state/nav_tab_state.dart';

/// The same 4-tab Home/Shop/Wishlist/Account bar RootShell shows, usable
/// from a screen PUSHED on top of it (Store) too — see NavTabState's doc.
/// [embedded] (RootShell's own usage) just switches the shared tab index
/// in place. A pushed screen instead pops back to RootShell first, then
/// switches — passing [embedded]: false.
class AppBottomNav extends StatelessWidget {
  final bool embedded;
  const AppBottomNav({super.key, this.embedded = true});

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartState>();
    final navTab = context.watch<NavTabState>();
    final ar = context.watch<LocaleState>().isArabic;
    String t(String en, String arabic) => ar ? arabic : en;

    void go(int i) {
      context.read<NavTabState>().setTab(i);
      if (!embedded) {
        // Pushed screen (Store): the 4 tabs live on RootShell, further
        // down the Navigator stack, not here — pop back to it now that
        // the tab's switched, so it's showing the right one underneath.
        Navigator.popUntil(context, (r) => r.isFirst);
      }
    }

    return BottomNavigationBar(
      currentIndex: navTab.index,
      onTap: go,
      items: [
        BottomNavigationBarItem(icon: const Icon(Icons.home_outlined), label: t('Home', 'الرئيسية')),
        BottomNavigationBarItem(icon: const Icon(Icons.grid_view_rounded), label: t('Shop', 'المتجر')),
        BottomNavigationBarItem(
          icon: Badge(
            label: Text('${cart.wishlist.length}'),
            isLabelVisible: cart.wishlist.isNotEmpty,
            child: const Icon(Icons.favorite_border_rounded),
          ),
          label: t('Wishlist', 'المفضلة'),
        ),
        BottomNavigationBarItem(icon: const Icon(Icons.person_outline_rounded), label: t('Account', 'الحساب')),
      ],
    );
  }
}
