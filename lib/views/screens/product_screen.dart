import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/async_state_view.dart';
import '../../data/models/seller.dart';
import '../../state/cart_state.dart';
import '../../viewmodels/product_view_model.dart';
import '../widgets/product_image.dart';
import '../widgets/toast.dart';

class ProductScreen extends StatelessWidget {
  final int productId;
  final String? lockedToSeller;
  const ProductScreen({super.key, required this.productId, this.lockedToSeller});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ProductViewModel(productId: productId, lockedToSeller: lockedToSeller),
      child: const _ProductBody(),
    );
  }
}

class _ProductBody extends StatelessWidget {
  const _ProductBody();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ProductViewModel>();
    final cart = context.watch<CartState>();
    final p = vm.product;
    final sel = vm.selectedSeller;
    final wished = cart.isWished(p.id);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: () => cart.toggleWishRemote(context, p),
            icon: Icon(wished ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: wished ? AppColors.rose : AppColors.navy),
          ),
          IconButton(
            onPressed: () => Share.share(
              '${p.nameEn}\n${Formatters.money(sel.price)} on WASFA',
              subject: p.nameEn,
            ),
            icon: const Icon(Icons.ios_share_rounded, size: 20, color: AppColors.navy),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: vm.isLoading
          ? const LoadingView(message: 'Loading product…')
          : (vm.error != null && p.sellers.isEmpty)
              ? ErrorRetryView(message: vm.error!, onRetry: vm.load)
              : ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (vm.error != null) InlineErrorBanner(message: vm.error!, onRetry: vm.load),
          // .pdp-hero — height:220px, blush bg, 92px glyph
          ProductImage(product: p, height: 220, emojiSize: 92),
          Padding(
            // .pdp-body — padding:16px 16px 24px
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.brand.toUpperCase(), style: const TextStyle(color: AppColors.sky, fontWeight: FontWeight.w700, fontSize: 11)),
                const SizedBox(height: 4),
                Text(p.nameEn, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.navy)),
                const SizedBox(height: 8),
                // .pdp-rate — gap:7px, font-size:12.5px, color:muted, margin-bottom:13px
                Padding(
                  padding: const EdgeInsets.only(bottom: 13),
                  child: Row(children: [
                    const Icon(Icons.star_rounded, color: AppColors.star, size: 15),
                    const SizedBox(width: 3),
                    Text('${p.rating}', style: const TextStyle(color: AppColors.star, fontWeight: FontWeight.w700, fontSize: 12.5)),
                    Text(
                      '  ·  ${p.reviews} reviews${p.scientificName.isNotEmpty ? '  ·  ${p.scientificName}' : ''}',
                      style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                    ),
                  ]),
                ),
                // .pdp-price — gap:9px baseline, margin-bottom:6px
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                    Text(Formatters.money(sel.price), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.navy)),
                    if (sel.was != null) ...[
                      const SizedBox(width: 9),
                      Text(Formatters.money(sel.was!), style: const TextStyle(color: AppColors.muted, decoration: TextDecoration.lineThrough, fontSize: 13)),
                      const SizedBox(width: 9),
                      Text('${sel.discountPercent}%', style: const TextStyle(color: AppColors.rose, fontWeight: FontWeight.w700, fontSize: 13)),
                    ],
                  ]),
                ),
                const SizedBox(height: 9),
                // .attrs — 2-col grid, gap:9px, margin:15px 0
                _AttrGrid(sel: sel),
                const SizedBox(height: 6),
                // .h-lbl — 14.5px/700/navy
                const Text('Key benefits', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.navy)),
                const SizedBox(height: 10),
                // .benef — gap:7px, margin:4px 0 18px
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 18),
                  child: Wrap(spacing: 7, runSpacing: 7, children: [
                    for (final b in [p.category, p.concern, p.form].where((b) => b.isNotEmpty)) _BenefitTag(text: b),
                  ]),
                ),
                Text(
                  vm.sellers.length > 1 ? '🏪 Choose your pharmacy (${vm.sellers.length})' : '🏪 Sold by ${sel.name}',
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.navy),
                ),
                const SizedBox(height: 10),
                if (vm.sellers.length > 1)
                  for (final s in vm.sellers)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _SellerOption(
                        seller: s,
                        selected: s.name == sel.name,
                        onTap: () => vm.selectSeller(s.name),
                      ),
                    )
                else
                  _LockedSeller(seller: sel),
                const SizedBox(height: 8),
                // .acc — bordered accordion box with +/- indicator (not a chevron)
                _AccordionBox(
                  title: 'Description',
                  content: '${p.nameEn} — ${p.scientificName}. Genuine MoH-approved product, stored and dispensed per guidelines.',
                  initiallyOpen: true,
                ),
                _AccordionBox(
                  title: 'How to use',
                  content: 'Follow your doctor or pharmacist instructions. Do not exceed the recommended dose.',
                ),
                _AccordionBox(
                  title: 'Ingredients',
                  content: '${p.scientificName}. See pack for full ingredient list.',
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Customer reviews', style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.navy)),
                ),
                const SizedBox(height: 10),
                // .revsum — gap:18px, margin:6px 0 14px
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${p.rating}', style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w700, color: AppColors.navy, height: 1)),
                      Text('${p.reviews} reviews', style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                    ]),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        children: [5, 4, 3, 2, 1].asMap().entries.map((e) {
                          final pct = [70, 20, 7, 2, 1][e.key];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(children: [
                              SizedBox(width: 22, child: Text('${e.value}★', style: const TextStyle(fontSize: 10, color: AppColors.muted))),
                              const SizedBox(width: 7),
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(value: pct / 100, minHeight: 6, backgroundColor: AppColors.cloud, color: AppColors.star),
                                ),
                              ),
                            ]),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => showToast(context, 'Coming soon'),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.white,
                      side: const BorderSide(color: AppColors.navy, width: 1.5),
                      foregroundColor: AppColors.navy,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Write a review', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(height: 18),
                const Text('Have a question?', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.navy)),
                const SizedBox(height: 10),
                // .qabox — bg:var(--bg), radius:13, padding:16, text-align:center
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(13)),
                  child: Column(
                    children: [
                      const Text('Have a question about this product?', textAlign: TextAlign.center, style: TextStyle(color: AppColors.ink, fontSize: 13.5)),
                      const SizedBox(height: 12),
                      // .btn-ghost — bg:var(--bg)... but sits inside a --bg box, so give
                      // it white so it's visually distinct, matching the on-screen look.
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: () => showToast(context, 'Coming soon'),
                          style: TextButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            foregroundColor: AppColors.navy,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                          ),
                          child: const Text('Ask a question', style: TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
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
              backgroundColor: sel.stock ? AppColors.sky : AppColors.line,
              disabledBackgroundColor: AppColors.line,
              foregroundColor: sel.stock ? Colors.white : AppColors.muted,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            onPressed: !sel.stock
                ? null
                : () {
                    cart.addToCart(p, seller: sel.name, price: sel.price, was: sel.was, apiProductId: sel.productId);
                    showToast(
                      context,
                      'Added to cart',
                      actionLabel: 'View',
                      onAction: () => Navigator.pushNamed(context, Routes.cart),
                    );
                  },
            child: Text(
              sel.stock ? 'Add to cart · ${Formatters.money(sel.price)}' : 'Out of stock',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
          ),
        ),
      ),
    );
  }
}

