import 'dart:convert';
import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

class Session extends Equatable {
  final String id;
  final String userId;
  final int openingTime;
  final int? closingTime;
  final double openingCash;
  final Map<String, int>? openingDenominations;
  final double? closingCash;
  final Map<String, int>? closingDenominations;
  final double? expectedCash;
  final double? difference;
  final String status;
  final String? notes;
  final int createdAt;

  const Session({
    required this.id,
    required this.userId,
    required this.openingTime,
    this.closingTime,
    this.openingCash = 0,
    this.openingDenominations,
    this.closingCash,
    this.closingDenominations,
    this.expectedCash,
    this.difference,
    this.status = 'open',
    this.notes,
    this.createdAt = 0,
  });

  factory Session.open({
    required String userId,
    double openingCash = 0,
    Map<String, int>? openingDenominations,
    String? notes,
  }) {
    return Session(
      id: const Uuid().v4(),
      userId: userId,
      openingTime: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      openingCash: openingCash,
      openingDenominations: openingDenominations,
      notes: notes,
      status: 'open',
    );
  }

  Session copyWith({
    int? closingTime,
    double? closingCash,
    Map<String, int>? closingDenominations,
    double? expectedCash,
    double? difference,
    String? status,
    String? notes,
  }) {
    return Session(
      id: id,
      userId: userId,
      openingTime: openingTime,
      closingTime: closingTime ?? this.closingTime,
      openingCash: openingCash,
      openingDenominations: openingDenominations,
      closingCash: closingCash ?? this.closingCash,
      closingDenominations: closingDenominations ?? this.closingDenominations,
      expectedCash: expectedCash ?? this.expectedCash,
      difference: difference ?? this.difference,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'opening_time': openingTime,
        'closing_time': closingTime,
        'opening_cash': openingCash,
        'opening_denominations': openingDenominations != null
            ? jsonEncode(openingDenominations)
            : null,
        'closing_cash': closingCash,
        'closing_denominations': closingDenominations != null
            ? jsonEncode(closingDenominations)
            : null,
        'expected_cash': expectedCash,
        'difference': difference,
        'status': status,
        'notes': notes,
        'created_at': createdAt,
      };

  factory Session.fromJson(Map<String, dynamic> map) => Session(
        id: map['id'] as String,
        userId: map['user_id'] as String,
        openingTime: map['opening_time'] as int,
        closingTime: map['closing_time'] as int?,
        openingCash: (map['opening_cash'] as num?)?.toDouble() ?? 0,
        openingDenominations: map['opening_denominations'] != null
            ? Map<String, int>.from(jsonDecode(map['opening_denominations']))
            : null,
        closingCash: (map['closing_cash'] as num?)?.toDouble(),
        closingDenominations: map['closing_denominations'] != null
            ? Map<String, int>.from(jsonDecode(map['closing_denominations']))
            : null,
        expectedCash: (map['expected_cash'] as num?)?.toDouble(),
        difference: (map['difference'] as num?)?.toDouble(),
        status: map['status'] as String? ?? 'open',
        notes: map['notes'] as String?,
        createdAt: map['created_at'] as int? ?? 0,
      );

  @override
  List<Object?> get props => [id, userId, status, openingTime];
}
