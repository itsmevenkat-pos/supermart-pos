import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

/// Which processor handled a payment.
///
/// Only [razorpay] is implemented — [paypal] and [square] exist so the
/// abstraction and the stored data have somewhere honest to put them, and
/// their gateway implementations throw [UnimplementedError] rather than
/// pretending. See `lib/services/gateways/`.
enum PaymentGatewayName { razorpay, paypal, square }

/// Where a gateway payment stands.
///
/// `pending` is written the moment an order is created, before the customer
/// has done anything. `success` and `failed` are terminal for the payment
/// itself; `refunded` is reachable only from `success`.
enum GatewayTransactionStatus { pending, success, failed, refunded }

/// Gateway-specific detail for one row of the `payments` table, one-to-one.
///
/// The money side of the payment lives on the `payments` row ([paymentId]) —
/// amount, method, which sale it settles. This holds only what the gateway
/// itself knows: its order id, its payment id, the status it reported, and
/// the raw response for when someone has to answer "what exactly did
/// Razorpay say".
///
/// [gatewayTransactionId] is the gateway's own payment id (`pay_XXX`) and is
/// UNIQUE in the schema. That is deliberate and load-bearing: a retried or
/// duplicated verification callback for the same gateway payment must not be
/// able to record a second success and credit the shop twice.
class PaymentGatewayTransaction extends Equatable {
  final String id;

  /// The `payments` row this is detail for.
  final String paymentId;

  final PaymentGatewayName gateway;

  /// The gateway's order id (`order_XXX`), created before the customer pays.
  final String? gatewayOrderId;

  /// The gateway's payment id (`pay_XXX`), known only once they have paid.
  final String? gatewayTransactionId;

  final GatewayTransactionStatus status;

  /// Raw JSON as the gateway returned it. Audit/debugging only — nothing
  /// reads fields back out of this, so a gateway changing its response shape
  /// cannot break the app.
  final String? gatewayResponse;

  /// Seconds since epoch.
  final int createdAt;

  /// Seconds since epoch, set when the transaction reached a terminal state.
  final int? completedAt;

  const PaymentGatewayTransaction({
    required this.id,
    required this.paymentId,
    required this.gateway,
    this.gatewayOrderId,
    this.gatewayTransactionId,
    this.status = GatewayTransactionStatus.pending,
    this.gatewayResponse,
    required this.createdAt,
    this.completedAt,
  });

  factory PaymentGatewayTransaction.create({
    required String paymentId,
    required PaymentGatewayName gateway,
    String? gatewayOrderId,
    String? gatewayTransactionId,
    GatewayTransactionStatus status = GatewayTransactionStatus.pending,
    String? gatewayResponse,
    DateTime? createdAt,
  }) {
    final now = createdAt ?? DateTime.now();
    return PaymentGatewayTransaction(
      id: const Uuid().v4(),
      paymentId: paymentId,
      gateway: gateway,
      gatewayOrderId: gatewayOrderId,
      gatewayTransactionId: gatewayTransactionId,
      status: status,
      gatewayResponse: gatewayResponse,
      createdAt: now.millisecondsSinceEpoch ~/ 1000,
    );
  }

  DateTime get createdAtDateTime => DateTime.fromMillisecondsSinceEpoch(createdAt * 1000);

  DateTime? get completedAtDateTime =>
      completedAt == null ? null : DateTime.fromMillisecondsSinceEpoch(completedAt! * 1000);

  bool get isSuccessful => status == GatewayTransactionStatus.success;

  bool get isPending => status == GatewayTransactionStatus.pending;

  bool get isRefunded => status == GatewayTransactionStatus.refunded;

  /// Reached a state it will not move on from by itself. A `success` can
  /// still become `refunded`, which is why that is not counted here — this
  /// answers "should anything still be waiting on the gateway for this".
  bool get isTerminal => status != GatewayTransactionStatus.pending;

  PaymentGatewayTransaction copyWith({
    String? gatewayOrderId,
    String? gatewayTransactionId,
    GatewayTransactionStatus? status,
    String? gatewayResponse,
    int? completedAt,
  }) {
    return PaymentGatewayTransaction(
      id: id,
      paymentId: paymentId,
      gateway: gateway,
      gatewayOrderId: gatewayOrderId ?? this.gatewayOrderId,
      gatewayTransactionId: gatewayTransactionId ?? this.gatewayTransactionId,
      status: status ?? this.status,
      gatewayResponse: gatewayResponse ?? this.gatewayResponse,
      createdAt: createdAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'payment_id': paymentId,
        'gateway': gateway.name,
        'gateway_order_id': gatewayOrderId,
        'gateway_transaction_id': gatewayTransactionId,
        'status': status.name,
        'gateway_response': gatewayResponse,
        'created_at': createdAt,
        'completed_at': completedAt,
      };

  factory PaymentGatewayTransaction.fromJson(Map<String, dynamic> map) => PaymentGatewayTransaction(
        id: map['id'] as String,
        paymentId: map['payment_id'] as String,
        gateway: PaymentGatewayName.values.byName(map['gateway'] as String),
        gatewayOrderId: map['gateway_order_id'] as String?,
        gatewayTransactionId: map['gateway_transaction_id'] as String?,
        status: GatewayTransactionStatus.values.byName(map['status'] as String? ?? 'pending'),
        gatewayResponse: map['gateway_response'] as String?,
        createdAt: map['created_at'] as int,
        completedAt: map['completed_at'] as int?,
      );

  @override
  List<Object?> get props => [
        id,
        paymentId,
        gateway,
        gatewayOrderId,
        gatewayTransactionId,
        status,
        gatewayResponse,
        createdAt,
        completedAt,
      ];
}
