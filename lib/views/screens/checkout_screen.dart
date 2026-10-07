import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/auth_gate.dart';
import '../../core/widgets/async_state_view.dart';
import '../../data/models/checkout_init.dart';
import '../../data/models/cart_line.dart';
import '../../data/services/account_service.dart';
import '../../data/services/tap_payment_service.dart';
import '../../state/address_state.dart';
import '../../state/app_settings_state.dart';
import '../../state/auth_state.dart';
import '../../state/cart_state.dart';
import '../../state/locale_state.dart';
import '../../state/location_state.dart';
import '../../state/orders_state.dart';
import '../../viewmodels/checkout_view_model.dart';
import '../widgets/page_header.dart';
import '../widgets/address_sheets.dart';
import '../widgets/toast.dart';
import 'track_screen.dart';
import '../../data/models/address.dart';
class CheckoutScreen extends StatefulWidget {
  /// A specific prescription id, when Rx checkout has been scoped to just
  /// one prescription (see cart_screen.dart's _RxPrescriptionGroup) — null
  /// for the regular cart's unscoped checkout. Confirmed against the
  /// reference web app (2026-07-31): each prescription in the Rx cart gets
  /// its own separate checkout, not one combined checkout for everything.
  final String? rxScope;
  const CheckoutScreen({super.key, this.rxScope});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  CheckoutInitData? _initData;
  bool _initLoading = true;
  String? _initError;
  // Checkout used to silently trust whatever AddressState.effectiveAddress
  // already resolved to — GPS-based "Current location" by default, or a
  // guessed "default"/first saved address if GPS failed — with someone's
  // 2nd/3rd saved address never getting picked unless they'd deliberately
  // gone into "Delivery addresses" and chosen it themselves at some earlier
  // point. Whoever's placing THIS order deserves an explicit chance to
  // confirm which of their saved addresses it's actually going to, once per
  // visit to this screen — not a silent guess. Only fires when there's
  // genuinely more than one saved address to choose between; a single
  // saved address (or none) has nothing meaningful to ask about.
  bool _askedAddress = false;
  // Tracks what the last checkout-init fetch was actually FOR, so a
  // real address/area change (see _onAddressChanged) triggers a genuine
  // re-fetch — now that address_id/area_id are real params (confirmed
  // live 2026-09-18), the whole summary (not just delivery fee) depends
  // on which one is selected, so switching needs a fresh fetch, not just
  // a locally-patched number the way this used to work around it.
  int? _lastAddressId;
  int? _lastAreaId;
  // Held directly instead of looked up through `context` in dispose(): by
  // then the element is deactivated and `context.read` throws ("Looking up
  // a deactivated widget's ancestor is unsafe" — seen in real device logs),
  // so removeListener never ran and the listener outlived this screen,
  // re-fetching checkout and re-throwing on every later address change.
  AddressState? _addressState;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final addressState = context.read<AddressState>();
      _addressState = addressState;
      final location = context.read<LocationState>();
      await addressState.loadAreas();
      // Left the screen while areas were loading — registering the listener
      // now would leak it, since dispose() has already run.
      if (!mounted) return;
      // Match the GPS-detected area against the real catalog now that it's
      // loaded, so "Current location" (the default) carries a real
      // governorate/area, not just a display label.
      addressState.syncFromLocation(governorate: location.governorate, area: location.area, street: location.street);
      addressState.addListener(_onAddressChanged);
      final auth = context.read<AuthState>();
      if (auth.isSignedIn) {
        // Was fire-and-forget (`loadAddresses(...)` with no `await`),
        // immediately followed by capturing `_lastAddressId`/`_lastAreaId`
        // from whatever `effectiveAddress` was BEFORE the real address
        // list had actually loaded. The moment that fetch DID complete
        // moments later, it notified — `_onAddressChanged` saw a real
        // change (the snapshot was stale) and fired a second
        // `_loadCheckoutInit`, running the promo auto-apply logic twice
        // in a row (confirmed live: the exact same `/app/promotion/apply`
        // call, twice, in real logs). Awaiting it first means the
        // snapshot below is already correct, so that second redundant
        // fetch doesn't happen.
        await addressState.loadAddresses(auth.userId!);
        if (!mounted) return;
        final a = addressState.effectiveAddress;
        _lastAddressId = a?.id;
        _lastAreaId = a?.areaId;
        _loadCheckoutInit(auth.userId!);
      } else {
        setState(() => _initLoading = false);
      }
    });
  }

  @override
  void dispose() {
    _addressState?.removeListener(_onAddressChanged);
    super.dispose();
  }

  /// Re-fetches checkout-init whenever the SELECTED address/area actually
  /// changes — switching a saved address, GPS resolving to a new one, etc.
  /// (anything that changes what AddressState.effectiveAddress resolves
  /// to). Guarded so it only re-fetches on a genuine change, not every
  /// AddressState notification (it fires for plenty of unrelated reasons
  /// too — e.g. its own delivery-charge refresh completing).
  void _onAddressChanged() {
    final addressState = _addressState;
    if (!mounted || addressState == null) return;
    final a = addressState.effectiveAddress;
    if (a?.id == _lastAddressId && a?.areaId == _lastAreaId) return;
    _lastAddressId = a?.id;
    _lastAreaId = a?.areaId;
    final auth = context.read<AuthState>();
    if (auth.isSignedIn) _loadCheckoutInit(auth.userId!);
  }

  /// `GET /app/checkout` — confirmed live, consolidates cart/addresses/
  /// delivery-slots/payment-methods/wallet/promotions in one call. Feeds
  /// the result into the other providers that already display this data
  /// (AddressState/AppSettingsState/OrdersState), so those screens' own
  /// existing rendering just picks it up via their normal watch — only
  /// delivery slots and the promo/totals section need to read [_initData]
  /// directly, since nothing else already renders those.
  Future<void> _loadCheckoutInit(int userId) async {
    setState(() => _initLoading = true);
    try {
      final a = context.read<AddressState>().effectiveAddress;
      var data = await AccountService.instance.checkoutInit(
        userId,
        prescriptionId: widget.rxScope,
        addressId: a?.id,
        areaId: a?.areaId,
      );
      if (!mounted) return;
      // Auto-apply the best qualifying promotion that doesn't need a typed
      // code (Promotion.requiresCode == false — e.g. a straight "20% off"
      // or a "min 3 items" offer the cart already qualifies for), so it
      // shows applied on the order immediately rather than requiring the
      // person to open the promo sheet and tap it themselves. A promotion
      // that DOES require a code is never auto-applied — typing/choosing a
      // specific code is something the person does on purpose. Only runs
      // when nothing's already applied, so it can never override a choice
      // already made this session (including having removed an offer on
      // purpose earlier).
      if (data.appliedPromo == null && data.appliedCouponCode == null) {
        final candidates = data.promotions.where((p) => p.isActive && !p.requiresCode).toList()
          ..sort((a, b) => b.discount.compareTo(a.discount));
        if (candidates.isNotEmpty && mounted) {
          try {
            final areaId = context.read<AddressState>().effectiveAddress?.areaId;
            final result = await AccountService.instance.applyPromotion(
              userId, candidates.first.id,
              subtotal: data.summary.subtotal,
              itemCount: data.itemCount,
              areaId: areaId,
            );
            if (result.success) {
              // Was missing addressId/areaId here — unlike the initial
              // fetch just above, which correctly passes them. Confirmed
              // real-world effect: this refetch would fall back to
              // whatever address the SERVER considers the account's
              // default, which can genuinely differ from the one actually
              // in use — so even after a successful apply, this could come
              // back showing the promo as NOT applied (or the wrong
              // delivery fee) simply because it asked about a different
              // address's checkout state, not because the apply itself
              // failed.
              data = await AccountService.instance.checkoutInit(userId, prescriptionId: widget.rxScope, addressId: a?.id, areaId: a?.areaId);
            }
          } catch (_) {
            // Silent — checkout still works without the auto-applied offer;
            // the person can still open the promo sheet and apply it by hand.
          }
        }
      }
      if (!mounted) return;
      final addressState = context.read<AddressState>();
      addressState.hydrateAddresses(data.addresses);
      context.read<AppSettingsState>().applyFromCheckout(data.paymentMethods.enabledKeys);
      context.read<OrdersState>().syncWalletBalance(data.walletBalance);
      setState(() {
        _initData = data;
        _initLoading = false;
        _initError = null;
      });
      // Ask once per visit to this screen which address this order should
      // actually go to, when there's genuinely more than one saved address
      // to choose between — see _askedAddress's doc for why silently
      // trusting whatever was already active (GPS, or a guessed default)
      // isn't good enough for the address an order actually ships to.
      if (!_askedAddress && addressState.addresses.length > 1) {
        _askedAddress = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) showAddressPickerSheet(context, addressState, context.read<LocationState>());
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initLoading = false;
        // Non-blocking — checkout still works from local cart computation/
        // the mock-free empty delivery-slots state; this just means the
        // real promo list and server-computed totals aren't available yet.
        _initError = describeError(e);
      });
    }
  }

  void _onInitDataChanged(CheckoutInitData data) {
    if (!mounted) return;
    context.read<OrdersState>().syncWalletBalance(data.walletBalance);
    setState(() => _initData = data);
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => CheckoutViewModel(),
      child: _CheckoutBody(
        initData: _initData,
        initLoading: _initLoading,
        initError: _initError,
        onInitDataChanged: _onInitDataChanged,
        rxScope: widget.rxScope,
      ),
    );
  }
}

