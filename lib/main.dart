import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/routing/app_router.dart';
import 'core/routing/app_routes.dart';
import 'core/theme/app_theme.dart';
import 'state/address_state.dart';
import 'state/auth_state.dart';
import 'state/cart_state.dart';
import 'state/locale_state.dart';
import 'state/location_state.dart';
import 'state/orders_state.dart';

void main() {
  runApp(const WasfaApp());
}

class WasfaApp extends StatelessWidget {
  const WasfaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // "Model" layer shared app-wide — CartState/OrdersState/AddressState
        // double as the app's cross-screen ViewModels (see README section
        // "Architecture notes"), while per-screen ViewModels in lib/viewmodels
        // hold state that's local to a single screen.
        ChangeNotifierProvider(create: (_) => LocaleState()),
        ChangeNotifierProvider(create: (_) => AuthState()..restore()),
        ChangeNotifierProvider(create: (_) => LocationState()),
        ChangeNotifierProvider(create: (_) => CartState()),
        ChangeNotifierProvider(create: (_) => OrdersState()),
        ChangeNotifierProvider(create: (_) => AddressState()),
      ],
      child: MaterialApp(
        title: 'WASFA',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        initialRoute: Routes.splash,
        onGenerateRoute: AppRouter.onGenerateRoute,
      ),
    );
  }
}
