import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

enum PromotionType { percentage, fixed, free_item }

class Promotion extends Equatable {
  final String id;
  final String name;
  final PromotionType type;
  final String? productId;
  final String? categoryId;
  final int minQuantity;
  final double? discountValue;
  final String? freeProductId;
  final int? startDate;
  final int? endDate;
  final bool isActive;
  final int createdAt;

  const Promotion({
    required this.id,
    required this.name,
    required this.type,
    this.productId,
    this.categoryId,
    this.minQuantity = 1,
    this.discountValue,
    this.freeProductId,
    this.startDate,
    this.endDate,
    this.isActive = true,
    this.createdAt = 0,
  });

  factory Promotion.create({
    required String name,
    required PromotionType type,
    String? productId,
    String? categoryId,
    int minQuantity = 1,
    double? discountValue,
    String? freeProductId,
    int? startDate,
    int? endDate,
  }) {
    return Promotion(
      id: const Uuid().v4(),
      name: name,
      type: type,
      productId: productId,
      categoryId: categoryId,
      minQuantity: minQuantity,
      discountValue: discountValue,
      freeProductId: freeProductId,
      startDate: startDate,
      endDate: endDate,
    );
  }

  Promotion copyWith({
    String? name,
    PromotionType? type,
    String? productId,
    String? categoryId,
    int? minQuantity,
    double? discountValue,
    String? freeProductId,
    int? startDate,
    int? endDate,
    bool? isActive,
  }) {
    return Promotion(
      id: id,
      name: name ?? this.name,
      type: type ?? this.type,
      productId: productId ?? this.productId,
      categoryId: categoryId ?? this.categoryId,
      minQuantity: minQuantity ?? this.minQuantity,
      discountValue: discountValue ?? this.discountValue,
      freeProductId: freeProductId ?? this.freeProductId,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'product_id': productId,
        'category_id': categoryId,
        'min_quantity': minQuantity,
        'discount_value': discountValue,
        'free_product_id': freeProductId,
        'start_date': startDate,
        'end_date': endDate,
        'is_active': isActive ? 1 : 0,
        'created_at': createdAt,
      };

  factory Promotion.fromJson(Map<String, dynamic> map) => Promotion(
        id: map['id'] as String,
        name: map['name'] as String,
        type: PromotionType.values.firstWhere(
          (e) => e.name == map['type'],
          orElse: () => PromotionType.percentage,
        ),
        productId: map['product_id'] as String?,
        categoryId: map['category_id'] as String?,
        minQuantity: map['min_quantity'] as int? ?? 1,
        discountValue: (map['discount_value'] as num?)?.toDouble(),
        freeProductId: map['free_product_id'] as String?,
        startDate: map['start_date'] as int?,
        endDate: map['end_date'] as int?,
        isActive: (map['is_active'] as int?) == 1,
        createdAt: map['created_at'] as int? ?? 0,
      );

  @override
  List<Object?> get props => [id, name, type, productId, categoryId];
}
