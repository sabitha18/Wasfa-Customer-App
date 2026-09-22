import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/network/api_exception.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/async_state_view.dart';
import '../../data/models/product.dart';
import '../../data/models/seller.dart';
import '../../state/auth_state.dart';
import '../../state/cart_state.dart';
import '../../state/locale_state.dart';
import '../../viewmodels/product_view_model.dart';
import '../widgets/product_image.dart';
import '../widgets/html_content.dart';
import '../widgets/review_sheet.dart';
import '../widgets/toast.dart';

class ProductScreen extends StatelessWidget {
  final int productId;
  final String? lockedToSeller;
  const ProductScreen({super.key, required this.productId, this.lockedToSeller});

  @override
  Widget build(BuildContext context) {
    final userId = context.read<AuthState>().userId;
    return ChangeNotifierProvider(
      create: (_) => ProductViewModel(productId: productId, lockedToSeller: lockedToSeller, userId: userId),
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
    final wished = cart.isWishedOrFallback(p.id, p.wishlistStatus);
    final ar = context.watch<LocaleState>().isArabic;
    String t(String en, String arabic) => ar ? arabic : en;

    return Directionality(
      textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
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
          ? LoadingView(message: t('Loading product…', 'جارٍ تحميل المنتج…'))
          : (vm.error != null && p.sellers.isEmpty)
              ? ErrorRetryView(message: vm.error!, onRetry: vm.load)
              : ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (vm.error != null) InlineErrorBanner(message: vm.error!, onRetry: vm.load),
          // .pdp-hero — height:220px, blush bg, 92px glyph. Now a gallery
          // when the PDP has more than one photo (confirmed live: `photos[]`
          // — this was never parsed or shown at all before, only the single
          // `image` field).
          _ProductGallery(product: p),
          Padding(
            // .pdp-body — padding:16px 16px 24px
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (p.isBogo)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(color: AppColors.rose, borderRadius: BorderRadius.circular(20)),
                      child: Text(
                        p.bogoDisplayLabel!,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
                      ),
                    ),
                  ),
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
                      '  ·  ${p.reviews} ${t("reviews", "تقييم")}${p.scientificName.isNotEmpty ? '  ·  ${p.scientificName}' : ''}',
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
                Text(t('Key benefits', 'الفوائد الرئيسية'), style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.navy)),
                const SizedBox(height: 10),
                // .benef — gap:7px, margin:4px 0 18px
                // Prefers the dashboard's real `tags` field (confirmed by the
                // client as the actual intended source for this section) —
                // falls back to the HTML prototype's category/concern/form
                // synthesis only for products that don't have tags set yet,
                // so this section doesn't just go blank for older/untagged
                // products.
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 18),
                  child: Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      for (final b in (p.tags.isNotEmpty ? p.tags : [p.category, p.concern, p.form]).where((b) => b.isNotEmpty))
                        _BenefitTag(text: b),
                    ],
                  ),
                ),
                // Per the confirmed business rule: the PDP always shows exactly
                // ONE pharmacy — picked automatically by ProductViewModel's
                // existing rules (cheapest in-stock seller by default, or
                // whichever pharmacy the person arrived from if they're
                // browsing that pharmacy's storefront — see
                // ProductViewModel.selectedSeller / lockedToSeller). There's
                // no picker here for the person to choose a different one —
                // that's only ever the result of the app's own selection
                // logic. This previously showed a "Choose your pharmacy (N)"
                // radio list whenever a product had more than one seller,
                // which contradicted that rule and let the person override
                // the pharmacy the app had already decided on.
                Text(
                  '🏪 ${t("Sold by", "يُباع بواسطة")} ${sel.name}',
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.navy),
                ),
                const SizedBox(height: 10),
                _LockedSeller(seller: sel),
                const SizedBox(height: 8),
                // .acc — bordered accordion box with +/- indicator (not a chevron)
                //
                // Used to be 3 boxes here — Description, How to use,
                // Ingredients — every one of them entirely fabricated text
                // (a sentence built from the product's own name/scientific-
                // name, and two generic boilerplate lines repeated
                // identically on every single product regardless of what
                // it actually was). A real PDP response has a genuine
                // `description` field with real product-specific HTML
                // content — including "how to use" info baked directly
                // into that same HTML (e.g. "...</p>How To Use:<p>Use
                // Twice aday</p>"), not as a separate field at all. So
                // rather than keep 2 more fabricated boxes alongside the
                // one real one, "How to use" and "Ingredients" (no real
                // field backs the latter either) were removed outright —
                // this single box now shows the actual real content, and
                // only appears at all when that content is non-empty.
                if (p.description.trim().isNotEmpty)
                  _AccordionBox(
                    title: t('Description', 'الوصف'),
                    child: HtmlBlocks(html: p.description),
                    initiallyOpen: true,
                  ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(t('Customer reviews', 'تقييمات العملاء'), style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.navy)),
                ),
                const SizedBox(height: 10),
                // .revsum — average rating + count are real fields
                // (`rating`/`reviews`, confirmed live on every product).
                // The 5-star breakdown bars used to show hardcoded
                // percentages (70/20/7/2/1) on EVERY product regardless of
                // its real rating — fake data with nothing behind it,
                // removed for that reason. Restored here with the same
                // visual design, but now computed for real from this
                // product's own `reviewList` (each real review's actual
                // star rating) — a product with zero reviews now correctly
                // shows every bar empty, rather than the old fake
                // distribution appearing regardless of review count.
                Builder(builder: (context) {
                  final counts = List.filled(6, 0); // index 1..5 used
                  for (final r in p.reviewList) {
                    if (r.rating >= 1 && r.rating <= 5) counts[r.rating]++;
                  }
                  // reviewList is what's actually available to count from;
                  // p.reviews is the server's own official total and may
                  // exceed it if reviews are ever paginated server-side —
                  // the bars reflect what's genuinely counted here, not a
                  // number reconstructed to match a total we can't see.
                  final counted = p.reviewList.length;
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${p.rating}', style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w700, color: AppColors.navy, height: 1)),
                        Text('${p.reviews} ${t("reviews", "تقييم")}', style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                      ]),
                      const SizedBox(width: 18),
                      Expanded(
                        child: Column(
                          children: [
                            for (var star = 5; star >= 1; star--)
                              Padding(
                                padding: EdgeInsets.only(bottom: star > 1 ? 5 : 0),
                                child: Row(children: [
                                  Text('$star★', style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(3),
                                      child: LinearProgressIndicator(
                                        value: counted > 0 ? counts[star] / counted : 0,
                                        backgroundColor: AppColors.cloud,
                                        color: AppColors.star,
                                        minHeight: 6,
                                      ),
                                    ),
                                  ),
                                ]),
                              ),
                          ],
                        ),
                      ),
                    ],
                  );
                }),
                // Real individual reviews — confirmed live on the PDP
                // (2026-09-17): each product's own `reviews[]` array
                // (reviewer name, their rating, their comment, date).
                // Never shown anywhere before this; the section above used
                // to be the only review-related content, just a bare
                // number with nothing under it.
                if (p.reviewList.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  for (final r in p.reviewList)
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(12)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                            Text(r.name.isNotEmpty ? r.name : t('Anonymous', 'مجهول'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: AppColors.navy)),
                            if (r.date != null) Text(Formatters.dateShort(r.date!), style: const TextStyle(fontSize: 10.5, color: AppColors.muted)),
                          ]),
                          const SizedBox(height: 3),
                          Row(children: List.generate(5, (i) => Icon(Icons.star_rounded, size: 14, color: i < r.rating ? AppColors.star : AppColors.cloud))),
                          if (r.comment.trim().isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(r.comment, style: const TextStyle(fontSize: 12.5, color: AppColors.ink, height: 1.4)),
                          ],
                        ],
                      ),
                    ),
                ],
                const SizedBox(height: 14),
                // Confirmed live (2026-09-17): `can_review`/`already_reviewed`
                // — the button used to show for literally any signed-in
                // person regardless of whether they'd ever ordered this
                // product, with zero eligibility check anywhere. Hidden
                // outright when ineligible, rather than shown-then-blocked
                // on tap, since there's nothing actionable for the person to
                // do about it right now (no "buy this to unlock reviewing"
                // flow) — a disabled/explained button would just be a dead
                // end. Already-reviewed gets its own distinct, non-actionable
                // note instead of vanishing silently, since that's a
                // different, worth-knowing reason than "not eligible at all".
                if (p.alreadyReviewed)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(12)),
                    child: Text(
                      t('You\'ve already reviewed this product', 'لقد قمت بتقييم هذا المنتج بالفعل'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.muted, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  )
                else if (p.canReview)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => openReviewSheet(context, sku: p.sku, productName: p.name(ar)),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: Colors.white,
                        side: const BorderSide(color: AppColors.navy, width: 1.5),
                        foregroundColor: AppColors.navy,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(t('Write a review', 'اكتب تقييماً'), style: const TextStyle(fontWeight: FontWeight.w700)),
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
                    cart.addToCartRemote(context, p, seller: sel.name, price: sel.price, was: sel.was, apiProductId: sel.productId, inStock: sel.stock);
                    showToast(
                      context,
                      t('Added to cart', 'أُضيف للسلة'),
                      actionLabel: t('View', 'عرض'),
                      onAction: () => Navigator.pushNamed(context, Routes.cart),
                    );
                  },
            child: Text(
              sel.stock ? '${t("Add to cart", "أضف للسلة")} · ${Formatters.money(sel.price)}' : t('Out of stock', 'غير متوفر'),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
          ),
        ),
      ),
      ),
    );
  }
}

