import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/network/api_exception.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/async_state_view.dart';
import '../../data/models/legal_page.dart';
import '../../data/services/account_service.dart';
import '../../data/services/notification_history_store.dart';
import '../../state/address_state.dart';
import '../../state/auth_state.dart';
import '../../state/cart_state.dart';
import '../../state/locale_state.dart';
import '../../state/location_state.dart';
import '../../state/orders_state.dart';
import '../widgets/address_sheets.dart';
import '../widgets/html_content.dart';
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
    final ar = locale.isArabic;
    // Small local helper — every string on THIS screen only; not a general
    // app-wide translation mechanism (see Language row's bug report: most
    // of the rest of the app doesn't check `locale.isArabic` at all yet).
    String t(String en, String arabic) => ar ? arabic : en;

    final rows = <List<dynamic>>[
      [Icons.person_outline_rounded, t('View & edit profile', 'عرض وتعديل الملف الشخصي'), () => Navigator.pushNamed(context, Routes.profile)],
      [Icons.inventory_2_outlined, t('My orders', 'طلباتي'), () => Navigator.pushNamed(context, Routes.orders)],
      [Icons.assignment_return_outlined, t('My requests', 'طلباتي الأخرى') + (orders.pendingRequestCount > 0 ? ' · ${orders.pendingRequestCount}' : ''), () => Navigator.pushNamed(context, Routes.requests)],
      [Icons.medication_outlined, t('My Rx', 'وصفاتي الطبية'), () => Navigator.pushNamed(context, Routes.myRx)],
      [Icons.account_balance_wallet_outlined, t('Wallet', 'المحفظة'), () => Navigator.pushNamed(context, Routes.wallet)],
      [Icons.location_on_outlined, t('Delivery addresses', 'عناوين التوصيل'), () async {
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
      [Icons.favorite_border_rounded, t('Wishlist', 'المفضلة'), () => Navigator.pushNamed(context, Routes.wishlist)],
      [Icons.language_rounded, '${t("Language", "اللغة")} · ${ar ? "العربية" : "English"}', () => locale.toggle()],
    ];

    final infoRows = <List<dynamic>>[
      [Icons.help_outline_rounded, t('About WASFA', 'عن وصفة'), () => _openInfoSheet(context, 'about', ar)],
      [Icons.quiz_outlined, t('FAQ', 'الأسئلة الشائعة'), () => _openInfoSheet(context, 'faq', ar)],
      [Icons.description_outlined, t('Terms & conditions', 'الشروط والأحكام'), () => _openInfoSheet(context, 'terms', ar)],
      [Icons.privacy_tip_outlined, t('Privacy policy', 'سياسة الخصوصية'), () => _openInfoSheet(context, 'privacy', ar)],
      [Icons.support_agent_rounded, t('Help & support', 'المساعدة والدعم'), () => _callSupport(context, ar)],
    ];

    // Scoped to just this screen, not the whole app — the shared AppTopBar
    // above it (Deliver-to/search/notification icons) is a separate widget
    // this doesn't reach, and stays LTR/English until its own turn to be
    // localized. See the Language-toggle bug report: only a handful of
    // screens check `locale.isArabic` at all right now, this being one of
    // the first fully done.
    return Directionality(
      textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
      child: Container(
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
                  // .av — shows the real uploaded photo once one exists
                  // (confirmed live, 2026-09-28), falling back to the
                  // initial-letter avatar until then.
                  Container(
                    width: 58, height: 58,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(.2),
                      borderRadius: BorderRadius.circular(17),
                      image: signedIn && auth.user?.photoUrl != null
                          ? DecorationImage(image: NetworkImage(auth.user!.photoUrl!), fit: BoxFit.cover)
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: (signedIn && auth.user?.photoUrl != null)
                        ? null
                        : Text(
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
                              Text(auth.user!.name.isNotEmpty ? auth.user!.name : t('WASFA customer', 'عميل وصفة'),
                                  maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
                              if (auth.user!.email != null) ...[
                                const SizedBox(height: 3),
                                Text(auth.user!.email!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.white70)),
                              ],
                              const SizedBox(height: 2),
                              Text('+965 ${Formatters.localPhone(auth.user!.phone)}', style: const TextStyle(fontSize: 12, color: Colors.white70)),
                            ]
                          : [
                              Text(t('Sign in', 'تسجيل الدخول'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
                              const SizedBox(height: 2),
                              Text(t('Tap to sign in with your phone number', 'اضغط لتسجيل الدخول برقم هاتفك'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.white70)),
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
                t('LEGAL & INFO', 'معلومات قانونية'),
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
                        builder: (_) => Directionality(
                          textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
                          child: AlertDialog(
                          title: Text(t('Log out?', 'تسجيل الخروج؟')),
                          content: Text(t('You\'ll need to verify your phone number again to sign back in.', 'ستحتاج إلى التحقق من رقم هاتفك مرة أخرى لتسجيل الدخول مجدداً.')),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t('Cancel', 'إلغاء'))),
                            TextButton(onPressed: () => Navigator.pop(context, true), child: Text(t('Log out', 'تسجيل الخروج'))),
                          ],
                          ),
                        ),
                      );
                      if (confirm == true) {
                        // Clear the previous user's data before signing out,
                        // so a guest/next user never sees it.
                        context.read<CartState>().reset();
                        context.read<AddressState>().reset();
                        context.read<OrdersState>().reset();
                        await NotificationHistoryStore.instance.clear();
                        if (!context.mounted) return;
                        await context.read<AuthState>().logout();
                      }
                    },
                    child: Text(t('Log out', 'تسجيل الخروج')),
                  ),
                ),
              )
            else
              const SizedBox(height: 30),
          ],
        ),
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

