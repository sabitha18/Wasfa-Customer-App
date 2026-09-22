import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// Renders just the HTML tags actually seen in real CMS-authored content
/// (h1/h2/h3/p/hr as block tags, strong/b/br inline) as native Flutter
/// widgets, rather than pulling in a full HTML-rendering package. Shared
/// between account_screen.dart's Legal pages (`/app/page/{slug}`) and
/// product_screen.dart's real product `description` field — both are raw
/// CMS HTML with the same handful of tags, so this one renderer (and any
/// bug fix to it) covers both rather than two separately-maintained copies.
///
/// Handles real-world messy authoring quirks confirmed from actual
/// responses, not just clean hand-written markup:
/// - A block that's empty/whitespace-only once its own tags are stripped
///   (a real response had an empty `<p>` used purely as a spacer between
///   sections) is skipped rather than rendered as a blank gap.
/// - Both `<strong>` and `<b>` are treated as bold — different real
///   responses used different ones; the CMS isn't consistent about it.
/// - Word/Outlook-exported HTML hard-wraps long lines with raw `\r\n`
///   INSIDE the sentence text itself, not just between paragraphs — left
///   as-is, these show up as arbitrary mid-sentence line breaks with no
///   relation to the app's actual screen width. Collapsed to a single
///   space before real `<br>` tags (the only INTENTIONAL line breaks) are
///   converted to an actual newline.
/// - Tag-stripping never trims individual inline segments (only whole
///   blocks, for the empty-block check) — trimming per-segment swallowed a
///   real, meaningful space sitting right after a closing tag in one
///   response (`"...CONDITIONS:</b> Apix Solutions..."` became
///   `"CONDITIONS:Apix Solutions"` with the words run together).
class HtmlBlocks extends StatelessWidget {
  final String html;
  const HtmlBlocks({super.key, required this.html});

  static final _blockRegex = RegExp(r'<(h1|h2|h3|p)\b[^>]*>(.*?)</\1>|<hr\b[^>]*/?>', dotAll: true, caseSensitive: false);
  static final _strongRegex = RegExp(r'<(?:strong|b)\b[^>]*>(.*?)</(?:strong|b)>', dotAll: true, caseSensitive: false);
  static final _tagRegex = RegExp(r'<[^>]+>');

  static String _decodeEntities(String s) => s
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");

  static String _stripTags(String s) => _decodeEntities(s.replaceAll(_tagRegex, ''));

  static Widget _richText(String inner, TextStyle baseStyle) {
    final collapsed = inner.replaceAll(RegExp(r'[\t ]*[\r\n]+[\t ]*'), ' ');
    final normalized = collapsed.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    final spans = <TextSpan>[];
    var last = 0;
    for (final m in _strongRegex.allMatches(normalized)) {
      if (m.start > last) {
        final plain = _stripTags(normalized.substring(last, m.start));
        if (plain.isNotEmpty) spans.add(TextSpan(text: plain, style: baseStyle));
      }
      final bold = _stripTags(m.group(1) ?? '');
      if (bold.isNotEmpty) spans.add(TextSpan(text: bold, style: baseStyle.copyWith(fontWeight: FontWeight.w700)));
      last = m.end;
    }
    if (last < normalized.length) {
      final plain = _stripTags(normalized.substring(last));
      if (plain.isNotEmpty) spans.add(TextSpan(text: plain, style: baseStyle));
    }
    return Text.rich(TextSpan(children: spans));
  }

  @override
  Widget build(BuildContext context) {
    const bodyStyle = TextStyle(fontSize: 13.5, height: 1.7, color: AppColors.ink);
    const h1Style = TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.navy, height: 1.4);
    const h2Style = TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700, color: AppColors.navy, height: 1.4);
    const h3Style = TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.navy, height: 1.4);

    final widgets = <Widget>[];
    for (final m in _blockRegex.allMatches(html)) {
      final full = m.group(0)!;
      if (full.toLowerCase().startsWith('<hr')) {
        widgets.add(const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(color: AppColors.line, height: 1)));
        continue;
      }
      final tag = m.group(1)!.toLowerCase();
      final inner = m.group(2) ?? '';
      if (_stripTags(inner).trim().isEmpty) continue; // e.g. an empty <p> used as a spacer
      final style = switch (tag) { 'h1' => h1Style, 'h2' => h2Style, 'h3' => h3Style, _ => bodyStyle };
      widgets.add(Padding(
        padding: EdgeInsets.only(bottom: tag == 'p' ? 10 : 6, top: tag == 'p' ? 0 : 4),
        child: _richText(inner, style),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: widgets);
  }
}
