import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/auth_gate.dart';
import '../../core/widgets/async_state_view.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../state/address_state.dart';
import '../../state/auth_state.dart';
import '../../state/cart_state.dart';
import '../../state/location_state.dart';
import '../../state/orders_state.dart';
import '../../viewmodels/checkout_view_model.dart';
import '../widgets/page_header.dart';
import '../widgets/toast.dart';
import 'track_screen.dart';
import '../../data/models/address.dart';
class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final addressState = context.read<AddressState>();
      addressState.loadAreas();
      final auth = context.read<AuthState>();
      if (auth.isSignedIn) addressState.loadAddresses(auth.userId!);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => CheckoutViewModel(),
      child: const _CheckoutBody(),
    );
  }
}

class _CheckoutBody extends StatelessWidget {
  const _CheckoutBody();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<CheckoutViewModel>();
    final cart = context.watch<CartState>();
    final addressState = context.watch<AddressState>();
    final totals = cart.computeTotals();
    final a = addressState.selected;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: PageHeader(title: 'Checkout'),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 120),
        children: [
          // ── .sec2 — "Shipping address" + edit icon ──
          _Sec2(
            label: 'Shipping address',
            onEdit: () => _openAddressForm(context, addressState, addressState.selectedIndex),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: GestureDetector(
              onTap: () => _openAddressPicker(context, addressState),
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
                for (var i = 0; i < CatalogRepository.deliverySlots.length; i++)
                  _PayOption(
                    icon: Icons.schedule_rounded,
                    label: '${CatalogRepository.deliverySlots[i][0]} – ${CatalogRepository.deliverySlots[i][1]}',
                    on: vm.slotTimeIndex == i,
                    onTap: () => vm.setSlotTime(i),
                  ),
              ]),
            ),
          ],

          const _HLbl(label: 'Payment method'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(children: [
              _PayOption(icon: Icons.credit_card_rounded, label: 'KNET', on: vm.pay == 'knet', onTap: () => vm.setPay('knet')),
              _PayOption(icon: Icons.credit_card_rounded, label: 'Card', on: vm.pay == 'card', onTap: () => vm.setPay('card')),
              _PayOption(icon: Icons.account_balance_wallet_rounded, label: 'Wallet · ${Formatters.money(context.watch<OrdersState>().wallet)}', on: vm.pay == 'wallet', onTap: () => vm.setPay('wallet')),
              _PayOption(icon: Icons.payments_rounded, label: 'Cash on delivery', on: vm.pay == 'cod', onTap: () => vm.setPay('cod')),
            ]),
          ),

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
            child: GestureDetector(
              onTap: () => _openPromoPicker(context, cart, vm),
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
                    child: totals.promo != null
                        ? Text.rich(TextSpan(children: [
                      TextSpan(text: '${totals.promo!.code} ', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: AppColors.ink)),
                      TextSpan(text: '· ${totals.promo!.labelEn}', style: const TextStyle(color: AppColors.ink, fontSize: 12.5)),
                    ]))
                        : const Text('Choose a coupon', style: TextStyle(color: AppColors.ink, fontSize: 12.5)),
                  ),
                  if (totals.promo != null) Text('−${Formatters.money(totals.promoDiscount)}', style: const TextStyle(color: AppColors.rose, fontWeight: FontWeight.w700, fontSize: 13)),
                  const SizedBox(width: 6),
                  const Icon(Icons.chevron_right_rounded, color: AppColors.muted, size: 16),
                ]),
              ),
            ),
          ),

          const _HLbl(label: 'Order summary'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: AppColors.shSm),
              child: Column(
                children: [
                  _SumRow(label: 'Subtotal', value: Formatters.money(totals.before)),
                  if (totals.itemDiscount > 0) _SumRow(label: 'Discount', value: '−${Formatters.money(totals.itemDiscount)}', color: AppColors.rose),
                  _SumRow(label: 'Delivery fee', value: totals.deliveryFee == 0 ? 'Free' : Formatters.money(totals.deliveryFee)),
                  if (totals.promo != null) _SumRow(label: 'Promo (${totals.promo!.code})', value: '−${Formatters.money(totals.promoDiscount)}', color: AppColors.rose),
                  Container(
                    margin: const EdgeInsets.only(top: 3),
                    padding: const EdgeInsets.only(top: 11),
                    decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line, width: 1))),
                    child: _SumRow(label: 'Total', value: Formatters.money(totals.due), bold: true),
                  ),
                ],
              ),
            ),
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
            onPressed: () => _placeOrder(context, cart, vm),
            child: Text('Place order · ${Formatters.money(totals.due)}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          ),
        ),
      ),
    );
  }

  Future<void> _placeOrder(BuildContext context, CartState cart, CheckoutViewModel vm) async {
    if (cart.cartCount == 0 && cart.rxCartCount == 0) return;

    if (!await requireLogin(context)) return;
    if (!context.mounted) return;

    final auth = context.read<AuthState>();
    final addressState = context.read<AddressState>();
    final address = addressState.selected;
    final orders = context.read<OrdersState>();
    final totals = cart.computeTotals();

    if (vm.pay == 'wallet' && orders.wallet < totals.due) {
      showErrorToast(context, 'Insufficient wallet balance for this order.');
      return;
    }
    if (address.governorateId == null || address.areaId == null) {
      showErrorToast(context, 'Please pick your area from the address form before checking out.');
      return;
    }

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
        coupon: totals.promo?.code ?? '',
      );
      // Close the overlay as soon as we have a result — BEFORE the mounted
      // check below, which used to return early and skip this entirely,
      // leaving "Placing your order…" stuck on screen forever even though
      // the order had actually gone through.
      if (context.mounted) hideBusyOverlay(context);
      if (!context.mounted) return;

      if (cart.cartTab == 'rx') {
        cart.clearRxCart();
      } else {
        cart.clearCart();
      }
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

  // ── .sh-h/.sh-b/.sh-f — address picker sheet matching openAddrPicker() ──
  void _openAddressPicker(BuildContext context, AddressState addressState) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // .sh-h
            Container(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line, width: 1))),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Shipping address', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.navy)),
                InkWell(onTap: () => Navigator.pop(context), child: const Icon(Icons.close_rounded, size: 20, color: AppColors.muted)),
              ]),
            ),
            // .sh-b — address rows styled like .payopt
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 12),
              child: Column(children: [
                for (var i = 0; i < addressState.addresses.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: GestureDetector(
                      onTap: () {
                        addressState.select(i);
                        Navigator.pop(context);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          color: addressState.selectedIndex == i ? const Color(0xFFF2FAFE) : Colors.white,
                          border: Border.all(color: addressState.selectedIndex == i ? AppColors.sky : AppColors.line, width: 1.5),
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: Row(children: [
                          const Icon(Icons.location_on_outlined, size: 20, color: AppColors.navy),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(addressState.addresses[i].title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: AppColors.navy)),
                                const SizedBox(height: 2),
                                Text(addressState.addresses[i].formatted, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                              ],
                            ),
                          ),
                          Container(
                            width: 20, height: 20,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: addressState.selectedIndex == i ? AppColors.sky : AppColors.line, width: 2),
                            ),
                            child: addressState.selectedIndex == i
                                ? Center(child: Container(width: 12, height: 12, decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.sky)))
                                : null,
                          ),
                        ]),
                      ),
                    ),
                  ),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.line, width: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      _openAddressForm(context, addressState, -1);
                    },
                    child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.add, size: 16, color: AppColors.navy),
                      SizedBox(width: 6),
                      Text('Add new address', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.navy, fontSize: 13.5)),
                    ]),
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  // ── .sh-h/.sh-b — promo picker sheet matching openPromo() ──
  void _openPromoPicker(BuildContext context, CartState cart, CheckoutViewModel vm) {
    final totals = cart.computeTotals();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line, width: 1))),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Choose a coupon', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.navy)),
                InkWell(onTap: () => Navigator.pop(context), child: const Icon(Icons.close_rounded, size: 20, color: AppColors.muted)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 16),
              child: Column(children: [
                for (final p in CatalogRepository.instance.promos)
                  _PromoOptRow(
                    code: p.code,
                    labelText: p.labelEn,
                    eligible: totals.subtotal >= p.min,
                    isCurrent: totals.promo?.code == p.code,
                    minSpendText: 'Min spend ${Formatters.money(p.min)}',
                    saveText: totals.subtotal >= p.min ? '−${Formatters.money(p.savings(totals.subtotal, totals.deliveryFee))}' : null,
                    onTap: totals.subtotal >= p.min
                        ? () {
                      cart.selectedPromoCode = p.code;
                      cart.notifyListeners();
                      Navigator.pop(context);
                    }
                        : null,
                  ),
                _PromoOptRow(
                  code: 'No coupon',
                  labelText: null,
                  eligible: true,
                  isCurrent: cart.selectedPromoCode == '__none__',
                  minSpendText: null,
                  saveText: null,
                  onTap: () {
                    cart.selectedPromoCode = '__none__';
                    cart.notifyListeners();
                    Navigator.pop(context);
                  },
                ),
              ]),
            ),
          ],
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

