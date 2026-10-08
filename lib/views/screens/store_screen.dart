import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/pharmacy_store.dart';
import '../../data/models/seller_banner.dart';
import '../../state/auth_state.dart';
import '../../state/cart_state.dart';
import '../../state/locale_state.dart';
import '../../viewmodels/shop_view_model.dart';
import '../../viewmodels/store_view_model.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/store_avatar.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/open_product.dart';
import '../widgets/product_card.dart';
import '../widgets/section_header.dart';
import 'brands_screen.dart';
import 'shop_screen.dart';

class StoreScreen extends StatelessWidget {
  final PharmacyStore store;
  const StoreScreen({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    final userId = context.read<AuthState>().userId;
    return ChangeNotifierProvider(
      create: (_) => StoreViewModel(store, userId: userId),
      child: _StoreBody(store: store),
    );
  }
}

class _StoreBody extends StatelessWidget {
  final PharmacyStore store;
  const _StoreBody({required this.store});

  void _openShop(BuildContext context, {String? category, String? brand, bool offersOnly = false, bool bestSellersOnly = false}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ShopScreen(
          // `shopId` (the store's user_id) is what actually scopes the server
          // listing to this store; `pharmacy` is kept for the header title.
          initialFilter: ShopFilter(
            pharmacy: store.seller,
            shopId: store.id,
            category: category,
            brand: brand,
            offersOnly: offersOnly,
            bestSellersOnly: bestSellersOnly,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<StoreViewModel>();
    final cart = context.watch<CartState>();
    final name = store.name;
    final ar = context.watch<LocaleState>().isArabic;
    String t(String en, String arabic) => ar ? arabic : en;

    return Directionality(
      textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
      // .appbar — same persistent location/search/Rx/cart bar as Home, per
      // renderAppbar(): shown on home/store/shop/wishlist/account.
      appBar: const AppTopBar(),
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              // .store-top — gradient header: back + logo + name, then .freedel
              SliverToBoxAdapter(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(colors: AppColors.storeTopGradient, begin: Alignment.topCenter, end: Alignment.bottomCenter),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // .st-row
                      Row(
                        children: [
                          GestureDetector(
                            onTap: () => Navigator.of(context).maybePop(),
                            child: Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: AppColors.shSm),
                              alignment: Alignment.center,
                              child: Icon(ar ? Icons.arrow_forward_rounded : Icons.arrow_back_rounded, size: 19, color: AppColors.navy),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // .st-logo — the store's real logo (`logo` from
                          // /app/stores) when it has one, monogram otherwise.
                          StoreAvatar(store: store, size: 42, borderRadius: 11, fontSize: 18),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.navy, height: 1.2)),
                          ),
                        ],
                      ),
                      // .freedel — only when this store actually has free
                      // delivery on (`free` from /app/stores). Was always
                      // shown, whatever the store's real value was.
                      if (store.freeDelivery)
                        Padding(
                          padding: const EdgeInsets.only(top: 10, bottom: 2),
                          child: Row(
                            children: [
                              const Icon(Icons.electric_moped, size: 16, color: AppColors.freeDeliveryOrange),
                              const SizedBox(width: 7),
                              Text(t('Free delivery on your next order', 'توصيل مجاني لطلبك القادم'), style: const TextStyle(color: AppColors.freeDeliveryOrange, fontSize: 13, fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // .carousel — real per-store banners (confirmed live,
              // 2026-09-17: GET /app/seller/{id}/banners), replacing what
              // used to be 3 entirely hardcoded cards — the same "Free
              // delivery in 1 hour"/"Your prescriptions, delivered" copy on
              // literally every seller's page, with zero backend control.
              // Shows nothing at all if this store has no banners
              // configured, rather than falling back to those old fake ones.
              if (vm.banners.isNotEmpty) SliverToBoxAdapter(child: _SellerBannerCarousel(banners: vm.banners, store: store)),

              // .sec "Shop by category" + .catgrid — matches rStore(): the
              // category grid is the first section after the carousel, and
              // its header always renders (an empty catgrid just renders
              // nothing, same as the HTML's empty div when a store has no
              // categorised products).
              SliverToBoxAdapter(child: SectionHeader(title: t('Shop by category', 'تسوق حسب الفئة'), actionLabel: t('See all', 'عرض الكل'), onAction: () => _openShop(context))),
              if (vm.isLoading)
                const SliverToBoxAdapter(
                  child: Padding(padding: EdgeInsets.symmetric(vertical: 34), child: Center(child: CircularProgressIndicator())),
                )
              else
                SliverToBoxAdapter(
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: .8),
                    itemCount: vm.categoriesInStore.length,
                    itemBuilder: (context, i) {
                      final c = vm.categoriesInStore[i];
                      final iconUrl = c['icon'];
                      return GestureDetector(
                        onTap: () => _openShop(context, category: c['cat']),
                        child: Column(
                          children: [
                            Expanded(
                              child: Container(
                                width: double.infinity,
                                decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(14)),
                                alignment: Alignment.center,
                                // Real category icon when the API provides one;
                                // falls back to the emoji placeholder if there's
                                // no icon, it's empty, or it fails to load.
                                child: (iconUrl != null && iconUrl.isNotEmpty)
                                    ? Padding(
                                        padding: const EdgeInsets.all(10),
                                        child: Image.network(
                                          iconUrl,
                                          fit: BoxFit.contain,
                                          errorBuilder: (_, __, ___) => Text(c['emoji']!, style: const TextStyle(fontSize: 30)),
                                        ),
                                      )
                                    : Text(c['emoji']!, style: const TextStyle(fontSize: 30)),
                              ),
                            ),
                            const SizedBox(height: 7),
                            Text(c['cat']!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.ink)),
                          ],
                        ),
                      );
                    },
                  ),
                ),

              // .sec "Special offers" + .rail — header always renders per
              // rStore(); only the rail content falls back to "No results".
              // NOTE: See all here deliberately diverges from the HTML
              // (which just calls the same unfiltered storeAll() as every
              // other section) — passes offersOnly so Shop opens already
              // narrowed to this store's actual offers, per client request.
              SliverToBoxAdapter(child: SectionHeader(title: t('Special offers', 'عروض خاصة'), actionLabel: t('See all', 'عرض الكل'), onAction: () => _openShop(context, offersOnly: true))),
              _ProductRail(products: vm.offers, onTapProduct: (p) => Navigator.pushNamed(context, Routes.product, arguments: p.id)),

              // .sec "Best sellers" + .rail — same divergence as Special
              // offers above: See all passes bestSellersOnly instead of
              // opening the unfiltered catalogue.
              SliverToBoxAdapter(child: SectionHeader(title: t('Best sellers', 'الأكثر مبيعاً'), actionLabel: t('See all', 'عرض الكل'), onAction: () => _openShop(context, bestSellersOnly: true))),
              _ProductRail(products: vm.bestSellers, onTapProduct: (p) => Navigator.pushNamed(context, Routes.product, arguments: p.id)),

              // .sec "Top brands" + .brand-rail
              SliverToBoxAdapter(
                child: SectionHeader(
                  title: t('Top brands', 'أفضل العلامات التجارية'),
                  actionLabel: t('See all', 'عرض الكل'),
                  // Push directly (rather than the named Routes.brands route)
                  // so we can hand BrandsScreen this store's real,
                  // server-scoped brand list — see BrandsScreen for why that
                  // matters for keeping the shop filter intact.
                  onAction: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => BrandsScreen(store: store, brands: vm.brandsInStore)),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: vm.brandsInStore.isEmpty
                    ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(t('No results', 'لا توجد نتائج'), style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                )
                    : SizedBox(
                  height: 62,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: vm.brandsInStore.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, i) {
                      final name = vm.brandsInStore[i];
                      final logo = vm.brandLogosInStore[name];
                      const nameStyle = TextStyle(fontWeight: FontWeight.w700, color: AppColors.navy, fontSize: 13);
                      final nameText = Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: nameStyle);
                      return Semantics(
                        // The name isn't drawn when there's a logo, so screen
                        // readers still need it.
                        label: name,
                        button: true,
                        child: GestureDetector(
                          onTap: () => _openShop(context, brand: name),
                          child: Container(
                            constraints: const BoxConstraints(minWidth: 92),
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(13), boxShadow: AppColors.shSm),
                            alignment: Alignment.center,
                            // A brand with a logo shows ONLY the logo (no
                            // name next to it); one without keeps the name.
                            // `contain` so a wide logo isn't cropped to a
                            // square the way it used to be. If the image
                            // fails to load it falls back to the name, not a
                            // broken-image icon.
                            child: logo != null
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: _BrandLogo(url: logo, width: 96, height: 40, fit: BoxFit.contain, fallback: nameText),
                                  )
                                : nameText,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 90)),
            ],
          ),
          // storeMinbar() — pinned to the bottom, sits just above the tab
          // bar below (Scaffold reserves that space automatically).
          Positioned(left: 0, right: 0, bottom: 0, child: _StoreMinbar(cart: cart)),
        ],
      ),
      // Store used to have no bottom nav at all — the same 4-tab
      // Home/Shop/Wishlist/Account bar RootShell shows, but Store isn't
      // one of those 4 tabs (it's pushed on top of RootShell), so tapping
      // one here pops back to RootShell and switches its tab — see
      // AppBottomNav's `embedded: false` doc.
      bottomNavigationBar: const AppBottomNav(embedded: false),
      ),
    );
  }
}

