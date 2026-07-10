import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/cart_line.dart';
import '../../data/models/prescription.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../state/cart_state.dart';
import '../widgets/page_header.dart';
import '../widgets/toast.dart';

class RxDetailScreen extends StatefulWidget {
  final String rxId;
  const RxDetailScreen({super.key, required this.rxId});

  @override
  State<RxDetailScreen> createState() => _RxDetailScreenState();
}

class _RxDetailScreenState extends State<RxDetailScreen> {
  final Map<int, String> _selectedSeller = {};
  final Set<int> _refillRequested = {}; // local-only until backend exists

  @override
  Widget build(BuildContext context) {
    final rx = CatalogRepository.instance.findPrescription(widget.rxId);
    if (rx == null) return const Scaffold(body: Center(child: Text('Prescription not found')));
    final cart = context.watch<CartState>();

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: PageHeader(title: rx.id),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(0, 14, 0, 96),
        children: [
          // ── .rxmeta — with dividers between rows ──
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: AppColors.shSm),
            child: Column(children: [
              _MetaRow(label: 'Doctor', value: '${rx.doctor} · ${rx.specialty}', showDivider: true),
              _MetaRow(label: 'Clinic', value: rx.clinic, showDivider: true),
              _MetaRow(label: 'Diagnosis', value: rx.diagnosis, showDivider: true),
              _MetaRow(label: 'Date', value: rx.date, showDivider: false),
            ]),
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < rx.items.length; i++)
            _RxItemCard(
              rx: rx,
              index: i,
              selectedSeller: _selectedSeller[i],
              refillRequested: _refillRequested.contains(i),
              onSelectSeller: (name) => setState(() => _selectedSeller[i] = name),
              onAdd: () => _addItem(context, cart, rx, i),
              onRequestRefill: () => setState(() => _refillRequested.add(i)),
            ),
        ],
      ),
      bottomNavigationBar: rx.isPriced
          ? Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(color: AppColors.navy.withOpacity(0.10), blurRadius: 22, offset: const Offset(0, -6))],
        ),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.navy,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            onPressed: () => _addAll(context, cart, rx),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.shopping_bag_outlined, size: 17),
                SizedBox(width: 8),
                Text('Add all to RX cart', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              ],
            ),
          ),
        ),
      )
          : null,
    );
  }

  void _addItem(BuildContext context, CartState cart, Prescription rx, int idx) {
    final item = rx.items[idx];
    if (!rx.isPriced || item.sellers.isEmpty) return;
    final seller = _sellerFor(item, idx);
    final key = '${rx.id}#$idx';
    cart.rxCart[key] = CartLine(
      key: key,
      apiProductId: seller.productId,
      seller: seller.name,
      price: seller.price,
      rxId: rx.id,
      nameOverride: item.name,
      nameOverrideAr: item.nameAr,
      emojiOverride: item.emoji,
    );
    cart.notifyListeners();
    showToast(context, 'Added to Rx cart');
  }

  void _addAll(BuildContext context, CartState cart, Prescription rx) {
    for (var i = 0; i < rx.items.length; i++) {
      if (rx.items[i].sellers.isNotEmpty) _addItem(context, cart, rx, i);
    }
    cart.setCartTab('rx');
    Navigator.pop(context);
  }

  dynamic _sellerFor(RxItem item, int idx) {
    final name = _selectedSeller[idx];
    if (name != null) return item.sellers.firstWhere((s) => s.name == name, orElse: () => item.sellers.first);
    final sorted = item.sellers.where((s) => s.stock).toList()..sort((a, b) => a.price.compareTo(b.price));
    return sorted.isNotEmpty ? sorted.first : item.sellers.first;
  }
}

class _MetaRow extends StatelessWidget {
  final String label;
  final String value;
  final bool showDivider;
  const _MetaRow({required this.label, required this.value, required this.showDivider});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        border: showDivider ? const Border(bottom: BorderSide(color: AppColors.line, width: 1)) : null,
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
        Flexible(child: Text(value, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: AppColors.navy))),
      ]),
    );
  }
}

class _RxItemCard extends StatelessWidget {
  final Prescription rx;
  final int index;
  final String? selectedSeller;
  final bool refillRequested;
  final void Function(String) onSelectSeller;
  final VoidCallback onAdd;
  final VoidCallback onRequestRefill;
  const _RxItemCard({
    required this.rx,
    required this.index,
    required this.selectedSeller,
    required this.refillRequested,
    required this.onSelectSeller,
    required this.onAdd,
    required this.onRequestRefill,
  });

