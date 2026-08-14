import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import '../core/database/database_helper.dart';
import '../models/product_batch_model.dart';

class ProductBatchRepository {
  ProductBatchRepository({DatabaseHelper? dbHelper}) : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _dbHelper;

  /// Pass [executor] as the active `txn` when calling this from inside a
  /// transaction (e.g. from `PurchaseRepository`) — see the same note on
  /// `StockLedgerRepository.insert`.
  Future<void> insert(ProductBatch batch, {DatabaseExecutor? executor}) async {
    final db = executor ?? await _dbHelper.database;
    await db.insert('product_batches', batch.toJson());
  }

  /// Soonest-to-expire first (nulls last), then most recent purchase first
  /// — the order a cashier or manager would actually want to review batches
  /// in.
  Future<List<ProductBatch>> getByProduct(String productId) async {
    final db = await _dbHelper.database;
    final result = await db.rawQuery(
      '''
      SELECT * FROM product_batches
      WHERE product_id = ?
      ORDER BY expiry_date IS NULL, expiry_date ASC, created_at DESC
      ''',
      [productId],
    );
    return result.map((e) => ProductBatch.fromJson(e)).toList();
  }
}

final productBatchRepositoryProvider = Provider<ProductBatchRepository>((ref) {
  return ProductBatchRepository();
});
