import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

class Category extends Equatable {
  final String id;
  final String name;
  final bool allowNegativeStock;
  final bool isActive;
  final int createdAt;

  const Category({
    required this.id,
    required this.name,
    this.allowNegativeStock = false,
    this.isActive = true,
    this.createdAt = 0,
  });

  factory Category.create({
    required String name,
    bool allowNegativeStock = false,
  }) {
    return Category(
      id: const Uuid().v4(),
      name: name,
      allowNegativeStock: allowNegativeStock,
    );
  }

  Category copyWith({
    String? name,
    bool? allowNegativeStock,
    bool? isActive,
  }) {
    return Category(
      id: id,
      name: name ?? this.name,
      allowNegativeStock: allowNegativeStock ?? this.allowNegativeStock,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'allow_negative_stock': allowNegativeStock ? 1 : 0,
        'is_active': isActive ? 1 : 0,
        'created_at': createdAt,
      };

  factory Category.fromJson(Map<String, dynamic> map) => Category(
        id: map['id'] as String,
        name: map['name'] as String,
        allowNegativeStock: (map['allow_negative_stock'] as int?) == 1,
        isActive: (map['is_active'] as int?) == 1,
        createdAt: map['created_at'] as int? ?? 0,
      );

  @override
  List<Object?> get props => [id, name, allowNegativeStock];
}
