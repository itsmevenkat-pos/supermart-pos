import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

class PriceHistoryEntry extends Equatable {
  final String id;
  final String productId;
  final String field;
  final double? oldValue;
  final double newValue;
  final String? changedByUserId;
  final int changedAt;

  const PriceHistoryEntry({
    required this.id,
    required this.productId,
    required this.field,
    this.oldValue,
    required this.newValue,
    this.changedByUserId,
    this.changedAt = 0,
  });

  factory PriceHistoryEntry.create({
    required String productId,
    required String field,
    double? oldValue,
    required double newValue,
    String? changedByUserId,
  }) {
    return PriceHistoryEntry(
      id: const Uuid().v4(),
      productId: productId,
      field: field,
      oldValue: oldValue,
      newValue: newValue,
      changedByUserId: changedByUserId,
      changedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'product_id': productId,
        'field': field,
        'old_value': oldValue,
        'new_value': newValue,
        'changed_by_user_id': changedByUserId,
        'changed_at': changedAt,
      };

  factory PriceHistoryEntry.fromJson(Map<String, dynamic> map) => PriceHistoryEntry(
        id: map['id'] as String,
        productId: map['product_id'] as String,
        field: map['field'] as String,
        oldValue: (map['old_value'] as num?)?.toDouble(),
        newValue: (map['new_value'] as num).toDouble(),
        changedByUserId: map['changed_by_user_id'] as String?,
        changedAt: map['changed_at'] as int? ?? 0,
      );

  @override
  List<Object?> get props => [id, productId, field, oldValue, newValue, changedAt];
}
