import '../core/database/database_helper.dart';
import '../models/price_history_model.dart';

/// Append-only log of `products.retail_price`/`mrp`/`cost_price`/
/// `wholesale_price` edits — see MigrationV24. Written from
/// `product_form_screen.dart` on save, one row per field that actually
/// changed.
class PriceHistoryRepository {
  PriceHistoryRepository({DatabaseHelper? dbHelper}) : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _dbHelper;

  Future<void> logChange(
    String productId,
    String field,
    double? oldValue,
    double newValue,
    String? userId,
  ) async {
    final db = await _dbHelper.database;
    final entry = PriceHistoryEntry.create(
      productId: productId,
      field: field,
      oldValue: oldValue,
      newValue: newValue,
      changedByUserId: userId,
    );
    await db.insert('price_history', entry.toJson());
  }

  Future<List<PriceHistoryEntry>> getHistory(String productId) async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'price_history',
      where: 'product_id = ?',
      whereArgs: [productId],
      orderBy: 'changed_at DESC',
    );
    return result.map((e) => PriceHistoryEntry.fromJson(e)).toList();
  }
}
