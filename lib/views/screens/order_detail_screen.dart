import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/async_state_view.dart';
import '../../data/models/order.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../state/address_state.dart';
import '../../state/auth_state.dart';
import '../../state/cart_state.dart';
import '../../state/locale_state.dart';
import '../../state/orders_state.dart';
import '../widgets/page_header.dart';
import '../widgets/review_sheet.dart';
import 'request_flow_screen.dart';
import 'track_screen.dart';

/// `OrderAddress.formatted` skips the area name entirely when it's blank
/// — true for a real `/acct/order/{code}` response (2026-09-18) where
/// `governorate`/`area` come back as bare numeric ids with no name
/// anywhere in that object at all (see OrderAddress.fromJson's doc).
/// Resolves the real name from the area catalog (already loaded
/// elsewhere, for delivery-fee purposes) in that case, reusing
/// `formatted`'s own block/street/building join for the rest rather than
/// re-implementing it here too.
String _formattedDeliveryAddress(BuildContext context, OrderAddress a) {
  final rest = a.formatted;
  if (a.areaName.trim().isNotEmpty || a.areaId == null) return rest;
  final area = context.read<AddressState>().areaCatalog.findArea(a.areaId!);
  if (area == null) return rest;
  final name = area.label(context.read<LocaleState>().isArabic);
  return rest.isEmpty ? name : '$name, $rest';
}

class OrderDetailScreen extends StatefulWidget {
  final String orderId;
  const OrderDetailScreen({super.key, required this.orderId});

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final ar = context.read<LocaleState>().isArabic;
    final auth = context.read<AuthState>();
    if (!auth.isSignedIn) {
      setState(() => _loading = false);
      return;
    }
    setState(() { _loading = true; _error = null; });
    final result = await context.read<OrdersState>().loadOrderDetail(code: widget.orderId, userId: auth.userId!);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = result == null ? (ar ? 'تعذر تحميل هذا الطلب.' : 'Couldn\'t load this order.') : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final orders = context.watch<OrdersState>();
    final order = orders.byId(widget.orderId);
    final ar = context.watch<LocaleState>().isArabic;
    String t(String en, String arabic) => ar ? arabic : en;

    if (_loading && order == null) {
      return Directionality(
        textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
        child: Scaffold(appBar: PageHeader(title: t('Order details', 'تفاصيل الطلب')), body: LoadingView(message: t('Loading order…', 'جارٍ تحميل الطلب…'))),
      );
    }
    if (order == null) {
      return Directionality(
        textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
        child: Scaffold(
        appBar: PageHeader(title: t('Order details', 'تفاصيل الطلب')),
        body: ErrorRetryView(message: _error ?? t('Order not found.', 'لم يتم العثور على الطلب.'), onRetry: _load),
        ),
      );
    }
    // Matches the HTML's labels array — st_conf/st_prep/st_way/st_done.
    final labels = [
      t('Order confirmed', 'تم تأكيد الطلب'),
      t('Preparing your order', 'جارٍ تحضير طلبك'),
      t('On the way', 'في الطريق'),
      t('Delivered', 'تم التوصيل'),
    ];
    final idx = {'conf': 0, 'prep': 1, 'way': 2, 'done': 3}[order.status] ?? 1;

