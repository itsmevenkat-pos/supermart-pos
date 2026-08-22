import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/permissions/price_override_guard.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../models/chart_of_account_model.dart';
import '../../../models/user_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../repositories/gl_repository.dart';
import '../../../services/cash_management_service.dart';
import '../../../services/counter_service.dart';

final _currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

class CashManagementScreen extends ConsumerStatefulWidget {
  const CashManagementScreen({super.key});

  @override
  ConsumerState<CashManagementScreen> createState() => _CashManagementScreenState();
}

class _CashManagementScreenState extends ConsumerState<CashManagementScreen> {
  final _service = CashManagementService();
  List<Map<String, dynamic>> _history = [];
  bool _loading = true;
  String? _activeSessionId;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final user = ref.read(authProvider).user;
    if (user == null) return;
    final session = await CounterService().getActiveSession(user.id);
    _activeSessionId = session?.id;
    if (session != null) {
      _history = await _service.manualMovementsForSession(session.id);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<String?> _getApprover() async {
    final user = ref.read(authProvider).user;
    if (user == null) return null;
    if (user.role == UserRole.admin || user.role == UserRole.manager) {
      return user.id;
    }
    final approver = await requireApprovalWithApprover(
      context,
      ref,
      actionLabel: 'Cash management operation',
    );
    return approver?.id;
  }

  Future<void> _doCashIn() async {
    final result = await _showAmountReasonDialog('Cash In', needsReason: true);
    if (result == null) return;
    final user = ref.read(authProvider).user!;
    try {
      await _service.cashIn(
        amount: result.amount,
        reason: result.reason,
        userId: user.id,
        sessionId: _activeSessionId,
        counterparty: result.counterparty,
      );
      _showSuccess('Cash in of ${_currency.format(result.amount)} recorded');
      _loadHistory();
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _doCashOut() async {
    final approver = await _getApprover();
    if (approver == null) return;
    final result = await _showCashOutDialog();
    if (result == null) return;
    final user = ref.read(authProvider).user!;
    try {
      await _service.cashOut(
        amount: result.amount,
        reason: result.reason,
        userId: user.id,
        sessionId: _activeSessionId,
        counterparty: result.counterparty,
        approvedByUserId: approver,
        expenseAccountCode: result.expenseAccountCode,
      );
      _showSuccess('Cash out of ${_currency.format(result.amount)} recorded');
      _loadHistory();
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _doCashDrop() async {
    final approver = await _getApprover();
    if (approver == null) return;
    final result = await _showAmountReasonDialog('Cash Drop', destinationLabel: 'Destination (e.g. safe)');
    if (result == null) return;
    final user = ref.read(authProvider).user!;
    try {
      await _service.cashDrop(
        amount: result.amount,
        userId: user.id,
        destination: result.counterparty ?? 'safe',
        reason: result.reason.isNotEmpty ? result.reason : null,
        sessionId: _activeSessionId,
        approvedByUserId: approver,
      );
      _showSuccess('Cash drop of ${_currency.format(result.amount)} recorded');
      _loadHistory();
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _doManualAdjustment() async {
    final approver = await _getApprover();
    if (approver == null) return;
    final result = await _showManualAdjustmentDialog();
    if (result == null) return;
    final user = ref.read(authProvider).user!;
    try {
      await _service.manualAdjustment(
        amount: result.amount,
        direction: result.direction,
        reason: result.reason,
        userId: user.id,
        approvedByUserId: approver,
        sessionId: _activeSessionId,
      );
      _showSuccess('Manual adjustment of ${_currency.format(result.amount)} (${result.direction}) recorded');
      _loadHistory();
    } catch (e) {
      _showError(e);
    }
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  void _showError(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
    );
  }

  Future<_MovementInput?> _showAmountReasonDialog(
    String title, {
    bool needsReason = false,
    String? destinationLabel,
  }) async {
    final amountCtl = TextEditingController();
    final reasonCtl = TextEditingController();
    final counterpartyCtl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: amountCtl,
                decoration: const InputDecoration(labelText: 'Amount', prefixText: '₹ ', border: OutlineInputBorder()),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (v) {
                  final n = double.tryParse(v ?? '');
                  if (n == null || n <= 0) return 'Enter a positive amount';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: reasonCtl,
                decoration: InputDecoration(labelText: needsReason ? 'Reason *' : 'Reason', border: const OutlineInputBorder()),
                validator: needsReason ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null : null,
              ),
              if (destinationLabel != null) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: counterpartyCtl,
                  decoration: InputDecoration(labelText: destinationLabel, border: const OutlineInputBorder()),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(ctx, true);
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    if (confirmed != true) return null;
    return _MovementInput(
      amount: double.parse(amountCtl.text),
      reason: reasonCtl.text.trim(),
      counterparty: counterpartyCtl.text.trim().isNotEmpty ? counterpartyCtl.text.trim() : null,
    );
  }

  Future<_CashOutInput?> _showCashOutDialog() async {
    final amountCtl = TextEditingController();
    final reasonCtl = TextEditingController();
    final counterpartyCtl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    String? selectedAccountCode;
    List<ChartOfAccount> expenseAccounts = [];

    try {
      expenseAccounts = await GLRepository().getAllAccounts(type: AccountType.expense, isActive: true);
    } catch (_) {}

    if (!mounted) return null;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Cash Out'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: amountCtl,
                    decoration: const InputDecoration(labelText: 'Amount', prefixText: '₹ ', border: OutlineInputBorder()),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    validator: (v) {
                      final n = double.tryParse(v ?? '');
                      if (n == null || n <= 0) return 'Enter a positive amount';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: reasonCtl,
                    decoration: const InputDecoration(labelText: 'Reason *', border: OutlineInputBorder()),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: counterpartyCtl,
                    decoration: const InputDecoration(labelText: 'Paid to', border: OutlineInputBorder()),
                  ),
                  if (expenseAccounts.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String?>(
                      value: selectedAccountCode,
                      decoration: const InputDecoration(
                        labelText: 'Expense account (optional)',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('None — classify later')),
                        ...expenseAccounts.map((a) => DropdownMenuItem(
                              value: a.code,
                              child: Text('${a.code} — ${a.name}'),
                            )),
                      ],
                      onChanged: (v) => setDialogState(() => selectedAccountCode = v),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState!.validate()) Navigator.pop(ctx, true);
              },
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return null;
    return _CashOutInput(
      amount: double.parse(amountCtl.text),
      reason: reasonCtl.text.trim(),
      counterparty: counterpartyCtl.text.trim().isNotEmpty ? counterpartyCtl.text.trim() : null,
      expenseAccountCode: selectedAccountCode,
    );
  }

  Future<_AdjustmentInput?> _showManualAdjustmentDialog() async {
    final amountCtl = TextEditingController();
    final reasonCtl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    String direction = 'in';

    if (!mounted) return null;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Manual Adjustment'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'in', label: Text('Surplus'), icon: Icon(Icons.add)),
                    ButtonSegment(value: 'out', label: Text('Shortage'), icon: Icon(Icons.remove)),
                  ],
                  selected: {direction},
                  onSelectionChanged: (v) => setDialogState(() => direction = v.first),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: amountCtl,
                  decoration: const InputDecoration(labelText: 'Amount', prefixText: '₹ ', border: OutlineInputBorder()),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: (v) {
                    final n = double.tryParse(v ?? '');
                    if (n == null || n <= 0) return 'Enter a positive amount';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: reasonCtl,
                  decoration: const InputDecoration(labelText: 'Reason *', border: OutlineInputBorder()),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState!.validate()) Navigator.pop(ctx, true);
              },
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return null;
    return _AdjustmentInput(
      amount: double.parse(amountCtl.text),
      reason: reasonCtl.text.trim(),
      direction: direction,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Cash Management',
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _activeSessionId == null
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.warning_amber_rounded, size: 48, color: Colors.orange),
                      SizedBox(height: 16),
                      Text('No active shift. Open a counter to manage cash.', style: TextStyle(fontSize: 16)),
                    ],
                  ),
                )
              : Column(
                  children: [
                    _buildActionBar(),
                    const Divider(height: 1),
                    Expanded(child: _buildHistory()),
                  ],
                ),
    );
  }

