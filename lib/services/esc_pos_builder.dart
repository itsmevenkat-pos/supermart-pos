/// Minimal ESC/POS command builder — hand-rolled rather than pulling in a
/// third-party package, since none of this can be tested against real
/// thermal-printer hardware in this environment and a small, fully-legible
/// implementation is easier to trust (and adjust later against a real
/// printer) than an opaque dependency of uncertain compatibility.
///
/// Covers the standard Epson-compatible command set most budget thermal
/// printers (SNBC, TVS, generic 58mm/80mm units, etc.) implement: init,
/// bold, double-size, alignment, and paper cut. If a specific printer
/// doesn't respond to one of these, that command is the one to adjust —
/// see the ESC/POS programming manual for that model.
class EscPosBuilder {
  final List<int> _bytes = [];

  /// 32 for 58mm paper, 48 for 80mm — the two common thermal receipt
  /// widths. Used to pad/align two-column lines (item name + price).
  final int charsPerLine;

  EscPosBuilder({this.charsPerLine = 32}) {
    _bytes.addAll([0x1B, 0x40]); // ESC @ — initialize printer
  }

  /// Encodes as single-byte ASCII. Most budget thermal printers use a
  /// single-byte codepage (often CP437 or similar), not UTF-8 — reliably
  /// encoding non-ASCII (₹, Tamil, etc.) would need that printer's exact
  /// codepage table, which varies by model/firmware and can't be
  /// determined without the real hardware. Anything outside printable
  /// ASCII becomes '?' so output stays legible rather than silently
  /// garbled — callers should pass "Rs." rather than "₹" here.
  void _write(String value) {
    for (final unit in value.codeUnits) {
      _bytes.add(unit >= 0x20 && unit <= 0x7E ? unit : 0x3F);
    }
  }

  void text(String value, {bool bold = false, bool doubleSize = false}) {
    if (bold) _bytes.addAll([0x1B, 0x45, 0x01]);
    if (doubleSize) _bytes.addAll([0x1D, 0x21, 0x11]);
    _write(value);
    _bytes.add(0x0A);
    if (doubleSize) _bytes.addAll([0x1D, 0x21, 0x00]);
    if (bold) _bytes.addAll([0x1B, 0x45, 0x00]);
  }

  void align(String alignment) {
    final code = switch (alignment) {
      'center' => 0x01,
      'right' => 0x02,
      _ => 0x00,
    };
    _bytes.addAll([0x1B, 0x61, code]);
  }

  void hr([String char = '-']) => text(char * charsPerLine);

  /// Left-aligned label + right-aligned value on one line — e.g. an item
  /// name and its price. Truncates an overlong label rather than wrapping,
  /// since a wrapped second line would break the right-alignment of value.
  void twoColumn(String left, String right, {bool bold = false}) {
    final maxLeft = charsPerLine - right.length - 1;
    final truncated = maxLeft > 0 && left.length > maxLeft ? left.substring(0, maxLeft) : left;
    final padding = charsPerLine - truncated.length - right.length;
    text('$truncated${' ' * (padding > 0 ? padding : 1)}$right', bold: bold);
  }

  void feed([int lines = 1]) {
    for (var i = 0; i < lines; i++) {
      _bytes.add(0x0A);
    }
  }

  /// Full cut (GS V 0). Some printers only support partial cut (GS V 1) —
  /// if the paper doesn't cut on a given model, that's the byte to change.
  void cut() => _bytes.addAll([0x1D, 0x56, 0x00]);

  List<int> build() => List.unmodifiable(_bytes);
}
