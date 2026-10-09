import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/auth_gate.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/async_state_view.dart';
import '../../data/models/cart_line.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../state/auth_state.dart';
import '../../state/cart_state.dart';
import '../../state/locale_state.dart';
import '../widgets/page_header.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthState>();
      // Syncs the server's copy of the cart in — mirrors how the Wishlist
      // tab refreshes on open (see CartState.loadCartRemote's doc for why).
      // Guests too: userId null → guest cart by device_token.
      final cart = context.read<CartState>();
      cart.loadCartRemote(auth.userId);
      if (auth.isSignedIn) cart.loadRxCartRemote(auth.userId!);
    });
  }

  /// True while a guest is being taken through login → assign → reload.
  bool _checkingOut = false;

  /// Signed in: straight to checkout. Guest: open login (with a message
  /// saying why). On success, AuthState.verifyOtp has already called
  /// `/app/cart/assign`, so reload the now-merged cart from the API and
  /// continue to checkout. If login is cancelled, stay on the cart.
  Future<void> _onCheckout() async {
    final auth = context.read<AuthState>();
    if (auth.isSignedIn) {
      Navigator.pushNamed(context, Routes.checkout);
      return;
    }
    final ar = context.read<LocaleState>().isArabic;
    final ok = await requireLogin(
      context,
      message: ar ? 'سجّل الدخول لإتمام طلبك' : 'Log in to complete your order',
    );
    if (!ok || !mounted) return;
    final userId = context.read<AuthState>().userId;
    if (userId == null) return;
    setState(() => _checkingOut = true);
    try {
      await context.read<CartState>().reloadAfterLogin(userId);
    } finally {
      if (mounted) setState(() => _checkingOut = false);
    }
    if (!mounted) return;
    Navigator.pushNamed(context, Routes.checkout);
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartState>();
    final store = cart.activeStore;
    final isRx = cart.cartTab == 'rx';
    final ar = context.watch<LocaleState>().isArabic;
    String t(String en, String arabic) => ar ? arabic : en;
    // Rx groups by prescription (its own subtotal + its own Checkout
    // button — confirmed against the reference web app), not by pharmacy
    // like the regular cart does.
    final groups = isRx ? cart.rxGroupsFor() : cart.groupsFor(store);
    final keys = groups.keys.toList();

    return Directionality(
      textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
      backgroundColor: AppColors.bg,
      appBar: PageHeader(title: t('Cart', 'السلة')),
      body: Column(
        children: [
          // ── .carttabs — equal-width pills ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Row(
              children: [
                Expanded(child: _Tab(label: '${t("My Cart", "سلتي")} (${cart.cartCount})', on: cart.cartTab == 'my', onTap: () => cart.setCartTab('my'))),
                const SizedBox(width: 8),
                Expanded(child: _Tab(label: '${t("Rx Cart", "سلة الوصفات")} (${cart.rxCartCount})', on: cart.cartTab == 'rx', onTap: () => cart.setCartTab('rx'))),
              ],
            ),
          ),
          if ((isRx ? cart.rxCartLoading : cart.cartLoading) && keys.isEmpty)
            // Nothing to show yet and a sync is in flight — a proper
            // loading state here instead of the empty-cart illustration,
            // which would otherwise flash "Your cart is empty" for a beat
            // before real data arrives, even for a cart that isn't empty.
            Expanded(child: LoadingView(message: t('Loading your cart…', 'جارٍ تحميل سلتك…')))
          else if (keys.isEmpty)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 50),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ── .ph-screen .ic — white rounded box, sky icon ──
                      Container(
                        width: 92, height: 92,
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28), boxShadow: AppColors.shSm),
                        alignment: Alignment.center,
                        child: Icon(isRx ? Icons.medication_liquid_rounded : Icons.shopping_bag_outlined, size: 40, color: AppColors.sky),
                      ),
                      const SizedBox(height: 20),
                      Text(isRx ? t('My Rx', 'وصفاتي الطبية') : t('Your cart is empty', 'سلتك فارغة'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.navy)),
                      const SizedBox(height: 6),
                      Text(
                        isRx ? t('Prescriptions your doctor sends appear in My Rx.', 'تظهر الوصفات التي يرسلها طبيبك في صفحة وصفاتي الطبية.') : t('Add products to get started.', 'أضف منتجات للبدء.'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.muted, fontSize: 13),
                      ),
                      const SizedBox(height: 18),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isRx ? AppColors.bg : AppColors.sky,
                          foregroundColor: isRx ? AppColors.navy : Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        onPressed: () => Navigator.pushNamed(context, isRx ? Routes.myRx : Routes.shop),
                        child: Text(isRx ? t('My Rx →', '← وصفاتي الطبية') : t('Start shopping', 'ابدأ التسوق'), style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 110),
                children: [
                  if (isRx ? cart.rxCartLoading : cart.cartLoading)
                    // Already has content to show (local/optimistic or from
                    // a previous sync) — don't block it with a full-screen
                    // spinner, just a quiet note that it's refreshing.
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          const SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.sky)),
                          const SizedBox(width: 8),
                          Text(isRx ? t('Syncing your Rx cart…', 'جارٍ مزامنة سلة الوصفات…') : t('Syncing your cart…', 'جارٍ مزامنة سلتك…'), style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
                        ],
                      ),
                    ),
                  if (!isRx && keys.length > 1)
                  // ── .togcard — light-blue tinted, no shadow ──
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(color: const Color(0xFFE7F7FB), borderRadius: BorderRadius.circular(13)),
                      child: Row(children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(t('Deliver together', 'التوصيل معاً'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.navy)),
                              const SizedBox(height: 2),
                              Text('${t("One delivery fee for all pharmacies", "رسوم توصيل واحدة لجميع الصيدليات")} · ${Formatters.money(CartState.togetherDeliveryFee)}', style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                            ],
                          ),
                        ),
                        Switch(value: cart.deliverTogether, activeColor: AppColors.sky, onChanged: (_) => cart.toggleDeliverTogether()),
                      ]),
                    ),
                  for (final k in keys)
                    if (isRx)
                      _RxPrescriptionGroup(rxId: k, items: groups[k]!, cart: cart)
                    else
                      _PharmacyGroup(pharmacy: k, items: groups[k]!, isRx: isRx, cart: cart),
                ],
              ),
            ),
        ],
      ),
      bottomNavigationBar: (keys.isEmpty || isRx)
          ? null
          : Builder(builder: (context) {
              // Cart shows ONLY the subtotal from /app/cart (guest or
              // signed in) — no delivery fee, no local math. If the API
              // value isn't available (call failed), just "Checkout".
              final apiSubtotal = cart.serverSubtotal;
              final showSpinner = _checkingOut || (apiSubtotal == null && cart.cartLoading);
              return Container(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + MediaQuery.viewPaddingOf(context).bottom),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [BoxShadow(color: AppColors.navy.withOpacity(0.10), blurRadius: 22, offset: const Offset(0, -6))],
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.navy,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppColors.navy,
                      disabledForegroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    onPressed: _checkingOut ? null : _onCheckout,
                    child: showSpinner
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                        : Text(
                            apiSubtotal == null
                                ? (ar ? "إتمام الطلب" : "Checkout")
                                : '${ar ? "إتمام الطلب" : "Checkout"} · ${Formatters.money(apiSubtotal)}',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                          ),
                  ),
                ),
              );
            }),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback onTap;
  const _Tab({required this.label, required this.on, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: on ? AppColors.navy : AppColors.bg, borderRadius: BorderRadius.circular(11)),
        child: Text(label, style: TextStyle(color: on ? Colors.white : AppColors.muted, fontWeight: FontWeight.w700, fontSize: 13)),
      ),
    );
  }
}

