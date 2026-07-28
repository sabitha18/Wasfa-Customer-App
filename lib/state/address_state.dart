import 'package:flutter/foundation.dart';
import '../core/network/api_exception.dart';
import '../data/models/address.dart';
import '../data/models/area_catalog.dart';
import '../data/services/account_service.dart';
import '../data/services/catalog_service.dart';

class AddressState extends ChangeNotifier {
  final CatalogService _catalogService = CatalogService.instance;
  final AccountService _accountService = AccountService.instance;

  /// Starts genuinely empty — no placeholder/dummy address. Populated only
  /// by [loadAddresses] (a real fetch) or [upsert]/[saveRemote] (the person
  /// actually adding one). A blank "Home/Apartment" placeholder used to sit
  /// here until the first real fetch replaced it — but if a signed-in
  /// person genuinely has zero saved addresses, that fetch returns an empty
  /// list and never clears it, so it just sat there permanently looking
  /// like a real, selectable address on Checkout.
  final List<Address> addresses = [];
  int selectedIndex = 0;

  /// True = "Deliver to <GPS area>" (the default), following [LocationState]
  /// directly rather than any saved address. False = the person explicitly
  /// picked a saved address from the picker sheet, so [selected] should be
  /// shown/used instead. Starts true so a fresh install/session defaults to
  /// auto-detected current location, per the intended behaviour.
  bool useCurrentLocation = true;

  bool addressesLoading = false;
  String? addressesError;

  AreaCatalog areaCatalog = AreaCatalog.empty;
  bool areasLoading = false;
  String? areasError;

  /// Null if there are genuinely no saved addresses yet — see [addresses]'
  /// doc for why this doesn't fall back to a fake placeholder instead.
  Address? get selected => addresses.isEmpty ? null : addresses[selectedIndex.clamp(0, addresses.length - 1)];

  /// A synthesized Address built from the device's GPS-detected area,
  /// matched against the real `/areas` catalog — see [syncFromLocation].
  /// Null until that matching has actually run (or found nothing).
  Address? currentLocationAddress;

  /// True once [syncFromLocation] has actually tried matching the device's
  /// GPS-detected governorate against the real catalog and found NOTHING —
  /// distinct from simply "hasn't tried yet". Needed because that first
  /// state is temporary (worth retrying once location/catalog data
  /// arrives) while this one is durable: e.g. testing/traveling from
  /// outside Kuwait entirely, where no retry will ever produce a match.
  /// Without this distinction, the picker sheet kept showing "Current
  /// location" as the active selection forever, while [effectiveAddress]
  /// was silently using a completely different saved address underneath —
  /// two parts of the UI permanently disagreeing about what's selected.
  bool currentLocationMatchFailed = false;

  /// What Checkout/order-placement should actually use: the GPS-matched
  /// address while [useCurrentLocation] is on (falling back to [selected]
  /// if the GPS area hasn't matched anything in the catalog yet), or the
  /// explicitly-picked saved address otherwise. Null if none of those
  /// resolved to anything — callers need to handle that (prompt to add an
  /// address), not assume one always exists.
  Address? get effectiveAddress => useCurrentLocation ? (currentLocationAddress ?? selected) : selected;

  /// True only when "Current location" is BOTH selected AND actually
  /// resolved to something usable — i.e. what [effectiveAddress] is really
  /// using right now. Use this (not the raw [useCurrentLocation] flag)
  /// anywhere the UI needs to show which option is genuinely active, so a
  /// permanently-unmatchable GPS location can't keep showing as selected
  /// while a different saved address is silently used underneath.
  bool get isCurrentLocationActive => useCurrentLocation && !(currentLocationAddress == null && currentLocationMatchFailed);

  void select(int index) {
    selectedIndex = index;
    useCurrentLocation = false;
    notifyListeners();
  }

  /// Switches back to following the device's GPS location instead of a
  /// saved address — the picker sheet's "Current location" tile. Resets
  /// [currentLocationMatchFailed] so a fresh [syncFromLocation] attempt
  /// (e.g. after the person has actually moved, or just re-tapped the
  /// tile) isn't stuck showing the previous attempt's failure forever.
  void selectCurrentLocation() {
    useCurrentLocation = true;
    currentLocationMatchFailed = false;
    notifyListeners();
  }

