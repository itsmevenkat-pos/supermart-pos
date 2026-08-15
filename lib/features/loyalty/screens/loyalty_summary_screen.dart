import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/app_scaffold.dart';
import '../../../models/loyalty_point_event_model.dart';
import '../../../repositories/loyalty_event_repository.dart';
import '../../../repositories/store_repository.dart';
import '../../../services/loyalty_service.dart';

final _dateFormat = DateFormat('dd MMM yyyy');

/// Store-wide loyalty position: what the shop owes its customers in points,
/// this period's activity, and the controls for point expiry.
///
/// Lives under `features/loyalty/` rather than `features/reports/` for the
/// same reason bank reconciliation does: `reports/` is read-only output, and
/// this screen writes — running an expiry sweep and changing the store's
/// expiry window both change data.
class LoyaltySummaryScreen extends ConsumerStatefulWidget {
  const LoyaltySummaryScreen({super.key});

  @override
  ConsumerState<LoyaltySummaryScreen> createState() => _LoyaltySummaryScreenState();
}

class _LoyaltySummaryScreenState extends ConsumerState<LoyaltySummaryScreen> {
  final _service = LoyaltyService();
  final _events = LoyaltyEventRepository();
  final _stores = StoreRepository();

  late Future<StoreLoyaltySummary> _summaryFuture;
  late Future<List<LoyaltyPointEvent>> _activityFuture;

  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _summaryFuture = _service.getStoreSummary(from: _from, to: _to);
    _activityFuture = _events.getEventsInRange(from: _from, to: _to);
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(start: _from, end: _to),
    );
    if (picked == null) return;
    setState(() {
      _from = picked.start;
      _to = picked.end;
      _load();
    });
  }

  Future<void> _runExpirySweep() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Expire lapsed points?'),
        content: const Text(
          'This writes off points whose validity date has passed and that the '
          'customer never spent, and reduces their balance. It cannot be undone '
          'from this screen.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Run')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final result = await _service.expireOldPoints();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _load();
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result.isEmpty
            ? 'Nothing to expire — no customer had unspent points past their date.'
            : 'Expired ${result.pointsExpired} point(s) across '
                '${result.customersAffected} customer(s).'),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Expiry run failed: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _editExpiryWindow(int current) async {
    final controller = TextEditingController(text: current.toString());
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Point Validity'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'How many days a point stays spendable after it is earned. '
              'Set 0 for points that never expire.\n\n'
              'This applies to points earned from now on — points already in '
              'customers\' balances keep the validity they were given.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Days (0 = never)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Save')),
        ],
      ),
    );
    if (saved != true || !mounted) return;

    final days = int.tryParse(controller.text.trim());
    if (days == null || days < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter 0 or a positive number of days.'), backgroundColor: Colors.red),
      );
      return;
    }
    await _stores.updateLoyaltyExpiryDays(days);
    if (!mounted) return;
    setState(_load);
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Loyalty Points',
      actions: [
        IconButton(
          icon: const Icon(Icons.date_range),
          tooltip: 'Change period',
          onPressed: _pickRange,
        ),
      ],
      body: FutureBuilder<StoreLoyaltySummary>(
        future: _summaryFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Could not load loyalty summary: ${snapshot.error}'));
          }
          final summary = snapshot.data!;

          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              _liabilityCard(summary),
              const SizedBox(height: 8),
              _activityCard(summary),
              const SizedBox(height: 8),
              _expiryCard(summary),
              const SizedBox(height: 8),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Text('Activity in this period', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              _activityList(),
            ],
          );
        },
      ),
    );
  }

  Widget _liabilityCard(StoreLoyaltySummary summary) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Outstanding Liability', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              children: [
                _stat('Points Outstanding', '${summary.outstandingPoints}', Colors.purple),
                _stat('Value', '₹${summary.outstandingValue.toStringAsFixed(2)}', Colors.red),
                _stat('Customers Holding', '${summary.customersWithPoints}', Colors.blue),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'At ₹${summary.valuePerPoint.toStringAsFixed(2)} per point. This is a real '
              'liability — future discounts already promised — but it is not posted to '
              'the General Ledger, so the Balance Sheet does not include it.',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _activityCard(StoreLoyaltySummary summary) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_dateFormat.format(summary.periodFrom)} — ${_dateFormat.format(summary.periodTo)}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _stat('Earned', '${summary.pointsEarnedInPeriod}', Colors.green),
                _stat('Redeemed', '${summary.pointsRedeemedInPeriod}', Colors.orange),
                _stat('Expired', '${summary.pointsExpiredInPeriod}', Colors.grey),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _expiryCard(StoreLoyaltySummary summary) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(child: Text('Point Expiry', style: TextStyle(fontWeight: FontWeight.bold))),
                TextButton(
                  onPressed: () => _editExpiryWindow(summary.expiryDays),
                  child: Text(summary.expiryEnabled ? '${summary.expiryDays} days' : 'Off'),
                ),
              ],
            ),
            Text(
              summary.expiryEnabled
                  ? 'Points earned from now on lapse ${summary.expiryDays} days after they are earned. '
                      'Nothing expires on its own — run the sweep below to apply it.'
                  : 'Points never expire. Turn this on above if the shop wants a validity window; '
                      'existing balances are unaffected either way.',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                // Offered even when expiry is off: points stamped while it was
                // on are still carrying a date, and switching the setting off
                // should not strand them.
                onPressed: _busy ? null : _runExpirySweep,
                icon: _busy
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.hourglass_bottom),
                label: const Text('Run Expiry Sweep'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _activityList() {
    return FutureBuilder<List<LoyaltyPointEvent>>(
      future: _activityFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final events = snapshot.data ?? [];
        if (events.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('No point activity in this period.', style: TextStyle(color: Colors.grey))),
          );
        }
        return Column(
          children: events.map((event) {
            final net = event.netPoints;
            final color = net > 0 ? Colors.green : (net < 0 ? Colors.red : Colors.grey);
            return ListTile(
              dense: true,
              leading: CircleAvatar(
                backgroundColor: color.withValues(alpha: 0.15),
                child: Text(
                  event.eventType.name[0].toUpperCase(),
                  style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.bold),
                ),
              ),
              title: Text(_dateFormat.format(event.dateTime)),
              subtitle: Text(event.note ?? event.eventType.name),
              trailing: Text(
                net > 0 ? '+$net' : '$net',
                style: TextStyle(fontWeight: FontWeight.bold, color: color),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _stat(String label, String value, Color color) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}