class _PromoOptRow extends StatelessWidget {
  final String code;
  final String? labelText;
  final bool eligible;
  final bool isCurrent;
  final String? minSpendText;
  final String? saveText;
  final VoidCallback? onTap;
  const _PromoOptRow({
    required this.code,
    required this.labelText,
    required this.eligible,
    required this.isCurrent,
    required this.minSpendText,
    required this.saveText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: eligible ? 1 : 0.5,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: isCurrent ? const Color(0xFFF2FAFE) : Colors.white,
              border: Border.all(color: isCurrent ? AppColors.sky : AppColors.line, width: 1.5),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(code, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: AppColors.navy)),
                    if (labelText != null) ...[
                      const SizedBox(height: 2),
                      Text(labelText!, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                    ],
                    if (!eligible && minSpendText != null) ...[
                      const SizedBox(height: 2),
                      Text(minSpendText!, style: const TextStyle(fontSize: 10, color: AppColors.warn)),
                    ],
                  ],
                ),
              ),
              if (saveText != null) ...[
                Text(saveText!, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.rose)),
                const SizedBox(width: 9),
              ],
              Container(
                width: 20, height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: isCurrent ? AppColors.sky : AppColors.line, width: 2),
                ),
                child: isCurrent
                    ? Center(child: Container(width: 12, height: 12, decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.sky)))
                    : null,
              ),
            ]),
          ),
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

