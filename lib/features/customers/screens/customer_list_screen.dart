import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../providers/customer_provider.dart';
import '../../../models/customer_model.dart';
import 'customer_form_screen.dart';

class CustomerListScreen extends ConsumerStatefulWidget {
  const CustomerListScreen({super.key});

  @override
  ConsumerState<CustomerListScreen> createState() => _CustomerListScreenState();
}

class _CustomerListScreenState extends ConsumerState<CustomerListScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final customersAsync = ref.watch(customerNotifierProvider);

    return AppScaffold(
      title: 'Customers',
      actions: [
        IconButton(
          icon: const Icon(Icons.notifications_active_outlined),
          tooltip: 'Service Reminders',
          onPressed: () => context.push('/customers/reminders'),
        ),
        IconButton(
          icon: const Icon(Icons.campaign_outlined),
          tooltip: 'Campaigns',
          onPressed: () => context.push('/customers/campaigns'),
        ),
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () => ref.invalidate(customerNotifierProvider),
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
                  ref.read(customerNotifierProvider.notifier).search(value);
                } else {
                  ref.invalidate(customerNotifierProvider);
                }
              },
            ),
          ),
          Expanded(
            child: customersAsync.when(
              data: (customers) {
                if (customers.isEmpty) return const Center(child: Text('No customers'));
                return ListView.builder(
                  itemCount: customers.length,
                  itemBuilder: (_, index) {
                    final c = customers[index];
                    return ListTile(
                      title: Text(c.name),
                      subtitle: Text(c.phone),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('₹${c.totalSpent.toStringAsFixed(0)}'),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 20),
                            tooltip: 'Edit',
                            onPressed: () => _navigateToForm(c),
                          ),
                        ],
                      ),
                      onTap: () async {
                        await context.push('/customers/history?id=${c.id}');
                        ref.invalidate(customerNotifierProvider);
                      },
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

  void _navigateToForm([Customer? customer]) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CustomerFormScreen(customer: customer),
      ),
    ).then((_) => ref.invalidate(customerNotifierProvider));
  }
}
