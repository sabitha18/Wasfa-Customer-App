import 'package:geocoding/geocoding.dart';
import '../../data/models/address.dart';

/// Turns a saved address's human-readable area/governorate name into
/// approximate coordinates — the reverse of what [LocationState] already
/// does (turning the device's real GPS coordinates into an area name).
/// Uses the same `geocoding` package, already a dependency for that
/// reverse lookup.
///
/// This exists because [Address] itself carries no coordinates at all
/// (only `governorate_id`/`area_id` + human-readable `gov`/`area` names) —
/// there's no other source of a lat/lng for "this saved address" anywhere
/// in the app or a confirmed backend field. Forward-geocoding the area
/// name is an approximation (it resolves to roughly the area's center,
/// not the exact building), not the same precision as real GPS — worth
/// knowing when interpreting "nearest stores" results for a saved address
/// versus "Current location" (which uses the device's exact GPS fix).
class AddressGeocoder {
  AddressGeocoder._();
  static final AddressGeocoder instance = AddressGeocoder._();

  final Map<String, ({double lat, double lng})> _cache = {};

  Future<({double? lat, double? lng})> forAddress(Address address) async {
    final key = '${address.governorateId}_${address.areaId}';
    final cached = _cache[key];
    if (cached != null) return (lat: cached.lat, lng: cached.lng);

    final query = [address.area, address.gov, 'Kuwait'].where((s) => s.isNotEmpty).join(', ');
    if (query.isEmpty || query == 'Kuwait') return (lat: null, lng: null);

    try {
      final results = await locationFromAddress(query);
      if (results.isEmpty) return (lat: null, lng: null);
      final loc = results.first;
      _cache[key] = (lat: loc.latitude, lng: loc.longitude);
      return (lat: loc.latitude, lng: loc.longitude);
    } catch (_) {
      // Geocoding can fail for all sorts of reasons (no network, the
      // query not resolving to anything, platform geocoder hiccups) —
      // treat it the same as "couldn't resolve", not a crash.
      return (lat: null, lng: null);
    }
  }
}
