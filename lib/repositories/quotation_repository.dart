import '../core/database/database_helper.dart';
import '../models/quotation_model.dart';
import '../models/quotation_item_model.dart';

class QuotationRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<void> insert(Quotation quotation) async {
    final db = await _dbHelper.database;
    await db.insert('quotations', quotation.toJson());
    await _dbHelper.queueSync('quotations', quotation.id, 'INSERT', quotation.toJson());
  }

  /// Persists the quotation's line items — without this, a quotation is
  /// just a lump-sum total with nothing to reload when converting it to a
  /// bill later.
  Future<void> insertItems(String quotationId, List<QuotationItem> items) async {
    final db = await _dbHelper.database;
    final batch = db.batch();
    for (final item in items) {
      batch.insert('quotation_items', (item.toJson()..['quotation_id'] = quotationId));
    }
    await batch.commit(noResult: true);
  }

  Future<List<QuotationItem>> getItems(String quotationId) async {
    final db = await _dbHelper.database;
    final result = await db.query('quotation_items', where: 'quotation_id = ?', whereArgs: [quotationId]);
    return result.map((e) => QuotationItem.fromJson(e)).toList();
  }

  Future<void> update(Quotation quotation) async {
    final db = await _dbHelper.database;
    await db.update('quotations', quotation.toJson(), where: 'id = ?', whereArgs: [quotation.id]);
    await _dbHelper.queueSync('quotations', quotation.id, 'UPDATE', quotation.toJson());
  }

  Future<List<Quotation>> getAll({String? status}) async {
    final db = await _dbHelper.database;
    // sqflite's `where` param wants a bare condition ("status = ?"), not a
    // full "WHERE ..." clause — sqflite builds the WHERE keyword itself.
    // The old "WHERE status = ?" produced invalid SQL ("...WHERE WHERE
    // status = ?") whenever a status filter was actually passed.
    final where = status != null ? 'status = ?' : '';
    final args = status != null ? [status] : <Object?>[];
    final result = await db.query(
      'quotations',
      where: where.isNotEmpty ? where : null,
      whereArgs: args.isNotEmpty ? args : null,
      orderBy: 'created_at DESC',
    );
    return result.map((e) => Quotation.fromJson(e)).toList();
  }

  Future<Quotation?> getById(String id) async {
    final db = await _dbHelper.database;
    final result = await db.query('quotations', where: 'id = ?', whereArgs: [id]);
    if (result.isEmpty) return null;
    return Quotation.fromJson(result.first);
  }

  Future<void> delete(String id) async {
    final db = await _dbHelper.database;
    await db.delete('quotations', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateStatus(String id, String status) async {
    final db = await _dbHelper.database;
    await db.update(
      'quotations',
      {'status': status, 'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}