import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../state/address_state.dart';
import '../../state/auth_state.dart';
import '../../state/locale_state.dart';
import '../../state/location_state.dart';
import '../../state/orders_state.dart';
import '../widgets/address_sheets.dart';
import '../widgets/toast.dart';

/// Matches the HTML's `rAccount()`:
/// - `.acc-head` — full-bleed sky→navy gradient banner (not a rounded card
///   with margin), avatar in a translucent-white chip, name/phone in white,
///   whole thing tappable through to the profile screen.
/// - `.acc-list`/`.acc-row` — each row is its own white block with a 1px
///   bottom margin against the page's light-gray background, which is what
///   creates the hairline gaps between rows; only the first/last row in a
///   group get rounded corners, giving the illusion of one grouped card.
/// - `.acc-grouplbl` — uppercase "Legal" label above the second group.
/// - `.btn btn-ghost` — flat, no-border logout button (bg = page background,
///   navy text) at the bottom.
class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final orders = context.watch<OrdersState>();
    final locale = context.watch<LocaleState>();
    final auth = context.watch<AuthState>();
    final signedIn = auth.isSignedIn;

    final rows = <List<dynamic>>[
      [Icons.person_outline_rounded, 'View & edit profile', () => Navigator.pushNamed(context, Routes.profile)],
      [Icons.inventory_2_outlined, 'My orders', () => Navigator.pushNamed(context, Routes.orders)],
      [Icons.assignment_return_outlined, 'My requests${orders.pendingRequestCount > 0 ? ' · ${orders.pendingRequestCount}' : ''}', () => Navigator.pushNamed(context, Routes.requests)],
      [Icons.medication_outlined, 'My Rx', () => Navigator.pushNamed(context, Routes.myRx)],
      [Icons.account_balance_wallet_outlined, 'Wallet', () => Navigator.pushNamed(context, Routes.wallet)],
      [Icons.location_on_outlined, 'Delivery addresses', () async {
        final addressState = context.read<AddressState>();
        // Wait for both before opening — showing the sheet immediately
        // while these were still in flight meant the address list could
        // change size right under it as the real fetch came in, leaving a
        // captured "edit" index pointing past the end of the new list and
        // crashing.
        await Future.wait([
          addressState.loadAreas(),
          if (auth.isSignedIn) addressState.loadAddresses(auth.userId!),
        ]);
        if (!context.mounted) return;
        showAddressPickerSheet(context, addressState, context.read<LocationState>());
      }],
      [Icons.favorite_border_rounded, 'Wishlist', () => Navigator.pushNamed(context, Routes.wishlist)],
      [Icons.language_rounded, 'Language · ${locale.isArabic ? "العربية" : "English"}', () => locale.toggle()],
    ];

    final infoRows = <List<dynamic>>[
      [Icons.help_outline_rounded, 'About WASFA', () => _openInfoSheet(context, 'about', locale.isArabic)],
      [Icons.quiz_outlined, 'FAQ', () => _openInfoSheet(context, 'faq', locale.isArabic)],
      [Icons.description_outlined, 'Terms & conditions', () => _openInfoSheet(context, 'terms', locale.isArabic)],
      [Icons.privacy_tip_outlined, 'Privacy policy', () => _openInfoSheet(context, 'privacy', locale.isArabic)],
      [Icons.support_agent_rounded, 'Help & support', () => showToast(context, locale.isArabic ? 'جارٍ فتح دعم واتساب…' : 'Opening WhatsApp support…')],
    ];

    return Container(
      color: AppColors.bg,
      child: SafeArea(
        top: false, // AppTopBar (provided by the Scaffold this is hosted in) already covers the top safe area
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            // ── .acc-head ──
            InkWell(
              onTap: signedIn ? () => Navigator.pushNamed(context, Routes.profile) : () => Navigator.pushNamed(context, Routes.login),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 30, 16, 22),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [AppColors.sky, AppColors.navy]),
                ),
                child: Row(children: [
                  // .av
                  Container(
                    width: 58, height: 58,
                    decoration: BoxDecoration(color: Colors.white.withOpacity(.2), borderRadius: BorderRadius.circular(17)),
                    alignment: Alignment.center,
                    child: Text(
                      signedIn && auth.user!.name.isNotEmpty ? auth.user!.name[0].toUpperCase() : '?',
                      style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 14),
                  // .me
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: signedIn
                          ? [
                              Text(auth.user!.name.isNotEmpty ? auth.user!.name : 'WASFA customer',
                                  maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
                              if (auth.user!.email != null) ...[
                                const SizedBox(height: 3),
                                Text(auth.user!.email!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.white70)),
                              ],
                              const SizedBox(height: 2),
                              Text('+965 ${Formatters.localPhone(auth.user!.phone)}', style: const TextStyle(fontSize: 12, color: Colors.white70)),
                            ]
                          : const [
                              Text('Sign in', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
                              SizedBox(height: 2),
                              Text('Tap to sign in with your phone number', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Colors.white70)),
                            ],
                    ),
                  ),
                  // .achev
                  const Icon(Icons.chevron_right_rounded, color: Colors.white70),
                ]),
              ),
            ),

            const SizedBox(height: 14), // .acc-list{padding:14px 0 0}
            _AccList(rows: rows),

            // .acc-grouplbl
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
              child: Text(
                'LEGAL & INFO',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.muted, letterSpacing: .5),
              ),
            ),
            _AccList(rows: infoRows),

            if (signedIn)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.bg,
                      foregroundColor: AppColors.navy,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                      textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text('Log out?'),
                          content: const Text('You\'ll need to verify your phone number again to sign back in.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Log out')),
                          ],
                        ),
                      );
                      if (confirm == true) await context.read<AuthState>().logout();
                    },
                    child: const Text('Log out'),
                  ),
                ),
              )
            else
              const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}

