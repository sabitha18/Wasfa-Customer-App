import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/auth_gate.dart';
import '../../core/widgets/async_state_view.dart';
import '../../data/models/checkout_init.dart';
import '../../data/services/account_service.dart';
import '../../data/services/tap_payment_service.dart';
import '../../state/address_state.dart';
import '../../state/app_settings_state.dart';
import '../../state/auth_state.dart';
import '../../state/cart_state.dart';
import '../../state/location_state.dart';
import '../../state/orders_state.dart';
import '../../viewmodels/checkout_view_model.dart';
import '../widgets/page_header.dart';
import '../widgets/address_sheets.dart';
import '../widgets/toast.dart';
import 'track_screen.dart';
import '../../data/models/address.dart';
class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  CheckoutInitData? _initData;
  bool _initLoading = true;
  String? _initError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final addressState = context.read<AddressState>();
      final location = context.read<LocationState>();
      await addressState.loadAreas();
      // Match the GPS-detected area against the real catalog now that it's
      // loaded, so "Current location" (the default) carries a real
      // governorate/area, not just a display label.
      addressState.syncFromLocation(governorate: location.governorate, area: location.area, street: location.street);
      final auth = context.read<AuthState>();
      if (auth.isSignedIn) {
        addressState.loadAddresses(auth.userId!);
        _loadCheckoutInit(auth.userId!);
      } else {
        setState(() => _initLoading = false);
      }
    });
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
      final data = await AccountService.instance.checkoutInit(userId);
      if (!mounted) return;
      context.read<AddressState>().hydrateAddresses(data.addresses);
      context.read<AppSettingsState>().applyFromCheckout(data.paymentMethods.enabledKeys);
      context.read<OrdersState>().syncWalletBalance(data.walletBalance);
      setState(() {
        _initData = data;
        _initLoading = false;
        _initError = null;
      });
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
      ),
    );
  }
}