/// .attrs — 2-column grid of pale boxes: green icon + bold navy label.
class _AttrGrid extends StatelessWidget {
  final Seller sel;
  const _AttrGrid({required this.sel});

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.check_circle_rounded, 'Genuine product'),
      (Icons.verified_rounded, 'MoH approved'),
      (Icons.location_on_rounded, sel.stock ? 'In stock' : 'Out of stock'),
      (Icons.local_shipping_rounded, 'Fast delivery'),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 9,
      crossAxisSpacing: 9,
      childAspectRatio: 2.8,
      children: [for (final it in items) _Attr(icon: it.$1, label: it.$2)],
    );
  }
}

class _Attr extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Attr({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(11)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: AppColors.ok),
        const SizedBox(width: 9),
        Expanded(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.navy)),
        ),
      ]),
    );
  }
}

/// .benef .b — pale-blue pill, navy/600/11.5, fully rounded.
class _BenefitTag extends StatelessWidget {
  final String text;
  const _BenefitTag({required this.text});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(color: AppColors.benefitPillBg, borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.navy)),
    );
  }
}

/// .srow.on style="cursor:default" — non-interactive, always the selected look.
class _LockedSeller extends StatelessWidget {
  final Seller seller;
  const _LockedSeller({required this.seller});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.skySelectedBg,
        border: Border.all(color: AppColors.sky, width: 1.5),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(seller.name, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.ink)),
                const SizedBox(height: 3),
                Text('🚚 ${seller.eta}   ${seller.stock ? "🟢 In stock" : "⚪ Out of stock"}', style: const TextStyle(fontSize: 11, color: AppColors.muted)),
              ],
            ),
          ),
          Text(Formatters.money(seller.price), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.navy)),
        ],
      ),
    );
  }
}

/// A selectable pharmacy row for the PDP price-comparison list. Highlights
/// the chosen seller (sky border/tint + filled radio) and stays tappable so
/// the person can compare prices and pick which pharmacy to buy from.
class _SellerOption extends StatelessWidget {
  final Seller seller;
  final bool selected;
  final VoidCallback onTap;
  const _SellerOption({required this.seller, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(13),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? AppColors.skySelectedBg : Colors.white,
          border: Border.all(color: selected ? AppColors.sky : AppColors.line, width: 1.5),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
              size: 20,
              color: selected ? AppColors.sky : AppColors.muted,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(seller.name, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.ink)),
                  const SizedBox(height: 3),
                  Text('🚚 ${seller.eta}   ${seller.stock ? "🟢 In stock" : "⚪ Out of stock"}', style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(Formatters.money(seller.price), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.navy)),
                if (seller.was != null)
                  Text(Formatters.money(seller.was!), style: const TextStyle(fontSize: 11, color: AppColors.muted, decoration: TextDecoration.lineThrough)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// .acc — bordered box (border:line, radius:12), summary row with a
/// "+"/"−" text indicator (never a chevron), content padded 0/14/14.
class _AccordionBox extends StatefulWidget {
  final String title;
  final String content;
  final bool initiallyOpen;
  const _AccordionBox({required this.title, required this.content, this.initiallyOpen = false});

  @override
  State<_AccordionBox> createState() => _AccordionBoxState();
}

class _AccordionBoxState extends State<_AccordionBox> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.line, width: 1),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(widget.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.navy)),
                  ),
                  Text(_open ? '−' : '+', style: const TextStyle(fontSize: 20, color: AppColors.sky, fontWeight: FontWeight.w400)),
                ],
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Text(widget.content, style: const TextStyle(color: AppColors.muted, fontSize: 13, height: 1.6)),
            ),
        ],
      ),
    );
  }
}
