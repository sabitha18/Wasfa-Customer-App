import 'package:flutter/foundation.dart';
import '../core/network/api_exception.dart';
import '../data/models/address.dart';
import '../data/models/area_catalog.dart';
import '../data/models/delivery_charge.dart';
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

  /// The REAL, server-computed delivery charge for whatever [effectiveAddress]
  /// currently resolves to — see `GET /app/delivery-charge(/address/{id})`'s
  /// doc (ApiConfig). Kept here, on AddressState, rather than recomputed
  /// from checkout-init's own bundled `summary.delivery_fee`, because
  /// checkoutInit only ever takes `user_id` (no address override) and
  /// always reflects the account's own DEFAULT address — not necessarily
  /// whichever one is actually selected client-side. This is the one
  /// source Cart/Checkout should ever read a delivery fee from; neither
  /// screen computes one itself. Null until [refreshDeliveryCharge] has
  /// actually resolved something — callers should show a loading state for
  /// null, never a guessed number.
  DeliveryCharge? currentDeliveryCharge;
  bool deliveryChargeLoading = false;
  String? deliveryChargeError;

  /// Re-fetches [currentDeliveryCharge] for whatever [effectiveAddress]
  /// currently is: by real address id when one exists, else by area id
  /// (covers a GPS-matched [currentLocationAddress], which has no id of
  /// its own, and a guest/new address not saved yet). Called after every
  /// method below that can change what [effectiveAddress] resolves to —
  /// not awaited from those (they're synchronous), so this runs in the
  /// background and the fee updates via [notifyListeners] once it resolves.
  Future<void> refreshDeliveryCharge() async {
    final address = effectiveAddress;
    final addressId = address?.id;
    final areaId = address?.areaId;
    if (addressId == null && areaId == null) {
      currentDeliveryCharge = null;
      deliveryChargeError = null;
      notifyListeners();
      return;
    }
    deliveryChargeLoading = true;
    deliveryChargeError = null;
    notifyListeners();
    try {
      currentDeliveryCharge = addressId != null
          ? await _accountService.deliveryChargeForAddress(addressId)
          : await _accountService.deliveryChargeForArea(areaId!);
    } catch (e) {
      deliveryChargeError = describeError(e);
    } finally {
      deliveryChargeLoading = false;
      notifyListeners();
    }
  }

  void select(int index) {
    selectedIndex = index;
    useCurrentLocation = false;
    notifyListeners();
    refreshDeliveryCharge();
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
    refreshDeliveryCharge();
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

    // Re-added (2026-09-23) after an earlier removal — see git history for
    // why it was pulled before: editing "current location" used to risk
    // silently opening and overwriting an unrelated saved address. That
    // specific danger is fixed separately now (editing current location
    // always creates a new entry, never touches an existing saved one),
    // so the remaining trade-off was purely convenience-vs-accuracy,
    // decided explicitly this time: a saved address always has fuller
    // delivery details (block/street/building) than a bare GPS point, so
    // when one already exists for the exact area GPS just resolved to,
    // use it directly rather than making the person deal with "address
    // block is required" for an area they already have a complete saved
    // address for. select() sets useCurrentLocation = false, which also
    // means this method's own guard at the top naturally stops it from
    // re-triggering on the next GPS ping — it only fires again if
    // "Current location" gets explicitly re-selected afterward.
    if (matchedArea != null) {
      for (var i = 0; i < addresses.length; i++) {
        if (addresses[i].areaId == matchedArea.id) {
          select(i);
          return;
        }
      }
    }

    final previousAreaId = currentLocationAddress?.areaId;
    currentLocationAddress = Address(
      title: 'Current location',
      governorateId: matchedGov.id,
      areaId: matchedArea?.id,
      gov: matchedGov.name,
      area: matchedArea?.name ?? area ?? '',
      street: street ?? '',
    );
    notifyListeners();
    // Guarded so a GPS ping that resolves to the SAME area as before
    // (common — location updates fire repeatedly) doesn't refetch the
    // same delivery charge over and over.
    if (matchedArea?.id != previousAreaId) refreshDeliveryCharge();
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
      resolveMissingAreaIds();
    } catch (e) {
      areasError = describeError(e);
    } finally {
      areasLoading = false;
      notifyListeners();
    }
  }

  /// Best-effort recovery for a saved address missing EITHER its area ids
  /// or its area display names — whichever direction is missing, resolved
  /// from the other using [areaCatalog] (the same list the "Add address"
  /// dropdowns use).
  ///
  /// Direction 1 (id known, name missing) was needed for checkout-init's
  /// `addresses[]`, which as of 2026-07-29 sent real `governorate_id`/
  /// `area_id` but no name field at all. The backend has since added
  /// `governorate`/`area` (confirmed live, full words — not the older
  /// abbreviated `gov` key some other response used) directly to that same
  /// endpoint, so this direction should rarely trigger for it now. Left in
  /// as a safety net for any other address source that might still omit
  /// the name.
  ///
  /// Direction 2 (name known, id missing) was the original reason this
  /// existed: `governorateId`/`areaId` on [Address.fromJson] only ever try
  /// ONE guessed field name each with no confirmed-live example of their
  /// own. If some address source sends the name under a key this model
  /// doesn't try, an address could display its area name fine while still
  /// failing the governorateId/areaId null check in checkout_screen.dart's
  /// `_placeOrder` — forcing an unnecessary "Add address" sheet for an
  /// address that was never actually missing anything.
  ///
  /// Safe to call repeatedly (from wherever finishes loading last,
  /// [loadAreas] or [loadAddresses]/[hydrateAddresses], since either can
  /// resolve first) — only fills in whatever's still missing, never
  /// overwrites a value that's already there.
  void resolveMissingAreaIds() {
    if (areaCatalog.governorates.isEmpty) return;
    for (final a in addresses) {
      // Direction 1: have a real governorateId/areaId, missing the name —
      // the checkout-init case above.
      if (a.governorateId != null && a.gov.trim().isEmpty) {
        final g = areaCatalog.findGov(a.governorateId!);
        if (g != null) a.gov = g.name;
      }
      if (a.governorateId != null && a.areaId != null && a.area.trim().isEmpty) {
        final area = areaCatalog.findArea(a.areaId!);
        if (area != null) a.area = area.name;
      }
      // Direction 2: have a real name, missing the id — the original case
      // this method covered.
      if (a.governorateId != null && a.areaId != null) continue;
      final govName = a.gov.trim().toLowerCase();
      final areaName = a.area.trim().toLowerCase();
      if (govName.isEmpty && areaName.isEmpty) continue;
      for (final g in areaCatalog.governorates) {
        final govMatches = govName.isEmpty || g.name.toLowerCase() == govName || g.nameAr.toLowerCase() == govName;
        if (!govMatches) continue;
        a.governorateId ??= g.id;
        if (areaName.isNotEmpty) {
          for (final ar in g.areas) {
            if (ar.name.toLowerCase() == areaName || ar.nameAr.toLowerCase() == areaName) {
              a.areaId ??= ar.id;
              break;
            }
          }
        }
        break;
      }
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
    resolveMissingAreaIds();
    notifyListeners();
    // Always refreshed, not just when useCurrentLocation is off — even with
    // it on, effectiveAddress falls back to this just-loaded default
    // address until/unless GPS has already resolved one of its own.
    refreshDeliveryCharge();
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
        resolveMissingAreaIds();
      }
    } catch (e) {
      addressesError = describeError(e);
    } finally {
      addressesLoading = false;
      notifyListeners();
      refreshDeliveryCharge();
    }
  }

  /// Saves [address] to the server, then reflects it locally. Resolves the
  /// display gov/area names from [areaCatalog] so `address.formatted` reads
  /// correctly right away without waiting on a re-fetch.
  /// [index] is no longer used — matching now happens by id against a
  /// fresh reload of the whole list (see below), which is more reliable
  /// than trusting a locally-passed index. Kept as a parameter only so the
  /// existing call site (address_sheets.dart) doesn't need to change.
  Future<void> saveRemote(int userId, Address address, {int? index}) async {
    final gov = address.governorateId != null ? areaCatalog.findGov(address.governorateId!) : null;
    final area = address.areaId != null ? areaCatalog.findArea(address.areaId!) : null;
    if (gov != null) address.gov = gov.name;
    if (area != null) address.area = area.name;

    // The save endpoint's own response doesn't reliably return a usable id
    // (unconfirmed field name — see AccountService.saveAddress's doc, and
    // the bug this replaced: a brand-new address used to get added and
    // selected locally with a genuinely null id whenever that response
    // didn't have one). Rather than trust that response at all, reload the
    // full list from the server — which DOES have real, confirmed ids for
    // every entry — and match this address within it, so it always ends
    // up with its real id regardless of what (if anything) the save call
    // itself returned.
    final wasNew = address.id == null;
    final oldIds = wasNew ? addresses.map((a) => a.id).where((id) => id != null).toSet() : <int>{};
    await _accountService.saveAddress(userId, address);
    final fresh = await _accountService.addresses(userId);

    Address? match;
    if (wasNew) {
      // The one id in the fresh list that wasn't in our old list is almost
      // certainly the one we just added.
      final candidates = fresh.where((a) => a.id != null && !oldIds.contains(a.id)).toList();
      if (candidates.length == 1) {
        match = candidates.first;
      } else {
        // More than one new id (a concurrent add from elsewhere?) or none
        // at all — fall back to matching this address's own distinguishing
        // fields instead.
        for (final a in fresh) {
          if (a.phone == address.phone && a.block == address.block && a.street == address.street && a.building == address.building) {
            match = a;
            break;
          }
        }
      }
    } else {
      // Editing — the id is already known and doesn't change; just find
      // that same entry in the fresh list.
      match = fresh.firstWhere((a) => a.id == address.id, orElse: () => address);
    }

    if (match == null || match.id == null) {
      throw ApiException.business('This address didn\'t save correctly — please try again.');
    }

    addresses
      ..clear()
      ..addAll(fresh);
    final matchIndex = addresses.indexOf(match);
    selectedIndex = matchIndex >= 0 ? matchIndex : addresses.length - 1;
    resolveMissingAreaIds();
    notifyListeners();
    refreshDeliveryCharge();
  }

  Future<void> deleteRemote(int userId, int index) async {
    final address = addresses[index];
    if (address.id != null) {
      await _accountService.deleteAddress(userId, address.id!);
    }
    addresses.removeAt(index);
    if (selectedIndex >= addresses.length) selectedIndex = (addresses.length - 1).clamp(0, addresses.length);
    notifyListeners();
    refreshDeliveryCharge();
  }

  void upsert(Address address, {int? index}) {
    if (index != null && index >= 0) {
      addresses[index] = address;
    } else {
      addresses.add(address);
      selectedIndex = addresses.length - 1;
    }
    notifyListeners();
    refreshDeliveryCharge();
  }

  /// Clears the signed-in user's addresses and anything derived from them —
  /// call on logout. Also resets the load-once guard so the NEXT user's
  /// addresses actually get fetched. The area catalog (public data, not
  /// user-specific) is kept.
  void reset() {
    addresses.clear();
    selectedIndex = 0;
    useCurrentLocation = true;
    addressesLoading = false;
    addressesError = null;
    currentLocationAddress = null;
    currentLocationMatchFailed = false;
    currentDeliveryCharge = null;
    deliveryChargeLoading = false;
    deliveryChargeError = null;
    _addressesRequested = false;
    notifyListeners();
  }
}