class _CheckoutBody extends StatelessWidget {
  final CheckoutInitData? initData;
  final bool initLoading;
  final String? initError;
  final ValueChanged<CheckoutInitData> onInitDataChanged;
  const _CheckoutBody({required this.initData, required this.initLoading, required this.initError, required this.onInitDataChanged});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<CheckoutViewModel>();
    final cart = context.watch<CartState>();
    final addressState = context.watch<AddressState>();
    final location = context.watch<LocationState>();
    final totals = cart.computeTotals();
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

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: PageHeader(title: 'Checkout'),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 120),
        children: [
          if (initError != null)
            // Non-blocking — checkout still works from local computation
            // while this failed, so this is a note, not a hard stop.
            InlineErrorBanner(message: 'Some checkout details didn\'t load: $initError', onRetry: null)
          else if (initLoading && initData == null)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(children: [
                SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.sky)),
                SizedBox(width: 8),
                Text('Loading checkout details…', style: TextStyle(fontSize: 11.5, color: AppColors.muted)),
              ]),
            ),
          // ── .sec2 — "Shipping address" + edit icon ──
          _Sec2(
            label: 'Shipping address',
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
                        const Expanded(
                          child: Text('Add a delivery address to continue', style: TextStyle(color: AppColors.rose, fontWeight: FontWeight.w600, fontSize: 12.5)),
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
                    const Row(children: [
                      Text('Change address', style: TextStyle(color: AppColors.sky, fontWeight: FontWeight.w600, fontSize: 12)),
                      SizedBox(width: 3),
                      Icon(Icons.chevron_right_rounded, size: 14, color: AppColors.sky),
                    ]),
                  ],
                ),
              ),
            ),
          ),

          const _HLbl(label: 'Delivery date'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              _ChoiceChip(label: 'ASAP', on: vm.slot == 'asap', onTap: () => vm.setSlot('asap')),
              const SizedBox(width: 8),
              _ChoiceChip(label: 'Scheduled', on: vm.slot == 'sched', onTap: () => vm.setSlot('sched')),
            ]),
          ),
          if (vm.slot == 'sched') ...[
            _Calendar(vm: vm),
            const _HLbl(label: 'Shipping method'),
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
                        ? '${initData!.deliverySlots[i].title} · ${Formatters.money(initData!.deliverySlots[i].amount)}'
                        : initData!.deliverySlots[i].title,
                    on: vm.slotTimeIndex == i,
                    onTap: () => vm.setSlotTime(i),
                  ),
              ]),
            ),
          ],

          const _HLbl(label: 'Payment method'),
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
                  return _PayOption(icon: Icons.credit_card_rounded, label: 'KNET', on: vm.pay == 'knet', onTap: () => vm.setPay('knet'));
                case 'card':
                  return _PayOption(icon: Icons.credit_card_rounded, label: 'Card', on: vm.pay == 'card', onTap: () => vm.setPay('card'));
                case 'wallet':
                  return _PayOption(icon: Icons.account_balance_wallet_rounded, label: 'Wallet · ${Formatters.money(wallet)}', on: vm.pay == 'wallet', onTap: () => vm.setPay('wallet'));
                case 'cod':
                  return _PayOption(icon: Icons.payments_rounded, label: 'Cash on delivery', on: vm.pay == 'cod', onTap: () => vm.setPay('cod'));
                default:
                  return const SizedBox.shrink();
              }
            }
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(children: [for (final key in enabled) optionFor(key)]),
            );
          }),

          const _HLbl(label: 'Additional notes'),
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
                hintText: 'Any note for the rider or pharmacy…',
                hintStyle: const TextStyle(color: AppColors.muted, fontSize: 14),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: AppColors.line, width: 1.5)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: AppColors.line, width: 1.5)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: AppColors.sky, width: 1.5)),
                disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: AppColors.line, width: 1.5)),
              ),
            ),
          ),
          const SizedBox(height: 18),

          const _HLbl(label: 'Promo code'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Builder(builder: (context) {
              final appliedLabel = initData?.appliedCouponCode ?? initData?.appliedPromo?.promoCode;
              final appliedTitle = initData?.appliedPromo?.title;
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
                          ? Text.rich(TextSpan(children: [
                        TextSpan(text: '$appliedLabel ', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: AppColors.ink)),
                        if (appliedTitle != null) TextSpan(text: '· $appliedTitle', style: const TextStyle(color: AppColors.ink, fontSize: 12.5)),
                      ]))
                          : const Text('Enter a promo code', style: TextStyle(color: AppColors.ink, fontSize: 12.5)),
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

          const _HLbl(label: 'Order summary'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Builder(builder: (context) {
              // Prefers the server's own computed totals (confirmed live
              // via checkout-init) once loaded — that reflects its actual
              // promo/delivery-fee logic exactly, rather than the client
              // trying to replicate it locally. Falls back to local
              // computation only until that fetch completes (or if it
              // fails), so the screen isn't blank in the meantime.
              final summary = initData?.summary;
              final local = cart.computeTotals();
              final subtotal = summary?.subtotal ?? local.before;
              final deliveryFee = summary?.deliveryFee ?? local.deliveryFee;
              final couponDiscount = summary?.couponDiscount ?? local.promoDiscount;
              final grandTotal = summary?.grandTotal ?? local.due;
              final appliedLabel = initData?.appliedCouponCode ?? initData?.appliedPromo?.promoCode;
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: AppColors.shSm),
                child: Column(
                  children: [
                    _SumRow(label: 'Subtotal', value: Formatters.money(subtotal)),
                    if (summary == null && local.itemDiscount > 0) _SumRow(label: 'Discount', value: '−${Formatters.money(local.itemDiscount)}', color: AppColors.rose),
                    _SumRow(label: 'Delivery fee', value: deliveryFee == 0 ? 'Free' : Formatters.money(deliveryFee)),
                    if (couponDiscount > 0) _SumRow(label: appliedLabel != null ? 'Promo ($appliedLabel)' : 'Promo', value: '−${Formatters.money(couponDiscount)}', color: AppColors.rose),
                    Container(
                      margin: const EdgeInsets.only(top: 3),
                      padding: const EdgeInsets.only(top: 11),
                      decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line, width: 1))),
                      child: _SumRow(label: 'Total', value: Formatters.money(grandTotal), bold: true),
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
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.rose,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
              elevation: 0,
            ),
            onPressed: () => _placeOrder(context, cart, vm, initData),
            child: Text('Place order · ${Formatters.money(initData?.summary.grandTotal ?? totals.due)}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          ),
        ),
      ),
    );
  }

  Future<void> _placeOrder(BuildContext context, CartState cart, CheckoutViewModel vm, CheckoutInitData? initData) async {
    if (cart.cartCount == 0 && cart.rxCartCount == 0) return;

    if (!await requireLogin(context)) return;
    if (!context.mounted) return;

    final auth = context.read<AuthState>();
    final addressState = context.read<AddressState>();
    final address = addressState.effectiveAddress;
    final orders = context.read<OrdersState>();
    final location = context.read<LocationState>();
    final totals = cart.computeTotals();
    // Prefer the server's own total (confirmed live via checkout-init) for
    // the wallet-balance check, same reasoning as the summary display above.
    final due = initData?.summary.grandTotal ?? totals.due;

    if (address == null) {
      showErrorToast(context, 'Please add a delivery address before checking out.');
      return;
    }
    if (vm.pay == 'wallet' && orders.wallet < due) {
      showErrorToast(context, 'Insufficient wallet balance for this order.');
      return;
    }
    // The scenario this is actually meant to catch: the person is trying to
    // order to their CURRENT location, but it didn't resolve to anywhere in
    // the delivery-area catalog — NOT simply "no address has valid ids at
    // all" (checking that alone would miss this case entirely, since
    // effectiveAddress silently falls back to a SAVED address with
    // perfectly valid ids, just not the place they're actually standing).
    // Was previously silent about this exact substitution — the order
    // would just go out to whichever saved address happened to be
    // selected, without ever telling the person "hey, we couldn't use
    // where you actually are."
    if (addressState.useCurrentLocation && addressState.currentLocationMatchFailed) {
      final saved = await showAddressFormSheet(context, addressState, -1);
      if (!context.mounted) return;
      if (saved == true) {
        await _placeOrder(context, cart, vm, initData);
      } else {
        showErrorToast(context, 'We couldn\'t match your current location — please add or choose a delivery address.');
      }
      return;
    }
    if (address.governorateId == null || address.areaId == null) {
      // Safety net for any other case where the resolved address itself
      // lacks a real area (shouldn't normally happen for a saved address,
      // but defends against it rather than silently placing an
      // unfulfillable order).
      final saved = await showAddressFormSheet(context, addressState, -1);
      if (!context.mounted) return;
      if (saved == true) {
        await _placeOrder(context, cart, vm, initData);
      } else {
        showErrorToast(context, 'Please add a delivery address before checking out.');
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
    showBusyOverlay(context, message: 'Placing your order…');
    try {
      final code = await orders.placeOrderRemote(
        userId: auth.userId!,
        customerName: auth.user?.name.isNotEmpty == true ? auth.user!.name : '${address.first} ${address.last}'.trim(),
        customerPhone: address.phone.isNotEmpty ? address.phone : (auth.user?.phone ?? ''),
        address: address,
        pay: vm.pay,
        totals: totals,
        coupon: initData?.appliedCouponCode ?? initData?.appliedPromo?.promoCode ?? '',
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
      if (vm.pay == 'knet') {
        final customerName = auth.user?.name.isNotEmpty == true ? auth.user!.name : address.first;
        final result = await TapPaymentService.instance.payWithKnet(
          userId: auth.userId!,
          amount: due,
          customerFirstName: customerName,
          customerEmail: auth.user?.email ?? '',
          customerPhone: address.phone.replaceAll(RegExp(r'\s'), '').replaceFirst(RegExp(r'^(\+?965)'), ''),
          orderCode: code,
        );
        if (!context.mounted) return;

        final reported = await TapPaymentService.instance.reportPaymentResponse(
          orderCode: code,
          success: result.success,
          transactionId: result.chargeId,
        );
        if (!context.mounted) return;

        if (!result.success) {
          showErrorToast(context, result.errorMessage ?? 'KNET payment failed. Your order is saved — you can try paying again from Order details.');
          return; // stay on checkout; order already exists but isn't marked paid
        }
        if (!reported) {
          showErrorToast(context, 'Payment went through, but we couldn\'t confirm it with the server. Please check Order details.');
          return;
        }
      }

      cart.clearCartRemote(auth.userId!);
      showToast(context, 'Order placed! Tracking #$code');
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => TrackScreen(orderId: code)),
        (route) => route.isFirst,
      );
    } catch (e) {
      if (context.mounted) hideBusyOverlay(context);
      if (context.mounted) showErrorToast(context, describeError(e));
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
    if (address.id == null) {
      showErrorToast(context, 'Rx checkout needs a saved address — please pick one instead of using your current location.');
      return;
    }

    showBusyOverlay(context, message: 'Submitting your prescription order…');
    try {
      final results = await orders.placeRxOrdersRemote(
        userId: auth.userId!,
        addressId: address.id!,
        payment: vm.pay,
        rxCart: cart.rxCart,
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
        showToast(context, succeeded.length > 1 ? 'Submitted ${succeeded.length} prescription orders' : 'Prescription order submitted');
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
        showErrorToast(context, failed.first.error ?? 'Couldn\'t submit your prescription order.');
      } else {
        // Mixed result — some prescriptions checked out, at least one didn't.
        showToast(context, '${succeeded.length} submitted, ${failed.length} failed — still in your Rx cart');
        Navigator.pop(context);
      }
    } catch (e) {
      if (context.mounted) hideBusyOverlay(context);
      if (context.mounted) showErrorToast(context, describeError(e));
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
    final auth = context.read<AuthState>();
    final userId = auth.userId;
    final currentCode = initData?.appliedCouponCode ?? initData?.appliedPromo?.promoCode ?? '';
    final controller = TextEditingController(text: currentCode);
    final active = (initData?.promotions ?? const <Promotion>[]).where((p) => p.isActive).toList();
    final hasApplied = (initData?.appliedCouponCode != null) || (initData?.appliedPromo != null);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
        child: StatefulBuilder(builder: (sheetContext, setSheetState) {
          bool checking = false;
          String? error;

          // Apply/remove only return {success, message, ...} — not the
          // updated cart/totals — so a successful one needs a follow-up
          // full re-fetch to actually refresh what's on screen.
          Future<void> refreshAfterChange() async {
            if (userId == null) return;
            final fresh = await AccountService.instance.checkoutInit(userId);
            onChanged(fresh);
          }

          Future<void> applyCode(String code) async {
            if (userId == null || code.isEmpty) return;
            setSheetState(() { checking = true; error = null; });
            try {
              final result = await AccountService.instance.applyPromoCode(userId, code, subtotal: subtotal);
              if (!result.success) {
                setSheetState(() { checking = false; error = result.message ?? 'That code isn\'t valid for this order.'; });
                return;
              }
              await refreshAfterChange();
              if (sheetContext.mounted) Navigator.pop(sheetContext);
            } catch (e) {
              setSheetState(() { checking = false; error = describeError(e); });
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
                setSheetState(() { checking = false; error = result.message ?? 'Couldn\'t apply that offer.'; });
                return;
              }
              await refreshAfterChange();
              if (sheetContext.mounted) Navigator.pop(sheetContext);
            } catch (e) {
              setSheetState(() { checking = false; error = describeError(e); });
            }
          }

          Future<void> remove() async {
            if (userId == null) return;
            setSheetState(() { checking = true; error = null; });
            try {
              final currentCode = initData?.appliedCouponCode ?? initData?.appliedPromo?.promoCode ?? '';
              final result = await AccountService.instance.removePromotion(userId, code: currentCode, subtotal: subtotal);
              if (!result.success) {
                setSheetState(() { checking = false; error = result.message ?? 'Couldn\'t remove that offer.'; });
                return;
              }
              await refreshAfterChange();
              if (sheetContext.mounted) Navigator.pop(sheetContext);
            } catch (e) {
              setSheetState(() { checking = false; error = describeError(e); });
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
                    const Text('Promo code', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.navy)),
                    InkWell(onTap: () => Navigator.pop(sheetContext), child: const Icon(Icons.close_rounded, size: 20, color: AppColors.muted)),
                  ]),
                  const SizedBox(height: 14),
                  TextField(
                    controller: controller,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      hintText: 'Enter code',
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
                      child: Text(checking ? 'Applying…' : 'Apply'),
                    ),
                  ),
                  if (hasApplied)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: checking ? null : remove,
                          child: const Text('Remove applied code'),
                        ),
                      ),
                    ),
                  // Real offers from checkout-init — a promotion with its
                  // own code fills the field above and applies it; one
                  // without a code (condition-based, e.g. "min 3 items")
                  // applies directly by its id via /app/promotion/apply.
                  if (active.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    const Text('Available offers', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.navy)),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 220),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: active.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final promo = active[i];
                          final desc = promo.offerType == 'percent'
                              ? '${promo.offerValue.toStringAsFixed(0)}% off'
                              : Formatters.money(promo.offerValue) + ' off';
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
                                        promo.requiresCode ? '$desc · code ${promo.promoCode}' : desc,
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
  static const _dow = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'];

  @override
  Widget build(BuildContext context) {
    final y = vm.calendarMonth.year;
    final m = vm.calendarMonth.month; // 1-12
    final today = DateTime.now();
    final todayMidnight = DateTime(today.year, today.month, today.day);
    final firstOfMonth = DateTime(y, m, 1);
    final daysInMonth = DateTime(y, m + 1, 0).day;
    final startDow = firstOfMonth.weekday % 7; // DateTime.weekday: Mon=1..Sun=7 -> Sun=0..Sat=6

    return Container(
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
              Text('${_months[m - 1]} $y', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.navy, fontSize: 14)),
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
          Row(children: [for (final d in _dow) Expanded(child: Center(child: Text(d, style: const TextStyle(fontSize: 11, color: AppColors.muted, fontWeight: FontWeight.w600))))]),
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
