import '../../core/utils/json_utils.dart';

/// One Q&A pair in `faq`'s real `faqs[]` array — confirmed live
/// (2026-09-21): `{ question, answer, question_ar, answer_ar }`. This
/// REPLACED faq's old shape (a single `content` HTML blob, same as
/// about/terms/privacy/help) — `faqs` used to come back as an empty,
/// unused array alongside that HTML content; it's now the real, structured
/// source for this one page, with `content`/`content_ar` no longer
/// necessarily present for it at all.
class FaqEntry {
  final String question;
  final String answer;
  final String? questionAr;
  final String? answerAr;

  const FaqEntry({required this.question, required this.answer, this.questionAr, this.answerAr});

  String questionFor(bool arabic) => (arabic && (questionAr?.trim().isNotEmpty ?? false)) ? questionAr! : question;
  String answerFor(bool arabic) => (arabic && (answerAr?.trim().isNotEmpty ?? false)) ? answerAr! : answer;

  factory FaqEntry.fromJson(Map<String, dynamic> json) => FaqEntry(
        question: asString(json, const ['question']),
        answer: asString(json, const ['answer']),
        questionAr: asStringOrNull(json, const ['question_ar']),
        answerAr: asStringOrNull(json, const ['answer_ar']),
      );
}

/// `GET /app/page/{slug}` — confirmed live for all 5 slugs (2026-09-16):
/// about, faq, terms, privacy, help. See ApiConfig.page's doc for details,
/// including why 'help' is handled differently on screen (its `content` is
/// a Maps link, not text — see account_screen.dart's "Help & support" row).
///
/// ✅ `title_ar`/`content_ar` confirmed added (2026-09-18) — this content
/// used to only ever come back in English, regardless of the app's
/// language toggle; that's now a real gap closed rather than a permanent
/// backend limitation. [title]/[content] stay as the raw English fields;
/// use [titleFor]/[contentFor] to pick the right one for the current locale.
///
/// ✅ `faq`'s shape changed (2026-09-21) — see [FaqEntry]'s doc. [faqs] is
/// empty for the other 4 slugs, which still use [content]/[contentAr] as
/// before; account_screen.dart's sheet checks [faqs] first and renders a
/// Q&A list instead of HTML content whenever it's non-empty.
class LegalPage {
  final String slug;
  final String title;
  final String? titleAr;
  /// Raw HTML from the CMS — rendered by HtmlBlocks (views/widgets/html_content.dart),
  /// which handles just the tags actually seen in real responses (h1/h2/h3/
  /// p/hr, plus inline strong/b/br) rather than pulling in a full
  /// HTML-rendering package for one screen. Same handling applies to
  /// [contentAr] — it's the same kind of CMS HTML, just in Arabic. Empty
  /// for 'faq' now — see [faqs].
  final String content;
  final String? contentAr;
  final List<FaqEntry> faqs;
  final String? phone;
  final String? email;
  final String? address;

  const LegalPage({
    required this.slug,
    required this.title,
    this.titleAr,
    required this.content,
    this.contentAr,
    this.faqs = const [],
    this.phone,
    this.email,
    this.address,
  });

  /// Falls back to the English field whenever no real Arabic value was
  /// sent for this particular page — some slugs may get their Arabic
  /// content added later than others, so this degrades gracefully per
  /// page rather than assuming all-or-nothing.
  String titleFor(bool arabic) => (arabic && (titleAr?.trim().isNotEmpty ?? false)) ? titleAr! : title;
  String contentFor(bool arabic) => (arabic && (contentAr?.trim().isNotEmpty ?? false)) ? contentAr! : content;

  factory LegalPage.fromJson(Map<String, dynamic> json) => LegalPage(
        slug: asString(json, const ['slug']),
        title: asString(json, const ['title']),
        titleAr: asStringOrNull(json, const ['title_ar']),
        content: asString(json, const ['content']),
        contentAr: asStringOrNull(json, const ['content_ar']),
        faqs: asList(json, const ['faqs']).whereType<Map<String, dynamic>>().map((e) => FaqEntry.fromJson(e)).toList(),
        phone: asStringOrNull(json, const ['phone']),
        email: asStringOrNull(json, const ['email']),
        address: asStringOrNull(json, const ['address']),
      );
}
