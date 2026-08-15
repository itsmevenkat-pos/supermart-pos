import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../core/database/database_helper.dart';
import '../core/database/migrations/migration_v28.dart';
import '../models/chart_of_account_model.dart';
import '../models/gl_balance_model.dart';
import '../models/gl_entry_model.dart';

/// Data access for the General Ledger. Storage only — no balancing rules, no
/// closed-period checks, no deciding which accounts a sale touches. All of
/// that is `GLService`'s job; this class does what it is told.
///
/// Every method that writes takes an optional [DatabaseExecutor] `executor`.
/// Pass the surrounding `txn` when GL writes have to succeed or fail together
/// with a sale or purchase — same pattern as
/// `StockGroupRepository.propagateDelta`. Omit it and the call runs on its own
/// connection.
class GLRepository {
  GLRepository({DatabaseHelper? dbHelper}) : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _dbHelper;

  Future<DatabaseExecutor> _db(DatabaseExecutor? executor) async => executor ?? await _dbHelper.database;

  // ---------------------------------------------------------------- accounts

  Future<ChartOfAccount> createAccount(ChartOfAccount account, {DatabaseExecutor? executor}) async {
    final db = await _db(executor);
    await db.insert('chart_of_accounts', account.toJson());
    return account;
  }

  Future<ChartOfAccount?> getAccount(String id, {DatabaseExecutor? executor}) async {
    final db = await _db(executor);
    final rows = await db.query('chart_of_accounts', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : ChartOfAccount.fromJson(rows.first);
  }

  /// Looks an account up by its chart-of-accounts code (e.g. '1000' for Cash).
  /// The sale/purchase posting paths address accounts this way — a code is
  /// stable and readable where a uuid is neither.
  Future<ChartOfAccount?> getAccountByCode(String code, {DatabaseExecutor? executor}) async {
    final db = await _db(executor);
    final rows = await db.query('chart_of_accounts', where: 'code = ?', whereArgs: [code], limit: 1);
    return rows.isEmpty ? null : ChartOfAccount.fromJson(rows.first);
  }

  Future<List<ChartOfAccount>> getAllAccounts({
    AccountType? type,
    bool? isActive,
    DatabaseExecutor? executor,
  }) async {
    final db = await _db(executor);
    final where = <String>[];
    final args = <Object?>[];
    if (type != null) {
      where.add('account_type = ?');
      args.add(type.name);
    }
    if (isActive != null) {
      where.add('is_active = ?');
      args.add(isActive ? 1 : 0);
    }
    final rows = await db.query(
      'chart_of_accounts',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'code ASC',
    );
    return rows.map(ChartOfAccount.fromJson).toList();
  }

  /// Matches [query] against either code or name, so typing "1000" and typing
  /// "cash" both find the Cash account.
  Future<List<ChartOfAccount>> searchAccounts(String query, {DatabaseExecutor? executor}) async {
    final db = await _db(executor);
    final term = '%${query.trim()}%';
    final rows = await db.query(
      'chart_of_accounts',
      where: 'code LIKE ? OR name LIKE ?',
      whereArgs: [term, term],
      orderBy: 'code ASC',
    );
    return rows.map(ChartOfAccount.fromJson).toList();
  }

  Future<void> updateAccount(ChartOfAccount account, {DatabaseExecutor? executor}) async {
    final db = await _db(executor);
    final data = account.toJson()
      ..remove('id')
      ..remove('created_at')
      ..['updated_at'] = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await db.update('chart_of_accounts', data, where: 'id = ?', whereArgs: [account.id]);
  }

  /// Accounts are deactivated, never deleted — posted `gl_entries` rows point
  /// at them, and history that loses its account name stops being auditable.
  Future<void> deactivateAccount(String id, {DatabaseExecutor? executor}) async {
    final db = await _db(executor);
    await db.update(
      'chart_of_accounts',
      {'is_active': 0, 'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Inserts the default chart of accounts if it isn't there. Idempotent, and
  /// deliberately delegated to the migration that first created those rows so
  /// there is exactly one definition of the default chart in the codebase.
  Future<void> seedDefaultAccounts({DatabaseExecutor? executor}) async {
    final db = await _db(executor);
    await MigrationV28.seedDefaultAccounts(db);
  }

  // ----------------------------------------------------------------- entries

  /// Writes one journal line exactly as given. Balancing across the lines of a
  /// compound entry is checked in `GLService` before this is ever called.
  Future<GLEntry> postEntry(GLEntry entry, {DatabaseExecutor? executor}) async {
    final db = await _db(executor);
    await db.insert('gl_entries', entry.toJson());
    return entry;
  }

  Future<GLEntry?> getEntry(String id, {DatabaseExecutor? executor}) async {
    final db = await _db(executor);
    final rows = await db.query('gl_entries', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : GLEntry.fromJson(rows.first);
  }

  /// [from] is inclusive and [to] is exclusive-of-nothing — `to` is compared
  /// with `<=`, so passing the same date for both returns that day's entries
  /// only if they were stamped at exactly that second. Pass end-of-day for
  /// [to] when filtering by calendar day.
  Future<List<GLEntry>> getEntriesByAccount(
    String accountId, {
    DateTime? from,
    DateTime? to,
    DatabaseExecutor? executor,
  }) async {
    final db = await _db(executor);
    final where = <String>['account_id = ?'];
    final args = <Object?>[accountId];
    if (from != null) {
      where.add('entry_date >= ?');
      args.add(from.millisecondsSinceEpoch ~/ 1000);
    }
    if (to != null) {
      where.add('entry_date <= ?');
      args.add(to.millisecondsSinceEpoch ~/ 1000);
    }
    final rows = await db.query(
      'gl_entries',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'entry_date ASC, created_at ASC',
    );
    return rows.map(GLEntry.fromJson).toList();
  }

  /// All lines posted for one source document — the two or more sides of a
  /// single sale, purchase or return.
  Future<List<GLEntry>> getEntriesByReference(
    String referenceType,
    String referenceId, {
    DatabaseExecutor? executor,
  }) async {
    final db = await _db(executor);
    final rows = await db.query(
      'gl_entries',
      where: 'reference_type = ? AND reference_id = ?',
      whereArgs: [referenceType, referenceId],
      orderBy: 'created_at ASC',
    );
    return rows.map(GLEntry.fromJson).toList();
  }

  Future<List<GLEntry>> getEntriesByFinancialYear(String financialYear, {DatabaseExecutor? executor}) async {
    final db = await _db(executor);
    final rows = await db.query(
      'gl_entries',
      where: 'financial_year = ?',
      whereArgs: [financialYear],
      orderBy: 'entry_date ASC, created_at ASC',
    );
    return rows.map(GLEntry.fromJson).toList();
  }

  // ---------------------------------------------------------------- balances

  Future<GLBalance?> getAccountBalance(
    String accountId,
    String financialYear, {
    DatabaseExecutor? executor,
  }) async {
    final db = await _db(executor);
    final rows = await db.query(
      'gl_balances',
      where: 'account_id = ? AND financial_year = ?',
      whereArgs: [accountId, financialYear],
      limit: 1,
    );
    return rows.isEmpty ? null : GLBalance.fromJson(rows.first);
  }

  Future<List<GLBalance>> getAllBalances(String financialYear, {DatabaseExecutor? executor}) async {
    final db = await _db(executor);
    final rows = await db.query(
      'gl_balances',
      where: 'financial_year = ?',
      whereArgs: [financialYear],
    );
    return rows.map(GLBalance.fromJson).toList();
  }

  /// Re-sums `gl_entries` for one account and year and upserts the cached row.
  /// This is the only place `gl_balances` is written — the cache is always a
  /// pure function of the journal, so a wrong balance is always fixable by
  /// calling this again rather than by editing the number.
  ///
  /// The existing row is updated in place (rather than deleted and reinserted)
  /// so its id stays stable for anything holding a reference to it.
  Future<GLBalance> recalculateBalance(
    String accountId,
    String financialYear, {
    DatabaseExecutor? executor,
  }) async {
    final db = await _db(executor);

    final account = await getAccount(accountId, executor: db);
    if (account == null) {
      throw ArgumentError('Cannot recalculate a balance for unknown account: $accountId');
    }

    final sums = await db.rawQuery(
      'SELECT COALESCE(SUM(debit), 0) AS total_debit, COALESCE(SUM(credit), 0) AS total_credit '
      'FROM gl_entries WHERE account_id = ? AND financial_year = ?',
      [accountId, financialYear],
    );
    final totalDebit = (sums.first['total_debit'] as num).toDouble();
    final totalCredit = (sums.first['total_credit'] as num).toDouble();

    final existing = await getAccountBalance(accountId, financialYear, executor: db);
    final balance = GLBalance.create(
      accountId: accountId,
      financialYear: financialYear,
      type: account.type,
      totalDebit: totalDebit,
      totalCredit: totalCredit,
    );

    if (existing == null) {
      await db.insert('gl_balances', balance.toJson());
      return balance;
    }

    final updated = GLBalance(
      id: existing.id,
      accountId: accountId,
      financialYear: financialYear,
      totalDebit: totalDebit,
      totalCredit: totalCredit,
      balance: balance.balance,
      lastUpdated: balance.lastUpdated,
    );
    await db.update(
      'gl_balances',
      updated.toJson()..remove('id'),
      where: 'id = ?',
      whereArgs: [existing.id],
    );
    return updated;
  }
}

final glRepositoryProvider = Provider<GLRepository>((ref) {
  return GLRepository();
});
