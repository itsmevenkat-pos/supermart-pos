import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../models/session_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/counter_service.dart';
import '../../../services/day_end_report_service.dart';
import '../../../repositories/cash_movement_repository.dart';

class CounterCloseScreen extends ConsumerStatefulWidget {
  const CounterCloseScreen({super.key});

  @override
  ConsumerState<CounterCloseScreen> createState() => _CounterCloseScreenState();
}

class _CounterCloseScreenState extends ConsumerState<CounterCloseScreen> {
  final _closingCashController = TextEditingController();
  final _notesController = TextEditingController();

  Session? _activeSession;
  double _cashSalesSoFar = 0;
  bool _loading = true;
  bool _saving = false;
  bool _printingReport = false;
  String? _error;
  Session? _closedResult;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _closingCashController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final user = ref.read(authProvider).user;
    if (user == null) {
      setState(() {
        _loading = false;
        _error = 'No user logged in';
      });
      return;
    }
    final session = await CounterService().getActiveSession(user.id);
    if (session == null) {
      setState(() {
        _loading = false;
        _error = 'No open shift found for this user';
      });
      return;
    }
    // Every cash movement in this shift, not just the selling — khata
    // collections and cash refunds move the drawer too (see MigrationV34).
    final cashSales = await CashMovementRepository().getSessionNet(session.id);
    setState(() {
      _activeSession = session;
      _cashSalesSoFar = cashSales;
      _loading = false;
    });
  }

  Future<void> _closeShift() async {
    final session = _activeSession;
    if (session == null) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final closed = await CounterService().closeShift(
        sessionId: session.id,
        closingCash: double.tryParse(_closingCashController.text.trim()) ?? 0,
        denominations: null,
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _closedResult = closed;
        _saving = false;
      });
    } catch (e) {
      setState(() {
        _saving = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _printDayEndReport(Session session) async {
    final user = ref.read(authProvider).user;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No user logged in'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _printingReport = true);
    try {
      final pdfData = await DayEndReportService.generateReport(
        session: session,
        cashier: user,
      );
      if (!mounted) return;
      await DayEndReportService.printReport(context, pdfData);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _printingReport = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Close Shift',
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: _loading
                ? const CircularProgressIndicator()
                : _closedResult != null
                    ? _buildResult(_closedResult!)
                    : _activeSession != null
                        ? _buildForm(_activeSession!)
                        : _buildNoSession(),
          ),
        ),
      ),
    );
  }

  Widget _buildNoSession() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.info_outline, size: 48, color: Colors.grey),
        const SizedBox(height: 12),
        Text(_error ?? 'No open shift', textAlign: TextAlign.center),
        const SizedBox(height: 16),
        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Back')),
      ],
    );
  }

  Widget _buildForm(Session session) {
    final expectedCash = session.openingCash + _cashSalesSoFar;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          color: Colors.grey.shade50,
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _summaryRow('Opening Cash', '₹${session.openingCash.toStringAsFixed(2)}'),
                _summaryRow('Net Cash Movements', '₹${_cashSalesSoFar.toStringAsFixed(2)}'),
                const Divider(),
                _summaryRow(
                  'Expected Cash in Drawer',
                  '₹${expectedCash.toStringAsFixed(2)}',
                  bold: true,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _closingCashController,
          decoration: const InputDecoration(
            labelText: 'Actual Cash Counted (₹)',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.currency_rupee),
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _notesController,
          decoration: const InputDecoration(labelText: 'Notes (optional)', border: OutlineInputBorder()),
          maxLines: 2,
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: Colors.red)),
        ],
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: _saving ? null : _closeShift,
          icon: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.lock),
          label: const Text('Close Shift'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red.shade700,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ],
    );
  }

  Widget _buildResult(Session closed) {
    final diff = closed.difference ?? 0;
    final isShort = diff < 0;
    final isOver = diff > 0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isShort ? Icons.trending_down : (isOver ? Icons.trending_up : Icons.check_circle),
          size: 48,
          color: isShort ? Colors.red : (isOver ? Colors.orange : Colors.green),
        ),
        const SizedBox(height: 12),
        Text(
          'Shift Closed',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _summaryRow('Expected Cash', '₹${(closed.expectedCash ?? 0).toStringAsFixed(2)}'),
                _summaryRow('Actual Cash Counted', '₹${(closed.closingCash ?? 0).toStringAsFixed(2)}'),
                const Divider(),
                _summaryRow(
                  isShort ? 'Shortage' : (isOver ? 'Overage' : 'Balanced'),
                  '₹${diff.abs().toStringAsFixed(2)}',
                  bold: true,
                  color: isShort ? Colors.red : (isOver ? Colors.orange : Colors.green),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _printingReport ? null : () => _printDayEndReport(closed),
          icon: _printingReport
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.print),
          label: const Text('Print Day-End Report'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Done'),
        ),
      ],
    );
  }

  Widget _summaryRow(String label, String value, {bool bold = false, Color? color}) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      fontSize: bold ? 16 : 14,
      color: color,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(value, style: style),
        ],
      ),
    );
  }
}