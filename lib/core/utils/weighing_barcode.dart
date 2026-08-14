/// Decoded contents of a weighing-scale barcode — either an embedded
/// weight (grams) or an embedded total price (paise), depending on how
/// the store's scale is configured.
class WeighingBarcodeResult {
  final String itemCode;
  final double weightKg;
  final double? priceRupees;

  const WeighingBarcodeResult({
    required this.itemCode,
    this.weightKg = 0,
    this.priceRupees,
  });
}

/// Decodes a 13-digit weighing-scale barcode of the form:
/// `[prefix: 2 digits][item code: 5 digits][value: 5 digits][check digit: 1 digit]`
///
/// This 2+5+5+1 split (item code then either weight-in-grams or
/// price-in-paise) is the most common convention among Indian retail
/// weighing scales, but isn't universal hardware-to-hardware. [prefix]
/// (from Settings → Weighing Scale Barcodes) is the one piece that
/// definitely varies store to store — commonly "20"–"29" — and disables
/// this entirely when empty, so a normal 13-digit product barcode that
/// happens to start with a digit never gets misread as a weight. If a
/// specific scale uses a different digit layout, adjust the slicing below
/// to match its manual rather than guessing further from here.
WeighingBarcodeResult? decodeWeighingBarcode(
  String barcode, {
  required String prefix,
  required String valueType,
}) {
  if (prefix.isEmpty) return null;
  if (barcode.length != 13) return null;
  if (!barcode.startsWith(prefix)) return null;

  final itemCode = barcode.substring(2, 7);
  final valueDigits = barcode.substring(7, 12);
  final valueInt = int.tryParse(valueDigits);
  if (valueInt == null) return null;

  if (valueType == 'price_paise') {
    return WeighingBarcodeResult(itemCode: itemCode, priceRupees: valueInt / 100);
  }
  return WeighingBarcodeResult(itemCode: itemCode, weightKg: valueInt / 1000);
}