/// "Help & support" dials the real call center number from `GET
/// /app/page/help` (confirmed live, 2026-09-16) directly, per explicit
/// request — that response's `content` isn't page text to display at all
/// (unlike about/faq/terms/privacy) but a Google Maps link to the office,
/// so the sheet/HTML-rendering path used for the other Legal rows doesn't
/// apply here; `phone` is the actually useful field for this one. Fetched
/// fresh each tap rather than cached/hardcoded, so a future number change
/// on the backend takes effect without an app update.
Future<void> _callSupport(BuildContext context, bool isArabic) async {
  try {
    final page = await AccountService.instance.page('help');
    final phone = page.phone?.trim();
    if (phone == null || phone.isEmpty) {
      if (context.mounted) {
        showErrorToast(context, isArabic ? 'رقم الدعم غير متوفر حالياً.' : 'Support number is not available right now.');
      }
      return;
    }
    final uri = Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'\s+'), ''));
    final launched = await launchUrl(uri);
    if (!launched && context.mounted) {
      showErrorToast(context, isArabic ? 'تعذر فتح تطبيق الاتصال.' : 'Couldn\'t open the phone dialer.');
    }
  } catch (e) {
    if (context.mounted) showErrorToast(context, describeError(e));
  }
}

/// Matches `openInfo()`/`openSheet()` in the HTML — a `.sheet` bottom sheet
/// with a `.sh-h` title/close header and a `.sh-b` scrollable body styled
/// like `.infotext` (13.5px, line-height 1.7). Used for 'about'/'faq'/
/// 'terms'/'privacy' — NOT 'help', which dials the support number directly
/// instead (see _callSupport) since its `content` isn't page text.
///
/// Content used to be hardcoded copy-of-the-HTML placeholder text (both
/// about/terms/privacy — plain paragraphs — and a fabricated FAQ Q&A list)
/// — none of it real. Now backed by the real `GET /app/page/{slug}`
/// (confirmed live for all 4 slugs used here — see ApiConfig.page's doc) —
/// the sheet's own title stays app-curated (translated, properly
/// cased) since that's just UI chrome, but the actual body content is
/// exactly what the API sends, rendered from its raw HTML rather than
/// replaced with invented text.
void _openInfoSheet(BuildContext context, String key, bool isArabic) {
  final titles = {
    'about': isArabic ? 'عن وصفة' : 'About WASFA',
    'faq': isArabic ? 'الأسئلة الشائعة' : 'Frequently Asked Questions',
    'terms': isArabic ? 'الشروط والأحكام' : 'Terms & conditions',
    'privacy': isArabic ? 'سياسة الخصوصية' : 'Privacy policy',
  };

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (_) => Directionality(
      textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: _LegalPageSheet(slug: key, title: titles[key] ?? '', isArabic: isArabic),
    ),
  );
}