  /// Matches the device's reverse-geocoded governorate/area (from
  /// [LocationState]) against the real `/areas` catalog by name, and
  /// builds [currentLocationAddress] from whatever matches — this is what
  /// Normalizes a governorate name for matching — reverse-geocoding
  /// (`Placemark.administrativeArea`, via the `geocoding` package) commonly
  /// returns Kuwait governorates with extra words the backend catalog's
  /// clean names don't have (e.g. "Al Asimah Governorate" vs just "Al
  /// Asimah", or "Capital Governorate" as an entirely different English
  /// name for the same place) — an exact string match was failing for
  /// real, legitimate in-Kuwait locations purely over formatting, not
  /// because the location genuinely couldn't be matched. Strips common
  /// suffix words, "al"/"al-" prefixes, and extra whitespace so "Al Asimah
  /// Governorate" and "Asimah" both normalize to the same thing.
  static String _normalizeGovName(String s) {
    var n = s.trim().toLowerCase();
    for (final suffix in const ['governorate', 'province', 'muhafazah', 'muhafadhah']) {
      if (n.endsWith(suffix)) n = n.substring(0, n.length - suffix.length).trim();
    }
    if (n.startsWith('al ') || n.startsWith('al-')) n = n.substring(3).trim();
    return n.replaceAll(RegExp(r'\s+'), ' ');
  }

  /// actually lets "current location" carry a real governorate_id/area_id
  /// for delivery-fee calculation and order placement, not just a display
  /// label. No-op while [useCurrentLocation] is off, or before [areaCatalog]
  /// has loaded. Best-effort: a raw GPS reverse-geocode won't always spell
  /// area/governorate names exactly the way the catalog does, so this can
  /// legitimately find nothing — [effectiveAddress] falls back to [selected]
  /// in that case, and the existing "pick your area" checkout validation
  /// still catches it before an order can be placed without one.
  void syncFromLocation({String? governorate, String? area, String? street}) {
    if (!useCurrentLocation) return;
    if (areaCatalog.governorates.isEmpty) return;
    if (governorate == null || governorate.isEmpty) return;

    final normalizedIncoming = _normalizeGovName(governorate);
    Governorate? matchedGov;
    // Exact (normalized) match first...
    for (final g in areaCatalog.governorates) {
      if (_normalizeGovName(g.name) == normalizedIncoming) {
        matchedGov = g;
        break;
      }
    }
    // ...then a looser "one contains the other" pass, so e.g. a geocoder
    // returning "Capital" alone still matches a catalog entry named "Al
    // Asimah (Capital)" or similar, without risking a false match between
    // two genuinely different governorates that just happen to share a
    // short common substring (hence checking containment, not just any
    // shared characters).
    if (matchedGov == null) {
      for (final g in areaCatalog.governorates) {
        final normalizedCatalog = _normalizeGovName(g.name);
        if (normalizedCatalog.isEmpty || normalizedIncoming.isEmpty) continue;
        if (normalizedCatalog.contains(normalizedIncoming) || normalizedIncoming.contains(normalizedCatalog)) {
          matchedGov = g;
          break;
        }
      }
    }
    if (matchedGov == null) {
      // A real attempt was made (catalog was loaded, a governorate name was
      // present) and genuinely found nothing — e.g. the device is reporting
      // a location outside Kuwait entirely, where no amount of retrying
      // will ever produce a match. Distinguishes this durable failure from
      // simply not having tried yet.
      currentLocationMatchFailed = true;
      notifyListeners();
      return;
    }
    currentLocationMatchFailed = false;

    AreaInfo? matchedArea;
    if (area != null && area.isNotEmpty) {
      for (final a in matchedGov.areas) {
        if (a.name.toLowerCase() == area.toLowerCase()) {
          matchedArea = a;
          break;
        }
      }
    }

    currentLocationAddress = Address(
      title: 'Current location',
      governorateId: matchedGov.id,
      areaId: matchedArea?.id,
      gov: matchedGov.name,
      area: matchedArea?.name ?? area ?? '',
      street: street ?? '',
    );
    notifyListeners();
  }

