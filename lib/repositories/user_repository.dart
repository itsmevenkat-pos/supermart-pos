import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/database/database_helper.dart';
import '../core/security/password_hasher.dart';
import '../models/user_model.dart';

class UserRepository {
  UserRepository({DatabaseHelper? dbHelper}) : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _dbHelper;

  Future<List<User>> getAll() async {
    final db = await _dbHelper.database;
    final result = await db.query('users', orderBy: 'name ASC');
    return result.map((e) => User.fromJson(e)).toList();
  }

  Future<User?> getById(String id) async {
    final db = await _dbHelper.database;
    final result = await db.query('users', where: 'id = ?', whereArgs: [id]);
    if (result.isEmpty) return null;
    return User.fromJson(result.first);
  }

  Future<User?> getByUsername(String username) async {
    final db = await _dbHelper.database;
    final result = await db.query('users', where: 'username = ?', whereArgs: [username]);
    if (result.isEmpty) return null;
    return User.fromJson(result.first);
  }

  Future<void> insert(User user) async {
    final db = await _dbHelper.database;
    await db.insert('users', user.toJson());
    await _dbHelper.queueSync('users', user.id, 'INSERT', user.toJson());
  }

  Future<void> update(User user) async {
    final db = await _dbHelper.database;
    await db.update('users', user.toJson(), where: 'id = ?', whereArgs: [user.id]);
    await _dbHelper.queueSync('users', user.id, 'UPDATE', user.toJson());
  }

  Future<void> delete(String id) async {
    final db = await _dbHelper.database;
    await db.update('users', {'is_active': 0}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> ensureAdminExists() async {
    try {
      final db = await _dbHelper.database;
      final result = await db.query('users', where: 'username = ?', whereArgs: ['admin']);
      if (result.isEmpty) {
        await db.insert('users', {
          'id': 'user_admin',
          'username': 'admin',
          // Hashed, not plaintext — default admin password is still "admin",
          // but must_change_password forces a change on first login.
          'password_hash': PasswordHasher.hash('admin'),
          'role': 'admin',
          'name': 'Super Admin',
          'must_change_password': 1,
          'is_active': 1,
          'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        });
      }
    } catch (e) {
      print('ensureAdminExists error: $e');
    }
  }
}

final userRepositoryProvider = Provider<UserRepository>((ref) {
  return UserRepository();
});