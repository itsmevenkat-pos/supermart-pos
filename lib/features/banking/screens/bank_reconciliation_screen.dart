import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_scaffold.dart';
import '../../../models/bank_account_model.dart';
import '../../../models/bank_transaction_model.dart';
import '../../../repositories/bank_reconciliation_repository.dart';
import '../../../services/bank_reconciliation_exceptions.dart';
import '../../../services/bank_reconciliation_service.dart';

/// One account's reconciliation: the summary at the top, the statement lines
/// below, and the import/auto-match actions that move them.
///
/// The screen deliberately shows *unmatched* lines first and keeps the variance
/// visible at all times — the two numbers a person actually needs in order to
/// decide whether the period is done.
class BankReconciliationScreen extends ConsumerStatefulWidget {
  const BankReconciliationScreen({super.key, required this.bankAccountId});

  final String bankAccountId;

  @override
  ConsumerState<BankReconciliationScreen> createState() => _BankReconciliationScreenState();
}

class _BankReconciliationScreenState extends ConsumerState<BankReconciliationScreen> {
  final _repo = BankReconciliationRepository();
  final _service = BankReconciliationService();

  late Future<_ReconciliationView> _viewFuture;
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _viewFuture = _buildView();
  }

  Future<_ReconciliationView> _buildView() async {
    final account = await _repo.getAccount(widget.bankAccountId);
    if (account == null) {
      throw StateError('Bank account ${widget.bankAccountId} no longer exists.');
    }
    final transactions = await _repo.getTransactionsForAccount(widget.bankAccountId);
    // An unlinked account has no ledger side, so there is no summary to show —
    // the UI says so rather than surfacing the exception as an error screen.
    ReconciliationSummary? summary;
    if (account.glAccountId != null) {
      summary = await _service.reconcile(widget.bankAccountId);
    }
    return _ReconciliationView(account: account, transactions: transactions, summary: summary);
  }

  Future<void> _refresh() async {
    setState(_load);
    await _viewFuture;
  }

  void _report(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : null,
      ),
    );
  }

  /// Wraps an action so every path re-reads the data and clears the busy flag,
  /// including the failure path — a stuck spinner after a bad CSV is its own
  /// small disaster.
  Future<void> _run(Future<String> Function() action) async {
    setState(() => _isBusy = true);
    try {
      final message = await action();
      await _refresh();
      _report(message);
    } catch (e) {
      _report('$e', isError: true);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _importStatement() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (result == null || result.files.single.path == null) return;
    final path = result.files.single.path!;

    if (!mounted) return;
    final details = await showDialog<_ImportDetails>(
      context: context,
      builder: (_) => const _ImportDetailsDialog(),
    );
    if (details == null) return;

    await _run(() async {
      final csv = await File(path).readAsString(encoding: utf8);
      final statement = await _service.importStatement(
        bankAccountId: widget.bankAccountId,
        statementDate: details.statementDate,
        beginningBalance: details.beginningBalance,
        endingBalance: details.endingBalance,
        csv: csv,
      );
      final lines = await _repo.getTransactionsForStatement(statement.id);
      return 'Imported ${lines.length} transaction(s).';
    });
  }

  Future<void> _autoMatch() => _run(() async {
        final matched = await _service.autoMatch(widget.bankAccountId);
        return matched == 0
            ? 'No exact date-and-amount matches to confirm — review the remaining lines by hand.'
            : 'Confirmed $matched exact match(es).';
      });

  Future<void> _matchByHand(BankTransaction transaction) async {
    final suggestions = await _service.suggestMatches(widget.bankAccountId);
    final forThisLine = suggestions.where((s) => s.transaction.id == transaction.id).toList();
    if (!mounted) return;

    if (forThisLine.isEmpty) {
      _report('No ledger entry within ±2 days and ±₹0.01 of this line.');
      return;
    }

    final chosen = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirm match'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: forThisLine
              .map((s) => ListTile(
                    title: Text(s.entry.description),
                    subtitle: Text(
                      '${_formatDate(s.entry.entryDateTime)} · '
                      '₹${s.entry.amount.toStringAsFixed(2)} · '
                      '${s.dayDifference} day(s) apart',
                    ),
                    onTap: () => Navigator.pop(context, s.entry.id),
                  ))
              .toList(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ],
      ),
    );
    if (chosen == null) return;

    await _run(() async {
      await _service.matchTransaction(transaction.id, chosen);
      return 'Matched.';
    });
  }

  Future<void> _markReconciled(BankAccount account) async {
    final through = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      helpText: 'Reconciled through',
    );
    if (through == null) return;

    await _run(() async {
      try {
        await _service.markReconciled(widget.bankAccountId, through: through);
        return 'Reconciled through ${_formatDate(through)}.';
      } on BankReconciliationException {
        if (!mounted) rethrow;
        final accept = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Period does not balance'),
            content: const Text(
              'There is still a variance or unmatched lines in this period. '
              'Closing it anyway records that you have seen and accepted the difference.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Accept anyway')),
            ],
          ),
        );
        if (accept != true) return 'Left open.';
        await _service.markReconciled(widget.bankAccountId, through: through, force: true);
        return 'Closed with an accepted variance through ${_formatDate(through)}.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Reconcile',
      actions: [
        IconButton(icon: const Icon(Icons.refresh), onPressed: () => setState(_load)),
      ],
      body: FutureBuilder<_ReconciliationView>(
        future: _viewFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final view = snapshot.data!;
          return Column(
            children: [
              if (_isBusy) const LinearProgressIndicator(),
              _SummaryCard(view: view),
              _ActionBar(
                canReconcile: view.account.glAccountId != null,
                isBusy: _isBusy,
                onImport: _importStatement,
                onAutoMatch: _autoMatch,
                onClose: () => _markReconciled(view.account),
              ),
              const Divider(height: 1),
              Expanded(child: _TransactionList(view: view, onMatch: _matchByHand, onAction: _run)),
            ],
          );
        },
      ),
    );
  }
}

