import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'dart:io';
import 'esc_pos_builder.dart';
import 'network_printer.dart';
import 'windows_printer.dart';

class ThermalPrintService {
  /// Builds a full receipt as raw ESC/POS bytes — real thermal-printer
  /// output, not the PDF-via-OS-print-dialog fallback below. [items] takes
  /// the same `{name, qty, price}` map shape as [generatePDFReceipt].
  /// Currency is printed as "Rs." rather than "₹": most budget thermal
  /// printers use a single-byte codepage that doesn't include the rupee
  /// glyph — see EscPosBuilder's encoding note.
  static List<int> buildEscPosReceipt({
    required String storeName,
    String? storeAddress,
    String? storePhone,
    String? storeGstin,
    required String invoiceLabel,
    required DateTime date,
    required String customerName,
    required List<Map<String, dynamic>> items,
    required double subtotal,
    double tax = 0,
    double discount = 0,
    required double total,
    String footerMessage = 'Thank you! Visit again!',
    int charsPerLine = 32,
  }) {
    final b = EscPosBuilder(charsPerLine: charsPerLine);

    b.align('center');
    b.text(storeName, bold: true, doubleSize: true);
    if (storeAddress != null && storeAddress.isNotEmpty) b.text(storeAddress);
    if (storePhone != null && storePhone.isNotEmpty) b.text('Ph: $storePhone');
    if (storeGstin != null && storeGstin.isNotEmpty) b.text('GSTIN: $storeGstin');

    b.align('left');
    b.hr();
    b.text('Invoice: $invoiceLabel');
    b.text('Date: ${date.toLocal().toString().split('.').first}');
    b.text('Customer: $customerName');
    b.hr();

    for (final item in items) {
      final name = (item['name'] ?? '').toString();
      final qty = (item['qty'] as num).toDouble();
      final price = (item['price'] as num).toDouble();
      final lineTotal = qty * price;
      b.text(name);
      final qtyLabel = qty == qty.roundToDouble() ? qty.toStringAsFixed(0) : qty.toStringAsFixed(2);
      b.twoColumn('  $qtyLabel x Rs.${price.toStringAsFixed(2)}', 'Rs.${lineTotal.toStringAsFixed(2)}');
    }

    b.hr();
    b.twoColumn('Subtotal', 'Rs.${subtotal.toStringAsFixed(2)}');
    if (discount > 0) b.twoColumn('Discount', '-Rs.${discount.toStringAsFixed(2)}');
    if (tax > 0) b.twoColumn('Tax', 'Rs.${tax.toStringAsFixed(2)}');
    b.hr();
    b.twoColumn('TOTAL', 'Rs.${total.toStringAsFixed(2)}', bold: true);

    b.feed(1);
    b.align('center');
    b.text(footerMessage);
    b.feed(3);
    b.cut();

    return b.build();
  }

  /// Sends a receipt built by [buildEscPosReceipt] to whichever printer
  /// Settings → Thermal Printer has configured. [printerType] is
  /// `'network'` (TCP to [printerTarget]:[printerPort], default port 9100)
  /// or `'windows'` (raw bytes to the Windows printer named
  /// [printerTarget] via the spooler — see windows_printer.dart). Returns
  /// false on any failure so callers can fall back to [generatePDFReceipt]
  /// rather than leaving the cashier with no receipt at all.
  static Future<bool> printEscPos({
    required String printerType,
    required String printerTarget,
    int? printerPort,
    required List<int> receiptBytes,
  }) async {
    switch (printerType) {
      case 'network':
        return NetworkPrinter.printRawBytes(
          ipAddress: printerTarget,
          port: printerPort ?? 9100,
          bytes: receiptBytes,
        );
      case 'windows':
        return WindowsPrinter.printRawBytes(printerName: printerTarget, bytes: receiptBytes);
      default:
        return false;
    }
  }

  static Future<void> printReceipt({
    required int invoiceNo,
    String? invoiceLabel,
    required String customerName,
    required double total,
    required List<Map<String, dynamic>> items,
    required DateTime date,
  }) async {
    try {
      // For Windows, we'll use PDF generation as fallback
      // and later we can connect to thermal printer via USB/Bluetooth
      await generatePDFReceipt(
        invoiceNo: invoiceNo,
        invoiceLabel: invoiceLabel,
        customerName: customerName,
        total: total,
        items: items,
        date: date,
      );
    } catch (e) {
      print('Print error: $e');
    }
  }

  static Future<void> generatePDFReceipt({
    required int invoiceNo,
    String? invoiceLabel,
    required String customerName,
    required double total,
    required List<Map<String, dynamic>> items,
    required DateTime date,
  }) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text('SUPERMART POS', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 8),
              pw.Text('Invoice ${invoiceLabel ?? '#$invoiceNo'}'),
              pw.Text('Date: ${date.toLocal().toString().split(' ')[0]}'),
              pw.Text('Customer: $customerName'),
              pw.Divider(),
              pw.SizedBox(height: 8),
              // Headers
              pw.Row(
                children: [
                  pw.Expanded(child: pw.Text('Item', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                  pw.Expanded(child: pw.Text('Qty', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                  pw.Expanded(child: pw.Text('Price', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                  pw.Expanded(child: pw.Text('Total', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                ],
              ),
              pw.Divider(),
              ...items.map((item) => pw.Row(
                children: [
                  pw.Expanded(child: pw.Text(item['name'] ?? '')),
                  pw.Expanded(child: pw.Text(item['qty'].toString())),
                  pw.Expanded(child: pw.Text('₹${item['price'].toStringAsFixed(2)}')),
                  pw.Expanded(child: pw.Text('₹${(item['qty'] * item['price']).toStringAsFixed(2)}')),
                ],
              )),
              pw.Divider(),
              pw.SizedBox(height: 8),
              pw.Row(
                children: [
                  pw.Expanded(child: pw.Text('Total:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                  pw.Expanded(child: pw.Text('₹${total.toStringAsFixed(2)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                ],
              ),
              pw.SizedBox(height: 16),
              pw.Text('Thank you! Visit again!', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            ],
          );
        },
      ),
    );

    // Save PDF to temp directory
    final tempDir = Directory.systemTemp;
    final file = File('${tempDir.path}/receipt_$invoiceNo.pdf');
    await file.writeAsBytes(await pdf.save());
    print('PDF saved to: ${file.path}');
  }
}