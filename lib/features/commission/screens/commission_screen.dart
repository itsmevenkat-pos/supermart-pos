import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/app_scaffold.dart';
import '../../../models/commission_rule_model.dart';
import '../../../models/commission_settlement_model.dart';
import '../../../models/salesman_model.dart';
import '../../../repositories/salesman_repository.dart';
import '../../../services/commission_exceptions.dart';
import '../../../services/commission_service.dart';

final _dateFormat = DateFormat('dd MMM yyyy');
final _monthFormat = DateFormat('MMMM yyyy');
final _currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

/// Commission rules per salesman and the settlements raised against them.
///
/// Settlement periods are whole calendar months. That is a deliberate limit,
/// not an oversight: the `UNIQUE(salesman_id, period_from, period_to)`
/// constraint only catches an exactly repeated period, so two overlapping but
/// differently-bounded periods would double-pay the overlap. Offering only
/// whole months makes overlaps impossible from this screen. See
/// `docs/COLLECTIONS_COMMISSION_ARCHITECTURE.md`.
class CommissionScreen extends ConsumerStatefulWidget {
  const CommissionScreen({super.key});

  @override
  ConsumerState<CommissionScreen> createState() => _CommissionScreenState();
}

class _CommissionScreenState extends ConsumerState<CommissionScreen> {
  final _service = CommissionService();
  final _salesmen = SalesmanRepository();

  late Future<_CommissionOverview> _future;

