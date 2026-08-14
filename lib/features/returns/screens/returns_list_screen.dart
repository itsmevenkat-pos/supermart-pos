import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../models/sales_return_model.dart';
import '../../../providers/sales_return_provider.dart';

class ReturnsListScreen extends ConsumerWidget {
  const ReturnsListScreen({super.key});

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

  void _showDetail(BuildContext context, SalesReturn r) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(r.isUntied ? 'Untied Return' : 'Return'),
        content: SizedBox(
          width: 380,
          child: Consumer(
            builder: (context, ref, _) {
              final itemsAsync = ref.watch(returnItemsProvider(r.id));
              return itemsAsync.when(
                loading: () => const SizedBox(height: 80, child: Center(child: CircularProgressIndicator())),
                error: (e, _) => Text('Error: $e'),
                data: (items) => Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Reason: ${r.reason}'),
                    Text('Refund: ₹${r.refundAmount.toStringAsFixed(2)} via ${_refundMethodLabel(r.refundMethod)}'),
                    if (r.approvedByUserId != null) const Text('Manager-approved'),
                    const Divider(),
                    ...items.map((i) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text('${i.quantity} × ₹${i.unitPrice.toStringAsFixed(2)}'),
                          subtitle: Text(i.restocked ? 'Restocked' : 'Damaged / not restocked'),
                          trailing: Text('₹${i.totalPrice.toStringAsFixed(2)}'),
                        )),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final returnsAsync = ref.watch(recentReturnsProvider);

    return AppScaffold(
      title: 'Returns',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () => ref.invalidate(recentReturnsProvider),
        ),
      ],
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/returns/form'),
        icon: const Icon(Icons.add),
        label: const Text('New Return'),
      ),
      body: returnsAsync.when(
        data: (returns) {
          if (returns.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.assignment_return, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('No returns recorded yet'),
                ],
              ),
            );
          }
          return ListView.builder(
            itemCount: returns.length,
            itemBuilder: (_, index) {
              final r = returns[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: ListTile(
                  leading: Icon(r.isUntied ? Icons.help_outline : Icons.assignment_return),
                  title: Text('₹${r.refundAmount.toStringAsFixed(2)} — ${r.reason}'),
                  subtitle: Text(
                    '${_refundMethodLabel(r.refundMethod)} • '
                    '${DateTime.fromMillisecondsSinceEpoch(r.createdAt * 1000).toLocal().toString().split(' ')[0]}'
                    '${r.approvedByUserId != null ? ' • approved' : ''}',
                  ),
                  onTap: () => _showDetail(context, r),
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
