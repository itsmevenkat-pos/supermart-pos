import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../services/report_service.dart';
import '../../../services/sales_summary_service.dart';
import '../widgets/report_card.dart';

String _money(num value) => '₹${value.toStringAsFixed(0)}';

const _weekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
String _weekday(DateTime d) => _weekdayShort[d.weekday - 1];

enum _Period { today, week, month }

class SalesDashboardScreen extends ConsumerStatefulWidget {
  const SalesDashboardScreen({super.key});

  @override
  ConsumerState<SalesDashboardScreen> createState() => _SalesDashboardScreenState();
}

class _SalesDashboardScreenState extends ConsumerState<SalesDashboardScreen> {
  final _reportService = ReportService();
  final _summaryService = SalesSummaryService();

  _Period _period = _Period.today;
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic> _report = {};
  List<Map<String, dynamic>> _trend = [];
  Map<String, dynamic> _paymentSummary = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  (DateTime, DateTime) _rangeFor(_Period period) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    switch (period) {
      case _Period.today:
        return (todayStart, now);
      case _Period.week:
        return (todayStart.subtract(const Duration(days: 6)), now);
      case _Period.month:
        return (DateTime(now.year, now.month - 1, now.day), now);
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final (from, to) = _rangeFor(_period);
      final report = await _reportService.getSalesReport(from: from, to: to);
      // Trend always spans the last 30 days regardless of the selected
      // period toggle -- it's a dashboard-wide view, not scoped to Today/
      // Week/Month like the stat cards and payment breakdown are.
      final trend = await _reportService.getDailySalesTrend(days: 30);
      final payments = await _summaryService.getSummary(from: from, to: to);
      if (!mounted) return;
      setState(() {
        _report = report;
        _trend = trend;
        _paymentSummary = payments;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Sales Dashboard',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: _loadData,
        ),
      ],
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Could not load dashboard: $_error'))
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _PeriodToggle(
                        period: _period,
                        onChanged: (p) {
                          setState(() => _period = p);
                          _loadData();
                        },
                      ),
                      const SizedBox(height: 16),
                      GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 1.6,
                        children: [
                          ReportCard(
                            title: 'Total Sales',
                            value: _money((_report['totalSales'] as num?) ?? 0),
                            color: Colors.green,
                            icon: Icons.point_of_sale,
                          ),
                          ReportCard(
                            title: 'Total Bills',
                            value: '${(_report['totalBills'] as num?) ?? 0}',
                            color: Colors.blue,
                            icon: Icons.receipt_long,
                          ),
                          ReportCard(
                            title: 'Average Bill',
                            value: _money((_report['averageBill'] as num?) ?? 0),
                            color: Colors.indigo,
                            icon: Icons.calculate,
                          ),
                          ReportCard(
                            title: 'Total Tax',
                            value: _money((_report['totalTax'] as num?) ?? 0),
                            color: Colors.orange,
                            icon: Icons.receipt,
                          ),
                          ReportCard(
                            title: 'Total Discount',
                            value: _money((_report['totalDiscount'] as num?) ?? 0),
                            color: Colors.red,
                            icon: Icons.discount,
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      Text('Last 30 Days', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      _TrendChart(data: _trend),
                      const SizedBox(height: 28),
                      Text('Payment Methods', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      _PaymentBreakdown(summary: _paymentSummary),
                    ],
                  ),
                ),
    );
  }
}

// ----------------------------- Period toggle -----------------------------

class _PeriodToggle extends StatelessWidget {
  final _Period period;
  final ValueChanged<_Period> onChanged;

  const _PeriodToggle({required this.period, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<_Period>(
      segments: const [
        ButtonSegment(value: _Period.today, label: Text('Today')),
        ButtonSegment(value: _Period.week, label: Text('Week')),
        ButtonSegment(value: _Period.month, label: Text('Month')),
      ],
      selected: {period},
      onSelectionChanged: (selection) => onChanged(selection.first),
    );
  }
}

// ------------------------------ Trend chart ------------------------------

/// A plain bar sparkline -- no charting package dependency needed. Mirrors
/// the style of `_TrendChart` in dashboard_screen.dart, but that class is
/// private to its file so it's reimplemented here rather than shared.
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
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: data.map((d) {
            final value = (d['totalSales'] as num?)?.toDouble() ?? 0;
            final date = d['date'] as DateTime;
            final heightFraction = maxValue > 0 ? value / maxValue : 0.0;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: SizedBox(
                width: 32,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      value > 0 ? _money(value) : '',
                      style: const TextStyle(fontSize: 8),
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
      ),
    );
  }
}

// --------------------------- Payment breakdown ---------------------------

/// Hand-rolled horizontal bar list for the cash/UPI/card/credit split --
/// kept in the same no-charting-package style as [_TrendChart].
class _PaymentBreakdown extends StatelessWidget {
  final Map<String, dynamic> summary;

  const _PaymentBreakdown({required this.summary});

  @override
  Widget build(BuildContext context) {
    final rows = [
      ('Cash', (summary['cash'] as num?)?.toDouble() ?? 0, Colors.green),
      ('UPI', (summary['upi'] as num?)?.toDouble() ?? 0, Colors.teal),
      ('Card', (summary['card'] as num?)?.toDouble() ?? 0, Colors.indigo),
      ('Credit', (summary['credit'] as num?)?.toDouble() ?? 0, Colors.red),
    ];
    final maxValue = rows.map((r) => r.$2).fold<double>(0, (a, b) => a > b ? a : b);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: rows.map((row) {
            final (label, value, color) = row;
            final fraction = maxValue > 0 ? value / maxValue : 0.0;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(label, style: const TextStyle(fontSize: 14)),
                      Text(
                        _money(value),
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: fraction.clamp(0.0, 1.0),
                      minHeight: 8,
                      backgroundColor: color.withValues(alpha: 0.15),
                      valueColor: AlwaysStoppedAnimation(color),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
