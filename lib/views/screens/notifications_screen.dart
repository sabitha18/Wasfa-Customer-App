import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_exception.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/async_state_view.dart';
import '../../data/models/server_notification.dart';
import '../../data/services/account_service.dart';
import '../../data/services/notification_history_store.dart';
import '../../state/auth_state.dart';
import '../widgets/page_header.dart';

/// The "notification listing page" opened from the bell icon in the app
/// bar. Now backed by the confirmed `GET /app/acct/notifications` list
/// (2026-07-28) — this REPLACES [NotificationHistoryStore] as the source
/// of truth for what's SHOWN here (that store still exists purely to
/// drive the app bar's badge with zero-latency the instant a push
/// arrives, without waiting on a server round trip — see its own doc).
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final List<ServerNotification> _items = [];
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  int _page = 1;
  bool _hasMore = true;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _loadingMore || _loading) return;
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 300) {
      _loadMore();
    }
  }

  Future<void> _load() async {
    final auth = context.read<AuthState>();
    if (!auth.isSignedIn) {
      setState(() {
        _loading = false;
        _error = 'Please sign in to see your notifications.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await AccountService.instance.notifications(auth.userId!, page: 1);
      if (!mounted) return;
      setState(() {
        _items.clear();
        _items.addAll(result.items);
        _page = 1;
        _hasMore = result.hasMore;
        _loading = false;
      });
      // Marks everything read server-side the moment the list loads —
      // matches the common "opening the list clears the badge" pattern.
      // Also resets the app bar badge's own local counter, since that's a
      // separate data source from this list (see NotificationHistoryStore's
      // doc) that needs reconciling here too. Fire-and-forget — neither
      // should block the list from showing.
      AccountService.instance.markAllNotificationsRead(auth.userId!);
      context.read<NotificationHistoryStore>().markAllRead();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = describeError(e);
      });
    }
  }

  Future<void> _loadMore() async {
    final auth = context.read<AuthState>();
    if (!auth.isSignedIn) return;
    setState(() => _loadingMore = true);
    try {
      final next = _page + 1;
      final result = await AccountService.instance.notifications(auth.userId!, page: next);
      if (!mounted) return;
      setState(() {
        _items.addAll(result.items);
        _page = next;
        _hasMore = result.hasMore;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false); // silent — the list already loaded fine, don't block on "more" failing
    }
  }

  String _relativeTime(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${t.day}/${t.month}/${t.year}';
  }

  /// ✅ Confirmed live (2026-07-28, real logcat output) — see
  /// NotificationService._handleDeepLink's doc for the exact payload
  /// shapes this matches. Whether the LIST endpoint's response uses these
  /// same field names inside each notification item is still unconfirmed
  /// (see ServerNotification's doc) — this assumes it does, on the
  /// reasonable bet that backend reuses the same `type`/`order_code`/
  /// `prescription_id` shape it already sends in the push payload itself.
  void _openNotification(ServerNotification n) {
    final nav = Navigator.of(context);
    switch (n.type) {
      case 'order':
        if (n.orderCode != null && n.orderCode!.isNotEmpty) nav.pushNamed(Routes.track, arguments: n.orderCode);
        break;
      case 'prescription':
        if (n.prescriptionId != null && n.prescriptionId!.isNotEmpty) nav.pushNamed(Routes.rxDetail, arguments: n.prescriptionId);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: const PageHeader(title: 'Notifications'),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const LoadingView(message: 'Loading notifications…')
            : (_error != null && _items.isEmpty)
                ? ErrorRetryView(message: _error!, onRetry: _load)
                : _items.isEmpty
                    ? ListView(
                        // ListView (not Center) so RefreshIndicator's pull
                        // gesture still works on an empty list.
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 120),
                            child: Column(
                              children: [
                                const Icon(Icons.notifications_none_rounded, size: 48, color: AppColors.muted),
                                const SizedBox(height: 12),
                                const Text('No notifications yet', style: TextStyle(color: AppColors.muted, fontSize: 13.5)),
                              ],
                            ),
                          ),
                        ],
                      )
                    : ListView.separated(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: _items.length + (_hasMore ? 1 : 0),
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          if (i >= _items.length) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
                            );
                          }
                          final n = _items[i];
                          return InkWell(
                            onTap: () => _openNotification(n),
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: n.read ? null : Border.all(color: AppColors.sky, width: 1.5),
                                boxShadow: AppColors.shSm,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (!n.read)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 5, right: 8),
                                      child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.sky, shape: BoxShape.circle)),
                                    ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(n.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: AppColors.navy)),
                                        const SizedBox(height: 3),
                                        Text(n.body, style: const TextStyle(fontSize: 12.5, color: AppColors.ink)),
                                        const SizedBox(height: 6),
                                        Text(_relativeTime(n.date), style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}
