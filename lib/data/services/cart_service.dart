import '../../core/network/api_client.dart';
import '../../core/network/api_config.dart';
import '../../core/network/api_exception.dart';

/// The regular (non-Rx) shopping cart's server-side endpoints — see
/// [ApiConfig.cart]/[cartAdd]/[cartUpdate]/[cartRemove] for the confirmed
/// request shapes. None of these have a saved example *response* yet, so
/// every parse below is a best-effort guess at plausible key names, tried
/// in order, falling back gracefully rather than throwing on a shape
/// mismatch — see each method's doc for specifics.
class CartService {
  CartService._();
  static final CartService instance = CartService._();
  final ApiClient _client = ApiClient.instance;

  /// `GET /app/cart?user_id=`. Returns the raw decoded body — there's no
  /// confirmed shape yet to build a model around, so [CartState] adapts
  /// this itself rather than this method guessing a structure that might
  /// not survive contact with a real response.
  Future<dynamic> cart(int userId) async {
    return _client.get(ApiConfig.cart, query: {'user_id': userId});
  }

  /// `POST /app/cart/add` — body: `user_id`, `product_id`, `qty`. Returns
  /// the new line's server-side `cart_id` if the response includes one
  /// under any of a few plausible keys (needed later for
  /// `POST /app/cart/remove`, which references `cart_id` rather than
  /// `product_id`) — null if none of those guesses match, in which case
  /// removing this specific line via the server just won't be possible
  /// until a `/app/cart` sync happens to pick up its real id.
  Future<int?> add(int userId, int productId, int qty) async {
    final res = await withFallbackMessage(
      () => _client.post(ApiConfig.cartAdd, body: {'user_id': userId, 'product_id': productId, 'qty': qty}),
      'Couldn\'t add this to your cart right now.',
    );
    return _extractCartId(res);
  }

  /// `POST /app/cart/update` — confirmed live request body: `user_id`,
  /// `cart_id`, `qty` (changed from `product_id` to `cart_id` — a specific
  /// cart line, not the product in general).
  Future<void> update(int userId, int cartId, int qty) async {
    await withFallbackMessage(
      () => _client.post(ApiConfig.cartUpdate, body: {'user_id': userId, 'cart_id': cartId, 'qty': qty}),
      'Couldn\'t update this item\'s quantity right now.',
    );
  }

  /// `POST /app/cart/remove` — body: `user_id`, `cart_id`, `qty`. Confirmed
  /// request shape takes `qty` too (not just an id) — unclear whether that's
  /// "remove this many" (partial) or must equal the line's full quantity to
  /// remove it entirely; passing the line's current quantity is the safer
  /// default until that's confirmed.
  Future<void> remove(int userId, int cartId, int qty) async {
    await withFallbackMessage(
      () => _client.post(ApiConfig.cartRemove, body: {'user_id': userId, 'cart_id': cartId, 'qty': qty}),
      'Couldn\'t remove this item right now.',
    );
  }

  int? _extractCartId(dynamic res) {
    if (res is! Map) return null;
    final candidate = res['cart_id'] ?? res['id'] ?? (res['cart'] is Map ? res['cart']['id'] : null) ?? (res['item'] is Map ? res['item']['id'] : null);
    if (candidate == null) return null;
    return int.tryParse(candidate.toString());
  }
}
