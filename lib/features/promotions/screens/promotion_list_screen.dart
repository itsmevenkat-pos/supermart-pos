import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../models/promotion_model.dart';
import '../../../repositories/promotion_repository.dart';

class PromotionListScreen extends ConsumerStatefulWidget {
  const PromotionListScreen({super.key});

  @override
  ConsumerState<PromotionListScreen> createState() => _PromotionListScreenState();
}

class _PromotionListScreenState extends ConsumerState<PromotionListScreen> {
  late Future<List<Promotion>> _promotionsFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _promotionsFuture = ref.read(promotionRepositoryProvider).getAll();
  }

  Future<void> _refresh() async {
    setState(_load);
    await _promotionsFuture;
  }

  Future<void> _navigateToForm([Promotion? promotion]) async {
    await context.push('/promotions/form', extra: promotion);
    if (mounted) await _refresh();
  }

  Future<void> _toggleActive(Promotion promotion) async {
    try {
      await ref.read(promotionRepositoryProvider).setActive(promotion.id, !promotion.isActive);
      if (mounted) await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating promotion: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _delete(Promotion promotion) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Promotion?'),
        content: Text('"${promotion.name}" will stop applying immediately. This cannot be undone.'),
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
    try {
      await ref.read(promotionRepositoryProvider).delete(promotion.id);
      if (mounted) await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error deleting promotion: $e'), backgroundColor: Colors.red),
      );
    }
  }

  String _typeLabel(PromotionType type) {
    switch (type) {
      case PromotionType.percentage:
        return 'Percentage off';
      case PromotionType.fixed:
        return 'Flat ₹ off';
      case PromotionType.free_item:
        return 'Free item';
    }
  }

  String _subtitleFor(Promotion promo) {
    final scope = promo.productId != null
        ? 'this product'
        : promo.categoryId != null
            ? 'this category'
            : 'no scope set — will never apply';
    final parts = <String>['Buy ${promo.minQuantity}+ of $scope'];
    switch (promo.type) {
      case PromotionType.percentage:
        parts.add('get ${promo.discountValue?.toStringAsFixed(0) ?? '?'}% off');
      case PromotionType.fixed:
        parts.add('get ₹${promo.discountValue?.toStringAsFixed(2) ?? '?'} off');
      case PromotionType.free_item:
        parts.add('get a free item (only waived if it\'s already in the cart)');
    }
    if (promo.startDate != null || promo.endDate != null) {
      final start = promo.startDate != null
          ? DateTime.fromMillisecondsSinceEpoch(promo.startDate! * 1000).toString().split(' ')[0]
          : 'always';
      final end = promo.endDate != null
          ? DateTime.fromMillisecondsSinceEpoch(promo.endDate! * 1000).toString().split(' ')[0]
          : 'no end';
      parts.add('· $start → $end');
    }
    return parts.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Promotions',
      actions: [
        IconButton(icon: const Icon(Icons.refresh), onPressed: () => setState(_load)),
      ],
      floatingActionButton: FloatingActionButton(
        onPressed: () => _navigateToForm(),
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<List<Promotion>>(
        future: _promotionsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final promotions = snapshot.data ?? [];
          if (promotions.isEmpty) {
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                children: const [
                  SizedBox(height: 120),
                  Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        'No promotions yet. Create one to auto-apply discounts at billing '
                        '— e.g. "Buy 2 get 10% off" or "Buy 3, get one free".',
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
              itemCount: promotions.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, index) {
                final promo = promotions[index];
                return ListTile(
                  title: Text(promo.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('${_typeLabel(promo.type)} — ${_subtitleFor(promo)}'),
                  isThreeLine: true,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Chip(
                        label: Text(promo.isActive ? 'Active' : 'Inactive'),
                        backgroundColor: promo.isActive
                            ? Colors.green.withValues(alpha: 0.15)
                            : Colors.grey.withValues(alpha: 0.2),
                        labelStyle: TextStyle(
                          color: promo.isActive ? Colors.green.shade800 : Colors.grey.shade700,
                          fontSize: 12,
                        ),
                        visualDensity: VisualDensity.compact,
                        onDeleted: () => _toggleActive(promo),
                        deleteIcon: Icon(promo.isActive ? Icons.toggle_on : Icons.toggle_off, size: 20),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: () => _delete(promo),
                      ),
                    ],
                  ),
                  onTap: () => _navigateToForm(promo),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
