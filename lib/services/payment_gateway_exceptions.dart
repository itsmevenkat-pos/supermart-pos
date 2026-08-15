/// Failures specific to gateway payment handling, mirroring
/// `gl_exceptions.dart` and `bank_reconciliation_exceptions.dart` so callers
/// can catch a payment problem distinctly from a ledger or bank one.
///
/// Transport and gateway-reported failures are *not* here — those are
/// `PaymentGatewayException` in `gateways/payment_gateway.dart`, because they
/// belong to the gateway boundary rather than to this app's own rules.
class PaymentGatewayServiceException implements Exception {
  PaymentGatewayServiceException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// The gateway named is not implemented, or is implemented but switched off /
/// missing credentials. Distinguished from a payment failure because the fix
/// is in Settings, not at the till.
class GatewayUnavailable extends PaymentGatewayServiceException {
  GatewayUnavailable(super.message);
}

/// No `payment_gateway_transactions` row with the given id or order id.
class GatewayTransactionNotFound extends PaymentGatewayServiceException {
  GatewayTransactionNotFound(super.message);
}

/// This gateway payment id has already been recorded against a transaction.
///
/// Thrown rather than quietly ignored: a duplicate confirmation usually means
/// a retried callback (harmless, and the caller can treat this as success) but
/// can equally mean a replayed one (not harmless). The service refuses either
/// way and leaves the original record untouched, so the shop is never credited
/// twice for the same payment.
class DuplicateGatewayPayment extends PaymentGatewayServiceException {
  DuplicateGatewayPayment(super.message, {this.existingTransactionId});

  /// The transaction that already holds this gateway payment id, so a caller
  /// handling a benign retry can look up what was recorded the first time.
  final String? existingTransactionId;
}

/// The gateway's signature did not verify, or the gateway reports the payment
/// as anything other than captured. Either way no money is confirmed and the
/// sale must not be settled.
class PaymentVerificationFailed extends PaymentGatewayServiceException {
  PaymentVerificationFailed(super.message, {this.signatureValid = true});

  /// False when the *signature* failed, as opposed to a genuinely failed
  /// payment with a good signature. A false here is a security event worth
  /// logging differently — someone sent a confirmation they could not have
  /// signed.
  final bool signatureValid;
}

/// A transaction is not in a state the requested operation can act on — an
/// attempt to refund something that never succeeded, or to verify one that is
/// already terminal.
class InvalidTransactionState extends PaymentGatewayServiceException {
  InvalidTransactionState(super.message);
}
