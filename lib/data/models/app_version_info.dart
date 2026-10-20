import '../../core/utils/json_utils.dart';

/// One platform's block from `GET /app/version`:
/// `{ min_version, latest_version, store_url, message, message_ar }`.
/// Edited in the admin panel (App version), separately for Android / iOS.
class AppVersionInfo {
  /// Below this → force update (app blocked until updated).
  final String minVersion;

  /// Below this (but not below [minVersion]) → optional "new version" prompt.
  final String latestVersion;

  /// Store page the Update button opens.
  final String storeUrl;

  /// Optional custom text for the update screen/prompt (empty = default text).
  final String message;
  final String messageAr;

  const AppVersionInfo({
    required this.minVersion,
    required this.latestVersion,
    required this.storeUrl,
    required this.message,
    required this.messageAr,
  });

  factory AppVersionInfo.fromJson(Map<String, dynamic> json) => AppVersionInfo(
        minVersion: asString(json, const ['min_version']).trim(),
        latestVersion: asString(json, const ['latest_version']).trim(),
        storeUrl: asString(json, const ['store_url']).trim(),
        message: asString(json, const ['message']).trim(),
        messageAr: asString(json, const ['message_ar']).trim(),
      );

  String messageFor(bool isArabic) => isArabic ? messageAr : message;
}
