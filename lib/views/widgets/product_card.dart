import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/product.dart';
import '../../state/cart_state.dart';
import '../../state/locale_state.dart';
import '../widgets/toast.dart';
import 'product_image.dart';

class ProductCard extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;

  const ProductCard({
    super.key,
    required this.product,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartState>();
    final locale = context.watch<LocaleState>();
    final wished = cart.isWishedOrFallback(product.id, product.wishlistStatus);
    final price = product.bestPrice;
    final was = product.bestWasPrice;

    String? badgeText;
    Color badgeColor = AppColors.rose;
    if (product.tag != null) {
      badgeText = product.tag;
      badgeColor = AppColors.blush;
    } else if (was != null) {
      final off = (100 - (price / was * 100)).round();
      badgeText = '-$off%';
      badgeColor = AppColors.blush;
    } else if (product.isNew) {
      badgeText = locale.isArabic ? 'جديد' : 'New';
      badgeColor = AppColors.aqua;
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppColors.shSm,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ProductImage(product: product, height: 110),
                if (badgeText != null)
                  Positioned(
                    left: 9,
                    top: 9,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: badgeColor == AppColors.blush ? AppColors.blush : badgeColor,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(badgeText,
                          style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: badgeColor == AppColors.blush ? AppColors.rose : Colors.white)),
                    ),
                  ),
                Positioned(
                  right: 8,
                  top: 8,
                  child: GestureDetector(
                    onTap: () => cart.toggleWishRemote(context, product),
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(.92),
                        shape: BoxShape.circle,
                        boxShadow: AppColors.shSm,
                      ),
                      child: Icon(
                        wished ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                        size: 16,
                        color: wished ? AppColors.rose : AppColors.muted,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(11, 9, 11, 9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product.brand.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.sky, letterSpacing: .3)),
                  const SizedBox(height: 3),
                  SizedBox(
                    height: 32,
                    child: Text(
                      product.name(locale.isArabic),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.ink, height: 1.25),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${product.rating} ★',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10, color: AppColors.muted),
                  ),
                  const SizedBox(height: 3),
                  Builder(builder: (context) {
                    final s = product.defaultSeller;
                    // The PLP response has no seller/pharmacy-name field at
                    // all for single-seller items — Product.fromJson's
                    // synthesized seller falls back to the literal string
                    // 'WASFA' when none is given. Showing that as if it
                    // were a real pharmacy name would be fabricated info,
                    // so this line only renders when there's something
                    // genuine to show.
                    //
                    // Always shows the actual pharmacy name (the same one
                    // the PDP would show as "Sold by X" — see
                    // ProductViewModel/Product.defaultSeller's "locked
                    // seller" rule), even when there's more than one seller
                    // for this product. This used to show "N pharmacies"
                    // (a bare count) instead whenever sellerCount > 1,
                    // which contradicted that same rule: the PDP never
                    // shows a picker or a count, just the one pharmacy
                    // that's actually been selected — the card shouldn't
                    // either.
                    final label = s.name != 'WASFA' ? '🏪 ${s.name}' : null;
                    if (label == null) return const SizedBox(height: 10);
                    return Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10, color: AppColors.muted),
                    );
                  }),
                  const SizedBox(height: 4),
                  // .pr — reserve space for 2 lines (price, then strike-through
                  // price below if it doesn't fit alongside) so wrapping can't
                  // change the card's total height and reintroduce overflow.
                  SizedBox(
                    height: 34,
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        children: [
                          Text(Formatters.money(price), style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.navy)),
                          if (was != null)
                            Text(Formatters.money(was), style: const TextStyle(fontSize: 11, color: AppColors.muted, decoration: TextDecoration.lineThrough)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Builder(builder: (context) {
                    final s = product.defaultSeller;
                    final key = '${product.id}_${s.name}';
                    // Deferred to after this frame — seeding (if it does
                    // anything at all) calls notifyListeners, which
                    // shouldn't happen synchronously mid-build.
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      cart.seedCartStatusOnce(product, seller: s.name, price: s.price, was: s.was, apiProductId: s.productId, cartStatus: product.cartStatus);
                    });
                    final qty = cart.cart[key]?.qty ?? 0;
                    final outOfStock = !s.stock;
                    if (qty > 0) {
                      // .qstep — full-width stepper replaces the button entirely once in cart.
                      // "+" is disabled (but "-"/remove stays available) if stock ran out
                      // after this line was already added.
                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                        decoration: BoxDecoration(color: AppColors.sky, borderRadius: BorderRadius.circular(11)),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            StepBtn(icon: Icons.remove_rounded, onTap: () => cart.setQtyRemote(context, key, -1)),
                            Text('$qty', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                            StepBtn(
                              icon: Icons.add_rounded,
                              onTap: outOfStock
                                  ? null
                                  : () => cart.addToCartRemote(context, product, seller: s.name, price: s.price, was: s.was, apiProductId: s.productId),
                            ),
                          ],
                        ),
                      );
                    }
                    if (outOfStock) {
                      return SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.line,
                            disabledBackgroundColor: AppColors.line,
                            minimumSize: const Size.fromHeight(32),
                            padding: EdgeInsets.zero,
                            textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: Text(locale.isArabic ? 'غير متوفر' : 'Out of stock', style: const TextStyle(color: AppColors.muted)),
                        ),
                      );
                    }
                    return SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          cart.addToCartRemote(context, product, seller: s.name, price: s.price, was: s.was, apiProductId: s.productId);
                          showToast(context, locale.isArabic ? 'أُضيف للسلة' : 'Added to cart');
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.sky,
                          minimumSize: const Size.fromHeight(32),
                          padding: EdgeInsets.zero,
                          textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: Text(locale.isArabic ? 'أضف للسلة' : 'Add to cart'),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small +/- tap target inside the `.qstep` cart quantity stepper.
/// Pass `onTap: null` to show it disabled (dimmed, non-interactive) — used
/// for "+" once a product's stock runs out after it's already in the cart.
class StepBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const StepBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        child: Icon(icon, color: onTap == null ? Colors.white.withOpacity(.4) : Colors.white, size: 16),
      ),
    );
  }
}
