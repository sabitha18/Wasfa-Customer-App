class Formatters {
  Formatters._();

  /// Kuwaiti Dinar formatting — 3 decimal places, mirrors JS `money()`.
  static String money(double value) => 'KWD ${value.toStringAsFixed(3)}';

  static String dateShort(DateTime d) => '${d.day}/${d.month}/${d.year}';

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  /// Reformats a date string into "Jun 17, 2026" — the display style the
  /// design uses everywhere a date shows up (Rx meta, order timestamps).
  /// Tolerant of whatever raw format the backend actually sends: confirmed
  /// against a real `/acct/rx` response that this can arrive as a full
  /// datetime like `"2026-07-18 08:01:34"` rather than a pre-formatted
  /// display string, which — printed as-is — looked broken next to the
  /// design's clean "Jun 17, 2026" style. `DateTime.parse` already accepts
  /// both `"yyyy-MM-dd HH:mm:ss"` and ISO 8601 forms, so no manual
  /// string-splitting is needed. Falls back to the original string
  /// unchanged if it doesn't parse as a date at all, rather than hiding it.
  static String displayDate(String raw) {
    final iso = DateTime.tryParse(raw);
    if (iso != null) return '${_months[iso.month - 1]} ${iso.day}, ${iso.year}';
    // Confirmed from the existing native app's own date parsing that Rx
    // dates can come back as "dd-MM-yyyy hh:mm a" (e.g. "17-06-2026 08:01
    // AM") — a format DateTime.tryParse doesn't understand at all, so that
    // attempt above silently fails and this needs its own parse instead of
    // just falling back to the raw string.
    final m = RegExp(r'^(\d{1,2})-(\d{1,2})-(\d{4})').firstMatch(raw.trim());
    if (m != null) {
      final day = int.tryParse(m.group(1)!);
      final month = int.tryParse(m.group(2)!);
      final year = int.tryParse(m.group(3)!);
      if (day != null && month != null && year != null && month >= 1 && month <= 12) {
        return '${_months[month - 1]} $day, $year';
      }
    }
    return raw;
  }

  /// A short "—" placeholder for a field that's blank/not filled in yet,
  /// rather than leaving a bare gap next to a bold label (e.g. Rx
  /// diagnosis/specialty before a pharmacist/doctor has filled it in).
  static String orDash(String value) => value.trim().isEmpty ? '—' : value;

  /// Strips a leading `+965`/`965` from a phone number for display.
  /// Confirmed live: `GET /acct/profile` returns `phone` already including
  /// `+965` (e.g. `"+96575598838"`) — but the profile form and account
  /// header both show their own separate, hardcoded "+965" box in front of
  /// the phone field, so without this the prefix showed up twice
  /// ("+965 +96575598838"). Only for display — the stored value itself is
  /// untouched everywhere else (checkout, OTP, etc. keep using the full
  /// canonical form).
  static String localPhone(String phone) => phone.replaceFirst(RegExp(r'^\+?965'), '');
}