  Widget _buildActionBar() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _actionButton(Icons.arrow_downward, 'Cash In', Colors.green, _doCashIn),
          _actionButton(Icons.arrow_upward, 'Cash Out', Colors.red, _doCashOut),
          _actionButton(Icons.move_down, 'Cash Drop', Colors.blue, _doCashDrop),
          _actionButton(Icons.tune, 'Manual Adjustment', Colors.orange, _doManualAdjustment),
        ],
      ),
    );
  }

  Widget _actionButton(IconData icon, String label, Color color, VoidCallback onTap) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
    );
  }

  Widget _buildHistory() {
    if (_history.isEmpty) {
      return const Center(
        child: Text('No cash movements this shift', style: TextStyle(color: Colors.grey)),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadHistory,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _history.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final row = _history[i];
          final amount = (row['amount'] as num).toDouble();
          final direction = row['direction'] as String?;
          final sourceType = row['source_type'] as String? ?? '';
          final note = row['note'] as String? ?? '';
          final ts = row['created_at'] as int?;
          final time = ts != null ? DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(ts * 1000)) : '';

          final isIn = direction == 'in';
          return ListTile(
            leading: Icon(
              isIn ? Icons.arrow_downward : Icons.arrow_upward,
              color: isIn ? Colors.green : Colors.red,
            ),
            title: Text(_sourceLabel(sourceType)),
            subtitle: note.isNotEmpty ? Text(note, maxLines: 1, overflow: TextOverflow.ellipsis) : null,
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${isIn ? '+' : '-'}${_currency.format(amount)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isIn ? Colors.green : Colors.red,
                  ),
                ),
                Text(time, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          );
        },
      ),
    );
  }

  String _sourceLabel(String sourceType) {
    switch (sourceType) {
      case 'cash_in':
        return 'Cash In';
      case 'cash_out':
        return 'Cash Out';
      case 'cash_drop':
        return 'Cash Drop';
      case 'cash_transfer_out':
        return 'Transfer Out';
      case 'cash_transfer_in':
        return 'Transfer In';
      case 'manual_adjustment':
        return 'Manual Adjustment';
      default:
        return sourceType;
    }
  }
}

class _MovementInput {
  final double amount;
  final String reason;
  final String? counterparty;
  _MovementInput({required this.amount, required this.reason, this.counterparty});
}

class _CashOutInput extends _MovementInput {
  final String? expenseAccountCode;
  _CashOutInput({
    required super.amount,
    required super.reason,
    super.counterparty,
    this.expenseAccountCode,
  });
}

class _AdjustmentInput {
  final double amount;
  final String reason;
  final String direction;
  _AdjustmentInput({required this.amount, required this.reason, required this.direction});
}