/// Confirmed against the reference web app (2026-07-31): each prescription
/// in the Rx cart is its own card with its own subtotal and its own
/// "Checkout" button — NOT grouped by pharmacy, and NOT combined into one
/// cart-wide checkout the way [_PharmacyGroup] works for the regular cart.
/// Different prescriptions may need to be fulfilled/paid separately, so
/// tapping Checkout here scopes the whole checkout flow to just this
/// prescription's lines (see checkout_screen.dart's `rxScope`).
class _RxPrescriptionGroup extends StatelessWidget {
  final String rxId;
  final List<CartLine> items;
  final CartState cart;
  const _RxPrescriptionGroup({required this.rxId, required this.items, required this.cart});

  @override
  Widget build(BuildContext context) {
    final ar = context.watch<LocaleState>().isArabic;
    final sub = items.fold(0.0, (s, l) => s + cart.lineCharge(l));
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: AppColors.shSm),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Expanded(
                child: Text('℞ ${ar ? "وصفة" : "Prescription"} #$rxId', overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.navy, fontSize: 12.5)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: AppColors.rose, borderRadius: BorderRadius.circular(20)),
                child: Text(ar ? 'تتطلب وصفة' : 'Rx Required', style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
          const Divider(height: 1, color: AppColors.line),
          for (final line in items) _CartLineTile(line: line, isRx: true, cart: cart),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(Formatters.money(sub), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.navy)),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.navy,
                  foregroundColor: Colors.white,
                  // Overrides the app-wide ElevatedButtonTheme's
                  // minimumSize: Size.fromHeight(50) (== width: infinity).
                  // That default is fine for a full-width button in a
                  // Column, but this one sits directly inside a Row
                  // alongside the subtotal Text — Row gives non-flex
                  // children unbounded width, and asking to fill infinite
                  // width there crashes ("BoxConstraints forces an
                  // infinite width"). Sized to content instead.
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                  elevation: 0,
                ),
                onPressed: () => Navigator.pushNamed(context, Routes.checkout, arguments: rxId),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(ar ? 'إتمام الطلب' : 'Checkout', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  const SizedBox(width: 6),
                  Icon(ar ? Icons.arrow_back : Icons.arrow_forward, size: 15),
                ]),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

