import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/async_state_view.dart';
import '../../data/models/order.dart';
import '../../state/auth_state.dart';
import '../../state/cart_state.dart';
import '../../state/orders_state.dart';
import '../widgets/page_header.dart';
import '../widgets/toast.dart';
import 'order_detail_screen.dart';
import 'track_screen.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _load() {
    final auth = context.read<AuthState>();
    if (auth.isSignedIn) {
      context.read<OrdersState>().loadMyOrders(auth.userId!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final orders = context.watch<OrdersState>();

    if (!auth.isSignedIn) {
      return Scaffold(
        appBar: PageHeader(title: 'My orders'),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('📦', style: TextStyle(fontSize: 34)),
                const SizedBox(height: 10),
                const Text('Sign in to see your orders', style: TextStyle(color: AppColors.muted)),
                const SizedBox(height: 14),
                ElevatedButton(
                  onPressed: () async {
                    final ok = await Navigator.of(context).pushNamed('login');
                    if (ok == true) _load();
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.navy, foregroundColor: Colors.white),
                  child: const Text('Sign in'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: PageHeader(title: 'My orders'),
      body: RefreshIndicator(
        onRefresh: () => orders.loadMyOrders(auth.userId!),
        child: (orders.ordersLoading && orders.orders.isEmpty)
            ? const LoadingView(message: 'Loading your orders…')
            : (orders.ordersError != null && orders.orders.isEmpty)
                ? ErrorRetryView(message: orders.ordersError!, onRetry: () => orders.loadMyOrders(auth.userId!))
                : orders.orders.isEmpty
            ? ListView(children: const [
                SizedBox(height: 120),
                Center(child: Text('No orders yet', style: TextStyle(color: AppColors.muted))),
              ])
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: orders.orders.length + (orders.ordersError != null ? 1 : 0),
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, i) {
                  if (orders.ordersError != null && i == 0) {
                    return InlineErrorBanner(message: orders.ordersError!, onRetry: () => orders.loadMyOrders(auth.userId!));
                  }
                  final idx = orders.ordersError != null ? i - 1 : i;
                  return _OrderCard(order: orders.orders[idx]);
                },
              ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final Order order;
  const _OrderCard({required this.order});

  String get _statusLabel => {'prep': 'Preparing', 'way': 'On the way', 'done': 'Delivered'}[order.status] ?? 'Preparing';

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: order.id))),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: AppColors.shSm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(order.id, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(Formatters.dateShort(order.ts), style: const TextStyle(fontSize: 11, color: AppColors.muted)),
              ]),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: order.status == 'done' ? const Color(0xFFE7F8F0) : AppColors.blush, borderRadius: BorderRadius.circular(20)),
                child: Text(_statusLabel, style: TextStyle(color: order.status == 'done' ? AppColors.ok : AppColors.rose, fontWeight: FontWeight.w700, fontSize: 11)),
              ),
            ]),
            const SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(
                // pharmacyCount now falls back to the confirmed
                // "pharmacies" count from /my-orders when there's no
                // groups breakdown to count directly (the list endpoint's
                // shape) — no longer needs to omit this for list orders.
                order.pharmacyCount > 0
                    ? '${Formatters.money(order.total)} · ${order.itemCount} items · ${order.pharmacyCount} 🏪'
                    : '${Formatters.money(order.total)} · ${order.itemCount} items',
                style: const TextStyle(fontSize: 12.5),
              ),
              InkWell(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TrackScreen(orderId: order.id))),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('Track', style: TextStyle(color: AppColors.sky, fontWeight: FontWeight.w700, fontSize: 12.5)),
                  SizedBox(width: 3),
                  Icon(Icons.chevron_right_rounded, color: AppColors.sky, size: 16),
                ]),
              ),
            ]),
            if (order.status == 'done')
              // .oact — no space-between in the HTML (no flex on the
              // container at all), so these two sit adjacent on the left
              // rather than pushed to opposite ends.
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(children: [
                  InkWell(
                    onTap: () {
                      final r = context.read<OrdersState>().reorderInto(context.read<CartState>(), order.id);
                      final String msg;
                      if (r.added == 0) {
                        msg = 'These items are no longer available to reorder.';
                      } else if (r.skipped > 0) {
                        msg = 'Added ${r.added} item(s) to cart · ${r.skipped} no longer available';
                      } else {
                        msg = 'Added to cart';
                      }
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
                    },
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.add_rounded, size: 16, color: AppColors.navy),
                      SizedBox(width: 5),
                      Text('Reorder', style: TextStyle(color: AppColors.navy, fontWeight: FontWeight.w700, fontSize: 12.5)),
                    ]),
                  ),
                  const SizedBox(width: 18),
                  if (order.rating != null)
                    Text('${'★' * order.rating!}${'☆' * (5 - order.rating!)} Rated', style: const TextStyle(color: AppColors.star, fontWeight: FontWeight.w700, fontSize: 12))
                  else
                    InkWell(
                      onTap: () => _rate(context, order.id),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Text('⭐ ', style: TextStyle(fontSize: 12.5)),
                        Text('Rate order', style: TextStyle(color: AppColors.navy, fontWeight: FontWeight.w700, fontSize: 12.5)),
                      ]),
                    ),
                ]),
              ),
          ],
        ),
      ),
    );
  }

  void _rate(BuildContext context, String orderId) {
    int stars = 0;
    final reviewCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // .sh-h — title + close button, divider below
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line, width: 1))),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('⭐ Rate order', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: AppColors.navy)),
                  InkWell(
                    onTap: () => Navigator.pop(sheetContext),
                    borderRadius: BorderRadius.circular(9),
                    child: Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(9)),
                      alignment: Alignment.center,
                      child: const Icon(Icons.close_rounded, size: 18, color: AppColors.navy),
                    ),
                  ),
                ]),
              ),
              // .sh-b
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 6),
                child: Column(children: [
                  const Text('How was your experience with this order?', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: AppColors.muted)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (i) => IconButton(
                          onPressed: () => setState(() => stars = i + 1),
                          icon: Icon(Icons.star_rounded, color: stars > i ? AppColors.star : AppColors.cloud, size: 38),
                        )),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: reviewCtrl,
                    minLines: 3,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: 'Share your experience (optional)',
                      contentPadding: const EdgeInsets.all(11),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: AppColors.line)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: AppColors.line)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: AppColors.sky)),
                    ),
                  ),
                ]),
              ),
              // .sh-f
              Container(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line, width: 1))),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.navy, foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                    ),
                    // Always tappable — matching the HTML's submitRate(),
                    // which shows a toast rather than just disabling the
                    // button when nothing's picked yet (a disabled button
                    // absorbing taps silently is exactly what read as
                    // "submit does nothing").
                    onPressed: () async {
                      if (stars == 0) {
                        showErrorToast(sheetContext, 'Pick a rating');
                        return;
                      }
                      final userId = context.read<AuthState>().userId;
                      if (userId == null) return;
                      try {
                        await context.read<OrdersState>().rateOrder(orderId, stars, userId: userId, review: reviewCtrl.text.trim());
                        if (!sheetContext.mounted) return;
                        Navigator.pop(sheetContext);
                        showToast(context, 'Thanks for your feedback!');
                      } catch (e) {
                        if (sheetContext.mounted) showErrorToast(sheetContext, describeError(e));
                      }
                    },
                    child: const Text('Submit rating', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
