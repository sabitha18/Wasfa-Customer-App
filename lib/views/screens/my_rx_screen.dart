import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/async_state_view.dart';
import '../../data/models/prescription.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../data/services/account_service.dart';
import '../../state/auth_state.dart';
import '../../state/locale_state.dart';
import '../widgets/page_header.dart';
import '../widgets/toast.dart';
import 'rx_detail_screen.dart';

class MyRxScreen extends StatefulWidget {
  const MyRxScreen({super.key});

  @override
  State<MyRxScreen> createState() => _MyRxScreenState();
}

class _MyRxScreenState extends State<MyRxScreen> {
  String _query = '';
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
    try {
      final fetched = await AccountService.instance.prescriptions(auth.userId!);
      CatalogRepository.instance.cachePrescriptions(fetched);
    } catch (e) {
      _error = describeError(e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final ar = context.watch<LocaleState>().isArabic;
    String t(String en, String arabic) => ar ? arabic : en;
    if (!auth.isSignedIn) {
      return Directionality(
        textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
        child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: PageHeader(title: t('My Rx', 'وصفاتي الطبية')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('💊', style: TextStyle(fontSize: 34)),
              const SizedBox(height: 10),
              Text(t('Sign in to see your prescriptions', 'سجّل الدخول لعرض وصفاتك الطبية'), style: const TextStyle(color: AppColors.muted)),
              const SizedBox(height: 14),
              ElevatedButton(
                onPressed: () async {
                  final ok = await Navigator.of(context).pushNamed('login');
                  if (ok == true) _load();
                },
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.navy, foregroundColor: Colors.white),
                child: Text(t('Sign in', 'تسجيل الدخول')),
              ),
            ]),
          ),
        ),
        ),
      );
    }

    final all = CatalogRepository.instance.prescriptions;
    final list = _query.isEmpty
        ? all
        : all.where((r) => (r.doctor + r.diagnosis + r.id + r.clinic).toLowerCase().contains(_query.toLowerCase())).toList();

    return Directionality(
      textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
      backgroundColor: AppColors.bg,
      appBar: PageHeader(title: t('My Rx', 'وصفاتي الطبية')),
      body: (_loading && all.isEmpty)
          ? LoadingView(message: t('Loading your prescriptions…', 'جارٍ تحميل وصفاتك الطبية…'))
          : (_error != null && all.isEmpty)
              ? ErrorRetryView(message: _error!, onRetry: _load)
              : Column(
        children: [
          if (_error != null) InlineErrorBanner(message: _error!, onRetry: _load),
          // ── .rxsearch — bordered white pill with inline icon ──
          // ── .rxsearch — bordered white pill with inline icon ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: AppColors.line, width: 1.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                const Icon(Icons.search_rounded, size: 18, color: AppColors.muted),
                const SizedBox(width: 9),
                Expanded(
                  child: TextField(
                    onChanged: (v) => setState(() => _query = v),
                    style: const TextStyle(fontSize: 13.5, color: AppColors.ink, height: 1.2),
                    cursorColor: AppColors.navy,
                    decoration: InputDecoration(
                      isCollapsed: true,
                      filled: false,
                      fillColor: Colors.transparent,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      focusedErrorBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      hintText: t('Search by doctor or diagnosis', 'ابحث بالطبيب أو التشخيص'),
                      hintStyle: const TextStyle(fontSize: 13.5, color: AppColors.muted, height: 1.2),
                    ),
                  ),
                ),
              ]),
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? Center(child: Text(t('No results', 'لا توجد نتائج'), style: const TextStyle(color: AppColors.muted)))
                : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) => _RxCard(rx: list[i], onUpdated: () => setState(() {})),
            ),
          ),
        ],
      ),
      ),
    );
  }
}

class _RxCard extends StatefulWidget {
  final Prescription rx;
  /// Called after a successful pricing request so the parent list (which
  /// reads straight from [CatalogRepository.instance.prescriptions] — a
  /// plain cache, not a ChangeNotifier) knows to rebuild and pick up the
  /// freshly-cached status. Without this, [_requestPrices] updated the
  /// cache correctly but nothing told MyRxScreen a rebuild was needed, so
  /// the status pill stayed stale until the screen happened to rebuild for
  /// some unrelated reason (e.g. leaving and coming back).
  final VoidCallback? onUpdated;
  const _RxCard({required this.rx, this.onUpdated});

  @override
  State<_RxCard> createState() => _RxCardState();
}

class _RxCardState extends State<_RxCard> {
  bool _expanded = false;
  bool _requesting = false;

