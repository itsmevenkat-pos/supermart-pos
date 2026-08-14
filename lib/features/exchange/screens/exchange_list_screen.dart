import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../models/exchange_model.dart';
import '../../../repositories/customer_repository.dart';
import '../../../repositories/exchange_repository.dart';
import '../../../repositories/sale_repository.dart';
import '../../../repositories/sales_return_repository.dart';

/// An [Exchange] row enriched with the display labels a list needs — the
/// original sale's invoice (via its return header), the new sale's invoice,
/// and the customer name — none of which live directly on [Exchange].
class _ExchangeRow {
  final Exchange exchange;
  final String? originalInvoiceLabel;
  final String? newInvoiceLabel;
  final String? customerName;

  _ExchangeRow({
    required this.exchange,
    this.originalInvoiceLabel,
    this.newInvoiceLabel,
    this.customerName,
  });
}

/// Plain FutureProvider (not riverpod codegen) to match the Returns feature's
/// `recentReturnsProvider` convention and avoid a build_runner step.
final _recentExchangeRowsProvider = FutureProvider<List<_ExchangeRow>>((ref) async {
  final exchangeRepo = ref.watch(exchangeRepositoryProvider);
  final returnRepo = SalesReturnRepository();
  final saleRepo = SaleRepository();
  final customerRepo = CustomerRepository();

  final exchanges = await exchangeRepo.getRecent();
  final rows = <_ExchangeRow>[];
  for (final exchange in exchanges) {
    final returnHeader = await returnRepo.getById(exchange.returnId);
    String? originalLabel;
    if (returnHeader?.saleId != null) {
      final originalSale = await saleRepo.getById(returnHeader!.saleId!);
      originalLabel = originalSale?.invoiceLabel;
    }
    String? newLabel;
    if (exchange.newSaleId != null) {
      final newSale = await saleRepo.getById(exchange.newSaleId!);
      newLabel = newSale?.invoiceLabel;
    }
    String? customerName;
    if (exchange.customerId != null) {
      final customer = await customerRepo.getById(exchange.customerId!);
      customerName = customer?.name;
    }
    rows.add(_ExchangeRow(
      exchange: exchange,
      originalInvoiceLabel: originalLabel,
      newInvoiceLabel: newLabel,
      customerName: customerName,
    ));
  }
  return rows;
});

String _settlementMethodLabel(String method) {
  switch (method) {
    case 'upi':
      return 'UPI';
    case 'card':
      return 'Card';
    case 'credit_adjust':
      return 'Adjusted against credit';
    default:
      return 'Cash';
  }
}

class ExchangeListScreen extends ConsumerWidget {
  const ExchangeListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rowsAsync = ref.watch(_recentExchangeRowsProvider);

    return AppScaffold(
      title: 'Exchanges',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () => ref.invalidate(_recentExchangeRowsProvider),
        ),
      ],
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/exchanges/form'),
        icon: const Icon(Icons.add),
        label: const Text('New Exchange'),
      ),
      body: rowsAsync.when(
        data: (rows) {
          if (rows.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.swap_horiz, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('No exchanges recorded yet'),
                ],
              ),
            );
          }
          return ListView.builder(
            itemCount: rows.length,
            itemBuilder: (_, index) {
              final row = rows[index];
              final diff = row.exchange.priceDifference;
              // Positive = customer owes more (red); negative = refund due
              // to the customer (green); zero = even exchange (neutral).
              final diffColor = diff > 0 ? Colors.red : (diff < 0 ? Colors.green : Colors.grey);
              final diffLabel = diff > 0
                  ? 'Customer owes ₹${diff.toStringAsFixed(2)}'
                  : diff < 0
                      ? 'Refund ₹${(-diff).toStringAsFixed(2)}'
                      : 'No difference';
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: ListTile(
                  leading: const Icon(Icons.swap_horiz),
                  title: Text(
                    '${row.originalInvoiceLabel ?? 'Untied'} → ${row.newInvoiceLabel ?? '—'}',
                  ),
                  subtitle: Text(
                    '${row.customerName ?? 'Walk-in customer'} • '
                    '${_settlementMethodLabel(row.exchange.settlementMethod)} • '
                    '${DateTime.fromMillisecondsSinceEpoch(row.exchange.createdAt * 1000).toLocal().toString().split(' ')[0]}',
                  ),
                  trailing: Text(
                    diffLabel,
                    style: TextStyle(color: diffColor, fontWeight: FontWeight.w600),
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