  /// The month settlements are raised for. Defaults to last month, since a
  /// month is normally settled once it is over.
  late DateTime _period;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _period = DateTime(now.year, now.month - 1);
    _load();
  }

  void _load() {
    _future = _loadOverview();
  }

  Future<_CommissionOverview> _loadOverview() async {
    final salesmen = await _salesmen.getAll(activeOnly: true);
    final settlements = await _service.getSettlements();
    final outstanding = await _service.outstandingCommission();
    final rules = <String, List<CommissionRule>>{};
    for (final salesman in salesmen) {
      rules[salesman.id] = await _service.getRules(salesman.id, activeOnly: true);
    }
    return _CommissionOverview(
      salesmen: salesmen,
      rulesBySalesman: rules,
      settlements: settlements,
      outstanding: outstanding,
    );
  }

  DateTime get _periodStart => DateTime(_period.year, _period.month);
  DateTime get _periodEnd => DateTime(_period.year, _period.month + 1)
      .subtract(const Duration(seconds: 1));

  void _reload() => setState(_load);

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Commission',
      actions: [
        IconButton(icon: const Icon(Icons.refresh), tooltip: 'Refresh', onPressed: _reload),
      ],
      body: FutureBuilder<_CommissionOverview>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Could not load commission data: ${snapshot.error}'));
          }
          final overview = snapshot.data!;

          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              _periodCard(overview),
              const SizedBox(height: 8),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Text('Salesmen', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              if (overview.salesmen.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'No active salesmen. Add one from the Salesmen screen first.',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              else
                ...overview.salesmen.map((s) => _salesmanCard(s, overview)),
              const Divider(height: 32),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Text('Settlements', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              if (overview.settlements.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No settlements raised yet.', style: TextStyle(color: Colors.grey)),
                )
              else
                ...overview.settlements.map((s) => _settlementCard(s, overview)),
            ],
          );
        },
      ),
    );
  }

  Widget _periodCard(_CommissionOverview overview) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Unpaid commission', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              _currency.format(overview.outstanding),
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  tooltip: 'Previous month',
                  onPressed: () => setState(() {
                    _period = DateTime(_period.year, _period.month - 1);
                  }),
                ),
                Expanded(
                  child: Text(
                    'Settlement period: ${_monthFormat.format(_period)}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  tooltip: 'Next month',
                  onPressed: () => setState(() {
                    _period = DateTime(_period.year, _period.month + 1);
                  }),
                ),
              ],
            ),
            const Text(
              'Periods are whole calendar months, so two settlements can never overlap and '
              'double-pay. Commission is not posted to the general ledger — see the '
              'architecture doc.',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _salesmanCard(Salesman salesman, _CommissionOverview overview) {
    final rules = overview.rulesBySalesman[salesman.id] ?? const <CommissionRule>[];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(salesman.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Rule'),
                  onPressed: () => _addRule(salesman),
                ),
                FilledButton.icon(
                  icon: const Icon(Icons.calculate, size: 18),
                  label: const Text('Settle'),
                  onPressed: () => _createSettlement(salesman),
                ),
              ],
            ),
            if (rules.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'No active commission rule — settling will be refused until one exists.',
                  style: TextStyle(fontSize: 12, color: Colors.orange),
                ),
              )
            else
              ...rules.map((rule) => Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(_describeRule(rule), style: const TextStyle(fontSize: 12)),
                        ),
                        IconButton(
                          icon: const Icon(Icons.block, size: 18),
                          tooltip: 'Retire this rule',
                          onPressed: () => _deactivateRule(rule),
                        ),
                      ],
                    ),
                  )),
          ],
        ),
      ),
    );
  }

  String _describeRule(CommissionRule rule) {
    final from = _dateFormat.format(DateTime.fromMillisecondsSinceEpoch(rule.effectiveFrom * 1000));
    final to = rule.effectiveTo == null
        ? 'ongoing'
        : _dateFormat.format(DateTime.fromMillisecondsSinceEpoch(rule.effectiveTo! * 1000));
    final body = switch (rule.ruleType) {
      CommissionRuleType.percentage =>
        '${(rule.baseRate * 100).toStringAsFixed(2)}% of sales',
      CommissionRuleType.tiered => rule.tiers
          .map((t) => t.upTo == null
              ? 'above: ${(t.rate * 100).toStringAsFixed(2)}%'
              : '≤${_currency.format(t.upTo)}: ${(t.rate * 100).toStringAsFixed(2)}%')
          .join(', '),
    };
    return '$body  ($from → $to)';
  }

  Widget _settlementCard(CommissionSettlement settlement, _CommissionOverview overview) {
    final salesman = overview.salesmen.where((s) => s.id == settlement.salesmanId).firstOrNull;
    final from = DateTime.fromMillisecondsSinceEpoch(settlement.periodFrom * 1000);
    final to = DateTime.fromMillisecondsSinceEpoch(settlement.periodTo * 1000);
    return Card(
      child: ListTile(
        leading: Icon(
          settlement.isSettled ? Icons.check_circle : Icons.pending,
          color: settlement.isSettled ? Colors.green.shade700 : Colors.orange.shade700,
        ),
        title: Text(salesman?.name ?? settlement.salesmanId),
        subtitle: Text(
          '${_dateFormat.format(from)} → ${_dateFormat.format(to)}\n'
          'Gross ${_currency.format(settlement.grossSales)}'
          '${settlement.salaryReference == null ? '' : ' • ref ${settlement.salaryReference}'}',
          style: const TextStyle(fontSize: 12),
        ),
        isThreeLine: true,
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              _currency.format(settlement.commissionAmount),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (!settlement.isSettled)
              TextButton(
                onPressed: () => _markSettled(settlement),
                child: const Text('Mark paid'),
              ),
          ],
        ),
        onLongPress: settlement.isSettled ? null : () => _deleteSettlement(settlement),
      ),
    );
  }

  // ---------------------------------------------------------------- actions

  Future<void> _createSettlement(Salesman salesman) async {
    try {
      // Show the working before committing to a payable.
      final calculation = await _service.calculateCommission(
        salesman.id,
        _periodStart,
        _periodEnd,
      );
      if (!mounted) return;

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('${salesman.name} — ${_monthFormat.format(_period)}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Gross sales: ${_currency.format(calculation.grossSales)}'),
              Text('Commission: ${_currency.format(calculation.commissionAmount)}'),
              Text(
                'Effective rate: ${(calculation.effectiveRate * 100).toStringAsFixed(2)}%',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              if (calculation.bands.isNotEmpty) ...[
                const Divider(),
                const Text('Bands', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                ...calculation.bands.map((band) => Text(
                      '${_currency.format(band.salesInBand)} @ '
                      '${(band.rate * 100).toStringAsFixed(2)}% = '
                      '${_currency.format(band.commission)}',
                      style: const TextStyle(fontSize: 12),
                    )),
              ],
              const SizedBox(height: 8),
              const Text(
                'Cancelled sales are excluded. This raises a payable; it does not pay it.',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Raise settlement'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;

      await _service.createSettlement(salesman.id, _periodStart, _periodEnd);
      if (!mounted) return;
      _reload();
    } on CommissionException catch (e) {
      _showError(e.message);
    }
  }

  Future<void> _markSettled(CommissionSettlement settlement) async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Mark commission paid'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${_currency.format(settlement.commissionAmount)} will be marked as paid out.'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Salary / voucher reference (optional)',
                helperText: 'Free text — this app has no payroll module to link to.',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Confirm')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await _service.markAsSettled(
        settlement.id,
        salaryReference: controller.text.trim().isEmpty ? null : controller.text.trim(),
      );
      if (!mounted) return;
      _reload();
    } on CommissionException catch (e) {
      _showError(e.message);
    }
  }

  Future<void> _deleteSettlement(CommissionSettlement settlement) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this settlement?'),
        content: const Text(
          'The payable is removed and the period can be recalculated. Only possible '
          'while it is unpaid.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await _service.deleteSettlement(settlement.id);
      if (!mounted) return;
      _reload();
    } on CommissionException catch (e) {
      _showError(e.message);
    }
  }

  Future<void> _deactivateRule(CommissionRule rule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Retire this rule?'),
        content: const Text(
          'It stops applying to new settlements. The rule is kept, not deleted, so past '
          'settlements still show what they were based on.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Retire')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await _service.deactivateRule(rule.id);
      if (!mounted) return;
      _reload();
    } on CommissionException catch (e) {
      _showError(e.message);
    }
  }

  Future<void> _addRule(Salesman salesman) async {
    final rateController = TextEditingController();
    final tierController = TextEditingController();
    var type = CommissionRuleType.percentage;
    DateTime effectiveFrom = DateTime(DateTime.now().year, DateTime.now().month);

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Commission rule — ${salesman.name}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SegmentedButton<CommissionRuleType>(
                  segments: const [
                    ButtonSegment(value: CommissionRuleType.percentage, label: Text('Flat %')),
                    ButtonSegment(value: CommissionRuleType.tiered, label: Text('Tiered')),
                  ],
                  selected: {type},
                  onSelectionChanged: (s) => setDialogState(() => type = s.first),
                ),
                const SizedBox(height: 12),
                if (type == CommissionRuleType.percentage)
                  TextField(
                    controller: rateController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Rate %',
                      helperText: 'e.g. 2.5 for two and a half percent',
                    ),
                  )
                else
                  TextField(
                    controller: tierController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Bands',
                      helperText: 'One per line: "50000 2" means up to ₹50,000 at 2%.\n'
                          'Last line may be "rest 3" for everything above.',
                    ),
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: Text('Effective from ${_dateFormat.format(effectiveFrom)}')),
                    TextButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: effectiveFrom,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (picked != null) setDialogState(() => effectiveFrom = picked);
                      },
                      child: const Text('Change'),
                    ),
                  ],
                ),
                const Text(
                  'Tiers are marginal: each band\'s rate applies only to the sales inside it.',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (saved != true || !mounted) return;

    try {
      final CommissionRule rule;
      if (type == CommissionRuleType.percentage) {
        final percent = double.tryParse(rateController.text.trim());
        if (percent == null) {
          _showError('"${rateController.text.trim()}" is not a number.');
          return;
        }
        rule = CommissionRule.percentage(
          salesmanId: salesman.id,
          rate: percent / 100,
          effectiveFrom: effectiveFrom,
        );
      } else {
        final tiers = _parseTiers(tierController.text);
        if (tiers == null) {
          _showError('Could not read the bands. Use one "limit rate" pair per line.');
          return;
        }
        rule = CommissionRule.tiered(
          salesmanId: salesman.id,
          tiers: tiers,
          effectiveFrom: effectiveFrom,
        );
      }
      await _service.createRule(rule);
      if (!mounted) return;
      _reload();
    } on CommissionException catch (e) {
      _showError(e.message);
    }
  }

  /// Parses the band editor's text. Returns null if any line is unreadable —
  /// a partly-understood rule is worse than a rejected one, since the shop
  /// would be paying against bands it never entered.
  List<CommissionTier>? _parseTiers(String text) {
    final tiers = <CommissionTier>[];
    for (final line in text.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final parts = trimmed.split(RegExp(r'\s+'));
      if (parts.length != 2) return null;
      final rate = double.tryParse(parts[1]);
      if (rate == null) return null;
      if (parts[0].toLowerCase() == 'rest' || parts[0] == '*') {
        tiers.add(CommissionTier(upTo: null, rate: rate / 100));
        continue;
      }
      final limit = double.tryParse(parts[0]);
      if (limit == null) return null;
      tiers.add(CommissionTier(upTo: limit, rate: rate / 100));
    }
    return tiers.isEmpty ? null : tiers;
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }
}

class _CommissionOverview {
  const _CommissionOverview({
    required this.salesmen,
    required this.rulesBySalesman,
    required this.settlements,
    required this.outstanding,
  });

  final List<Salesman> salesmen;
  final Map<String, List<CommissionRule>> rulesBySalesman;
  final List<CommissionSettlement> settlements;
  final double outstanding;
}
