import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/notifications/notification_service.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../state/auth_state.dart';
import '../../state/locale_state.dart';
import '../../state/location_state.dart';
import 'location_gate_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  Future<void> _boot() async {
    final location = context.read<LocationState>();
    // Waited together (not just location) so Home builds with userId
    // already known. Previously this only awaited location, so Home's
    // ChangeNotifierProviders (HomeViewModel, ShopViewModel, etc.) got
    // constructed and fired their first round of API calls (`/app/home`,
    // `/app/categories`, `/app/products`, ...) BEFORE AuthState.restore()
    // (reading the saved login token from disk) had actually finished —
    // meaning that first round always went out with no user_id at all,
    // then something re-fetched a moment later once auth caught up. Every
    // app launch was doing each of those requests twice for no reason.
    await Future.wait([
      location.initialize(),
      context.read<AuthState>().restore(),
      // Loads whatever language was saved last session — without this,
      // the app always started back at English regardless of what was
      // picked before, since LocaleState itself was never persisted.
      context.read<LocaleState>().restore(),
    ]);
    if (!mounted) return;

    // Started here — not in main() — and deliberately not awaited. See
    // the comment in main.dart for why: by this point location's own
    // permission request (if it made one) has already fully resolved, so
    // there's nothing left in flight for this to collide with. Not
    // awaiting keeps push setup from delaying navigation — it finishes in
    // the background regardless of which screen the person lands on next.
    NotificationService.instance.initialize();

    if (location.status == LocationStatus.granted) {
      Navigator.of(context).pushReplacementNamed(Routes.root);
    } else {
      // Location is compulsory — anything other than "granted" routes to
      // the blocking gate screen instead of the app itself.
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LocationGateScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: _WasfaMark(),
      ),
    );
  }
}

/// Real logo (`assets/images/wasfa_logo.png`, declared under `flutter:
/// assets:` in pubspec.yaml) — replaces the earlier code-drawn "℞" +
/// "WASFA" text placeholder this comment used to describe swapping out.
class _WasfaMark extends StatelessWidget {
  const _WasfaMark();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset('assets/images/wasfa_logo.png', width: 180),
        const SizedBox(height: 24),
        const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.sky)),
      ],
    );
  }
}
