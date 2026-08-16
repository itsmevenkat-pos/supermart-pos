import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../core/database/database_helper.dart';

/// Where a cash movement came from. Kept as constants rather than an enum so
/// the stored strings are greppable and stable across schema dumps.
class CashMovementSource {
  static const String sale = 'sale';
  static const String salesReturn = 'sales_return';
  static const String saleCancellation = 'sale_cancellation';
  static const String customerPayment = 'customer_payment';
  static const String manualAdjustment = 'manual_adjustment';
}

/// The one writer of `cash_movements` — every path that moves notes in or out
/// of a till goes through [record], and shift reconciliation reads nothing
/// else (see `MigrationV34` for why).
///
/// Callers pass their own `executor` so the movement commits or rolls back
/// with whatever caused it. A cash row that outlived a rolled-back sale would
/// be worse than no row at all.
class CashMovementRepository {
  CashMovementRepository({DatabaseHelper? dbHelper})
      : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _dbHelper;
  static const _uuid = Uuid();

  /// Payment-method strings that mean physical notes. Anything else — UPI,
  /// card, store credit, `exchange_settled` — moves no cash and must not
  /// produce a row.
  static bool isCashMethod(String? method) => method == 'cash';

  /// Records one movement. [amount] is taken as a magnitude; its sign is
  /// ignored in favour of [direction], so a caller passing a negative refund
  /// amount cannot silently invert the drawer.
  ///
  /// [sessionId] may be left null and resolved from [userId] instead — the
  /// lookup runs on [executor], never on a second connection, because
  /// querying through `_dbHelper.database` inside a caller's transaction
  /// deadlocks against it in sqflite.
  Future<void> record({
    required String direction,
    required double amount,
    required String sourceType,
    String? sourceId,
    String? sessionId,
    String? userId,
    String? note,
    required DatabaseExecutor executor,
  }) async {
    assert(direction == 'in' || direction == 'out');
    final magnitude = amount.abs();
    // A zero-value movement is not a movement. Recording it would clutter the
    // cash book without changing any total.
    if (magnitude == 0) return;

    final resolvedSession = sessionId ?? await _activeSessionId(userId, executor);

    await executor.insert('cash_movements', {
      'id': _uuid.v4(),
      'session_id': resolvedSession,
      'direction': direction,
      'amount': magnitude,
      'source_type': sourceType,
      'source_id': sourceId,
      'user_id': userId,
      'note': note,
      'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    });
  }

  /// Convenience wrappers — they exist so call sites read as what happened
  /// ("cash came in") rather than as a string literal.
  Future<void> recordIn({
    required double amount,
    required String sourceType,
    String? sourceId,
    String? sessionId,
    String? userId,
    String? note,
    required DatabaseExecutor executor,
  }) =>
      record(
        direction: 'in',
        amount: amount,
        sourceType: sourceType,
        sourceId: sourceId,
        sessionId: sessionId,
        userId: userId,
        note: note,
        executor: executor,
      );

  Future<void> recordOut({
    required double amount,
    required String sourceType,
    String? sourceId,
    String? sessionId,
    String? userId,
    String? note,
    required DatabaseExecutor executor,
  }) =>
      record(
        direction: 'out',
        amount: amount,
        sourceType: sourceType,
        sourceId: sourceId,
        sessionId: sessionId,
        userId: userId,
        note: note,
        executor: executor,
      );

  /// The open shift for [userId], or null. Mirrors
  /// `SessionRepository.getActiveSession` but runs on the caller's executor.
  Future<String?> _activeSessionId(String? userId, DatabaseExecutor executor) async {
    if (userId == null) return null;
    final rows = await executor.query(
      'sessions',
      columns: ['id'],
      where: 'user_id = ? AND status = ?',
      whereArgs: [userId, 'open'],
      orderBy: 'opening_time DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['id'] as String?;
  }

  /// Net cash for a shift: everything in, minus everything out. This is the
  /// figure shift-close adds to opening cash.
  Future<double> getSessionNet(String sessionId, {DatabaseExecutor? executor}) async {
    final db = executor ?? await _dbHelper.database;
    final rows = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(CASE direction WHEN 'in' THEN amount ELSE -amount END), 0) AS net
      FROM cash_movements
      WHERE session_id = ?
      ''',
      [sessionId],
    );
    return (rows.first['net'] as num?)?.toDouble() ?? 0;
  }

  /// Every movement in a shift, newest first — the cash book behind the
  /// single "expected cash" number, so a discrepancy can be investigated
  /// rather than just observed.
  Future<List<Map<String, dynamic>>> getBySession(String sessionId) async {
    final db = await _dbHelper.database;
    return db.query(
      'cash_movements',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'created_at DESC',
    );
  }
}

final cashMovementRepositoryProvider =
    Provider<CashMovementRepository>((ref) => CashMovementRepository());
