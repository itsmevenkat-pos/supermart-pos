import 'package:flutter/material.dart';
import '../../../models/customer_model.dart';
import '../../../models/payment_gateway_transaction_model.dart';
import '../../../services/payment_gateway_service.dart';
import '../../payments/widgets/gateway_collect_dialog.dart';

/// [preFilledMethod] – when the user taps a quick-pay button (Cash/UPI/Card/
/// Credit) on the billing screen, this dialog now opens already set to that
/// single method with the full amount filled in, instead of resetting back
/// to a blank "Cash" row and forcing the cashier to pick again.
///
/// [startWithPartial] – opens the dialog with "Partial Payment" already
/// switched on (used by the new Partial quick-pay button).
///
/// [onPay] now also reports how much change is owed back to the customer
/// (relevant for Cash) as its 4th argument, and — as its 5th — the ids of any
/// gateway transactions collected in this dialog.
///
/// **Gateway payments are collected before the bill is saved.** A configured
/// gateway appears in the method dropdown alongside Cash/UPI/Card/Credit, but
/// its amount cannot be typed: the cashier presses "Collect", the money is
/// taken and verified through [GatewayCollectDialog], and only a *verified*
/// payment puts an amount into the split. That is why the ids come back —
/// the sale does not exist yet at collection time, so `billing_screen` links
/// them to it once `processSale` has written the row. See
/// `docs/PAYMENT_GATEWAY_ARCHITECTURE.md`.
class PaymentDialog extends StatefulWidget {
  final double total;
  final Customer? customer;
  final String? preFilledMethod;
  final bool startWithPartial;
  final void Function(
    Map<String, double> payments,
    double? partialAmount,
    double? creditUsed,
    double changeDue,
    List<String> gatewayTransactionIds,
  ) onPay;

  const PaymentDialog({
    super.key,
    required this.total,
    this.customer,
    this.preFilledMethod,
    this.startWithPartial = false,
    required this.onPay,
  });

  @override
  State<PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<PaymentDialog> {
  final List<Map<String, dynamic>> _payments = [];
  bool _partialPayment = false;

  final List<String> _paymentMethods = ['Cash', 'UPI', 'Card', 'Credit'];

  /// Gateways this shop has configured, appended to [_paymentMethods] once
  /// looked up. Empty for every shop that has not set one up, so the dialog
  /// looks exactly as it did before for them.
  final List<PaymentGatewayName> _gateways = [];

  /// Transaction ids for gateway payments verified in this dialog, handed
  /// back through `onPay` so the sale can be linked to them afterwards.
  final List<String> _gatewayTransactionIds = [];

  bool _isGateway(String method) => _gateways.any((g) => g.name == method);

  @override
  void initState() {
    super.initState();
    _loadGateways();

    final method = widget.preFilledMethod ?? 'Cash';
    final controller = TextEditingController(
      text: widget.preFilledMethod != null ? widget.total.toStringAsFixed(2) : '',
    );
    _payments.add({
      'method': method,
      'amount': widget.preFilledMethod != null ? widget.total : 0.0,
      'controller': controller,
      'receivedController': TextEditingController(
        text: widget.preFilledMethod == 'Cash' ? widget.total.toStringAsFixed(2) : '',
      ),
    });

    if (widget.startWithPartial && widget.customer != null) {
      _partialPayment = true;
    }
  }

  /// Looked up rather than hardcoded, so an unconfigured or unimplemented
  /// gateway is never offered. Failure is deliberately silent: a gateway
  /// lookup problem must not stop a cashier taking cash.
  Future<void> _loadGateways() async {
    try {
      final available = await PaymentGatewayService().availableGateways();
      if (!mounted || available.isEmpty) return;
      setState(() {
        _gateways.addAll(available);
        _paymentMethods.addAll(available.map((g) => g.name));
      });
    } catch (_) {
      // Till keeps working on cash/card either way.
    }
  }

  /// Takes a gateway payment for [row], and only records an amount against it
  /// once the payment has actually been verified.
  Future<void> _collectGatewayPayment(Map<String, dynamic> row) async {
    final gateway = _gateways.firstWhere((g) => g.name == row['method']);
    // Defaults to whatever is still owed on the bill — the common case is the
    // customer paying the remainder online.
    final outstanding = _remainingAmount + (row['amount'] as double);
    if (outstanding <= 0) return;

    final result = await showDialog<GatewayCollectResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => GatewayCollectDialog(amount: outstanding, gateway: gateway),
    );
    if (result == null || !mounted) return;

    setState(() {
      row['amount'] = result.amount;
      (row['controller'] as TextEditingController).text = result.amount.toStringAsFixed(2);
      row['gatewayTransactionId'] = result.transactionId;
      _gatewayTransactionIds.add(result.transactionId);
    });
  }

  @override
  void dispose() {
    for (final p in _payments) {
      (p['controller'] as TextEditingController).dispose();
      (p['receivedController'] as TextEditingController).dispose();
    }
    super.dispose();
  }

