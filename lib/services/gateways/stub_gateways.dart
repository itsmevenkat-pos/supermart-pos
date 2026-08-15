import '../../models/payment_gateway_transaction_model.dart';
import 'payment_gateway.dart';

/// PayPal and Square: the interface, none of the implementation.
///
/// These exist because [PaymentGatewayName] has three values and the schema
/// stores a gateway name, so the code needs somewhere honest to say "not
/// built". Every method throws [UnimplementedError] — deliberately, per the
/// task file: a half-written integration that silently returns a fake success
/// is far worse than one that refuses to run. Nothing in the app offers these
/// at the till, because [isConfigured] is false and the till only lists
/// configured gateways.
///
/// Implementing either means: PayPal's OAuth2 token flow and orders v2 API,
/// or Square's payments API with its own idempotency-key convention. Neither
/// maps onto Razorpay's HMAC-signature verification, which is why they are
/// separate implementations of [PaymentGateway] rather than a parameterised
/// one.
abstract class _UnimplementedGateway implements PaymentGateway {
  const _UnimplementedGateway();

  /// Never configured — this is what keeps an unbuilt gateway out of the
  /// payment dialog without any caller needing to special-case it.
  @override
  bool get isConfigured => false;

  Never _notBuilt(String operation) {
    throw UnimplementedError(
      '${name.name} is not implemented — $operation is unavailable. '
      'Only Razorpay is integrated in this app.',
    );
  }

  @override
  Future<GatewayOrder> createOrder({
    required double amount,
    required String receipt,
    String currency = 'INR',
  }) async =>
      _notBuilt('creating an order');

  @override
  Future<GatewayVerification> verifyPayment({
    required String orderId,
    required String gatewayTransactionId,
    required String signature,
  }) async =>
      _notBuilt('verifying a payment');

  @override
  Future<GatewayRefund> refund({
    required String gatewayTransactionId,
    double? amount,
  }) async =>
      _notBuilt('refunding');

  @override
  Future<GatewayVerification> getStatus(String gatewayTransactionId) async => _notBuilt('checking status');
}

class PayPalGateway extends _UnimplementedGateway {
  const PayPalGateway();

  @override
  PaymentGatewayName get name => PaymentGatewayName.paypal;
}

class SquareGateway extends _UnimplementedGateway {
  const SquareGateway();

  @override
  PaymentGatewayName get name => PaymentGatewayName.square;
}
