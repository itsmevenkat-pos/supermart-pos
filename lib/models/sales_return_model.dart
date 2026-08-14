import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

class SalesReturn extends Equatable {
  final String id;
  final String? saleId;
  final String? customerId;
  final String? storeId;
  final String? sessionId;
  final String userId;
  final String? approvedByUserId;
  final String reason;
  final String refundMethod;
  final double refundAmount;
  final bool isUntied;
  final int createdAt;

  const SalesReturn({
    required this.id,
    this.saleId,
    this.customerId,
    this.storeId,
    this.sessionId,
    required this.userId,
    this.approvedByUserId,
    required this.reason,
    required this.refundMethod,
    this.refundAmount = 0,
    this.isUntied = false,
    this.createdAt = 0,
  });

  factory SalesReturn.create({
    String? saleId,
    String? customerId,
    String? storeId,
    String? sessionId,
    required String userId,
    String? approvedByUserId,
    required String reason,
    required String refundMethod,
    double refundAmount = 0,
    bool isUntied = false,
  }) {
    return SalesReturn(
      id: const Uuid().v4(),
      saleId: saleId,
      customerId: customerId,
      storeId: storeId,
      sessionId: sessionId,
      userId: userId,
      approvedByUserId: approvedByUserId,
      reason: reason,
      refundMethod: refundMethod,
      refundAmount: refundAmount,
      isUntied: isUntied,
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'sale_id': saleId,
        'customer_id': customerId,
        'store_id': storeId,
        'session_id': sessionId,
        'user_id': userId,
        'approved_by_user_id': approvedByUserId,
        'reason': reason,
        'refund_method': refundMethod,
        'refund_amount': refundAmount,
        'is_untied': isUntied ? 1 : 0,
        'created_at': createdAt,
      };

  factory SalesReturn.fromJson(Map<String, dynamic> map) => SalesReturn(
        id: map['id'] as String,
        saleId: map['sale_id'] as String?,
        customerId: map['customer_id'] as String?,
        storeId: map['store_id'] as String?,
        sessionId: map['session_id'] as String?,
        userId: map['user_id'] as String,
        approvedByUserId: map['approved_by_user_id'] as String?,
        reason: map['reason'] as String,
        refundMethod: map['refund_method'] as String,
        refundAmount: (map['refund_amount'] as num?)?.toDouble() ?? 0,
        isUntied: (map['is_untied'] as int?) == 1,
        createdAt: map['created_at'] as int? ?? 0,
      );

  @override
  List<Object?> get props => [id, saleId, refundAmount, createdAt];
}