/// `.acc-list` — a group of `.acc-row`s. Rows sit almost flush against each
/// other (1px bottom margin) so the light page background peeks through as
/// a hairline gap; only the group's first/last row get rounded corners.
class _AccList extends StatelessWidget {
  final List<List<dynamic>> rows;
  const _AccList({required this.rows});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++)
          _AccRow(
            icon: rows[i][0] as IconData,
            label: rows[i][1] as String,
            onTap: rows[i][2] as VoidCallback,
            isFirst: i == 0,
            isLast: i == rows.length - 1,
          ),
      ],
    );
  }
}

class _AccRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isFirst;
  final bool isLast;
  const _AccRow({required this.icon, required this.label, required this.onTap, required this.isFirst, required this.isLast});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 16, right: 16, bottom: 1),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(
          top: isFirst ? const Radius.circular(14) : Radius.zero,
          bottom: isLast ? const Radius.circular(14) : Radius.zero,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
          child: Row(children: [
            // .ic
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(11)),
              alignment: Alignment.center,
              child: Icon(icon, color: AppColors.navy, size: 19),
            ),
            const SizedBox(width: 14),
            // .lb
            Expanded(child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink))),
            // .ch
            const Icon(Icons.chevron_right_rounded, color: AppColors.muted, size: 20),
          ]),
        ),
      ),
    );
  }
}

/// Matches `openInfo()`/`openSheet()` in the HTML — a `.sheet` bottom sheet
/// with a `.sh-h` title/close header and a `.sh-b` scrollable body styled
/// like `.infotext` (13.5px, line-height 1.7). Content is the real copy
/// from the HTML's `INFO` object (both `about`/`terms`/`privacy` — plain
/// paragraphs — and `faq`, which is Q&A pairs there via inline `<b>`/`<br>`
/// tags, rebuilt here as a list instead of parsing HTML).
void _openInfoSheet(BuildContext context, String key, bool isArabic) {
  final titles = {
    'about': isArabic ? 'عن وصفة' : 'About WASFA',
    'faq': isArabic ? 'الأسئلة الشائعة' : 'FAQ',
    'terms': isArabic ? 'الشروط والأحكام' : 'Terms & conditions',
    'privacy': isArabic ? 'سياسة الخصوصية' : 'Privacy policy',
  };

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (_) => SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // .sh-h
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line, width: 1))),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(titles[key] ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: AppColors.navy)),
                InkWell(
                  onTap: () => Navigator.pop(context),
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
            // .sh-b
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
                child: key == 'faq' ? _FaqBody(isArabic: isArabic) : Text(_infoText(key, isArabic), style: const TextStyle(fontSize: 13.5, height: 1.7, color: AppColors.ink)),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

String _infoText(String key, bool isArabic) {
  const en = {
    'about': "WASFA is Kuwait's smart healthcare marketplace — genuine medicines from multiple pharmacies, e-prescriptions, doctors, labs and your medical file, all in one app. Delivered fast, MoH-approved.",
    'terms': 'By using WASFA you agree to our Terms of Service. Medicines are dispensed by licensed pharmacies under Kuwait MoH regulations. Prescription-only items require a valid prescription. Prices and availability may vary by pharmacy.',
    'privacy': 'Your privacy matters. Your medical file is private to you and shared with a provider only during a consultation, with your consent. We use encryption and never sell your personal data.',
  };
  const ar = {
    'about': 'وصفة هي سوق الرعاية الصحية الذكي في الكويت — أدوية أصلية من عدة صيدليات، وصفات إلكترونية، أطباء، تحاليل، وملفك الطبي في تطبيق واحد. توصيل سريع ومعتمد من وزارة الصحة.',
    'terms': 'باستخدامك وصفة فإنك توافق على شروط الخدمة. تُصرف الأدوية عبر صيدليات مرخّصة وفق أنظمة وزارة الصحة الكويتية. تتطلب الأدوية الموصوفة وصفة سارية. قد تختلف الأسعار والتوفر حسب الصيدلية.',
    'privacy': 'خصوصيتك تهمنا. ملفك الطبي خاص بك ولا يُشارك مع مقدم الرعاية إلا أثناء الاستشارة وبموافقتك. نستخدم التشفير ولا نبيع بياناتك أبداً.',
  };
  return (isArabic ? ar : en)[key] ?? '';
}

class _FaqBody extends StatelessWidget {
  final bool isArabic;
  const _FaqBody({required this.isArabic});

  @override
  Widget build(BuildContext context) {
    final qa = isArabic
        ? const [
            ['كم تستغرق مدة التوصيل؟', 'تصل معظم الطلبات خلال ساعة.'],
            ['كيف تعمل الوصفات؟', 'يرسل طبيبك الوصفة إلى تطبيقك؛ تقدّم الصيدليات الأسعار وتختار الأفضل.'],
            ['طرق الدفع؟', 'كي نت، بطاقة، محفظة وصفة، أو الدفع عند الاستلام.'],
          ]
        : const [
            ['How fast is delivery?', 'Most orders arrive within 1 hour.'],
            ['How do prescriptions work?', 'Your doctor sends the e-Rx straight to your app; pharmacies submit prices and you pick the best.'],
            ['What payment methods?', 'KNET, card, WASFA Wallet, or cash on delivery.'],
          ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < qa.length; i++) ...[
          if (i > 0) const SizedBox(height: 14),
          Text(qa[i][0], style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.navy, height: 1.7)),
          Text(qa[i][1], style: const TextStyle(fontSize: 13.5, color: AppColors.ink, height: 1.7)),
        ],
      ],
    );
  }
}
