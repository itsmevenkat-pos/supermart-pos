import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

/// A recurring festival date (month + day, not a specific year) used by the
/// festival-stock-suggestion report to find last year's sales around the
/// same calendar window. See FestivalRepository.nextOccurrence.
class Festival extends Equatable {
  final String id;
  final String name;
  final int month;
  final int day;
  final String? notes;
  final bool isActive;

  const Festival({
    required this.id,
    required this.name,
    required this.month,
    required this.day,
    this.notes,
    this.isActive = true,
  });

  factory Festival.create({
    required String name,
    required int month,
    required int day,
    String? notes,
  }) {
    return Festival(id: const Uuid().v4(), name: name, month: month, day: day, notes: notes);
  }

  Festival copyWith({
    String? name,
    int? month,
    int? day,
    String? notes,
    bool? isActive,
  }) {
    return Festival(
      id: id,
      name: name ?? this.name,
      month: month ?? this.month,
      day: day ?? this.day,
      notes: notes ?? this.notes,
      isActive: isActive ?? this.isActive,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'month': month,
        'day': day,
        'notes': notes,
        'is_active': isActive ? 1 : 0,
      };

  factory Festival.fromJson(Map<String, dynamic> map) => Festival(
        id: map['id'] as String,
        name: map['name'] as String,
        month: map['month'] as int,
        day: map['day'] as int,
        notes: map['notes'] as String?,
        isActive: (map['is_active'] as int? ?? 1) == 1,
      );

  @override
  List<Object?> get props => [id, name, month, day, notes, isActive];
}
