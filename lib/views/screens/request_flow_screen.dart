import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../state/orders_state.dart';
import '../widgets/page_header.dart';

/// A single screen that walks through the 3-step cancel/return flow using
/// an internal PageView — equivalent to the three separate HTML screens
/// (rReqItems -> rReqReason -> rReqDone) but easier to maintain as one
/// self-contained flow in Flutter.
class RequestFlowScreen extends StatefulWidget {
  final String orderId;
  final String type; // 'cancel' | 'return'
  const RequestFlowScreen({super.key, required this.orderId, required this.type});

  @override
  State<RequestFlowScreen> createState() => _RequestFlowScreenState();
}

class _RequestFlowScreenState extends State<RequestFlowScreen> {
  final _page = PageController();
  int _step = 0;
  final Set<String> _selected = {};
  String? _reason;
  final _noteController = TextEditingController();

  bool get isReturn => widget.type == 'return';

  List<String> get _reasons => isReturn
      ? ['Wrong item', 'Damaged', 'Expired', 'Not as described', 'Changed mind', 'Other']
      : ['Ordered by mistake', 'Found better price', 'Taking too long', 'Need to change order', 'Other'];

  @override
  void initState() {
    super.initState();
    final order = context.read<OrdersState>().byId(widget.orderId);
    if (order != null) {
      for (var gi = 0; gi < order.groups.length; gi++) {
        for (var ii = 0; ii < order.groups[gi].items.length; ii++) {
          _selected.add('${gi}_$ii');
        }
      }
    }
  }

  void _goTo(int step) {
    setState(() => _step = step);
    _page.animateToPage(step, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  void _submit() {
    context.read<OrdersState>().startRequest(widget.orderId, widget.type, reason: _reason ?? 'other', note: _noteController.text);
    _goTo(2);
  }

  @override
  Widget build(BuildContext context) {
    final order = context.read<OrdersState>().byId(widget.orderId);
    if (order == null) return const Scaffold(body: Center(child: Text('Order not found')));

    return Scaffold(
      appBar: PageHeader(title: isReturn ? 'Return / refund' : 'Cancel order'),
      body: PageView(
        controller: _page,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          // Step 1 — pick items
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(isReturn ? 'Select the items to return' : 'Select the items to cancel', style: const TextStyle(color: AppColors.muted, fontSize: 13)),
              const SizedBox(height: 12),
              for (var gi = 0; gi < order.groups.length; gi++)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: AppColors.shSm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(padding: const EdgeInsets.fromLTRB(14, 12, 14, 4), child: Text('🏪 ${order.groups[gi].pharmacy}', style: const TextStyle(fontWeight: FontWeight.w700))),
                      for (var ii = 0; ii < order.groups[gi].items.length; ii++)
                        CheckboxListTile(
                          value: _selected.contains('${gi}_$ii'),
                          title: Text(order.groups[gi].items[ii].productId != null
                              ? (CatalogRepository.instance.findProduct(order.groups[gi].items[ii].productId!)?.nameEn ?? '#${order.groups[gi].items[ii].productId}')
                              : 'Item'),
                          subtitle: Text('×${order.groups[gi].items[ii].qty} · ${Formatters.money(order.groups[gi].items[ii].price)}'),
                          onChanged: (v) => setState(() {
                            final key = '${gi}_$ii';
                            if (v == true) {
                              _selected.add(key);
                            } else {
                              _selected.remove(key);
                            }
                          }),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: _selected.isEmpty ? null : () => _goTo(1),
                child: Text('Continue (${_selected.length})'),
              ),
            ],
          ),
          // Step 2 — reason
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(isReturn ? 'Why are you returning these items?' : 'Why are you cancelling?', style: const TextStyle(color: AppColors.muted, fontSize: 13)),
              const SizedBox(height: 12),
              for (final r in _reasons)
                RadioListTile<String>(
                  value: r,
                  groupValue: _reason,
                  title: Text(r),
                  onChanged: (v) => setState(() => _reason = v),
                ),
              const SizedBox(height: 10),
              TextField(
                controller: _noteController,
                maxLines: 3,
                decoration: const InputDecoration(hintText: 'Add a note (optional)'),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _reason == null ? null : _submit,
                child: Text(isReturn ? 'Submit return request' : 'Submit cancellation'),
              ),
            ],
          ),
          // Step 3 — confirmation
          Center(
            child: Padding(
              padding: const EdgeInsets.all(30),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle_rounded, color: AppColors.ok, size: 64),
                  const SizedBox(height: 16),
                  Text(isReturn ? 'Return request sent' : 'Cancellation sent', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.navy)),
                  const SizedBox(height: 8),
                  const Text('We will review your request and update you soon.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
                  const SizedBox(height: 20),
                  ElevatedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Back to order')),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
