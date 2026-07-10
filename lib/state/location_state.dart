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
enum LocationStatus { unknown, requesting, granted, denied, deniedForever, serviceDisabled }

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
      permission = await Geolocator.requestPermission();
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

  Future<void> _fetchAndGeocode() async {
    try {
      position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium);
      status = LocationStatus.granted;
      notifyListeners();

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
    } catch (e) {
      status = LocationStatus.denied;
      notifyListeners();
    }
  }
}
