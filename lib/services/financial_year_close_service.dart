import 'package:uuid/uuid.dart';

import '../core/database/database_helper.dart';

/// Locks a financial year's books. Closing is a one-way, admin-only action:
/// once a financial year is recorded in `financial_year_closures` there is
/// no "reopen" path in this service — that mirrors the real-world act of
/// closing a year's accounts.
class FinancialYearCloseService {
  FinancialYearCloseService({DatabaseHelper? dbHelper}) : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _dbHelper;

  /// Records [financialYear] (e.g. "25-26") as closed. Throws if that year
  /// is already closed — a financial year can only be closed once.
  Future<void> closeFinancialYear({
    required String financialYear,
    required String userId,
    String? notes,
  }) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      final existing = await txn.query(
        'financial_year_closures',
        where: 'financial_year = ?',
        whereArgs: [financialYear],
      );
      if (existing.isNotEmpty) {
        throw Exception('Financial year $financialYear is already closed.');
      }

      await txn.insert('financial_year_closures', {
        'id': const Uuid().v4(),
        'financial_year': financialYear,
        'closed_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'closed_by_user_id': userId,
        'notes': notes,
      });
    });
  }

  /// All closed financial years, most recently closed first.
  Future<List<Map<String, dynamic>>> getClosedFinancialYears() async {
    final db = await _dbHelper.database;
    return db.query('financial_year_closures', orderBy: 'closed_at DESC');
  }

  /// Whether [financialYear] has already been closed.
  Future<bool> isFinancialYearClosed(String financialYear) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'financial_year_closures',
      columns: ['1'],
      where: 'financial_year = ?',
      whereArgs: [financialYear],
      limit: 1,
    );
    return rows.isNotEmpty;
  }
}