/// A real brand_logo (confirmed live, 2026-09-16) came back as a `.svg`
/// file — Image.network can't decode SVG at all (it only understands
/// raster formats: PNG/JPG/WebP/etc.), so it would have silently failed
/// and always fallen through to errorBuilder, never actually showing a
/// logo despite one genuinely being there. Picks the right renderer by the
/// URL's own extension rather than assuming every brand's logo is the same
/// format — backend may not be consistent about it across brands.
class _BrandLogo extends StatelessWidget {
  final String url;
  final double width;
  final double height;
  final BoxFit fit;
  final Widget fallback;
  const _BrandLogo({required this.url, required this.width, required this.height, this.fit = BoxFit.cover, required this.fallback});

  @override
  Widget build(BuildContext context) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? url.toLowerCase();
    if (path.endsWith('.svg')) {
      return SvgPicture.network(
        url,
        width: width,
        height: height,
        fit: fit,
        placeholderBuilder: (_) => SizedBox(width: width, height: height),
        errorBuilder: (_, __, ___) => fallback,
      );
    }
    return Image.network(
      url,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, __, ___) => fallback,
    );
  }
}

/// Mirrors Home's own `_BannerCarousel`/`_BannerCard` (real API-driven
/// banners there too) — same page-tracked dots, adapted for
/// SellerBanner's different shape (`link_type`/`link_id` instead of a
/// plain URL string).
class _SellerBannerCarousel extends StatefulWidget {
  final List<SellerBanner> banners;
  final PharmacyStore store;
  const _SellerBannerCarousel({required this.banners, required this.store});

