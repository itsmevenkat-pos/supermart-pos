import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../models/product_model.dart';
import '../../../models/stock_group_model.dart';
import '../../../repositories/product_repository.dart';
import '../../../repositories/stock_group_repository.dart';

class StockGroupDetailScreen extends ConsumerStatefulWidget {
  final String groupId;

  const StockGroupDetailScreen({super.key, required this.groupId});

  @override
  ConsumerState<StockGroupDetailScreen> createState() => _StockGroupDetailScreenState();
}

class _StockGroupDetailScreenState extends ConsumerState<StockGroupDetailScreen> {
  final _repo = StockGroupRepository();
  late Future<List<StockGroup>> _groupFuture;
  late Future<List<Product>> _membersFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _groupFuture = _repo.getAll();
    _membersFuture = _repo.getMembers(widget.groupId);
  }

  Future<void> _refresh() async {
    setState(_load);
    await Future.wait([_groupFuture, _membersFuture]);
  }

  Future<void> _removeMember(Product product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove From Group?'),
        content: Text(
          '"${product.displayName ?? product.name}" keeps its current stock (${product.stockQuantity.toStringAsFixed(0)}) '
          'as its own count from now on, tracked separately from the rest of this group.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true) return;
    await _repo.removeMember(product.id);
    if (mounted) await _refresh();
  }

  Future<void> _deleteGroup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Stock Group?'),
        content: const Text(
          'Every member product keeps its current pooled stock as its own individual count '
          'from now on. This cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _repo.deleteGroup(widget.groupId);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _addMember() async {
    final searchController = TextEditingController();
    List<Product> results = [];

    final picked = await showDialog<Product>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Add Product to Group'),
          content: SizedBox(
            width: 400,
            height: 320,
            child: Column(
              children: [
                TextField(
                  controller: searchController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Search by name or barcode',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (value) async {
                    final found = value.trim().isEmpty ? <Product>[] : await ProductRepository().search(value.trim());
                    setDialogState(() => results = found);
                  },
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    itemCount: results.length,
                    itemBuilder: (_, index) {
                      final product = results[index];
                      return ListTile(
                        dense: true,
                        title: Text(product.displayName ?? product.name),
                        subtitle: Text(
                          '${product.barcode} · ₹${product.retailPrice.toStringAsFixed(2)} · ${product.taxRate}% tax '
                          '· stock ${product.stockQuantity.toStringAsFixed(0)}',
                        ),
                        onTap: () => Navigator.pop(dialogContext, product),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          ],
        ),
      ),
    );
    if (picked == null) return;

    try {
      await _repo.addMember(picked.id, widget.groupId);
      if (mounted) await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<StockGroup>>(
      future: _groupFuture,
      builder: (context, groupSnapshot) {
        StockGroup? group;
        for (final g in groupSnapshot.data ?? const <StockGroup>[]) {
          if (g.id == widget.groupId) {
            group = g;
            break;
          }
        }
        if (groupSnapshot.connectionState != ConnectionState.done) {
          return const AppScaffold(title: 'Stock Group', body: Center(child: CircularProgressIndicator()));
        }
        if (group == null) {
          return const AppScaffold(title: 'Stock Group', body: Center(child: Text('Group not found')));
        }

        return AppScaffold(
          title: group.name,
          actions: [
            IconButton(icon: const Icon(Icons.delete_outline), onPressed: _deleteGroup, tooltip: 'Delete group'),
          ],
          floatingActionButton: FloatingActionButton(
            onPressed: _addMember,
            child: const Icon(Icons.add),
          ),
          body: FutureBuilder<List<Product>>(
            future: _membersFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final members = snapshot.data ?? [];
              final pooledStock = members.isNotEmpty ? members.first.stockQuantity : 0.0;

              return Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pooled Stock: ${pooledStock.toStringAsFixed(0)}',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Selling or receiving any member updates this shared total. '
                          'Sales reports still show which specific SKU was sold.',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: members.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(32),
                              child: Text(
                                'No products in this group yet. Tap + to add one.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey),
                              ),
                            ),
                          )
                        : ListView.separated(
                            itemCount: members.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (_, index) {
                              final product = members[index];
                              return ListTile(
                                title: Text(product.displayName ?? product.name),
                                subtitle: Text('${product.barcode} · ₹${product.retailPrice.toStringAsFixed(2)}'),
                                trailing: IconButton(
                                  icon: const Icon(Icons.link_off),
                                  tooltip: 'Remove from group',
                                  onPressed: () => _removeMember(product),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}
