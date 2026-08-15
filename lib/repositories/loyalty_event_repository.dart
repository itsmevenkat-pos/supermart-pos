import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../core/database/database_helper.dart';
import '../models/loyalty_point_event_model.dart';

/// Data access for the loyalty point event log (`bonus_points`).
///
/// Storage only — no expiry arithmetic, no deciding what a balance *should*
/// be. That is `LoyaltyService`'s job; this class reads and writes rows.
///
/// Same `executor` convention as `GLRepository` and
/// `BankReconciliationRepository`: every writing method takes an optional
/// [DatabaseExecutor] so an expiry sweep (N lot updates, one event row and one
/// customer balance update) can be made atomic by the service, while the same
/// methods still work standalone.
///
/// Note this repository deliberately does **not** own
/// `customers.loyalty_points`. That column is written by `SaleRepository`
/// inside the sale transaction and by `LoyaltyService` for adjustments and
/// expiry; making a second class free to move it would put the running total
/// and its audit trail out of step.
class LoyaltyEventRepository {
  LoyaltyEventRepository({DatabaseHelper? dbHelper}) : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _dbHelper;

  Future<DatabaseExecutor> _db(DatabaseExecutor? executor) async => executor ?? await _dbHelper.database;

  // -------------------------------------------------------------- writing

  Future<LoyaltyPointEvent> insertEvent(LoyaltyPointEvent event, {DatabaseExecutor? executor}) async {
    final db = await _db(executor);
    await db.insert('bonus_points', event.toJson());
    return event;
  }

  /// Raises a lot's written-off total. Additive rather than absolute so a
  /// second expiry run on a partially-expired lot cannot silently reset what
  /// an earlier run already took.
  Future<void> addExpiredPoints(String eventId, int points, {DatabaseExecutor? executor}) async {
    if (points <= 0) return;
    final db = await _db(executor);
    await db.rawUpdate(
      'UPDATE bonus_points SET expired_points = expired_points + ? WHERE id = ?',
      [points, eventId],
    );
  }

  // -------------------------------------------------------------- reading

  /// One customer's events, newest first — the order a history screen wants.
  /// Use [getEarnLotsForCustomer] when you need FIFO (oldest-first) order.
  Future<List<LoyaltyPointEvent>> getEventsForCustomer(
    String customerId, {
    DateTime? from,
    DateTime? to,
    int? limit,
    DatabaseExecutor? executor,
  }) async {
    final db = await _db(executor);
    final where = StringBuffer('customer_id = ?');
    final args = <Object?>[customerId];
    if (from != null) {
      where.write(' AND date >= ?');
      args.add(from.millisecondsSinceEpoch ~/ 1000);
    }
    if (to != null) {
      where.write(' AND date <= ?');
      args.add(to.millisecondsSinceEpoch ~/ 1000);
    }
    final rows = await db.query(
      'bonus_points',
      where: where.toString(),
      whereArgs: args,
      orderBy: 'date DESC, id DESC',
      limit: limit,
    );
    return rows.map(LoyaltyPointEvent.fromJson).toList();
  }

  /// All events in a date range across every customer, newest first —
  /// the store-wide activity feed.
  Future<List<LoyaltyPointEvent>> getEventsInRange({
    required DateTime from,
    required DateTime to,
    LoyaltyEventType? eventType,
    DatabaseExecutor? executor,
  }) async {
    final db = await _db(executor);
    final where = StringBuffer('date >= ? AND date <= ?');
    final args = <Object?>[
      from.millisecondsSinceEpoch ~/ 1000,
      to.millisecondsSinceEpoch ~/ 1000,
    ];
    if (eventType != null) {
      where.write(' AND event_type = ?');
      args.add(eventType.name);
    }
    final rows = await db.query(
      'bonus_points',
      where: where.toString(),
      whereArgs: args,
      orderBy: 'date DESC, id DESC',
    );
    return rows.map(LoyaltyPointEvent.fromJson).toList();
  }

  Future<LoyaltyPointEvent?> getEventForSale(String saleId, {DatabaseExecutor? executor}) async {
    final db = await _db(executor);
    final rows = await db.query(
      'bonus_points',
      where: 'sale_id = ? AND event_type = ?',
      whereArgs: [saleId, LoyaltyEventType.sale.name],
      orderBy: 'date ASC',
      limit: 1,
    );
    return rows.isEmpty ? null : LoyaltyPointEvent.fromJson(rows.first);
  }

