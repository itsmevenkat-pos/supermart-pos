import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../providers/quotation_provider.dart';
import '../../../providers/cart_provider.dart';
import '../../../repositories/product_repository.dart';
import '../../../models/quotation_model.dart';

class QuotationListScreen extends ConsumerStatefulWidget {
  const QuotationListScreen({super.key});

  @override
  ConsumerState<QuotationListScreen> createState() => _QuotationListScreenState();
}

class _QuotationListScreenState extends ConsumerState<QuotationListScreen> {
  bool _converting = false;

  Future<void> _convertToBill(Quotation quotation) async {
    if (quotation.status == 'converted') return;

    final existingCart = ref.read(cartProvider);
    if (existingCart.isNotEmpty) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Cart already has items'),
          content: Text(
            'Your current bill has ${existingCart.length} item${existingCart.length == 1 ? '' : 's'} in it. '
            "Add ${quotation.quoteNo}'s items on top of those?",
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add Anyway')),
          ],
        ),
      );
      if (proceed != true) return;
    }

    setState(() => _converting = true);
    try {
      final items = await ref.read(quotationNotifierProvider.notifier).getItems(quotation.id);
      if (items.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('This quotation has no saved items (it predates item tracking) — nothing to load.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final productRepo = ProductRepository();
      var missing = 0;
      for (final item in items) {
        final product = await productRepo.getById(item.productId);
        if (product == null) {
          missing++;
          continue;
        }
        ref.read(cartProvider.notifier).addItem(product, quantity: item.quantity);
      }

      await ref.read(quotationNotifierProvider.notifier).updateStatus(quotation.id, 'converted');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            missing > 0
                ? '${items.length - missing} item(s) added to the bill — $missing product(s) no longer exist.'
                : '${items.length} item(s) added to the bill.',
          ),
          backgroundColor: missing > 0 ? Colors.orange : Colors.green,
        ),
      );
      context.go('/billing');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not convert quotation: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _converting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final quotationsAsync = ref.watch(quotationNotifierProvider);

    return AppScaffold(
      title: 'Quotations',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () => ref.invalidate(quotationNotifierProvider),
        ),
      ],
      body: quotationsAsync.when(
        data: (quotations) {
          if (quotations.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.description, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('No quotations'),
                  SizedBox(height: 8),
                  Text('Create one from the billing screen', style: TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            );
          }
          return ListView.builder(
            itemCount: quotations.length,
            itemBuilder: (context, index) {
              final q = quotations[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: ListTile(
                  leading: const Icon(Icons.description),
                  title: Text(q.quoteNo),
                  subtitle: Text('${q.customerName} | ₹${q.netAmount.toStringAsFixed(2)}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Chip(
                        label: Text(q.status),
                        backgroundColor: q.status == 'converted' ? Colors.green : Colors.orange,
                        labelStyle: const TextStyle(color: Colors.white, fontSize: 10),
                      ),
                      if (q.status != 'converted')
                        IconButton(
                          icon: const Icon(Icons.point_of_sale, color: Colors.blue),
                          tooltip: 'Convert to Bill',
                          onPressed: _converting ? null : () => _convertToBill(q),
                        ),
                      IconButton(
                        icon: const Icon(Icons.print),
                        onPressed: () {
                          // Print quotation
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () {
                          ref.read(quotationNotifierProvider.notifier).deleteQuotation(q.id);
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
