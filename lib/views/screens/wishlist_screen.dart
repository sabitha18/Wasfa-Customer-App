import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/async_state_view.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../state/auth_state.dart';
import '../../state/cart_state.dart';
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

    if (!auth.isSignedIn) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.favorite_border_rounded, size: 56, color: AppColors.muted),
              const SizedBox(height: 14),
              const Text('Sign in to see your wishlist', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.navy)),
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pushNamed(Routes.login),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.navy, foregroundColor: Colors.white),
                child: const Text('Sign in'),
              ),
            ],
          ),
        ),
      );
    }

    if (cart.wishlistLoading && cart.wishlist.isEmpty) {
      return const LoadingView(message: 'Loading your wishlist…');
    }

    final products = CatalogRepository.instance.products.where((p) => cart.isWished(p.id)).toList();

    if (products.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.favorite_border_rounded, size: 56, color: AppColors.muted),
              const SizedBox(height: 14),
              const Text('Your wishlist is empty', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.navy)),
              const SizedBox(height: 6),
              const Text('Tap the heart on any product to save it here', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 13)),
              const SizedBox(height: 18),
              ElevatedButton(onPressed: () => Navigator.pushNamed(context, Routes.shop), child: const Text('Browse shop')),
            ],
          ),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: .50),
      itemCount: products.length,
      itemBuilder: (context, i) => ProductCard(
        product: products[i],
        onTap: () => Navigator.pushNamed(context, Routes.product, arguments: products[i].id),
      ),
    );
  }
}
