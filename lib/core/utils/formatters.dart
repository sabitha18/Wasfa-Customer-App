class Formatters {
  Formatters._();

  /// Kuwaiti Dinar formatting — 3 decimal places, mirrors JS `money()`.
  static String money(double value) => 'KWD ${value.toStringAsFixed(3)}';

  static String dateShort(DateTime d) => '${d.day}/${d.month}/${d.year}';
}