  /// Governorate/area lists + delivery fees — needed for the address form
  /// dropdowns and for computing checkout delivery fees. Anonymous endpoint,
  /// safe to call before login.
  Future<void> loadAreas() async {
    if (areaCatalog.governorates.isNotEmpty || areasLoading) return;
    areasLoading = true;
    areasError = null;
    notifyListeners();
    try {
      areaCatalog = await _catalogService.areas();
    } catch (e) {
      areasError = describeError(e);
    } finally {
      areasLoading = false;
      notifyListeners();
    }
  }

  /// Feeds in addresses from another source that already fetched them
  /// (the checkout-init endpoint also returns the person's saved
  /// addresses) — only if nothing's loaded yet, so this never clobbers a
  /// fresher/already-loaded set from [loadAddresses] itself.
  void hydrateAddresses(List<Address> fetched) {
    if (addresses.isNotEmpty || fetched.isEmpty) return;
    addresses.addAll(fetched);
    final defaultIdx = addresses.indexWhere((a) => a.isDefault);
    selectedIndex = defaultIdx >= 0 ? defaultIdx : 0;
    notifyListeners();
  }

  bool _addressesRequested = false;

  /// Fetches addresses exactly ONCE per app session (see [RootShell],
  /// which calls this right at startup) — safe to call again from
  /// anywhere without worrying about duplicate fetches; only the first
  /// call actually does anything. This exists specifically because
  /// nothing was guaranteeing [addresses] was populated before the
  /// "Delivery addresses" picker sheet could be opened from the app bar
  /// (Home/Store/Wishlist) — only Account and Checkout ever proactively
  /// called [loadAddresses] themselves, so opening the picker from Home
  /// before visiting either of those screens showed a sheet with an empty
  /// list, since nothing had fetched anything yet. Account/Checkout still
  /// call [loadAddresses] directly (not this) since they want a genuinely
  /// fresh reload each time they open, not a load-once guard.
  Future<void> ensureAddressesLoaded(int userId) async {
    if (_addressesRequested) return;
    _addressesRequested = true;
    await loadAddresses(userId);
  }

  Future<void> loadAddresses(int userId) async {
    addressesLoading = true;
    addressesError = null;
    notifyListeners();
    try {
      final fetched = await _accountService.addresses(userId);
      if (fetched.isNotEmpty) {
        addresses
          ..clear()
          ..addAll(fetched);
        final defaultIdx = addresses.indexWhere((a) => a.isDefault);
        selectedIndex = defaultIdx >= 0 ? defaultIdx : 0;
      }
    } catch (e) {
      addressesError = describeError(e);
    } finally {
      addressesLoading = false;
      notifyListeners();
    }
  }

  /// Saves [address] to the server, then reflects it locally. Resolves the
  /// display gov/area names from [areaCatalog] so `address.formatted` reads
  /// correctly right away without waiting on a re-fetch.
  Future<void> saveRemote(int userId, Address address, {int? index}) async {
    final gov = address.governorateId != null ? areaCatalog.findGov(address.governorateId!) : null;
    final area = address.areaId != null ? areaCatalog.findArea(address.areaId!) : null;
    if (gov != null) address.gov = gov.name;
    if (area != null) address.area = area.name;

    final savedId = await _accountService.saveAddress(userId, address);
    address.id = savedId;
    upsert(address, index: index);
  }

  Future<void> deleteRemote(int userId, int index) async {
    final address = addresses[index];
    if (address.id != null) {
      await _accountService.deleteAddress(userId, address.id!);
    }
    addresses.removeAt(index);
    if (selectedIndex >= addresses.length) selectedIndex = (addresses.length - 1).clamp(0, addresses.length);
    notifyListeners();
  }

  void upsert(Address address, {int? index}) {
    if (index != null && index >= 0) {
      addresses[index] = address;
    } else {
      addresses.add(address);
      selectedIndex = addresses.length - 1;
    }
    notifyListeners();
  }
}
