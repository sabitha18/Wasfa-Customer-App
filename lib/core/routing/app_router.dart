import 'package:flutter/material.dart';
import '../../data/models/pharmacy_store.dart';
import '../../views/screens/account_screen.dart';
import '../../views/screens/brands_screen.dart';
import '../../views/screens/cart_screen.dart';
import '../../views/screens/checkout_screen.dart';
import '../../views/screens/coming_soon_screen.dart';
import '../../views/screens/my_rx_screen.dart';
import '../../views/screens/notifications_screen.dart';
import '../../views/screens/order_detail_screen.dart';
import '../../views/screens/orders_screen.dart';
import '../../views/screens/login_screen.dart';
import '../../views/screens/profile_screen.dart';
import '../../views/screens/splash_screen.dart';
import '../../views/screens/pharmacies_screen.dart';
import '../../views/screens/product_screen.dart';
import '../../views/screens/requests_screen.dart';
import '../../views/screens/root_shell.dart';
import '../../views/screens/rx_detail_screen.dart';
import '../../views/screens/shop_screen.dart';
import '../../viewmodels/shop_view_model.dart';
import '../../views/screens/store_screen.dart';
import '../../views/screens/track_screen.dart';
import '../../views/screens/wallet_screen.dart';
import '../../views/screens/wishlist_screen.dart';
import 'app_routes.dart';

class AppRouter {
  AppRouter._();

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    final args = settings.arguments;

    switch (settings.name) {
      case Routes.splash:
        return _page(const SplashScreen());
      case Routes.root:
        return _page(const RootShell());
      case Routes.login:
        return _page(const LoginScreen());
      case Routes.profile:
        return _page(const ProfileScreen());

      // ---- ✅ Phase 1 -----------------------------------------------------
      case Routes.store:
        return _page(StoreScreen(store: args as PharmacyStore));
      case Routes.brands:
        return _page(BrandsScreen(store: args as PharmacyStore?));
      case Routes.shop:
        // Was silently dropping any filter argument before (always opened
        // a plain, unfiltered ShopScreen) — needed so anything that wants
        // to deep-link into Shop pre-filtered (e.g. a home banner linking
        // to "?deals=1") actually works instead of just landing on the
        // full, unfiltered catalogue.
        return _page(ShopScreen(initialFilter: args as ShopFilter?));
      case Routes.product:
        return _page(ProductScreen(productId: args as int));
      case Routes.wishlist:
        return _page(Scaffold(appBar: AppBar(title: const Text('Wishlist')), body: const WishlistScreen()));
      case Routes.account:
        return _page(Scaffold(appBar: AppBar(title: const Text('Account')), body: const AccountScreen()));
      case Routes.cart:
        return _page(const CartScreen());
      case Routes.checkout:
        return _page(const CheckoutScreen());
      case Routes.track:
        return _page(TrackScreen(orderId: args as String));
      case Routes.myRx:
        return _page(const MyRxScreen());
      case Routes.rxDetail:
        return _page(RxDetailScreen(rxId: args as String));
      case Routes.wallet:
        return _page(const WalletScreen());
      case Routes.orders:
        return _page(const OrdersScreen());
      case Routes.orderDetail:
        return _page(OrderDetailScreen(orderId: args as String));
      case Routes.pharmacies:
        return _page(const PharmaciesScreen());
      case Routes.requests:
        return _page(const RequestsScreen());
      case Routes.notifications:
        return _page(const NotificationsScreen());

      // ---- 🚧 Phase 2 — placeholder screens --------------------------------
      default:
        return _page(ComingSoonScreen(title: _titleFor(settings.name ?? '')));
    }
  }

  static MaterialPageRoute _page(Widget child) => MaterialPageRoute(builder: (_) => child);

  static String _titleFor(String route) {
    if (route.isEmpty) return 'Not found';
    return route[0].toUpperCase() + route.substring(1);
  }
}
