import '../../core/network/api_client.dart';
import '../../core/network/api_config.dart';
import '../../core/network/api_exception.dart';
import '../models/address.dart';
import '../models/checkout_init.dart';
import '../models/delivery_charge.dart';
import '../models/legal_page.dart';
import '../models/prescription.dart';
import '../models/server_notification.dart';
import '../models/wallet_transaction.dart';

/// Every call here needs a signed-in [userId] — gate screens with
/// `requireLogin(context)` (see core/utils/auth_gate.dart) before calling.
class AccountService {
  AccountService._();
  static final AccountService instance = AccountService._();
  final ApiClient _client = ApiClient.instance;

  /// See ApiConfig.page's doc — confirmed live for all 5 slugs. Anonymous
  /// — no user_id needed, matches this being static legal/support content.
  Future<LegalPage> page(String slug) async {
    final res = await _client.get(ApiConfig.page(slug));
    return LegalPage.fromJson(res as Map<String, dynamic>);
  }

  /// See ApiConfig.deliveryChargeByArea's doc.
  Future<DeliveryCharge> deliveryChargeForArea(int areaId) async {
    final res = await _client.get(ApiConfig.deliveryChargeByArea, query: {'area_id': areaId});
    return DeliveryCharge.fromJson(res as Map<String, dynamic>);
  }

  /// See ApiConfig.deliveryChargeByAddress's doc.
  Future<DeliveryCharge> deliveryChargeForAddress(int addressId) async {
    final res = await _client.get(ApiConfig.deliveryChargeByAddress(addressId));
    return DeliveryCharge.fromJson(res as Map<String, dynamic>);
  }

  Future<WalletSummary> wallet(int userId) async {
    final res = await _client.get(ApiConfig.acctWallet, query: {'user_id': userId});
    return WalletSummary.fromJson(res as Map<String, dynamic>);
  }

