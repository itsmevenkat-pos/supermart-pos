import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import '../core/database/database_helper.dart';
import '../models/supplier_ledger_model.dart';

class SupplierLedgerRepository {
  SupplierLedgerRepository({DatabaseHelper? dbHelper}) : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _dbHelper;

  /// Pass [executor] as the active `txn` when calling this from inside a
  /// transaction — see [StockLedgerRepository.insert] for why.
  Future<void> insert(SupplierLedger ledger, {DatabaseExecutor? executor}) async {
    final db = executor ?? await _dbHelper.database;
    await db.insert('supplier_ledger', ledger.toJson());
  }

  /// Pass [executor] as the active `txn` when reading the running balance
  /// from inside a transaction that's about to write a new balance row —
  /// this keeps the read consistent with any writes already made earlier
  /// in that same transaction, and avoids querying via a separate
  /// connection reference while the transaction is still open.
  Future<double> getBalance(String supplierId, {DatabaseExecutor? executor}) async {
    final db = executor ?? await _dbHelper.database;
    final result = await db.rawQuery(
      'SELECT balance FROM supplier_ledger WHERE supplier_id = ? ORDER BY created_at DESC LIMIT 1',
      [supplierId],
    );
    if (result.isEmpty) return 0.0;
    return (result.first['balance'] as num?)?.toDouble() ?? 0.0;
  }
}

final supplierLedgerRepositoryProvider = Provider<SupplierLedgerRepository>((ref) {
  return SupplierLedgerRepository();
});