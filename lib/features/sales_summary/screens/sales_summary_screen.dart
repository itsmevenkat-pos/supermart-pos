import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../services/sales_summary_service.dart';

class SalesSummaryScreen extends ConsumerStatefulWidget {
  const SalesSummaryScreen({super.key});

  @override
  ConsumerState<SalesSummaryScreen> createState() => _SalesSummaryScreenState();
}

class _SalesSummaryScreenState extends ConsumerState<SalesSummaryScreen> {
  Map<String, dynamic> _summary = {};
  bool _isLoading = true;
  String _filter = 'Today';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final service = SalesSummaryService();
    Map<String, dynamic> data;
    if (_filter == 'Today') {
      data = await service.getTodaySummary();
    } else {
      // For other filters, we'll use a date range
      final now = DateTime.now();
      DateTime from;
      if (_filter == 'Week') {
        from = now.subtract(const Duration(days: 7));
      } else if (_filter == 'Month') {
        from = DateTime(now.year, now.month - 1, now.day);
      } else {
        from = DateTime(now.year - 1, now.month, now.day);
      }
      data = await service.getSummary(from: from);
    }
    setState(() {
      _summary = data;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Sales Summary',
      actions: [
        DropdownButton<String>(
          value: _filter,
          items: ['Today', 'Week', 'Month', 'Year'].map((f) {
            return DropdownMenuItem(value: f, child: Text(f));
          }).toList(),
          onChanged: (val) {
            setState(() => _filter = val!);
            _loadData();
          },
        ),
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: _loadData,
        ),
      ],
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Total Sales:', style: TextStyle(fontSize: 18)),
                              Text(
                                '₹${(_summary['totalSales'] ?? 0).toStringAsFixed(2)}',
                                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Total Bills:', style: TextStyle(fontSize: 16)),
                              Text(
                                '${_summary['totalCount'] ?? 0}',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _summaryRow('Cash', _summary['cash'] ?? 0, Colors.green),
                          const Divider(),
                          _summaryRow('UPI', _summary['upi'] ?? 0, Colors.teal),
                          const Divider(),
                          _summaryRow('Card', _summary['card'] ?? 0, Colors.indigo),
                          const Divider(),
                          _summaryRow('Credit', _summary['credit'] ?? 0, Colors.red),
                          const Divider(),
                          _summaryRow('Partial Payments', _summary['partial'] ?? 0, Colors.orange),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _summaryRow(String label, double amount, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontSize: 16)),
          ],
        ),
        Text(
          '₹${amount.toStringAsFixed(2)}',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }
}