  @override
  State<_SellerBannerCarousel> createState() => _SellerBannerCarouselState();
}

class _SellerBannerCarouselState extends State<_SellerBannerCarousel> {
  final _controller = PageController(viewportFraction: .92);
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
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
                  child: _SellerBannerCard(banner: banner, store: widget.store),
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
      ),
    );
  }
}

/// Renders one real `SellerBanner`. Title/description/button all only show
/// when actually present/enabled, same principle as Home's `_BannerCard` —
/// a banner can be pure image with `button_show: false`, and description
/// is skipped when it's just a duplicate of the title (confirmed live: a
/// real banner had `title`/`description` both set to the exact same
/// string, "Pharmacline Pharmacy" — showing that twice would just look
/// like a mistake, not real content).
class _SellerBannerCard extends StatelessWidget {
  final SellerBanner banner;
  final PharmacyStore store;
  const _SellerBannerCard({required this.banner, required this.store});

  @override
  Widget build(BuildContext context) {
    final showDescription = banner.description.isNotEmpty && banner.description != banner.title;
    final showButton = banner.buttonShow && banner.buttonText.isNotEmpty;
    final hasText = banner.title.isNotEmpty || showDescription || showButton;
    // Tappable with a button (as before) OR when the admin picked a real
    // destination, even with no button — otherwise a banner linked to a
    // category/brand/product but shown image-only was a dead tap.
    final tappable = showButton || sellerBannerHasDestination(banner);

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: GestureDetector(
        onTap: tappable ? () => _openSellerBannerDestination(context, banner, store) : null,
        child: Container(
          decoration: BoxDecoration(color: AppColors.blush, boxShadow: AppColors.shSm),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (banner.image.isNotEmpty)
                Image.network(
                  banner.image,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(color: AppColors.blush),
                ),
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
                          banner.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700, height: 1.2),
                        ),
                      if (showDescription) ...[
                        const SizedBox(height: 4),
                        Text(
                          banner.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.white.withOpacity(.92), fontSize: 12, height: 1.25),
                        ),
                      ],
                      if (showButton) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                          child: Text(banner.buttonText, style: const TextStyle(color: AppColors.navy, fontWeight: FontWeight.w700, fontSize: 12)),
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

/// Link types handled on a SELLER banner, mirroring what Home banners
/// confirmed live (2026-10-07): `category`, `brand`, `product`, with
/// `link_id` = that thing's id and `link_label` = its name. In a real
/// SELLER-banner response: `none`, `brand` and `product` are confirmed
/// (2026-10-07); `category` is assumed to follow the same shape. Anything
/// unrecognised keeps the old behaviour (below) instead of failing.
bool sellerBannerHasDestination(SellerBanner b) =>
    (b.linkType == 'product' && b.linkIdText != null) ||
    (b.linkId != null && (b.linkType == 'category' || b.linkType == 'brand'));

/// category/brand open this store's Shop listing narrowed to that
/// category/brand (it's this store's own banner, so it stays inside this
/// store); product opens the product page directly. `none` and anything
/// not recognised falls back to the previous behaviour — this store's whole
/// Shop listing — rather than doing nothing or guessing.
void _openSellerBannerDestination(BuildContext context, SellerBanner banner, PharmacyStore store) {
  final id = banner.linkId;
  final label = (banner.linkLabel ?? '').trim();
  // A product banner's link_id is a SKU — text, not a whole number — so it's
  // handled before the numeric-id guard below, which would drop e.g. "a16346".
  if (banner.linkType == 'product' && banner.linkIdText != null) {
    openProductFromBanner(context, banner.linkIdText!, label);
    return;
  }
  if (id != null) {
    switch (banner.linkType) {
      case 'category':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ShopScreen(initialFilter: ShopFilter(category: label.isEmpty ? null : label, categoryId: id, pharmacy: store.seller, shopId: store.id))),
        );
        return;
      case 'brand':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ShopScreen(initialFilter: ShopFilter(brand: label.isEmpty ? 'Brand #$id' : label, brandId: id, pharmacy: store.seller, shopId: store.id))),
        );
        return;
    }
  }
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => ShopScreen(initialFilter: ShopFilter(pharmacy: store.seller, shopId: store.id))),
  );
}

