import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/async_state_view.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../state/auth_state.dart';
import '../../state/cart_state.dart';
import '../../state/locale_state.dart';
import '../widgets/product_card.dart';

class WishlistScreen extends StatefulWidget {
  const WishlistScreen({super.key});

  @override
  State<WishlistScreen> createState() => _WishlistScreenState();
}

class _WishlistScreenState extends State<WishlistScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthState>();
      if (auth.isSignedIn) context.read<CartState>().loadWishlistRemote(auth.userId!);
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final cart = context.watch<CartState>();
    final ar = context.watch<LocaleState>().isArabic;
    String t(String en, String arabic) => ar ? arabic : en;
    // Defensive wrap, not strictly required when shown as the Wishlist tab
    // (root_shell.dart already wraps the whole shell in Directionality) —
    // but this screen is ALSO reachable as its own standalone pushed route
    // (see Routes.wishlist in app_router.dart), which sits outside that
    // wrap entirely. Nesting an identical Directionality when already
    // inside one is a harmless no-op, so this is safe either way.
    final dir = ar ? TextDirection.rtl : TextDirection.ltr;

    if (!auth.isSignedIn) {
      return Directionality(
        textDirection: dir,
        child: Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.favorite_border_rounded, size: 56, color: AppColors.muted),
              const SizedBox(height: 14),
              Text(t('Sign in to see your wishlist', 'سجّل الدخول لعرض قائمة المفضلة'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.navy)),
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pushNamed(Routes.login),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.navy, foregroundColor: Colors.white),
                child: Text(t('Sign in', 'تسجيل الدخول')),
              ),
            ],
          ),
        ),
        ),
      );
    }

    if (cart.wishlistLoading && cart.wishlist.isEmpty) {
      return Directionality(textDirection: dir, child: LoadingView(message: t('Loading your wishlist…', 'جارٍ تحميل قائمة المفضلة…')));
    }

    final products = CatalogRepository.instance.products.where((p) => cart.isWished(p.id)).toList();

    if (products.isEmpty) {
      return Directionality(
        textDirection: dir,
        child: Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.favorite_border_rounded, size: 56, color: AppColors.muted),
              const SizedBox(height: 14),
              Text(t('Your wishlist is empty', 'قائمة المفضلة فارغة'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.navy)),
              const SizedBox(height: 6),
              Text(t('Tap the heart on any product to save it here', 'اضغط على القلب في أي منتج لحفظه هنا'), textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
              const SizedBox(height: 18),
              ElevatedButton(onPressed: () => Navigator.pushNamed(context, Routes.shop), child: Text(t('Browse shop', 'تصفح المتجر'))),
            ],
          ),
        ),
        ),
      );
    }

    return Directionality(
      textDirection: dir,
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: .50),
        itemCount: products.length,
        itemBuilder: (context, i) => ProductCard(
          product: products[i],
          onTap: () => Navigator.pushNamed(context, Routes.product, arguments: products[i].id),
        ),
      ),
    );
  }
}