// ── .sh-h/.afield/.arow/.sh-f — address form sheet matching openAddrForm() ──
void _openAddressForm(BuildContext context, AddressState addressState, int index) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (_) => _AddressFormSheet(addressState: addressState, index: index),
  );
}

class _AddressFormSheet extends StatefulWidget {
  final AddressState addressState;
  final int index; // -1 = add new
  const _AddressFormSheet({required this.addressState, required this.index});

  @override
  State<_AddressFormSheet> createState() => _AddressFormSheetState();
}

class _AddressFormSheetState extends State<_AddressFormSheet> {
  static const titles = ['Home/Apartment', 'Work', 'Other'];

  late String _title;
  int? _govId;
  int? _areaId;
  late final TextEditingController _first;
  late final TextEditingController _last;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  late final TextEditingController _alt;
  late final TextEditingController _block;
  late final TextEditingController _street;
  late final TextEditingController _building;
  late final TextEditingController _apt;
  late final TextEditingController _floor;
  bool _saving = false;

  bool get _isEdit => widget.index >= 0;

  @override
  void initState() {
    super.initState();
    final existing = _isEdit ? widget.addressState.addresses[widget.index] : null;
    _title = titles.contains(existing?.title) ? existing!.title : titles.first;
    _govId = existing?.governorateId;
    _areaId = existing?.areaId;
    _first = TextEditingController(text: existing?.first ?? '');
    _last = TextEditingController(text: existing?.last ?? '');
    _email = TextEditingController(text: existing?.email ?? '');
    _phone = TextEditingController(text: existing?.phone ?? '');
    _alt = TextEditingController(text: existing?.alt ?? '');
    _block = TextEditingController(text: existing?.block ?? '');
    _street = TextEditingController(text: existing?.street ?? '');
    _building = TextEditingController(text: existing?.building ?? '');
    _apt = TextEditingController(text: existing?.apt ?? '');
    _floor = TextEditingController(text: existing?.floor ?? '');
    if (widget.addressState.areaCatalog.governorates.isEmpty) {
      widget.addressState.loadAreas().then((_) => _autofillFromLocation());
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _autofillFromLocation());
    }
  }

  /// New addresses only — same best-effort name match against `/areas` as
  /// the standalone address form screen.
  void _autofillFromLocation() {
    if (!mounted || _isEdit) return;
    final location = context.read<LocationState>();
    if (!location.isReady) return;

    String norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    final govGuess = location.governorate;
    final areaGuess = location.area;
    if (govGuess == null && areaGuess == null) return;

    for (final g in widget.addressState.areaCatalog.governorates) {
      final govMatches = govGuess != null && (norm(g.name).contains(norm(govGuess)) || norm(govGuess).contains(norm(g.name)));
      for (final a in g.areas) {
        final areaMatches = areaGuess != null && (norm(a.name).contains(norm(areaGuess)) || norm(areaGuess).contains(norm(a.name)));
        if (areaMatches || (govMatches && areaGuess == null)) {
          setState(() {
            _govId = g.id;
            _areaId = a.id;
            if (location.street != null && location.street!.isNotEmpty && _street.text.isEmpty) _street.text = location.street!;
          });
          return;
        }
      }
    }
  }

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _email.dispose();
    _phone.dispose();
    _alt.dispose();
    _block.dispose();
    _street.dispose();
    _building.dispose();
    _apt.dispose();
    _floor.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_govId == null || _areaId == null) {
      showErrorToast(context, 'Please choose your governorate and area.');
      return;
    }
    if (!await requireLogin(context)) return;
    if (!mounted) return;

    final address = Address(
      id: _isEdit ? widget.addressState.addresses[widget.index].id : null,
      title: _title,
      first: _first.text,
      last: _last.text,
      email: _email.text,
      phone: _phone.text,
      alt: _alt.text,
      governorateId: _govId,
      areaId: _areaId,
      block: _block.text,
      street: _street.text,
      building: _building.text,
      apt: _apt.text,
      floor: _floor.text,
    );

    setState(() => _saving = true);
    try {
      final auth = context.read<AuthState>();
      await widget.addressState.saveRemote(auth.userId!, address, index: _isEdit ? widget.index : null);
      if (!mounted) return;
      Navigator.pop(context);
      showToast(context, 'Address saved');
    } catch (e) {
      if (!mounted) return;
      showErrorToast(context, describeError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // .sh-h
            Container(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line, width: 1))),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(_isEdit ? 'Edit address' : 'Add new address', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.navy)),
                InkWell(onTap: () => Navigator.pop(context), child: const Icon(Icons.close_rounded, size: 20, color: AppColors.muted)),
              ]),
            ),
            // .sh-b — scrollable field list
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 12),
                child: Column(children: [
                  _AField(
                    label: 'Title',
                    required: true,
                    child: _ADropdown(value: _title, options: titles, onChanged: (v) => setState(() => _title = v)),
                  ),
                  _ARow(children: [
                    _AField(label: 'First name', required: true, child: _AInput(controller: _first)),
                    _AField(label: 'Last name', required: true, child: _AInput(controller: _last)),
                  ]),
                  _AField(label: 'Email', required: true, child: _AInput(controller: _email, keyboard: TextInputType.emailAddress)),
                  _ARow(children: [
                    SizedBox(
                      width: 64,
                      child: _AField(label: 'Phone', required: true, child: _AInput(controller: TextEditingController(text: '+965'), readOnly: true)),
                    ),
                    Expanded(
                      child: _AField(label: '\u00A0', required: false, child: _AInput(controller: _phone, hint: 'Enter phone number', keyboard: TextInputType.phone)),
                    ),
                  ]),
                  _ARow(children: [
                    SizedBox(
                      width: 64,
                      child: _AField(label: 'Alt. phone', required: false, child: _AInput(controller: TextEditingController(text: '+965'), readOnly: true)),
                    ),
                    Expanded(
                      child: _AField(label: '\u00A0', required: false, child: _AInput(controller: _alt, keyboard: TextInputType.phone)),
                    ),
                  ]),
                  _AField(
                    label: 'Governorate',
                    required: true,
                    child: _AreaIdDropdown(
                      value: _govId,
                      hint: 'Select governorate',
                      options: [for (final g in widget.addressState.areaCatalog.governorates) (id: g.id, label: g.name)],
                      onChanged: (v) => setState(() { _govId = v; _areaId = null; }),
                    ),
                  ),
                  _AField(
                    label: 'Area',
                    required: true,
                    child: _AreaIdDropdown(
                      value: _areaId,
                      hint: 'Select area',
                      options: [
                        for (final g in widget.addressState.areaCatalog.governorates)
                          if (g.id == _govId)
                            for (final a in g.areas) (id: a.id, label: a.name),
                      ],
                      onChanged: (v) => setState(() => _areaId = v),
                    ),
                  ),
                  _ARow(children: [
                    _AField(label: 'Block', required: true, child: _AInput(controller: _block)),
                    _AField(label: 'Street name', required: true, child: _AInput(controller: _street)),
                  ]),
                  _ARow(children: [
                    _AField(label: 'Building', required: true, child: _AInput(controller: _building)),
                    _AField(label: 'Apartment', required: false, child: _AInput(controller: _apt)),
                  ]),
                  _AField(label: 'Floor', required: false, child: _AInput(controller: _floor)),
                ]),
              ),
            ),
            // .sh-f
            Container(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line, width: 1))),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.navy,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                    elevation: 0,
                  ),
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                      : Text(_isEdit ? 'Save address' : 'Add address', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── .afield — label + input/dropdown wrapper ──
class _AField extends StatelessWidget {
  final String label;
  final bool required;
  final Widget child;
  const _AField({required this.label, required this.required, required this.child});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(required ? '$label *' : label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.navy)),
        const SizedBox(height: 5),
        child,
      ]),
    );
  }
}

