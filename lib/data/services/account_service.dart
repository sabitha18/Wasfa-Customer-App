import '../../core/network/api_client.dart';
import '../../core/network/api_config.dart';
import '../../core/network/api_exception.dart';
import '../models/address.dart';
import '../models/prescription.dart';
import '../models/wallet_transaction.dart';

/// Every call here needs a signed-in [userId] — gate screens with
/// `requireLogin(context)` (see core/utils/auth_gate.dart) before calling.
class AccountService {
  AccountService._();
  static final AccountService instance = AccountService._();
  final ApiClient _client = ApiClient.instance;

  Future<WalletSummary> wallet(int userId) async {
    final res = await _client.get(ApiConfig.acctWallet, query: {'user_id': userId});
    return WalletSummary.fromJson(res as Map<String, dynamic>);
  }

  Future<List<Prescription>> prescriptions(int userId) async {
    final res = await _client.get(ApiConfig.acctRx, query: {'user_id': userId});
    final list = (res is Map ? res['rx'] ?? res['data'] ?? res['items'] : null) ?? (res is List ? res : const []);
    return (list as List).map((e) => Prescription.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<Address>> addresses(int userId) async {
    final res = await _client.get(ApiConfig.acctAddresses, query: {'user_id': userId});
    final list = (res is Map ? res['addresses'] ?? res['data'] ?? res['items'] : null) ?? (res is List ? res : const []);
    return (list as List).map((e) => Address.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Returns the saved address's server id (useful to reconcile a newly
  /// created address with its id for later edits/deletes).
  Future<int?> saveAddress(int userId, Address address) async {
    final res = await withFallbackMessage(
      () => _client.post(ApiConfig.acctAddressSave, body: address.toSaveJson(userId)),
      'Couldn\'t save this address — check the details and try again.',
    );
    if (res is Map) {
      final id = res['id'] ?? (res['address'] is Map ? res['address']['id'] : null);
      if (id != null) return id is int ? id : int.tryParse(id.toString());
    }
    return address.id;
  }

  Future<void> deleteAddress(int userId, int addressId) async {
    await withFallbackMessage(
      () => _client.post(ApiConfig.acctAddressDelete, body: {'user_id': userId, 'id': addressId}),
      'Couldn\'t delete this address right now.',
    );
  }

  Future<List<String>> wishlist(int userId) async {
    final res = await _client.get(ApiConfig.acctWishlist, query: {'user_id': userId});
    final list = (res is Map ? res['wishlist'] ?? res['skus'] ?? res['items'] : null) ?? (res is List ? res : const []);
    return (list as List).map((e) => e.toString()).toList();
  }

  /// Toggles [sku] in the wishlist; returns the new state (true = now wished).
  Future<bool> toggleWish(int userId, String sku) async {
    final res = await withFallbackMessage(
      () => _client.post(ApiConfig.acctWishToggle, body: {'user_id': userId, 'sku': sku}),
      'Couldn\'t update your wishlist for this item right now.',
    );
    if (res is Map && res.containsKey('wished')) return res['wished'] == true;
    if (res is Map && res.containsKey('added')) return res['added'] == true;
    return true;
  }
}