/// Everything one build of this screen needs, fetched together so the widget
/// tree never has to await inside `build`.
class _ReconciliationView {
  _ReconciliationView({required this.account, required this.transactions, required this.summary});

  final BankAccount account;
  final List<BankTransaction> transactions;

  /// Null when the account has no linked ledger account.
  final ReconciliationSummary? summary;
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.view});

  final _ReconciliationView view;

  @override
  Widget build(BuildContext context) {
    final summary = view.summary;
    if (summary == null) {
      return const Card(
        margin: EdgeInsets.all(12),
        child: ListTile(
          leading: Icon(Icons.link_off),
          title: Text('Not linked to a ledger account'),
          subtitle: Text('Link this bank account to a chart-of-accounts row before reconciling.'),
        ),
      );
    }

    final theme = Theme.of(context);
    final balanced = summary.variance.abs() <= BankReconciliationService.amountTolerance;
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${view.account.bankName} · ${view.account.maskedNumber}', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            _row(context, 'Ledger balance', summary.glBalance),
            _row(context, 'Statement balance', summary.statementBalance),
            const Divider(),
            _row(
              context,
              'Variance',
              summary.variance,
              color: balanced ? Colors.green : theme.colorScheme.error,
            ),
            const SizedBox(height: 8),
            Text(
              '${summary.matchedCount} matched · ${summary.unmatchedCount} unmatched · '
              '${summary.ignoredCount} ignored',
              style: theme.textTheme.bodySmall,
            ),
            if (summary.unmatchedCount > 0)
              Text(
                'Outstanding lines total ₹${summary.unmatchedTotal.toStringAsFixed(2)}',
                style: theme.textTheme.bodySmall,
              ),
            if (summary.isReconciled)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'This period reconciles.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: Colors.green),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String label, double amount, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            '₹${amount.toStringAsFixed(2)}',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: color,
                  fontWeight: color == null ? null : FontWeight.bold,
                ),
          ),
        ],
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.canReconcile,
    required this.isBusy,
    required this.onImport,
    required this.onAutoMatch,
    required this.onClose,
  });

  final bool canReconcile;
  final bool isBusy;
  final VoidCallback onImport;
  final VoidCallback onAutoMatch;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Wrap(
        spacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: isBusy ? null : onImport,
            icon: const Icon(Icons.upload_file),
            label: const Text('Import CSV'),
          ),
          OutlinedButton.icon(
            onPressed: isBusy || !canReconcile ? null : onAutoMatch,
            icon: const Icon(Icons.auto_fix_high),
            label: const Text('Auto-match'),
          ),
          OutlinedButton.icon(
            onPressed: isBusy || !canReconcile ? null : onClose,
            icon: const Icon(Icons.lock_outline),
            label: const Text('Mark reconciled'),
          ),
        ],
      ),
    );
  }
}

class _TransactionList extends StatelessWidget {
  const _TransactionList({required this.view, required this.onMatch, required this.onAction});

  final _ReconciliationView view;
  final Future<void> Function(BankTransaction) onMatch;
  final Future<void> Function(Future<String> Function()) onAction;