class _CheckoutBody extends StatelessWidget {
  final CheckoutInitData? initData;
  final bool initLoading;
  final String? initError;
  final ValueChanged<CheckoutInitData> onInitDataChanged;
  final String? rxScope;
  const _CheckoutBody({required this.initData, required this.initLoading, required this.initError, required this.onInitDataChanged, this.rxScope});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<CheckoutViewModel>();
    final cart = context.watch<CartState>();
    final addressState = context.watch<AddressState>();
    final location = context.watch<LocationState>();
    final ar = context.watch<LocaleState>().isArabic;
    String t(String en, String arabic) => ar ? arabic : en;
    // Scoped to just this prescription's lines when rxScope is set (see its
    // doc) — null otherwise, meaning "use the whole active store" as before.
    final Map<String, CartLine>? rxScopeStore =
        (rxScope != null && cart.cartTab == 'rx') ? Map.fromEntries(cart.rxCart.entries.where((e) => e.value.rxId == rxScope)) : null;
    final totals = cart.computeTotals(
      storeOverride: rxScopeStore,
      areaCatalog: addressState.areaCatalog,
      areaId: addressState.effectiveAddress?.areaId,
    );
    final a = addressState.effectiveAddress;

    // CheckoutScreen's initState only ever calls syncFromLocation ONCE, right
    // when the page first mounts. If the device's GPS/reverse-geocode hadn't
    // resolved yet at that exact moment, that one attempt silently no-ops
    // (see syncFromLocation's doc) and currentLocationAddress is left null
    // forever for this screen instance — so effectiveAddress permanently
    // fell back to whatever saved address happens to be selected, even
    // though "Current location" was still the active choice. Watching
    // LocationState here and re-attempting once it actually has data fixes
    // the "hadn't resolved yet" case: this keeps retrying (harmlessly) until
    // it succeeds, then never needs to again. It deliberately stops once
    // [AddressState.currentLocationMatchFailed] is true, though — that
    // means a real attempt already ran and genuinely found no match (e.g.
    // testing/traveling from outside Kuwait entirely), and retrying that
    // forever would just be pointless busywork every rebuild.
    if (addressState.useCurrentLocation &&
        addressState.currentLocationAddress == null &&
        !addressState.currentLocationMatchFailed &&
        (location.governorate?.isNotEmpty ?? false)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        // Guarded by the same condition again in case something else beat
        // us to it between scheduling and running this callback.
        if (addressState.useCurrentLocation && addressState.currentLocationAddress == null && !addressState.currentLocationMatchFailed) {
          addressState.syncFromLocation(governorate: location.governorate, area: location.area, street: location.street);
        }
      });
    }

    return Directionality(
      textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
      backgroundColor: AppColors.bg,
      appBar: PageHeader(title: t('Checkout', 'إتمام الطلب')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 120),
        children: [
          if (initError != null)
            // Non-blocking — checkout still works from local computation
            // while this failed, so this is a note, not a hard stop.
            InlineErrorBanner(message: t('Some checkout details didn\'t load: $initError', 'لم يتم تحميل بعض تفاصيل الطلب: $initError'), onRetry: null)
          else if (initLoading && initData == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(children: [
                const SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.sky)),
                const SizedBox(width: 8),
                Text(t('Loading checkout details…', 'جارٍ تحميل تفاصيل الطلب…'), style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
              ]),
            ),
          // ── .sec2 — "Shipping address" + edit icon ──
          _Sec2(
            label: t('Shipping address', 'عنوان التوصيل'),
            onEdit: a == null ? () => showAddressFormSheet(context, addressState, -1) : () => showAddressFormSheet(context, addressState, addressState.selectedIndex),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: a == null
                // Genuinely no address to show — a real empty state, not a
                // fabricated placeholder address (see AddressState.addresses'
                // doc for why that used to happen).
                ? GestureDetector(
                    onTap: () => showAddressFormSheet(context, addressState, -1),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: AppColors.rose, width: 1.5),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Row(children: [
                        const Icon(Icons.add_location_alt_outlined, size: 18, color: AppColors.rose),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(t('Add a delivery address to continue', 'أضف عنوان توصيل للمتابعة'), style: const TextStyle(color: AppColors.rose, fontWeight: FontWeight.w600, fontSize: 12.5)),
                        ),
                        const Icon(Icons.chevron_right_rounded, color: AppColors.rose, size: 16),
                      ]),
                    ),
                  )
                : GestureDetector(
              onTap: () => showAddressPickerSheet(context, addressState, context.read<LocationState>()),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: AppColors.line, width: 1.5),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a.title, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.navy, fontSize: 14)),
                    const SizedBox(height: 4),
                    Text(a.formatted, style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4)),
                    const SizedBox(height: 9),
                    Row(children: [
                      Text(t('Change address', 'تغيير العنوان'), style: const TextStyle(color: AppColors.sky, fontWeight: FontWeight.w600, fontSize: 12)),
                      const SizedBox(width: 3),
                      const Icon(Icons.chevron_right_rounded, size: 14, color: AppColors.sky),
                    ]),
                  ],
                ),
              ),
            ),
          ),

          _HLbl(label: t('Delivery date', 'تاريخ التوصيل')),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              _ChoiceChip(label: t('ASAP', 'في أقرب وقت'), on: vm.slot == 'asap', onTap: () => vm.setSlot('asap')),
              const SizedBox(width: 8),
              _ChoiceChip(label: t('Scheduled', 'مجدول'), on: vm.slot == 'sched', onTap: () => vm.setSlot('sched')),
            ]),
          ),
          if (vm.slot == 'sched') ...[
            _Calendar(vm: vm),
            _HLbl(label: t('Shipping method', 'طريقة التوصيل')),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(children: [
                // Real slots from checkout-init (GET /app/checkout) — no
                // mock/dummy fallback list; if this hasn't loaded yet or
                // came back empty, there's simply nothing to pick here yet
                // rather than showing invented placeholder times.
                for (var i = 0; i < (initData?.deliverySlots.length ?? 0); i++)
                  _PayOption(
                    icon: Icons.schedule_rounded,
                    label: initData!.deliverySlots[i].amount > 0
                        ? '${initData!.deliverySlots[i].titleFor(ar)} · ${Formatters.money(initData!.deliverySlots[i].amount)}'
                        : initData!.deliverySlots[i].titleFor(ar),
                    on: vm.slotTimeIndex == i,
                    onTap: () => vm.setSlotTime(i),
                  ),
              ]),
            ),
          ],

          _HLbl(label: t('Payment method', 'طريقة الدفع')),
          Builder(builder: (context) {
            final settings = context.watch<AppSettingsState>();
            final enabled = settings.enabledPaymentMethods;
            // If the currently-selected method got disabled from the
            // dashboard (or the settings fetch only just came back), fall
            // back to the first still-enabled one rather than leaving the
            // order stuck on a payment method that's no longer offered.
            if (!enabled.contains(vm.pay) && enabled.isNotEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) => vm.setPay(enabled.first));
            }
            final wallet = context.watch<OrdersState>().wallet;
            Widget optionFor(String key) {
              switch (key) {
                case 'knet':
                  return _PayOption(icon: Icons.credit_card_rounded, label: t('KNET', 'كي نت'), on: vm.pay == 'knet', onTap: () => vm.setPay('knet'));
                case 'card':
                  return _PayOption(icon: Icons.credit_card_rounded, label: t('Card', 'بطاقة'), on: vm.pay == 'card', onTap: () => vm.setPay('card'));
                case 'wallet':
                  return _PayOption(icon: Icons.account_balance_wallet_rounded, label: '${t("Wallet", "المحفظة")} · ${Formatters.money(wallet)}', on: vm.pay == 'wallet', onTap: () => vm.setPay('wallet'));
                case 'cod':
                  return _PayOption(icon: Icons.payments_rounded, label: t('Cash on delivery', 'الدفع عند الاستلام'), on: vm.pay == 'cod', onTap: () => vm.setPay('cod'));
                default:
                  return const SizedBox.shrink();
              }
            }
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(children: [for (final key in enabled) optionFor(key)]),
            );
          }),

          _HLbl(label: t('Additional notes', 'ملاحظات إضافية')),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              maxLines: 2,
              onChanged: vm.setNote,
              style: const TextStyle(fontSize: 14, color: AppColors.ink),
              cursorColor: AppColors.navy,
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.all(12),
                hintText: t('Any note for the rider or pharmacy…', 'أي ملاحظة للسائق أو الصيدلية…'),
                hintStyle: const TextStyle(color: AppColors.muted, fontSize: 14),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: AppColors.line, width: 1.5)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: AppColors.line, width: 1.5)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: AppColors.sky, width: 1.5)),
                disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: AppColors.line, width: 1.5)),
              ),
            ),
          ),
          const SizedBox(height: 18),

          _HLbl(label: t('Promo code', 'رمز الخصم')),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Builder(builder: (context) {
              // Was `initData?.appliedPromo?.promoCode` — that field never
              // existed on the real applied_promo shape at all (see
              // AppliedPromo's doc), so this always silently evaluated to
              // null for an auto-applied promotion, showing "Enter a promo
              // code" here even while the Order Summary right below
              // correctly showed the real discount applied. `label` here IS
              // the complete display name for this case ("testpromo") —
              // there's no separate secondary title to also show alongside
              // it the way a coupon code + Promotion.title pairing might
              // have had.
              final appliedLabel = initData?.appliedCouponCode ?? initData?.appliedPromo?.label;
              final discount = initData?.summary.couponDiscount ?? 0;
              return GestureDetector(
                onTap: () => _openPromoSheet(
                  context,
                  initData,
                  onInitDataChanged,
                  subtotal: initData?.summary.subtotal ?? totals.before,
                  itemCount: initData?.itemCount ?? cart.cartCount,
                  areaId: a?.areaId,
                ),
                child: Container(
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: AppColors.line, width: 1.5),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Row(children: [
                    const Icon(Icons.sell_outlined, size: 17, color: AppColors.navy),
                    const SizedBox(width: 10),
                    Expanded(
                      child: appliedLabel != null
                          ? Text(appliedLabel, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: AppColors.ink))
                          : Text(t('Enter a promo code', 'أدخل رمز خصم'), style: const TextStyle(color: AppColors.ink, fontSize: 12.5)),
                    ),
                    if (appliedLabel != null && discount > 0)
                      Text('−${Formatters.money(discount)}', style: const TextStyle(color: AppColors.rose, fontWeight: FontWeight.w700, fontSize: 13)),
                    const SizedBox(width: 6),
                    const Icon(Icons.chevron_right_rounded, color: AppColors.muted, size: 16),
                  ]),
                ),
              );
            }),
          ),

          _HLbl(label: t('Order summary', 'ملخص الطلب')),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Builder(builder: (context) {
              final summary = initData?.summary;
              // checkout-init now takes address_id/area_id (confirmed live
              // 2026-09-18) and returns a summary already correct for
              // whichever address is actually selected — no more
              // reconstructing the total from a separately-fetched
              // per-address fee (see this Builder's own history/git blame
              // for what used to be here instead, and
              // AccountService.checkoutInit's doc for the full story).
              if (summary == null) {
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: AppColors.shSm),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.sky)),
                      const SizedBox(width: 10),
                      Text(t('Loading order summary…', 'جارٍ تحميل ملخص الطلب…'), style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
                    ],
                  ),
                );
              }
              final appliedLabel = initData?.appliedCouponCode ?? initData?.appliedPromo?.label;
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: AppColors.shSm),
                child: Column(
                  children: [
                    _SumRow(label: t('Subtotal', 'المجموع الفرعي'), value: Formatters.money(summary.subtotal)),
                    if (summary.discount > 0) _SumRow(label: t('Discount', 'الخصم'), value: '−${Formatters.money(summary.discount)}', color: AppColors.rose),
                    _SumRow(label: t('Delivery fee', 'رسوم التوصيل'), value: summary.deliveryFee == 0 ? t('Free', 'مجاني') : Formatters.money(summary.deliveryFee)),
                    if (summary.couponDiscount > 0) _SumRow(label: appliedLabel != null ? '${t("Promo", "رمز الخصم")} ($appliedLabel)' : t('Promo', 'رمز الخصم'), value: '−${Formatters.money(summary.couponDiscount)}', color: AppColors.rose),
                    Container(
                      margin: const EdgeInsets.only(top: 3),
                      padding: const EdgeInsets.only(top: 11),
                      decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line, width: 1))),
                      child: _SumRow(label: t('Total', 'الإجمالي'), value: Formatters.money(summary.grandTotal), bold: true),
                    ),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(color: AppColors.navy.withOpacity(0.10), blurRadius: 22, offset: const Offset(0, -6))],
        ),
        child: SizedBox(
          width: double.infinity,
          child: Builder(builder: (context) {
            // `initData` is a public field, not a local variable — Dart
            // can't promote a public field from nullable to non-nullable
            // just from an `== null` check the way it can a local `final`,
            // even right next to the check (this is what actually failed
            // the build once: "'initData' refers to a public property so
            // it couldn't be promoted"). Captured into a local here so the
            // compiler can actually see it's non-null below.
            final data = initData;
            return ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.rose,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                elevation: 0,
              ),
              // Needs the real summary before this is tappable or shows an
              // amount — checkout-init's own response is now already
              // correct for whichever address is selected (confirmed live
              // address_id/area_id, 2026-09-18), so this alone is enough;
              // no separate per-address fee to also wait on anymore.
              // Placing an order against a guessed number isn't something
              // to let happen silently either way.
              onPressed: data != null ? () => _placeOrder(context, cart, vm, data) : null,
              child: data == null
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                  : Text(
                      '${t("Place order", "تأكيد الطلب")} · ${Formatters.money(data.summary.grandTotal)}',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
            );
          }),
        ),
      ),
      ),
    );
  }

  Future<void> _placeOrder(BuildContext context, CartState cart, CheckoutViewModel vm, CheckoutInitData? initData) async {
    final ar = context.read<LocaleState>().isArabic;
    String t(String en, String arabic) => ar ? arabic : en;
    // Scoped to just this prescription's lines when rxScope is set — see
    // its doc on CheckoutScreen.
    final scopedRxCart =
        rxScope != null ? Map<String, CartLine>.fromEntries(cart.rxCart.entries.where((e) => e.value.rxId == rxScope)) : cart.rxCart;
    if (cart.cartCount == 0 && scopedRxCart.isEmpty) return;

    if (!await requireLogin(context)) return;
    if (!context.mounted) return;

    final auth = context.read<AuthState>();
    final addressState = context.read<AddressState>();
    final address = addressState.effectiveAddress;
    final orders = context.read<OrdersState>();
    final location = context.read<LocationState>();
    // Still needed below for placeOrderRemote's own `totals:` argument
    // (line grouping/structure for the request), independent of the fix
    // just below for the actual wallet-check AMOUNT.
    final totals = cart.computeTotals(
      storeOverride: cart.cartTab == 'rx' ? scopedRxCart : null,
      areaCatalog: addressState.areaCatalog,
      areaId: address?.areaId,
    );
    // The button that calls this is already disabled until initData is
    // ready (see its onPressed) — kept as an explicit guard anyway.
    // checkout-init's own response is now already correct for whichever
    // address is selected (confirmed live address_id/area_id,
    // 2026-09-18), so summary.grandTotal alone is trustworthy here — no
    // separate per-address fee to also factor in anymore.
    if (initData == null) {
      showErrorToast(context, t('Still loading your order — try again in a moment.', 'لا يزال طلبك قيد التحميل — حاول مرة أخرى بعد لحظات.'));
      return;
    }
    final due = initData.summary.grandTotal;

    if (address == null) {
      showErrorToast(context, t('Please add a delivery address before checking out.', 'يرجى إضافة عنوان توصيل قبل إتمام الطلب.'));
      return;
    }
    if (vm.pay == 'wallet' && orders.wallet < due) {
      showErrorToast(context, t('Insufficient wallet balance for this order.', 'رصيد المحفظة غير كافٍ لهذا الطلب.'));
      return;
    }
    if (address.governorateId == null || address.areaId == null) {
      // Catches every case where the ACTUALLY-RESOLVED address (whatever
      // effectiveAddress landed on — current-location match, or its own
      // fallback to a saved address) lacks a real area to deliver to.
      // Checking the resolved address itself, rather than the internal
      // useCurrentLocation/currentLocationMatchFailed flags on their own,
      // is what matters here — those flags describe HOW an address got
      // resolved, not whether the result is actually usable. A previous
      // version blocked checkout whenever useCurrentLocation was still
      // true and the GPS match had failed, even when effectiveAddress had
      // already correctly fallen back to a perfectly valid saved address
      // — interrupting an already-successful fallback with an unnecessary
      // "Add address" prompt, on every fresh checkout session where GPS
      // simply hadn't resolved yet (useCurrentLocation defaults to true
      // regardless of whether the person ever asked for their current
      // location specifically). Re-selecting an address in that state
      // worked purely because doing so sets useCurrentLocation to false —
      // not because anything about the address itself had changed.
      final saved = await showAddressFormSheet(context, addressState, -1);
      if (!context.mounted) return;
      if (saved == true) {
        await _placeOrder(context, cart, vm, initData);
      } else {
        showErrorToast(context, t('Please add a delivery address before checking out.', 'يرجى إضافة عنوان توصيل قبل إتمام الطلب.'));
      }
      return;
    }

    if (cart.cartTab == 'rx') {
      await _placeRxOrder(context, cart, vm, auth, address, orders);
      return;
    }

    // ✅ Confirmed live in the Postman collection's "Place order" example
    // (`delivery_date`, `delivery_slot`) — this was being collected by the
    // ASAP/Scheduled + calendar + slot-time UI above and then never sent
    // anywhere. For ASAP, defaults to today's date with no slot id (the
    // confirmed example only shows the Scheduled case — what, if anything,
    // an ASAP order should send for `delivery_slot` isn't confirmed, so
    // it's omitted here rather than guessed).
    final deliveryDateStr = (vm.slot == 'sched' && vm.scheduledDate != null) ? _yyyyMMdd(vm.scheduledDate!) : _yyyyMMdd(DateTime.now());
    final deliverySlotId = (vm.slot == 'sched' && initData != null && vm.slotTimeIndex < initData.deliverySlots.length)
        ? initData.deliverySlots[vm.slotTimeIndex].id
        : null;

    // NOT awaited: showDialog()'s Future only resolves once the dialog is
    // popped — awaiting it here would block forever, since nothing pops it
    // until the code below (which never got a chance to run) does.
    showBusyOverlay(context, message: t('Placing your order…', 'جارٍ تقديم طلبك…'));
    try {
      final code = await orders.placeOrderRemote(
        userId: auth.userId!,
        customerName: auth.user?.name.isNotEmpty == true ? auth.user!.name : '${address.first} ${address.last}'.trim(),
        customerPhone: address.phone.isNotEmpty ? address.phone : (auth.user?.phone ?? ''),
        address: address,
        pay: vm.pay,
        totals: totals,
        // Only a genuine typed/selected coupon code goes here — an
        // auto-applied promotion (initData?.appliedPromo) has no code at
        // all (see AppliedPromo's doc); sending its NAME as if it were one
        // risked the order-placement endpoint trying to validate "testpromo"
        // against a coupon-codes table and rejecting it, or worse silently
        // ignoring the discount at the one moment it actually matters. The
        // server already has this promotion applied in its own session
        // state from the earlier successful /app/promotion/apply call, so
        // it doesn't need to be told again here — worth confirming with
        // backend that a placed order's final total does still correctly
        // reflect an auto-applied promo when this field is empty.
        coupon: initData?.appliedCouponCode ?? '',
        deliveryDate: deliveryDateStr,
        deliverySlot: deliverySlotId,
        // Sent alongside the structured address regardless of which saved
        // address was chosen — the device's actual GPS pin, for the rider.
        latitude: location.position?.latitude,
        longitude: location.position?.longitude,
      );
      if (context.mounted) hideBusyOverlay(context);
      if (!context.mounted) return;

      // Matches the native Android app's sequencing exactly (see
      // `CheckOutActivity.updateStatus` observer): the order is created
      // FIRST regardless of payment method, and only THEN — if KNET was
      // chosen — does the Tap `goSellSDK` session start, using the new
      // order's own code as the reference reported back afterwards. COD
      // and wallet finish immediately here, same as before.
      TapChargeOutcome? verified;
      if (vm.pay == 'knet') {
        final customerName = auth.user?.name.isNotEmpty == true ? auth.user!.name : address.first;
        var result = await TapPaymentService.instance.payWithKnet(
          userId: auth.userId!,
          amount: due,
          customerFirstName: customerName,
          customerEmail: auth.user?.email ?? '',
          customerPhone: address.phone.replaceAll(RegExp(r'\s'), '').replaceFirst(RegExp(r'^(\+?965)'), ''),
          orderCode: code,
        );
        if (!context.mounted) return;

        // Session ended via the plugin's cancel callback — no charge id, so
        // there's nothing to verify against Tap, and (like the old native
        // app, which does nothing on sessionCancelled) nothing is reported
        // to the backend: telling it "failed" would assert something this
        // app can't actually know. A KNET payment can complete at the bank
        // while the session still ends this way (the real incident), so the
        // customer is told plainly what to do rather than a vanishing toast.
        if (result.cancelled) {
          final viewOrder = await _showPaymentCancelledDialog(context, code);
          if (!context.mounted) return;
          if (viewOrder == true) {
            cart.clearCartRemote(auth.userId!);
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => TrackScreen(orderId: code)),
              (route) => route.isFirst,
            );
          }
          return;
        }

        // The SDK's own result isn't a reliable verdict for a redirect-based
        // method like KNET: real incident (2026-10-03) — Tap's dashboard
        // showed the charge Captured / Paid successfully while this app was
        // told it failed, so the customer saw "Payment was not completed"
        // for money that had actually left their account. Whenever the SDK
        // says anything other than success but a charge exists, ask Tap
        // directly what really happened before telling the customer
        // anything (see TapPaymentService.verifyCharge).
        final chargeId = result.chargeId;
        if (!result.success && chargeId != null && chargeId.isNotEmpty) {
          showBusyOverlay(context, message: t('Confirming your payment…', 'جارٍ تأكيد الدفع…'));
          verified = await TapPaymentService.instance.verifyCharge(chargeId);
          if (context.mounted) hideBusyOverlay(context);
          if (!context.mounted) return;
          if (verified == TapChargeOutcome.captured) {
            result = TapPaymentResult(success: true, chargeId: chargeId);
          }
        }

        final reported = await TapPaymentService.instance.reportPaymentResponse(
          orderCode: code,
          success: result.success,
          transactionId: result.chargeId,
        );
        if (!context.mounted) return;

        if (!result.success && verified != TapChargeOutcome.pending) {
          showErrorToast(context, result.errorMessage ?? t('KNET payment failed. Your order is saved — you can try paying again from Order details.', 'فشلت عملية الدفع عبر كي نت. تم حفظ طلبك — يمكنك محاولة الدفع مرة أخرى من تفاصيل الطلب.'));
          if (TapPaymentService.paymentDebug) await _showPaymentDebugDialog(context);
          return; // stay on checkout; order already exists but isn't marked paid
        }
        if (verified == TapChargeOutcome.pending) {
          // A charge exists but Tap hadn't reached a final state inside the
          // wait window — it may well be paid. Staying on checkout here
          // would invite the customer to place the order again and be
          // charged twice, so this goes on to the order instead, with a
          // clear "don't pay again" message.
          showErrorToast(context, t('We couldn\'t confirm your payment yet. If money was deducted, please don\'t pay again — check order #$code or contact support.', 'لم نتمكن من تأكيد الدفع بعد. إذا تم خصم المبلغ فلا تدفع مرة أخرى — راجع الطلب #$code أو تواصل مع الدعم.'));
          if (TapPaymentService.paymentDebug) {
            await _showPaymentDebugDialog(context);
            if (!context.mounted) return;
          }
        } else if (!reported) {
          showErrorToast(context, t('Payment went through, but we couldn\'t confirm it with the server. Please check Order details.', 'تمت عملية الدفع، لكن لم نتمكن من تأكيدها مع الخادم. يرجى مراجعة تفاصيل الطلب.'));
          return;
        }
      }

      cart.clearCartRemote(auth.userId!);
      // Not shown when payment is still unconfirmed — it would immediately
      // cover the "don't pay again" warning above.
      if (verified != TapChargeOutcome.pending) {
        showToast(context, t('Order placed! Tracking #$code', 'تم تقديم الطلب! رقم التتبع #$code'));
      }
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => TrackScreen(orderId: code)),
        (route) => route.isFirst,
      );
    } catch (e) {
      if (context.mounted) hideBusyOverlay(context);
      if (!context.mounted) return;
      final message = describeError(e);
      // A server-side address validation failure (e.g. "The address.block
      // field is required") was easy to miss as a toast — it could land
      // half-covering whatever field the person was looking at (see the
      // screenshot this was reported from), and disappears on its own
      // before there's time to act on it. Detected by the Laravel-style
      // "address.<field>" naming in the message; shown as a dialog instead,
      // with a direct path to fix the actual problem rather than just
      // reading about it.
      if (message.toLowerCase().contains('address.')) {
        await _showAddressErrorDialog(context, addressState, message);
      } else {
        showErrorToast(context, message);
      }
    }
  }

  /// Shown when the Tap session ends via cancel. Returns true if the
  /// customer chose to go to the order instead of staying on checkout.
  /// Staying and re-placing would create a second order, and — if the
  /// first payment actually went through at the bank — a second charge.
  Future<bool?> _showPaymentCancelledDialog(BuildContext context, String code) {
    final ar = context.read<LocaleState>().isArabic;
    String t(String en, String arabic) => ar ? arabic : en;
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Directionality(
        textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
        child: AlertDialog(
          title: Text(t('Payment not completed', 'لم تكتمل عملية الدفع')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t(
                  'If your bank shows a deduction, please don\'t pay again — your order #$code is saved and we can confirm it. Otherwise you can try again.',
                  'إذا ظهر خصم في حسابك البنكي فلا تدفع مرة أخرى — طلبك #$code محفوظ ويمكننا تأكيده. وإلا يمكنك المحاولة مرة أخرى.',
                )),
                // Only in test APKs built with --dart-define=PAYMENT_DEBUG=true.
                if (TapPaymentService.paymentDebug) ..._paymentDebugBlock(),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(t('Try again', 'حاول مرة أخرى'))),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(t('View order', 'عرض الطلب'))),
          ],
        ),
      ),
    );
  }

  /// Raw SDK result + Tap check for the last payment attempt, selectable and
  /// copyable. Exists so a client testing an APK on their own phone (no PC,
  /// so no `adb logcat`) can screenshot or paste exactly what happened.
  /// Gated by [TapPaymentService.paymentDebug]; never shown to customers.
  List<Widget> _paymentDebugBlock() => [
        const SizedBox(height: 14),
        const Text('Test details', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        SelectableText(TapPaymentService.instance.lastDiagnostics, style: const TextStyle(fontSize: 11)),
        TextButton(
          onPressed: () => Clipboard.setData(ClipboardData(text: TapPaymentService.instance.lastDiagnostics)),
          child: const Text('Copy details'),
        ),
      ];

  Future<void> _showPaymentDebugDialog(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Payment details (test build)'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: _paymentDebugBlock())),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close'))],
      ),
    );
  }

  /// See the catch block in [_placeOrder] above for why this exists —
  /// same address-validation-error dialog used by [_placeRxOrder] too.
  Future<void> _showAddressErrorDialog(BuildContext context, AddressState addressState, String message) async {
    final ar = context.read<LocaleState>().isArabic;
    final shouldEdit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
        child: AlertDialog(
        title: Text(ar ? 'هناك مشكلة في هذا العنوان' : 'There\'s a problem with this address'),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(ar ? 'إلغاء' : 'Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(ar ? 'تعديل العنوان' : 'Edit address')),
        ],
        ),
      ),
    );
    if (shouldEdit == true && context.mounted) {
      // Was always `addressState.selectedIndex` — a SAVED address, even
      // when the order is actually going to "Current location" instead
      // (useCurrentLocation true). Confirmed live: the person's order was
      // using their GPS-detected location, which has no block/building at
      // all (that's exactly what this dialog is about) — but "Edit
      // address" opened a COMPLETELY different, already-complete SAVED
      // address's form instead, with nothing to do with the actual
      // problem. Opening as "add new" (-1) instead correctly triggers
      // _autofillFromLocation (see its doc) — it prefills governorate/
      // area/street from the same live GPS match already being used for
      // checkout, leaving just the genuinely-missing fields (block etc.)
      // for the person to fill in, rather than either editing the wrong
      // address or making them re-enter everything from scratch.
      final index = addressState.useCurrentLocation ? -1 : addressState.selectedIndex;
      final saved = await showAddressFormSheet(context, addressState, index);
      // Without this, saveRemote() sets selectedIndex to the new address
      // but leaves useCurrentLocation true — effectiveAddress would keep
      // resolving back to the SAME incomplete GPS-only address regardless,
      // so the exact same "block is required" error would recur on the
      // very next "Place order" attempt despite having just fixed it.
      // select() flips that off (and re-selects the same index, which
      // saveRemote already set correctly — redundant there, but reuses its
      // existing, already-correct refresh logic rather than duplicating
      // it). Only in this specific flow — an unrelated address edit
      // elsewhere shouldn't silently switch what's active for checkout.
      if (saved == true && index == -1 && context.mounted) {
        addressState.select(addressState.selectedIndex);
      }
    }
  }

  /// The Rx cart checks out through a completely separate endpoint
  /// (`POST /app/acct/rx/checkout`) — one prescription at a time, and it
  /// needs a real *saved* address id, unlike the regular flow above which
  /// can use a GPS-matched "current location" address. See
  /// [OrdersState.placeRxOrdersRemote] for why this can mean more than one
  /// network call for a single tap of "Place order".
  Future<void> _placeRxOrder(
    BuildContext context,
    CartState cart,
    CheckoutViewModel vm,
    AuthState auth,
    Address address,
    OrdersState orders,
  ) async {
    final ar = context.read<LocaleState>().isArabic;
    String t(String en, String arabic) => ar ? arabic : en;
    if (address.id == null) {
      showErrorToast(context, t('Rx checkout needs a saved address — please pick one instead of using your current location.', 'يتطلب إتمام طلب الوصفة عنواناً محفوظاً — يرجى اختيار عنوان بدلاً من استخدام موقعك الحالي.'));
      return;
    }

    // Scoped to just this prescription's lines (see rxScope's doc on
    // CheckoutScreen) — confirmed against the reference web app, each
    // prescription's Rx cart lines check out separately, not combined with
    // whatever else happens to be in the Rx cart at the same time.
    final scopedRxCart =
        rxScope != null ? Map<String, CartLine>.fromEntries(cart.rxCart.entries.where((e) => e.value.rxId == rxScope)) : cart.rxCart;

    // Only in-stock lines actually go through — see CartState.isRxLineInStock's
    // doc for why an Rx line can go stale after being added (pricing/stock is
    // set by a pharmacist, possibly well after the add). Left in the cart
    // rather than removed, same as a line whose own checkout call fails below,
    // so the person can see it's still there (now labeled) rather than having
    // it silently vanish.
    final outOfStockKeys = scopedRxCart.entries.where((e) => !cart.isRxLineInStock(e.value)).map((e) => e.key).toSet();
    if (outOfStockKeys.length == scopedRxCart.length && scopedRxCart.isNotEmpty) {
      showErrorToast(context, t('Every item in your Rx cart is out of stock right now — nothing to submit.', 'كل العناصر في سلة الوصفة غير متوفرة حالياً — لا يوجد شيء لإرساله.'));
      return;
    }
    final inStockRxCart = Map<String, CartLine>.fromEntries(scopedRxCart.entries.where((e) => !outOfStockKeys.contains(e.key)));
    if (outOfStockKeys.isNotEmpty) {
      showToast(context, t('${outOfStockKeys.length} out-of-stock item${outOfStockKeys.length > 1 ? 's' : ''} skipped', '${outOfStockKeys.length} عنصر غير متوفر تم تخطيه'));
    }

    showBusyOverlay(context, message: t('Submitting your prescription order…', 'جارٍ إرسال طلب وصفتك…'));
    try {
      final results = await orders.placeRxOrdersRemote(
        userId: auth.userId!,
        addressId: address.id!,
        payment: vm.pay,
        rxCart: inStockRxCart,
      );
      if (context.mounted) hideBusyOverlay(context);
      if (!context.mounted) return;

      final succeeded = results.where((r) => r.success).toList();
      final failed = results.where((r) => !r.success).toList();

      if (succeeded.isNotEmpty) {
        // Only clear what actually went through — a line whose prescription
        // failed to check out should still be sitting in the Rx cart
        // afterward, not silently dropped.
        cart.rxCart.removeWhere((_, line) => succeeded.any((r) => r.prescriptionId == line.rxId));
        cart.notifyListeners();
      }

      if (failed.isEmpty) {
        showToast(context, succeeded.length > 1 ? t('Submitted ${succeeded.length} prescription orders', 'تم إرسال ${succeeded.length} طلبات وصفة') : t('Prescription order submitted', 'تم إرسال طلب الوصفة'));
        final code = succeeded.first.orderCode;
        if (code != null) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => TrackScreen(orderId: code)),
            (route) => route.isFirst,
          );
        } else {
          Navigator.pop(context);
        }
      } else if (succeeded.isEmpty) {
        final message = failed.first.error ?? t('Couldn\'t submit your prescription order.', 'تعذر إرسال طلب وصفتك.');
        if (message.toLowerCase().contains('address.')) {
          await _showAddressErrorDialog(context, context.read<AddressState>(), message);
        } else {
          showErrorToast(context, message);
        }
      } else {
        // Mixed result — some prescriptions checked out, at least one didn't.
        showToast(context, t('${succeeded.length} submitted, ${failed.length} failed — still in your Rx cart', 'تم إرسال ${succeeded.length}، وفشل ${failed.length} — لا تزال في سلة الوصفة'));
        Navigator.pop(context);
      }
    } catch (e) {
      if (context.mounted) hideBusyOverlay(context);
      if (!context.mounted) return;
      final message = describeError(e);
      if (message.toLowerCase().contains('address.')) {
        await _showAddressErrorDialog(context, context.read<AddressState>(), message);
      } else {
        showErrorToast(context, message);
      }
    }
  }


  // ── Real promo sheet — replaces the old picker that just chose among a
  // hardcoded, entirely client-side "promos" list with no backend
  // involvement at all. Now backed by checkout-init's real `promotions`
  // list and the real apply/remove endpoints. ──
  void _openPromoSheet(
    BuildContext context,
    CheckoutInitData? initData,
    ValueChanged<CheckoutInitData> onChanged, {
    required double subtotal,
    required int itemCount,
    int? areaId,
  }) {
    final ar = context.read<LocaleState>().isArabic;
    String t(String en, String arabic) => ar ? arabic : en;
    final auth = context.read<AuthState>();
    final userId = auth.userId;
    // Only a genuine typed code pre-fills this — an auto-applied
    // promotion's own NAME (e.g. "testpromo") isn't something the person
    // could type back in here as if it were a code (see AppliedPromo's doc
    // for why it was never really a "code" at all).
    final currentCode = initData?.appliedCouponCode ?? '';
    final controller = TextEditingController(text: currentCode);
    // Excludes whichever promotion is already auto-applied (matched by its
    // real promotion_id, not the old broken id-from-Promotion.fromJson
    // comparison) — without this, an already-applied no-code promotion
    // kept showing in this list as if it still needed tapping.
    final appliedPromotionId = initData?.appliedPromo?.promotionId;
    final active = (initData?.promotions ?? const <Promotion>[]).where((p) => p.isActive && p.id != appliedPromotionId).toList();
    // Backend is adding promotion_id support to the remove endpoint
    // (reported 2026-09-23) — see AccountService.removePromotion's doc.
    // Previously this only allowed removing a genuine typed code, since
    // an auto-applied promotion's removal had no working endpoint at
    // all; remove() below now sends whichever real identifier applies.
    final hasApplied = (initData?.appliedCouponCode != null) || (initData?.appliedPromo != null);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (sheetContext) => Directionality(
        textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
        child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
        child: StatefulBuilder(builder: (sheetContext, setSheetState) {
          bool checking = false;
          String? error;

          // Apply/remove only return {success, message, ...} — not the
          // updated cart/totals — so a successful one needs a follow-up
          // full re-fetch to actually refresh what's on screen. Same
          // address-context fix as the auto-apply path in
          // _loadCheckoutInit — without addressId/areaId here, this could
          // come back reflecting a different address's checkout state
          // than the one actually in use, making a successful apply look
          // like it didn't take.
          Future<void> refreshAfterChange() async {
            if (userId == null) return;
            final address = context.read<AddressState>().effectiveAddress;
            final fresh = await AccountService.instance.checkoutInit(userId, prescriptionId: rxScope, addressId: address?.id, areaId: address?.areaId);
            onChanged(fresh);
          }

          Future<void> applyCode(String code) async {
            if (userId == null || code.isEmpty) return;
            setSheetState(() { checking = true; error = null; });
            try {
              final result = await AccountService.instance.applyPromoCode(userId, code, subtotal: subtotal);
              if (!result.success) {
                final msg = result.message ?? t('That code isn\'t valid for this order.', 'هذا الرمز غير صالح لهذا الطلب.');
                setSheetState(() { checking = false; error = msg; });
                showErrorToast(sheetContext, msg);
                return;
              }
              await refreshAfterChange();
              if (sheetContext.mounted) Navigator.pop(sheetContext);
            } catch (e) {
              final msg = describeError(e);
              setSheetState(() { checking = false; error = msg; });
              showErrorToast(sheetContext, msg);
            }
          }

          Future<void> applyPromotion(Promotion promo) async {
            if (userId == null) return;
            if (promo.requiresCode && promo.promoCode != null) {
              await applyCode(promo.promoCode!);
              return;
            }
            setSheetState(() { checking = true; error = null; });
            try {
              final result = await AccountService.instance.applyPromotion(userId, promo.id, subtotal: subtotal, itemCount: itemCount, areaId: areaId);
              if (!result.success) {
                // Was ONLY setting `error` here, which is bound to the typed-
                // code TextField's `errorText` further down — meaningless for
                // a failure that came from tapping a LISTED offer, not typing
                // anything into that field. With the list sitting below the
                // field (sometimes well below, on a scrolled sheet), that left
                // this failure with no visible feedback at all — tapping an
                // offer that then silently did nothing, confirmed live: a
                // real "Promotion not found or expired" 404 on tapping
                // exactly this kind of listed offer. A toast is visible
                // regardless of where in the sheet the person's looking.
                final msg = result.message ?? t('Couldn\'t apply that offer.', 'تعذر تطبيق هذا العرض.');
                setSheetState(() { checking = false; error = msg; });
                showErrorToast(sheetContext, msg);
                return;
              }
              await refreshAfterChange();
              if (sheetContext.mounted) Navigator.pop(sheetContext);
            } catch (e) {
              final msg = describeError(e);
              setSheetState(() { checking = false; error = msg; });
              showErrorToast(sheetContext, msg);
            }
          }

          Future<void> remove() async {
            if (userId == null) return;
            setSheetState(() { checking = true; error = null; });
            try {
              // Confirmed by backend (2026-09-23): removes whatever's
              // currently applied for this user, no code or promotion_id
              // needed at all — works the same whether a typed code or an
              // auto-applied promotion is what's actually active.
              final result = await AccountService.instance.removePromotion(userId, subtotal: subtotal);
              if (!result.success) {
                final msg = result.message ?? t('Couldn\'t remove that offer.', 'تعذر إزالة هذا العرض.');
                setSheetState(() { checking = false; error = msg; });
                showErrorToast(sheetContext, msg);
                return;
              }
              await refreshAfterChange();
              if (sheetContext.mounted) Navigator.pop(sheetContext);
            } catch (e) {
              final msg = describeError(e);
              setSheetState(() { checking = false; error = msg; });
              showErrorToast(sheetContext, msg);
            }
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text(t('Promo code', 'رمز الخصم'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.navy)),
                    InkWell(onTap: () => Navigator.pop(sheetContext), child: const Icon(Icons.close_rounded, size: 20, color: AppColors.muted)),
                  ]),
                  const SizedBox(height: 14),
                  TextField(
                    controller: controller,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      hintText: t('Enter code', 'أدخل الرمز'),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      errorText: error,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.navy, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 13)),
                      onPressed: checking ? null : () => applyCode(controller.text.trim()),
                      child: Text(checking ? t('Applying…', 'جارٍ التطبيق…') : t('Apply', 'تطبيق')),
                    ),
                  ),
                  if (hasApplied)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: checking ? null : remove,
                          child: Text(t('Remove applied code', 'إزالة الرمز المطبق')),
                        ),
                      ),
                    ),
                  // Real offers from checkout-init — a promotion with its
                  // own code fills the field above and applies it; one
                  // without a code (condition-based, e.g. "min 3 items")
                  // applies directly by its id via /app/promotion/apply.
                  if (active.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Text(t('Available offers', 'العروض المتاحة'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.navy)),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 220),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: active.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final promo = active[i];
                          // The server's own label (e.g. "20% off"), not a
                          // reconstruction — offerValue alone is the raw
                          // config number, not display text. Falls back to
                          // building one only if label is somehow missing.
                          final desc = promo.label ?? (promo.offerType == 'percent'
                              ? t('${promo.offerValue.toStringAsFixed(0)}% off', '${promo.offerValue.toStringAsFixed(0)}% خصم')
                              : t('${Formatters.money(promo.offerValue)} off', '${Formatters.money(promo.offerValue)} خصم'));
                          // The ACTUAL savings for THIS cart (not just the
                          // promo's raw rate) — matters most for a percent
                          // promo, where "20% off" alone doesn't say how
                          // much that comes to on the current subtotal. Was
                          // gated on `offerType == 'percent'` too, but a
                          // real live promo had `offer_type: "A percent
                          // amount discount"` (free text, not that literal
                          // key) alongside a real non-zero `discount` —
                          // discount>0 alone is the confirmed signal (see
                          // Promotion.isActive's doc comment for the same
                          // issue), so this no longer depends on offerType's
                          // exact wording at all.
                          final savings = promo.discount > 0 ? t(' · saves ${Formatters.money(promo.discount)}', ' · يوفر ${Formatters.money(promo.discount)}') : '';
                          return GestureDetector(
                            onTap: checking ? null : () => applyPromotion(promo),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(11)),
                              child: Row(children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(promo.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: AppColors.navy)),
                                      const SizedBox(height: 2),
                                      Text(
                                        promo.requiresCode ? '$desc$savings · ${t("code", "الرمز")} ${promo.promoCode}' : '$desc$savings',
                                        style: const TextStyle(fontSize: 11, color: AppColors.muted),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.muted),
                              ]),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }),
        ),
      ),
    );
  }
}

