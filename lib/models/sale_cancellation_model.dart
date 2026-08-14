import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

class SaleCancellation extends Equatable {
  final String id;
  final String saleId;
  final String? customerId;
  final String reason;
  final String refundMethod;
  final double refundAmount;
  final String userId;
  final String? approvedByUserId;
  final int createdAt;

  const SaleCancellation({
    required this.id,
    required this.saleId,
    this.customerId,
    required this.reason,
    required this.refundMethod,
    this.refundAmount = 0,
    required this.userId,
    this.approvedByUserId,
    this.createdAt = 0,
  });

  factory SaleCancellation.create({
    required String saleId,
    String? customerId,
    required String reason,
    required String refundMethod,
    double refundAmount = 0,
    required String userId,
    String? approvedByUserId,
  }) {
    return SaleCancellation(
      id: const Uuid().v4(),
      saleId: saleId,
      customerId: customerId,
      reason: reason,
      refundMethod: refundMethod,
      refundAmount: refundAmount,
      userId: userId,
      approvedByUserId: approvedByUserId,
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'sale_id': saleId,
        'customer_id': customerId,
        'reason': reason,
        'refund_method': refundMethod,
        'refund_amount': refundAmount,
        'user_id': userId,
        'approved_by_user_id': approvedByUserId,
        'created_at': createdAt,
      };

  factory SaleCancellation.fromJson(Map<String, dynamic> map) => SaleCancellation(
        id: map['id'] as String,
        saleId: map['sale_id'] as String,
        customerId: map['customer_id'] as String?,
        reason: map['reason'] as String,
        refundMethod: map['refund_method'] as String,
        refundAmount: (map['refund_amount'] as num?)?.toDouble() ?? 0,
        userId: map['user_id'] as String,
        approvedByUserId: map['approved_by_user_id'] as String?,
        createdAt: map['created_at'] as int? ?? 0,
      );

  @override
  List<Object?> get props => [id, saleId, refundAmount, createdAt];
}
