import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/cart_line.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../state/cart_state.dart';
import '../widgets/page_header.dart';

class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartState>();
    final store = cart.activeStore;
    final groups = cart.groupsFor(store);
    final keys = groups.keys.toList();
    final isRx = cart.cartTab == 'rx';

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: PageHeader(title: 'Cart'),
      body: Column(
        children: [
          // ── .carttabs — equal-width pills ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Row(
              children: [
                Expanded(child: _Tab(label: 'My Cart (${cart.cartCount})', on: cart.cartTab == 'my', onTap: () => cart.setCartTab('my'))),
                const SizedBox(width: 8),
                Expanded(child: _Tab(label: 'Rx Cart (${cart.rxCartCount})', on: cart.cartTab == 'rx', onTap: () => cart.setCartTab('rx'))),
              ],
            ),
          ),
          if (keys.isEmpty)
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
                      Text(isRx ? 'My Rx' : 'Your cart is empty', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.navy)),
                      const SizedBox(height: 6),
                      Text(
                        isRx ? 'Prescriptions your doctor sends appear in My Rx.' : 'Add products to get started.',
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
                        child: Text(isRx ? 'My Rx →' : 'Start shopping', style: const TextStyle(fontWeight: FontWeight.w700)),
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
                  if (keys.length > 1)
                  // ── .togcard — light-blue tinted, no shadow ──
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(color: const Color(0xFFE7F7FB), borderRadius: BorderRadius.circular(13)),
                      child: Row(children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text('Deliver together', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.navy)),
                              SizedBox(height: 2),
                              Text('One delivery fee for all pharmacies', style: TextStyle(fontSize: 11, color: AppColors.muted)),
                            ],
                          ),
                        ),
                        Switch(value: cart.deliverTogether, activeColor: AppColors.sky, onChanged: (_) => cart.toggleDeliverTogether()),
                      ]),
                    ),
                  for (final k in keys) _PharmacyGroup(pharmacy: k, items: groups[k]!, isRx: isRx, cart: cart),
                ],
              ),
            ),
        ],
      ),
      bottomNavigationBar: keys.isEmpty
          ? null
          : Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
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
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            onPressed: () => Navigator.pushNamed(context, Routes.checkout),
            child: Text('Checkout · ${Formatters.money(cart.computeTotals().total)}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          ),
        ),
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

class _PharmacyGroup extends StatelessWidget {
  final String pharmacy;
  final List<CartLine> items;
  final bool isRx;
  final CartState cart;
  const _PharmacyGroup({required this.pharmacy, required this.items, required this.isRx, required this.cart});

  @override
  Widget build(BuildContext context) {
    final sub = cart.groupSubtotal(items);
    final fee = cart.pharmacyFee(sub);
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
              Text('🏪 $pharmacy', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.navy, fontSize: 12.5)),
              Text(
                cart.deliverTogether ? '' : (fee == 0 ? '🚚 Free' : Formatters.money(fee)),
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.ok),
              ),
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
    final product = line.productId != null ? CatalogRepository.instance.findProduct(line.productId!) : null;
    final name = line.nameOverride ?? product?.nameEn ?? 'Item';
    final emoji = line.emojiOverride ?? product?.emoji ?? '💊';
    final isBogo = product?.isBogo ?? false;
    final freeUnits = isBogo ? line.qty ~/ 2 : 0;
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
              child: Text(emoji, style: const TextStyle(fontSize: 26)),
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
                    (product?.brand ?? (line.rxId ?? 'Rx')).toUpperCase(),
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
                  if (isBogo)
                    Container(
                      margin: const EdgeInsets.only(top: 5),
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(color: const Color(0xFFE4F6EF), borderRadius: BorderRadius.circular(12)),
                      child: Text(
                        freeUnits > 0 ? '🎁 1+1 · $freeUnits free' : '🎁 1+1 · add 1 more = free',
                        style: const TextStyle(fontSize: 10.5, color: AppColors.ok, fontWeight: FontWeight.w700),
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
                      _QtyButton(icon: Icons.remove, onTap: () => cart.setQty(line.key, -1, rx: isRx)),
                      SizedBox(
                        width: 32,
                        child: Text('${line.qty}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      ),
                      _QtyButton(icon: Icons.add, onTap: () => cart.setQty(line.key, 1, rx: isRx)),
                    ]),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () => cart.removeLine(line.key, rx: isRx),
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
  final VoidCallback onTap;
  const _QtyButton({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(width: 28, height: 28, child: Icon(icon, size: 14, color: AppColors.navy)),
    );
  }
}