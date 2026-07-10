import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/async_state_view.dart';
import '../../data/models/pharmacy_store.dart';
import '../../viewmodels/home_view_model.dart';
import '../widgets/section_header.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => HomeViewModel(),
      child: const _HomeBody(),
    );
  }
}

class _HomeBody extends StatelessWidget {
  const _HomeBody();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<HomeViewModel>();

    return CustomScrollView(
      slivers: [
        // The home feed (deals/best/recent rails, categories, brands) comes
        // from GET /app/home — it's fetched on load to warm the product
        // cache for other screens. The store marketplace below stays mock
        // (GET /app/stores isn't implemented server-side yet), so a feed
        // fetch failure is shown as a small non-blocking banner rather than
        // hiding the page.
        if (vm.error != null)
          SliverToBoxAdapter(
            child: InlineErrorBanner(message: vm.error!, onRetry: vm.load),
          ),

        // ---- .carousel — promo cards -----------------------------------------
        SliverToBoxAdapter(
          child: SizedBox(
            height: 188,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              children: [
                PromoCard(
                  gradient: AppColors.promo1,
                  title: 'Pharmacy & doctor,\nin one app',
                  subtitle: 'Genuine meds in 1 hour + doctors on demand',
                  cta: 'Explore',
                  onTap: () => Navigator.pushNamed(context, Routes.shop),
                ),
                const SizedBox(width: 12),
                PromoCard(
                  gradient: AppColors.promo2,
                  title: 'Free delivery in 1 hour',
                  subtitle: 'On orders of 3 items or more',
                  cta: 'Shop now',
                  onTap: () => Navigator.pushNamed(context, Routes.shop),
                ),
                const SizedBox(width: 12),
                PromoCard(
                  gradient: AppColors.promo3,
                  title: 'Your prescriptions,\ndelivered',
                  subtitle: 'Doctor sends your Rx straight to the app',
                  cta: 'My Rx',
                  onTap: () => Navigator.pushNamed(context, Routes.myRx),
                ),
              ],
            ),
          ),
        ),
        // ---- .dots — carousel page indicator ---------------------------------
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.only(top: 9, bottom: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _Dot(on: true),
                SizedBox(width: 5),
                _Dot(on: false),
                SizedBox(width: 5),
                _Dot(on: false),
              ],
            ),
          ),
        ),

        // ---- .sec + .nearrail — "Nearest stores" -------------------------------
        const SliverToBoxAdapter(child: SectionHeader(title: 'Nearest stores')),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 195,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              itemCount: vm.nearestStores.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) => _NearStoreCard(store: vm.nearestStores[i]),
            ),
          ),
        ),

        // ---- .sec — "Browse all stores" --------------------------------------
        const SliverToBoxAdapter(child: SectionHeader(title: 'Browse all stores')),

        // ---- .storefilters -----------------------------------------------------
        SliverToBoxAdapter(
          child: SizedBox(
            height: 50,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
              children: [
                _FilterChip(label: 'Offers', on: vm.storeFilters['offers']!, onTap: () => vm.toggleFilter('offers')),
                _FilterChip(label: 'Under 30 mins', on: vm.storeFilters['under30']!, onTap: () => vm.toggleFilter('under30')),
                _FilterChip(label: 'Free delivery', on: vm.storeFilters['free']!, onTap: () => vm.toggleFilter('free')),
                _FilterChip(label: 'Pro', on: vm.storeFilters['pro']!, onTap: () => vm.toggleFilter('pro')),
              ],
            ),
          ),
        ),

        // ---- #storeList ----------------------------------------------------------
        if (vm.filteredStores.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Column(children: [
                  Text('🏪', style: TextStyle(fontSize: 34)),
                  SizedBox(height: 10),
                  Text('No products found', style: TextStyle(color: AppColors.muted)),
                ]),
              ),
            ),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
                  (context, i) {
                final store = vm.filteredStores[i];
                return _StoreRow(
                  store: store,
                  isLast: i == vm.filteredStores.length - 1,
                  onTap: () => Navigator.pushNamed(context, Routes.store, arguments: store),
                );
              },
              childCount: vm.filteredStores.length,
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 90)),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  final bool on;
  const _Dot({required this.on});
  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: on ? 16 : 6,
      height: 6,
      decoration: BoxDecoration(color: on ? AppColors.sky : AppColors.cloud, borderRadius: BorderRadius.circular(4)),
    );
  }
}

