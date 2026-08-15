import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

import 'payment_gateway_transaction_model.dart';

/// One payout from a gateway into the shop's bank account.
///
/// A gateway does not deposit each payment as it happens; it batches a day's
/// takings, subtracts its fee and transfers the remainder. This records what
/// the gateway said it paid out, so that figure can be compared against what
/// this app thinks it collected.
///
/// [settledAmount] is what actually arrives in the bank —
/// `totalAmount - feesCharged` in every case seen in practice, but it is
/// stored as the gateway reported it rather than derived, because a
/// disagreement between the two is exactly the kind of thing this table
/// exists to make visible. [feeVariance] surfaces it.
class PaymentSettlement extends Equatable {
  final String id;
  final PaymentGatewayName gateway;

  /// Seconds since epoch — the date the gateway made the payout.
  final int settlementDate;

  /// How many gateway payments the payout covers, as the gateway reported.
  final int transactionCount;

  /// Gross collected before the gateway's fee.
  final double totalAmount;

  final double feesCharged;

  /// Net actually deposited.
  final double settledAmount;

  /// The gateway's payout reference (`setl_XXX`), for matching against the
  /// bank statement line in the Task 2.1 reconciliation screen.
  final String? settlementReference;

  final int createdAt;

  const PaymentSettlement({
    required this.id,
    required this.gateway,
    required this.settlementDate,
    required this.transactionCount,
    required this.totalAmount,
    this.feesCharged = 0,
    required this.settledAmount,
    this.settlementReference,
    required this.createdAt,
  });

  factory PaymentSettlement.create({
    required PaymentGatewayName gateway,
    required DateTime settlementDate,
    required int transactionCount,
    required double totalAmount,
    double feesCharged = 0,
    required double settledAmount,
    String? settlementReference,
    DateTime? createdAt,
  }) {
    final now = createdAt ?? DateTime.now();
    return PaymentSettlement(
      id: const Uuid().v4(),
      gateway: gateway,
      settlementDate: settlementDate.millisecondsSinceEpoch ~/ 1000,
      transactionCount: transactionCount,
      totalAmount: totalAmount,
      feesCharged: feesCharged,
      settledAmount: settledAmount,
      settlementReference: settlementReference,
      createdAt: now.millisecondsSinceEpoch ~/ 1000,
    );
  }

  DateTime get settlementDateTime => DateTime.fromMillisecondsSinceEpoch(settlementDate * 1000);

  /// Gap between what the gateway said it deposited and what its own gross
  /// and fee figures imply. Non-zero means the payout does not add up and a
  /// human should look at it — it is not silently absorbed anywhere.
  double get feeVariance => settledAmount - (totalAmount - feesCharged);

  /// The gateway's fee as a percentage of gross. Useful for spotting a payout
  /// charged at an unexpected rate. Zero-gross payouts report 0 rather than
  /// dividing by zero.
  double get effectiveFeePercent => totalAmount == 0 ? 0 : (feesCharged / totalAmount) * 100;

  Map<String, dynamic> toJson() => {
        'id': id,
        'gateway': gateway.name,
        'settlement_date': settlementDate,
        'transaction_count': transactionCount,
        'total_amount': totalAmount,
        'fees_charged': feesCharged,
        'settled_amount': settledAmount,
        'settlement_reference': settlementReference,
        'created_at': createdAt,
      };

  factory PaymentSettlement.fromJson(Map<String, dynamic> map) => PaymentSettlement(
        id: map['id'] as String,
        gateway: PaymentGatewayName.values.byName(map['gateway'] as String),
        settlementDate: map['settlement_date'] as int,
        transactionCount: map['transaction_count'] as int,
        totalAmount: (map['total_amount'] as num).toDouble(),
        feesCharged: (map['fees_charged'] as num?)?.toDouble() ?? 0,
        settledAmount: (map['settled_amount'] as num).toDouble(),
        settlementReference: map['settlement_reference'] as String?,
        createdAt: map['created_at'] as int,
      );

  @override
  List<Object?> get props => [
        id,
        gateway,
        settlementDate,
        transactionCount,
        totalAmount,
        feesCharged,
        settledAmount,
        settlementReference,
        createdAt,
      ];
}
