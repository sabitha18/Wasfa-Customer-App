/// Base URL + endpoint paths for the WASFA Customer API.
/// Mirrors `WASFA_Customer_API_postman_collection.json` exactly — if the
/// backend adds/renames a route, this is the only file that should need
/// to change everywhere the path is used.
class ApiConfig {
  ApiConfig._();

  /// Postman collection variable `base_url`.
  static const String baseUrl = 'https://portal.apixservices.com';

  /// Everything below is relative to `$baseUrl/api/v1`.
  static const String apiVersion = '/api/v1';

  // ---- Login / OTP --------------------------------------------------------
  static const String otpRequest = '/otp/request';
  static const String otpVerify = '/otp/verify';

  // ---- Home / browsing (anonymous) ----------------------------------------
  static const String home = '/app/home';
  static const String stores = '/app/stores'; // ⚠ not implemented server-side yet
  static const String products = '/app/products';
  static String product(String sku) => '/app/product/$sku';
  static const String areas = '/areas';
  static const String coupon = '/coupon';

  // ---- Orders ---------------------------------------------------------------
  static const String orders = '/orders';
  static const String track = '/track';
  static const String myOrders = '/my-orders';
  static String acctOrder(String code) => '/acct/order/$code';

  // ---- Account --------------------------------------------------------------
  static const String acctProfile = '/acct/profile';
  static const String acctWallet = '/acct/wallet';
  static const String acctRx = '/acct/rx';
  static const String acctAddresses = '/acct/addresses';
  static const String acctAddressSave = '/acct/address-save';
  static const String acctAddressDelete = '/acct/address-delete';
  static const String acctWishlist = '/acct/wishlist';
  static const String acctWishToggle = '/acct/wish-toggle';
}