  void _addPayment() {
    setState(() {
      _payments.add({
        'method': 'Cash',
        'amount': 0.0,
        'controller': TextEditingController(),
        'receivedController': TextEditingController(),
      });
    });
  }

  void _removePayment(int index) {
    if (_payments.length <= 1) return;
    (_payments[index]['controller'] as TextEditingController).dispose();
    (_payments[index]['receivedController'] as TextEditingController).dispose();
    setState(() {
      _payments.removeAt(index);
    });
  }

  double get _totalPaid =>
      _payments.fold(0.0, (sum, p) => sum + (p['amount'] as double));

  double get _remainingAmount => widget.total - _totalPaid;

  /// Change only makes sense once the bill is fully covered (not a partial
  /// payment) and comes specifically from cash tendered above what was owed.
  double get _totalChangeDue {
    if (_remainingAmount > 0) return 0.0;
    double change = 0.0;
    for (final p in _payments) {
      if (p['method'] == 'Cash') {
        final received = double.tryParse(
              (p['receivedController'] as TextEditingController).text,
            ) ??
            (p['amount'] as double);
        final applied = p['amount'] as double;
        if (received > applied) change += received - applied;
      }
    }
    return change;
  }

  /// Called whenever a Cash row's "Received" field changes. The amount
  /// actually applied to the bill is capped at whatever is still owed
  /// (across all rows) so change is calculated correctly instead of
  /// silently over-paying the bill.
  void _onCashReceivedChanged(Map<String, dynamic> row, String value) {
    final received = double.tryParse(value) ?? 0;
    final othersPaid = _payments
        .where((p) => p != row)
        .fold(0.0, (sum, p) => sum + (p['amount'] as double));
    final stillOwed = (widget.total - othersPaid).clamp(0.0, widget.total);
    final applied = received >= stillOwed ? stillOwed : received;
    setState(() {
      row['amount'] = applied;
      (row['controller'] as TextEditingController).text = applied.toStringAsFixed(2);
    });
  }

  void _quickCash(Map<String, dynamic> row, double amount) {
    (row['receivedController'] as TextEditingController).text = amount.toStringAsFixed(2);
    _onCashReceivedChanged(row, amount.toStringAsFixed(2));
  }

  bool get _canPay {
    if (_exceedsCreditLimit) return false;
    if (_partialPayment) return _totalPaid > 0 && _totalPaid <= widget.total;
    return _totalPaid >= widget.total;
  }

  /// How much new credit this checkout would put on the customer's account —
  /// an explicit "Credit" payment row plus whatever's left as partial-payment
  /// credit. Both increase `customers.outstanding_balance` the same way (see
  /// `SaleRepository.insertSaleWithItems`), so both count against the limit.
  double get _creditExposure {
    final creditRows = _payments
        .where((p) => p['method'] == 'Credit')
        .fold(0.0, (sum, p) => sum + (p['amount'] as double));
    final partialCredit = _partialPayment ? _remainingAmount.clamp(0.0, widget.total) : 0.0;
    return creditRows + partialCredit;
  }

