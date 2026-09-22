import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../state/locale_state.dart';
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
    final ar = context.watch<LocaleState>().isArabic;
    final deniedForever = location.status == LocationStatus.deniedForever;
    final serviceOff = location.status == LocationStatus.serviceDisabled;
    // Permission IS granted here — a fresh fix just failed/timed out. Kept
    // visually distinct from the "please grant permission" copy below so
    // someone who already tapped Allow isn't told to do it again.
    final positionUnavailable = location.status == LocationStatus.positionUnavailable;

    final String title = serviceOff
        ? (ar ? 'تفعيل خدمات الموقع' : 'Turn on location services')
        : deniedForever
            ? (ar ? 'الوصول إلى الموقع محظور' : 'Location access is blocked')
            : positionUnavailable
                ? (ar ? 'تعذر الحصول على موقعك' : 'Couldn\'t get your location')
                : (ar ? 'فعّل الموقع للمتابعة' : 'Enable location to continue');
    final String body = serviceOff
        ? (ar
            ? 'خدمات الموقع في جهازك مغلقة. فعّلها للمتابعة — يحتاج تطبيق وصفة إلى موقعك لتقدير أوقات التوصيل، وإيجاد الصيدليات القريبة، وتعبئة عنوانك تلقائياً.'
            : 'Your device\'s location services are switched off. Turn them on to continue — WASFA needs your location for delivery estimates, nearby pharmacies, and address autofill.')
        : deniedForever
            ? (ar
                ? 'لقد رفضت الوصول إلى الموقع سابقاً. افتح إعدادات جهازك واسمح بالوصول إلى الموقع لمتابعة استخدام وصفة.'
                : 'You\'ve previously denied location access. Open your device settings and allow location for WASFA to continue.')
            : positionUnavailable
                ? (ar
                    ? 'تم السماح بالوصول إلى الموقع، لكن تعذر تحديد موقعك عبر GPS. تأكد من وجود إشارة جيدة (أو تفعيل الواي فاي) وحاول مرة أخرى.'
                    : 'Location access is allowed, but we couldn\'t get a GPS fix. Make sure you have a clear signal (or Wi-Fi is on) and try again.')
                : (ar
                    ? 'يحتاج تطبيق وصفة إلى موقعك لعرض أوقات توصيل دقيقة، وإيجاد الصيدليات القريبة، وتعبئة عنوانك تلقائياً. هذا الأمر مطلوب لاستخدام التطبيق.'
                    : 'WASFA needs your location to show accurate delivery times, nearby pharmacies, and to fill in your address automatically. This is required to use the app.');

    return Directionality(
      textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
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
                    deniedForever
                        ? (ar ? 'فتح الإعدادات' : 'Open settings')
                        : serviceOff
                            ? (ar ? 'فتح إعدادات الموقع' : 'Open location settings')
                            : positionUnavailable
                                ? (ar ? 'حاول مرة أخرى' : 'Try again')
                                : (ar ? 'تفعيل الموقع' : 'Enable location'),
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
              ),
              if (deniedForever || serviceOff) ...[
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => _retry(context),
                  child: Text(ar ? 'لقد قمت بتفعيله — تحقق مرة أخرى' : 'I\'ve enabled it — check again', style: const TextStyle(color: AppColors.sky, fontWeight: FontWeight.w700)),
                ),
              ],
            ],
          ),
        ),
      ),
      ),
    );
  }
}
