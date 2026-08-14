/// Formats a quantity for display: whole numbers show with no decimal
/// point ("5" not "5.0"), fractional quantities show up to 3 decimal
/// places with trailing zeros trimmed ("0.5", "2.25", "1.333").
///
/// Needed because quantities are now `double` throughout (loose items like
/// vegetables, meat, and other weighed goods need fractional units), and
/// raw `double.toString()` output (e.g. "5.0" or floating-point noise like
/// "0.30000000000000004") is not something you want on a bill.
String formatQty(double qty) {
  if (qty == qty.truncateToDouble()) {
    return qty.toInt().toString();
  }
  String s = qty.toStringAsFixed(3);
  while (s.endsWith('0')) {
    s = s.substring(0, s.length - 1);
  }
  if (s.endsWith('.')) {
    s = s.substring(0, s.length - 1);
  }
  return s;
}

/// Parses user-entered quantity text, accepting both whole numbers and
/// decimals. Returns null for invalid/empty input so callers can decide
/// how to handle it (e.g. keep the previous value).
double? parseQty(String text) => double.tryParse(text.trim());