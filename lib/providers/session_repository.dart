import '../core/database/database_helper.dart';
import '../models/session_model.dart';

class SessionRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<void> insert(Session session) async {
    final db = await _dbHelper.database;
    await db.insert('sessions', session.toJson());
  }

  Future<void> update(Session session) async {
    final db = await _dbHelper.database;
    await db.update('sessions', session.toJson(), where: 'id = ?', whereArgs: [session.id]);
  }

  Future<Session?> getActiveSession(String userId) async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'sessions',
      where: 'user_id = ? AND status = ?',
      whereArgs: [userId, 'open'],
    );
    if (result.isEmpty) return null;
    return Session.fromJson(result.first);
  }

  Future<List<Session>> getHistory(String userId, {int limit = 50}) async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'sessions',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return result.map((e) => Session.fromJson(e)).toList();
  }

  Future<Session?> getById(String id) async {
    final db = await _dbHelper.database;
    final result = await db.query('sessions', where: 'id = ?', whereArgs: [id]);
    if (result.isEmpty) return null;
    return Session.fromJson(result.first);
  }
}