  /// ✅ Confirmed live (2026-07-30): `GET /app/acct/rx?user_id=` returns a
  /// bare array, not wrapped under `rx`/`data`/`items` — the fallback logic
  /// below already handled this case correctly, this was just unconfirmed
  /// until now.
  Future<List<Prescription>> prescriptions(int userId) async {
    final res = await _client.get(ApiConfig.acctRxList, query: {'user_id': userId});
    final list = (res is Map ? res['rx'] ?? res['data'] ?? res['items'] : null) ?? (res is List ? res : const []);
    return (list as List).map((e) => Prescription.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// `GET /app/acct/rx/{id}` — confirmed live path for a single
  /// prescription's detail (see [ApiConfig.acctRxDetail]).
  Future<Prescription> prescriptionDetail(int userId, String rxId) async {
    final res = await _client.get(ApiConfig.acctRxDetail(rxId), query: {'user_id': userId});
    // Tolerate either a bare prescription object or one wrapped under a key,
    // matching the flexible-wrapper pattern used elsewhere in this file.
    final obj = (res is Map && res['rx'] is Map) ? res['rx'] : ((res is Map && res['data'] is Map) ? res['data'] : res);
    return Prescription.fromJson(obj as Map<String, dynamic>);
  }

  /// `POST /app/acct/rx/add-to-cart` — confirmed live request shape:
  /// `user_id`, `prescription_id`, `item_ids[0]`, `item_ids[1]`, ...
  /// Response shape is unconfirmed; callers should treat this as
  /// fire-and-confirm (throws on failure) rather than parsing a specific
  /// result from it.
  Future<void> addToRxCart(int userId, String prescriptionId, List<String> itemIds) async {
    final body = <String, dynamic>{'user_id': userId, 'prescription_id': prescriptionId};
    for (var i = 0; i < itemIds.length; i++) {
      body['item_ids[$i]'] = itemIds[i];
    }
    await withFallbackMessage(
      () => _client.post(ApiConfig.acctRxAddToCart, body: body),
      'Couldn\'t add this to your Rx cart right now.',
    );
  }

  /// `GET /app/acct/rx/cart?user_id=` — response shape unconfirmed; returns
  /// the raw decoded body so callers can adapt once the real shape is known
  /// rather than guessing a model that might not match.
  Future<dynamic> rxCartList(int userId) async {
    return _client.get(ApiConfig.acctRxCart, query: {'user_id': userId});
  }

  /// `POST /app/acct/rx/checkout` — confirmed live. Request: `user_id`,
  /// `prescription_id`, `address_id`, `payment`. Response:
  /// `{ ok: true, order_code: "APM123" }`. Checks out ONE prescription's
  /// cart at a time — there's no equivalent of `/orders`' itemized body
  /// here. (`ok: false` responses never reach the code below at all — the
  /// shared ApiClient already throws for those before this method sees
  /// them, same as every other endpoint.)
  Future<String> rxCheckout(int userId, String prescriptionId, int addressId, String payment) async {
    final res = await withFallbackMessage(
      () => _client.post(ApiConfig.acctRxCheckout, body: {
        'user_id': userId,
        'prescription_id': prescriptionId,
        'address_id': addressId,
        'payment': payment,
      }),
      'Couldn\'t check out this prescription right now.',
    );
    if (res is Map) {
      final code = res['order_code'] ?? res['code'] ?? res['id'];
      if (code != null) return code.toString();
    }
    // Shouldn't happen for a real success response (order_code is always
    // sent) — kept only as a last-resort fallback so the UI always has
    // *something* to show/track rather than crashing on a missing field.
    return prescriptionId;
  }

  /// `POST /app/acct/rx/request-price` — confirmed live via Postman. Moves a
  /// pending prescription into pharmacist review. Throws on failure (caller
  /// shows the error) rather than swallowing it, since this is a
  /// person-initiated action they need to know didn't go through.
  Future<void> requestPricing(int userId, String prescriptionId) async {
    await withFallbackMessage(
      () => _client.post(ApiConfig.acctRxRequestPricing, body: {'user_id': userId, 'prescription_id': prescriptionId}),
      'Couldn\'t submit your pricing request right now.',
    );
  }

  /// `GET /app/checkout?user_id=` — confirmed live. See [CheckoutInitData].
  /// [prescriptionId] scopes this to one Rx checkout (confirmed needed,
  /// 2026-08-01) — sends `is_rx=1` alongside `prescription_id` so the
  /// response (delivery slots, summary, promotions) reflects just that
  /// prescription's items, not the regular cart. `is_rx=0` (no
  /// prescription_id) for the regular cart's own checkout, same as before.
  /// ✅ `address_id`/`area_id` confirmed live (2026-09-18) — this used to
  /// only ever take `user_id`, meaning its whole response (crucially
  /// `summary.delivery_fee`/`summary.grand_total`) always reflected the
  /// account's own DEFAULT address, never whichever one was actually
  /// selected client-side. checkout_screen.dart worked around that by
  /// fetching the real per-address fee separately (`GET
  /// /app/delivery-charge(/address/{id})`) and recomputing the total
  /// itself — arithmetic on real numbers, but still the app reconstructing
  /// something the server should just say directly. Passing the actual
  /// selected address/area here means the summary this returns is already
  /// correct for it, so that workaround is gone — see
  /// checkout_screen.dart's history for what used to be here instead.
  Future<CheckoutInitData> checkoutInit(int userId, {String? prescriptionId, int? addressId, int? areaId}) async {
    final res = await _client.get(ApiConfig.checkoutInit, query: {
      'user_id': userId,
      'is_rx': prescriptionId != null ? 1 : 0,
      if (prescriptionId != null) 'prescription_id': prescriptionId,
      if (addressId != null) 'address_id': addressId,
      if (areaId != null) 'area_id': areaId,
    });
    return CheckoutInitData.fromJson(res as Map<String, dynamic>);
  }

  /// `POST /app/promotion/apply` — for a promotion that applies
  /// automatically once the cart qualifies (`condition_type` other than
  /// `promo_code` — see [Promotion.requiresCode]). Confirmed live request
  /// body: `user_id`, `promotion_id`, `subtotal`, `item_count`, `area_id`.
  /// Returns just `{success, promotion_id, title, promo_discount,
  /// message}` — NOT the full checkout payload — so the caller needs to
  /// re-fetch [checkoutInit] afterward to get refreshed totals/state.
  Future<PromoApplyResult> applyPromotion(int userId, int promotionId, {required double subtotal, required int itemCount, int? areaId}) async {
    final res = await withFallbackMessage(
      () => _client.post(ApiConfig.promotionApply, body: {
        'user_id': userId,
        'promotion_id': promotionId,
        'subtotal': subtotal,
        'item_count': itemCount,
        if (areaId != null) 'area_id': areaId,
      }),
      'Couldn\'t apply that offer right now.',
    );
    return PromoApplyResult.fromJson(res as Map<String, dynamic>);
  }

  /// `POST /app/promo-code/apply` — for a person-entered code
  /// (`condition_type: 'promo_code'`). Confirmed live request body: `code`,
  /// `subtotal`, `user_id`. Same lightweight response shape as
  /// [applyPromotion] — confirmed for the failure case (`{success: false,
  /// message}`); the success case wasn't captured in an example but is
  /// assumed to match [applyPromotion]'s shape for consistency.
  Future<PromoApplyResult> applyPromoCode(int userId, String code, {required double subtotal}) async {
    final res = await withFallbackMessage(
      () => _client.post(ApiConfig.promoCodeApply, body: {'code': code, 'subtotal': subtotal, 'user_id': userId}),
      'That code doesn\'t seem to work.',
    );
    return PromoApplyResult.fromJson(res as Map<String, dynamic>);
  }

  /// `POST /app/promotion/remove` — clears whatever coupon/promotion is
  /// currently applied. ✅ Confirmed live request body (found in the
  /// updated Postman collection): `code`, `subtotal`, `user_id` — an
  /// earlier version of this method claimed "the confirmed example didn't
  /// show a request body at all" and only sent `user_id`, which was wrong;
  /// `code`/`subtotal` were missing entirely.
  Future<PromoApplyResult> removePromotion(int userId, {required String code, required double subtotal}) async {
    final res = await withFallbackMessage(
      () => _client.post(ApiConfig.promotionRemove, body: {'user_id': userId, 'code': code, 'subtotal': subtotal}),
      'Couldn\'t remove that offer right now.',
    );
    return PromoApplyResult.fromJson(res as Map<String, dynamic>);
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

  /// `?detail=1` (confirmed live) makes this return full objects — each
  /// with an `id`, `apix_sku`, AND a separately-populated `sku` field that
  /// is *not* the same value (e.g. `apix_sku: "2771"` vs `sku: "21993"` on
  /// the same item) — without it, the response stays the old flat
  /// id-only list so the website's existing usage is untouched.
  /// Match on **`apix_sku`** first, not `sku`: confirmed against a real
  /// `/app/products` response that `GET /app/product/{..}` (the PDP fetch)
  /// needs `apix_sku` specifically, not `sku` — an earlier version of this
  /// comment claimed the opposite (that `/app/products` never sends
  /// `apix_sku` at all), which was wrong. Matching on `sku` here would send
  /// wishlisted items into a PDP fetch with the wrong identifier.
  /// Returns the `sku` (not `apix_sku`) for each wishlisted item, since the
  /// result feeds straight into `GET /app/product/{id}` (see
  /// [CatalogService.product]/[Product.pdpIdentifier]'s docs) — ✅ confirmed
  /// live (2026-07-24) that endpoint wants `sku`, not `apix_sku`. This was
  /// backwards before (apix_sku first), which is exactly why loading the
  /// wishlist screen was silently 404ing on every single item whose
  /// apix_sku didn't happen to also work as a valid sku value elsewhere.
  Future<List<String>> wishlist(int userId) async {
    final res = await _client.get(ApiConfig.acctWishlist, query: {'user_id': userId, 'detail': 1});
    final list = (res is Map ? res['wishlist'] ?? res['skus'] ?? res['items'] : null) ?? (res is List ? res : const []);
    return (list as List)
        .map((e) => e is Map ? (e['sku'] ?? e['apix_sku'] ?? e['id'] ?? '').toString() : e.toString())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// Toggles [sku] in the wishlist; returns the new state (true = now
  /// wished). Confirmed request body is just `{"user_id":.., "sku":..}` —
  /// and that `sku` is the product's own separate catalog code (e.g.
  /// `"A1224232"`), NOT `apix_sku` (e.g. `"6819"`). An earlier version of
  /// this sent `apix_sku` under this `sku` key by mistake — wrong value on
  /// the right key name. See [Product.sku] vs [Product.apixSku]'s docs for
  /// why those two are genuinely different codes on the same item.
  Future<bool> toggleWish(int userId, String sku) async {
    final res = await withFallbackMessage(
      () => _client.post(ApiConfig.acctWishToggle, body: {'user_id': userId, 'sku': sku}),
      'Couldn\'t update your wishlist for this item right now.',
    );
    if (res is Map && res.containsKey('wished')) return res['wished'] == true;
    if (res is Map && res.containsKey('added')) return res['added'] == true;
    return true;
  }

  /// ✅ Confirmed live — see [ApiConfig.acctFcmToken]. Best-effort by
  /// design: called from [NotificationService] right after login/app
  /// start, and a failure here (network hiccup, etc.) should never block
  /// sign-in or app usage — it's caught and swallowed by the caller, not
  /// here, so this stays a plain, simple POST.
  Future<void> registerFcmToken(int userId, String fcmToken) async {
    await _client.post(ApiConfig.acctFcmToken, body: {'user_id': userId, 'fcm_token': fcmToken});
  }

  /// ✅ Confirmed live: `GET /app/acct/notifications?user_id=&page=&per_page=`.
  /// See [ServerNotification]'s doc for why the response shape itself is
  /// still a best-effort guess (no saved example response exists yet).
  Future<NotificationPage> notifications(int userId, {int page = 1, int perPage = 20}) async {
    final res = await _client.get(ApiConfig.acctNotifications, query: {
      'user_id': userId,
      'page': page,
      'per_page': perPage,
    });
    return NotificationPage.fromJson(res, requestedPage: page, requestedPerPage: perPage);
  }

  /// ✅ Confirmed live: `POST /app/acct/notifications/read` — body
  /// `user_id`, `id` (the notification's own row id — see
  /// [ServerNotification.id]'s doc, NOT the order/Rx this notification is
  /// about).
  Future<void> markNotificationRead(int userId, int id) async {
    await _client.post(ApiConfig.acctNotificationRead, body: {'user_id': userId, 'id': id});
  }

  /// ✅ Confirmed live: `POST /app/acct/notifications/read-all` — body
  /// `user_id` only.
  Future<void> markAllNotificationsRead(int userId) async {
    await _client.post(ApiConfig.acctNotificationReadAll, body: {'user_id': userId});
  }
}
