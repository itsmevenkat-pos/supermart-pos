import 'package:sqflite/sqflite.dart';

/// Price revision history: `product_form_screen.dart` previously overwrote
/// `retail_price`/`mrp`/`cost_price`/`wholesale_price` silently on every
/// edit, with no audit trail of who changed a price, when, or from what.
/// This adds one append-only row per changed field per edit — see
/// `PriceHistoryRepository.logChange`.
class MigrationV24 {
  static Future<void> up(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS price_history (
        id TEXT PRIMARY KEY,
        product_id TEXT NOT NULL REFERENCES products(id) ON DELETE CASCADE,
        field TEXT NOT NULL,
        old_value REAL,
        new_value REAL NOT NULL,
        changed_by_user_id TEXT REFERENCES users(id) ON DELETE SET NULL,
        changed_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_price_history_product ON price_history(product_id)');
  }
}
