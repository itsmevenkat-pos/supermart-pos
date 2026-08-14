import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../providers/supplier_provider.dart';
import '../../../models/supplier_model.dart';
import 'supplier_form_screen.dart';

class SupplierListScreen extends ConsumerStatefulWidget {
  const SupplierListScreen({super.key});

  @override
  ConsumerState<SupplierListScreen> createState() => _SupplierListScreenState();
}

class _SupplierListScreenState extends ConsumerState<SupplierListScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final suppliersAsync = ref.watch(supplierNotifierProvider);

    return AppScaffold(
      title: 'Suppliers',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () => ref.invalidate(supplierNotifierProvider),
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
              decoration: const InputDecoration(hintText: 'Search by name or phone', prefixIcon: Icon(Icons.search), border: OutlineInputBorder()),
              onChanged: (value) {
                if (value.isNotEmpty) {
                  ref.read(supplierNotifierProvider.notifier).search(value);
                } else {
                  ref.invalidate(supplierNotifierProvider);
                }
              },
            ),
          ),
          Expanded(
            child: suppliersAsync.when(
              data: (suppliers) {
                if (suppliers.isEmpty) return const Center(child: Text('No suppliers'));
                return ListView.builder(
                  itemCount: suppliers.length,
                  itemBuilder: (_, index) {
                    final s = suppliers[index];
                    return ListTile(
                      title: Text(s.name),
                      subtitle: Text(s.phone ?? ''),
                      trailing: Text('₹${s.openingBalance.toStringAsFixed(0)}'),
                      onTap: () => _navigateToForm(s),
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

  void _navigateToForm([Supplier? supplier]) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SupplierFormScreen(supplier: supplier),
      ),
    ).then((_) => ref.invalidate(supplierNotifierProvider));
  }
}
