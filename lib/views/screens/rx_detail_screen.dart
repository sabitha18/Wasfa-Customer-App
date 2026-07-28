import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/async_state_view.dart';
import '../../data/models/cart_line.dart';
import '../../data/models/prescription.dart';
import '../../data/models/seller.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../data/services/account_service.dart';
import '../../state/auth_state.dart';
import '../../state/cart_state.dart';
import '../widgets/page_header.dart';
import '../widgets/toast.dart';

/// Matches `rRxDetail()` exactly — this page stays true to the HTML
/// prototype's design, unlike the My Rx *list*, which now uses the real
/// "Get Prices" action confirmed from the existing native app (see
/// [Prescription.priceSubmitted]/[priceRequested]). That action only lives
/// on the listing page; this page keeps the HTML's original binary
/// priced/not-priced treatment — no "Get Prices" button here, and every
/// non-priced item shows the same "Pharmacist is pricing — soon" message
/// regardless of whether pricing has been requested yet or not.
///
/// Restricted items are the one addition beyond the HTML itself (a
/// separate, explicit client requirement, unrelated to either the HTML or
/// the native app's flow) — they always show "Restricted · Pickup Only"
/// and are never priced or addable, at any status.
///
/// Also worth noting: there is no seller *picker* here — `rxSelSeller()`
/// always auto-picks (cheapest in-stock seller, else the first one) and
/// nothing in the original template ever calls a seller-switching
/// function. So a priced item shows exactly one seller row, styled like a
/// selected option but not tappable — not a list to choose from.
///
/// Fetches fresh via `GET /app/acct/rx/{id}` (confirmed live) rather than
/// only reading the local cache — that cache is populated by the *list*
/// fetch, whose endpoint is still unconfirmed to actually return a list
/// (see AccountService.prescriptions).
class RxDetailScreen extends StatefulWidget {
  final String rxId;
  const RxDetailScreen({super.key, required this.rxId});

  @override
  State<RxDetailScreen> createState() => _RxDetailScreenState();
}

class _RxDetailScreenState extends State<RxDetailScreen> {
  Prescription? _rx;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Instant display from cache (e.g. if this prescription was seen on the
    // My Rx list already) while the real fetch below refreshes it. Ignores
    // a cached copy with an empty id — that's itself a sign it was cached
    // by an older/buggy parse (e.g. from before rx_id was read correctly),
    // and showing it would silently carry that bug forward even after the
    // fix, since a genuinely fresh fetch failing would otherwise fall back
    // to displaying this stale, broken copy.
    final cached = CatalogRepository.instance.findPrescription(widget.rxId);
    _rx = (cached != null && cached.id.isNotEmpty) ? cached : null;
    if (_rx != null) _loading = false;
    _load();
  }