class _Dot extends StatelessWidget {
  final bool on;
  const _Dot({required this.on});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: on ? 18 : 6,
      height: 6,
      decoration: BoxDecoration(color: on ? AppColors.navy : AppColors.line, borderRadius: BorderRadius.circular(3)),
    );
  }
}

/// storeMinbar() — "add KWD X to place an order" nudge, or a tappable
/// "View cart (N) · total" bar once the cart has items.
class _StoreMinbar extends StatelessWidget {
  final CartState cart;
  const _StoreMinbar({required this.cart});

  @override
  Widget build(BuildContext context) {
    final count = cart.cartCount;
    final hasItems = count > 0;
    final ar = context.watch<LocaleState>().isArabic;
    // .minbar — always white; only the text/icon color switches to navy
    // when it's tappable (.minbar.go), never the background.
    final textColor = hasItems ? AppColors.navy : AppColors.ink;
    return GestureDetector(
      onTap: hasItems ? () => Navigator.pushNamed(context, Routes.cart) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        decoration: BoxDecoration(
          color: Colors.white,
          border: const Border(top: BorderSide(color: AppColors.line, width: 1)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(.06), blurRadius: 16, offset: const Offset(0, -4))],
        ),
        child: Row(
          children: [
            Text('🛍️', style: TextStyle(fontSize: 17, color: textColor)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                hasItems ? (ar ? 'عرض السلة ($count)' : 'View cart ($count)') : (ar ? 'ابدأ بإضافة 1.000 د.ك لتقديم طلبك!' : 'Start adding KWD 1.000 to place your order!'),
                style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 14),
              ),
            ),
            if (hasItems)
              Text(
                Formatters.money(cart.computeTotals().subtotal),
                style: const TextStyle(color: AppColors.navy, fontWeight: FontWeight.w700, fontSize: 14),
              ),
          ],
        ),
      ),
    );
  }
}

class _ProductRail extends StatelessWidget {
  final List products;
  final void Function(dynamic product) onTapProduct;
  const _ProductRail({required this.products, required this.onTapProduct});

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
      final ar = context.watch<LocaleState>().isArabic;
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(ar ? 'لا توجد نتائج' : 'No results', style: const TextStyle(color: AppColors.muted, fontSize: 13)),
        ),
      );
    }
    return SliverToBoxAdapter(
      child: SizedBox(
        height: 296,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: products.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (context, i) => SizedBox(
            width: 160,
            child: ProductCard(
              product: products[i],
              onTap: () => onTapProduct(products[i]),
            ),
          ),
        ),
      ),
    );
  }
}
