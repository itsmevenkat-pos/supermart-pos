import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../core/database/database_helper.dart';
import '../models/bank_account_model.dart';
import '../models/bank_statement_model.dart';
import '../models/bank_transaction_model.dart';

/// Data access for bank reconciliation. Storage only — no CSV parsing, no
/// matching algorithm, no deciding whether a reconciliation balances. All of
/// that is `BankReconciliationService`'s job; this class does what it is told.
///
/// Same `executor` convention as `GLRepository`: every writing method takes an
/// optional [DatabaseExecutor] so a statement import (one statement row plus N
/// transaction rows) can be made atomic by the service, and the same methods
/// still work standalone.
class BankReconciliationRepository {
  BankReconciliationRepository({DatabaseHelper? dbHelper}) : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _dbHelper;

  Future<DatabaseExecutor> _db(DatabaseExecutor? executor) async => executor ?? await _dbHelper.database;

  // ----------------------------------------------------------- bank accounts

  Future<BankAccount> createAccount(BankAccount account, {DatabaseExecutor? executor}) async {
    final db = await _db(executor);
    await db.insert('bank_accounts', account.toJson());
    return account;
  }

  Future<BankAccount?> getAccount(String id, {DatabaseExecutor? executor}) async {
    final db = await _db(executor);
    final rows = await db.query('bank_accounts', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : BankAccount.fromJson(rows.first);
  }

  Future<List<BankAccount>> getAllAccounts({bool? isActive, DatabaseExecutor? executor}) async {
    final db = await _db(executor);
    final rows = await db.query(
      'bank_accounts',
      where: isActive == null ? null : 'is_active = ?',
      whereArgs: isActive == null ? null : [isActive ? 1 : 0],
      orderBy: 'bank_name ASC, account_number ASC',
    );
    return rows.map(BankAccount.fromJson).toList();
  }

  Future<void> updateAccount(BankAccount account, {DatabaseExecutor? executor}) async {
    final db = await _db(executor);
    await db.update(
      'bank_accounts',
      account.toJson()..remove('id'),
      where: 'id = ?',
      whereArgs: [account.id],
    );
  }

  /// Soft delete — a bank account with imported statements behind it must stay
  /// resolvable, so it is deactivated rather than removed.
  Future<void> deactivateAccount(String id, {DatabaseExecutor? executor}) async {
    final db = await _db(executor);
    await db.update('bank_accounts', {'is_active': 0}, where: 'id = ?', whereArgs: [id]);
  }

  /// Moves the reconciled-through watermark. Only ever called by the service,
  /// which decides whether the period actually balances first.
  Future<void> setReconciledUpTo(String accountId, DateTime? date, {DatabaseExecutor? executor}) async {
    final db = await _db(executor);
    await db.update(
      'bank_accounts',
      {'reconciled_up_to': date == null ? null : date.millisecondsSinceEpoch ~/ 1000},
      where: 'id = ?',
      whereArgs: [accountId],
    );
  }

  // -------------------------------------------------------------- statements

  Future<BankStatement> createStatement(BankStatement statement, {DatabaseExecutor? executor}) async {
    final db = await _db(executor);
    await db.insert('bank_statements', statement.toJson());
    return statement;
  }

  Future<BankStatement?> getStatement(String id, {DatabaseExecutor? executor}) async {
    final db = await _db(executor);
    final rows = await db.query('bank_statements', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : BankStatement.fromJson(rows.first);
  }

  Future<List<BankStatement>> getStatementsForAccount(String bankAccountId, {DatabaseExecutor? executor}) async {
    final db = await _db(executor);
    final rows = await db.query(
      'bank_statements',
      where: 'bank_account_id = ?',
      whereArgs: [bankAccountId],
      orderBy: 'statement_date DESC',
    );
    return rows.map(BankStatement.fromJson).toList();
  }

  /// Removes a statement and its lines together — re-importing a bad CSV is a
  /// normal thing to want, and a half-deleted statement would leave orphan
  /// transactions pointing at nothing.
  Future<void> deleteStatement(String id, {DatabaseExecutor? executor}) async {
    Future<void> work(DatabaseExecutor db) async {
      await db.delete('bank_transactions', where: 'bank_statement_id = ?', whereArgs: [id]);
      await db.delete('bank_statements', where: 'id = ?', whereArgs: [id]);
    }

    if (executor != null) return work(executor);
    final db = await _dbHelper.database;
    return db.transaction(work);
  }

  // ------------------------------------------------------------ transactions

  Future<void> insertTransactions(List<BankTransaction> transactions, {DatabaseExecutor? executor}) async {
    Future<void> work(DatabaseExecutor db) async {
      final batch = db.batch();
      for (final transaction in transactions) {
        batch.insert('bank_transactions', transaction.toJson());
      }
      await batch.commit(noResult: true);
    }

    if (executor != null) return work(executor);
    final db = await _dbHelper.database;
    return db.transaction(work);
  }

  Future<BankTransaction?> getTransaction(String id, {DatabaseExecutor? executor}) async {
    final db = await _db(executor);
    final rows = await db.query('bank_transactions', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : BankTransaction.fromJson(rows.first);
  }

  Future<List<BankTransaction>> getTransactionsForStatement(
    String bankStatementId, {
    BankMatchStatus? status,
    DatabaseExecutor? executor,
  }) async {
    final db = await _db(executor);
    final where = <String>['bank_statement_id = ?'];
    final args = <Object?>[bankStatementId];
    if (status != null) {
      where.add('match_status = ?');
      args.add(status.name);
    }
    final rows = await db.query(
      'bank_transactions',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'transaction_date ASC',
    );
    return rows.map(BankTransaction.fromJson).toList();
  }

  /// Every line across every statement of one account, optionally within a date
  /// window. This is the reconciliation view: statements are an import-batching
  /// detail, but what you reconcile is an *account* over a *period*.
  Future<List<BankTransaction>> getTransactionsForAccount(
    String bankAccountId, {
    DateTime? from,
    DateTime? to,
    BankMatchStatus? status,
    DatabaseExecutor? executor,
  }) async {
    final db = await _db(executor);
    final where = <String>[
      'bank_statement_id IN (SELECT id FROM bank_statements WHERE bank_account_id = ?)',
    ];
    final args = <Object?>[bankAccountId];
    if (from != null) {
      where.add('transaction_date >= ?');
      args.add(from.millisecondsSinceEpoch ~/ 1000);
    }
    if (to != null) {
      where.add('transaction_date <= ?');
      args.add(to.millisecondsSinceEpoch ~/ 1000);
    }
    if (status != null) {
      where.add('match_status = ?');
      args.add(status.name);
    }
    final rows = await db.query(
      'bank_transactions',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'transaction_date ASC',
    );
    return rows.map(BankTransaction.fromJson).toList();
  }

  /// The GL entry ids already claimed by a matched line on this account. The
  /// matcher subtracts these from its candidate pool so two statement lines
  /// can never both claim the same ledger entry.
  Future<Set<String>> getMatchedGlEntryIds(String bankAccountId, {DatabaseExecutor? executor}) async {
    final db = await _db(executor);
    final rows = await db.rawQuery(
      'SELECT matched_gl_entry_id FROM bank_transactions '
      'WHERE matched_gl_entry_id IS NOT NULL '
      'AND bank_statement_id IN (SELECT id FROM bank_statements WHERE bank_account_id = ?)',
      [bankAccountId],
    );
    return rows.map((r) => r['matched_gl_entry_id'] as String).toSet();
  }

  /// Sets [transactionId] to `matched` against [glEntryId]. Status and entry id
  /// move together — see `BankTransaction`'s doc for why they are never allowed
  /// to disagree.
  Future<void> markMatched(String transactionId, String glEntryId, {DatabaseExecutor? executor}) async {
    final db = await _db(executor);
    await db.update(
      'bank_transactions',
      {'matched_gl_entry_id': glEntryId, 'match_status': BankMatchStatus.matched.name},
      where: 'id = ?',
      whereArgs: [transactionId],
    );
  }

  /// Returns a line to `unmatched` and drops its GL link in the same write.
  Future<void> markUnmatched(String transactionId, {DatabaseExecutor? executor}) async {
    final db = await _db(executor);
    await db.update(
      'bank_transactions',
      {'matched_gl_entry_id': null, 'match_status': BankMatchStatus.unmatched.name},
      where: 'id = ?',
      whereArgs: [transactionId],
    );
  }

  /// Marks a line as never-to-be-matched. Also clears any GL link, since an
  /// ignored line that still points at a ledger entry would keep that entry out
  /// of the candidate pool for no reason.
  Future<void> markIgnored(String transactionId, {DatabaseExecutor? executor}) async {
    final db = await _db(executor);
    await db.update(
      'bank_transactions',
      {'matched_gl_entry_id': null, 'match_status': BankMatchStatus.ignored.name},
      where: 'id = ?',
      whereArgs: [transactionId],
    );
  }
}

final bankReconciliationRepositoryProvider = Provider<BankReconciliationRepository>((ref) {
  return BankReconciliationRepository();
});
