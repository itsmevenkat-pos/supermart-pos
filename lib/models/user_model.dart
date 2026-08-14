import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

enum UserRole { admin, manager, cashier, accountant }

class User extends Equatable {
  final String id;
  final String username;
  final String passwordHash;
  final UserRole role;
  final String name;
  final bool mustChangePassword;
  final bool isActive;
  final int createdAt;

  const User({
    required this.id,
    required this.username,
    required this.passwordHash,
    required this.role,
    required this.name,
    this.mustChangePassword = true,
    this.isActive = true,
    this.createdAt = 0,
  });

  factory User.create({
    required String username,
    required String passwordHash,
    required UserRole role,
    required String name,
    bool mustChangePassword = true,
  }) {
    return User(
      id: const Uuid().v4(),
      username: username,
      passwordHash: passwordHash,
      role: role,
      name: name,
      mustChangePassword: mustChangePassword,
    );
  }

  User copyWith({
    String? username,
    String? passwordHash,
    UserRole? role,
    String? name,
    bool? mustChangePassword,
    bool? isActive,
  }) {
    return User(
      id: id,
      username: username ?? this.username,
      passwordHash: passwordHash ?? this.passwordHash,
      role: role ?? this.role,
      name: name ?? this.name,
      mustChangePassword: mustChangePassword ?? this.mustChangePassword,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'password_hash': passwordHash,
        'role': role.name,
        'name': name,
        'must_change_password': mustChangePassword ? 1 : 0,
        'is_active': isActive ? 1 : 0,
        'created_at': createdAt,
      };

  factory User.fromJson(Map<String, dynamic> map) => User(
        id: map['id'] as String,
        username: map['username'] as String,
        passwordHash: map['password_hash'] as String,
        role: UserRole.values.firstWhere(
          (e) => e.name == map['role'],
          orElse: () => UserRole.cashier,
        ),
        name: map['name'] as String,
        mustChangePassword: (map['must_change_password'] as int?) == 1,
        isActive: (map['is_active'] as int?) == 1,
        createdAt: map['created_at'] as int? ?? 0,
      );

  @override
  List<Object?> get props => [id, username, role, name];
}