class _LegalPageSheet extends StatefulWidget {
  final String slug;
  final String title;
  final bool isArabic;
  const _LegalPageSheet({required this.slug, required this.title, required this.isArabic});

  @override
  State<_LegalPageSheet> createState() => _LegalPageSheetState();
}

class _LegalPageSheetState extends State<_LegalPageSheet> {
  late Future<LegalPage> _future = AccountService.instance.page(widget.slug);
  // Which FAQ entries are currently expanded — starts empty (all
  // collapsed), matching the reference design: a question + a "+" that
  // flips to "−" on tap, more than one can be open at once independently.
  final Set<int> _expandedFaq = {};

  @override
  Widget build(BuildContext context) {
    return SafeArea(
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
                Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: AppColors.navy)),
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
              child: FutureBuilder<LegalPage>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))),
                    );
                  }
                  if (snap.hasError) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
                      child: InlineErrorBanner(
                        message: describeError(snap.error!),
                        onRetry: () => setState(() => _future = AccountService.instance.page(widget.slug)),
                      ),
                    );
                  }
                  final page = snap.data!;
                  final hasContact = page.phone != null || page.email != null || page.address != null;
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // faq's real shape (confirmed live 2026-09-21) is a
                        // structured Q&A list now, not the single HTML blob
                        // the other 4 Legal slugs still use — checked first
                        // since content/contentAr are empty for this page.
                        // Was a flat always-expanded list; rebuilt as a real
                        // accordion per a provided reference design — each
                        // question collapsed by default with a "+"/"−"
                        // toggle, independently expandable (more than one
                        // can be open at once), divider between entries.
                        if (page.faqs.isNotEmpty)
                          for (var i = 0; i < page.faqs.length; i++)
                            _FaqAccordionItem(
                              question: page.faqs[i].questionFor(widget.isArabic),
                              answer: page.faqs[i].answerFor(widget.isArabic),
                              expanded: _expandedFaq.contains(i),
                              isLast: i == page.faqs.length - 1 && !hasContact,
                              onTap: () => setState(() {
                                if (!_expandedFaq.add(i)) _expandedFaq.remove(i);
                              }),
                            )
                        else
                          HtmlBlocks(html: page.contentFor(widget.isArabic)),
                        if (hasContact) ...[
                          const SizedBox(height: 6),
                          const Divider(color: AppColors.line, height: 1),
                          const SizedBox(height: 12),
                          if (page.phone != null) _ContactRow(icon: Icons.call_outlined, text: page.phone!),
                          if (page.email != null) _ContactRow(icon: Icons.email_outlined, text: page.email!),
                          if (page.address != null) _ContactRow(icon: Icons.location_on_outlined, text: page.address!),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _ContactRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 16, color: AppColors.sky),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13, color: AppColors.ink, height: 1.4))),
      ]),
    );
  }
}

/// One collapsible FAQ row — question + a "+"/"−" toggle, answer only
/// shown while expanded, divider below (matching the provided reference
/// design). Kept as plain text for the answer, per an explicit "keep it
/// as text" — a URL appearing inside one doesn't get made tappable.
class _FaqAccordionItem extends StatelessWidget {
  final String question;
  final String answer;
  final bool expanded;
  final bool isLast;
  final VoidCallback onTap;
  const _FaqAccordionItem({required this.question, required this.answer, required this.expanded, required this.isLast, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 13),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(question, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.navy, height: 1.35)),
                ),
                const SizedBox(width: 10),
                Icon(expanded ? Icons.remove_rounded : Icons.add_rounded, size: 19, color: AppColors.muted),
              ],
            ),
          ),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.only(bottom: 13),
            child: Text(answer, style: const TextStyle(fontSize: 13.5, color: AppColors.ink, height: 1.6)),
          ),
        if (!isLast) const Divider(color: AppColors.line, height: 1),
      ],
    );
  }
}

/// Renders just the tags actually seen in a real `/app/page/` response
/// (h1/h2/h3/p/hr as block tags, strong/br inline) as native Flutter
/// widgets, rather than pulling in a full HTML-rendering package for one
/// screen. A block that's empty or whitespace-only once its own tags are
/// stripped (a real response had one — an empty `<p>` full of newlines
/// used as a spacer between sections) is skipped rather than rendered as a
/// blank gap.

