import 'dart:async';
import 'dart:io' show Platform;

import 'package:package_info_plus/package_info_plus.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_config.dart';
import '../models/app_version_info.dart';

enum UpdateType { none, optional, force }

class UpdateCheckResult {
  final UpdateType type;
  final AppVersionInfo? info;

  /// Store page to open: the API's store_url, or (Android only, when the
  /// admin left it empty) the app's own Play Store page.
  final String storeUrl;

  const UpdateCheckResult(this.type, {this.info, this.storeUrl = ''});

  static const none = UpdateCheckResult(UpdateType.none);
}

/// Force / optional update check against `GET /app/version`.
///
/// Never blocks the app by mistake: ANY failure (no internet, timeout,
/// server error, missing or malformed fields) → [UpdateType.none].
class AppVersionService {
  AppVersionService._();
  static final AppVersionService instance = AppVersionService._();

  final ApiClient _client = ApiClient.instance;

  /// Short, so a slow server never holds up app start for long.
  static const Duration _timeout = Duration(seconds: 6);

  Future<UpdateCheckResult> check() async {
    try {
      final results = await Future.wait([
        _client.get(ApiConfig.appVersion),
        PackageInfo.fromPlatform(),
      ]).timeout(_timeout);

      final res = results[0];
      final pkg = results[1] as PackageInfo;
      if (res is! Map) return UpdateCheckResult.none;

      final key = Platform.isIOS ? 'ios' : 'android';
      final block = res[key];
      if (block is! Map) return UpdateCheckResult.none;
      final info = AppVersionInfo.fromJson(Map<String, dynamic>.from(block));

      final installed = pkg.version; // e.g. "1.0.0" (build number excluded)
      var storeUrl = info.storeUrl;
      if (storeUrl.isEmpty && !Platform.isIOS && pkg.packageName.isNotEmpty) {
        storeUrl = 'https://play.google.com/store/apps/details?id=${pkg.packageName}';
      }

      if (info.minVersion.isNotEmpty && compareVersions(installed, info.minVersion) < 0) {
        return UpdateCheckResult(UpdateType.force, info: info, storeUrl: storeUrl);
      }
      if (info.latestVersion.isNotEmpty && compareVersions(installed, info.latestVersion) < 0) {
        return UpdateCheckResult(UpdateType.optional, info: info, storeUrl: storeUrl);
      }
      return UpdateCheckResult.none;
    } catch (_) {
      return UpdateCheckResult.none;
    }
  }

  /// Compares "major.minor.patch" numerically ("1.0.10" > "1.0.9").
  /// Missing parts count as 0 ("1.1" == "1.1.0"); anything after a '+' or
  /// '-' (build / suffix) is ignored. Returns <0, 0 or >0.
  static int compareVersions(String a, String b) {
    List<int> parts(String v) => v
        .split(RegExp(r'[+\-]'))
        .first
        .split('.')
        .map((p) => int.tryParse(p.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
        .toList();
    final pa = parts(a), pb = parts(b);
    final len = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < len; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }
}
