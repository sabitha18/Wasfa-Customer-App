import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../data/services/app_version_service.dart';

String _t(bool ar, String en, String arabic) => ar ? arabic : en;

/// Opens the store page (Play Store / App Store app, not an in-app browser).
Future<void> _openStore(String url) async {
  if (url.isEmpty) return;
  try {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {}
}

/// FORCE update — full screen, no way back into the app. Shown when the
/// installed version is below `min_version` from GET /app/version.
class UpdateRequiredScreen extends StatelessWidget {
  final UpdateCheckResult result;
  final bool isArabic;
  const UpdateRequiredScreen({super.key, required this.result, required this.isArabic});

  @override
  Widget build(BuildContext context) {
    final ar = isArabic;
    final apiMessage = result.info?.messageFor(ar) ?? '';
    final message = apiMessage.isNotEmpty
        ? apiMessage
        : _t(ar, 'A new version of Wasfa Rx is available. Please update to continue.',
            'يتوفر إصدار جديد من تطبيق وصفة RX. يرجى التحديث للمتابعة.');

    return PopScope(
      canPop: false, // Android back can't leave this screen into the app
      child: Directionality(
        textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
        child: Scaffold(
          backgroundColor: Colors.white,
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset('assets/images/wasfa_logo.png', height: 72),
                    const SizedBox(height: 28),
                    Text(
                      _t(ar, 'Update required', 'تحديث مطلوب'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: AppColors.navy),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 14, color: AppColors.muted, height: 1.5),
                    ),
                    const SizedBox(height: 28),
                    if (result.storeUrl.isNotEmpty)
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.navy,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                            elevation: 0,
                          ),
                          onPressed: () => _openStore(result.storeUrl),
                          child: Text(_t(ar, 'Update now', 'تحديث الآن'),
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                        ),
                      )
                    else
                      Text(
                        _t(ar, 'Please update Wasfa Rx from the App Store.', 'يرجى تحديث تطبيق وصفة RX من متجر التطبيقات.'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 13, color: AppColors.navy, fontWeight: FontWeight.w600),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// OPTIONAL update — "new version available" with Update / Later. Shown when
/// the installed version is below `latest_version` (but not `min_version`).
/// Returns when the user picks either option; the app then continues.
Future<void> showOptionalUpdateDialog(BuildContext context, UpdateCheckResult result, bool isArabic) {
  final ar = isArabic;
  final apiMessage = result.info?.messageFor(ar) ?? '';
  final message = apiMessage.isNotEmpty
      ? apiMessage
      : _t(ar, 'A new version of Wasfa Rx is available with the latest improvements.',
          'يتوفر إصدار جديد من تطبيق وصفة RX مع أحدث التحسينات.');
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => Directionality(
      textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
      child: AlertDialog(
        title: Text(_t(ar, 'New version available', 'إصدار جديد متوفر')),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(_t(ar, 'Later', 'لاحقاً')),
          ),
          if (result.storeUrl.isNotEmpty)
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _openStore(result.storeUrl);
              },
              child: Text(_t(ar, 'Update', 'تحديث')),
            ),
        ],
      ),
    ),
  );
}