// ── .h-lbl — navy bold section label ──
/// .cal — inline month calendar shown when "Scheduled" is picked, matching
/// `rCalendar()`: bordered box, month header with prev/next nav, day-of-week
/// row, then a 7-column day grid. Past days are greyed out and unselectable;
/// the selected day is a filled navy circle.
class _Calendar extends StatelessWidget {
  final CheckoutViewModel vm;
  const _Calendar({required this.vm});

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  static const _monthsAr = [
    'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
    'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
  ];
  static const _dow = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'];
  // Single-letter day headers are the idiomatic short form in Arabic
  // calendar UIs (there's no clean 2-letter abbreviation convention the
  // way English has Su/Mo/Tu) — same Sunday-first order as _dow above.
  static const _dowAr = ['ح', 'ن', 'ث', 'ر', 'خ', 'ج', 'س'];

  @override
  Widget build(BuildContext context) {
    final ar = context.watch<LocaleState>().isArabic;
    final y = vm.calendarMonth.year;
    final m = vm.calendarMonth.month; // 1-12
    final today = DateTime.now();
    final todayMidnight = DateTime(today.year, today.month, today.day);
    final firstOfMonth = DateTime(y, m, 1);
    final daysInMonth = DateTime(y, m + 1, 0).day;
    final startDow = firstOfMonth.weekday % 7; // DateTime.weekday: Mon=1..Sun=7 -> Sun=0..Sat=6
    final monthNames = ar ? _monthsAr : _months;
    final dowLabels = ar ? _dowAr : _dow;

    return Directionality(
      textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
      child: Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppColors.line, width: 1.5), borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: [
          // .cal-h
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: () => vm.calNav(-1),
                icon: const Icon(Icons.chevron_left_rounded, color: AppColors.navy),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              Text('${monthNames[m - 1]} $y', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.navy, fontSize: 14)),
              IconButton(
                onPressed: () => vm.calNav(1),
                icon: const Icon(Icons.chevron_right_rounded, color: AppColors.navy),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // .cal-dow
          Row(children: [for (final d in dowLabels) Expanded(child: Center(child: Text(d, style: const TextStyle(fontSize: 11, color: AppColors.muted, fontWeight: FontWeight.w600))))]),
          const SizedBox(height: 4),
          // .cal-grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, mainAxisSpacing: 3, crossAxisSpacing: 3, childAspectRatio: 1),
            itemCount: startDow + daysInMonth,
            itemBuilder: (context, i) {
              if (i < startDow) return const SizedBox();
              final day = i - startDow + 1;
              final date = DateTime(y, m, day);
              final isPast = date.isBefore(todayMidnight);
              final isSelected = vm.scheduledDate != null &&
                  vm.scheduledDate!.year == y && vm.scheduledDate!.month == m && vm.scheduledDate!.day == day;
              return GestureDetector(
                onTap: isPast ? null : () => vm.setScheduledDate(date),
                child: Container(
                  decoration: BoxDecoration(color: isSelected ? AppColors.navy : Colors.transparent, borderRadius: BorderRadius.circular(9)),
                  alignment: Alignment.center,
                  child: Text(
                    '$day',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white : (isPast ? AppColors.cloud : AppColors.ink),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      ),
    );
  }
}

class _HLbl extends StatelessWidget {
  final String label;
  const _HLbl({required this.label});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 9),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.navy, fontSize: 14.5)),
    );
  }
}

