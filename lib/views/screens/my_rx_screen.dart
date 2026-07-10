import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/network/api_exception.dart';
import '../../core/widgets/async_state_view.dart';
import '../../data/models/prescription.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../data/services/account_service.dart';
import '../../state/auth_state.dart';
import '../widgets/page_header.dart';
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
    if (!auth.isSignedIn) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        appBar: PageHeader(title: 'My Rx'),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('💊', style: TextStyle(fontSize: 34)),
              const SizedBox(height: 10),
              const Text('Sign in to see your prescriptions', style: TextStyle(color: AppColors.muted)),
              const SizedBox(height: 14),
              ElevatedButton(
                onPressed: () async {
                  final ok = await Navigator.of(context).pushNamed('login');
                  if (ok == true) _load();
                },
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.navy, foregroundColor: Colors.white),
                child: const Text('Sign in'),
              ),
            ]),
          ),
        ),
      );
    }

    final all = CatalogRepository.instance.prescriptions;
    final list = _query.isEmpty
        ? all
        : all.where((r) => (r.doctor + r.diagnosis + r.id + r.clinic).toLowerCase().contains(_query.toLowerCase())).toList();

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: PageHeader(title: 'My Rx'),
      body: (_loading && all.isEmpty)
          ? const LoadingView(message: 'Loading your prescriptions…')
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
                      hintText: 'Search by doctor or diagnosis',
                      hintStyle: const TextStyle(fontSize: 13.5, color: AppColors.muted, height: 1.2),
                    ),
                  ),
                ),
              ]),
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? const Center(child: Text('No results', style: TextStyle(color: AppColors.muted)))
                : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) => _RxCard(rx: list[i]),
            ),
          ),
        ],
      ),
    );
  }
}

class _RxCard extends StatelessWidget {
  final Prescription rx;
  const _RxCard({required this.rx});

  @override
  Widget build(BuildContext context) {
    final first = rx.items.first;
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RxDetailScreen(rxId: rx.id))),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: AppColors.shSm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── .rxtop — badge + id/date, status pill ──
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  width: 34, height: 34,
                  decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(10)),
                  alignment: Alignment.center,
                  child: const Text('℞', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                ),
                const SizedBox(width: 9),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(rx.id, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: AppColors.navy)),
                  Text(rx.date, style: const TextStyle(fontSize: 10.5, color: AppColors.muted)),
                ]),
              ]),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: rx.isPriced ? const Color(0xFFE8F5FC) : AppColors.blush,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  rx.isPriced ? 'Price submitted' : 'Pharmacist review',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: rx.isPriced ? AppColors.sky : AppColors.rose),
                ),
              ),
            ]),
            const SizedBox(height: 9),
            // ── .rxdoc ──
            Text.rich(TextSpan(children: [
              TextSpan(text: '${rx.doctor} · ${rx.specialty}\n', style: const TextStyle(color: AppColors.ink, fontSize: 12, height: 1.5)),
              TextSpan(text: rx.clinic, style: const TextStyle(color: AppColors.sky, fontSize: 12, height: 1.5)),
            ])),
            const SizedBox(height: 10),
            // ── .rxprev — light gray container ──
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(11)),
              child: Row(children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(9)),
                  alignment: Alignment.center,
                  child: Text(first.emoji, style: const TextStyle(fontSize: 20)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(first.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5, color: AppColors.navy)),
                    const SizedBox(height: 2),
                    Text(first.dosage, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, color: AppColors.muted)),
                  ]),
                ),
              ]),
            ),
            if (rx.items.length > 1)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('+${rx.items.length - 1} more items',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.sky)),
              ),
            // ── .rxview — full-width bordered button ──
            Padding(
              padding: const EdgeInsets.only(top: 11),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.line, width: 1.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('View prescription', style: TextStyle(color: AppColors.navy, fontWeight: FontWeight.w700, fontSize: 12.5)),
                    SizedBox(width: 5),
                    Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.navy),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}