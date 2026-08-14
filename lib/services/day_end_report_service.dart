import 'dart:typed_data';
import 'package:flutter/widgets.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/session_model.dart';
import '../models/user_model.dart';
import 'sales_summary_service.dart';

/// Builds and prints the Day-End / Z Report — a printable summary of a
/// closed counter session's cash reconciliation and payment-method mix.
///
/// Mirrors the static-methods style of BarcodeLabelService and reuses the
/// same `pdf` + `printing` packages already used by InvoiceService, so the
/// printed output looks consistent with invoices/labels elsewhere in the
/// app. Per-payment-method totals are not tracked on [Session] itself, so
/// this pulls them from SalesSummaryService instead of recomputing them.
class DayEndReportService {
  /// Builds the report PDF for a closed [session]. [cashier] is the user
  /// who ran the shift (shown as "Cashier" on the report). Store details
  /// default to the same values used on invoices (see billing_screen.dart)
  /// but can be overridden if needed.
  static Future<Uint8List> generateReport({
    required Session session,
    required User cashier,
    String storeName = 'SuperMart POS',
    String storeAddress = '123 Main Street, City',
    String storePhone = '+91-9876543210',
  }) async {
    final openedAt = DateTime.fromMillisecondsSinceEpoch(session.openingTime * 1000).toLocal();
    final closedAt = session.closingTime != null
        ? DateTime.fromMillisecondsSinceEpoch(session.closingTime! * 1000).toLocal()
        : DateTime.now();

    final summary = await SalesSummaryService().getSummary(
      from: openedAt,
      to: closedAt,
      userId: session.userId,
    );

    final expectedCash = session.expectedCash ?? session.openingCash;
    final countedCash = session.closingCash ?? 0;
    final diff = session.difference ?? (countedCash - expectedCash);
    final diffLabel = diff < 0 ? 'Shortage' : (diff > 0 ? 'Overage' : 'Balanced');

    final totalSales = (summary['totalSales'] as num?)?.toDouble() ?? 0;
    final totalCount = summary['totalCount'] as int? ?? 0;
    final cashTotal = (summary['cash'] as num?)?.toDouble() ?? 0;
    final upiTotal = (summary['upi'] as num?)?.toDouble() ?? 0;
    final cardTotal = (summary['card'] as num?)?.toDouble() ?? 0;
    final creditTotal = (summary['credit'] as num?)?.toDouble() ?? 0;

    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        build: (context) => [
          pw.Container(
            alignment: pw.Alignment.centerLeft,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(storeName, style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 4),
                pw.Text(storeAddress, style: const pw.TextStyle(fontSize: 11)),
                pw.Text('Phone: $storePhone', style: const pw.TextStyle(fontSize: 11)),
                pw.SizedBox(height: 10),
                pw.Text(
                  'DAY-END / Z REPORT',
                  style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 8),
                pw.Divider(thickness: 2),
              ],
            ),
          ),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Cashier: ${cashier.name}'),
                  pw.Text('Report Generated: ${DateTime.now().toLocal().toString().split('.')[0]}'),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('Session Opened: ${openedAt.toString().split('.')[0]}'),
                  pw.Text('Session Closed: ${closedAt.toString().split('.')[0]}'),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 20),
          pw.Text('Cash Reconciliation', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400),
            columnWidths: {0: const pw.FlexColumnWidth(2), 1: const pw.FlexColumnWidth(1)},
            children: [
              _reportRow('Opening Cash', session.openingCash),
              _reportRow('Expected Cash in Drawer', expectedCash),
              _reportRow('Actual Cash Counted', countedCash),
              _reportRow(diffLabel, diff.abs(), bold: true),
            ],
          ),
          pw.SizedBox(height: 20),
          pw.Text('Sales Summary', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400),
            columnWidths: {0: const pw.FlexColumnWidth(2), 1: const pw.FlexColumnWidth(1)},
            children: [
              _reportRow('Total Sales', totalSales, bold: true),
              _reportTextRow('Total Transactions', totalCount.toString()),
            ],
          ),
          pw.SizedBox(height: 20),
          pw.Text('Payment Method Breakdown', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400),
            columnWidths: {0: const pw.FlexColumnWidth(2), 1: const pw.FlexColumnWidth(1)},
            children: [
              _reportRow('Cash', cashTotal),
              _reportRow('UPI', upiTotal),
              _reportRow('Card', cardTotal),
              _reportRow('Credit', creditTotal),
            ],
          ),
          if (session.notes != null && session.notes!.isNotEmpty) ...[
            pw.SizedBox(height: 20),
            pw.Text('Notes', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text(session.notes!),
          ],
          pw.SizedBox(height: 24),
          pw.Container(
            alignment: pw.Alignment.center,
            child: pw.Text(
              'End of Day-End Report',
              style: pw.TextStyle(fontSize: 11, fontStyle: pw.FontStyle.italic),
            ),
          ),
        ],
      ),
    );

    return pdf.save();
  }

  static pw.TableRow _reportRow(String label, double amount, {bool bold = false}) {
    final style = pw.TextStyle(fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal);
    return pw.TableRow(
      children: [
        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(label, style: style)),
        pw.Padding(
          padding: const pw.EdgeInsets.all(6),
          child: pw.Text('₹${amount.toStringAsFixed(2)}', style: style),
        ),
      ],
    );
  }

  static pw.TableRow _reportTextRow(String label, String value, {bool bold = false}) {
    final style = pw.TextStyle(fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal);
    return pw.TableRow(
      children: [
        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(label, style: style)),
        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(value, style: style)),
      ],
    );
  }

  /// Opens the OS printer picker and prints directly to the chosen printer —
  /// same pattern as InvoiceService.printPDF / BarcodeLabelService.printLabels.
  static Future<void> printReport(BuildContext context, Uint8List pdfData) async {
    final printer = await Printing.pickPrinter(context: context);
    if (printer == null) return; // user cancelled the picker
    await Printing.directPrintPdf(printer: printer, onLayout: (_) => pdfData);
  }

  /// Falls back to the OS default print dialog/preview.
  static Future<void> printReportDefault(Uint8List pdfData) async {
    await Printing.layoutPdf(onLayout: (_) => pdfData);
  }
}
