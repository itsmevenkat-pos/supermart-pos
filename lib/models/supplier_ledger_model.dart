import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

class SupplierLedger extends Equatable {
  final String id;
  final String supplierId;
  final String referenceType;
  final String referenceId;
  final double amount;
  final double balance;
  final int createdAt;

  const SupplierLedger({
    required this.id,
    required this.supplierId,
    required this.referenceType,
    required this.referenceId,
    required this.amount,
    required this.balance,
    this.createdAt = 0,
  });

  factory SupplierLedger.create({
    required String supplierId,
    required String referenceType,
    required String referenceId,
    required double amount,
    required double balance,
  }) {
    return SupplierLedger(
      id: const Uuid().v4(),
      supplierId: supplierId,
      referenceType: referenceType,
      referenceId: referenceId,
      amount: amount,
      balance: balance,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'supplier_id': supplierId,
    'reference_type': referenceType,
    'reference_id': referenceId,
    'amount': amount,
    'balance': balance,
    'created_at': createdAt,
  };

  factory SupplierLedger.fromJson(Map<String, dynamic> map) => SupplierLedger(
    id: map['id'] as String,
    supplierId: map['supplier_id'] as String,
    referenceType: map['reference_type'] as String,
    referenceId: map['reference_id'] as String,
    amount: (map['amount'] as num).toDouble(),
    balance: (map['balance'] as num).toDouble(),
    createdAt: map['created_at'] as int? ?? 0,
  );

  @override
  List<Object?> get props => [id, supplierId, amount, balance];
}