  Future<void> _requestPrices(BuildContext context, Prescription rx) async {
    final ar = context.read<LocaleState>().isArabic;
    final auth = context.read<AuthState>();
    if (auth.userId == null) return;
    if (rx.id.isEmpty) {
      showErrorToast(context, ar ? 'هذه الوصفة تفتقد إلى رقم تعريفي — لا يمكن طلب السعر بعد.' : 'This prescription is missing its id — can\'t request pricing yet.');
      return;
    }
    setState(() => _requesting = true);
    try {
      await AccountService.instance.requestPricing(auth.userId!, rx.id);
      final fresh = await AccountService.instance.prescriptionDetail(auth.userId!, rx.id);
      CatalogRepository.instance.upsertPrescription(fresh);
      widget.onUpdated?.call();
      if (context.mounted) showToast(context, ar ? 'تم طلب الأسعار' : 'Prices requested');
    } catch (e) {
      if (context.mounted) showErrorToast(context, describeError(e));
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rx = widget.rx;
    final ar = context.watch<LocaleState>().isArabic;
    // A prescription can legitimately come back with zero items yet (still
    // being transcribed/reviewed, or the backend just hasn't attached items
    // yet) — `.first` on an empty list throws and was taking down this
    // entire screen for every prescription in the list, not just this card.
    final first = rx.items.isEmpty ? null : rx.items.first;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: AppColors.shSm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── .rxtop — badge + id/date (tap navigates to detail); status
          // pill is always passive — "Request Price" is a separate button
          // shown alongside it, not the pill itself ──
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.start, children: [
            GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RxDetailScreen(rxId: rx.id))),
              child: Row(children: [
                Container(
                  width: 34, height: 34,
                  decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(10)),
                  alignment: Alignment.center,
                  child: const Text('℞', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                ),
                const SizedBox(width: 9),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(rx.id, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: AppColors.navy)),
                  Text(Formatters.displayDate(rx.date), style: const TextStyle(fontSize: 10.5, color: AppColors.muted)),
                ]),
              ]),
            ),
            // Confirmed against the reference web app (2026-07-30): the
            // status pill is ALWAYS passive — Pending (gray), Pharmacist
            // Review (amber), Price Submitted (mint-green) — never itself
            // tappable. "Request Price" is a completely separate button
            // underneath it, shown only when rx.isPending &&
            // rx.canRequestPrice (some pending prescriptions don't offer
            // this at all — see Prescription.canRequestPrice's doc).
            Builder(builder: (context) {
              final canAsk = rx.isPending && rx.canRequestPrice;
              return Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: rx.isPriced ? const Color(0xFFE3F5EA) : (rx.isInReview ? const Color(0xFFFFF1DC) : AppColors.blush),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    rx.statusLabel(ar),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: rx.isPriced ? AppColors.ok : (rx.isInReview ? const Color(0xFFB8720A) : AppColors.rose),
                    ),
                  ),
                ),
                if (canAsk) ...[
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: _requesting ? null : () => _requestPrices(context, rx),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(color: AppColors.sky, borderRadius: BorderRadius.circular(9)),
                      child: Text(
                        _requesting ? (ar ? 'جارٍ الطلب…' : 'Requesting…') : (ar ? 'طلب السعر' : 'Request Price'),
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ]);
            }),
          ]),
          const SizedBox(height: 9),
          GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RxDetailScreen(rxId: rx.id))),
            child: Text.rich(TextSpan(children: [
              TextSpan(text: '${Formatters.orDash(rx.doctorLine)}\n', style: const TextStyle(color: AppColors.ink, fontSize: 12, height: 1.5)),
              TextSpan(text: Formatters.orDash(rx.clinic), style: const TextStyle(color: AppColors.sky, fontSize: 12, height: 1.5)),
            ])),
          ),
          const SizedBox(height: 10),
          // ── .rxprev — one row per item; collapsed to just the first by
          // default, expands in place (no navigation) via "+N more items" ──
          if (first == null)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(11)),
              child: Text(ar ? 'لا توجد عناصر مدرجة بعد' : 'No items listed yet', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            )
          else
            Column(children: [
              for (final item in (_expanded ? rx.items : [first]))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(11)),
                    child: Row(children: [
                      Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(9)),
                        alignment: Alignment.center,
                        child: (item.imageUrl != null && item.imageUrl!.isNotEmpty)
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(9),
                                child: Image.network(
                                  item.imageUrl!,
                                  width: 40, height: 40,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5, color: AppColors.navy)),
                          const SizedBox(height: 2),
                          Text(item.dosage, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, color: AppColors.muted)),
                        ]),
                      ),
                    ]),
                  ),
                ),
            ]),
          if (rx.items.length > 1)
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(children: [
                  Text(
                    _expanded ? (ar ? 'عرض أقل' : 'Show less') : (ar ? '+${rx.items.length - 1} عناصر أخرى' : '+${rx.items.length - 1} more items'),
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.sky),
                  ),
                  Icon(_expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 15, color: AppColors.sky),
                ]),
              ),
            ),
          // ── .rxview — full-width bordered button ──
          Padding(
            padding: const EdgeInsets.only(top: 11),
            child: GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RxDetailScreen(rxId: rx.id))),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.line, width: 1.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(ar ? 'عرض الوصفة' : 'View prescription', style: const TextStyle(color: AppColors.navy, fontWeight: FontWeight.w700, fontSize: 12.5)),
                    const SizedBox(width: 5),
                    Icon(ar ? Icons.chevron_left_rounded : Icons.chevron_right_rounded, size: 16, color: AppColors.navy),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}