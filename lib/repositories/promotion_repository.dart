import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/database/database_helper.dart';
import '../models/promotion_model.dart';

class PromotionRepository {
  PromotionRepository({DatabaseHelper? dbHelper}) : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _dbHelper;

  Future<List<Promotion>> getAll() async {
    final db = await _dbHelper.database;
    final result = await db.query('promotions', orderBy: 'created_at DESC');
    return result.map((e) => Promotion.fromJson(e)).toList();
  }

  Future<Promotion?> getById(String id) async {
    final db = await _dbHelper.database;
    final result = await db.query('promotions', where: 'id = ?', whereArgs: [id]);
    if (result.isEmpty) return null;
    return Promotion.fromJson(result.first);
  }

  /// Promotions eligible to apply right now: active, and (if a date range
  /// is set) within it. A null start/end means unbounded on that side —
  /// e.g. an end_date-only promotion runs until that date with no fixed
  /// start, and vice versa.
  Future<List<Promotion>> getActivePromotions() async {
    final db = await _dbHelper.database;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final result = await db.query(
      'promotions',
      where: 'is_active = 1 '
          'AND (start_date IS NULL OR start_date <= ?) '
          'AND (end_date IS NULL OR end_date >= ?)',
      whereArgs: [now, now],
      orderBy: 'created_at DESC',
    );
    return result.map((e) => Promotion.fromJson(e)).toList();
  }

  Future<void> insert(Promotion promotion) async {
    final db = await _dbHelper.database;
    await db.insert('promotions', promotion.toJson());
  }

  Future<void> update(Promotion promotion) async {
    final db = await _dbHelper.database;
    await db.update('promotions', promotion.toJson(), where: 'id = ?', whereArgs: [promotion.id]);
  }

  Future<void> setActive(String id, bool isActive) async {
    final db = await _dbHelper.database;
    await db.update('promotions', {'is_active': isActive ? 1 : 0}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> delete(String id) async {
    final db = await _dbHelper.database;
    await db.delete('promotions', where: 'id = ?', whereArgs: [id]);
  }
}

final promotionRepositoryProvider = Provider<PromotionRepository>((ref) {
  return PromotionRepository();
});