/// .pdp-hero + gallery thumbnails — confirmed live: the PDP's `photos[]`
/// (its first entry is the same photo as the standalone `image` field, so
/// this uses `photos` as the complete gallery rather than showing `image`
/// separately from it). Falls back to the plain single-image [ProductImage]
/// when there's no gallery data at all, rather than showing an empty
/// thumbnail strip with nothing in it.
class _ProductGallery extends StatefulWidget {
  final Product product;
  const _ProductGallery({required this.product});

  @override
  State<_ProductGallery> createState() => _ProductGalleryState();
}

class _ProductGalleryState extends State<_ProductGallery> {
  int _index = 0;

  void _openFullScreen(int startIndex) {
    Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (context, _, __) => _FullScreenGallery(photos: widget.product.photos, initialIndex: startIndex),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final photos = widget.product.photos;
    if (photos.isEmpty) {
      return ProductImage(product: widget.product, height: 220, emojiSize: 92);
    }
    final heroUrl = photos[_index.clamp(0, photos.length - 1)];
    return Column(
      children: [
        GestureDetector(
          onTap: () => _openFullScreen(_index),
          child: SizedBox(
            height: 220,
            width: double.infinity,
            child: Image.network(
              heroUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(color: AppColors.blush),
            ),
          ),
        ),
        if (photos.length > 1)
          Container(
            color: AppColors.bg,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: photos.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (context, i) {
                  final selected = i == _index;
                  return GestureDetector(
                    onTap: () => setState(() => _index = i),
                    onDoubleTap: () => _openFullScreen(i),
                    child: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(color: selected ? AppColors.sky : AppColors.line, width: selected ? 2 : 1),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.network(
                          photos[i],
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(color: AppColors.blush),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}

/// Full-screen photo viewer, opened by tapping the hero image (or a
/// thumbnail). Swipeable between all of a product's photos, each
/// pinch-zoomable via [InteractiveViewer] (built into Flutter — no extra
/// package needed). Tap anywhere to dismiss.
class _FullScreenGallery extends StatefulWidget {
  final List<String> photos;
  final int initialIndex;
  const _FullScreenGallery({required this.photos, required this.initialIndex});

  @override
  State<_FullScreenGallery> createState() => _FullScreenGalleryState();
}

class _FullScreenGalleryState extends State<_FullScreenGallery> {
  late final PageController _controller = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            PageView.builder(
              controller: _controller,
              itemCount: widget.photos.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) => InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Center(
                  child: Image.network(
                    widget.photos[i],
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined, color: Colors.white38, size: 48),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8, right: 8,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
              ),
            ),
            if (widget.photos.length > 1)
              Positioned(
                bottom: 16,
                left: 0, right: 0,
                child: Text(
                  '${_index + 1} / ${widget.photos.length}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
          ],
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
    final ar = context.watch<LocaleState>().isArabic;
    final items = [
      (Icons.check_circle_rounded, ar ? 'منتج أصلي' : 'Genuine product'),
      (Icons.verified_rounded, ar ? 'معتمد من وزارة الصحة' : 'MoH approved'),
      (Icons.location_on_rounded, sel.stock ? (ar ? 'متوفر' : 'In stock') : (ar ? 'غير متوفر' : 'Out of stock')),
      (Icons.local_shipping_rounded, ar ? 'توصيل سريع' : 'Fast delivery'),
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
    final ar = context.watch<LocaleState>().isArabic;
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
                Text('🚚 ${seller.eta}   ${seller.stock ? (ar ? "🟢 متوفر" : "🟢 In stock") : (ar ? "⚪ غير متوفر" : "⚪ Out of stock")}', style: const TextStyle(fontSize: 11, color: AppColors.muted)),
              ],
            ),
          ),
          Text(Formatters.money(seller.price), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.navy)),
        ],
      ),
    );
  }
}

/// .acc — bordered box (border:line, radius:12), summary row with a
/// "+"/"−" text indicator (never a chevron), content padded 0/14/14.
class _AccordionBox extends StatefulWidget {
  final String title;
  final String? content;
  final Widget? child;
  final bool initiallyOpen;
  const _AccordionBox({required this.title, this.content, this.child, this.initiallyOpen = false}) : assert(content != null || child != null);

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
              child: widget.child ?? Text(widget.content!, style: const TextStyle(color: AppColors.muted, fontSize: 13, height: 1.6)),
            ),
        ],
      ),
    );
  }
}
