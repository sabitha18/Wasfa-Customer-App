import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/async_state_view.dart';
import '../../state/address_state.dart';
import '../../state/auth_state.dart';
import '../../state/cart_state.dart';
import '../../state/locale_state.dart';
import '../../state/location_state.dart';
import '../../viewmodels/shop_view_model.dart';
import '../widgets/address_sheets.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/page_header.dart';
import '../widgets/product_card.dart';
import '../widgets/product_image.dart';
import '../widgets/toast.dart';

class ShopScreen extends StatelessWidget {
  final ShopFilter? initialFilter;
  /// False only for RootShell's own embedded "Shop" tab — that Scaffold
  /// already provides the bottom nav around the whole tab set, so this
  /// screen's own copy would double up with it. Every other place Shop
  /// gets opened (Home's categories, Store's "Explore"/"See all", brand
  /// pages, a banner's category link, etc.) pushes it as its own route —
  /// same as Store's own history here — with no bottom nav of its own
  /// otherwise, confirmed live from a real screenshot showing exactly that.
  final bool showBottomNav;
  const ShopScreen({super.key, this.initialFilter, this.showBottomNav = true});

  @override
  Widget build(BuildContext context) {
    final userId = context.read<AuthState>().userId;
    if (userId != null) {
      // The real, authoritative cart — not a `cart_status` boolean guess.
      // Fired once per Shop-screen open (this build() runs once per
      // navigation push, not on every rebuild); loadCartRemote's own
      // re-entrancy guard makes a second call here harmless too.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.read<CartState>().loadCartRemote(userId);
      });
    }
    return ChangeNotifierProvider(
      create: (_) => ShopViewModel(initial: initialFilter, userId: userId),
      child: _ShopBody(showBottomNav: showBottomNav),
    );
  }
}

// ── Pins a fixed-height widget to the top of a CustomScrollView ──
// This is the Flutter equivalent of the HTML prototype's
// `.sortbar{position:sticky;top:0;background:var(--bg);z-index:5}` — only
// the sort/filter bar sticks; everything above it (the category chips)
// scrolls away normally.
class _StickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double height;
  _StickyHeaderDelegate({required this.child, required this.height});

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return SizedBox.expand(child: child);
  }

  @override
  bool shouldRebuild(covariant _StickyHeaderDelegate oldDelegate) {
    return oldDelegate.child != child || oldDelegate.height != height;
  }
}

class _ShopBody extends StatelessWidget {
  final bool showBottomNav;
  const _ShopBody({required this.showBottomNav});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ShopViewModel>();
    // context.read, not watch — cart/list cards each select just the piece
    // they need (see ProductCard/_ProductListCard). Watching the whole
    // CartState here would rebuild this entire grid/list on every cart
    // change anywhere, not just the count badge below.
    final cart = context.read<CartState>();
    final cartCount = context.select<CartState, int>((c) => c.cartCount);
    final locale = context.watch<LocaleState>();
    final ar = locale.isArabic;
    String t(String en, String arabic) => ar ? arabic : en;
    final results = vm.results;
    final inPharmacy = vm.pharmacy != null;

    // ── .sortbar height — used as the pinned SliverPersistentHeader extent ──
    const double sortBarHeight = 54;

