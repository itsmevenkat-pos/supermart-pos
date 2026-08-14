import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

class Supplier extends Equatable {
  final String id;
  final String? storeId;
  final String name;
  final String? phone;
  final String? email;
  final String? address;
  final double openingBalance;
  final bool isDeleted;
  final int createdAt;

  const Supplier({
    required this.id,
    this.storeId,
    required this.name,
    this.phone,
    this.email,
    this.address,
    this.openingBalance = 0,
    this.isDeleted = false,
    this.createdAt = 0,
  });

  factory Supplier.create({
    String? storeId,
    required String name,
    String? phone,
    String? email,
    String? address,
    double openingBalance = 0,
  }) {
    return Supplier(
      id: const Uuid().v4(),
      storeId: storeId,
      name: name,
      phone: phone,
      email: email,
      address: address,
      openingBalance: openingBalance,
    );
  }

  Supplier copyWith({
    String? name,
    String? phone,
    String? email,
    String? address,
    double? openingBalance,
    bool? isDeleted,
  }) {
    return Supplier(
      id: id,
      storeId: storeId,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      address: address ?? this.address,
      openingBalance: openingBalance ?? this.openingBalance,
      isDeleted: isDeleted ?? this.isDeleted,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'store_id': storeId,
        'name': name,
        'phone': phone,
        'email': email,
        'address': address,
        'opening_balance': openingBalance,
        'is_deleted': isDeleted ? 1 : 0,
        'created_at': createdAt,
      };

  factory Supplier.fromJson(Map<String, dynamic> map) => Supplier(
        id: map['id'] as String,
        storeId: map['store_id'] as String?,
        name: map['name'] as String,
        phone: map['phone'] as String?,
        email: map['email'] as String?,
        address: map['address'] as String?,
        openingBalance: (map['opening_balance'] as num?)?.toDouble() ?? 0,
        isDeleted: (map['is_deleted'] as int?) == 1,
        createdAt: map['created_at'] as int? ?? 0,
      );

  @override
  List<Object?> get props => [id, name, phone, openingBalance];
}
