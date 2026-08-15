import 'package:flutter/material.dart';

import '../../../core/widgets/app_scaffold.dart';
import '../../../models/payment_gateway_transaction_model.dart';
import '../../../models/payment_settlement_model.dart';
import '../../../services/gateways/payment_gateway.dart';
import '../../../services/payment_gateway_exceptions.dart';
import '../../../services/payment_gateway_service.dart';

/// Gateway payments and payouts: what was collected online, and what the
/// gateway has actually deposited.
///
/// Lives in its own feature folder rather than under `reports/` for the same
/// reason the banking and loyalty screens do — `reports/` is read-only
/// output, and this screen records settlements and issues refunds.
class PaymentGatewayScreen extends StatefulWidget {
  const PaymentGatewayScreen({super.key});

  @override
  State<PaymentGatewayScreen> createState() => _PaymentGatewayScreenState();
}

class _PaymentGatewayScreenState extends State<PaymentGatewayScreen> with SingleTickerProviderStateMixin {
  final _service = PaymentGatewayService();

  late final TabController _tabController = TabController(length: 2, vsync: this);

  late Future<List<PaymentGatewayTransaction>> _transactionsFuture;
  late Future<List<PaymentSettlement>> _settlementsFuture;
  late Future<List<PaymentGatewayName>> _availableFuture;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _transactionsFuture = _service.getTransactions();
      _settlementsFuture = _service.getSettlements();
      _availableFuture = _service.availableGateways();
    });
  }

  void _report(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: isError ? Colors.red : null),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Payment Gateways',
      body: Column(
        children: [
          FutureBuilder<List<PaymentGatewayName>>(
            future: _availableFuture,
            builder: (context, snapshot) {
              final available = snapshot.data;
              if (available == null) return const SizedBox.shrink();
              if (available.isEmpty) {
                return Container(
                  width: double.infinity,
                  color: Colors.orange.shade50,
                  padding: const EdgeInsets.all(12),
                  child: const Text(
                    'No payment gateway is configured. Add your Razorpay key id and secret in '
                    'Settings → Payment Gateways before taking online payments. '
                    'PayPal and Square are not implemented in this app.',
                  ),
                );
              }
              return Container(
                width: double.infinity,
                color: Colors.green.shade50,
                padding: const EdgeInsets.all(12),
                child: Text('Configured: ${available.map((g) => g.name).join(", ")}'),
              );
            },
          ),
          TabBar(
            controller: _tabController,
            labelColor: Theme.of(context).colorScheme.primary,
            tabs: const [
              Tab(text: 'Transactions'),
              Tab(text: 'Settlements'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildTransactions(),
                _buildSettlements(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------- transactions

  Widget _buildTransactions() {
    return FutureBuilder<List<PaymentGatewayTransaction>>(
      future: _transactionsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final transactions = snapshot.data ?? const <PaymentGatewayTransaction>[];
        if (transactions.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('No gateway payments yet.'),
            ),
          );
        }

        return ListView.separated(
          itemCount: transactions.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final transaction = transactions[index];
            return ListTile(
              leading: Icon(_statusIcon(transaction.status), color: _statusColour(transaction.status)),
              title: Text(transaction.gatewayTransactionId ?? transaction.gatewayOrderId ?? '(no reference)'),
              subtitle: Text(
                '${transaction.gateway.name} · ${transaction.status.name}'
                ' · created ${_formatDate(transaction.createdAtDateTime)}'
                '${transaction.completedAtDateTime == null ? '' : ' · completed ${_formatDate(transaction.completedAtDateTime!)}'}',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (transaction.isPending)
                    TextButton(
                      onPressed: () => _refresh(transaction),
                      child: const Text('Check status'),
                    ),
                  if (transaction.isSuccessful)
                    TextButton(
                      onPressed: () => _refund(transaction),
                      child: const Text('Refund'),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _refresh(PaymentGatewayTransaction transaction) async {
    try {
      final status = await _service.refreshStatus(transaction.id);
      _report('Gateway reports: ${status.name}');
      _reload();
    } catch (e) {
      _report(_message(e), isError: true);
    }
  }

  Future<void> _refund(PaymentGatewayTransaction transaction) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Refund this payment?'),
        content: const Text(
          'The full payment will be refunded through the gateway and its ledger entries reversed. '
          'Partial refunds are not handled here — use a sales return for those.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Refund')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _service.refundPayment(transactionId: transaction.id);
      _report('Refunded.');
      _reload();
    } catch (e) {
      _report(_message(e), isError: true);
    }
  }

  // ------------------------------------------------------------ settlements

  Widget _buildSettlements() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: ElevatedButton.icon(
              onPressed: _recordSettlement,
              icon: const Icon(Icons.add),
              label: const Text('Record a payout'),
            ),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<PaymentSettlement>>(
            future: _settlementsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final settlements = snapshot.data ?? const <PaymentSettlement>[];
              if (settlements.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No payouts recorded.\n\n'
                      'Gateway fees are recorded here but are NOT posted to the ledger — '
                      'booking them needs a gateway clearing account, which is a decision for '
                      'your accountant.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }

              return ListView.separated(
                itemCount: settlements.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final settlement = settlements[index];
                  return ListTile(
                    title: Text(
                      '₹${settlement.settledAmount.toStringAsFixed(2)} on ${_formatDate(settlement.settlementDateTime)}',
                    ),
                    subtitle: Text(
                      '${settlement.gateway.name} · ${settlement.transactionCount} payments'
                      ' · gross ₹${settlement.totalAmount.toStringAsFixed(2)}'
                      ' · fee ₹${settlement.feesCharged.toStringAsFixed(2)}'
                      ' (${settlement.effectiveFeePercent.toStringAsFixed(2)}%)'
                      '${settlement.settlementReference == null ? '' : ' · ${settlement.settlementReference}'}',
                    ),
                    trailing: TextButton(
                      onPressed: () => _reconcile(settlement),
                      child: const Text('Reconcile'),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _reconcile(PaymentSettlement settlement) async {
    try {
      final result = await _service.reconcileSettlement(settlement.id);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Payout vs. recorded payments'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Gateway says: ₹${result.settlement.totalAmount.toStringAsFixed(2)} '
                  'over ${result.settlement.transactionCount} payments'),
              Text('This app recorded: ₹${result.recordedTotal.toStringAsFixed(2)} '
                  'over ${result.recordedCount} payments'),
              const SizedBox(height: 8),
              Text(
                result.agrees
                    ? 'These agree.'
                    : 'Difference: ₹${result.grossVariance.toStringAsFixed(2)} '
                        'and ${result.countVariance} payment(s).',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: result.agrees ? Colors.green.shade800 : Colors.orange.shade900,
                ),
              ),
              if (!result.agrees) ...[
                const SizedBox(height: 8),
                Text(
                  'A gateway batches on its own cut-off rather than your calendar day, so a payment '
                  'taken late one evening can land in the next day\'s payout. A difference here is '
                  'worth looking at, not necessarily an error.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          ],
        ),
      );
    } catch (e) {
      _report(_message(e), isError: true);
    }
  }

  Future<void> _recordSettlement() async {
    final dateController = TextEditingController(text: _formatDate(DateTime.now()));
    final countController = TextEditingController();
    final grossController = TextEditingController();
    final feeController = TextEditingController();
    final netController = TextEditingController();
    final referenceController = TextEditingController();

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Record a gateway payout'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: dateController,
                  decoration: const InputDecoration(
                    labelText: 'Settlement date (yyyy-MM-dd)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: countController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Number of payments',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: grossController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Gross amount',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: feeController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Fees charged',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: netController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Amount deposited',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: referenceController,
                  decoration: const InputDecoration(
                    labelText: 'Payout reference (optional)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );

    if (saved != true) return;

    final date = DateTime.tryParse(dateController.text.trim());
    if (date == null) {
      _report('Could not read that settlement date — use yyyy-MM-dd.', isError: true);
      return;
    }

    try {
      await _service.recordSettlement(
        gateway: PaymentGatewayName.razorpay,
        settlementDate: date,
        transactionCount: int.tryParse(countController.text.trim()) ?? 0,
        totalAmount: double.tryParse(grossController.text.trim()) ?? 0,
        feesCharged: double.tryParse(feeController.text.trim()) ?? 0,
        settledAmount: double.tryParse(netController.text.trim()) ?? 0,
        settlementReference:
            referenceController.text.trim().isEmpty ? null : referenceController.text.trim(),
      );
      _report('Payout recorded.');
      _reload();
    } catch (e) {
      _report(_message(e), isError: true);
    }
  }

  // ----------------------------------------------------------------- shared

  static String _message(Object error) {
    if (error is PaymentGatewayServiceException) return error.message;
    if (error is PaymentGatewayException) return error.message;
    if (error is GatewayNotConfigured) return error.message;
    return error.toString();
  }

  static String _formatDate(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  static IconData _statusIcon(GatewayTransactionStatus status) => switch (status) {
        GatewayTransactionStatus.success => Icons.check_circle,
        GatewayTransactionStatus.failed => Icons.cancel,
        GatewayTransactionStatus.refunded => Icons.undo,
        GatewayTransactionStatus.pending => Icons.hourglass_empty,
      };

  static Color _statusColour(GatewayTransactionStatus status) => switch (status) {
        GatewayTransactionStatus.success => Colors.green,
        GatewayTransactionStatus.failed => Colors.red,
        GatewayTransactionStatus.refunded => Colors.orange,
        GatewayTransactionStatus.pending => Colors.grey,
      };
}
