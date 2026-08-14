import 'package:sqflite/sqflite.dart';

/// Adds returns/refunds: `sales_returns` (header) + `sales_return_items`
/// (lines), plus `stores.return_threshold_no_approval` — the rupee amount
/// below which a return posts without manager/admin sign-off. Untied
/// returns (no originating sale) always require approval regardless of
/// amount, enforced in code, not schema.
class MigrationV15 {
  static Future<void> up(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sales_returns (
        id TEXT PRIMARY KEY,
        sale_id TEXT REFERENCES sales(id) ON DELETE SET NULL,
        customer_id TEXT REFERENCES customers(id) ON DELETE SET NULL,
        store_id TEXT REFERENCES stores(id),
        session_id TEXT,
        user_id TEXT NOT NULL,
        approved_by_user_id TEXT REFERENCES users(id) ON DELETE SET NULL,
        reason TEXT NOT NULL,
        refund_method TEXT NOT NULL,
        refund_amount REAL NOT NULL DEFAULT 0,
        is_untied INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sales_returns_sale ON sales_returns(sale_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sales_returns_customer ON sales_returns(customer_id)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sales_return_items (
        id TEXT PRIMARY KEY,
        return_id TEXT NOT NULL REFERENCES sales_returns(id) ON DELETE CASCADE,
        sale_item_id TEXT REFERENCES sale_items(id),
        product_id TEXT NOT NULL REFERENCES products(id),
        quantity REAL NOT NULL,
        unit_price REAL NOT NULL DEFAULT 0,
        tax_amount REAL NOT NULL DEFAULT 0,
        total_price REAL NOT NULL DEFAULT 0,
        cost_price REAL NOT NULL DEFAULT 0,
        restocked INTEGER NOT NULL DEFAULT 1
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sales_return_items_return ON sales_return_items(return_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sales_return_items_product ON sales_return_items(product_id)');

    try {
      await db.execute('ALTER TABLE stores ADD COLUMN return_threshold_no_approval REAL DEFAULT 500');
    } catch (_) {
      // Column may already exist on some upgrade paths — safe to ignore.
    }
  }
}