  // ── Refill logic — mirrors HTML's durationDays()/rxDaysLeft()/needsRefill() ──
  // Parses a "NN days" pattern out of the dosage string and a date out of rx.date,
  // no new model fields required.
  int? _durationDays(String dosage) {
    final match = RegExp(r'(\d+)\s*day').firstMatch(dosage.toLowerCase());
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  DateTime? _parseRxDate(String dateStr) {
    // Expects formats like "Jun 17, 2026"
    const months = {
      'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
      'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
    };
    final m = RegExp(r'([A-Za-z]{3,})\s+(\d{1,2}),\s*(\d{4})').firstMatch(dateStr);
    if (m == null) return null;
    final mon = months[m.group(1)!.toLowerCase().substring(0, 3)];
    if (mon == null) return null;
    return DateTime(int.parse(m.group(3)!), mon, int.parse(m.group(2)!));
  }

  int? _daysLeft(RxItem item) {
    final days = _durationDays(item.dosage);
    if (days == null) return null;
    final start = _parseRxDate(rx.date);
    if (start == null) return null;
    final end = start.add(Duration(days: days));
    return end.difference(DateTime.now()).inDays;
  }

  bool _needsRefill(RxItem item) {
    if (refillRequested) return false;
    final dl = _daysLeft(item);
    return dl != null && dl <= 5;
  }

  @override
  Widget build(BuildContext context) {
    final item = rx.items[index];
    final priced = rx.isPriced && item.sellers.isNotEmpty;
    final sorted = List.of(item.sellers)..sort((a, b) => a.price.compareTo(b.price));
    final sel = selectedSeller != null
        ? item.sellers.firstWhere((s) => s.name == selectedSeller, orElse: () => sorted.first)
        : (sorted.isNotEmpty ? sorted.first : null);

    final needsRefill = priced && _needsRefill(item);
    final daysLeft = needsRefill ? _daysLeft(item) : null;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: AppColors.shSm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── .rih — 46x46 icon, 12px bottom margin ──
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(children: [
              Container(
                width: 46, height: 46,
                decoration: BoxDecoration(color: AppColors.blush, borderRadius: BorderRadius.circular(11)),
                alignment: Alignment.center,
                child: Text(item.emoji, style: const TextStyle(fontSize: 22)),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(item.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: AppColors.navy)),
                  const SizedBox(height: 2),
                  Text('💊 ${item.dosage}', style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                ]),
              ),
            ]),
          ),

          if (priced) ...[
            // ── .srow.sm — bordered radio rows, sky highlight when selected ──
            for (var i = 0; i < sorted.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: GestureDetector(
                  onTap: () => onSelectSeller(sorted[i].name),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: sel?.name == sorted[i].name ? const Color(0xFFF2FAFE) : Colors.white,
                      border: Border.all(
                        color: sel?.name == sorted[i].name ? AppColors.sky : AppColors.line,
                        width: 1.5,
                      ),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Row(children: [
                      // Custom radio circle matching .srow .rad
                      Container(
                        width: 20, height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: sel?.name == sorted[i].name ? AppColors.sky : AppColors.line,
                            width: 2,
                          ),
                        ),
                        child: sel?.name == sorted[i].name
                            ? Center(child: Container(width: 12, height: 12, decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.sky)))
                            : null,
                      ),
                      const SizedBox(width: 11),
                      Expanded(child: Text(sorted[i].name, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.ink))),
                      // ── .sp2 — price on top, Best pill below ──
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text(Formatters.money(sorted[i].price), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.navy)),
                        if (i == 0)
                          Container(
                            margin: const EdgeInsets.only(top: 3),
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(color: const Color(0xFFE4F6EF), borderRadius: BorderRadius.circular(10)),
                            child: const Text('Best price', style: TextStyle(color: AppColors.ok, fontSize: 9, fontWeight: FontWeight.w700)),
                          ),
                      ]),
                    ]),
                  ),
                ),
              ),
            const SizedBox(height: 1),
            // ── .btn.btn-sky — with plus icon ──
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.sky,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                onPressed: onAdd,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.add, size: 16),
                    const SizedBox(width: 6),
                    Text('Add · ${Formatters.money(sel!.price)}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                  ],
                ),
              ),
            ),
          ] else
          // ── .rx-soon — blush bg, rose text ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.blush, borderRadius: BorderRadius.circular(10)),
              child: const Text('⏳ Pharmacist is pricing — soon', textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.rose, fontSize: 12, fontWeight: FontWeight.w600)),
            ),

          // ── .refill-bar — course ending soon, request refill ──
          if (needsRefill)
            Container(
              margin: const EdgeInsets.only(top: 9),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(color: const Color(0xFFFFF6E9), borderRadius: BorderRadius.circular(11)),
              child: Row(children: [
                Expanded(
                  child: Text(
                    daysLeft! <= 0 ? '🔁 Course finished' : '🔁 $daysLeft days left',
                    style: const TextStyle(color: AppColors.warn, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
                GestureDetector(
                  onTap: onRequestRefill,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(color: AppColors.warn, borderRadius: BorderRadius.circular(9)),
                    child: const Text('Refill request', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                ),
              ]),
            ),

          // ── .refill-done — request sent ──
          if (refillRequested)
            Container(
              margin: const EdgeInsets.only(top: 9),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(color: const Color(0xFFF3FBF7), borderRadius: BorderRadius.circular(11)),
              child: const Row(children: [
                Text('✓ Refill request pending', style: TextStyle(color: AppColors.ok, fontSize: 12, fontWeight: FontWeight.w600)),
              ]),
            ),
        ],
      ),
    );
  }
}