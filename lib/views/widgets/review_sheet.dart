import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/auth_gate.dart';
import '../../core/widgets/async_state_view.dart';
import '../../data/services/catalog_service.dart';
import '../../state/auth_state.dart';
import '../../state/locale_state.dart';
import 'toast.dart';

/// `POST /app/product/{sku}/review` — confirmed live (2026-09-17). Shared
/// between product_screen.dart's "Write a review" (gated on the PDP's own
/// `can_review`/`already_reviewed` flags) and order_detail_screen.dart's
/// "Review this item" on a delivered order's line (inherently verified —
/// getting there at all means this item is in an order that's actually
/// this person's own, confirmed `sku` present on order items 2026-09-18 —
/// no separate eligibility check needed the way the PDP does). [name]/
/// [email] come from the signed-in person's own profile rather than
/// asking for them again, since the endpoint accepts but doesn't require a
/// dedicated guest-review flow here.
Future<void> openReviewSheet(BuildContext context, {required String sku, required String productName}) async {
  final ar = context.read<LocaleState>().isArabic;
  if (!await requireLogin(context)) return;
  if (!context.mounted) return;
  final auth = context.read<AuthState>();

  int stars = 0;
  final commentCtrl = TextEditingController();

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (sheetContext) => Directionality(
      textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
      child: StatefulBuilder(
        builder: (context, setState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line, width: 1))),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Expanded(
                    child: Text(
                      ar ? '⭐ اكتب تقييماً' : '⭐ Write a review',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: AppColors.navy),
                    ),
                  ),
                  InkWell(
                    onTap: () => Navigator.pop(sheetContext),
                    borderRadius: BorderRadius.circular(9),
                    child: Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(9)),
                      alignment: Alignment.center,
                      child: const Icon(Icons.close_rounded, size: 18, color: AppColors.navy),
                    ),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 6),
                child: Column(children: [
                  Text(
                    productName.isNotEmpty
                        ? (ar ? 'كيف تقيّم "$productName"؟' : 'How would you rate "$productName"?')
                        : (ar ? 'كيف تقيّم هذا المنتج؟' : 'How would you rate this product?'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: AppColors.muted),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (i) => IconButton(
                          onPressed: () => setState(() => stars = i + 1),
                          icon: Icon(Icons.star_rounded, color: stars > i ? AppColors.star : AppColors.cloud, size: 38),
                        )),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: commentCtrl,
                    minLines: 3,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: ar ? 'شارك رأيك في هذا المنتج (اختياري)' : 'Share your thoughts about this product (optional)',
                      contentPadding: const EdgeInsets.all(11),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: AppColors.line)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: AppColors.line)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: AppColors.sky)),
                    ),
                  ),
                ]),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line, width: 1))),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.navy, foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                    ),
                    onPressed: () async {
                      if (stars == 0) {
                        showErrorToast(sheetContext, ar ? 'اختر تقييماً' : 'Pick a rating');
                        return;
                      }
                      if (auth.userId == null) return;
                      try {
                        await CatalogService.instance.submitReview(
                          sku,
                          userId: auth.userId!,
                          rating: stars,
                          name: auth.user?.name ?? '',
                          email: auth.user?.email ?? '',
                          comment: commentCtrl.text.trim(),
                        );
                        if (!sheetContext.mounted) return;
                        Navigator.pop(sheetContext);
                        showToast(context, ar ? 'شكراً على تقييمك!' : 'Thanks for your review!');
                      } catch (e) {
                        if (sheetContext.mounted) showErrorToast(sheetContext, describeError(e));
                      }
                    },
                    child: Text(ar ? 'إرسال التقييم' : 'Submit review', style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    ),
  );
}
