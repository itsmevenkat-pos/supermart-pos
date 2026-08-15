import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../core/database/database_helper.dart';
import '../models/collection_activity_model.dart';
import '../models/customer_ledger_model.dart';
import '../models/customer_model.dart';

/// Data access for collection follow-ups, plus the ledger reads that
/// accounts-receivable aging is computed from.
///
/// Storage only — it does not decide which aging bucket anything falls in or
/// what a customer still owes. That is `CollectionsService`'s job, and it
/// works from the rows this class returns.
///
/// **There is no aging table to read or write.** Aging comes from
/// `customer_ledger`, which `SaleRepository`, `CustomerRepository`,
/// `SalesReturnRepository`, `ExchangeRepository` and
/// `SaleCancellationRepository` have all been writing since well before this
/// module existed. Deriving it keeps one source of truth for what a customer
/// owes; a stored snapshot would be stale the moment the next payment lands.
class CollectionsRepository {
  CollectionsRepository({DatabaseHelper? dbHelper}) : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _dbHelper;

  Future<DatabaseExecutor> _db(DatabaseExecutor? executor) async => executor ?? await _dbHelper.database;

  // ----------------------------------------------------------------- ledger

  /// Every ledger entry at or before [asOf], oldest first within each
  /// customer, for the FIFO walk in `CollectionsService`.
  ///
  /// Ordered by `customer_id, created_at, id`. The `id` tie-break is not
  /// cosmetic: `created_at` is only second-granular, so a sale and the
  /// payment that settles it in the same second would otherwise come back in
  /// an order that varies between runs, and FIFO would age different entries
  /// each time.
  ///
  /// Entries dated *after* [asOf] are excluded rather than clamped, so an
  /// as-of report reproduces what the shop would have seen on that day.
  Future<List<CustomerLedger>> getLedgerEntries({
    DateTime? asOf,
    String? customerId,
    DatabaseExecutor? executor,
  }) async {
    final db = await _db(executor);
    final where = <String>[];
    final args = <Object?>[];
    if (asOf != null) {
      where.add('created_at <= ?');
      args.add(asOf.millisecondsSinceEpoch ~/ 1000);
    }
    if (customerId != null) {
      where.add('customer_id = ?');
      args.add(customerId);
    }
    final rows = await db.query(
      'customer_ledger',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'customer_id ASC, created_at ASC, id ASC',
    );
    return rows.map(CustomerLedger.fromJson).toList();
  }

  /// The customers named by [ids], keyed by id, for putting a name and phone
  /// number against an aging row. Deleted customers are included on purpose —
  /// money owed by a customer someone has since removed from the list is
  /// still money owed, and hiding it would quietly shrink the receivable.
  Future<Map<String, Customer>> getCustomersByIds(
    Iterable<String> ids, {
    DatabaseExecutor? executor,
  }) async {
    final idList = ids.toSet().toList();
    if (idList.isEmpty) return {};
    final db = await _db(executor);
    final result = <String, Customer>{};
    // SQLite caps variables per statement (999 on older builds); chunking
    // keeps this working for a customer list of any size.
    const chunkSize = 500;
    for (var i = 0; i < idList.length; i += chunkSize) {
      final chunk = idList.sublist(i, (i + chunkSize).clamp(0, idList.length));
      final placeholders = List.filled(chunk.length, '?').join(',');
      final rows = await db.query(
        'customers',
        where: 'id IN ($placeholders)',
        whereArgs: chunk,
      );
      for (final row in rows) {
        final customer = Customer.fromJson(row);
        result[customer.id] = customer;
      }
    }
    return result;
  }

  // ------------------------------------------------------------- activities

  Future<void> insertActivity(CollectionActivity activity, {DatabaseExecutor? executor}) async {
    final db = await _db(executor);
    await db.insert('collection_activities', activity.toJson());
    await _dbHelper.queueSync(
      'collection_activities',
      activity.id,
      'INSERT',
      activity.toJson(),
      executor: executor,
    );
  }

  Future<void> updateActivity(CollectionActivity activity, {DatabaseExecutor? executor}) async {
    final db = await _db(executor);
    await db.update(
      'collection_activities',
      activity.toJson(),
      where: 'id = ?',
      whereArgs: [activity.id],
    );
    await _dbHelper.queueSync(
      'collection_activities',
      activity.id,
      'UPDATE',
      activity.toJson(),
      executor: executor,
    );
  }

  Future<CollectionActivity?> getActivityById(String id, {DatabaseExecutor? executor}) async {
    final db = await _db(executor);
    final rows = await db.query('collection_activities', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return CollectionActivity.fromJson(rows.first);
  }

  /// One customer's collection history, most recent first — newest first
  /// because the question a collector asks is "when did we last chase them",
  /// unlike the customer ledger which reads as a statement.
  Future<List<CollectionActivity>> getActivitiesForCustomer(
    String customerId, {
    DatabaseExecutor? executor,
  }) async {
    final db = await _db(executor);
    final rows = await db.query(
      'collection_activities',
      where: 'customer_id = ?',
      whereArgs: [customerId],
      orderBy: 'COALESCE(completed_date, scheduled_date, created_at) DESC, id DESC',
    );
    return rows.map(CollectionActivity.fromJson).toList();
  }

  /// The follow-up worklist: pending activities with a scheduled date,
  /// soonest first. Pass [dueBy] to get only what is due by then.
  Future<List<CollectionActivity>> getPendingActivities({
    DateTime? dueBy,
    DatabaseExecutor? executor,
  }) async {
    final db = await _db(executor);
    final where = StringBuffer('status = ? AND scheduled_date IS NOT NULL');
    final args = <Object?>[CollectionActivityStatus.pending.name];
    if (dueBy != null) {
      where.write(' AND scheduled_date <= ?');
      args.add(dueBy.millisecondsSinceEpoch ~/ 1000);
    }
    final rows = await db.query(
      'collection_activities',
      where: where.toString(),
      whereArgs: args,
      orderBy: 'scheduled_date ASC, id ASC',
    );
    return rows.map(CollectionActivity.fromJson).toList();
  }

  /// Deletes a follow-up outright. Used for a reminder scheduled by mistake;
  /// completed activities are history and the UI does not offer this for
  /// them.
  Future<void> deleteActivity(String id, {DatabaseExecutor? executor}) async {
    final db = await _db(executor);
    await db.delete('collection_activities', where: 'id = ?', whereArgs: [id]);
    await _dbHelper.queueSync('collection_activities', id, 'DELETE', {'id': id}, executor: executor);
  }
}

final collectionsRepositoryProvider = Provider<CollectionsRepository>((ref) => CollectionsRepository());
