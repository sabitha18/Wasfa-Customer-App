# WASFA Patient App — Flutter (MVVM)

Flutter conversion of `WASFA_App_-_PHASE_1.html`, following the same MVVM
structure used on WASFA Rider / WASFA Rep.

## ⚠️ Scope of this delivery — please read

The HTML prototype you uploaded is a **48-screen super-app** (pharmacy
shop + cart/checkout, e-prescriptions, telehealth doctors, lab tests,
family profiles, insurance, AI chat, doctor messaging, wallet, medical
file, blogs...). That is realistically several weeks of Flutter work, not
something that can be fully, pixel-perfectly hand-written in one pass.

To give you something genuinely usable right now rather than a shallow
pass over everything, I built the **commerce core completely** (the part
you've been iterating on most: shop → cart → checkout → orders → Rx) with
real business logic ported line-for-line from the JS, and wired **every
other screen into navigation** with a placeholder so the app runs
end-to-end and nothing 404s.

### ✅ Fully implemented (18 screens, real logic, no placeholders)
Home (store directory + promo carousel + filters) · per-pharmacy
Storefront · Brands · Shop/PLP (categories, concerns, sort, filter,
grid/list) · Product detail (multi-seller picker, BOGO, discounts) ·
Wishlist · Cart (grouped by pharmacy, deliver-together, BOGO free-unit
math) · Checkout (address, slots, payment method, promo codes, order
summary) · Address form · Order tracking · Orders list · Order detail ·
Cancel/Return request flow · My Prescriptions · Prescription detail
(seller picker, add-to-Rx-cart) · Wallet (top-up, transactions) ·
Account · Pharmacies list · My requests.

Every pricing rule from the HTML is ported exactly: per-pharmacy delivery
fee (free ≥ KWD 3, else 0.750), "deliver together" flat fee, BOGO
("1+1") free-unit calculation, promo code stacking rules (percent / flat
/ free-delivery, auto-picks the best one), multi-seller price sorting,
and wallet-insufficient-balance handling.

### 🚧 Placeholder only (routes exist, screen says "Coming soon")
Doctors/telehealth, lab tests, family members, insurance, AI chat,
doctor messaging, medical file, blogs, consent/sharing, profile editor.
See `lib/core/routing/app_routes.dart` — every route name from the HTML
already has a constant, so wiring in a real screen later is a one-line
change in `app_router.dart`.

**Suggested next step:** tell me which Phase-2 area to build next
(telehealth/doctors is usually the highest-value one) and I'll build it
the same way, screen-by-screen, with the same fidelity as Phase 1.

## Architecture (MVVM)

```
lib/
  core/
    theme/        design tokens — colors/spacing/radius match the HTML :root exactly
    routing/      route name constants + onGenerateRoute
    utils/        formatters (KWD money, dates)
  data/
    models/       Product, Seller, PharmacyStore, CartLine, Order, Promo,
                  Address, Prescription/RxItem, WalletTransaction
    repositories/ CatalogRepository — seeded mock data (mirrors the JS
                  `const PRODUCTS/STORES/...` blocks). Swap its method
                  bodies for real API calls later; nothing above it changes.
  state/          Cross-screen "app-level" ViewModels (ChangeNotifier):
                  CartState (cart/RX-cart/wishlist + all pricing math),
                  OrdersState (orders/wallet/rewards), AddressState,
                  LocaleState (en/ar toggle)
  viewmodels/     Per-screen ViewModels (HomeViewModel, ShopViewModel,
                  ProductViewModel, StoreViewModel, CheckoutViewModel)
  views/
    screens/      One file per screen (the "View")
    widgets/      Shared widgets: ProductCard, PageHeader, SectionHeader
```

**Why two kinds of ViewModel?** `CartState`/`OrdersState`/`AddressState`
hold state that many screens read and mutate (e.g. the cart badge on the
bottom nav, the wallet balance shown in Checkout) — these are provided
once at the app root via `MultiProvider` in `main.dart`, the same way you
already use a top-level cart provider on WASFA Rider/WASFA Rep. Anything
scoped to a single screen (sort/filter state on the Shop screen, the
selected seller on a Product screen) gets its own small ViewModel created
right where that screen is pushed, exactly like the pattern in
`ShopScreen`/`ProductScreen`.

## Known simplifications (flagged, not hidden)
- **Persistence**: the HTML uses `localStorage` for everything; this
  build keeps state in memory only (`shared_preferences` is in
  `pubspec.yaml` but not wired up yet — happy to add if you want cart/
  wishlist/orders to survive an app restart).
- **Insurance-aware checkout** (`INS`/`insCover` in the JS) is not built
  since Insurance itself is Phase 2 — `CheckoutTotals.due` currently
  equals `total`.
- **Map/rider tracking** is a placeholder box instead of the custom
  `CustomPaint` map — let me know if you want the same `_MapBg` approach
  you used on WASFA Rider ported here.
- Product/pharmacy "photos" are still emoji, matching the HTML's own
  placeholder approach (`ph:'💊'` etc.) — swap `Product.emoji` for a real
  asset/network image whenever you have real photography.

## Running it
```
flutter pub get
flutter run
```
