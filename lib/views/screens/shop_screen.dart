import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/async_state_view.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../state/cart_state.dart';
import '../../viewmodels/shop_view_model.dart';
import '../widgets/page_header.dart';
import '../widgets/product_card.dart';
import '../widgets/toast.dart';

class ShopScreen extends StatelessWidget {
  final ShopFilter? initialFilter;
  const ShopScreen({super.key, this.initialFilter});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ShopViewModel(initial: initialFilter),
      child: const _ShopBody(),
    );
  }
}

class _ShopBody extends StatelessWidget {
  const _ShopBody();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ShopViewModel>();
    final cart = context.watch<CartState>();
    final results = vm.results;
    final inPharmacy = vm.pharmacy != null;

    return Scaffold(
      backgroundColor: AppColors.bg,
      // ── .phead only shows when inside a single pharmacy storefront ──
      appBar: inPharmacy ? PageHeader(title: vm.pharmacy!) : null,
      body: SafeArea(
        top: !inPharmacy, // manual top padding only when there's no PageHeader
        child: Column(
          children: [
            // ── .appbar — one white block containing both .ab-top AND .search ──
            if (!inPharmacy) _TopAppBar(cartCount: cart.cartCount, onQueryChanged: vm.setQuery),

            // ── .cats2 — category pills ──
            Padding(
              padding: const EdgeInsets.only(top: 10), // ← margin-top equivalent
              child: SizedBox(
                height: 38,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 2),
                  children: [
                    _Chip(label: 'All', on: vm.category == null, onTap: () => vm.setCategory(null)),
                    for (final c in CatalogRepository.productCategories.where((c) => c['cat'] != 'Health'))
                      _Chip(label: c['cat']!, on: vm.category == c['cat'], onTap: () => vm.setCategory(c['cat'])),
                  ],
                ),
              ),
            ),
            // ── .cats2 — concern pills (small) ──
            Padding(
              padding: const EdgeInsets.only(top: 10), // ← margin-top equivalent
              child: SizedBox(
                height: 38,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 2),
                  children: [
                    for (final c in CatalogRepository.concerns)
                      _Chip(label: c['en']!, small: true, on: vm.concern == c['k'], onTap: () => vm.setConcern(c['k'])),
                  ],
                ),
              ),
            ),

