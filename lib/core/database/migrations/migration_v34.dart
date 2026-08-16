import 'dart:convert';

import 'package:sqflite/sqflite.dart';

/// Cash movements — one row per physical movement of notes in or out of a
/// till, whatever caused it (C1).
///
/// **Why this table exists.** Shift reconciliation used to compute
/// `expectedCash = openingCash + <cash portion of this session's sales>`.
/// That is blind to every other way cash enters or leaves the drawer:
/// khata (credit) collections, cash refunds on returns, and cash refunds on
/// cancellations. A cashier could collect ₹5,000 of dues, pocket exactly
/// ₹5,000, and still close a perfectly balanced till — the one control meant
/// to catch till shrinkage could not see the two transaction types most used
/// to create it. Symmetrically, an honest cashier who paid a ₹3,000 cash
/// refund read ₹3,000 short and went hunting a phantom error.
///
/// Design points worth knowing before changing anything here:
/// - **This is the single source of truth for expected cash.** Everything
///   that moves cash writes here, inside its own transaction, so a movement
///   cannot commit without its cause committing too. `expectedCash` is then
///   `openingCash + SUM(signed amount)` and nothing else.
/// - **`direction` is 'in' or 'out'**, with `amount` always stored positive.
///   Storing the sign separately keeps "how much cash changed hands" and
///   "which way" independently queryable — a cash book wants both.
/// - **`session_id` is nullable.** A movement made while no shift is open is
///   still a real movement and still belongs in the cash book; it simply
///   does not land in any shift's reconciliation. Dropping it instead would
///   make the ledger lie by omission.
/// - **Only genuinely-cash movements get a row.** A return settled against
///   store credit, or the return leg of an exchange (`exchange_settled`),
///   moves no notes and must not appear here.
class MigrationV34 {
  static Future<void> up(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cash_movements (
        id TEXT PRIMARY KEY,
        session_id TEXT REFERENCES sessions(id) ON DELETE SET NULL,
        direction TEXT NOT NULL CHECK (direction IN ('in', 'out')),
        amount REAL NOT NULL CHECK (amount >= 0),
        source_type TEXT NOT NULL,
        source_id TEXT,
        user_id TEXT REFERENCES users(id) ON DELETE SET NULL,
        note TEXT,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_cash_movements_session ON cash_movements(session_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_cash_movements_source ON cash_movements(source_type, source_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_cash_movements_created ON cash_movements(created_at)',
    );

    await _backfillFromSales(db);
  }

  /// Recreates cash-in rows for sales that already happened, so an upgrade
  /// does not make an in-flight shift suddenly read short.
  ///
  /// Sales are the one cash source that *was* already counted (from
  /// `sales.payment_methods`), so without this the switch to
  /// `SUM(cash_movements)` would drop every sale taken before the upgrade.
  /// Parsed in Dart rather than SQL on purpose: `payment_methods` is a JSON
  /// map, and relying on SQLite's JSON1 extension being compiled in is a
  /// portability bet this migration does not need to make.
  static Future<void> _backfillFromSales(Database db) async {
    final existing = await db.rawQuery(
      "SELECT COUNT(*) AS c FROM cash_movements WHERE source_type = 'sale'",
    );
    // Idempotent: a re-run (or a v1 create that already delegated here) must
    // not double every historical sale.
    if ((existing.first['c'] as int? ?? 0) > 0) return;

    final sales = await db.query(
      'sales',
      columns: ['id', 'session_id', 'payment_methods', 'created_at', 'user_id'],
      where: "status = ? AND session_id IS NOT NULL",
      whereArgs: ['completed'],
    );

    for (final sale in sales) {
      final cash = _cashPortionOf(sale['payment_methods'] as String?);
      if (cash <= 0) continue;
      await db.insert('cash_movements', {
        'id': 'cm_backfill_${sale['id']}',
        'session_id': sale['session_id'],
        'direction': 'in',
        'amount': cash,
        'source_type': 'sale',
        'source_id': sale['id'],
        'user_id': sale['user_id'],
        'note': 'Backfilled from sale on upgrade to v34',
        'created_at': sale['created_at'] ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
      });
    }
  }

  /// The cash figure out of a sale's `payment_methods` JSON map, or 0 if the
  /// column is absent, unparseable, or records no cash leg. A malformed row
  /// must not abort an upgrade, so this swallows rather than throws.
  static double _cashPortionOf(String? paymentMethodsJson) {
    if (paymentMethodsJson == null || paymentMethodsJson.isEmpty) return 0;
    try {
      final decoded = jsonDecode(paymentMethodsJson);
      if (decoded is! Map) return 0;
      final value = decoded['cash'];
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0;
      return 0;
    } catch (_) {
      return 0;
    }
  }
}
