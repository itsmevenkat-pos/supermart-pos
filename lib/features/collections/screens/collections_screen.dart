import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/app_scaffold.dart';
import '../../../models/collection_activity_model.dart';
import '../../../services/collections_exceptions.dart';
import '../../../services/collections_service.dart';

final _dateFormat = DateFormat('dd MMM yyyy');
final _currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

/// Accounts-receivable aging and the collection follow-up worklist.
///
/// Lives under `features/collections/` rather than `features/reports/` for the
/// same reason banking and loyalty do: `reports/` is read-only output, and
/// this screen writes — logging calls, scheduling reminders and opening
/// WhatsApp all change data.
class CollectionsScreen extends ConsumerStatefulWidget {
  const CollectionsScreen({super.key});

  @override
  ConsumerState<CollectionsScreen> createState() => _CollectionsScreenState();
}

class _CollectionsScreenState extends ConsumerState<CollectionsScreen>
    with SingleTickerProviderStateMixin {
  final _service = CollectionsService();

  late TabController _tabs;
  late Future<AgingReport> _agingFuture;
  late Future<List<CollectionActivity>> _followUpsFuture;

  /// The report is always computed against a moment, and that moment is shown
  /// in the header — an aging figure with no as-of date is meaningless.
  DateTime _asOf = DateTime.now();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _load() {
    _agingFuture = _service.generateAgingReport(asOf: _asOf);
    _followUpsFuture = _service.getPendingFollowUps();
  }

  Future<void> _pickAsOf() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _asOf,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked == null || !mounted) return;
    setState(() {
      // End of the chosen day, so a report "as of the 15th" includes the
      // 15th's sales rather than stopping at midnight.
      _asOf = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
      _load();
    });
  }

  void _reload() => setState(_load);

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Collections',
      actions: [
        IconButton(
          icon: const Icon(Icons.event),
          tooltip: 'Report as of a different date',
          onPressed: _pickAsOf,
        ),
        IconButton(icon: const Icon(Icons.refresh), tooltip: 'Refresh', onPressed: _reload),
      ],
      body: Column(
        children: [
          TabBar(
            controller: _tabs,
            labelColor: Theme.of(context).colorScheme.primary,
            tabs: const [
              Tab(text: 'Aging'),
              Tab(text: 'Follow-ups'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [_agingTab(), _followUpTab()],
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------- aging tab

  Widget _agingTab() {
    return FutureBuilder<AgingReport>(
      future: _agingFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Could not load the aging report: ${snapshot.error}'));
        }
        final report = snapshot.data!;
        if (report.rows.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Nothing outstanding as of ${_dateFormat.format(_asOf)}.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            _summaryCard(report),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Text('Oldest debt first', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            ...report.rows.map(_customerTile),
          ],
        );
      },
    );
  }

  Widget _summaryCard(AgingReport report) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Receivable as of ${_dateFormat.format(_asOf)}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              _currency.format(report.grandTotal),
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),
            Text(
              '${report.customerCount} customer(s), ${report.overdueCustomerCount} with '
              'something past 30 days',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const Divider(height: 24),
            ...AgingBucket.values.map((bucket) {
              final amount = report.totalIn(bucket);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(bucket.label, style: TextStyle(color: _bucketColour(bucket))),
                    Text(
                      _currency.format(amount),
                      style: TextStyle(
                        fontWeight: amount > 0 ? FontWeight.bold : FontWeight.normal,
                        color: _bucketColour(bucket),
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 12),
            const Text(
              'Debts are aged from the date of the credit sale — this app records no '
              'invoice due date. Payments clear the oldest debt first.',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Color _bucketColour(AgingBucket bucket) => switch (bucket) {
        AgingBucket.current => Colors.green.shade700,
        AgingBucket.days30 => Colors.orange.shade700,
        AgingBucket.days60 => Colors.deepOrange.shade700,
        AgingBucket.days90Plus => Colors.red.shade700,
      };

  Widget _customerTile(CustomerAging aging) {
    final worst = aging.openCharges.isEmpty
        ? AgingBucket.current
        : aging.openCharges
            .map((c) => c.bucket)
            .reduce((a, b) => a.index >= b.index ? a : b);
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _bucketColour(worst).withValues(alpha: 0.15),
          child: Icon(Icons.person, color: _bucketColour(worst)),
        ),
        title: Text(aging.customer.name),
        subtitle: Text(
          'Oldest ${aging.oldestChargeDays} day(s) • ${aging.openCharges.length} open item(s)'
          '${aging.customer.phone.isEmpty ? '' : ' • ${aging.customer.phone}'}',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Text(
          _currency.format(aging.totalOutstanding),
          style: TextStyle(fontWeight: FontWeight.bold, color: _bucketColour(worst)),
        ),
        onTap: () => _openCustomer(aging),
      ),
    );
  }

  // --------------------------------------------------------- customer sheet

  Future<void> _openCustomer(CustomerAging aging) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (_, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(16),
          children: [
            Text(aging.customer.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Text(
              '${_currency.format(aging.totalOutstanding)} outstanding'
              '${aging.customer.phone.isEmpty ? '' : ' • ${aging.customer.phone}'}',
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.chat, size: 18),
                  label: const Text('WhatsApp reminder'),
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    _sendReminder(aging);
                  },
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.add_task, size: 18),
                  label: const Text('Log activity'),
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    _logActivity(aging);
                  },
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.schedule, size: 18),
                  label: const Text('Schedule follow-up'),
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    _scheduleFollowUp(aging);
                  },
                ),
              ],
            ),
            const Divider(height: 32),
            const Text('Open items', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...aging.openCharges.map((charge) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${charge.referenceType} • ${_dateFormat.format(
                      DateTime.fromMillisecondsSinceEpoch(charge.createdAt * 1000),
                    )}',
                  ),
                  subtitle: Text(
                    '${charge.ageInDays} day(s) old • ${charge.bucket.label}'
                    '${charge.outstanding < charge.originalAmount ? ' • part-paid from ${_currency.format(charge.originalAmount)}' : ''}',
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: Text(
                    _currency.format(charge.outstanding),
                    style: TextStyle(color: _bucketColour(charge.bucket)),
                  ),
                )),
            const Divider(height: 32),
            const Text('Collection history', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            FutureBuilder<List<CollectionActivity>>(
              future: _service.getActivitiesForCustomer(aging.customer.id),
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.all(8),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final activities = snapshot.data ?? const <CollectionActivity>[];
                if (activities.isEmpty) {
                  return const Text(
                    'Nobody has chased this customer yet.',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  );
                }
                return Column(children: activities.map(_activityTile).toList());
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _activityTile(CollectionActivity activity) {
    final when = activity.completedDate ?? activity.scheduledDate ?? activity.createdAt;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(_activityIcon(activity.activityType), size: 20),
      title: Text('${activity.activityType.name} • ${activity.status.name}'),
      subtitle: Text(
        '${_dateFormat.format(DateTime.fromMillisecondsSinceEpoch(when * 1000))}'
        '${activity.notes == null ? '' : ' — ${activity.notes}'}',
        style: const TextStyle(fontSize: 11),
      ),
      trailing: activity.amountCollected == null || activity.amountCollected == 0
          ? null
          : Text(
              _currency.format(activity.amountCollected),
              style: TextStyle(color: Colors.green.shade700, fontSize: 12),
            ),
    );
  }

  IconData _activityIcon(CollectionActivityType type) => switch (type) {
        CollectionActivityType.call => Icons.phone,
        CollectionActivityType.email => Icons.email,
        CollectionActivityType.sms => Icons.sms,
        CollectionActivityType.whatsapp => Icons.chat,
        CollectionActivityType.visit => Icons.directions_walk,
        CollectionActivityType.payment => Icons.payments,
      };

  // ------------------------------------------------------------- follow-ups

  Widget _followUpTab() {
    return FutureBuilder<List<CollectionActivity>>(
      future: _followUpsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Could not load follow-ups: ${snapshot.error}'));
        }
        final pending = snapshot.data ?? const <CollectionActivity>[];
        if (pending.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No follow-ups scheduled. Open a customer from the Aging tab to schedule one.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ),
          );
        }

        final now = DateTime.now();
        return ListView(
          padding: const EdgeInsets.all(12),
          children: pending.map((activity) {
            final due = activity.isDue(asOf: now);
            return Card(
              child: ListTile(
                leading: Icon(
                  _activityIcon(activity.activityType),
                  color: due ? Colors.red.shade700 : Colors.grey,
                ),
                title: Text(activity.activityType.name),
                subtitle: Text(
                  'Due ${_dateFormat.format(
                    DateTime.fromMillisecondsSinceEpoch(activity.scheduledDate! * 1000),
                  )}${due ? ' — overdue' : ''}'
                  '${activity.notes == null ? '' : '\n${activity.notes}'}',
                  style: TextStyle(fontSize: 12, color: due ? Colors.red.shade700 : null),
                ),
                isThreeLine: activity.notes != null,
                trailing: PopupMenuButton<String>(
                  onSelected: (value) => _resolveFollowUp(activity, value),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'complete', child: Text('Mark done')),
                    PopupMenuItem(value: 'skip', child: Text('Skip')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Future<void> _resolveFollowUp(CollectionActivity activity, String action) async {
    try {
      switch (action) {
        case 'complete':
          await _service.completeActivity(activity.id);
        case 'skip':
          await _service.skipActivity(activity.id);
        case 'delete':
          await _service.deleteFollowUp(activity.id);
      }
      if (!mounted) return;
      _reload();
    } on CollectionsException catch (e) {
      _showError(e.message);
    }
  }

  // ---------------------------------------------------------------- actions

  Future<void> _sendReminder(CustomerAging aging) async {
    try {
      await _service.sendDuesReminder(aging.customer.id, asOf: _asOf);
      if (!mounted) return;
      _reload();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Opened WhatsApp with the reminder — press send there to deliver it.'),
      ));
    } on CollectionsException catch (e) {
      _showError(e.message);
    }
  }

  Future<void> _logActivity(CustomerAging aging) async {
    final type = await _pickActivityType('Log an activity');
    if (type == null || !mounted) return;

    final notesController = TextEditingController();
    final amountController = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${type.name} — ${aging.customer.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: notesController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Notes'),
            ),
            TextField(
              controller: amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Amount collected (optional)',
                helperText: 'Recording it here does not post a payment.',
              ),
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

    final amountText = amountController.text.trim();
    final amount = amountText.isEmpty ? null : double.tryParse(amountText);
    if (amountText.isNotEmpty && amount == null) {
      _showError('"$amountText" is not a number.');
      return;
    }

    try {
      await _service.logActivity(
        customerId: aging.customer.id,
        activityType: type,
        notes: notesController.text.trim().isEmpty ? null : notesController.text.trim(),
        amountCollected: amount,
      );
      if (!mounted) return;
      _reload();
    } on CollectionsException catch (e) {
      _showError(e.message);
    }
  }

  Future<void> _scheduleFollowUp(CustomerAging aging) async {
    final type = await _pickActivityType('Schedule a follow-up');
    if (type == null || !mounted) return;

    final when = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 7)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (when == null || !mounted) return;

    try {
      await _service.scheduleFollowUp(
        customerId: aging.customer.id,
        activityType: type,
        // End of the chosen day, so a reminder for today is not instantly
        // rejected as being in the past.
        scheduledDate: DateTime(when.year, when.month, when.day, 23, 59, 59),
      );
      if (!mounted) return;
      _reload();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Follow-up scheduled for ${_dateFormat.format(when)}.'),
      ));
    } on CollectionsException catch (e) {
      _showError(e.message);
    }
  }

  Future<CollectionActivityType?> _pickActivityType(String title) {
    return showDialog<CollectionActivityType>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(title),
        children: CollectionActivityType.values
            .map((type) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(dialogContext, type),
                  child: Row(
                    children: [
                      Icon(_activityIcon(type), size: 20),
                      const SizedBox(width: 12),
                      Text(type.name),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }
}
