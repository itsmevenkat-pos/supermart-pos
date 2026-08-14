import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

class Salesman extends Equatable {
  final String id;
  final String? storeId;
  final String name;
  final String? phone;
  final bool isActive;
  final int createdAt;

  const Salesman({
    required this.id,
    this.storeId,
    required this.name,
    this.phone,
    this.isActive = true,
    this.createdAt = 0,
  });

  factory Salesman.create({
    String? storeId,
    required String name,
    String? phone,
  }) {
    return Salesman(
      id: const Uuid().v4(),
      storeId: storeId,
      name: name,
      phone: phone,
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
  }

  Salesman copyWith({
    String? name,
    String? phone,
    bool? isActive,
  }) {
    return Salesman(
      id: id,
      storeId: storeId,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'store_id': storeId,
        'name': name,
        'phone': phone,
        'is_active': isActive ? 1 : 0,
        'created_at': createdAt,
      };

  factory Salesman.fromJson(Map<String, dynamic> map) => Salesman(
        id: map['id'] as String,
        storeId: map['store_id'] as String?,
        name: map['name'] as String,
        phone: map['phone'] as String?,
        isActive: (map['is_active'] as int?) == 1,
        createdAt: map['created_at'] as int? ?? 0,
      );

  @override
  List<Object?> get props => [id, name, phone, isActive];
}