            // ── .sortbar — sticky gray bar with bordered buttons + vtog ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: const BoxDecoration(
                color: AppColors.bg,
                border: Border(bottom: BorderSide(color: AppColors.line, width: 1)),
              ),
              child: Row(children: [
                _SortBarButton(icon: Icons.swap_vert_rounded, label: 'Sort', onTap: () => _openSort(context, vm)),
                const SizedBox(width: 8),
                Stack(clipBehavior: Clip.none, children: [
                  _SortBarButton(icon: Icons.filter_list_rounded, label: 'Filter', onTap: () => _openFilter(context, vm)),
                  if (vm.hasActiveFilters)
                    Positioned(
                      right: -2, top: -2,
                      child: Container(width: 7, height: 7, decoration: const BoxDecoration(color: AppColors.rose, shape: BoxShape.circle)),
                    ),
                ]),
                const Spacer(),
                // ── .vtog — grouped grid/list toggle ──
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppColors.line, width: 1), borderRadius: BorderRadius.circular(9)),
                  child: Row(children: [
                    _VtogButton(icon: Icons.grid_view_rounded, on: vm.view == 'grid', onTap: () => vm.setView('grid')),
                    _VtogButton(icon: Icons.view_list_rounded, on: vm.view == 'list', onTap: () => vm.setView('list')),
                  ]),
                ),
              ]),
            ),

            // ── .reshead ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 11, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  vm.isLoading ? 'Loading products…' : '${results.length} products',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            if (vm.error != null && results.isNotEmpty)
              InlineErrorBanner(message: vm.error!, onRetry: vm.load),

            Expanded(
              child: vm.isLoading && results.isEmpty
                  ? const LoadingView(message: 'Loading products…')
                  : (vm.error != null && results.isEmpty)
                  ? ErrorRetryView(message: vm.error!, onRetry: vm.load)
                  : results.isEmpty
                  ? const Center(child: Text('No results', style: TextStyle(color: AppColors.muted)))
                  : vm.view == 'grid'
              // ── .pgrid ──
                  ? GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                // Lower ratio = taller tiles. The card's content is a stack of
                // mostly fixed-height sections (110px image + brand + 2-line name
                // + rating + price + button); at .58 that stack was ~17px taller
                // than the tile on typical phones, causing "BOTTOM OVERFLOWED BY
                // 17 PIXELS". .52 gives the extra height a 2-line name needs.
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: .56),
                itemCount: results.length,
                itemBuilder: (context, i) => ProductCard(
                  product: results[i],
                  onTap: () => Navigator.pushNamed(context, Routes.product, arguments: results[i].id),
                ),
              )
              // ── .plist / .plc ──
                  : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                itemCount: results.length,
                separatorBuilder: (_, __) => const SizedBox(height: 11),
                itemBuilder: (context, i) => _ProductListCard(
                  product: results[i],
                  cart: cart,
                  onTap: () => Navigator.pushNamed(context, Routes.product, arguments: results[i].id),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openSort(BuildContext context, ShopViewModel vm) {
    const opts = [['pop', 'Popularity'], ['low', 'Price: low to high'], ['high', 'Price: high to low'], ['rated', 'Top rated']];
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
                const Text('Sort by', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.navy)),
                InkWell(onTap: () => Navigator.pop(context), child: const Icon(Icons.close_rounded, size: 20, color: AppColors.muted)),
              ]),
            ),
            for (final o in opts)
              InkWell(
                onTap: () { vm.setSort(o[0]); Navigator.pop(context); },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line, width: 1))),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text(o[1], style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.ink)),
                    if (vm.sort == o[0]) const Icon(Icons.check_rounded, color: AppColors.navy, size: 18),
                  ]),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _openFilter(BuildContext context, ShopViewModel vm) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line, width: 1))),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text('Filter', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.navy)),
                    InkWell(onTap: () => Navigator.pop(context), child: const Icon(Icons.close_rounded, size: 20, color: AppColors.muted)),
                  ]),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Pharmacy', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.muted, fontSize: 12.5)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8, runSpacing: 8,
                          children: [
                            _Chip(
                              label: 'All stores', small: true, on: vm.pharmacy == null,
                              onTap: () { vm.setPharmacy(null); setSheetState(() {}); },
                            ),
                            for (final nm in vm.sellerNames)
                              _Chip(
                                label: nm, small: true, on: vm.pharmacy == nm,
                                onTap: () { vm.setPharmacy(nm); setSheetState(() {}); },
                              ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        const Text('Brand', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.muted, fontSize: 12.5)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8, runSpacing: 8,
                          children: [
                            for (final b in vm.realBrands)
                              _Chip(
                                label: b, small: true, on: vm.brands.contains(b),
                                onTap: () { vm.toggleBrand(b); setSheetState(() {}); },
                              ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        const Text('Categories', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.muted, fontSize: 12.5)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8, runSpacing: 8,
                          children: [
                            _Chip(
                              label: 'All categories', small: true, on: vm.category == null,
                              onTap: () { vm.toggleFilterCategory(null); setSheetState(() {}); },
                            ),
                            for (final c in CatalogRepository.productCategories.where((c) => c['cat'] != 'Health'))
                              _Chip(
                                label: c['cat']!, small: true, on: vm.category == c['cat'],
                                onTap: () { vm.toggleFilterCategory(c['cat']); setSheetState(() {}); },
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _FilterRow(
                          label: '🏷️ Offers only',
                          value: vm.offersOnly,
                          onChanged: (_) { vm.toggleOffersOnly(); setSheetState(() {}); },
                        ),
                        _FilterRow(
                          label: 'In stock only',
                          value: vm.inStock,
                          onChanged: (_) { vm.toggleInStock(); setSheetState(() {}); },
                        ),
                      ]),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                  decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line, width: 1))),
                  child: Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.navy, width: 1.5),
                          foregroundColor: AppColors.navy,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                        ),
                        onPressed: () { vm.clearFilters(); setSheetState(() {}); },
                        child: const Text('Clear all', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.navy,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                          elevation: 0,
                        ),
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Apply', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── .appbar — location row + search bar, both inside one white block ──
class _TopAppBar extends StatelessWidget {
  final int cartCount;
  final ValueChanged<String> onQueryChanged;
  const _TopAppBar({required this.cartCount, required this.onQueryChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      color: Colors.white,
      child: Column(children: [
        // .ab-top
        Row(children: [
          Expanded(
            child: GestureDetector(
              onTap: () {}, // hook up location picker if you have one
              child: Row(children: [
                Container(
                  width: 34, height: 34,
                  decoration: BoxDecoration(color: AppColors.blush, borderRadius: BorderRadius.circular(11)),
                  alignment: Alignment.center,
                  child: const Icon(Icons.location_on_rounded, size: 18, color: AppColors.rose),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Deliver to Home', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.navy, height: 1.15)),
                      Row(children: [
                        const Expanded(
                          child: Text('Salmiya · Block 10, St 5', maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11, color: AppColors.muted)),
                        ),
                        const Icon(Icons.keyboard_arrow_down_rounded, size: 14, color: AppColors.muted),
                      ]),
                    ],
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(width: 10),
          // .ab-act
          Row(children: [
            GestureDetector(
              onTap: () => Navigator.pushNamed(context, Routes.myRx),
              child: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(10)),
                alignment: Alignment.center,
                child: const Icon(Icons.description_outlined, size: 18, color: AppColors.navy),
              ),
            ),
            const SizedBox(width: 7),
            GestureDetector(
              onTap: () => Navigator.pushNamed(context, Routes.cart),
              child: Stack(clipBehavior: Clip.none, children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(10)),
                  alignment: Alignment.center,
                  child: const Icon(Icons.shopping_bag_outlined, size: 18, color: AppColors.navy),
                ),
                if (cartCount > 0)
                  Positioned(
                    top: -4, right: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                      decoration: BoxDecoration(color: AppColors.rose, borderRadius: BorderRadius.circular(9)),
                      alignment: Alignment.center,
                      child: Text('$cartCount', style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w700)),
                    ),
                  ),
              ]),
            ),
          ]),
        ]),