class _PharmacyGroup extends StatelessWidget {
  final String pharmacy;
  final List<CartLine> items;
  final bool isRx;
  final CartState cart;
  const _PharmacyGroup({required this.pharmacy, required this.items, required this.isRx, required this.cart});

  @override
  Widget build(BuildContext context) {
    final ar = context.watch<LocaleState>().isArabic;
    // Was `cart.pharmacyFee(cart.groupSubtotal(items))` called with no area context at all —
    // the one spot left still falling straight through to the old fake
    // flat rule (`sub >= 3 ? 0 : 0.750`) after everywhere else was fixed
    // to use the real per-address delivery-charge endpoint. Confirmed
    // live in a real screenshot: this header showed "KWD 0.750" while the
    // bottom Checkout button correctly showed a total that EXCLUDED that
    // 0.750 — the two numbers didn't even agree with each other, both
    // supposedly describing the same cart.
    //
    // Real caveat worth knowing: the delivery-charge endpoint returns ONE
    // fee for the delivery address/area as a whole, with no per-pharmacy
    // breakdown — so with more than one pharmacy in the cart, every group
    // shows this SAME real number rather than each having its own
    // separately-confirmed fee. That's still real data, just not
    // necessarily a true per-pharmacy split; ask backend if a genuine
    // per-pharmacy fee is supposed to exist if that turns out to matter.
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: AppColors.shSm),
      child: Column(
        children: [
          // ── .phh — gray strip header ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            color: AppColors.bg,
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(isRx ? '℞ $pharmacy' : '🏪 $pharmacy', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.navy, fontSize: 12.5)),
            ]),
          ),
          for (final line in items) _CartLineTile(line: line, isRx: isRx, cart: cart),
        ],
      ),
    );
  }
}

class _CartLineTile extends StatelessWidget {
  final CartLine line;
  final bool isRx;
  final CartState cart;
  const _CartLineTile({required this.line, required this.isRx, required this.cart});

