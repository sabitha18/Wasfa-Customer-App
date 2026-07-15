import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/async_state_view.dart';
import '../../data/models/order.dart';
import '../../state/auth_state.dart';
import '../../state/cart_state.dart';
import '../../state/orders_state.dart';
import '../widgets/page_header.dart';
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
              Text('${Formatters.money(order.total)} · ${order.itemCount} items · ${order.groups.length} 🏪', style: const TextStyle(fontSize: 12.5)),
              TextButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TrackScreen(orderId: order.id))),
                child: const Text('Track →'),
              ),
            ]),
            if (order.status == 'done')
              Row(children: [
                TextButton.icon(
                  onPressed: () {
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
                  icon: const Icon(Icons.replay_rounded, size: 16),
                  label: const Text('Reorder'),
                ),
                const Spacer(),
                if (order.rating != null)
                  Text('★' * order.rating! + '☆' * (5 - order.rating!), style: const TextStyle(color: AppColors.star))
                else
                  TextButton(onPressed: () => _rate(context, order.id), child: const Text('⭐ Rate order')),
              ]),
          ],
        ),
      ),
    );
  }

  void _rate(BuildContext context, String orderId) {
    int stars = 0;
    showModalBottomSheet(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('⭐ Rate your order', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (i) => IconButton(
                        onPressed: () => setState(() => stars = i + 1),
                        icon: Icon(Icons.star_rounded, color: stars > i ? AppColors.star : AppColors.cloud, size: 32),
                      )),
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: stars == 0
                      ? null
                      : () {
                          context.read<OrdersState>().rateOrder(orderId, stars);
                          Navigator.pop(context);
                        },
                  child: const Text('Submit rating'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
