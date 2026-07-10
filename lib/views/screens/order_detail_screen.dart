import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/async_state_view.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../state/auth_state.dart';
import '../../state/cart_state.dart';
import '../../state/orders_state.dart';
import '../widgets/page_header.dart';
import 'request_flow_screen.dart';
import 'track_screen.dart';

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
      _error = result == null ? 'Couldn\'t load this order.' : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final orders = context.watch<OrdersState>();
    final order = orders.byId(widget.orderId);

    if (_loading && order == null) {
      return Scaffold(appBar: PageHeader(title: 'Order details'), body: const LoadingView(message: 'Loading order…'));
    }
    if (order == null) {
      return Scaffold(
        appBar: PageHeader(title: 'Order details'),
        body: ErrorRetryView(message: _error ?? 'Order not found.', onRetry: _load),
      );
    }
    const labels = ['Confirmed', 'Preparing', 'On the way', 'Delivered'];
    final idx = {'conf': 0, 'prep': 1, 'way': 2, 'done': 3}[order.status] ?? 1;

    return Scaffold(
      appBar: PageHeader(title: 'Order details'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_error != null) InlineErrorBanner(message: _error!, onRetry: _load),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(order.id, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              Text(Formatters.dateShort(order.ts), style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
            ]),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: order.status == 'done' ? const Color(0xFFE7F8F0) : AppColors.blush, borderRadius: BorderRadius.circular(20)),
              child: Text(order.status == 'done' ? 'Delivered' : (order.status == 'way' ? 'On the way' : 'Preparing'),
                  style: TextStyle(color: order.status == 'done' ? AppColors.ok : AppColors.rose, fontWeight: FontWeight.w700, fontSize: 11)),
            ),
          ]),
          const SizedBox(height: 14),
          Row(children: [for (var i = 0; i < labels.length; i++) Expanded(child: _StepChip(label: labels[i], done: i <= idx))]),
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
                        Container(width: 40, height: 40, decoration: BoxDecoration(color: AppColors.blush, borderRadius: BorderRadius.circular(9)), alignment: Alignment.center, child: Text(it.productId != null ? (CatalogRepository.instance.findProduct(it.productId!)?.emoji ?? '📦') : '📦')),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(it.productId != null ? (CatalogRepository.instance.findProduct(it.productId!)?.nameEn ?? '#${it.productId}') : 'Item', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                              Text('×${it.qty} · ${Formatters.money(it.price)}', style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                            ],
                          ),
                        ),
                        Text(Formatters.money(it.price * it.qty), style: const TextStyle(fontWeight: FontWeight.w700)),
                      ]),
                    ),
                ],
              ),
            ),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Total', style: TextStyle(fontWeight: FontWeight.w700)),
            Text(Formatters.money(order.total), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.navy)),
          ]),
          if (order.cancelRequest != null) _RequestBanner(label: 'Cancellation request', status: order.cancelRequest!.status),
          if (order.returnRequest != null) _RequestBanner(label: 'Return request', status: order.returnRequest!.status),
          const SizedBox(height: 16),
          Row(children: [
            if (order.status == 'done')
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    context.read<OrdersState>().reorderInto(context.read<CartState>(), order.id);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Added to cart')));
                  },
                  icon: const Icon(Icons.replay_rounded, size: 16),
                  label: const Text('Reorder'),
                ),
              ),
            if (order.status == 'done') const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TrackScreen(orderId: order.id))),
                child: const Text('Track'),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          if (order.status != 'done' && order.cancelRequest == null)
            OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger, side: const BorderSide(color: AppColors.danger)),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RequestFlowScreen(orderId: order.id, type: 'cancel'))),
              child: const Text('Cancel order'),
            ),
          if (order.status == 'done' && order.returnRequest == null)
            OutlinedButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RequestFlowScreen(orderId: order.id, type: 'return'))),
              child: const Text('↩︎ Return / refund'),
            ),
        ],
      ),
    );
  }
}

class _StepChip extends StatelessWidget {
  final String label;
  final bool done;
  const _StepChip({required this.label, required this.done});
  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(height: 4, decoration: BoxDecoration(color: done ? AppColors.navy : AppColors.cloud, borderRadius: BorderRadius.circular(4))),
      const SizedBox(height: 6),
      Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 9.5, color: done ? AppColors.navy : AppColors.muted, fontWeight: FontWeight.w600)),
    ]);
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