    return Directionality(
      textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
      backgroundColor: AppColors.bg,
      appBar: PageHeader(title: t('Order details', 'تفاصيل الطلب')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_error != null) InlineErrorBanner(message: _error!, onRetry: _load),
          // A cached summary (e.g. from the Orders list, already in
          // OrdersState before this screen even opened) shows immediately
          // — good for perceived speed, but it meant the full-detail fetch
          // that follows had NO visible loading indicator at all: the
          // full-screen LoadingView above only fires when there's no
          // cached order yet, so opening any order you'd already seen on
          // the list just silently showed the (possibly lighter/stale)
          // cached summary with nothing to indicate a fresher fetch was
          // even happening in the background.
          if (_loading)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(children: [
                const SizedBox(
                  width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(AppColors.sky)),
                ),
                const SizedBox(width: 8),
                Text(t('Refreshing…', 'جارٍ التحديث…'), style: const TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w600)),
              ]),
            ),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(order.id, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              Text(Formatters.dateShort(order.ts), style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
            ]),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: order.status == 'done' ? const Color(0xFFE7F8F0) : AppColors.blush, borderRadius: BorderRadius.circular(20)),
              child: Text(order.status == 'done' ? t('Delivered', 'تم التوصيل') : (order.status == 'way' ? t('On the way', 'في الطريق') : t('Preparing', 'قيد التحضير')),
                  style: TextStyle(color: order.status == 'done' ? AppColors.ok : AppColors.rose, fontWeight: FontWeight.w700, fontSize: 11)),
            ),
          ]),
          const SizedBox(height: 14),
          // .timeline — vertical dot + connecting line, not horizontal bars
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), boxShadow: AppColors.shSm),
            child: Column(
              children: [for (var i = 0; i < labels.length; i++) _TimelineStep(label: labels[i], done: i < idx, current: i == idx, isLast: i == labels.length - 1)],
            ),
          ),
          const SizedBox(height: 16),
          for (final g in order.groups)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: AppColors.shSm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(padding: const EdgeInsets.fromLTRB(14, 12, 14, 6), child: Text('🏪 ${g.pharmacy}', style: const TextStyle(fontWeight: FontWeight.w700))),
                  for (final it in g.items)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                      child: Row(children: [
                        Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(color: AppColors.blush, borderRadius: BorderRadius.circular(9)),
                          alignment: Alignment.center,
                          child: (it.imageUrl != null && it.imageUrl!.isNotEmpty)
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(9),
                                  child: Image.network(
                                    it.imageUrl!,
                                    width: 40, height: 40,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Prefer the server's own line-item name; only fall
                              // back to a catalog lookup / id when it's absent.
                              Text(
                                it.name.isNotEmpty
                                    ? it.name
                                    : (it.productId != null
                                        ? (CatalogRepository.instance.findProduct(it.productId!)?.nameEn ?? '#${it.productId}')
                                        : t('Item', 'عنصر')),
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                              ),
                              Text('×${it.qty} · ${Formatters.money(it.price)}', style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                              if (it.restricted) ...[
                                const SizedBox(height: 3),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(color: AppColors.blush, borderRadius: BorderRadius.circular(6)),
                                  child: Text(t('Restricted · Pickup Only', 'مقيّد · استلام فقط'), style: const TextStyle(color: AppColors.rose, fontSize: 10, fontWeight: FontWeight.w700)),
                                ),
                              ],
                              if (!it.restricted && !it.inStock) ...[
                                // Confirmed live (`in_stock`) across product/cart/
                                // order/rx responses (2026-07-29). This order's own
                                // line is already fulfilled regardless — this only
                                // means reordering it specifically isn't offered
                                // (see OrdersState.reorderInto, which now skips it).
                                const SizedBox(height: 3),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(color: AppColors.blush, borderRadius: BorderRadius.circular(6)),
                                  child: Text(t('Out of stock', 'غير متوفر'), style: const TextStyle(color: AppColors.rose, fontSize: 10, fontWeight: FontWeight.w700)),
                                ),
                              ],
                              // A second, inherently-verified way to leave a
                              // product review (confirmed live `sku` on
                              // order items, 2026-09-18) — getting here at
                              // all means this item is in an order that's
                              // actually this person's own and actually
                              // delivered, so no separate can_review check
                              // is needed the way the PDP's own review
                              // button requires. Prefers this line's own
                              // item_status over the whole order's status,
                              // since a multi-pharmacy order can have some
                              // items delivered before others.
                              if ((it.itemStatus?.toLowerCase() == 'delivered' || (it.itemStatus == null && order.status == 'done')) && (it.sku?.isNotEmpty ?? false))
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: GestureDetector(
                                    onTap: () => openReviewSheet(context, sku: it.sku!, productName: it.name),
                                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                                      const Icon(Icons.star_border_rounded, size: 13, color: AppColors.sky),
                                      const SizedBox(width: 3),
                                      Text(t('Review this item', 'قيّم هذا المنتج'), style: const TextStyle(color: AppColors.sky, fontSize: 11, fontWeight: FontWeight.w700)),
                                    ]),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Text(Formatters.money(it.price * it.qty), style: const TextStyle(fontWeight: FontWeight.w700)),
                      ]),
                    ),
                ],
              ),
            ),
          Builder(builder: (context) {
            // "Items total" used to just show order.total directly — which
            // already includes delivery and any discount, so the label was
            // wrong regardless. Now a real breakdown, using delivery_charge
            // and discount (confirmed live, 2026-07-31, neither parsed
            // before this).
            final subtotal = order.allItems.fold(0.0, (s, it) => s + it.price * it.qty);
            return Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(t('Subtotal', 'المجموع الفرعي'), style: const TextStyle(fontSize: 13, color: AppColors.muted)),
                Text(Formatters.money(subtotal), style: const TextStyle(fontSize: 13, color: AppColors.ink)),
              ]),
              const SizedBox(height: 4),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(t('Delivery', 'التوصيل'), style: const TextStyle(fontSize: 13, color: AppColors.muted)),
                Text(order.deliveryCharge == 0 ? t('Free', 'مجاني') : Formatters.money(order.deliveryCharge), style: const TextStyle(fontSize: 13, color: AppColors.ink)),
              ]),
              if (order.discount > 0) ...[
                const SizedBox(height: 4),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(t('Discount', 'الخصم'), style: const TextStyle(fontSize: 13, color: AppColors.muted)),
                  Text('−${Formatters.money(order.discount)}', style: const TextStyle(fontSize: 13, color: AppColors.rose, fontWeight: FontWeight.w700)),
                ]),
              ],
              const SizedBox(height: 4),
              // Confirmed live (payment_method/payment_type, 2026-07-31) —
              // never shown anywhere before this.
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(t('Payment', 'الدفع'), style: const TextStyle(fontSize: 13, color: AppColors.muted)),
                Row(children: [
                  Text(order.payLabel(ar), style: const TextStyle(fontSize: 13, color: AppColors.ink)),
                  if (order.paymentStatus != null) ...[
                    const SizedBox(width: 5),
                    Text(
                      '· ${order.paymentStatus == 'paid' ? t('Paid', 'مدفوع') : t('Unpaid', 'غير مدفوع')}',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: order.paymentStatus == 'paid' ? AppColors.ok : AppColors.rose),
                    ),
                  ],
                ]),
              ]),
              const SizedBox(height: 8),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(t('Total', 'الإجمالي'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.navy)),
                Text(Formatters.money(order.total), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: AppColors.navy)),
              ]),
            ]);
          }),
          if (order.deliveryAddress != null) ...[
            const SizedBox(height: 16),
            // The delivery address embedded directly on this order's own
            // response (confirmed live, 2026-07-31) — a snapshot of where
            // it was actually sent, never shown anywhere before this.
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: AppColors.shSm),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t('Delivered to', 'تم التوصيل إلى'), style: const TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text(order.deliveryAddress!.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: AppColors.navy)),
                const SizedBox(height: 2),
                Text(_formattedDeliveryAddress(context, order.deliveryAddress!), style: const TextStyle(fontSize: 12.5, color: AppColors.ink, height: 1.4)),
                const SizedBox(height: 2),
                Text(order.deliveryAddress!.phone, style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
              ]),
            ),
          ],
          if (order.buildingPhotos.isNotEmpty) ...[
            const SizedBox(height: 16),
            // Reference photos of the delivery location — confirmed live
            // (2026-09-18), never shown anywhere before this. Likely taken
            // by the rider on a previous delivery, for whoever delivers
            // here next to find the right building/entrance.
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: AppColors.shSm),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t('Building photos', 'صور المبنى'), style: const TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                SizedBox(
                  height: 84,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: order.buildingPhotos.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, i) {
                      final photo = order.buildingPhotos[i];
                      return GestureDetector(
                        onTap: () => showDialog(
                          context: context,
                          builder: (_) => Dialog(
                            backgroundColor: Colors.black,
                            insetPadding: const EdgeInsets.all(12),
                            child: InteractiveViewer(
                              child: Image.network(photo.url, errorBuilder: (_, __, ___) => const SizedBox(height: 200)),
                            ),
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(
                            photo.url,
                            width: 84, height: 84,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(width: 84, height: 84, color: AppColors.bg),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ]),
            ),
          ],
          for (final entry in order.cancelStatusGroups.entries)
            _RequestBanner(label: t('Cancellation request (${entry.value.length} item${entry.value.length == 1 ? '' : 's'})', 'طلب إلغاء (${entry.value.length} عنصر)'), status: entry.key),
          for (final entry in order.returnStatusGroups.entries)
            _RequestBanner(label: t('Return request (${entry.value.length} item${entry.value.length == 1 ? '' : 's'})', 'طلب إرجاع (${entry.value.length} عنصر)'), status: entry.key),
          const SizedBox(height: 16),
          Row(children: [
            if (order.status == 'done')
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    final r = context.read<OrdersState>().reorderInto(context.read<CartState>(), order.id);
                    final messenger = ScaffoldMessenger.of(context);
                    final String msg;
                    if (r.added == 0) {
                      msg = t('These items are no longer available to reorder.', 'هذه العناصر لم تعد متوفرة لإعادة الطلب.');
                    } else if (r.skipped > 0) {
                      // Was "... no longer available" unconditionally — now
                      // covers restricted (pickup-only) items too, which
                      // ARE still available, just not through cart reorder.
                      msg = t('Added ${r.added} item(s) to cart · ${r.skipped} couldn\'t be reordered', 'تمت إضافة ${r.added} عنصر إلى السلة · تعذر إعادة طلب ${r.skipped}');
                    } else {
                      msg = t('Added to cart', 'أُضيف للسلة');
                    }
                    messenger.showSnackBar(SnackBar(content: Text(msg)));
                    if (r.added > 0) Navigator.pushNamed(context, Routes.cart);
                  },
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: Text(t('Reorder', 'إعادة الطلب')),
                ),
              ),
            if (order.status == 'done') const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TrackScreen(orderId: order.id))),
                child: Text(t('Track', 'تتبع')),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          // "Cancel order"/"Return / Refund request" stay visible and
          // tappable as long as there's at least one item not yet covered
          // by SOME submitted request — someone can request 2 of 5 items,
          // and still be able to come back and request the other 3 later.
          // The button only disappears once every item has been covered.
          if (order.status != 'done' && order.remainingForCancel.isNotEmpty)
            OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger, side: const BorderSide(color: AppColors.danger)),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RequestFlowScreen(orderId: order.id, type: 'cancel'))),
              child: Text(t('Cancel order', 'إلغاء الطلب')),
            ),
          if (order.status == 'done' && order.remainingForReturn.isNotEmpty)
            OutlinedButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RequestFlowScreen(orderId: order.id, type: 'return'))),
              icon: const Icon(Icons.assignment_return_outlined, size: 16),
              label: Text(t('Return / Refund request', 'طلب إرجاع / استرداد')),
            ),
        ],
      ),
      ),
    );
  }
}

