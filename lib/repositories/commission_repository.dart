import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../core/database/database_helper.dart';
import '../models/commission_rule_model.dart';
import '../models/commission_settlement_model.dart';

/// Data access for commission rules and settlements.
///
/// Storage only. Which rule applies to a period, how a tiered rate is
/// applied, and whether a settlement may be raised at all are all decided by
/// `CommissionService`.
class CommissionRepository {
  CommissionRepository({DatabaseHelper? dbHelper}) : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _dbHelper;

  Future<DatabaseExecutor> _db(DatabaseExecutor? executor) async => executor ?? await _dbHelper.database;

  // ------------------------------------------------------------------ rules

  Future<void> insertRule(CommissionRule rule, {DatabaseExecutor? executor}) async {
    final db = await _db(executor);
    await db.insert('commission_rules', rule.toJson());
    await _dbHelper.queueSync('commission_rules', rule.id, 'INSERT', rule.toJson(), executor: executor);
  }

  Future<void> updateRule(CommissionRule rule, {DatabaseExecutor? executor}) async {
    final db = await _db(executor);
    await db.update('commission_rules', rule.toJson(), where: 'id = ?', whereArgs: [rule.id]);
    await _dbHelper.queueSync('commission_rules', rule.id, 'UPDATE', rule.toJson(), executor: executor);
  }

  Future<CommissionRule?> getRuleById(String id, {DatabaseExecutor? executor}) async {
    final db = await _db(executor);
    final rows = await db.query('commission_rules', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return CommissionRule.fromJson(rows.first);
  }

  /// A salesman's rules, newest agreement first. [activeOnly] filters on the
  /// `is_active` flag, not on dates — date filtering is the service's job
  /// because "which rule covers this period" has an answer the schema can't
  /// express.
  Future<List<CommissionRule>> getRulesForSalesman(
    String salesmanId, {
    bool activeOnly = false,
    DatabaseExecutor? executor,
  }) async {
    final db = await _db(executor);
    final rows = await db.query(
      'commission_rules',
      where: activeOnly ? 'salesman_id = ? AND is_active = 1' : 'salesman_id = ?',
      whereArgs: [salesmanId],
      orderBy: 'effective_from DESC, id DESC',
    );
    return rows.map(CommissionRule.fromJson).toList();
  }

  /// Retires a rule without deleting it. Deleting would orphan the reason a
  /// past settlement paid what it did, so rules are only ever deactivated.
  Future<void> deactivateRule(String id, {DatabaseExecutor? executor}) async {
    final db = await _db(executor);
    await db.update('commission_rules', {'is_active': 0}, where: 'id = ?', whereArgs: [id]);
    await _dbHelper.queueSync(
      'commission_rules',
      id,
      'UPDATE',
      {'id': id, 'is_active': 0},
      executor: executor,
    );
  }

  // ------------------------------------------------------------ gross sales

  /// Sum of `sales.net_amount` for one salesman between [from] and [to],
  /// both inclusive.
  ///
  /// **Cancelled sales are excluded.** `sales.status` is set to `'cancelled'`
  /// by `SaleCancellationRepository`, and paying commission on a bill the
  /// shop reversed is simply wrong. Note this differs from the older
  /// `SalesmanRepository.getPerformance()`, which counts every row regardless
  /// of status — that pre-existing inconsistency is recorded in
  /// `docs/COLLECTIONS_COMMISSION_ARCHITECTURE.md` rather than changed here,
  /// since a performance leaderboard and a payable are not obliged to agree.
  ///
  /// `net_amount` is the field every existing sales report totals
  /// (`AdvancedReportService` uses it throughout), so commission is worked
  /// out on the same figure the shop already calls a day's sales.
  Future<double> getGrossSales(
    String salesmanId,
    DateTime from,
    DateTime to, {
    DatabaseExecutor? executor,
  }) async {
    final db = await _db(executor);
    final rows = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(net_amount), 0) AS gross
      FROM sales
      WHERE salesman_id = ?
        AND created_at >= ?
        AND created_at <= ?
        AND COALESCE(status, 'completed') != 'cancelled'
      ''',
      [salesmanId, from.millisecondsSinceEpoch ~/ 1000, to.millisecondsSinceEpoch ~/ 1000],
    );
    return (rows.first['gross'] as num?)?.toDouble() ?? 0;
  }

  // ------------------------------------------------------------ settlements

  Future<void> insertSettlement(CommissionSettlement settlement, {DatabaseExecutor? executor}) async {
    final db = await _db(executor);
    await db.insert('commission_ledger', settlement.toJson());
    await _dbHelper.queueSync(
      'commission_ledger',
      settlement.id,
      'INSERT',
      settlement.toJson(),
      executor: executor,
    );
  }

  Future<CommissionSettlement?> getSettlementById(String id, {DatabaseExecutor? executor}) async {
    final db = await _db(executor);
    final rows = await db.query('commission_ledger', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return CommissionSettlement.fromJson(rows.first);
  }

  /// The existing settlement for exactly this salesman and period, if any —
  /// the pre-check behind the `UNIQUE(salesman_id, period_from, period_to)`
  /// constraint, so a duplicate gets a readable error instead of a raw
  /// SQLite exception.
  Future<CommissionSettlement?> getSettlementForPeriod(
    String salesmanId,
    DateTime from,
    DateTime to, {
    DatabaseExecutor? executor,
  }) async {
    final db = await _db(executor);
    final rows = await db.query(
      'commission_ledger',
      where: 'salesman_id = ? AND period_from = ? AND period_to = ?',
      whereArgs: [
        salesmanId,
        from.millisecondsSinceEpoch ~/ 1000,
        to.millisecondsSinceEpoch ~/ 1000,
      ],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return CommissionSettlement.fromJson(rows.first);
  }

  /// Settlements, most recent period first. Both filters are optional so the
  /// payout screen ("everything still unpaid") and the per-salesman history
  /// share one query.
  Future<List<CommissionSettlement>> getSettlements({
    String? salesmanId,
    CommissionSettlementStatus? status,
    DatabaseExecutor? executor,
  }) async {
    final db = await _db(executor);
    final where = <String>[];
    final args = <Object?>[];
    if (salesmanId != null) {
      where.add('salesman_id = ?');
      args.add(salesmanId);
    }
    if (status != null) {
      where.add('status = ?');
      args.add(status.name);
    }
    final rows = await db.query(
      'commission_ledger',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'period_from DESC, id DESC',
    );
    return rows.map(CommissionSettlement.fromJson).toList();
  }

  Future<void> updateSettlement(CommissionSettlement settlement, {DatabaseExecutor? executor}) async {
    final db = await _db(executor);
    await db.update(
      'commission_ledger',
      settlement.toJson(),
      where: 'id = ?',
      whereArgs: [settlement.id],
    );
    await _dbHelper.queueSync(
      'commission_ledger',
      settlement.id,
      'UPDATE',
      settlement.toJson(),
      executor: executor,
    );
  }

  /// Removes a settlement. `CommissionService` only allows this while the
  /// settlement is still `calculated` — a paid-out commission is history.
  Future<void> deleteSettlement(String id, {DatabaseExecutor? executor}) async {
    final db = await _db(executor);
    await db.delete('commission_ledger', where: 'id = ?', whereArgs: [id]);
    await _dbHelper.queueSync('commission_ledger', id, 'DELETE', {'id': id}, executor: executor);
  }
}

final commissionRepositoryProvider = Provider<CommissionRepository>((ref) => CommissionRepository());
