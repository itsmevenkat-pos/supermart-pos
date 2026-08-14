import '../core/database/database_helper.dart';
import '../models/hold_model.dart';

class HoldRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<void> insert(Hold hold) async {
    final db = await _dbHelper.database;
    await db.insert('holds', hold.toJson());
  }

  Future<void> delete(String id) async {
    final db = await _dbHelper.database;
    await db.delete('holds', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Hold>> getAllByUser(String userId) async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'holds',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'created_at DESC',
    );
    return result.map((e) => Hold.fromJson(e)).toList();
  }

  Future<Hold?> getById(String id) async {
    final db = await _dbHelper.database;
    final result = await db.query('holds', where: 'id = ?', whereArgs: [id]);
    if (result.isEmpty) return null;
    return Hold.fromJson(result.first);
  }
}