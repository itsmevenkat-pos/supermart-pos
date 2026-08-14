import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../providers/purchase_provider.dart';
import '../../../models/purchase_model.dart';
import 'purchase_form_screen.dart';
import '../../../core/utils/quantity_utils.dart';

class PurchaseListScreen extends ConsumerStatefulWidget {
  const PurchaseListScreen({super.key});

  @override
  ConsumerState<PurchaseListScreen> createState() => _PurchaseListScreenState();
}

class _PurchaseListScreenState extends ConsumerState<PurchaseListScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final purchasesAsync = ref.watch(purchaseNotifierProvider);

    return AppScaffold(
      title: 'Purchases',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () => ref.read(purchaseNotifierProvider.notifier).refresh(),
        ),
      ],
      floatingActionButton: FloatingActionButton(
        onPressed: () => _navigateToForm(),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Search by GRN or supplier',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                setState(() {});
              },
            ),
          ),
          Expanded(
            child: purchasesAsync.when(
              data: (purchases) {
                final filtered = _searchController.text.isEmpty
                    ? purchases
                    : purchases.where((p) =>
                        p.grnNo.contains(_searchController.text) ||
                        (p.supplierName ?? '').contains(_searchController.text)).toList();
                if (filtered.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.receipt_long, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text('No purchases found'),
                        SizedBox(height: 8),
                        Text('Tap + to record a new purchase'),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (_, index) {
                    final p = filtered[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: ListTile(
                        leading: const Icon(Icons.receipt),
                        title: Text('GRN: ${p.grnNo}'),
                        subtitle: Text(
                          'Supplier: ${p.supplierName ?? "N/A"} | ₹${p.netAmount.toStringAsFixed(2)} | Qty: ${formatQty(p.totalQty)}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: p.received ? Colors.green : Colors.orange,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                p.received ? 'Received' : 'Pending',
                                style: const TextStyle(fontSize: 10, color: Colors.white),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit, size: 20),
                              onPressed: () => _navigateToForm(p),
                            ),
                          ],
                        ),
                        onTap: () => _navigateToForm(p),
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => Center(child: Text('Error: $err')),
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToForm([Purchase? purchase]) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PurchaseFormScreen(existingPurchase: purchase),
      ),
    ).then((_) => ref.read(purchaseNotifierProvider.notifier).refresh());
  }
}