    // ── .sortbar — sticky gray bar with bordered buttons + vtog ──
    // In the HTML prototype this is the ONLY element with position:sticky;
    // the category chips above it scroll away with the rest of the content.
    final sortBar = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: const BoxDecoration(
        color: AppColors.bg,
        border: Border(bottom: BorderSide(color: AppColors.line, width: 1)),
      ),
      child: Row(children: [
        _SortBarButton(icon: Icons.swap_vert_rounded, label: t('Sort', 'ترتيب'), onTap: () => _openSort(context, vm)),
        const SizedBox(width: 8),
        Stack(clipBehavior: Clip.none, children: [
          _SortBarButton(icon: Icons.filter_list_rounded, label: t('Filter', 'تصفية'), onTap: () => _openFilter(context, vm)),
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
    );

    // ── .reshead ──
    final resHead = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 11, 16, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              vm.isLoading ? t('Loading products…', 'جارٍ تحميل المنتجات…') : t('${results.length} products', '${results.length} منتج'),
              style: const TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        if (vm.error != null && results.isNotEmpty)
          InlineErrorBanner(message: vm.error!, onRetry: vm.load),
      ],
    );

    final slivers = <Widget>[
      // ── .cats2 — top-level (parent) category pills — scrolls away with content ──
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(top: 10), // ← margin-top equivalent
          child: SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 2),
              children: [
                _Chip(label: t('All', 'الكل'), on: vm.selectedParent == null, onTap: () => vm.selectParentCategory(null)),
                for (final c in vm.categories)
                  _Chip(label: c.label(locale.isArabic), on: vm.selectedParent?.id == c.id, onTap: () => vm.selectParentCategory(c)),
              ],
            ),
          ),
        ),
      ),
      // ── .cats2 — subcategories, one horizontally-scrolling row per level
      // of the drill-down path (selectedParent, then whichever child was
      // picked, then its own child, and so on) — previously only ever
      // showed selectedParent's direct children, with no way to drill into
      // a picked subcategory's own children ──
      for (int _i = 0; _i < vm.selectedCategoryPath.length; _i++)
        if (vm.selectedCategoryPath[_i].hasChildren)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 10), // ← margin-top equivalent
              child: SizedBox(
                height: 38,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 2),
                  children: [
                    for (final sub in vm.selectedCategoryPath[_i].children)
                      _Chip(
                        label: sub.label(locale.isArabic), small: true,
                        on: _i + 1 < vm.selectedCategoryPath.length && vm.selectedCategoryPath[_i + 1].id == sub.id,
                        onTap: () => vm.selectSubCategory(sub),
                      ),
                  ],
                ),
              ),
            ),
          ),

      // ── pinned sticky sort/filter bar (matches .sortbar{position:sticky;top:0}) ──
      SliverPersistentHeader(
        pinned: true,
        delegate: _StickyHeaderDelegate(height: sortBarHeight, child: sortBar),
      ),

      SliverToBoxAdapter(child: resHead),

      if (vm.isLoading && results.isEmpty)
        SliverFillRemaining(hasScrollBody: false, child: LoadingView(message: t('Loading products…', 'جارٍ تحميل المنتجات…')))
      else if (vm.error != null && results.isEmpty)
        SliverFillRemaining(hasScrollBody: false, child: ErrorRetryView(message: vm.error!, onRetry: vm.load))
      else if (results.isEmpty)
        SliverFillRemaining(hasScrollBody: false, child: Center(child: Text(t('No results', 'لا توجد نتائج'), style: const TextStyle(color: AppColors.muted))))
      else if (vm.view == 'grid')
        // ── .pgrid ──
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
          sliver: SliverGrid(
            // Lower ratio = taller tiles. The card's content is a stack of
            // mostly fixed-height sections (110px image + brand + 2-line name
            // + rating + pharmacy name + price + button); at .58 that stack
            // was ~17px taller than the tile on typical phones, causing
            // "BOTTOM OVERFLOWED BY 17 PIXELS", fixed by dropping to .56 —
            // then the pharmacy-name line added back a similar amount, so
            // this needs to be shorter again at .50.
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: .50),
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                // Captured ONCE here, not re-derived inside onTap — `results`
                // recomputes a brand-new filtered/sorted list on every
                // access (see ShopViewModel.results), so calling it again
                // lazily inside onTap (evaluated at actual tap time, not
                // build time) could return a DIFFERENT product than what's
                // rendered if anything changed the underlying list in
                // between — e.g. background pagination (loadMore)
                // appending items while scrolling. Capturing the product
                // here guarantees the id used for navigation always
                // matches what's actually on screen.
                final product = results[i];
                return ProductCard(
                  product: product,
                  onTap: () => Navigator.pushNamed(context, Routes.product, arguments: product.id),
                );
              },
              childCount: results.length,
            ),
          ),
        )
      else
        // ── .plist / .plc ──
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                if (i.isOdd) return const SizedBox(height: 11);
                // Same reasoning as the grid case above — capture once,
                // don't re-derive from `results` inside onTap.
                final idx = i ~/ 2;
                final product = results[idx];
                return _ProductListCard(
                  product: product,
                  cart: cart,
                  onTap: () => Navigator.pushNamed(context, Routes.product, arguments: product.id),
                );
              },
              childCount: results.length * 2 - 1,
            ),
          ),
        ),
    ];

    return Directionality(
      textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
      backgroundColor: AppColors.bg,
      // ── .phead only shows when inside a single pharmacy storefront ──
      appBar: inPharmacy ? PageHeader(title: vm.pharmacy!) : null,
      body: SafeArea(
        top: !inPharmacy, // manual top padding only when there's no PageHeader
        child: Column(
          children: [
            // ── .appbar — one white block containing both .ab-top AND .search ──
            // Stays fixed above the scroll area, same as the HTML prototype
            // where #screen (the scrollable div) sits below the fixed .appbar.
            if (!inPharmacy) _TopAppBar(cartCount: cartCount, onQueryChanged: vm.setQuery),

            Expanded(
              child: Stack(
                children: [
                  NotificationListener<ScrollNotification>(
                    onNotification: (n) {
                      if (vm.hasMore && !vm.isLoadingMore && n.metrics.pixels >= n.metrics.maxScrollExtent - 400) {
                        vm.loadMore();
                      }
                      return false;
                    },
                    child: CustomScrollView(slivers: slivers),
                  ),
                  if (vm.isLoadingMore)
                    Positioned(
                      left: 0, right: 0, bottom: 10,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: AppColors.shSm),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                            const SizedBox(width: 8),
                            Text(t('Loading more…', 'جارٍ تحميل المزيد…'), style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                          ]),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: showBottomNav ? const AppBottomNav(embedded: false) : null,
      ),
    );
  }

  void _openSort(BuildContext context, ShopViewModel vm) {
    final isArabic = context.read<LocaleState>().isArabic;
    final opts = [
      ['pop', isArabic ? 'الأكثر رواجاً' : 'Popularity'],
      ['low', isArabic ? 'السعر: من الأقل إلى الأعلى' : 'Price: low to high'],
      ['high', isArabic ? 'السعر: من الأعلى إلى الأقل' : 'Price: high to low'],
      ['rated', isArabic ? 'الأعلى تقييماً' : 'Top rated'],
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => Directionality(
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line, width: 1))),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(isArabic ? 'ترتيب حسب' : 'Sort by', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.navy)),
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
      ),
    );
  }

  void _openFilter(BuildContext context, ShopViewModel vm) {
    final isArabic = context.read<LocaleState>().isArabic;
    String t(String en, String ar) => isArabic ? ar : en;
    String brandSearch = '';
    bool showAllBrands = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => Directionality(
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        child: StatefulBuilder(
        builder: (context, setSheetState) {
          final allBrands = vm.realBrands;
          final q = brandSearch.trim().toLowerCase();
          final matchedBrands = q.isEmpty ? allBrands : allBrands.where((b) => b.toLowerCase().contains(q)).toList();
          final showingAll = showAllBrands || q.isNotEmpty;
          final visibleBrands = showingAll ? matchedBrands : matchedBrands.take(10).toList();
          final hiddenCount = matchedBrands.length - visibleBrands.length;

          return SafeArea(
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
                      Text(t('Filter', 'تصفية'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.navy)),
                      InkWell(onTap: () => Navigator.pop(context), child: const Icon(Icons.close_rounded, size: 20, color: AppColors.muted)),
                    ]),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          // ── Offers / In-stock — surfaced first since these are the
                          // two toggles people reach for most often ──
                          _FilterRow(
                            label: t('🏷️ Offers only', '🏷️ العروض فقط'),
                            value: vm.offersOnly,
                            onChanged: (_) { vm.toggleOffersOnly(); setSheetState(() {}); },
                          ),
                          _FilterRow(
                            label: t('🏆 Best sellers only', '🏆 الأكثر مبيعاً فقط'),
                            value: vm.bestSellersOnly,
                            onChanged: (_) { vm.toggleBestSellersOnly(); setSheetState(() {}); },
                          ),
                          _FilterRow(
                            label: t('In stock only', 'المتوفر فقط'),
                            value: vm.inStock,
                            onChanged: (_) { vm.toggleInStock(); setSheetState(() {}); },
                          ),
                          const SizedBox(height: 10),
                          Text(t('Pharmacy', 'الصيدلية'), style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.muted, fontSize: 12.5)),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8, runSpacing: 8,
                            children: [
                              _Chip(
                                label: t('All stores', 'كل المتاجر'), small: true, on: vm.pharmacy == null,
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
                          Text(t('Brand', 'العلامة التجارية'), style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.muted, fontSize: 12.5)),
                          const SizedBox(height: 8),
                          // ── small search box so a long brand list is still reachable ──
                          Container(
                            height: 36,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: AppColors.bg,
                              border: Border.all(color: AppColors.line, width: 1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(children: [
                              const Icon(Icons.search_rounded, size: 16, color: AppColors.muted),
                              const SizedBox(width: 6),
                              Expanded(
                                child: TextField(
                                  textAlignVertical: TextAlignVertical.center,
                                  decoration: InputDecoration(
                                    hintText: t('Search brands', 'ابحث عن العلامات التجارية'),
                                    hintStyle: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                                    border: InputBorder.none,
                                    isCollapsed: true,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                  style: const TextStyle(fontSize: 12.5, color: AppColors.navy),
                                  onChanged: (v) { brandSearch = v; setSheetState(() {}); },
                                ),
                              ),
                            ]),
                          ),
                          const SizedBox(height: 8),
                          if (matchedBrands.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Text(t('No brands found', 'لم يتم العثور على علامات تجارية'), style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                            )
                          else
                            Wrap(
                              spacing: 8, runSpacing: 8,
                              children: [
                                for (final b in visibleBrands)
                                  _Chip(
                                    label: b, small: true, on: vm.brands.contains(b),
                                    onTap: () { vm.toggleBrand(b); setSheetState(() {}); },
                                  ),
                                if (hiddenCount > 0)
                                  _Chip(
                                    label: t('+$hiddenCount more', '+$hiddenCount المزيد'), small: true, on: false,
                                    onTap: () { showAllBrands = true; setSheetState(() {}); },
                                  ),
                                if (showAllBrands && q.isEmpty && allBrands.length > 10)
                                  _Chip(
                                    label: t('Show less', 'عرض أقل'), small: true, on: false,
                                    onTap: () { showAllBrands = false; setSheetState(() {}); },
                                  ),
                              ],
                            ),
                          const SizedBox(height: 14),
                          Text(t('Categories', 'الفئات'), style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.muted, fontSize: 12.5)),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8, runSpacing: 8,
                            children: [
                              _Chip(
                                label: t('All categories', 'كل الفئات'), small: true, on: vm.selectedParent == null,
                                onTap: () { vm.selectParentCategory(null); setSheetState(() {}); },
                              ),
                              for (final c in vm.categories)
                                _Chip(
                                  label: c.label(isArabic), small: true, on: vm.selectedParent?.id == c.id,
                                  onTap: () { vm.selectParentCategory(c); setSheetState(() {}); },
                                ),
                            ],
                          ),
                          // ── subcategories of whichever parent is selected above —
                          // labeled + indented so it reads as a nested group, not
                          // a continuation of the parent chip row ──
                          // ── one nested, indented row per level of the
                          // drill-down path (selectedParent, then whichever
                          // child was picked, then its own child, and so on
                          // for as many levels as the tree actually has) ──
                          for (int i = 0; i < vm.selectedCategoryPath.length; i++)
                            if (vm.selectedCategoryPath[i].hasChildren) ...[
                              const SizedBox(height: 12),
                              Padding(
                                padding: const EdgeInsets.only(left: 2),
                                child: Text(
                                  t('Subcategories of ${vm.selectedCategoryPath[i].label(isArabic)}', 'الفئات الفرعية لـ ${vm.selectedCategoryPath[i].label(isArabic)}'),
                                  style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.muted, fontSize: 11, fontStyle: FontStyle.italic),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.only(left: 10),
                                decoration: const BoxDecoration(border: Border(left: BorderSide(color: AppColors.line, width: 2))),
                                child: Wrap(
                                  spacing: 8, runSpacing: 8,
                                  children: [
                                    for (final sub in vm.selectedCategoryPath[i].children)
                                      _Chip(
                                        label: sub.label(isArabic), small: true,
                                        on: i + 1 < vm.selectedCategoryPath.length && vm.selectedCategoryPath[i + 1].id == sub.id,
                                        onTap: () { vm.selectSubCategory(sub); setSheetState(() {}); },
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          const SizedBox(height: 20),
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
                          child: Text(t('Clear all', 'مسح الكل'), style: const TextStyle(fontWeight: FontWeight.w700)),
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
                          child: Text(t('Apply', 'تطبيق'), style: const TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ]),
                  ),
                ],
              ),
            ),
          );
        },
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
    final location = context.watch<LocationState>();
    final addressState = context.watch<AddressState>();
    final ar = context.watch<LocaleState>().isArabic;
    String t(String en, String arabic) => ar ? arabic : en;

    // Matches AppTopBar (Home/Store/Wishlist/Account) exactly: GPS location
    // by default, switching to a saved address once the person picks one
    // from the picker sheet. Was previously GPS-only here, and tapping the
    // row just re-triggered a GPS refresh instead of opening the picker —
    // so there was no way to reach "Delivery addresses" from this screen at
    // all.
    final usingSavedAddress = !addressState.isCurrentLocationActive && addressState.selected != null;
    final areaLabel = usingSavedAddress
        ? addressState.selected!.title
        : (location.area?.isNotEmpty == true ? location.area! : t('Current location', 'الموقع الحالي'));
    final detailLabel = usingSavedAddress
        ? addressState.selected!.formatted
        : [location.street, location.governorate].where((s) => s != null && s!.isNotEmpty).join(' · ');

    void openPicker() => showAddressPickerSheet(context, addressState, location);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      color: Colors.white,
      child: Column(children: [
        // .ab-top
        Row(children: [
          Expanded(
            child: GestureDetector(
              onTap: openPicker,
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
                      Text('${t("Deliver to", "التوصيل إلى")} $areaLabel', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.navy, height: 1.15)),
                      Row(children: [
                        Expanded(
                          child: Text(detailLabel.isNotEmpty ? detailLabel : t('Tap to choose your delivery address', 'اضغط لاختيار عنوان التوصيل'), maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11, color: AppColors.muted)),
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
                decoration: InputDecoration(
                  isCollapsed: true,
                  filled: false,
                  fillColor: Colors.transparent,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  hintText: t('Name, ingredient or concern…', 'الاسم أو المكون أو الحالة…'),
                  hintStyle: const TextStyle(color: AppColors.muted, fontSize: 14),
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
    final ar = context.watch<LocaleState>().isArabic;
    final was = p.bestWasPrice;
    final s = p.defaultSeller;
    // Canonical key — MUST match CartState.lineKey exactly (see its doc),
    // or a real synced cart line and this lookup silently diverge.
    final key = CartState.lineKey(apiProductId: s.productId, productId: p.id, seller: s.name);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      cart.syncQtyFromListing(
        p,
        seller: s.name,
        price: s.price,
        was: s.was,
        apiProductId: s.productId,
        qty: p.cartQty ?? (p.cartStatus ? 1 : 0),
        inStock: s.stock,
      );
    });
    final qty = context.select<CartState, int>((c) => c.cart[key]?.qty ?? 0);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: AppColors.shSm),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: ProductImage(product: p, height: 74, width: 74, emojiSize: 32),
              ),
              if (p.isBogo)
                Positioned(
                  left: 3,
                  top: 3,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(color: AppColors.rose, borderRadius: BorderRadius.circular(20)),
                    child: Text(
                      p.bogoDisplayLabel,
                      style: const TextStyle(fontSize: 7.5, fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                  ),
                ),
            ],
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
                const SizedBox(height: 2),
                // Always the actual pharmacy name (matching the PDP's
                // locked-seller rule) — was showing "N pharmacies" (a bare
                // count) instead whenever there was more than one seller.
                if (s.name != 'WASFA')
                  Text(
                    '🏪 ${s.name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10.5, color: AppColors.muted),
                  ),
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
                StepBtn(icon: Icons.remove_rounded, onTap: () => cart.setQtyRemote(context, key, -1)),
                SizedBox(width: 22, child: Text('$qty', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13))),
                StepBtn(
                  icon: Icons.add_rounded,
                  onTap: !s.stock ? null : () => cart.addToCartRemote(context, p, seller: s.name, price: s.price, was: s.was, apiProductId: s.productId, inStock: s.stock),
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
                cart.addToCartRemote(context, p, seller: s.name, price: s.price, was: s.was, apiProductId: s.productId, inStock: s.stock);
                // Matches ProductCard's exact wording (same toast, two
                // places it can fire from) — keep them in sync if this
                // ever changes.
                showToast(context, ar ? 'أُضيف للسلة' : 'Added to cart');
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