        // .search — margin-top 12, inside the SAME white container
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            const Icon(Icons.search_rounded, size: 18, color: AppColors.muted),
            const SizedBox(width: 9),
            Expanded(
              child: TextField(
                onChanged: onQueryChanged,
                style: const TextStyle(fontSize: 14, color: AppColors.ink),
                cursorColor: AppColors.navy,
                decoration: const InputDecoration(
                  isCollapsed: true,
                  filled: false,
                  fillColor: Colors.transparent,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  hintText: 'Name, ingredient or concern…',
                  hintStyle: TextStyle(color: AppColors.muted, fontSize: 14),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ── .sortbar>button ──
class _SortBarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _SortBarButton({required this.icon, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppColors.line, width: 1), borderRadius: BorderRadius.circular(9)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: AppColors.navy),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.navy)),
        ]),
      ),
    );
  }
}

// ── .vtog button ──
class _VtogButton extends StatelessWidget {
  final IconData icon;
  final bool on;
  final VoidCallback onTap;
  const _VtogButton({required this.icon, required this.on, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30, height: 28,
        decoration: BoxDecoration(color: on ? AppColors.navy : Colors.transparent, borderRadius: BorderRadius.circular(7)),
        alignment: Alignment.center,
        child: Icon(icon, size: 16, color: on ? Colors.white : AppColors.muted),
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _FilterRow({required this.label, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: const TextStyle(fontSize: 13.5, color: AppColors.ink)),
        Switch(value: value, activeColor: AppColors.sky, onChanged: onChanged),
      ]),
    );
  }
}

// ── .plc — list view product card ──
class _ProductListCard extends StatelessWidget {
  final dynamic product;
  final CartState cart;
  final VoidCallback onTap;
  const _ProductListCard({required this.product, required this.cart, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = product;
    final was = p.bestWasPrice;
    final s = p.defaultSeller;
    final key = '${p.id}_${s.name}';
    final qty = cart.cart[key]?.qty ?? 0;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: AppColors.shSm),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Container(
            width: 74, height: 74,
            decoration: BoxDecoration(color: AppColors.blush, borderRadius: BorderRadius.circular(11)),
            alignment: Alignment.center,
            child: Text(p.emoji, style: const TextStyle(fontSize: 32)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.brand.toUpperCase(), style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: AppColors.sky, letterSpacing: 0.3)),
                const SizedBox(height: 2),
                Text(p.nameEn, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink, height: 1.3)),
                const SizedBox(height: 4),
                Text('${p.rating} ★', style: const TextStyle(fontSize: 10.5, color: AppColors.muted)),
                const SizedBox(height: 4),
                Row(children: [
                  Text(Formatters.money(p.bestPrice), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.navy)),
                  if (was != null) ...[
                    const SizedBox(width: 5),
                    Text(Formatters.money(was), style: const TextStyle(fontSize: 11, color: AppColors.muted, decoration: TextDecoration.lineThrough)),
                  ],
                ]),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (qty > 0)
          // .qstep.sm — compact stepper replaces the plus-only button once in cart.
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(color: AppColors.sky, borderRadius: BorderRadius.circular(10)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                StepBtn(icon: Icons.remove_rounded, onTap: () => cart.setQty(key, -1)),
                SizedBox(width: 22, child: Text('$qty', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13))),
                StepBtn(
                  icon: Icons.add_rounded,
                  onTap: !s.stock ? null : () => cart.addToCart(p, seller: s.name, price: s.price, was: s.was, apiProductId: s.productId),
                ),
              ]),
            )
          else if (!s.stock)
            Container(
              width: 34, height: 34,
              decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(10)),
              alignment: Alignment.center,
              child: const Icon(Icons.remove_shopping_cart_rounded, color: AppColors.muted, size: 16),
            )
          else
            GestureDetector(
              onTap: () {
                cart.addToCart(p, seller: s.name, price: s.price, was: s.was, apiProductId: s.productId);
                showToast(context, 'Added to cart');
              },
              child: Container(
                width: 34, height: 34,
                decoration: BoxDecoration(color: AppColors.sky, borderRadius: BorderRadius.circular(10)),
                alignment: Alignment.center,
                child: const Icon(Icons.add, color: Colors.white, size: 18),
              ),
            ),
        ]),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool on;
  final bool small;
  final VoidCallback onTap;
  const _Chip({required this.label, required this.on, required this.onTap, this.small = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: small ? 12 : 14, vertical: small ? 7 : 9),
          decoration: BoxDecoration(
            color: on ? AppColors.navy : Colors.white,
            border: Border.all(color: on ? AppColors.navy : AppColors.line, width: 1.5),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(label, style: TextStyle(fontSize: small ? 12 : 13, fontWeight: FontWeight.w600, color: on ? Colors.white : AppColors.muted)),
        ),
      ),
    );
  }
}