  /// A `creditLimit` of 0 means "no limit configured" (the field's default),
  /// not "no credit allowed" — only enforce once a shop owner has actually
  /// set a positive limit for this customer.
  bool get _exceedsCreditLimit {
    final customer = widget.customer;
    if (customer == null || customer.creditLimit <= 0) return false;
    return (customer.outstandingBalance + _creditExposure) > customer.creditLimit;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Payment'),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Total: ₹${widget.total.toStringAsFixed(2)}', style: const TextStyle(fontSize: 20)),
              const SizedBox(height: 16),
              ..._payments.map((p) => _buildPaymentRow(p)),
              TextButton.icon(
                onPressed: _addPayment,
                icon: const Icon(Icons.add),
                label: const Text('Add Payment Method'),
              ),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Remaining:', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(
                    '₹${_remainingAmount.clamp(0, widget.total).toStringAsFixed(2)}',
                    style: TextStyle(
                      color: _remainingAmount > 0 ? Colors.red : Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              if (_totalChangeDue > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Change to return:', style: TextStyle(fontWeight: FontWeight.bold)),
                      Text(
                        '₹${_totalChangeDue.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: Colors.blue,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: _partialPayment,
                onChanged: (val) {
                  if (val == true && widget.customer == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please select a customer for partial payment'), backgroundColor: Colors.red),
                    );
                    return;
                  }
                  setState(() {
                    _partialPayment = val ?? false;
                  });
                },
                title: const Text('Partial Payment (Remaining as Credit)'),
              ),
              if (_partialPayment && widget.customer != null)
                Padding(
                  padding: const EdgeInsets.only(left: 32.0),
                  child: Text(
                    'Customer: ${widget.customer!.name} (Balance: ₹${widget.customer!.outstandingBalance.toStringAsFixed(2)})',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              if (_exceedsCreditLimit)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      border: Border.all(color: Colors.red),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'This would put ${widget.customer!.name} at ₹${(widget.customer!.outstandingBalance + _creditExposure).toStringAsFixed(2)} '
                      'owed, above their ₹${widget.customer!.creditLimit.toStringAsFixed(2)} credit limit. '
                      'Reduce the credit/partial amount or collect more payment upfront.',
                      style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _canPay
              ? () {
                  if (_partialPayment && widget.customer == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please select a customer for partial payment'), backgroundColor: Colors.red),
                    );
                    return;
                  }
                  final payments = <String, double>{};
                  for (final p in _payments) {
                    final amount = p['amount'] as double;
                    if (amount > 0) {
                      final method = (p['method'] as String).toLowerCase();
                      payments[method] = (payments[method] ?? 0) + amount;
                    }
                  }
                  final totalPaid = payments.values.fold(0.0, (sum, v) => sum + v);
                  final partialAmount = _partialPayment ? widget.total - totalPaid : null;
                  final creditUsed = payments.containsKey('credit') ? payments['credit'] : null;
                  widget.onPay(
                    payments,
                    partialAmount,
                    creditUsed,
                    _totalChangeDue,
                    List.unmodifiable(_gatewayTransactionIds),
                  );
                }
              : null,
          child: const Text('Check Out'),
        ),
      ],
    );
  }

  Widget _buildPaymentRow(Map<String, dynamic> p) {
    final isCash = p['method'] == 'Cash';
    final isGateway = _isGateway(p['method'] as String);
    final index = _payments.indexOf(p);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String>(
                    initialValue: p['method'],
                    decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                    items: _paymentMethods.map((m) {
                      return DropdownMenuItem(value: m, child: Text(m));
                    }).toList(),
                    onChanged: (val) {
                      setState(() {
                        p['method'] = val!;
                        // Reset amount when switching methods so a stale
                        // amount from a previous method isn't silently reused.
                        p['amount'] = 0.0;
                        (p['controller'] as TextEditingController).text = '';
                        (p['receivedController'] as TextEditingController).text = '';
                        // Switching away from a collected gateway payment
                        // drops the claim to it — the payment itself is
                        // already recorded and refundable from the Payment
                        // Gateways screen, it simply no longer settles this
                        // bill.
                        final claimed = p.remove('gatewayTransactionId') as String?;
                        if (claimed != null) _gatewayTransactionIds.remove(claimed);
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                if (isGateway)
                  // Not a typed amount: a gateway line is only ever worth
                  // what the gateway confirmed was paid.
                  Expanded(
                    flex: 3,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            (p['amount'] as double) > 0
                                ? '₹${(p['amount'] as double).toStringAsFixed(2)} collected'
                                : 'Not collected yet',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: (p['amount'] as double) > 0 ? Colors.green.shade800 : Colors.grey.shade700,
                            ),
                          ),
                        ),
                        if ((p['amount'] as double) <= 0)
                          TextButton(
                            onPressed: () => _collectGatewayPayment(p),
                            child: const Text('Collect'),
                          ),
                      ],
                    ),
                  ),
                if (!isCash && !isGateway)
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: p['controller'] as TextEditingController,
                      decoration: const InputDecoration(labelText: 'Amount', border: OutlineInputBorder(), isDense: true),
                      keyboardType: TextInputType.number,
                      onChanged: (v) {
                        setState(() {
                          p['amount'] = double.tryParse(v) ?? 0;
                        });
                      },
                    ),
                  ),
                if (isCash)
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: p['receivedController'] as TextEditingController,
                      decoration: const InputDecoration(labelText: 'Cash Received', border: OutlineInputBorder(), isDense: true),
                      keyboardType: TextInputType.number,
                      onChanged: (v) => _onCashReceivedChanged(p, v),
                    ),
                  ),
                if (_payments.length > 1)
                  IconButton(
                    icon: const Icon(Icons.remove_circle, color: Colors.red),
                    onPressed: () => _removePayment(index),
                  ),
              ],
            ),
            if (isCash) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                children: [
                  for (final amt in _quickCashAmounts())
                    ActionChip(
                      label: Text('₹${amt.toStringAsFixed(0)}'),
                      onPressed: () => _quickCash(p, amt),
                    ),
                  ActionChip(
                    label: const Text('Exact'),
                    onPressed: () => _quickCash(p, widget.total - _othersPaid(p)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Applied to bill: ₹${(p['amount'] as double).toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ],
        ),
      ),
    );
  }

  double _othersPaid(Map<String, dynamic> row) => _payments
      .where((p) => p != row)
      .fold(0.0, (sum, p) => sum + (p['amount'] as double));

  /// Common note denominations used in India, above whatever is left to pay,
  /// so the cashier can tap the note handed over instead of typing it.
  List<double> _quickCashAmounts() {
    final owed = widget.total - _othersPaid(_payments.firstWhere((p) => p['method'] == 'Cash', orElse: () => _payments.first));
    final candidates = [50.0, 100.0, 200.0, 500.0, 1000.0, 2000.0];
    return candidates.where((c) => c >= owed).take(3).toList();
  }
}