/// Matches `.tstep`: a dot (filled + checkmark once done, sky glow ring when
/// current, hollow otherwise) connected to the next step by a vertical line,
/// with the label to the right.
class _TimelineStep extends StatelessWidget {
  final String label;
  final bool done;
  final bool current;
  final bool isLast;
  const _TimelineStep({required this.label, required this.done, required this.current, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final dotColor = done ? AppColors.ok : (current ? AppColors.sky : AppColors.bg);
    final dotBorder = done ? AppColors.ok : (current ? AppColors.sky : AppColors.line);
    final labelColor = (done || current) ? AppColors.navy : AppColors.muted;
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Column(children: [
          Container(
            width: 24, height: 24,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
              border: Border.all(color: dotBorder, width: 2),
              boxShadow: current ? [BoxShadow(color: AppColors.sky.withOpacity(.18), blurRadius: 0, spreadRadius: 4)] : null,
            ),
            alignment: Alignment.center,
            child: done ? const Icon(Icons.check_rounded, size: 14, color: Colors.white) : null,
          ),
          if (!isLast) Expanded(child: Container(width: 2, color: done ? AppColors.ok : AppColors.line)),
        ]),
        const SizedBox(width: 12),
        Padding(
          padding: EdgeInsets.only(bottom: isLast ? 0 : 20),
          child: Text(label, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: labelColor)),
        ),
      ]),
    );
  }
}

class _RequestBanner extends StatelessWidget {
  final String label;
  final String status;
  const _RequestBanner({required this.label, required this.status});
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.blush, borderRadius: BorderRadius.circular(12)),
      child: Text('$label · ${status[0].toUpperCase()}${status.substring(1)}', style: const TextStyle(color: AppColors.rose, fontWeight: FontWeight.w700, fontSize: 12.5)),
    );
  }
}
