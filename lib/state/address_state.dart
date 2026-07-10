import 'package:flutter/foundation.dart';
import '../core/network/api_exception.dart';
import '../data/models/address.dart';
import '../data/models/area_catalog.dart';
import '../data/repositories/catalog_repository.dart';
import '../data/services/account_service.dart';
import '../data/services/catalog_service.dart';

class AddressState extends ChangeNotifier {
  final CatalogService _catalogService = CatalogService.instance;
  final AccountService _accountService = AccountService.instance;

  final List<Address> addresses = [CatalogRepository.instance.defaultAddress()];
  int selectedIndex = 0;

  bool addressesLoading = false;
  String? addressesError;

  AreaCatalog areaCatalog = AreaCatalog.empty;
  bool areasLoading = false;
  String? areasError;

  Address get selected => addresses[selectedIndex.clamp(0, addresses.length - 1)];

  void select(int index) {
    selectedIndex = index;
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
        selectedIndex = 0;
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
    if (addresses.isEmpty) addresses.add(CatalogRepository.instance.defaultAddress());
    if (selectedIndex >= addresses.length) selectedIndex = addresses.length - 1;
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
