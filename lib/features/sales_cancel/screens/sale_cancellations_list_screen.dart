import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../models/sale_cancellation_model.dart';
import '../../../models/sale_model.dart';
import '../../../repositories/sale_cancellation_repository.dart';
import '../../../repositories/sale_repository.dart';

/// Recent cancellations for the list screen — plain FutureProvider (not
/// riverpod codegen), matching `recentReturnsProvider`'s convention.
final recentSaleCancellationsProvider = FutureProvider<List<SaleCancellation>>((ref) async {
  final repo = ref.watch(saleCancellationRepositoryProvider);
  return repo.getRecent();
});

class SaleCancellationsListScreen extends ConsumerWidget {
  const SaleCancellationsListScreen({super.key});

  String _refundMethodLabel(String method) {
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cancellationsAsync = ref.watch(recentSaleCancellationsProvider);

    return AppScaffold(
      title: 'Sale Cancellations',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () => ref.invalidate(recentSaleCancellationsProvider),
        ),
      ],
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/sales-cancellations/form'),
        icon: const Icon(Icons.add),
        label: const Text('Cancel a Sale'),
      ),
      body: cancellationsAsync.when(
        data: (cancellations) {
          if (cancellations.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.cancel_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('No sale cancellations recorded yet'),
                ],
              ),
            );
          }
          return ListView.builder(
            itemCount: cancellations.length,
            itemBuilder: (_, index) {
              final c = cancellations[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: ListTile(
                  leading: const Icon(Icons.cancel_outlined),
                  title: Text('₹${c.refundAmount.toStringAsFixed(2)} — ${c.reason}'),
                  subtitle: FutureBuilder<Sale?>(
                    future: SaleRepository().getById(c.saleId),
                    builder: (context, snapshot) {
                      final invoiceLabel = snapshot.data?.invoiceLabel ?? c.saleId;
                      return Text(
                        'Invoice $invoiceLabel • ${_refundMethodLabel(c.refundMethod)} • '
                        '${DateTime.fromMillisecondsSinceEpoch(c.createdAt * 1000).toLocal().toString().split(' ')[0]}'
                        '${c.approvedByUserId != null ? ' • approved' : ''}',
                      );
                    },
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