  Future<void> _load() async {
    final auth = context.read<AuthState>();
    final userId = auth.userId;
    if (userId == null) {
      setState(() {
        _loading = false;
        _error = _rx == null ? 'Please sign in to view this prescription.' : null;
      });
      return;
    }
    if (widget.rxId.isEmpty) {
      // Confirmed from a real debug session: fetching with an empty id
      // doesn't 404 — it silently hits GET /app/acct/rx with no id
      // segment, which the backend treats as "list everything" and
      // returns an array instead of one prescription. That then fails to
      // parse as a single object, showing a generic error with no hint of
      // the real cause. Catching it here instead gives an actionable
      // message pointing at where this id actually needs to come from
      // (the My Rx list this screen was opened from).
      setState(() {
        _loading = false;
        _error = 'This prescription has no id to load — check the My Rx list entry it was opened from.';
      });
      return;
    }
    try {
      final fresh = await AccountService.instance.prescriptionDetail(userId, widget.rxId);
      CatalogRepository.instance.upsertPrescription(fresh);
      if (!mounted) return;
      setState(() {
        _rx = fresh;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        // Always surface this — it used to only show an error when there
        // was nothing cached to fall back on, which silently hid genuine
        // fetch failures behind a still-looking-fine stale cached copy.
        // That stale copy could be carrying data parsed by an older
        // version of this model (e.g. missing rx_id before that field was
        // added), with no visible sign anything was wrong — exactly the
        // kind of mismatch that made the "prescription missing its id"
        // guard fire despite the live API clearly sending rx_id.
        _error = describeError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final rx = _rx;
    final cart = context.watch<CartState>();

    if (rx == null) {
      return Scaffold(
        appBar: PageHeader(title: 'Prescription'),
        body: _loading ? const LoadingView() : ErrorRetryView(message: _error ?? 'Prescription not found', onRetry: _load),
      );
    }

    // Whether there's at least one non-restricted item with real seller/
    // price data — decides whether "Add all to RX cart" has anything to
    // actually add. Deliberately does NOT also require rx.isPriced: that
    // flag's field name was confirmed from a different endpoint (the
    // existing native app's RX *cart list*), not this prescription detail
    // endpoint — if this endpoint doesn't send the same field, isPriced
    // would always read false even when individual items clearly do have
    // real pricing already. Trusting each item's own `sellers` data is more
    // robust than depending on a status flag that may not even apply here.
    final hasAddableItems = rx.isPriced && rx.items.any((it) => it.sellers.isNotEmpty && !it.restricted);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: PageHeader(title: rx.id),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(0, 14, 0, 96),
        children: [
          if (_error != null) InlineErrorBanner(message: _error!, onRetry: _load),
          // ── .rxmeta — white card, dividers between rows ──
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: AppColors.shSm),
            child: Column(children: [
              _MetaRow(label: 'Doctor', value: Formatters.orDash(rx.doctorLine), showDivider: true),
              _MetaRow(label: 'Clinic', value: Formatters.orDash(rx.clinic), showDivider: true),
              _MetaRow(label: 'Diagnosis', value: Formatters.orDash(rx.diagnosis), showDivider: true),
              _MetaRow(label: 'Date', value: Formatters.displayDate(rx.date), showDivider: false),
            ]),
          ),
          if (rx.note.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: AppColors.shSm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Note', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.muted)),
                  const SizedBox(height: 4),
                  Text(rx.note, style: const TextStyle(fontSize: 13, color: AppColors.ink)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          if (rx.items.isEmpty)
            // Real prescriptions can come back with no items attached yet
            // (still being transcribed) — show that plainly instead of a
            // blank gap where the item cards and "Add all" bar would be.
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('No items have been added to this prescription yet.', style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
            )
          else
            for (var i = 0; i < rx.items.length; i++)
              _RxItemCard(rx: rx, index: i, onAdd: () => _addItem(context, cart, rx, i)),
        ],
      ),
      bottomNavigationBar: _buildDock(context, cart, rx, hasAddableItems),
    );
  }

  Widget? _buildDock(BuildContext context, CartState cart, Prescription rx, bool hasAddableItems) {
    if (hasAddableItems) {
      return _Dock(
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
      );
    }
    // Not priced, or priced but nothing addable (e.g. every item is
    // restricted) — matches the HTML's dock exactly, which only ever
    // shows anything when `rx.status === 'priced'`.
    return null;
  }

  /// Adds one item — calls the real `POST /app/acct/rx/add-to-cart`
  /// (confirmed live request shape: `user_id`, `prescription_id`,
  /// `item_ids[]`), then updates the local cart display optimistically so
  /// the UI reflects it immediately rather than waiting on a separate
  /// server-cart re-fetch (there's no confirmed response shape yet to
  /// render as source-of-truth — see AccountService.addToRxCart).
  Future<void> _addItem(BuildContext context, CartState cart, Prescription rx, int idx) async {
    final item = rx.items[idx];
    if (!rx.isPriced) return; // can't add before admin actually submits pricing
    if (item.sellers.isEmpty) return;
    if (item.restricted) return; // restricted items can never be added — pickup only
    final seller = _sellerFor(item);
    if (seller == null) return; // no seller available for this item — nothing to add
    if (item.id.isEmpty) {
      showErrorToast(context, 'This item is missing an id — can\'t add it to your Rx cart yet.');
      return;
    }
    if (rx.id.isEmpty) {
      // Fail loudly instead of sending an empty prescription_id — the
      // backend rejects that with "user_id and prescription_id required"
      // and silently doing nothing would be more confusing than an error.
      showErrorToast(context, 'This prescription is missing its id — can\'t add to cart yet.');
      return;
    }
    final auth = context.read<AuthState>();
    if (auth.userId == null) return;

    try {
      await AccountService.instance.addToRxCart(auth.userId!, rx.id, [item.id]);
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
      if (context.mounted) showToast(context, 'Added to Rx cart');
    } catch (e) {
      if (context.mounted) showErrorToast(context, describeError(e));
    }
  }

  /// Adds every priced item in one call — batches all their ids into a
  /// single `item_ids[]` array rather than one request per item, matching
  /// the confirmed request shape.
  Future<void> _addAll(BuildContext context, CartState cart, Prescription rx) async {
    final auth = context.read<AuthState>();
    if (auth.userId == null) return;
    if (rx.id.isEmpty) {
      showErrorToast(context, 'This prescription is missing its id — can\'t add to cart yet.');
      return;
    }

    final eligible = <MapEntry<int, RxItem>>[];
    for (var i = 0; i < rx.items.length; i++) {
      final it = rx.items[i];
      if (rx.isPriced && it.sellers.isNotEmpty && it.id.isNotEmpty && !it.restricted) eligible.add(MapEntry(i, it));
    }
    if (eligible.isEmpty) return;

    try {
      await AccountService.instance.addToRxCart(auth.userId!, rx.id, eligible.map((e) => e.value.id).toList());
      for (final entry in eligible) {
        final i = entry.key;
        final item = entry.value;
        final seller = _sellerFor(item);
        if (seller == null) continue;
        final key = '${rx.id}#$i';
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
      }
      cart.setCartTab('rx');
      cart.notifyListeners();
      if (context.mounted) Navigator.pop(context);
    } catch (e) {
      if (context.mounted) showErrorToast(context, describeError(e));
    }
  }
}

/// Mirrors JS `rxSelSeller()` exactly: cheapest in-stock seller, falling
/// back to the first seller if none are in stock, falling back to null if
/// there are no sellers at all. There's no manual override here — see the
/// class doc on [RxDetailScreen] for why (nothing in `rRxDetail()`'s
/// template ever calls `pickRxSeller()`).
Seller? _sellerFor(RxItem item) {
  final sorted = item.sellers.where((s) => s.stock).toList()..sort((a, b) => a.price.compareTo(b.price));
  if (sorted.isNotEmpty) return sorted.first;
  return item.sellers.isNotEmpty ? item.sellers.first : null;
}

class _Dock extends StatelessWidget {
  final Widget child;
  const _Dock({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: AppColors.navy.withOpacity(0.10), blurRadius: 22, offset: const Offset(0, -6))],
      ),
      child: child,
    );
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
  final VoidCallback onAdd;
  const _RxItemCard({required this.rx, required this.index, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final item = rx.items[index];
    // Was just `item.sellers.isNotEmpty` before — that let pharmacy/price/
    // Add show up whenever an item happened to have seller data attached
    // (e.g. the fallback single-seller synthesis in RxItem.fromJson),
    // regardless of whether the admin dashboard had actually submitted
    // pricing for this prescription yet. Now requires BOTH: the
    // prescription itself must be marked priced, AND this item must
    // actually have sellers.
    final priced = rx.isPriced && item.sellers.isNotEmpty;
    final sel = priced ? _sellerFor(item) : null;
    final restricted = item.restricted;

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
                child: (item.imageUrl != null && item.imageUrl!.isNotEmpty)
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(11),
                        child: Image.network(
                          item.imageUrl!,
                          width: 46, height: 46,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(item.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: AppColors.navy)),
                  if (item.dosage.trim().isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text('💊 ${item.dosage}', style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                  ],
                  if (item.note.trim().isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(item.note, style: const TextStyle(fontSize: 11, color: AppColors.muted, fontStyle: FontStyle.italic)),
                  ],
                ]),
              ),
            ]),
          ),

          if (restricted)
            // ── Restricted items can't be priced or added to cart at all —
            // this check was documented on the class but never actually
            // wired into the widget before, so a restricted item was
            // showing the normal priced/Add-button UI whenever it happened
            // to also have seller data attached. ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.blush, borderRadius: BorderRadius.circular(10)),
              child: const Text('Restricted · Pickup Only', textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.rose, fontSize: 12, fontWeight: FontWeight.w700)),
            )
          else if (priced && sel != null) ...[
            // ── .ri-sellers .srow.sm.on — ONE non-interactive row showing
            // the auto-picked seller (cursor:default in the HTML — this is
            // a display, not a picker) ──
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF2FAFE),
                border: Border.all(color: AppColors.sky, width: 1.5),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Row(children: [
                Expanded(child: Text(sel.name, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.ink))),
                Text(Formatters.money(sel.price), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.navy)),
              ]),
            ),
            // ── .btn.btn-sky — "+ Add · {price}" ──
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
                    Text('Add · ${Formatters.money(sel.price)}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                  ],
                ),
              ),
            ),
          ] else
            // ── .rx-soon — matches the HTML exactly: same message
            // regardless of whether pricing has been requested yet or not.
            // The pending/requested distinction only matters on the
            // listing page's "Get Prices" flow, not here.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.blush, borderRadius: BorderRadius.circular(10)),
              child: const Text('Pharmacist is pricing — soon', textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.rose, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }
}
