import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/order.dart';
import '../../state/orders_state.dart';
import '../widgets/page_header.dart';
import 'order_detail_screen.dart';

class RequestsScreen extends StatelessWidget {
  const RequestsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final orders = context.watch<OrdersState>();
    final entries = <MapEntry<Order, MapEntry<String, OrderRequest>>>[];
    for (final o in orders.orders) {
      if (o.cancelRequest != null) entries.add(MapEntry(o, MapEntry('cancel', o.cancelRequest!)));
      if (o.returnRequest != null) entries.add(MapEntry(o, MapEntry('return', o.returnRequest!)));
    }
    entries.sort((a, b) => b.value.value.ts.compareTo(a.value.value.ts));

    return Scaffold(
      appBar: PageHeader(title: 'My requests'),
      body: entries.isEmpty
          ? const Center(child: Text('No requests yet', style: TextStyle(color: AppColors.muted)))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: entries.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final order = entries[i].key;
                final type = entries[i].value.key;
                final req = entries[i].value.value;
                return GestureDetector(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: order.id))),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: AppColors.shSm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          Text('${type == 'cancel' ? '⛔' : '↩︎'} ${type == 'cancel' ? 'Cancellation' : 'Return'} · ${order.id}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                            decoration: BoxDecoration(color: AppColors.blush, borderRadius: BorderRadius.circular(16)),
                            child: Text(req.status, style: const TextStyle(color: AppColors.rose, fontWeight: FontWeight.w700, fontSize: 10.5)),
                          ),
                        ]),
                        if (req.reason.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(req.reason, style: const TextStyle(color: AppColors.muted, fontSize: 12))),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
