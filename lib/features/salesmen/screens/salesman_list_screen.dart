import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../models/salesman_model.dart';
import '../../../repositories/salesman_repository.dart';

class SalesmanListScreen extends ConsumerStatefulWidget {
  const SalesmanListScreen({super.key});

  @override
  ConsumerState<SalesmanListScreen> createState() => _SalesmanListScreenState();
}

class _SalesmanListScreenState extends ConsumerState<SalesmanListScreen> {
  late Future<List<SalesmanPerformance>> _performanceFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _performanceFuture = ref.read(salesmanRepositoryProvider).getPerformance();
  }

  Future<void> _refresh() async {
    setState(_load);
    await _performanceFuture;
  }

  Future<void> _navigateToForm([Salesman? salesman]) async {
    await context.push('/utilities/track-salesmen/form', extra: salesman);
    if (mounted) await _refresh();
  }

  Future<void> _toggleActive(Salesman salesman) async {
    try {
      await ref.read(salesmanRepositoryProvider).setActive(salesman.id, !salesman.isActive);
      if (mounted) await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating salesman: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Track Your Salesmen',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () => setState(_load),
        ),
      ],
      floatingActionButton: FloatingActionButton(
        onPressed: () => _navigateToForm(),
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<List<SalesmanPerformance>>(
        future: _performanceFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final rows = snapshot.data ?? [];
          if (rows.isEmpty) {
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                children: const [
                  SizedBox(height: 120),
                  Center(child: Text('No active salesmen yet')),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.builder(
              itemCount: rows.length,
              itemBuilder: (_, index) {
                final row = rows[index];
                final salesman = row.salesman;
                return ListTile(
                  title: Text(salesman.name),
                  subtitle: Text(
                    '${salesman.phone?.isNotEmpty == true ? salesman.phone : 'No phone'} · '
                    '${row.saleCount} sale${row.saleCount == 1 ? '' : 's'}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '₹${row.totalAmount.toStringAsFixed(0)}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 8),
                      Chip(
                        label: Text(salesman.isActive ? 'Active' : 'Inactive'),
                        backgroundColor: salesman.isActive
                            ? Colors.green.withValues(alpha: 0.15)
                            : Colors.grey.withValues(alpha: 0.2),
                        labelStyle: TextStyle(
                          color: salesman.isActive ? Colors.green.shade800 : Colors.grey.shade700,
                          fontSize: 12,
                        ),
                        visualDensity: VisualDensity.compact,
                        onDeleted: () => _toggleActive(salesman),
                        deleteIcon: Icon(
                          salesman.isActive ? Icons.toggle_on : Icons.toggle_off,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                  onTap: () => _navigateToForm(salesman),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