  @override
  Widget build(BuildContext context) {
    final ar = context.watch<LocaleState>().isArabic;
    final product = line.productId != null ? CatalogRepository.instance.findProduct(line.productId!) : null;
    final name = line.nameOverride ?? product?.nameEn ?? (ar ? 'منتج' : 'Item');
    // Straight off the cart line itself (confirmed live `image` field on
    // /app/cart, 2026-07-29) — not the CatalogRepository lookup above,
    // which comes up null for most real cart lines since a server-synced
    // line's productId is usually unset (see CartState.lineKey's doc).
    // That's exactly why thumbnails were blank: `product` was null, so
    // `product?.imageUrl` was always null too, regardless of whether the
    // API actually had an image for this line.
    final imageUrl = line.imageOverride ?? product?.imageUrl;
    // Straight off the cart line itself now (confirmed live on /app/cart,
    // 2026-07-29) — not a CatalogRepository lookup keyed by catalog
    // productId, which a server-synced line never reliably carries (see
    // CartState.lineKey's doc on apiProductId vs productId) and so was
    // silently finding nothing for exactly the lines that matter here.
    final bogoLabel = line.bogoDisplayLabel;
    // Real free_qty, not a guess — only shows once the current quantity
    // has actually earned at least one free unit (e.g. qty 3 under "Buy 1
    // Get 1" → free_qty 1, paid_qty 2 per the confirmed response). Using
    // free_qty itself rather than eyeballing qty directly is what makes
    // this correct for any BOGO variant the backend might define, not
    // just a strict "every 2nd unit" rule.
    final freeQty = line.freeQty;
    // Only meaningful for Rx lines — see CartState.isRxLineInStock's doc for
    // why this is re-checked live against the cached prescription rather
    // than trusting CartLine.inStock (captured once, at add time).
    // Rx lines get a live re-check (see isRxLineInStock's doc — pricing/
    // stock is set by a pharmacist, possibly well after the add, with no
    // equivalent to loadCartRemote to refresh from). Regular cart lines
    // trust their own inStock directly — it's kept fresh by loadCartRemote
    // parsing in_stock fresh on every full sync, unlike the Rx side.
    final outOfStock = isRx ? !cart.isRxLineInStock(line) : !line.inStock;
    final charge = cart.lineCharge(line);
    final full = line.lineTotalBeforeDiscount;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line, width: 1))),
      child: GestureDetector(
        onTap: () {}, // hook up cart.openLine(...) if you have PDP/RX navigation wired
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── .th — 60x60 thumbnail ──
            Container(
              width: 60, height: 60,
              decoration: BoxDecoration(color: AppColors.blush, borderRadius: BorderRadius.circular(11)),
              alignment: Alignment.center,
              child: (imageUrl != null && imageUrl.isNotEmpty)
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(11),
                      child: Image.network(
                        imageUrl,
                        width: 60, height: 60,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, height: 1.3, color: AppColors.ink)),
                  const SizedBox(height: 1),
                  Text(
                    (product?.brand ?? (line.rxId ?? (ar ? 'وصفة' : 'Rx'))).toUpperCase(),
                    style: const TextStyle(fontSize: 10, color: AppColors.sky, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 6,
                    children: [
                      Text(Formatters.money(charge), style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.navy, fontSize: 14)),
                      if (full > charge)
                        Text(Formatters.money(full), style: const TextStyle(fontSize: 11, color: AppColors.muted, decoration: TextDecoration.lineThrough)),
                    ],
                  ),
                  if (bogoLabel != null && freeQty != null && freeQty > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        ar ? '🎁 $bogoLabel · $freeQty مجاناً' : '🎁 $bogoLabel · $freeQty free',
                        style: const TextStyle(fontSize: 11, color: AppColors.ok, fontWeight: FontWeight.w700),
                      ),
                    ),
                  if (bogoLabel != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        bogoLabel,
                        style: const TextStyle(fontSize: 11, color: AppColors.rose, fontWeight: FontWeight.w700),
                      ),
                    ),
                  if (outOfStock)
                    // Rx: went stale after being added — see
                    // CartState.isRxLineInStock's doc — and excluded from
                    // the actual Rx checkout submission (see
                    // checkout_screen.dart's _placeRxOrder). Regular cart:
                    // reflects in_stock from the last /app/cart sync;
                    // not currently excluded from regular checkout, just
                    // labeled — ask if you also want that enforced the
                    // same way as the Rx side.
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        ar ? 'غير متوفر' : 'Out of stock',
                        style: const TextStyle(fontSize: 11, color: AppColors.rose, fontWeight: FontWeight.w700),
                      ),
                    ),
                  const SizedBox(height: 6),
                  // ── .qty — single bordered pill ──
                  Container(
                    height: 30,
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.line, width: 1.5),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      _QtyButton(icon: Icons.remove, onTap: () => cart.setQtyRemote(context, line.key, -1, rx: isRx)),
                      SizedBox(
                        width: 32,
                        child: Text('${line.qty}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      ),
                      _QtyButton(icon: Icons.add, onTap: outOfStock ? null : () => cart.setQtyRemote(context, line.key, 1, rx: isRx)),
                    ]),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () => cart.removeLineRemote(context, line.key, rx: isRx),
              icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.muted),
              padding: const EdgeInsets.all(3),
              constraints: const BoxConstraints(),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}

class _QtyButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _QtyButton({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(width: 28, height: 28, child: Icon(icon, size: 14, color: onTap == null ? AppColors.muted : AppColors.navy)),
    );
  }
}