import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/address_state.dart';
import '../../state/auth_state.dart';
import '../../state/locale_state.dart';
import '../../state/nav_tab_state.dart';
import 'account_screen.dart';
import 'home_screen.dart';
import 'shop_screen.dart';
import 'wishlist_screen.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/app_top_bar.dart';

/// The persistent 4-tab shell — Home / Shop / Wishlist / Account — matching
/// `renderBnav()` in the HTML prototype. The Home tab also carries the
/// `.appbar` (location row + search bar) from `renderAppbar()`, since that
/// appbar is only shown on home/store/shop/wishlist/account in the HTML.
///
/// The active tab lives in NavTabState now, not local State here — see its
/// doc for why: Store is pushed on top of this shell rather than being one
/// of these 4 tabs, and showing the identical bottom nav there (so tapping
/// Home/Wishlist/Account from Store actually switches tabs, not just pops)
/// needs something outside a single widget's own State to coordinate that.
class RootShell extends StatelessWidget {
  const RootShell({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final index = context.watch<NavTabState>().index;
    final ar = context.watch<LocaleState>().isArabic;

    // Ensures the "Delivery addresses" picker (openable from the app bar
    // on Home/Store/Wishlist, not just Account/Checkout) has something to
    // actually show the first time someone taps it, rather than depending
    // on them having visited Account or Checkout first this session — see
    // AddressState.ensureAddressesLoaded's doc. Covers both being signed
    // in already when this shell first mounts, and signing in later
    // (ensureAddressesLoaded's own guard makes repeated calls harmless, so
    // it's safe to just call this on every rebuild rather than needing
    // separate mount-time/later-login handling).
    if (auth.isSignedIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.read<AddressState>().ensureAddressesLoaded(auth.userId!);
      });
    }

    final pages = [
      Scaffold(appBar: const AppTopBar(), body: const HomeScreen()),
      const ShopScreen(showBottomNav: false),
      Scaffold(appBar: const AppTopBar(), body: const WishlistScreen()),
      Scaffold(appBar: const AppTopBar(), body: const AccountScreen()),
    ];

    // Root-level chrome — wraps the whole shell (not just one tab's body)
    // since the bottom nav itself lives here, outside any individual
    // screen's own Directionality.
    return Directionality(
      textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: const AppBottomNav(),
      ),
    );
  }
}

