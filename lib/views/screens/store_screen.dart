import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/pharmacy_store.dart';
import '../../state/auth_state.dart';
import '../../state/cart_state.dart';
import '../../viewmodels/shop_view_model.dart';
import '../../viewmodels/store_view_model.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/product_card.dart';
import '../widgets/section_header.dart';
import 'brands_screen.dart';
import 'home_screen.dart' show PromoCard;
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

    return Scaffold(
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
                              child: const Icon(Icons.arrow_back_rounded, size: 19, color: AppColors.navy),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // .st-logo
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(colors: store.gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
                              borderRadius: BorderRadius.circular(11),
                            ),
                            alignment: Alignment.center,
                            child: Text(store.monogram, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.navy, height: 1.2)),
                          ),
                        ],
                      ),
                      // .freedel
                      Padding(
                        padding: const EdgeInsets.only(top: 10, bottom: 2),
                        child: Row(
                          children: [
                            const Icon(Icons.electric_moped, size: 16, color: AppColors.freeDeliveryOrange),
                            const SizedBox(width: 7),
                            const Text('Free delivery on your next order', style: TextStyle(color: AppColors.freeDeliveryOrange, fontSize: 13, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // .carousel — same 3-card promo pattern as Home, first card = this store
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: SizedBox(
                    height: 188,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                      children: [
                        PromoCard(
                          gradient: AppColors.promo1,
                          title: name,
                          subtitle: 'Genuine meds in 1 hour + doctors on demand',
                          cta: 'Explore',
                          onTap: () => _openShop(context),
                        ),
                        const SizedBox(width: 12),
                        PromoCard(
                          gradient: AppColors.promo2,
                          title: 'Free delivery in 1 hour',
                          subtitle: 'On orders of 3 items or more',
                          cta: 'Shop now',
                          onTap: () => _openShop(context),
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
              ),
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

              // .sec "Shop by category" + .catgrid — matches rStore(): the
              // category grid is the first section after the carousel, and
              // its header always renders (an empty catgrid just renders
              // nothing, same as the HTML's empty div when a store has no
              // categorised products).
              SliverToBoxAdapter(child: SectionHeader(title: 'Shop by category', actionLabel: 'See all', onAction: () => _openShop(context))),
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
              SliverToBoxAdapter(child: SectionHeader(title: 'Special offers', actionLabel: 'See all', onAction: () => _openShop(context, offersOnly: true))),
              _ProductRail(products: vm.offers, onTapProduct: (p) => Navigator.pushNamed(context, Routes.product, arguments: p.id)),

              // .sec "Best sellers" + .rail — same divergence as Special
              // offers above: See all passes bestSellersOnly instead of
              // opening the unfiltered catalogue.
              SliverToBoxAdapter(child: SectionHeader(title: 'Best sellers', actionLabel: 'See all', onAction: () => _openShop(context, bestSellersOnly: true))),
              _ProductRail(products: vm.bestSellers, onTapProduct: (p) => Navigator.pushNamed(context, Routes.product, arguments: p.id)),

              // .sec "Top brands" + .brand-rail
              SliverToBoxAdapter(
                child: SectionHeader(
                  title: 'Top brands',
                  actionLabel: 'See all',
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
                    ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text('No results', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                )
                    : SizedBox(
                  height: 62,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: vm.brandsInStore.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, i) => GestureDetector(
                      onTap: () => _openShop(context, brand: vm.brandsInStore[i]),
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 92),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(13), boxShadow: AppColors.shSm),
                        alignment: Alignment.center,
                        child: Text(vm.brandsInStore[i], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.navy, fontSize: 13)),
                      ),
                    ),
                  ),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 90)),
            ],
          ),
          // storeMinbar() — pinned to the bottom
          Positioned(left: 0, right: 0, bottom: 0, child: _StoreMinbar(cart: cart)),
        ],
      ),
    );
  }
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
                hasItems ? 'View cart ($count)' : 'Start adding KWD 1.000 to place your order!',
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
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text('No results', style: TextStyle(color: AppColors.muted, fontSize: 13)),
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
