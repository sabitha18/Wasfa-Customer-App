import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
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
    await location.initialize();
    if (!mounted) return;

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

/// Code-drawn wordmark placeholder — swap for the real logo asset whenever
/// one is available: drop it at e.g. `assets/logo.png`, declare it under
/// `flutter: assets:` in pubspec.yaml, and replace this widget's body with
/// `Image.asset('assets/logo.png', width: 96)`.
class _WasfaMark extends StatelessWidget {
  const _WasfaMark();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [AppColors.navy, AppColors.sky], begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(24),
            boxShadow: AppColors.sh,
          ),
          alignment: Alignment.center,
          child: const Text('℞', style: TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(height: 16),
        const Text('WASFA', style: TextStyle(color: AppColors.navy, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
        const SizedBox(height: 24),
        const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.sky)),
      ],
    );
  }
}
