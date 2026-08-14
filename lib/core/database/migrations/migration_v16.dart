import 'package:sqflite/sqflite.dart';

/// Adds Sale Cancellations and Exchanges:
/// - `sale_cancellations`: one row per cancelled completed sale. `sale_id`
///   is UNIQUE — the DB-level guarantee a sale can only be cancelled once
///   (application code also checks no `sales_returns` reference the sale
///   first, since a cancel fully reverses stock and would double-count
///   against a partial return).
/// - `exchanges`: links a `sales_returns` row (what came back) with a new
///   `sales` row (the replacement items) and records the net settlement —
///   deliberately built on the existing return/sale schema rather than
///   duplicating item-line tables.
class MigrationV16 {
  static Future<void> up(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sale_cancellations (
        id TEXT PRIMARY KEY,
        sale_id TEXT UNIQUE NOT NULL REFERENCES sales(id),
        customer_id TEXT REFERENCES customers(id) ON DELETE SET NULL,
        reason TEXT NOT NULL,
        refund_method TEXT NOT NULL,
        refund_amount REAL NOT NULL DEFAULT 0,
        user_id TEXT NOT NULL,
        approved_by_user_id TEXT REFERENCES users(id) ON DELETE SET NULL,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sale_cancellations_sale ON sale_cancellations(sale_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sale_cancellations_customer ON sale_cancellations(customer_id)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS exchanges (
        id TEXT PRIMARY KEY,
        return_id TEXT NOT NULL REFERENCES sales_returns(id),
        new_sale_id TEXT REFERENCES sales(id) ON DELETE SET NULL,
        customer_id TEXT REFERENCES customers(id) ON DELETE SET NULL,
        price_difference REAL NOT NULL DEFAULT 0,
        settlement_method TEXT NOT NULL,
        user_id TEXT NOT NULL,
        approved_by_user_id TEXT REFERENCES users(id) ON DELETE SET NULL,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_exchanges_return ON exchanges(return_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_exchanges_new_sale ON exchanges(new_sale_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_exchanges_customer ON exchanges(customer_id)');
  }
}
