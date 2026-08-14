import 'dart:typed_data';
import 'package:barcode/barcode.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/product_model.dart';

/// Generates and prints Code128 barcode labels for products.
///
/// Uses the same `pdf` + `printing` packages already used by
/// InvoiceService/ThermalPrintService — barcode rendering comes from the
/// `barcode` package, which `pdf` already depends on internally for its
/// `pw.BarcodeWidget`. Add `barcode: ^2.2.7` to pubspec.yaml if it isn't
/// already listed as a direct dependency.
class BarcodeLabelService {
  /// One label = 50mm x 25mm, a common thermal barcode-label roll size.
  /// Each label is its own PDF page, so on a label printer each page is
  /// one sticker; on a normal printer it just prints one small page per
  /// copy.
  static const PdfPageFormat _labelFormat = PdfPageFormat(
    50 * PdfPageFormat.mm,
    25 * PdfPageFormat.mm,
    marginAll: 2 * PdfPageFormat.mm,
  );

  /// Builds a PDF with [copies] repeated labels for a single product —
  /// e.g. printing 20 copies of one SKU's barcode to stick on 20 units.
  static Future<Uint8List> generateLabels(Product product, {int copies = 1}) async {
    final pdf = pw.Document();
    for (var i = 0; i < copies; i++) {
      pdf.addPage(
        pw.Page(
          pageFormat: _labelFormat,
          build: (context) => _buildLabel(product),
        ),
      );
    }
    return pdf.save();
  }

  /// Builds A4 sheets of labels (3 per row) for printing several different
  /// products at once on a normal printer — e.g. after a stock intake
  /// where a batch of new SKUs all need labels.
  static Future<Uint8List> generateLabelSheet(List<Product> products) async {
    final pdf = pw.Document();
    const columns = 3;
    const rowsPerPage = 8;
    const perPage = columns * rowsPerPage;

    for (var start = 0; start < products.length; start += perPage) {
      final pageItems = products.skip(start).take(perPage).toList();
      final rows = <pw.Widget>[];
      for (var i = 0; i < pageItems.length; i += columns) {
        final rowItems = pageItems.skip(i).take(columns).toList();
        rows.add(
          pw.Row(
            children: [
              for (final p in rowItems)
                pw.Expanded(
                  child: pw.Container(
                    margin: const pw.EdgeInsets.all(3),
                    padding: const pw.EdgeInsets.all(4),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(width: 0.5, color: PdfColors.grey400),
                    ),
                    child: _buildLabel(p),
                  ),
                ),
              // Pad the row so a partial last row doesn't stretch its
              // real labels to fill the missing columns' width.
              for (var pad = rowItems.length; pad < columns; pad++) pw.Expanded(child: pw.Container()),
            ],
          ),
        );
      }
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(10),
          build: (context) => pw.Column(children: rows),
        ),
      );
    }
    return pdf.save();
  }

  static pw.Widget _buildLabel(Product product) {
    final displayName = (product.displayName?.isNotEmpty ?? false) ? product.displayName! : product.name;
    return pw.Column(
      mainAxisAlignment: pw.MainAxisAlignment.center,
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(
          displayName,
          maxLines: 1,
          overflow: pw.TextOverflow.clip,
          style: const pw.TextStyle(fontSize: 8),
          textAlign: pw.TextAlign.center,
        ),
        pw.SizedBox(height: 2),
        pw.BarcodeWidget(
          barcode: Barcode.code128(),
          data: product.barcode,
          width: 140,
          height: 40,
          drawText: false,
        ),
        pw.SizedBox(height: 2),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          children: [
            pw.Text(product.barcode, style: const pw.TextStyle(fontSize: 7)),
            pw.SizedBox(width: 8),
            pw.Text(
              'MRP Rs.${product.mrp.toStringAsFixed(2)}',
              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
            ),
          ],
        ),
      ],
    );
  }

  /// Opens the OS printer picker and sends the labels straight to the
  /// chosen printer/label printer — same pattern as InvoiceService.printPDF.
  static Future<void> printLabels(BuildContext context, Uint8List pdfData) async {
    final printer = await Printing.pickPrinter(context: context);
    if (printer == null) return; // user cancelled the picker
    await Printing.directPrintPdf(printer: printer, onLayout: (_) => pdfData);
  }

  /// Falls back to the OS default print dialog/preview instead of the
  /// in-app printer picker.
  static Future<void> printLabelsDefault(Uint8List pdfData) async {
    await Printing.layoutPdf(onLayout: (_) => pdfData);
  }
}
