import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

/// Links a [SalesReturn] (items coming back) with a new [Sale] (replacement
/// items) processed atomically as one exchange — see [ExchangeRepository].
/// Deliberately does not duplicate item-line schema; it just records the
/// pairing plus the net settlement between the two.
class Exchange extends Equatable {
  final String id;
  final String returnId;
  final String? newSaleId;
  final String? customerId;
  /// New sale's net amount minus the return's refund amount. Positive means
  /// the customer owes more; negative means a refund is due to them.
  final double priceDifference;
  final String settlementMethod;
  final String userId;
  final String? approvedByUserId;
  final int createdAt;

  const Exchange({
    required this.id,
    required this.returnId,
    this.newSaleId,
    this.customerId,
    this.priceDifference = 0,
    required this.settlementMethod,
    required this.userId,
    this.approvedByUserId,
    this.createdAt = 0,
  });

  factory Exchange.create({
    required String returnId,
    String? newSaleId,
    String? customerId,
    double priceDifference = 0,
    required String settlementMethod,
    required String userId,
    String? approvedByUserId,
  }) {
    return Exchange(
      id: const Uuid().v4(),
      returnId: returnId,
      newSaleId: newSaleId,
      customerId: customerId,
      priceDifference: priceDifference,
      settlementMethod: settlementMethod,
      userId: userId,
      approvedByUserId: approvedByUserId,
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'return_id': returnId,
        'new_sale_id': newSaleId,
        'customer_id': customerId,
        'price_difference': priceDifference,
        'settlement_method': settlementMethod,
        'user_id': userId,
        'approved_by_user_id': approvedByUserId,
        'created_at': createdAt,
      };

  factory Exchange.fromJson(Map<String, dynamic> map) => Exchange(
        id: map['id'] as String,
        returnId: map['return_id'] as String,
        newSaleId: map['new_sale_id'] as String?,
        customerId: map['customer_id'] as String?,
        priceDifference: (map['price_difference'] as num?)?.toDouble() ?? 0,
        settlementMethod: map['settlement_method'] as String,
        userId: map['user_id'] as String,
        approvedByUserId: map['approved_by_user_id'] as String?,
        createdAt: map['created_at'] as int? ?? 0,
      );

  @override
  List<Object?> get props => [id, returnId, newSaleId, priceDifference, createdAt];
}
