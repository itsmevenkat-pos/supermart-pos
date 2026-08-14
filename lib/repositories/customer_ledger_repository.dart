import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import '../core/database/database_helper.dart';
import '../models/customer_ledger_model.dart';

class CustomerLedgerRepository {
  CustomerLedgerRepository({DatabaseHelper? dbHelper}) : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _dbHelper;

  /// Pass [executor] as the active `txn` when calling this from inside a
  /// transaction — see [SupplierLedgerRepository.insert] for why.
  Future<void> insert(CustomerLedger ledger, {DatabaseExecutor? executor}) async {
    final db = executor ?? await _dbHelper.database;
    await db.insert('customer_ledger', ledger.toJson());
  }

  /// Pass [executor] as the active `txn` when reading the running balance
  /// from inside a transaction that's about to write a new balance row —
  /// see [SupplierLedgerRepository.getBalance] for why.
  Future<double> getBalance(String customerId, {DatabaseExecutor? executor}) async {
    final db = executor ?? await _dbHelper.database;
    final result = await db.rawQuery(
      'SELECT balance FROM customer_ledger WHERE customer_id = ? ORDER BY created_at DESC LIMIT 1',
      [customerId],
    );
    if (result.isEmpty) return 0.0;
    return (result.first['balance'] as num?)?.toDouble() ?? 0.0;
  }

  /// Full transaction-wise history for a customer's detail/ledger screen,
  /// oldest first so a running balance reads top-to-bottom like a statement.
  Future<List<CustomerLedger>> getEntries(String customerId) async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'customer_ledger',
      where: 'customer_id = ?',
      whereArgs: [customerId],
      orderBy: 'created_at ASC',
    );
    return result.map((e) => CustomerLedger.fromJson(e)).toList();
  }
}

final customerLedgerRepositoryProvider = Provider<CustomerLedgerRepository>((ref) {
  return CustomerLedgerRepository();
});
