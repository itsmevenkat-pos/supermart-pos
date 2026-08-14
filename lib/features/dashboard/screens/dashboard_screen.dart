import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../models/sale_model.dart';
import '../../../models/user_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/dashboard_provider.dart';

String _money(double value) => '\u20b9${value.toStringAsFixed(0)}';

const _weekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _monthShort = [
  '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _weekday(DateTime d) => _weekdayShort[d.weekday - 1];

String _dateTimeLabel(DateTime d) {
  final hour12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final minute = d.minute.toString().padLeft(2, '0');
  final ampm = d.hour >= 12 ? 'PM' : 'AM';
  return '${d.day} ${_monthShort[d.month]}, $hour12:$minute $ampm';
}

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    final isManager = user?.role == UserRole.manager || user?.role == UserRole.admin;
    final dataAsync = ref.watch(dashboardDataProvider);

    return AppScaffold(
      title: 'Dashboard',
      showBackButton: false,
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(dashboardDataProvider),
        child: dataAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(child: Text('Could not load dashboard: $err')),
          data: (data) => isManager
              ? _ManagerHome(data: data, userName: user?.name ?? '')
              : _CashierHome(data: data, userName: user?.name ?? ''),
        ),
      ),
    );
  }
}

// ----------------------------- Cashier home -----------------------------

class _CashierHome extends StatelessWidget {
  final DashboardData data;
  final String userName;

  const _CashierHome({required this.data, required this.userName});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Hi, $userName', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text("Here's your shift so far", style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 24),
        Card(
          color: Colors.green.shade50,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _StatBlock(label: "Today's Sales", value: _money(data.todaySales)),
                _StatBlock(label: 'Bills', value: '${data.todayBillCount}'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 32),
        SizedBox(
          height: 64,
          child: ElevatedButton.icon(
            onPressed: () => context.go('/billing'),
            icon: const Icon(Icons.point_of_sale, size: 28),
            label: const Text('New Bill', style: TextStyle(fontSize: 20)),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => context.go('/holds'),
                icon: const Icon(Icons.pause_circle_outline),
                label: const Text('Hold Bills'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => context.go('/quotations'),
                icon: const Icon(Icons.description_outlined),
                label: const Text('Quotations'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ------------------------- Manager/admin home -------------------------

class _ManagerHome extends StatelessWidget {
  final DashboardData data;
  final String userName;

  const _ManagerHome({required this.data, required this.userName});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Hi, $userName', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),

        // KPI strip
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.8,
          children: [
            _KpiCard(
              label: "Today's Sales",
              value: _money(data.todaySales),
              subtitle: '${data.todayBillCount} bills',
              icon: Icons.point_of_sale,
              color: Colors.green,
              onTap: () => context.go('/sales-history'),
            ),
            _KpiCard(
              label: "Today's Profit",
              value: _money(data.todayProfit ?? 0),
              icon: Icons.trending_up,
              color: Colors.blue,
            ),
            _KpiCard(
              label: 'Low Stock',
              value: '${data.lowStockCount ?? 0}',
              subtitle: 'items to reorder',
              icon: Icons.inventory_2,
              color: Colors.orange,
              onTap: () => context.go('/products'),
            ),
            _KpiCard(
              label: 'Pending Dues',
              value: _money(data.pendingDues ?? 0),
              icon: Icons.account_balance_wallet,
              color: Colors.red,
              onTap: () => context.go('/customers'),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Quick actions
        SizedBox(
          height: 56,
          child: ElevatedButton.icon(
            onPressed: () => context.go('/billing'),
            icon: const Icon(Icons.point_of_sale),
            label: const Text('New Bill', style: TextStyle(fontSize: 18)),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => context.go('/holds'),
                icon: const Icon(Icons.pause_circle_outline),
                label: const Text('Hold Bills'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => context.go('/quotations'),
                icon: const Icon(Icons.description_outlined),
                label: const Text('Quotations'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),

        // 7-day trend
        Text('Last 7 Days', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        _TrendChart(data: data.last7Days ?? []),
        const SizedBox(height: 28),

        // Recent sales
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Recent Sales', style: Theme.of(context).textTheme.titleMedium),
            TextButton(
              onPressed: () => context.go('/sales-history'),
              child: const Text('View all'),
            ),
          ],
        ),
        ...(data.recentSales ?? []).map((sale) => _RecentSaleTile(sale: sale)),
      ],
    );
  }
}

// --------------------------- Shared small widgets ---------------------------

class _StatBlock extends StatelessWidget {
  final String label;
  final String value;

  const _StatBlock({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        Text(label, style: TextStyle(color: Colors.grey.shade700)),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final String? subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 26),
              const SizedBox(height: 6),
              Text(
                value,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
              Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
              if (subtitle != null)
                Text(subtitle!, style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }
}

/// A plain bar sparkline -- no charting package dependency needed.
class _TrendChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;

  const _TrendChart({required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const SizedBox(height: 100, child: Center(child: Text('No data yet')));
    }

    final maxValue = data
        .map((d) => (d['totalSales'] as num?)?.toDouble() ?? 0)
        .fold<double>(0, (a, b) => a > b ? a : b);

    return SizedBox(
      height: 120,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: data.map((d) {
          final value = (d['totalSales'] as num?)?.toDouble() ?? 0;
          final date = d['date'] as DateTime;
          final heightFraction = maxValue > 0 ? value / maxValue : 0.0;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    value > 0 ? _money(value) : '',
                    style: const TextStyle(fontSize: 9),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Container(
                    height: (70 * heightFraction.clamp(0.02, 1.0)).toDouble(),
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(_weekday(date), style: const TextStyle(fontSize: 10)),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _RecentSaleTile extends StatelessWidget {
  final Sale sale;

  const _RecentSaleTile({required this.sale});

  @override
  Widget build(BuildContext context) {
    final date = DateTime.fromMillisecondsSinceEpoch(sale.createdAt * 1000);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const CircleAvatar(child: Icon(Icons.receipt_long, size: 18)),
      title: Text('Invoice ${sale.invoiceLabel}'),
      subtitle: Text(_dateTimeLabel(date)),
      trailing: Text(
        _money(sale.netAmount),
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    );
  }
}
