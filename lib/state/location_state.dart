import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

/// Add to pubspec.yaml:
///   geolocator: ^11.0.0
///   geocoding: ^3.0.0
///
/// Add to android/app/src/main/AndroidManifest.xml (as a direct child of
/// <manifest>, alongside the INTERNET permission):
///   <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
///   <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
enum LocationStatus {
  unknown,
  requesting,
  granted,
  denied,
  deniedForever,
  serviceDisabled,

  /// Permission IS granted (and service is on) — we just couldn't get a
  /// position fix (timed out, no last-known fix either). Kept distinct from
  /// [denied] so the gate screen never tells someone who already granted
  /// permission to go grant it again.
  positionUnavailable,
}

/// Drives the mandatory location gate (splash → permission screen → app),
/// the "Deliver to <area>" header shown on Home and throughout the app, and
/// address-form autofill. There is no "skip" path by design — the person
/// asked for location to be compulsory, matching how the HTML's storefront
/// always assumes a delivery area.
class LocationState extends ChangeNotifier {
  LocationStatus status = LocationStatus.unknown;
  Position? position;

  /// Best-effort reverse-geocoded pieces — Kuwait address quality from the
  /// device's native geocoder varies, so treat these as a starting point
  /// for autofill, not a guaranteed-accurate address.
  String? area; // Placemark.subLocality, falls back to locality
  String? governorate; // Placemark.administrativeArea
  String? street; // Placemark.thoroughfare
  String? formatted; // short label for the "Deliver to" header

  bool get isReady => status == LocationStatus.granted && position != null;

  /// Call once at app start (splash screen). Requests permission if not
  /// already decided, then fetches position + reverse-geocodes it.
  Future<void> initialize() async {
    status = LocationStatus.requesting;
    notifyListeners();

    if (!await Geolocator.isLocationServiceEnabled()) {
      status = LocationStatus.serviceDisabled;
      notifyListeners();
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      try {
        // Time-boxed as defense-in-depth: if another permission dialog
        // (e.g. the notification-permission prompt) is already on screen
        // when this fires, Android silently cancels this request, but
        // Geolocator.requestPermission() itself is known to hang forever
        // afterwards rather than resolving to denied — see
        // github.com/Baseflow/flutter-geolocator/issues/1378. main.dart /
        // splash_screen.dart now sequence things so that shouldn't happen
        // in practice, but this keeps a single stray concurrent permission
        // request (present or future) from ever wedging the whole app on
        // the splash screen again.
        permission = await Geolocator.requestPermission().timeout(const Duration(seconds: 25));
      } on TimeoutException {
        status = LocationStatus.denied;
        notifyListeners();
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      status = LocationStatus.deniedForever;
      notifyListeners();
      return;
    }
    if (permission == LocationPermission.denied) {
      status = LocationStatus.denied;
      notifyListeners();
      return;
    }

    await _fetchAndGeocode();
  }

  /// Re-run after the person grants permission from the blocking screen, or
  /// to refresh location (e.g. "Use current location" tap in the address form).
  Future<void> retry() => initialize();

  /// Fetches a fresh fix with a hard time cap so the splash/gate screen can
  /// never hang indefinitely. `isFirstAttempt` guards a single quick retry
  /// for the known race where, right after a permission grant, the very
  /// first getCurrentPosition() call fails on some Android devices because
  /// the location provider hasn't finished warming up yet — permission is
  /// fine, the fix just wasn't ready in that first instant.
  Future<void> _fetchAndGeocode({bool isFirstAttempt = true}) async {
    try {
      position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 12),
      );
      status = LocationStatus.granted;
      notifyListeners();
      await _reverseGeocode();
    } on TimeoutException {
      await _fallbackToLastKnown();
    } catch (_) {
      if (isFirstAttempt) {
        await Future.delayed(const Duration(milliseconds: 600));
        return _fetchAndGeocode(isFirstAttempt: false);
      }
      await _fallbackToLastKnown();
    }
  }

  /// Called once a fresh fix has failed/timed out. A stale last-known
  /// position is still useful for delivery-radius purposes, so prefer it
  /// over showing an error. Only if there's truly nothing do we surface
  /// [LocationStatus.positionUnavailable] — never [LocationStatus.denied],
  /// since permission was already granted at this point.
  Future<void> _fallbackToLastKnown() async {
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        position = last;
        status = LocationStatus.granted;
        notifyListeners();
        await _reverseGeocode();
        return;
      }
    } catch (_) {
      // fall through to positionUnavailable below
    }
    status = LocationStatus.positionUnavailable;
    notifyListeners();
  }

  Future<void> _reverseGeocode() async {
    try {
      final marks = await placemarkFromCoordinates(position!.latitude, position!.longitude);
      if (marks.isNotEmpty) {
        final m = marks.first;
        area = (m.subLocality?.isNotEmpty == true) ? m.subLocality : m.locality;
        governorate = m.administrativeArea;
        street = m.thoroughfare;
        formatted = [area, governorate].where((s) => s != null && s.isNotEmpty).join(', ');
      }
    } catch (_) {
      // Reverse geocoding failing shouldn't block the app — the person
      // still has a valid position for delivery-radius purposes even
      // without a human-readable label.
    }
    notifyListeners();
  }
}