class PromoCard extends StatelessWidget {
  final List<Color> gradient;
  final String title;
  final String subtitle;
  final String cta;
  final VoidCallback onTap;
  const PromoCard({super.key, required this.gradient, required this.title, required this.subtitle, required this.cta, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Container(
        width: 300,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
          boxShadow: AppColors.shSm,
        ),
        child: Stack(
          children: [
            // .deco — decorative translucent circle, bottom-right
            // positioned against the FULL card bounds, unaffected by text padding
            Positioned(
              right: -26,
              bottom: -26,
              child: Container(
                width: 130,
                height: 130,
                decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(.13)),
              ),
            ),
            // Text content — padding applies ONLY here now
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700, height: 1.2),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white.withOpacity(.92), fontSize: 12.5, height: 1.25),
                  ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: onTap,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                      child: Text(cta, style: const TextStyle(color: AppColors.navy, fontWeight: FontWeight.w700, fontSize: 12.5)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback onTap;
  const _FilterChip({required this.label, required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 9),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: on ? AppColors.navy : Colors.white,
            border: Border.all(color: on ? AppColors.navy : AppColors.line, width: 1.5),
            borderRadius: BorderRadius.circular(20),
          ),
          alignment: Alignment.center,
          child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: on ? Colors.white : AppColors.ink)),
        ),
      ),
    );
  }
}

class _NearStoreCard extends StatelessWidget {
  final PharmacyStore store;
  const _NearStoreCard({required this.store});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, Routes.store, arguments: store),
      child: Container(
        width: 130,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AppColors.line, width: 1.5),
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppColors.shSm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: store.gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(13),
              ),
              alignment: Alignment.center,
              child: Text(store.monogram, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 7),
            // .nc-nm — no line clamp in the CSS; min-height just keeps cards
            // even for short names, names can wrap to 2-3 lines naturally.
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 32),
              child: Text(
                store.name,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.navy, height: 1.25),
              ),
            ),
            const SizedBox(height: 7),
            Row(
              children: [
                const Icon(Icons.electric_moped, size: 14, color: AppColors.danger),
                const SizedBox(width: 4),
                Text('${store.eta} mins', style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
              ],
            ),
            const SizedBox(height: 7),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: store.offer != null ? AppColors.rose.withOpacity(.12) : AppColors.ok.withOpacity(.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                store.offer != null ? 'Offers' : 'Free delivery',
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: store.offer != null ? AppColors.rose : AppColors.ok),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoreRow extends StatelessWidget {
  final PharmacyStore store;
  final bool isLast;
  final VoidCallback onTap;
  const _StoreRow({required this.store, required this.isLast, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          border: Border(bottom: isLast ? BorderSide.none : const BorderSide(color: AppColors.line, width: 1)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: store.gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(15),
                boxShadow: AppColors.shSm,
              ),
              alignment: Alignment.center,
              child: Text(store.monogram, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(store.name, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: AppColors.navy, height: 1.3)),
                  const SizedBox(height: 3),
                  Text('${store.eta} mins · Free delivery', style: const TextStyle(fontSize: 13, color: AppColors.muted)),
                  if (store.offer != null)
                    Container(
                      margin: const EdgeInsets.only(top: 7),
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(color: const Color(0xFFD8F64A), borderRadius: BorderRadius.circular(7)),
                      child: const Text('Offers', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A))),
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.cloud),
          ],
        ),
      ),
    );
  }
}