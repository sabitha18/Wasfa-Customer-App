/// Base URL + endpoint paths for the WASFA Customer API.
/// Mirrors `WASFA_Customer_API_postman_collection.json` exactly — if the
/// backend adds/renames a route, this is the only file that should need
/// to change everywhere the path is used.
class ApiConfig {
  ApiConfig._();

  /// Postman collection variable `base_url`.
  static const String baseUrl = 'https://apixrx.com';

  /// Everything below is relative to `$baseUrl/api/v1`.
  static const String apiVersion = '/api/v1';

  // ---- Login / OTP --------------------------------------------------------
  static const String otpRequest = '/otp/request';
  static const String otpVerify = '/otp/verify';

  // ---- Home / browsing (anonymous) ----------------------------------------
  static const String home = '/app/home';
  static const String stores = '/app/stores'; // ✅ live — returns { stores: [...] }
  static const String products = '/app/products';
  static String product(String sku) => '/app/product/$sku';
  /// Confirmed live in the updated Postman collection (2026-09-17):
  /// `POST /app/product/{sku}/review` — form-data body `rating`, `name`,
  /// `email`, `user_id`, `comment`. No saved example response, so success
  /// confirmation is inferred from the HTTP status alone (see
  /// CatalogService.submitReview). The collection's own description text
  /// on this endpoint is a stale copy-paste from the PDP endpoint's own
  /// doc ("Adds sellers[]...") and doesn't actually describe this one —
  /// going by the real configured request shape, not that text.
  static String productReview(String sku) => '/app/product/$sku/review';
  static const String categories = '/app/categories'; // ✅ live — full nested category tree with children[]
  static const String areas = '/areas';
  static const String coupon = '/coupon';
  /// PROPOSED — NOT a confirmed live endpoint. There is currently no
  /// backend support at all for dashboard-controlled app settings (which
  /// payment methods are enabled, banner content, etc.) — this is a
  /// placeholder path for that future endpoint. See AppSettingsState for
  /// how the app degrades gracefully (all payment methods enabled) while
  /// this doesn't exist or fails.
  static const String appSettings = '/app/settings';
  /// ✅ Confirmed live (device log, 2026-07-24): `POST /acct/fcm-token` with
  /// body `{user_id, fcm_token}` returns `{"ok": true}`. Registers this
  /// device's FCM token against the signed-in user so push notifications
  /// (order status, Rx submitted/priced) can actually be targeted at them.
  /// See NotificationService for the message contract this feeds.
  static const String acctFcmToken = '/acct/fcm-token';

  // ---- Orders ---------------------------------------------------------------
  static const String orders = '/orders';

  /// Confirmed live via Postman (2026-07-24): `POST /order/payment` —
  /// form-data body `code`, `status` ("success"|"failed"), `transaction_id`,
  /// `payment_id` (optional), `ref_id` (optional). Returns
  /// `{ok, confirmed, msg}`. This is the "report how a payment went" step
  /// only — it does NOT initiate a KNET payment or hand back a payment
  /// URL/session; that piece is still unresolved (see TapPaymentService's
  /// doc).
  static const String orderPayment = '/order/payment';
  static const String track = '/track'; // needs ?code=&mobile= — mobile isn't in the Postman collection but the live endpoint requires it
  static const String myOrders = '/my-orders';
  static String acctOrder(String code) => '/acct/order/$code';
  // ✅ confirmed live in the updated Postman collection — cancel/return/rate
  // on a specific order, and the reason lists that feed the cancel/return
  // flow's reason picker.
  static String orderCancel(String code) => '/orders/$code/cancel';
  static String orderReturn(String code) => '/orders/$code/return';
  static String orderRate(String code) => '/orders/$code/rate';
  static const String returnReasons = '/return-reasons'; // ?type=cancel|return

  // ---- Account --------------------------------------------------------------
  static const String acctProfile = '/acct/profile'; // GET (confirmed live) and POST (save) both use this same path
  static const String acctWallet = '/acct/wallet';
  /// ✅ Confirmed to exist as a distinct endpoint in the updated Postman
  /// collection: `GET /app/acct/rx?user_id=` (separate from
  /// [acctRxDetail]'s single-id path). No saved example RESPONSE yet
  /// though, so the exact response shape (bare array vs wrapped under a
  /// key) is still a best-effort guess in [AccountService.prescriptions].
  static String acctRxDetail(String rxId) => '/app/acct/rx/$rxId';
  static const String acctRxList = '/app/acct/rx';
  static const String acctRxAddToCart = '/app/acct/rx/add-to-cart';
  static const String acctRxCart = '/app/acct/rx/cart';
  static const String acctRxCheckout = '/app/acct/rx/checkout';