  /// Earn lots oldest-first — the order the FIFO expiry walk consumes them in.
  /// Rows that earned nothing (a pure redemption, an expiry write-off) are not
  /// lots and are excluded.
  Future<List<LoyaltyPointEvent>> getEarnLotsForCustomer(
    String customerId, {
    DatabaseExecutor? executor,
  }) async {
    final db = await _db(executor);
    final rows = await db.query(
      'bonus_points',
      where: 'customer_id = ? AND points_earned > 0',
      whereArgs: [customerId],
      orderBy: 'date ASC, id ASC',
    );
    return rows.map(LoyaltyPointEvent.fromJson).toList();
  }

  /// Points this customer has spent, **excluding** expiry write-offs.
  ///
  /// Expiry rows carry their write-off in `points_redeemed` too, but the same
  /// amount is already recorded per-lot in `expired_points`. Counting both
  /// would deduct every expiry twice on the next sweep, so the FIFO walk asks
  /// for consumption-by-spending only and reads expiry off the lots.
  Future<int> getRedeemedTotalExcludingExpiry(
    String customerId, {
    DatabaseExecutor? executor,
  }) async {
    final db = await _db(executor);
    final rows = await db.rawQuery(
      'SELECT COALESCE(SUM(points_redeemed), 0) AS total FROM bonus_points '
      'WHERE customer_id = ? AND event_type != ?',
      [customerId, LoyaltyEventType.expire.name],
    );
    return (rows.first['total'] as num?)?.toInt() ?? 0;
  }

  /// Customer ids with at least one lot that is past its expiry date and has
  /// not been fully written off — the candidate set for an expiry sweep, so it
  /// does not have to walk every customer in the database.
  ///
  /// A candidate may still expire nothing: whether its remainder was already
  /// spent is only knowable from the full FIFO walk, which is the service's
  /// job.
  Future<List<String>> getCustomerIdsWithDueLots(
    DateTime asOf, {
    DatabaseExecutor? executor,
  }) async {
    final db = await _db(executor);
    final rows = await db.rawQuery(
      'SELECT DISTINCT customer_id FROM bonus_points '
      'WHERE expires_at IS NOT NULL AND expires_at <= ? AND points_earned > expired_points',
      [asOf.millisecondsSinceEpoch ~/ 1000],
    );
    return rows.map((r) => r['customer_id'] as String).toList();
  }

  /// Total unspent points across every customer. The store's outstanding
  /// loyalty liability in *points*; multiply by `loyalty_value_per_point` for
  /// the rupee figure (see `LoyaltyService.getStoreSummary`).
  ///
  /// Reads `customers.loyalty_points` — the authoritative running balance —
  /// rather than re-summing the event log, so the number agrees with what
  /// every customer is shown at the till.
  Future<int> getTotalOutstandingPoints({DatabaseExecutor? executor}) async {
    final db = await _db(executor);
    final rows = await db.rawQuery(
      'SELECT COALESCE(SUM(loyalty_points), 0) AS total FROM customers WHERE loyalty_points > 0',
    );
    return (rows.first['total'] as num?)?.toInt() ?? 0;
  }

  Future<int> getCustomerCountWithPoints({DatabaseExecutor? executor}) async {
    final db = await _db(executor);
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM customers WHERE loyalty_points > 0',
    );
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  /// Points due to lapse between now and [before], per the lots as they stand.
  ///
  /// This is an **upper bound**: it does not subtract redemptions, because
  /// which lot a redemption drew from is resolved by the FIFO walk, not stored.
  /// Good enough for a "points expiring soon" warning, not a figure to post.
  Future<int> getPointsExpiringBefore(
    DateTime before, {
    String? customerId,
    DatabaseExecutor? executor,
  }) async {
    final db = await _db(executor);
    final where = StringBuffer(
      'expires_at IS NOT NULL AND expires_at <= ? AND points_earned > expired_points',
    );
    final args = <Object?>[before.millisecondsSinceEpoch ~/ 1000];
    if (customerId != null) {
      where.write(' AND customer_id = ?');
      args.add(customerId);
    }
    final rows = await db.rawQuery(
      'SELECT COALESCE(SUM(points_earned - expired_points), 0) AS total FROM bonus_points WHERE $where',
      args,
    );
    return (rows.first['total'] as num?)?.toInt() ?? 0;
  }
}

final loyaltyEventRepositoryProvider =
    Provider<LoyaltyEventRepository>((ref) => LoyaltyEventRepository());
