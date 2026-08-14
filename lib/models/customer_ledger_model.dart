import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

/// A single entry in a customer's running credit ledger. Mirrors
/// [SupplierLedger]'s shape: [amount] is signed (positive = customer owes
/// more, e.g. a credit sale; negative = customer owes less, e.g. a payment
/// received), and [balance] is the running total immediately after this
/// entry, so the ledger can be displayed transaction-wise without
/// recomputing a running sum on every read.
class CustomerLedger extends Equatable {
  final String id;
  final String customerId;
  final String referenceType;
  final String referenceId;
  final double amount;
  final double balance;
  final String? note;
  final int createdAt;

  const CustomerLedger({
    required this.id,
    required this.customerId,
    required this.referenceType,
    required this.referenceId,
    required this.amount,
    required this.balance,
    this.note,
    this.createdAt = 0,
  });

  factory CustomerLedger.create({
    required String customerId,
    required String referenceType,
    required String referenceId,
    required double amount,
    required double balance,
    String? note,
  }) {
    return CustomerLedger(
      id: const Uuid().v4(),
      customerId: customerId,
      referenceType: referenceType,
      referenceId: referenceId,
      amount: amount,
      balance: balance,
      note: note,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'customer_id': customerId,
    'reference_type': referenceType,
    'reference_id': referenceId,
    'amount': amount,
    'balance': balance,
    'note': note,
    'created_at': createdAt,
  };

  factory CustomerLedger.fromJson(Map<String, dynamic> map) => CustomerLedger(
    id: map['id'] as String,
    customerId: map['customer_id'] as String,
    referenceType: map['reference_type'] as String,
    referenceId: map['reference_id'] as String,
    amount: (map['amount'] as num).toDouble(),
    balance: (map['balance'] as num).toDouble(),
    note: map['note'] as String?,
    createdAt: map['created_at'] as int? ?? 0,
  );

  @override
  List<Object?> get props => [id, customerId, amount, balance];
}
