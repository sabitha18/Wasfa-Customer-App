/// Route names — one constant per screen (`CUR` value) in
/// WASFA_App_-_PHASE_1.html's `map` inside `renderScreen()`.
///
/// Screens marked ✅ are fully implemented in this phase-1 delivery.
/// Screens marked 🚧 are wired into navigation with a placeholder
/// ("coming soon") screen so the whole app compiles/runs and every button
/// goes *somewhere* — implement them the same way as the ✅ screens.
class Routes {
  Routes._();

  static const splash = '/splash'; // white bg + logo, boots location permission
  static const root = '/'; // bottom-nav shell (home/shop/wishlist/account)
  static const login = 'login'; // phone + OTP, pops `true` on success

  // ---- ✅ Phase 1 — commerce core -----------------------------------------
  static const home = 'home';
  static const store = 'store'; // per-pharmacy storefront
  static const brands = 'brands';
  static const shop = 'shop'; // PLP
  static const product = 'product'; // PDP
  static const wishlist = 'wishlist';
  static const account = 'account';
  static const cart = 'cart';
  static const checkout = 'checkout';
  static const track = 'track';
  static const myRx = 'myrx';
  static const rxDetail = 'rxdetail';
  static const wallet = 'wallet';
  static const orders = 'orders';
  static const orderDetail = 'orderdetail';
  static const pharmacies = 'pharmacies';
  static const requests = 'requests';
  static const reqItems = 'reqitems';
  static const reqReason = 'reqreason';
  static const reqDone = 'reqdone';

  // ---- 🚧 Phase 2 — telehealth, tests, family, insurance, chat -----------
  static const medFile = 'medfile';
  static const consent = 'consent';
  static const doctors = 'doctors';
  static const doctor = 'doctor';
  static const visits = 'visits';
  static const consult = 'consult';
  static const careNow = 'carenow';
  static const visitReport = 'visitreport';
  static const tests = 'tests';
  static const test = 'test';
  static const myTests = 'mytests';
  static const clinic = 'clinic';
  static const bundle = 'bundle';
  static const carePay = 'carepay';
  static const careConf = 'careconf';
  static const clinics = 'clinics';
  static const apptDetail = 'apptdetail';
  static const blogs = 'blogs';
  static const blog = 'blog';
  static const family = 'family';
  static const insCoverage = 'inscoverage';
  static const messages = 'messages';
  static const chatThread = 'chatthread';
  static const profile = 'profile';
  static const healthEdit = 'healthedit';
  static const aiChat = 'aichat';
  static const insurance = 'insurance';
  static const insConnect = 'insconnect';
}
