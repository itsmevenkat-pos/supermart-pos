import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

enum CustomerRating { gold, silver, bronze, regular }

class Customer extends Equatable {
  final String id;
  final String? storeId;
  final String phone;
  final String name;
  final String? email;
  final String? address;
  final String? locality;
  final int loyaltyPoints;
  final double totalSpent;
  final double creditLimit;
  final double outstandingBalance;
  final CustomerRating rating;
  final CustomerRating? ratingManualOverride;
  /// Unix seconds — used for birthday-wish campaigns (Campaigns screen).
  final int? dateOfBirth;
  final bool isDeleted;
  final int createdAt;
  final int? updatedAt;

  const Customer({
    required this.id,
    this.storeId,
    required this.phone,
    required this.name,
    this.email,
    this.address,
    this.locality,
    this.loyaltyPoints = 0,
    this.totalSpent = 0,
    this.creditLimit = 0,
    this.outstandingBalance = 0,
    this.rating = CustomerRating.regular,
    this.ratingManualOverride,
    this.dateOfBirth,
    this.isDeleted = false,
    this.createdAt = 0,
    this.updatedAt,
  });

  factory Customer.create({
    String? storeId,
    required String phone,
    required String name,
    String? email,
    String? address,
    String? locality,
    double creditLimit = 0,
  }) {
    return Customer(
      id: const Uuid().v4(),
      storeId: storeId,
      phone: phone,
      name: name,
      email: email,
      address: address,
      locality: locality,
      creditLimit: creditLimit,
      rating: CustomerRating.regular,
    );
  }

  Customer copyWith({
    String? phone,
    String? name,
    String? email,
    String? address,
    String? locality,
    int? loyaltyPoints,
    double? totalSpent,
    double? creditLimit,
    double? outstandingBalance,
    CustomerRating? rating,
    CustomerRating? ratingManualOverride,
    int? dateOfBirth,
    bool? isDeleted,
  }) {
    return Customer(
      id: id,
      storeId: storeId,
      phone: phone ?? this.phone,
      name: name ?? this.name,
      email: email ?? this.email,
      address: address ?? this.address,
      locality: locality ?? this.locality,
      loyaltyPoints: loyaltyPoints ?? this.loyaltyPoints,
      totalSpent: totalSpent ?? this.totalSpent,
      creditLimit: creditLimit ?? this.creditLimit,
      outstandingBalance: outstandingBalance ?? this.outstandingBalance,
      rating: rating ?? this.rating,
      ratingManualOverride: ratingManualOverride ?? this.ratingManualOverride,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      isDeleted: isDeleted ?? this.isDeleted,
      createdAt: createdAt,
      updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
  }

  CustomerRating get effectiveRating => ratingManualOverride ?? rating;

  Map<String, dynamic> toJson() => {
        'id': id,
        'store_id': storeId,
        'phone': phone,
        'name': name,
        'email': email,
        'address': address,
        'locality': locality,
        'loyalty_points': loyaltyPoints,
        'total_spent': totalSpent,
        'credit_limit': creditLimit,
        'outstanding_balance': outstandingBalance,
        'rating': rating.name,
        'rating_manual_override': ratingManualOverride?.name,
        'date_of_birth': dateOfBirth,
        'is_deleted': isDeleted ? 1 : 0,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory Customer.fromJson(Map<String, dynamic> map) => Customer(
        id: map['id'] as String,
        storeId: map['store_id'] as String?,
        phone: map['phone'] as String,
        name: map['name'] as String,
        email: map['email'] as String?,
        address: map['address'] as String?,
        locality: map['locality'] as String?,
        loyaltyPoints: map['loyalty_points'] as int? ?? 0,
        totalSpent: (map['total_spent'] as num?)?.toDouble() ?? 0,
        creditLimit: (map['credit_limit'] as num?)?.toDouble() ?? 0,
        outstandingBalance: (map['outstanding_balance'] as num?)?.toDouble() ?? 0,
        rating: CustomerRating.values.firstWhere(
          (e) => e.name == (map['rating'] ?? 'regular'),
          orElse: () => CustomerRating.regular,
        ),
        ratingManualOverride: map['rating_manual_override'] != null
            ? CustomerRating.values.firstWhere(
                (e) => e.name == map['rating_manual_override'],
                orElse: () => CustomerRating.regular,
              )
            : null,
        dateOfBirth: map['date_of_birth'] as int?,
        isDeleted: (map['is_deleted'] as int?) == 1,
        createdAt: map['created_at'] as int? ?? 0,
        updatedAt: map['updated_at'] as int?,
      );

  @override
  List<Object?> get props => [id, phone, name, loyaltyPoints, totalSpent, effectiveRating];
}
