import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../models/product_model.dart';
import '../../../models/stock_group_model.dart';
import '../../../repositories/stock_group_repository.dart';

class StockGroupListScreen extends ConsumerStatefulWidget {
  const StockGroupListScreen({super.key});

  @override
  ConsumerState<StockGroupListScreen> createState() => _StockGroupListScreenState();
}

class _StockGroupListScreenState extends ConsumerState<StockGroupListScreen> {
  late Future<List<StockGroup>> _groupsFuture;
  final _repo = StockGroupRepository();

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _groupsFuture = _repo.getAll();
  }

  Future<void> _refresh() async {
    setState(_load);
    await _groupsFuture;
  }

  Future<void> _createGroup() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('New Stock Group'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Group Name',
            hintText: 'e.g. Lays ₹10 Flavors',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final group = await _repo.createGroup(name);
    if (!mounted) return;
    await context.push('/stock-groups/detail', extra: group.id);
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Stock Groups',
      actions: [
        IconButton(icon: const Icon(Icons.refresh), onPressed: () => setState(_load)),
      ],
      floatingActionButton: FloatingActionButton(
        onPressed: _createGroup,
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<List<StockGroup>>(
        future: _groupsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final groups = snapshot.data ?? [];
          if (groups.isEmpty) {
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                children: const [
                  SizedBox(height: 120),
                  Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        'No stock groups yet. Create one to share a single stock count across '
                        'several SKUs — e.g. different flavors of the same ₹10 chips — so one '
                        'flavor selling out doesn\'t look like a stockout while siblings still '
                        'have plenty.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              itemCount: groups.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, index) {
                final group = groups[index];
                return FutureBuilder<List<Product>>(
                  future: _repo.getMembers(group.id),
                  builder: (context, memberSnapshot) {
                    final members = memberSnapshot.data;
                    final pooledStock = members != null && members.isNotEmpty ? members.first.stockQuantity : null;
                    return ListTile(
                      title: Text(group.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(
                        members == null
                            ? 'Loading…'
                            : '${members.length} product${members.length == 1 ? '' : 's'}'
                                '${pooledStock != null ? ' · pooled stock: ${pooledStock.toStringAsFixed(0)}' : ''}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        await context.push('/stock-groups/detail', extra: group.id);
                        if (mounted) await _refresh();
                      },
                    );
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }
}
