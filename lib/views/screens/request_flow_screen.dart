import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/async_state_view.dart';
import '../../data/models/order.dart';
import '../../data/models/product.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../state/auth_state.dart';
import '../../state/locale_state.dart';
import '../../state/orders_state.dart';
import '../widgets/page_header.dart';
import '../widgets/product_image.dart';

/// A single screen that walks through the 3-step cancel/return flow using
/// an internal PageView — equivalent to the three separate HTML screens
/// (rReqItems -> rReqReason -> rReqDone).
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
  final Map<String, int> _selectedQty = {}; // key: 'gi_ii' -> chosen return/cancel qty (1..item.qty)
  Reason? _reason;
  final _noteController = TextEditingController();
  XFile? _photo;
  bool _submitting = false;

  // ✅ real reasons with ids from GET /return-reasons?type=cancel|return —
  // replaces the hardcoded copy-of-the-HTML strings, since submitting now
  // needs a real reason_id, not just display text.
  List<Reason> _reasons = [];
  bool _reasonsLoading = true;
  String? _reasonsError;

  bool get isReturn => widget.type == 'return';

  @override
  void initState() {
    super.initState();
    final order = context.read<OrdersState>().byId(widget.orderId);
    if (order != null) {
      // Only pre-select (and, in build(), only ever show) items not already
      // covered by an earlier partial cancel/return request — someone who
      // already requested 2 of 5 items should see just the remaining 3 here,
      // not the whole order again.
      final remaining = isReturn ? order.remainingForReturn : order.remainingForCancel;
      for (var gi = 0; gi < order.groups.length; gi++) {
        for (var ii = 0; ii < order.groups[gi].items.length; ii++) {
          if (remaining.contains(order.groups[gi].items[ii])) _selectedQty['${gi}_$ii'] = order.groups[gi].items[ii].qty;
        }
      }
    }
    _loadReasons();
  }

  Future<void> _loadReasons() async {
    setState(() { _reasonsLoading = true; _reasonsError = null; });
    try {
      final fetched = await context.read<OrdersState>().fetchReturnReasons(isReturn ? 'return' : 'cancel');
      if (!mounted) return;
      setState(() { _reasons = fetched; _reasonsLoading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _reasonsError = describeError(e); _reasonsLoading = false; });
    }
  }

  void _goTo(int step) {
    setState(() => _step = step);
    _page.animateToPage(step, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  Future<void> _pickPhoto() async {
    final ar = context.read<LocaleState>().isArabic;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) => Directionality(
        textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
        child: SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.camera_alt_outlined), title: Text(ar ? 'التقاط صورة' : 'Take photo'), onTap: () => Navigator.pop(sheetContext, ImageSource.camera)),
          ListTile(leading: const Icon(Icons.photo_library_outlined), title: Text(ar ? 'اختيار من المعرض' : 'Choose from gallery'), onTap: () => Navigator.pop(sheetContext, ImageSource.gallery)),
        ]),
        ),
      ),
    );
    if (source == null) return;
    try {
      final picked = await ImagePicker().pickImage(source: source, imageQuality: 85);
      if (picked != null && mounted) setState(() => _photo = picked);
    } catch (e) {
      if (mounted) showErrorToast(context, ar ? 'تعذر الوصول إلى الكاميرا/المعرض.' : "Couldn't access the camera/gallery.");
    }
  }

  Future<void> _submit() async {
    final ar = context.read<LocaleState>().isArabic;
    if (_reason == null) {
      showErrorToast(context, ar ? 'يرجى اختيار سبب' : 'Please choose a reason');
      return;
    }
    final userId = context.read<AuthState>().userId;
    if (userId == null) {
      showErrorToast(context, ar ? 'يرجى تسجيل الدخول لإرسال هذا الطلب.' : 'Please sign in to submit this request.');
      return;
    }
    final order = context.read<OrdersState>().byId(widget.orderId);
    final selectedItems = <OrderItemLine>[];
    final qtyByDetailId = <int, int>{};
    if (order != null) {
      for (final entry in _selectedQty.entries) {
        final parts = entry.key.split('_');
        final gi = int.tryParse(parts[0]);
        final ii = int.tryParse(parts[1]);
        if (gi == null || ii == null) continue;
        if (gi >= order.groups.length || ii >= order.groups[gi].items.length) continue;
        final item = order.groups[gi].items[ii];
        selectedItems.add(item);
        if (item.detailId != null) qtyByDetailId[item.detailId!] = entry.value;
      }
    }
    setState(() => _submitting = true);
    try {
      await context.read<OrdersState>().startRequest(
        widget.orderId,
        widget.type,
        userId: userId,
        reasonId: _reason!.id,
        reasonLabel: _reason!.label,
        note: _noteController.text,
        items: selectedItems,
        qtyByDetailId: qtyByDetailId,
        imagePath: _photo?.path,
      );
      if (!mounted) return;
      _goTo(2);
    } catch (e) {
      if (mounted) showErrorToast(context, describeError(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ar = context.watch<LocaleState>().isArabic;
    String t(String en, String arabic) => ar ? arabic : en;
    final order = context.read<OrdersState>().byId(widget.orderId);
    if (order == null) {
      return Directionality(
        textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
        child: Scaffold(body: Center(child: Text(t('Order not found', 'لم يتم العثور على الطلب')))),
      );
    }
    final remaining = isReturn ? order.remainingForReturn : order.remainingForCancel;
    if (remaining.isEmpty) {
      // Shouldn't normally happen — the button that opens this screen is
      // itself hidden once nothing's left to request — but guards against
      // opening this screen straight to a picker with nothing pickable.
      return Directionality(
        textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
        child: Scaffold(
        appBar: PageHeader(title: isReturn ? t('Return / Refund', 'إرجاع / استرداد') : t('Cancel order', 'إلغاء الطلب')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              isReturn
                  ? t('Every item in this order already has a return request.', 'كل عنصر في هذا الطلب لديه بالفعل طلب إرجاع.')
                  : t('Every item in this order already has a cancellation request.', 'كل عنصر في هذا الطلب لديه بالفعل طلب إلغاء.'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted, fontSize: 13.5),
            ),
          ),
        ),
        ),
      );
    }

    return Directionality(
      textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
      backgroundColor: AppColors.bg,
      appBar: PageHeader(title: isReturn ? t('Return / Refund', 'إرجاع / استرداد') : t('Cancel order', 'إلغاء الطلب')),
      body: PageView(
        controller: _page,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          // Step 1 — pick items
          ListView(
            padding: EdgeInsets.zero,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  isReturn ? t('Select the items you want to return', 'اختر العناصر التي تريد إرجاعها') : t('Select the items you want to cancel', 'اختر العناصر التي تريد إلغاءها'),
                  style: const TextStyle(color: AppColors.muted, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              for (var gi = 0; gi < order.groups.length; gi++)
                if (order.groups[gi].items.any((it) => remaining.contains(it)))
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppColors.line, width: 1), borderRadius: BorderRadius.circular(14), boxShadow: AppColors.shSm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('🏪 ${order.groups[gi].pharmacy}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: AppColors.navy)),
                        for (var ii = 0; ii < order.groups[gi].items.length; ii++)
                          if (remaining.contains(order.groups[gi].items[ii]))
                            _ReqItemRow(
                              product: order.groups[gi].items[ii].productId != null ? CatalogRepository.instance.findProduct(order.groups[gi].items[ii].productId!) : null,
                              name: order.groups[gi].items[ii].name,
                              maxQty: order.groups[gi].items[ii].qty,
                              price: order.groups[gi].items[ii].price,
                              isFirst: order.groups[gi].items.indexWhere((it) => remaining.contains(it)) == ii,
                              selectedQty: _selectedQty['${gi}_$ii'], // null = not selected
                              onTap: () => setState(() {
                                final key = '${gi}_$ii';
                                if (_selectedQty.containsKey(key)) {
                                  _selectedQty.remove(key);
                                } else {
                                  // Defaults to the full line quantity — the
                                  // stepper on the row lets the person dial
                                  // it down to a partial amount afterward.
                                  _selectedQty[key] = order.groups[gi].items[ii].qty;
                                }
                              }),
                              onQtyChanged: (newQty) => setState(() => _selectedQty['${gi}_$ii'] = newQty),
                            ),
                      ],
                    ),
                  ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.navy, foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                    minimumSize: const Size(double.infinity, 0),
                  ),
                  onPressed: _selectedQty.isEmpty ? null : () => _goTo(1),
                  child: Text('${t("Continue", "متابعة")} (${_selectedQty.length})', style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
          // Step 2 — reason
          ListView(
            padding: EdgeInsets.zero,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  isReturn ? t('Why are you returning?', 'لماذا تقوم بالإرجاع؟') : t('Why are you cancelling?', 'لماذا تقوم بالإلغاء؟'),
                  style: const TextStyle(color: AppColors.muted, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                child: _reasonsLoading
                    ? const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)))
                    : _reasonsError != null
                        ? InlineErrorBanner(message: _reasonsError!, onRetry: _loadReasons)
                        : Column(children: [
                            for (final r in _reasons) ...[
                              _ReasonPill(label: r.label, selected: _reason?.id == r.id, onTap: () => setState(() => _reason = r)),
                              const SizedBox(height: 9),
                            ],
                          ]),
              ),
              const SizedBox(height: 2),
              // .prof-card — "Additional details (optional)"
              Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppColors.line, width: 1), borderRadius: BorderRadius.circular(16), boxShadow: AppColors.shSm),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t('Additional details (optional)', 'تفاصيل إضافية (اختياري)'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.navy)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _noteController,
                    minLines: 3,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: t('Tell us more…', 'أخبرنا المزيد…'),
                      contentPadding: const EdgeInsets.all(11),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: AppColors.line)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: AppColors.line)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: AppColors.sky)),
                    ),
                  ),
                ]),
              ),
              // .prof-card — "📷 Attach product photo *" (return only)
              if (isReturn)
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppColors.line, width: 1), borderRadius: BorderRadius.circular(16), boxShadow: AppColors.shSm),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t('📷 Attach product photo *', '📷 أرفق صورة المنتج *'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.navy)),
                    const SizedBox(height: 12),
                    if (_photo != null)
                      Stack(children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(13),
                          child: Image.file(File(_photo!.path), width: 120, height: 120, fit: BoxFit.cover),
                        ),
                        Positioned(
                          top: 5, right: 5,
                          child: InkWell(
                            onTap: () => setState(() => _photo = null),
                            child: Container(width: 24, height: 24, decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle), alignment: Alignment.center, child: const Icon(Icons.close_rounded, size: 14, color: Colors.white)),
                          ),
                        ),
                      ])
                    else
                      InkWell(
                        onTap: _pickPhoto,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(color: AppColors.bg, border: Border.all(color: AppColors.cloud, width: 1.5), borderRadius: BorderRadius.circular(12)),
                          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            const Icon(Icons.camera_alt_outlined, size: 18, color: AppColors.sky),
                            const SizedBox(width: 9),
                            Text(t('Attach product photo', 'أرفق صورة المنتج'), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.sky)),
                          ]),
                        ),
                      ),
                  ]),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.navy, foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                    minimumSize: const Size(double.infinity, 0),
                  ),
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                      : Text(isReturn ? t('Submit return request', 'إرسال طلب الإرجاع') : t('Submit cancellation request', 'إرسال طلب الإلغاء'), style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
          // Step 3 — confirmation, matches .ph-screen
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 46),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // .ph-screen .ic
                  Container(
                    width: 92, height: 92,
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28), boxShadow: AppColors.shSm),
                    alignment: Alignment.center,
                    child: const Icon(Icons.check_rounded, color: AppColors.ok, size: 44),
                  ),
                  const SizedBox(height: 20),
                  Text(isReturn ? t('Return requested', 'تم طلب الإرجاع') : t('Cancellation requested', 'تم طلب الإلغاء'), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: AppColors.navy)),
                  const SizedBox(height: 8),
                  // .ph-screen p — max-width:240px, so it wraps/centers the
                  // same way as the HTML instead of spanning the full width
                  SizedBox(
                    width: 240,
                    child: Text(
                      isReturn
                          ? t('Our team will review your return and decide on a return or refund.', 'سيقوم فريقنا بمراجعة طلب الإرجاع واتخاذ قرار بشأن الإرجاع أو الاسترداد.')
                          : t("Your request was sent to our team. We'll review it and update you shortly.", 'تم إرسال طلبك إلى فريقنا. سنراجعه ونوافيك بالمستجدات قريباً.'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13.5, height: 1.5, color: AppColors.muted),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // .btn-primary, auto-width (not stretched full-width)
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.navy, foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(t('Back to order', 'العودة إلى الطلب'), style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(height: 10),
                  // .btn-ghost — the second button that was missing entirely
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.bg, foregroundColor: AppColors.navy, elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                    ),
                    onPressed: () {
                      // Pops this flow's 2 pushed screens (this one, then
                      // Order Detail) to land back on the Orders list, the
                      // only screen that ever pushes into this flow.
                      Navigator.of(context)
                        ..pop()
                        ..pop();
                    },
                    child: Text(t('My orders', 'طلباتي'), style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
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

/// Matches `.rq-item` exactly: a custom square checkbox (not a Material
/// Checkbox), the real product photo (falls back to emoji), name + qty·price,
/// with a hairline top border between rows (none on the first).
class _ReqItemRow extends StatelessWidget {
  final Product? product;
  final String name;
  final int maxQty; // the item's full quantity from the order — the ceiling the stepper can't exceed
  final double price;
  final bool isFirst;
  final int? selectedQty; // null = not selected; otherwise 1..maxQty
  final VoidCallback onTap;
  final ValueChanged<int> onQtyChanged;
  const _ReqItemRow({
    required this.product,
    required this.name,
    required this.maxQty,
    required this.price,
    required this.isFirst,
    required this.selectedQty,
    required this.onTap,
    required this.onQtyChanged,
  });

  @override
  Widget build(BuildContext context) {
    final ar = context.watch<LocaleState>().isArabic;
    final selected = selectedQty != null;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(border: isFirst ? null : const Border(top: BorderSide(color: AppColors.line, width: 1))),
      child: Row(children: [
        // .rq-cb
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(7),
          child: Container(
            width: 22, height: 22,
            decoration: BoxDecoration(
              color: selected ? AppColors.sky : Colors.white,
              border: Border.all(color: selected ? AppColors.sky : AppColors.line, width: 2),
              borderRadius: BorderRadius.circular(7),
            ),
            alignment: Alignment.center,
            child: selected ? const Icon(Icons.check_rounded, size: 13, color: Colors.white) : null,
          ),
        ),
        const SizedBox(width: 11),
        ClipRRect(
          borderRadius: BorderRadius.circular(9),
          // Plain empty box when there's no real photo — no emoji or other
          // stand-in, matching every other product thumbnail in the app.
          child: product != null
              ? ProductImage(product: product!, height: 40, width: 40)
              : Container(width: 40, height: 40, color: AppColors.blush),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name.isNotEmpty ? name : (product?.nameEn ?? (ar ? 'عنصر' : 'Item')), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink)),
              const SizedBox(height: 2),
              Text(
                ar ? '×$maxQty مطلوب · ${Formatters.money(price)} للقطعة' : '×$maxQty ordered · ${Formatters.money(price)} each',
                style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
              ),
            ]),
          ),
        ),
        // Qty stepper — only meaningful once this item is actually
        // selected; lets the person return/cancel fewer than the full
        // ordered quantity (e.g. 1 of 2), rather than always all-or-nothing
        // for the whole line.
        if (selected)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(border: Border.all(color: AppColors.line, width: 1), borderRadius: BorderRadius.circular(9)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              InkWell(
                onTap: selectedQty! > 1 ? () => onQtyChanged(selectedQty! - 1) : null,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(Icons.remove_rounded, size: 15, color: selectedQty! > 1 ? AppColors.navy : AppColors.line),
                ),
              ),
              SizedBox(
                width: 20,
                child: Text('$selectedQty', textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.navy)),
              ),
              InkWell(
                onTap: selectedQty! < maxQty ? () => onQtyChanged(selectedQty! + 1) : null,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(Icons.add_rounded, size: 15, color: selectedQty! < maxQty ? AppColors.navy : AppColors.line),
                ),
              ),
            ]),
          ),
      ]),
    );
  }
}

/// Matches `.rsn`: a pill button with a custom circular radio indicator —
/// sky border + light-blue fill when selected, plain line/white otherwise.
class _ReasonPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ReasonPill({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(13),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFF4FAFD) : Colors.white,
          border: Border.all(color: selected ? AppColors.sky : AppColors.line, width: 1.5),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Row(children: [
          Container(
            width: 20, height: 20,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: selected ? AppColors.sky : AppColors.line, width: 2)),
            alignment: Alignment.center,
            child: selected ? Container(width: 10, height: 10, decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.sky)) : null,
          ),
          const SizedBox(width: 11),
          Expanded(child: Text(label, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: selected ? AppColors.navy : AppColors.ink))),
        ]),
      ),
    );
  }
}
