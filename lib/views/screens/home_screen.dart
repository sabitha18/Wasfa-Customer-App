import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/address_geocoder.dart';
import '../../core/widgets/async_state_view.dart';
import '../../data/models/home_feed.dart';
import '../../data/models/pharmacy_store.dart';
import '../../state/address_state.dart';
import '../../state/location_state.dart';
import '../../viewmodels/home_view_model.dart';
import '../../viewmodels/shop_view_model.dart';
import '../widgets/section_header.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Location is a hard gate before this screen can ever build (see
    // LocationGateScreen) — position should already be available here.
    final location = context.read<LocationState>();
    final addressState = context.read<AddressState>();
    // Only the "Current location" case can be resolved synchronously here
    // (GPS position is already available) — a saved address needs
    // forward-geocoding, which is async and can't be awaited inside
    // build(). That case starts with no coordinates and gets corrected a
    // moment later by _HomeBody's own reactive refresh below, same as the
    // "GPS still resolving" race this already had to handle anyway.
    final initial = addressState.isCurrentLocationActive
        ? (lat: location.position?.latitude, lng: location.position?.longitude)
        : (lat: null, lng: null);
    return ChangeNotifierProvider(
      create: (_) => HomeViewModel(lat: initial.lat, lng: initial.lng),
      child: const _HomeBody(),
    );
  }
}

class _HomeBody extends StatelessWidget {
  const _HomeBody();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<HomeViewModel>();
    final location = context.watch<LocationState>();
    final addressState = context.watch<AddressState>();

