import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../providers/sale_provider.dart';
import '../../../repositories/sale_repository.dart';
import '../../../services/invoice_service.dart';

class SalesHistoryScreen extends ConsumerStatefulWidget {
  const SalesHistoryScreen({super.key});

  @override
  ConsumerState<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends ConsumerState<SalesHistoryScreen> {
  @override
  Widget build(BuildContext context) {
    final salesAsync = ref.watch(recentSalesProvider);

    return AppScaffold(
      title: 'Sales History',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () => ref.invalidate(recentSalesProvider),
        ),
      ],
      body: salesAsync.when(
        data: (sales) {
          if (sales.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.receipt_long, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('No sales yet'),
                ],
              ),
            );
          }
          return ListView.builder(
            itemCount: sales.length,
            itemBuilder: (_, index) {
              final sale = sales[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: ListTile(
                  leading: const Icon(Icons.receipt),
                  title: Text('Invoice ${sale.invoiceLabel}'),
                  subtitle: Text(
                    '₹${sale.netAmount.toStringAsFixed(2)} • '
                    '${DateTime.fromMillisecondsSinceEpoch(sale.createdAt * 1000).toLocal().toString().split(' ')[0]}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        sale.status,
                        style: TextStyle(
                          color: sale.status == 'completed' ? Colors.green : Colors.orange,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.assignment_return, size: 20),
                        tooltip: 'Return items from this sale',
                        onPressed: () => context.push('/returns/form?saleId=${sale.id}'),
                      ),
                      IconButton(
                        icon: const Icon(Icons.print, size: 20),
                        onPressed: () async {
                          final repo = SaleRepository();
                          final items = await repo.getItemsBySale(sale.id);
                          final service = InvoiceService();
                          final pdfData = await service.generateInvoice(
                            sale: sale,
                            items: items,
                            storeName: 'SuperMart POS',
                            storeAddress: '123 Main Street, City',
                            storePhone: '+91-9876543210',
                            storeGstin: '33ABCDE1234F1Z5',
                            storeFssai: '12421031000236',
                            // Reprints from history must be watermarked so
                            // they're never mistaken for the original bill.
                            isDuplicate: true,
                          );
                          // ✅ FIXED: Pass context to printPDF
                          await InvoiceService.printPDF(context, pdfData);
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
      ),
    );
  }
}