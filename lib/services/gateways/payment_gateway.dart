import '../../models/payment_gateway_transaction_model.dart';

/// Anything that went wrong talking to a gateway.
///
/// Deliberately one exception type with a [gateway] and an optional
/// [gatewayCode] rather than a hierarchy per processor: callers care whether
/// the payment happened, not which of Razorpay's error codes they got, and
/// the raw response is preserved for whoever does care.
class PaymentGatewayException implements Exception {
  final PaymentGatewayName gateway;
  final String message;

  /// The gateway's own error code where it gave one (`BAD_REQUEST_ERROR`).
  final String? gatewayCode;

  /// HTTP status, when the failure was an HTTP one.
  final int? statusCode;

  const PaymentGatewayException(
    this.gateway,
    this.message, {
    this.gatewayCode,
    this.statusCode,
  });

  @override
  String toString() {
    final parts = <String>[
      '${gateway.name}: $message',
      if (gatewayCode != null) 'code=$gatewayCode',
      if (statusCode != null) 'http=$statusCode',
    ];
    return 'PaymentGatewayException(${parts.join(', ')})';
  }
}

/// The gateway is switched on but has no usable credentials.
///
/// Separate from [PaymentGatewayException] because it is a configuration
/// mistake a manager can fix in Settings, not a payment failure — the UI
/// says so differently.
class GatewayNotConfigured implements Exception {
  final PaymentGatewayName gateway;
  final String message;

  const GatewayNotConfigured(this.gateway, this.message);

  @override
  String toString() => 'GatewayNotConfigured(${gateway.name}: $message)';
}

/// An order created at the gateway, ready for the customer to pay against.
class GatewayOrder {
  /// The gateway's order id (`order_XXX`).
  final String orderId;

  /// Echoed back in the shop's own currency unit (rupees), not the gateway's
  /// minor unit — conversion to paise is the gateway implementation's
  /// business and does not leak past this boundary.
  final double amount;

  final String currency;

  /// Raw JSON as returned, stored on the transaction row for audit.
  final String rawResponse;

  const GatewayOrder({
    required this.orderId,
    required this.amount,
    required this.currency,
    required this.rawResponse,
  });
}

/// The outcome of checking whether a payment really happened.
///
/// [isValid] false is a *verification* failure — the signature did not match,
/// meaning the callback cannot be trusted — which is different from a payment
/// the gateway says genuinely failed ([status] of
/// [GatewayTransactionStatus.failed]). Both stop the sale being settled; only
/// the first is a security event.
class GatewayVerification {
  final bool isValid;

  /// Whether the *signature* checked out, independently of what the payment
  /// then turned out to be.
  ///
  /// A separate field rather than something inferred from [failureReason],
  /// because the two failures need different handling and matching on prose
  /// would break the moment the wording changed: a false here means someone
  /// sent a confirmation they could not have signed, which is a security
  /// event, and the caller must not stamp the claimed payment id onto
  /// anything.
  final bool signatureValid;

  final GatewayTransactionStatus status;

  /// The gateway's payment id (`pay_XXX`).
  final String? gatewayTransactionId;

  /// Amount the gateway says was paid, in rupees. Null when the gateway was
  /// not asked (pure local signature check).
  final double? amount;

  final String rawResponse;

  /// Why verification failed, for the audit trail and the cashier's message.
  final String? failureReason;

  const GatewayVerification({
    required this.isValid,
    this.signatureValid = true,
    required this.status,
    this.gatewayTransactionId,
    this.amount,
    required this.rawResponse,
    this.failureReason,
  });
}

/// The outcome of a refund request.
class GatewayRefund {
  /// The gateway's refund id (`rfnd_XXX`).
  final String refundId;

  /// Amount refunded, in rupees.
  final double amount;

  final String rawResponse;

  const GatewayRefund({
    required this.refundId,
    required this.amount,
    required this.rawResponse,
  });
}

/// What every payment processor has to be able to do for this app.
///
/// The four operations are the whole surface the rest of the app sees; a
/// gateway's HTTP details, auth scheme and minor-currency-unit quirks stay
/// behind it. [PaymentGatewayService] talks only to this interface, which is
/// what lets the tests run the full sale-to-GL flow against a fake with no
/// network and no keys.
abstract class PaymentGateway {
  PaymentGatewayName get name;

  /// Whether this gateway has credentials and is switched on. A gateway that
  /// is not configured is never offered at the till.
  bool get isConfigured;

  /// Registers an intent to collect [amount] rupees, returning the gateway's
  /// order the customer will pay against.
  ///
  /// [receipt] is the shop's own reference (the sale id), echoed back by the
  /// gateway so a payment can be traced to a bill from the gateway's own
  /// dashboard.
  Future<GatewayOrder> createOrder({
    required double amount,
    required String receipt,
    String currency = 'INR',
  });

  /// Checks that a payment the customer claims to have made is real.
  ///
  /// Implementations verify the gateway's signature over
  /// (order id, payment id) using the shared secret. A caller must treat a
  /// non-[GatewayVerification.isValid] result as "no money arrived",
  /// regardless of what the client-side callback claimed.
  Future<GatewayVerification> verifyPayment({
    required String orderId,
    required String gatewayTransactionId,
    required String signature,
  });

  /// Returns [amount] rupees (or the full payment when [amount] is null).
  Future<GatewayRefund> refund({
    required String gatewayTransactionId,
    double? amount,
  });

  /// Asks the gateway what it currently thinks the payment's state is —
  /// the recovery path when a callback never arrived and a transaction is
  /// stuck `pending`.
  Future<GatewayVerification> getStatus(String gatewayTransactionId);
}