// ── .sec2 ──
class _Sec2 extends StatelessWidget {
  final String label;
  final VoidCallback onEdit;
  const _Sec2({required this.label, required this.onEdit});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 9),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.navy, fontSize: 14.5)),
        InkWell(
          onTap: onEdit,
          borderRadius: BorderRadius.circular(15),
          child: const SizedBox(width: 30, height: 30, child: Icon(Icons.edit_outlined, size: 17, color: AppColors.sky)),
        ),
      ]),
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback onTap;
  const _ChoiceChip({required this.label, required this.on, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: on ? AppColors.navy : Colors.white,
          border: Border.all(color: on ? AppColors.navy : AppColors.line, width: 1.5),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(label, style: TextStyle(color: on ? Colors.white : AppColors.muted, fontWeight: FontWeight.w600, fontSize: 13)),
      ),
    );
  }
}

class _PayOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool on;
  final VoidCallback onTap;
  const _PayOption({required this.icon, required this.label, required this.on, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: on ? const Color(0xFFF2FAFE) : Colors.white,
            border: Border.all(color: on ? AppColors.sky : AppColors.line, width: 1.5),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Row(children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(10)),
              alignment: Alignment.center,
              child: Icon(icon, size: 18, color: AppColors.navy),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, color: AppColors.ink))),
            Container(
              width: 20, height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: on ? AppColors.sky : AppColors.line, width: 2),
              ),
              child: on
                  ? Center(child: Container(width: 12, height: 12, decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.sky)))
                  : null,
            ),
          ]),
        ),
      ),
    );
  }
}

class _SumRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  final bool bold;
  const _SumRow({required this.label, required this.value, this.color, this.bold = false});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: bold ? 0 : 9),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: TextStyle(color: bold ? AppColors.navy : (color ?? AppColors.muted), fontWeight: bold ? FontWeight.w700 : FontWeight.w500, fontSize: bold ? 16 : 13)),
        Text(value, style: TextStyle(color: bold ? AppColors.navy : (color ?? AppColors.muted), fontWeight: bold ? FontWeight.w700 : FontWeight.w500, fontSize: bold ? 16 : 13)),
      ]),
    );
  }
}

/// Formats a [DateTime] as `yyyy-MM-dd` for the `delivery_date` field —
/// confirmed live in the Postman collection's "Place order" example.
String _yyyyMMdd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
