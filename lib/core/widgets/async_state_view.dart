import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Centered spinner in brand navy — use for full-screen first loads.
class LoadingView extends StatelessWidget {
  final String? message;
  const LoadingView({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 30,
            height: 30,
            child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.sky),
          ),
          if (message != null) ...[
            const SizedBox(height: 12),
            Text(message!, style: const TextStyle(color: AppColors.muted, fontSize: 13.5)),
          ],
        ],
      ),
    );
  }
}

/// Full-screen "couldn't load" state with a retry button — use when a
/// screen's primary data failed to fetch (no cached/mock content to fall
/// back to).
class ErrorRetryView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const ErrorRetryView({super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: AppColors.danger.withOpacity(.1), shape: BoxShape.circle),
              child: const Icon(Icons.wifi_off_rounded, color: AppColors.danger, size: 26),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.ink, fontSize: 14, fontWeight: FontWeight.w600, height: 1.4),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.navy,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
              ),
              child: const Text('Try again', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small inline banner used when a screen already has content (e.g. cached
/// list) but a background refresh failed — non-blocking, dismissible.
class InlineErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const InlineErrorBanner({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.danger.withOpacity(.08),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: AppColors.danger.withOpacity(.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: const TextStyle(color: AppColors.danger, fontSize: 12.5, fontWeight: FontWeight.w600)),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
              child: const Text('Retry', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w800, fontSize: 12.5)),
            ),
        ],
      ),
    );
  }
}

/// Wraps a screen body with the standard loading / error / content flow.
/// Pass [hasContent] as false only for the very first load (no cached data
/// yet) so a fetch failure shows [ErrorRetryView] full-screen; once there's
/// something to show, later failures should instead use [InlineErrorBanner]
/// inside your own build (so the user doesn't lose their place).
class AsyncStateView extends StatelessWidget {
  final bool isLoading;
  final String? error;
  final VoidCallback onRetry;
  final Widget child;
  final String? loadingMessage;

  const AsyncStateView({
    super.key,
    required this.isLoading,
    required this.error,
    required this.onRetry,
    required this.child,
  }) : loadingMessage = null;

  @override
  Widget build(BuildContext context) {
    if (isLoading) return LoadingView(message: loadingMessage);
    if (error != null) return ErrorRetryView(message: error!, onRetry: onRetry);
    return child;
  }
}

/// A modal, non-dismissible "working on it" overlay for actions that take a
/// moment (placing an order, saving an address) — blocks double-taps.
Future<void> showBusyOverlay(BuildContext context, {String message = 'Please wait…'}) {
  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.6, color: AppColors.sky),
              ),
              const SizedBox(width: 16),
              Text(message, style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600, fontSize: 13.5)),
            ],
          ),
        ),
      ),
    ),
  );
}

void hideBusyOverlay(BuildContext context) {
  if (Navigator.of(context, rootNavigator: true).canPop()) {
    Navigator.of(context, rootNavigator: true).pop();
  }
}

/// Red error toast — pairs with the green `showToast` in `toast.dart` for
/// failure states.
void showErrorToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(children: [
        const Icon(Icons.error_outline_rounded, color: Colors.white, size: 16),
        const SizedBox(width: 10),
        Expanded(
          child: Text(message, style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600)),
        ),
      ]),
      backgroundColor: AppColors.danger,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 74),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      duration: const Duration(milliseconds: 2800),
      elevation: 8,
    ),
  );
}
