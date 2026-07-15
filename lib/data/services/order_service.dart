import '../../core/network/api_client.dart';
import '../../core/network/api_config.dart';
import '../../core/network/api_exception.dart';
import '../models/address.dart';
import '../models/order.dart';

class OrderService {
  OrderService._();
  static final OrderService instance = OrderService._();
  final ApiClient _client = ApiClient.instance;

  /// Places an order. [items] is `[{id: sellerProductId, qty: n}, ...]` —
  /// the `id` must be the *seller's* product_id from the PDP, not the
  /// catalog product id (see [ApiConfig] notes on `/orders`).
  Future<PlaceOrderResult> placeOrder({
    required int userId,
    required String customerName,
    required String customerPhone,
    required Address address,
    required String payment, // cod | knet | wallet
    bool walletRedeem = false,
    String coupon = '',
    required List<Map<String, dynamic>> items,
  }) async {
    // The server's `payment` enum is strictly cod|knet|wallet. The checkout UI
    // also offers a "Card" option — Kuwait card payments run through the KNET
    // gateway, so map it to `knet` here rather than sending an invalid value
    // that the server rejects. Anything unexpected also falls back to `knet`.
    const validPayments = {'cod', 'knet', 'wallet'};
    final normalizedPayment = validPayments.contains(payment) ? payment : 'knet';
    final res = await withFallbackMessage(
      () => _client.post(ApiConfig.orders, body: {
        'user_id': userId,
        'customer': {'name': customerName, 'phone': customerPhone},
        'address': {
          'governorate_id': address.governorateId,
          'area_id': address.areaId,
          'block': address.block,
          'street': address.street,
          'building': address.building,
          'floor': address.floor,
          'flat': address.apt,
          'note': '',
        },
        'payment': normalizedPayment,
        'wallet_redeem': walletRedeem,
        'coupon': coupon,
        'items': items,
      }),
      'Couldn\'t place your order. Please try again.',
    );
    return PlaceOrderResult.fromJson(res as Map<String, dynamic>);
  }

  Future<TrackInfo> track(String code) async {
    final res = await _client.get(ApiConfig.track, query: {'code': code});
    return TrackInfo.fromJson(res as Map<String, dynamic>);
  }

  Future<List<Order>> myOrders(int userId) async {
    final res = await _client.get(ApiConfig.myOrders, query: {'user_id': userId});
    final list = (res is Map ? res['orders'] ?? res['data'] ?? res['items'] : null) ?? (res is List ? res : const []);
    return (list as List).map((e) => Order.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Order> orderDetail({required String code, required int userId}) async {
    final res = await _client.get(ApiConfig.acctOrder(code), query: {'user_id': userId});
    final map = (res is Map && res['order'] is Map) ? res['order'] as Map<String, dynamic> : res as Map<String, dynamic>;
    return Order.fromJson(map);
  }
}