    // Keeps the "Nearest stores" list honest about wherever delivery is
    // ACTUALLY going right now — reactively — not just whatever was true
    // the one time this ViewModel was first constructed. Always resolves
    // to lat/lng, never governorate_id/area_id — a saved address has no
    // coordinates of its own, so its area/governorate NAME gets
    // forward-geocoded into approximate coordinates instead (see
    // AddressGeocoder) rather than sending the area/governorate ids
    // themselves. Covers: GPS still resolving when Home first mounted (a
    // timing race, not a permanent failure), the position genuinely
    // changing later, AND switching which saved address is selected in
    // the delivery-address picker (the app bar's "Deliver to" label
    // already updates for this — the store list underneath used to
    // silently NOT follow it at all). refreshStoresIfLocationChanged
    // no-ops internally if the resolved coordinates haven't actually
    // changed, so this is safe to kick off on every rebuild.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      double? lat;
      double? lng;
      if (addressState.isCurrentLocationActive) {
        lat = location.position?.latitude;
        lng = location.position?.longitude;
      } else {
        final a = addressState.effectiveAddress;
        if (a != null) {
          final geocoded = await AddressGeocoder.instance.forAddress(a);
          lat = geocoded.lat;
          lng = geocoded.lng;
        }
      }
      vm.refreshStoresIfLocationChanged(lat, lng);
    });

    // Was rendering the full layout with every section already empty
    // (no categories, no banners, no product rails, no stores) while
    // GET /app/home and GET /app/stores were still in flight — looked
    // exactly like "nothing is happening" rather than "loading", since
    // there was no spinner or skeleton anywhere. Only applies to the very
    // first load (feed still the initial empty constant AND stores still
    // empty) — a background refresh with existing data already on screen
    // shouldn't wipe it all out again just to show a spinner.
    if (vm.isLoading && identical(vm.feed, HomeFeed.empty) && vm.stores.isEmpty) {
      return const LoadingView(message: 'Loading…');
    }

    return CustomScrollView(
      slivers: [
        // The home feed (deals/best/recent rails, categories, brands) comes
        // from GET /app/home — it's fetched on load to warm the product
        // cache for other screens. The store marketplace below is a
        // separate fetch (GET /app/stores, confirmed live — see
        // HomeViewModel.stores), so a feed fetch failure is shown as a
        // small non-blocking banner rather than hiding the page.
        if (vm.error != null)
          SliverToBoxAdapter(
            child: InlineErrorBanner(message: vm.error!, onRetry: vm.load),
          ),

        // ---- .carousel — promo banners, from GET /app/home's banners[] ----
        // No dummy fallback: if the API sends no banners, this section
        // shows nothing at all, rather than the 3 hardcoded promo cards
        // that used to be here regardless of what the API actually said.
        if (vm.feed.banners.isNotEmpty)
          SliverToBoxAdapter(child: _BannerCarousel(banners: vm.feed.banners)),

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

class _BannerCarousel extends StatefulWidget {
  final List<HomeBanner> banners;
  const _BannerCarousel({required this.banners});

  @override
  State<_BannerCarousel> createState() => _BannerCarouselState();
}

class _BannerCarouselState extends State<_BannerCarousel> {
  final _controller = PageController(viewportFraction: .92);
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 188,
          child: PageView.builder(
            controller: _controller,
            padEnds: false,
            onPageChanged: (i) => setState(() => _page = i),
            itemCount: widget.banners.length,
            itemBuilder: (context, i) {
              final banner = widget.banners[i];
              return Padding(
                padding: EdgeInsets.only(left: i == 0 ? 16 : 6, right: i == widget.banners.length - 1 ? 16 : 6),
                child: _BannerCard(banner: banner),
              );
            },
          ),
        ),
        if (widget.banners.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 9, bottom: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < widget.banners.length; i++) ...[
                  if (i > 0) const SizedBox(width: 5),
                  _Dot(on: i == _page),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// Renders one confirmed `banners[]` entry. Title/sub/buttons are all
/// optional per the confirmed response (a banner can be pure image — see
/// the third example in the confirmed payload, which has empty title/sub
/// and no buttons at all), so each piece only shows when actually present,
/// rather than assuming every banner has full text content.
class _BannerCard extends StatelessWidget {
  final HomeBanner banner;
  const _BannerCard({required this.banner});

  @override
  Widget build(BuildContext context) {
    final hasText = banner.title.isNotEmpty || banner.sub.isNotEmpty || banner.buttons.isNotEmpty;
    // Tappable whenever the API actually gives us somewhere to go — either
    // a button's own link, or (when there's no button but the image itself
    // is marked clickable) that same first-button link as a fallback. If
    // neither exists, the banner just isn't tappable rather than guessing
    // a destination that was never specified.
    final link = banner.buttons.isNotEmpty ? banner.buttons.first.link : null;
    final onTap = (link != null && link.isNotEmpty) ? () => _openBannerLink(context, link) : null;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(color: AppColors.blush, boxShadow: AppColors.shSm),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (banner.imageUrl.isNotEmpty)
                Image.network(
                  banner.imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(color: AppColors.blush),
                ),
              // Readability scrim behind the text — only when there's text
              // to actually read; a pure-image banner stays untouched.
              if (hasText)
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xCC0B2A4A), Colors.transparent],
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                    ),
                  ),
                ),
              if (hasText)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (banner.title.isNotEmpty)
                        Text(
                          banner.emoji.isNotEmpty ? '${banner.title} ${banner.emoji}' : banner.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700, height: 1.2),
                        ),
                      if (banner.sub.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          banner.sub,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.white.withOpacity(.92), fontSize: 12, height: 1.25),
                        ),
                      ],
                      if (banner.buttons.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                          child: Text(banner.buttons.first.text, style: const TextStyle(color: AppColors.navy, fontWeight: FontWeight.w700, fontSize: 12)),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Maps a banner's `link` (a relative WEB path, e.g. `/website/shop` or
/// `/website/shop?deals=1` — confirmed live) to actual in-app navigation.
/// This is a best-effort mapping for the destinations this app actually
/// has a screen for, NOT a full web-route parser — an unrecognized path
/// falls back to Shop (this app's main browsing surface) rather than
/// doing nothing, since some destination is better than a dead tap.
void _openBannerLink(BuildContext context, String link) {
  final uri = Uri.tryParse(link);
  final path = uri?.path ?? link;
  if (path.contains('shop')) {
    final wantsOffers = uri?.queryParameters['deals'] == '1' || uri?.queryParameters['offers'] == '1';
    Navigator.pushNamed(context, Routes.shop, arguments: wantsOffers ? const ShopFilter(offersOnly: true) : null);
    return;
  }
  if (path.contains('rx')) {
    Navigator.pushNamed(context, Routes.myRx);
    return;
  }
  Navigator.pushNamed(context, Routes.shop);
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
                Expanded(
                  child: Text(
                    etaLabel(store.eta),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            // Was: defaulted to "Free delivery" whenever there was no offer,
            // regardless of the real store.freeDelivery field — claiming
            // free delivery for stores that never said they offered it.
            if (store.offer != null || store.freeDelivery)
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
                  // Was: always appended "· Free delivery" regardless of
                  // the real store.freeDelivery field.
                  Text(
                    [
                      etaLabel(store.eta),
                      if (store.freeDelivery) 'Free delivery',
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: AppColors.muted),
                  ),
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
/// Was unconditionally appending " mins" to whatever the API sent,
/// assuming `eta` is always a bare range like "20-30" (per
/// PharmacyStore.eta's own doc comment) — but at least one real pharmacy's
/// `eta` value already has "mins" baked into the string itself, producing
/// "8420-8440 mins mins". This checks for that first rather than assuming
/// the API is always consistent about it. The "8420-8440" number itself is
/// a separate, genuine backend data-quality issue (~140 hours is not a
/// plausible delivery ETA) — worth flagging to Soumya, but not something
/// the app should try to silently "correct" by guessing at intended values.
String etaLabel(String eta) {
  if (eta.isEmpty) return 'ETA unavailable';
  if (RegExp(r'min', caseSensitive: false).hasMatch(eta)) return eta;
  return '$eta mins';
}
