/// India's financial year runs 1 April – 31 March. Returns the short label
/// used in invoice numbers, e.g. 12 Aug 2026 -> "26-27", 15 Jan 2026 -> "25-26".
String financialYearLabel(DateTime date) {
  final startYear = date.month >= 4 ? date.year : date.year - 1;
  final endYearShort = (startYear + 1) % 100;
  return '${_twoDigit(startYear % 100)}-${_twoDigit(endYearShort)}';
}

String _twoDigit(int year) => year.toString().padLeft(2, '0');
