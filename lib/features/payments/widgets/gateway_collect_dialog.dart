import 'package:flutter/material.dart';

import '../../../models/payment_gateway_transaction_model.dart';
import '../../../services/gateways/payment_gateway.dart';
import '../../../services/payment_gateway_exceptions.dart';
import '../../../services/payment_gateway_service.dart';

/// The result of a completed gateway collection, handed back to whoever
/// opened the dialog.
class GatewayCollectResult {
  const GatewayCollectResult({
    required this.transactionId,
    required this.gateway,
    required this.amount,
  });

  /// The `payment_gateway_transactions` row id, so the caller can link it to
  /// a sale once the sale exists.
  final String transactionId;
  final PaymentGatewayName gateway;
  final double amount;
}

/// Collects one payment through a gateway: create the order, wait for the
/// customer to pay, then prove it.
///
/// **Why the cashier types the payment id and signature by hand.** A phone
/// app would use Razorpay's checkout SDK and receive these in a callback.
/// This is a desktop/Windows POS with no such SDK available, so the customer
/// pays against the order (UPI link, hosted checkout on their own phone) and
/// the till confirms it with what the gateway returns. Nothing here trusts
/// what is typed: it goes straight to
/// [PaymentGatewayService.verifyAndRecordPayment], which checks the signature
/// against the shop's own secret and then asks the gateway what really
/// happened. A wrong or invented value fails verification and records a
/// failed attempt — it cannot settle a sale.
///
/// The "Check with gateway" button is the recovery path for when the customer
/// has paid but the cashier has no signature to hand: it asks the gateway
/// directly. It deliberately cannot settle the payment either — see
/// [PaymentGatewayService.refreshStatus].
class GatewayCollectDialog extends StatefulWidget {
  const GatewayCollectDialog({
    super.key,
    required this.amount,
    required this.gateway,
    this.service,
    this.saleId,
  });

  final double amount;
  final PaymentGatewayName gateway;

  /// Injectable so this dialog can be driven in a test without a live key.
  final PaymentGatewayService? service;

  /// Usually null at the till — the sale does not exist yet. See
  /// [PaymentGatewayService.createOrder].
  final String? saleId;

  @override
  State<GatewayCollectDialog> createState() => _GatewayCollectDialogState();
}

class _GatewayCollectDialogState extends State<GatewayCollectDialog> {
  late final PaymentGatewayService _service = widget.service ?? PaymentGatewayService();

  final _paymentIdController = TextEditingController();
  final _signatureController = TextEditingController();

  PaymentGatewayTransaction? _transaction;
  bool _busy = false;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _paymentIdController.dispose();
    _signatureController.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await action();
    } on PaymentVerificationFailed catch (e) {
      setState(() {
        _error = e.signatureValid
            ? e.message
            : 'Signature check failed — this confirmation cannot be trusted. ${e.message}';
      });
    } on DuplicateGatewayPayment catch (e) {
      setState(() => _error = '${e.message} It has not been recorded a second time.');
    } on GatewayNotConfigured catch (e) {
      setState(() => _error = e.message);
    } on GatewayUnavailable catch (e) {
      setState(() => _error = e.message);
    } on PaymentGatewayException catch (e) {
      setState(() => _error = e.message);
    } on PaymentGatewayServiceException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createOrder() => _run(() async {
        final created = await _service.createOrder(
          gateway: widget.gateway,
          amount: widget.amount,
          saleId: widget.saleId,
        );
        setState(() {
          _transaction = created;
          _info = 'Order created. Ask the customer to pay, then enter the payment reference below.';
        });
      });

  Future<void> _verify() => _run(() async {
        final transaction = _transaction!;
        final confirmed = await _service.verifyAndRecordPayment(
          transactionId: transaction.id,
          gatewayTransactionId: _paymentIdController.text.trim(),
          signature: _signatureController.text.trim(),
        );
        if (!mounted) return;
        Navigator.pop(
          context,
          GatewayCollectResult(
            transactionId: confirmed.id,
            gateway: confirmed.gateway,
            amount: widget.amount,
          ),
        );
      });

  Future<void> _checkStatus() => _run(() async {
        final status = await _service.refreshStatus(_transaction!.id);
        setState(() {
          _info = switch (status) {
            GatewayTransactionStatus.success =>
              'The gateway reports this payment as successful. Enter its payment id and signature above to record it.',
            GatewayTransactionStatus.failed => 'The gateway reports this payment as failed.',
            GatewayTransactionStatus.refunded => 'The gateway reports this payment as already refunded.',
            GatewayTransactionStatus.pending => 'The gateway has not received a payment for this order yet.',
          };
        });
      });

  @override
  Widget build(BuildContext context) {
    final transaction = _transaction;

    return AlertDialog(
      title: Text('Collect ₹${widget.amount.toStringAsFixed(2)} via ${widget.gateway.name}'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (transaction == null) ...[
              const Text(
                'This creates an order with the gateway for the amount above. '
                'No money moves until the customer pays and the payment is verified.',
              ),
            ] else ...[
              SelectableText(
                'Order: ${transaction.gatewayOrderId ?? "—"}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _paymentIdController,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: 'Gateway payment id',
                  hintText: 'pay_XXXXXXXXXXXX',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                // Rebuilds so "Verify & record" enables only once both
                // fields have something in them.
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _signatureController,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: 'Signature',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              Text(
                'The signature is checked against this shop\'s own gateway secret before '
                'anything is recorded. A payment that does not verify cannot complete the bill.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (_info != null) ...[
              const SizedBox(height: 12),
              Text(_info!, style: TextStyle(color: Colors.blue.shade800)),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            if (_busy) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        if (transaction != null)
          TextButton(
            onPressed: _busy ? null : _checkStatus,
            child: const Text('Check with gateway'),
          ),
        ElevatedButton(
          onPressed: _busy
              ? null
              : transaction == null
                  ? _createOrder
                  : (_paymentIdController.text.trim().isEmpty || _signatureController.text.trim().isEmpty
                      ? null
                      : _verify),
          child: Text(transaction == null ? 'Create order' : 'Verify & record'),
        ),
      ],
    );
  }
}
