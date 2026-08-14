import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import '../core/database/database_helper.dart';
import '../models/stock_ledger_model.dart';

class StockLedgerRepository {
  StockLedgerRepository({DatabaseHelper? dbHelper}) : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _dbHelper;

  /// Pass [executor] as the active `txn` when calling this from inside a
  /// transaction (e.g. from `SaleRepository`/`PurchaseRepository`) — without
  /// it, this runs on a fresh top-level connection instead of the open
  /// transaction, which risks a deadlock against that same transaction.
  Future<void> insert(StockLedger ledger, {DatabaseExecutor? executor}) async {
    final db = executor ?? await _dbHelper.database;
    await db.insert('stock_ledger', ledger.toJson());
  }

  Future<List<StockLedger>> getByProduct(String productId, {int limit = 50}) async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'stock_ledger',
      where: 'product_id = ?',
      whereArgs: [productId],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return result.map((e) => StockLedger.fromJson(e)).toList();
  }
}

final stockLedgerRepositoryProvider = Provider<StockLedgerRepository>((ref) {
  return StockLedgerRepository();
});