  /// Confirmed live — consolidates cart/addresses/delivery-slots/payment-
  /// methods/wallet/promotions for the checkout screen. See CheckoutInitData.
  static const String checkoutInit = '/app/checkout';
  static const String promotionApply = '/app/promotion/apply';
  static const String promoCodeApply = '/app/promo-code/apply';
  static const String promotionRemove = '/app/promotion/remove';
  /// Confirmed live via Postman: `POST /app/acct/rx/request-price` — form-data
  /// body `user_id`, `prescription_id`; returns `{ok:true, msg:"..."}`.
  /// Was `/app/acct/rx/request-pricing` (an unconfirmed guess) — the real
  /// path drops the "-ing", so every "Get Prices" tap was hitting a 404.
  static const String acctRxRequestPricing = '/app/acct/rx/request-price';

  /// Confirmed live request shapes (no saved example responses yet):
  /// - `GET /app/cart?user_id=` — list
  /// - `POST /app/cart/add` — body: user_id, product_id, qty
  /// - `POST /app/cart/update` — confirmed live: user_id, cart_id, qty
  /// - `POST /app/cart/remove` — body: user_id, cart_id, qty
  static const String cart = '/app/cart';
  static const String cartAdd = '/app/cart/add';
  static const String cartUpdate = '/app/cart/update';
  static const String cartRemove = '/app/cart/remove';
  static const String acctAddresses = '/acct/addresses';
  static const String acctAddressSave = '/acct/address-save';
  static const String acctAddressDelete = '/acct/address-delete';
  static const String acctWishlist = '/acct/wishlist';
  static const String acctWishToggle = '/acct/wish-toggle';
  static const String acctMyRequests = '/acct/my-requests'; // ✅ confirmed live — real cancel/return requests list

  /// ✅ Confirmed live (2026-07-28, updated Postman collection): the
  /// backend-fetched notification history that didn't exist earlier in
  /// this project — see NotificationHistoryStore's doc for why a
  /// client-side-only history existed as a stopgap before this. No saved
  /// EXAMPLE RESPONSE for the list endpoint though — only the request
  /// (`GET ?user_id=&page=&per_page=`) is shown, so the exact response
  /// field names (title/body/type/whatever holds the order-or-Rx
  /// reference for deep-linking/read flag/date) are still a best-effort
  /// guess in ServerNotification.fromJson. Get a real response example
  /// once a real notification exists to confirm/correct those.
  static const String acctNotifications = '/app/acct/notifications';
  static const String acctNotificationRead = '/app/acct/notifications/read';
  static const String acctNotificationReadAll = '/app/acct/notifications/read-all';

  // ---- Legal / static content --------------------------------------------
  /// ✅ Confirmed live for all 5 slugs (2026-09-16, real responses):
  /// `{ slug, title, content, phone, email, address }` — no `ok`/`data`
  /// wrapper, flat object. 'faq' also carries an empty, unused `faqs: []`
  /// alongside — ignored by LegalPage.fromJson, which only reads the 5
  /// fields above. 'terms' uses `<b>` for bold (not `<strong>`, which
  /// 'about' used) — the renderer matches both rather than assuming the
  /// CMS is consistent about which one it emits. 'privacy'`s `content` is
  /// Word/Outlook-exported HTML (MsoNormal classes, `<o:p>`,
  /// `<!--[endif]-->` conditional comments, raw `\r\n` line-wraps baked
  /// into the sentence text itself, collapsed to spaces before rendering).
  /// 'help' is the odd one out: its `content` isn't page text at all — a
  /// Google Maps link to the office — so account_screen.dart's
  /// "Help & support" row doesn't render it through the HTML sheet like
  /// the other 4 at all; it dials `phone` directly instead, per explicit
  /// request. No Arabic fields at all on any slug (`title`/`content` only
  /// — no `title_ar`/`content_ar`) — unlike categories/products, this
  /// content has no real translation from the API and always shows in
  /// English regardless of the app's language toggle.
  static String page(String slug) => '/app/page/$slug';

  // ---- Delivery charge --------------------------------------------------
  /// ✅ Confirmed live (2026-09-17): `{ ok, area_id, area, governorate_id,
  /// delivery_charge, effective_charge, free_delivery_applied,
  /// free_over_amount }` — see DeliveryCharge's doc for which field to
  /// actually use. Anonymous — no user_id needed, works for a guest with
  /// no saved addresses at all, picking an area for a new/unsaved address.
  static const String deliveryChargeByArea = '/app/delivery-charge';
  /// ✅ Confirmed live (2026-09-17) — same shape as [deliveryChargeByArea]
  /// plus an echoed `address_id`, scoped to one specific saved address.
  /// Call this the moment the person switches to a different saved
  /// address so the shown fee updates immediately, rather than staying
  /// stale until something else happens to refetch checkout data — nothing
  /// else does this automatically, since checkoutInit only ever takes
  /// `user_id` (no address override) and always reflects the account's
  /// own default address, not necessarily whichever one is currently
  /// selected client-side.
  static String deliveryChargeByAddress(int addressId) => '/app/delivery-charge/address/$addressId';

  // ---- Seller banners -----------------------------------------------------
  /// ✅ Confirmed live (2026-09-17): `{ banners: [...] }` — see
  /// SellerBanner's doc. Replaces the Store screen's old 3 hardcoded promo
  /// cards, identical on every seller's page, with real per-store content.
  static String sellerBanners(int shopId) => '/app/seller/$shopId/banners';
}
