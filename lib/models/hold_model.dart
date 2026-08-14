import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

class Hold extends Equatable {
  final String id;
  final String userId;
  final String data; // JSON string of cart, customer, discount, etc.
  final String? note;
  final int createdAt;

  const Hold({
    required this.id,
    required this.userId,
    required this.data,
    this.note,
    this.createdAt = 0,
  });

  factory Hold.create({
    required String userId,
    required String data,
    String? note,
  }) {
    return Hold(
      id: const Uuid().v4(),
      userId: userId,
      data: data,
      note: note,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'data': data,
        'note': note,
        'created_at': createdAt,
      };

  factory Hold.fromJson(Map<String, dynamic> map) => Hold(
        id: map['id'] as String,
        userId: map['user_id'] as String,
        data: map['data'] as String,
        note: map['note'] as String?,
        createdAt: map['created_at'] as int? ?? 0,
      );

  @override
  List<Object?> get props => [id, userId, createdAt];
}