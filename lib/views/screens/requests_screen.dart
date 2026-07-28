import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/routing/app_routes.dart';
import '../../core/widgets/async_state_view.dart';
import '../../data/models/order.dart';
import '../../state/auth_state.dart';
import '../../state/orders_state.dart';
import '../widgets/page_header.dart';
import 'order_detail_screen.dart';

/// Matches the HTML's `rRequests()`. ✅ Now backed by the real
/// `GET /acct/my-requests` (confirmed live) instead of only deriving
/// entries from whatever's cached in [OrdersState.orders] locally — that
/// approach only ever reflected requests made during the current app
/// session and vanished on any fresh fetch.
class RequestsScreen extends StatefulWidget {
  const RequestsScreen({super.key});

  @override
  State<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends State<RequestsScreen> {
  bool _loading = true;
  String? _error;
  List<({String orderCode, String type, OrderRequest request})> _entries = [];

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
    try {
      final fetched = await context.read<OrdersState>().fetchMyRequests(auth.userId!);
      fetched.sort((a, b) => b.request.ts.compareTo(a.request.ts));
      if (!mounted) return;
      setState(() { _entries = fetched; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = describeError(e); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: PageHeader(title: 'My requests'),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading && _entries.isEmpty
            ? const LoadingView(message: 'Loading your requests…')
            : (_error != null && _entries.isEmpty)
                ? ErrorRetryView(message: _error!, onRetry: _load)
                : _entries.isEmpty
                    ? ListView(children: [_EmptyState(onBrowseOrders: () => Navigator.pushNamed(context, Routes.orders))])
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                        itemCount: _entries.length + (_error != null ? 1 : 0),
                        separatorBuilder: (_, __) => const SizedBox(height: 14),
                        itemBuilder: (context, i) {
                          if (_error != null && i == 0) {
                            return InlineErrorBanner(message: _error!, onRetry: _load);
                          }
                          final idx = _error != null ? i - 1 : i;
                          final e = _entries[idx];
                          return _RequestCard(orderCode: e.orderCode, type: e.type, req: e.request);
                        },
                      ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onBrowseOrders;
  const _EmptyState({required this.onBrowseOrders});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 50),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // .ph-screen .ic — sky-colored here (not overridden, unlike the "done" screen)
            Container(
              width: 92, height: 92,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28), boxShadow: AppColors.shSm),
              alignment: Alignment.center,
              child: const Icon(Icons.assignment_return_outlined, size: 36, color: AppColors.sky),
            ),
            const SizedBox(height: 20),
            const Text('No cancellation or return requests yet', textAlign: TextAlign.center, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: AppColors.navy)),
            const SizedBox(height: 18),
            // .btn-sky — solid sky, auto-width
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.sky, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
              ),
              onPressed: onBrowseOrders,
              child: const Text('My orders', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  final String orderCode;
  final String type;
  final OrderRequest req;
  const _RequestCard({required this.orderCode, required this.type, required this.req});

  @override
  Widget build(BuildContext context) {
    final isCancel = type == 'cancel';
    final statusColors = {
      'pending': (const Color(0xFFFFF6E9), AppColors.warn),
      'approved': (const Color(0xFFF3FBF7), AppColors.ok),
      'rejected': (AppColors.blush, AppColors.rose),
    }[req.status] ?? (AppColors.blush, AppColors.rose);

    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: orderCode))),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: AppColors.shSm),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // .otop
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 13, 15, 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${isCancel ? '⛔' : '↩︎'} ${isCancel ? 'Cancellation request' : 'Return request'}', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.navy)),
                  const SizedBox(height: 2),
                  Text('Order $orderCode · ${Formatters.dateShort(req.ts)}', style: const TextStyle(fontSize: 10.5, color: AppColors.muted, fontWeight: FontWeight.w500)),
                ]),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                decoration: BoxDecoration(color: statusColors.$1, borderRadius: BorderRadius.circular(9)),
                child: Text(req.statusLabel, style: TextStyle(color: statusColors.$2, fontWeight: FontWeight.w700, fontSize: 10)),
              ),
            ]),
          ),
          // .obody — /acct/my-requests never sends a line-item breakdown,
          // just an amount, so that's the headline figure here instead of
          // an item count (which would always read "0 item(s)").
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 0, 15, 12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    req.items.isNotEmpty ? '${req.items.length} item(s)' : (req.amount != null ? Formatters.money(req.amount!) : ''),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.navy),
                  ),
                  if (req.reason.isNotEmpty) Text(req.reason, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                ]),
              ),
              InkWell(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: orderCode))),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('Order details', style: TextStyle(color: AppColors.sky, fontWeight: FontWeight.w700, fontSize: 12.5)),
                  SizedBox(width: 3),
                  Icon(Icons.chevron_right_rounded, color: AppColors.sky, size: 16),
                ]),
              ),
            ]),
          ),
          // .rq-mini
          if (req.items.isNotEmpty)
            Container(
              margin: const EdgeInsets.fromLTRB(15, 0, 15, 12),
              padding: const EdgeInsets.only(top: 10),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line, width: 1))),
              child: Wrap(
                spacing: 6, runSpacing: 6,
                children: [
                  for (final it in req.items)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(8)),
                      child: Text('📦 ${it.name.isNotEmpty ? it.name : 'Item'} ×${it.qty}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.navy)),
                    ),
                ],
              ),
            ),
        ]),
      ),
    );
  }
}
