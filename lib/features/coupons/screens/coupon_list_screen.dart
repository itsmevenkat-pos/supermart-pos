import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../models/coupon_model.dart';
import '../../../repositories/coupon_repository.dart';

class CouponListScreen extends ConsumerStatefulWidget {
  const CouponListScreen({super.key});

  @override
  ConsumerState<CouponListScreen> createState() => _CouponListScreenState();
}

class _CouponListScreenState extends ConsumerState<CouponListScreen> {
  late Future<List<Coupon>> _couponsFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _couponsFuture = ref.read(couponRepositoryProvider).getAll();
  }

  Future<void> _refresh() async {
    setState(_load);
    await _couponsFuture;
  }

  Future<void> _navigateToForm([Coupon? coupon]) async {
    await context.push('/coupons/form', extra: coupon);
    if (mounted) await _refresh();
  }

  Future<void> _toggleActive(Coupon coupon) async {
    try {
      await ref.read(couponRepositoryProvider).setActive(coupon.id, !coupon.isActive);
      if (mounted) await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating coupon: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _delete(Coupon coupon) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Coupon?'),
        content: Text('"${coupon.code}" will stop working immediately. This cannot be undone.'),
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
      await ref.read(couponRepositoryProvider).delete(coupon.id);
      if (mounted) await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error deleting coupon: $e'), backgroundColor: Colors.red),
      );
    }
  }

  String _subtitleFor(Coupon coupon) {
    final value = coupon.type == CouponType.percentage
        ? '${coupon.value.toStringAsFixed(0)}% off'
        : '₹${coupon.value.toStringAsFixed(2)} off';
    final parts = <String>[value];
    if (coupon.minBillAmount > 0) parts.add('min bill ₹${coupon.minBillAmount.toStringAsFixed(0)}');
    parts.add(coupon.maxUses != null ? 'used ${coupon.timesUsed}/${coupon.maxUses}' : 'used ${coupon.timesUsed}× (unlimited)');
    if (coupon.endDate != null) {
      final end = DateTime.fromMillisecondsSinceEpoch(coupon.endDate! * 1000).toString().split(' ')[0];
      parts.add('expires $end');
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Coupons',
      actions: [
        IconButton(icon: const Icon(Icons.refresh), onPressed: () => setState(_load)),
      ],
      floatingActionButton: FloatingActionButton(
        onPressed: () => _navigateToForm(),
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<List<Coupon>>(
        future: _couponsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final coupons = snapshot.data ?? [];
          if (coupons.isEmpty) {
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                children: const [
                  SizedBox(height: 120),
                  Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        'No coupons yet. Create one for customers to enter a code at '
                        'checkout — e.g. "WELCOME10" for 10% off.',
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
              itemCount: coupons.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, index) {
                final coupon = coupons[index];
                return ListTile(
                  title: Text(coupon.code, style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
                  subtitle: Text(_subtitleFor(coupon)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Chip(
                        label: Text(coupon.isActive ? 'Active' : 'Inactive'),
                        backgroundColor: coupon.isActive
                            ? Colors.green.withValues(alpha: 0.15)
                            : Colors.grey.withValues(alpha: 0.2),
                        labelStyle: TextStyle(
                          color: coupon.isActive ? Colors.green.shade800 : Colors.grey.shade700,
                          fontSize: 12,
                        ),
                        visualDensity: VisualDensity.compact,
                        onDeleted: () => _toggleActive(coupon),
                        deleteIcon: Icon(coupon.isActive ? Icons.toggle_on : Icons.toggle_off, size: 20),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: () => _delete(coupon),
                      ),
                    ],
                  ),
                  onTap: () => _navigateToForm(coupon),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
