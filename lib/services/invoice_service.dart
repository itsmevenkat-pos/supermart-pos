import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/sale_model.dart';
import '../models/sale_item_model.dart';
import '../repositories/product_repository.dart';
import '../repositories/customer_repository.dart';
import '../core/utils/quantity_utils.dart';

/// Injected via constructor so tests can pass fake repositories instead of
/// hitting the real SQLite database. Existing call sites that used
/// `InvoiceService()` still compile unchanged because both repositories
/// default to their own singleton-backed instances.
class InvoiceService {
  InvoiceService({
    ProductRepository? productRepo,
    CustomerRepository? customerRepo,
  })  : _productRepo = productRepo ?? ProductRepository(),
        _customerRepo = customerRepo ?? CustomerRepository();

  final ProductRepository _productRepo;
  final CustomerRepository _customerRepo;

  Future<Uint8List> generateInvoice({
    required Sale sale,
    required List<SaleItem> items,
    required String storeName,
    required String storeAddress,
    required String storePhone,
    required String storeGstin,
    required String storeFssai,
    double? cashReceived,
    double? changeDue,
    bool isDuplicate = false,
  }) async {
    final pdf = pw.Document();

    final customer = sale.customerId != null
        ? await _customerRepo.getById(sale.customerId!)
        : null;

    final productNames = <String, String>{};
    for (final item in items) {
      final product = await _productRepo.getById(item.productId);
      if (product != null) {
        productNames[item.productId] = product.displayName ?? product.name;
      } else {
        productNames[item.productId] = 'Product ${item.productId}';
      }
    }

    pdf.addPage(
      pw.MultiPage(
        // Watermark is drawn via `pageTheme.buildBackground` so it repeats
        // on every page behind the content without altering the foreground
        // layout. `pageFormat`/`margin` move into the theme because the pdf
        // package forbids setting both pageTheme and pageFormat/margin.
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(20),
          buildBackground: isDuplicate
              ? (context) => pw.Center(
                    child: pw.Transform.rotate(
                      angle: -30 * math.pi / 180,
                      child: pw.Text(
                        'DUPLICATE',
                        style: pw.TextStyle(
                          fontSize: 80,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.grey300,
                        ),
                      ),
                    ),
                  )
              : null,
        ),
        build: (context) => [
          pw.Container(
            alignment: pw.Alignment.centerLeft,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(storeName, style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 4),
                pw.Text(storeAddress, style: const pw.TextStyle(fontSize: 12)),
                pw.Text('Phone: $storePhone', style: const pw.TextStyle(fontSize: 12)),
                if (storeGstin.isNotEmpty) pw.Text('GSTIN: $storeGstin', style: const pw.TextStyle(fontSize: 12)),
                if (storeFssai.isNotEmpty) pw.Text('FSSAI: $storeFssai', style: const pw.TextStyle(fontSize: 12)),
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
                  pw.Text('Invoice ${sale.invoiceLabel}', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                  pw.Text('Date: ${DateTime.fromMillisecondsSinceEpoch(sale.createdAt * 1000).toLocal().toString().split(' ')[0]}'),
                  pw.Text('Time: ${DateTime.fromMillisecondsSinceEpoch(sale.createdAt * 1000).toLocal().toString().split(' ')[1]}'),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('Customer: ${customer?.name ?? 'Guest'}'),
                  pw.Text('Phone: ${customer?.phone ?? ''}'),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.Table(
            border: pw.TableBorder.all(),
            columnWidths: {
              0: const pw.FlexColumnWidth(0.5),
              1: const pw.FlexColumnWidth(3),
              2: const pw.FlexColumnWidth(1),
              3: const pw.FlexColumnWidth(1.5),
              4: const pw.FlexColumnWidth(1.5),
            },
            children: [
              pw.TableRow(
                children: [
                  pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('#', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                  pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Product', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                  pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Qty', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                  pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Rate', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                  pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Total', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                ],
              ),
              ...items.asMap().entries.map((entry) {
                final idx = entry.key + 1;
                final item = entry.value;
                final productName = productNames[item.productId] ?? 'Product ${item.productId}';
                return pw.TableRow(
                  children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(idx.toString())),
                    pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(productName)),
                    pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(formatQty(item.quantity))),
                    pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('₹${item.unitPrice.toStringAsFixed(2)}')),
                    pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('₹${item.totalPrice.toStringAsFixed(2)}')),
                  ],
                );
              }),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Row(children: [pw.SizedBox(width: 100), pw.Text('Subtotal: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)), pw.Text('₹${sale.subtotal.toStringAsFixed(2)}')]),
                  pw.Row(children: [pw.SizedBox(width: 100), pw.Text('Tax: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)), pw.Text('₹${sale.taxTotal.toStringAsFixed(2)}')]),
                  if (sale.discountTotal > 0) pw.Row(children: [pw.SizedBox(width: 100), pw.Text('Discount: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)), pw.Text('-₹${sale.discountTotal.toStringAsFixed(2)}')]),
                  if (sale.deliveryCharge > 0) pw.Row(children: [pw.SizedBox(width: 100), pw.Text('Delivery: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)), pw.Text('₹${sale.deliveryCharge.toStringAsFixed(2)}')]),
                  pw.Divider(thickness: 2),
                  pw.Row(children: [pw.SizedBox(width: 100), pw.Text('Total: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16)), pw.Text('₹${sale.netAmount.toStringAsFixed(2)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16))]),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 16),
          if (sale.paymentMethods != null && sale.paymentMethods!.isNotEmpty) ...{
            pw.Text('Payment:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            ...sale.paymentMethods!.entries.map((entry) => pw.Text('${entry.key.toUpperCase()}: ₹${entry.value.toStringAsFixed(2)}')),
          },
          if (sale.partialPaymentAmount != null && sale.partialPaymentAmount! > 0) pw.Text('Partial Payment: ₹${sale.partialPaymentAmount!.toStringAsFixed(2)}'),
          if (sale.creditUsed != null && sale.creditUsed! > 0) pw.Text('Credit Used: ₹${sale.creditUsed!.toStringAsFixed(2)}'),
          if (cashReceived != null && cashReceived > 0) pw.Text('Cash Received: ₹${cashReceived.toStringAsFixed(2)}'),
          if (changeDue != null && changeDue > 0) pw.Text('Change Returned: ₹${changeDue.toStringAsFixed(2)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          if (sale.isDelivery) pw.Text('Delivery Address: ${sale.deliveryAddress ?? ''}'),
          pw.SizedBox(height: 16),
          pw.Container(
            alignment: pw.Alignment.center,
            child: pw.Text('Thank you for shopping with us!', style: pw.TextStyle(fontSize: 14, fontStyle: pw.FontStyle.italic)),
          ),
        ],
      ),
    );

    return pdf.save();
  }

  Future<Uint8List> generateThermalReceipt({
    required Sale sale,
    required List<SaleItem> items,
    required String storeName,
    required String storeAddress,
    required String storePhone,
    required String storeGstin,
    double? cashReceived,
    double? changeDue,
  }) async {
    final pdf = pw.Document();

    final productNames = <String, String>{};
    for (final item in items) {
      final product = await _productRepo.getById(item.productId);
      if (product != null) {
        productNames[item.productId] = product.displayName ?? product.name;
      } else {
        productNames[item.productId] = 'Product ${item.productId}';
      }
    }

    pdf.addPage(
      pw.Page(
        pageFormat: const PdfPageFormat(58 * PdfPageFormat.mm, double.infinity),
        margin: const pw.EdgeInsets.all(8),
        build: (context) {
          return pw.Column(
            children: [
              pw.Text(storeName, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
              pw.Text(storeAddress, style: const pw.TextStyle(fontSize: 8)),
              pw.Text('Ph: $storePhone', style: const pw.TextStyle(fontSize: 8)),
              if (storeGstin.isNotEmpty) pw.Text('GSTIN: $storeGstin', style: const pw.TextStyle(fontSize: 8)),
              pw.Divider(thickness: 1),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Invoice: ${sale.invoiceLabel}', style: const pw.TextStyle(fontSize: 8)),
                  pw.Text(DateTime.fromMillisecondsSinceEpoch(sale.createdAt * 1000).toLocal().toString().split(' ')[0], style: const pw.TextStyle(fontSize: 8)),
                ],
              ),
              pw.Divider(thickness: 1),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Product', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                  pw.Text('Qty', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                  pw.Text('Price', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                  pw.Text('Total', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                ],
              ),
              ...items.map((item) {
                final name = productNames[item.productId] ?? 'Product';
                return pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Expanded(child: pw.Text(name, style: const pw.TextStyle(fontSize: 8))),
                    pw.Text(formatQty(item.quantity), style: const pw.TextStyle(fontSize: 8)),
                    pw.Text('₹${item.unitPrice.toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 8)),
                    pw.Text('₹${item.totalPrice.toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 8)),
                  ],
                );
              }),
              pw.Divider(thickness: 1),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Total:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                  pw.Text('₹${sale.netAmount.toStringAsFixed(2)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                ],
              ),
              if (cashReceived != null && cashReceived > 0)
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Cash Received:', style: const pw.TextStyle(fontSize: 8)),
                    pw.Text('₹${cashReceived.toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 8)),
                  ],
                ),
              if (changeDue != null && changeDue > 0)
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Change Returned:', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                    pw.Text('₹${changeDue.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
              pw.SizedBox(height: 4),
              pw.Text('Thank you!', style: pw.TextStyle(fontSize: 10, fontStyle: pw.FontStyle.italic)),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  /// Opens the OS printer picker and prints directly to the chosen printer.
  /// Requires a real [BuildContext] (used to anchor the picker dialog) and
  /// returns without printing if the user cancels the picker.
  static Future<void> printPDF(BuildContext context, Uint8List pdfData) async {
    final Printer? printer = await Printing.pickPrinter(context: context);
    if (printer == null) {
      // User cancelled the printer picker — nothing to print.
      return;
    }
    await Printing.directPrintPdf(
      printer: printer,
      onLayout: (_) => pdfData,
    );
  }

  static Future<void> printPDFDefault(Uint8List pdfData) async {
    await Printing.layoutPdf(
      onLayout: (_) => pdfData,
    );
  }
}

/// Riverpod provider — override this in tests with a fake InvoiceService
/// built from fake repositories, e.g.:
///   ProviderScope(overrides: [
///     invoiceServiceProvider.overrideWithValue(
///       InvoiceService(productRepo: fakeProducts, customerRepo: fakeCustomers),
///     ),
///   ])
final invoiceServiceProvider = Provider<InvoiceService>((ref) {
  return InvoiceService(
    productRepo: ref.watch(productRepositoryProvider),
    customerRepo: ref.watch(customerRepositoryProvider),
  );
});