import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

enum CouponType { percentage, fixed }

class Coupon extends Equatable {
  final String id;
  final String code;
  final CouponType type;
  final double value;
  final double minBillAmount;
  /// null = unlimited uses.
  final int? maxUses;
  final int timesUsed;
  final int? startDate;
  final int? endDate;
  final bool isActive;
  final int createdAt;

  const Coupon({
    required this.id,
    required this.code,
    required this.type,
    required this.value,
    this.minBillAmount = 0,
    this.maxUses,
    this.timesUsed = 0,
    this.startDate,
    this.endDate,
    this.isActive = true,
    this.createdAt = 0,
  });

  factory Coupon.create({
    required String code,
    required CouponType type,
    required double value,
    double minBillAmount = 0,
    int? maxUses,
    int? startDate,
    int? endDate,
  }) {
    return Coupon(
      id: const Uuid().v4(),
      // Normalized upper-case so lookups don't depend on how the customer
      // capitalized what they typed/were given.
      code: code.trim().toUpperCase(),
      type: type,
      value: value,
      minBillAmount: minBillAmount,
      maxUses: maxUses,
      startDate: startDate,
      endDate: endDate,
    );
  }

  Coupon copyWith({
    String? code,
    CouponType? type,
    double? value,
    double? minBillAmount,
    int? maxUses,
    bool clearMaxUses = false,
    int? timesUsed,
    int? startDate,
    bool clearStartDate = false,
    int? endDate,
    bool clearEndDate = false,
    bool? isActive,
  }) {
    return Coupon(
      id: id,
      code: code ?? this.code,
      type: type ?? this.type,
      value: value ?? this.value,
      minBillAmount: minBillAmount ?? this.minBillAmount,
      maxUses: clearMaxUses ? null : (maxUses ?? this.maxUses),
      timesUsed: timesUsed ?? this.timesUsed,
      startDate: clearStartDate ? null : (startDate ?? this.startDate),
      endDate: clearEndDate ? null : (endDate ?? this.endDate),
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'code': code,
        'type': type.name,
        'value': value,
        'min_bill_amount': minBillAmount,
        'max_uses': maxUses,
        'times_used': timesUsed,
        'start_date': startDate,
        'end_date': endDate,
        'is_active': isActive ? 1 : 0,
        'created_at': createdAt,
      };

  factory Coupon.fromJson(Map<String, dynamic> map) => Coupon(
        id: map['id'] as String,
        code: map['code'] as String,
        type: CouponType.values.firstWhere(
          (e) => e.name == map['type'],
          orElse: () => CouponType.percentage,
        ),
        value: (map['value'] as num?)?.toDouble() ?? 0,
        minBillAmount: (map['min_bill_amount'] as num?)?.toDouble() ?? 0,
        maxUses: map['max_uses'] as int?,
        timesUsed: map['times_used'] as int? ?? 0,
        startDate: map['start_date'] as int?,
        endDate: map['end_date'] as int?,
        isActive: (map['is_active'] as int?) == 1,
        createdAt: map['created_at'] as int? ?? 0,
      );

  @override
  List<Object?> get props => [id, code, type, value, timesUsed, isActive];
}
