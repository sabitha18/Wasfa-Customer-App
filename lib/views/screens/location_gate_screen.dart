import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../state/location_state.dart';

/// Location is a hard requirement for this app (delivery estimates, nearby
/// pharmacies, address autofill) — there is intentionally no "skip" or
/// "not now" option here. The person stays on this screen until they grant
/// permission (or enable location services), then it routes into the app.
class LocationGateScreen extends StatelessWidget {
  const LocationGateScreen({super.key});

  Future<void> _retry(BuildContext context) async {
    final location = context.read<LocationState>();
    await location.retry();
    if (!context.mounted) return;
    if (location.status == LocationStatus.granted) {
      Navigator.of(context).pushReplacementNamed(Routes.root);
    }
  }

  @override
  Widget build(BuildContext context) {
    final location = context.watch<LocationState>();
    final deniedForever = location.status == LocationStatus.deniedForever;
    final serviceOff = location.status == LocationStatus.serviceDisabled;

    final String title = serviceOff
        ? 'Turn on location services'
        : deniedForever
            ? 'Location access is blocked'
            : 'Enable location to continue';
    final String body = serviceOff
        ? 'Your device\'s location services are switched off. Turn them on to continue — WASFA needs your location for delivery estimates, nearby pharmacies, and address autofill.'
        : deniedForever
            ? 'You\'ve previously denied location access. Open your device settings and allow location for WASFA to continue.'
            : 'WASFA needs your location to show accurate delivery times, nearby pharmacies, and to fill in your address automatically. This is required to use the app.';

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(color: AppColors.blush, borderRadius: BorderRadius.circular(24)),
                alignment: Alignment.center,
                child: const Icon(Icons.location_on_rounded, color: AppColors.rose, size: 40),
              ),
              const SizedBox(height: 24),
              Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.navy)),
              const SizedBox(height: 10),
              Text(body, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13.5, color: AppColors.muted, height: 1.5)),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    if (deniedForever) {
                      await Geolocator.openAppSettings();
                    } else if (serviceOff) {
                      await Geolocator.openLocationSettings();
                    } else {
                      await _retry(context);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.navy,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                  ),
                  child: Text(
                    deniedForever ? 'Open settings' : serviceOff ? 'Open location settings' : 'Enable location',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
              ),
              if (deniedForever || serviceOff) ...[
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => _retry(context),
                  child: const Text('I\'ve enabled it — check again', style: TextStyle(color: AppColors.sky, fontWeight: FontWeight.w700)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