// ── .arow — two fields side by side with 10px gap ──
class _ARow extends StatelessWidget {
  final List<Widget> children;
  const _ARow({required this.children});
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (children[i] is _AField) Expanded(child: children[i]) else children[i],
          if (i != children.length - 1) const SizedBox(width: 10),
        ],
      ],
    );
  }
}

// ── .afield input ──
class _AInput extends StatelessWidget {
  final TextEditingController controller;
  final String? hint;
  final bool readOnly;
  final TextInputType? keyboard;
  const _AInput({required this.controller, this.hint, this.readOnly = false, this.keyboard});
  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      readOnly: readOnly,
      keyboardType: keyboard,
      textAlign: readOnly ? TextAlign.center : TextAlign.start,
      style: TextStyle(fontSize: 13.5, color: readOnly ? AppColors.muted : AppColors.ink),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: readOnly ? AppColors.bg : Colors.white,
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.muted, fontSize: 13.5),
        contentPadding: const EdgeInsets.all(11),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.line, width: 1.5)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.line, width: 1.5)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.sky, width: 1.5)),
      ),
    );
  }
}

// ── governorate/area select (id-based, from the /areas API) ──
class _AreaIdDropdown extends StatelessWidget {
  final int? value;
  final String? hint;
  final List<({int id, String label})> options;
  final ValueChanged<int?> onChanged;
  const _AreaIdDropdown({required this.value, this.hint, required this.options, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final validValue = options.any((o) => o.id == value) ? value : null;
    return DropdownButtonFormField<int>(
      value: validValue,
      hint: hint != null ? Text(hint!, style: const TextStyle(color: AppColors.muted, fontSize: 13.5)) : null,
      items: options.map((o) => DropdownMenuItem(value: o.id, child: Text(o.label, style: const TextStyle(fontSize: 13.5, color: AppColors.ink)))).toList(),
      onChanged: options.isEmpty ? null : onChanged,
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 11),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.line, width: 1.5)),
      ),
    );
  }
}

// ── .afield select ──
class _ADropdown extends StatelessWidget {
  final String? value;
  final String? hint;
  final List<String> options;
  final ValueChanged<String> onChanged;
  const _ADropdown({required this.value, this.hint, required this.options, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      value: value != null && options.contains(value) ? value : null,
      hint: hint != null ? Text(hint!, style: const TextStyle(color: AppColors.muted, fontSize: 13.5)) : null,
      items: options.map((o) => DropdownMenuItem(value: o, child: Text(o, style: const TextStyle(fontSize: 13.5, color: AppColors.ink)))).toList(),
      onChanged: (v) { if (v != null) onChanged(v); },
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 11),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.line, width: 1.5)),
      ),
    );
  }
}