  @override
  Widget build(BuildContext context) {
    if (view.transactions.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            'No statement lines imported yet. Import a CSV with the columns '
            'Date, Reference, Description, Amount — one signed amount per row, '
            'positive for money in and negative for money out.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    // Outstanding lines first — those are the ones needing a decision — then
    // by date within each group.
    final sorted = [...view.transactions]..sort((a, b) {
        if (a.isOutstanding != b.isOutstanding) return a.isOutstanding ? -1 : 1;
        return a.transactionDate.compareTo(b.transactionDate);
      });

    final service = BankReconciliationService();
    return ListView.separated(
      itemCount: sorted.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final transaction = sorted[index];
        return ListTile(
          leading: Icon(
            switch (transaction.matchStatus) {
              BankMatchStatus.matched => Icons.check_circle,
              BankMatchStatus.ignored => Icons.remove_circle_outline,
              BankMatchStatus.unmatched => Icons.help_outline,
            },
            color: switch (transaction.matchStatus) {
              BankMatchStatus.matched => Colors.green,
              BankMatchStatus.ignored => Theme.of(context).disabledColor,
              BankMatchStatus.unmatched => Theme.of(context).colorScheme.error,
            },
          ),
          title: Text(transaction.description ?? transaction.reference ?? 'Statement line'),
          subtitle: Text(
            [
              _formatDate(transaction.transactionDateTime),
              if (transaction.reference != null) transaction.reference!,
            ].join(' · '),
          ),
          trailing: Text(
            '₹${transaction.amount.toStringAsFixed(2)}',
            style: TextStyle(
              color: transaction.isCredit ? Colors.green : Theme.of(context).colorScheme.error,
              fontWeight: FontWeight.bold,
            ),
          ),
          onTap: () async {
            final action = await showModalBottomSheet<String>(
              context: context,
              builder: (_) => SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (transaction.isOutstanding)
                      ListTile(
                        leading: const Icon(Icons.link),
                        title: const Text('Find a ledger entry to match'),
                        onTap: () => Navigator.pop(context, 'match'),
                      ),
                    if (transaction.isOutstanding)
                      ListTile(
                        leading: const Icon(Icons.remove_circle_outline),
                        title: const Text('Ignore this line'),
                        subtitle: const Text('It has no ledger counterpart and never will'),
                        onTap: () => Navigator.pop(context, 'ignore'),
                      ),
                    if (!transaction.isOutstanding)
                      ListTile(
                        leading: const Icon(Icons.undo),
                        title: const Text('Return to unmatched'),
                        onTap: () => Navigator.pop(context, 'unmatch'),
                      ),
                  ],
                ),
              ),
            );
            switch (action) {
              case 'match':
                await onMatch(transaction);
              case 'ignore':
                await onAction(() async {
                  await service.ignoreTransaction(transaction.id);
                  return 'Ignored.';
                });
              case 'unmatch':
                await onAction(() async {
                  await service.unmatchTransaction(transaction.id);
                  return 'Returned to unmatched.';
                });
            }
          },
        );
      },
    );
  }
}

class _ImportDetails {
  const _ImportDetails({
    required this.statementDate,
    required this.beginningBalance,
    this.endingBalance,
  });

  final DateTime statementDate;
  final double beginningBalance;

  /// Null means "derive it from the lines" — see
  /// `BankReconciliationService.importStatement`.
  final double? endingBalance;
}

class _ImportDetailsDialog extends StatefulWidget {
  const _ImportDetailsDialog();

  @override
  State<_ImportDetailsDialog> createState() => _ImportDetailsDialogState();
}

class _ImportDetailsDialogState extends State<_ImportDetailsDialog> {
  final _formKey = GlobalKey<FormState>();
  final _beginningController = TextEditingController(text: '0');
  final _endingController = TextEditingController();
  DateTime _statementDate = DateTime.now();

  @override
  void dispose() {
    _beginningController.dispose();
    _endingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Statement details'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Statement date'),
              subtitle: Text(_formatDate(_statementDate)),
              trailing: const Icon(Icons.calendar_today),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _statementDate,
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now().add(const Duration(days: 1)),
                );
                if (picked != null) setState(() => _statementDate = picked);
              },
            ),
            TextFormField(
              controller: _beginningController,
              decoration: const InputDecoration(labelText: 'Beginning balance', prefixText: '₹ '),
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              validator: (v) => double.tryParse((v ?? '').trim()) == null ? 'Enter a number' : null,
            ),
            TextFormField(
              controller: _endingController,
              decoration: const InputDecoration(
                labelText: 'Ending balance (optional)',
                prefixText: '₹ ',
                helperText: 'Leave blank to derive it from the imported lines',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              validator: (v) {
                final text = (v ?? '').trim();
                if (text.isEmpty) return null;
                return double.tryParse(text) == null ? 'Enter a number' : null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            final ending = _endingController.text.trim();
            Navigator.pop(
              context,
              _ImportDetails(
                statementDate: _statementDate,
                beginningBalance: double.parse(_beginningController.text.trim()),
                endingBalance: ending.isEmpty ? null : double.parse(ending),
              ),
            );
          },
          child: const Text('Import'),
        ),
      ],
    );
  }
}

String _formatDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
