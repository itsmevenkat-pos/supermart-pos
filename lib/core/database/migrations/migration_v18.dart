import 'package:sqflite/sqflite.dart';

/// Vendor-checklist gaps: a configurable discount-% cap a cashier can apply
/// without manager approval (mirrors `return_threshold_no_approval`), a
/// free-text remarks field per bill, and per-line `quotation_items` — quotes
/// previously stored only header totals, so there was nothing to reload when
/// converting a quotation into a bill.
class MigrationV18 {
  static Future<void> up(Database db) async {
    try {
      await db.execute('ALTER TABLE stores ADD COLUMN max_discount_percent_no_approval REAL DEFAULT 10');
    } catch (_) {
      // Column may already exist on some upgrade paths — safe to ignore.
    }
    try {
      await db.execute('ALTER TABLE sales ADD COLUMN remarks TEXT');
    } catch (_) {
      // Column may already exist on some upgrade paths — safe to ignore.
    }
    await db.execute('''
      CREATE TABLE IF NOT EXISTS quotation_items (
        id TEXT PRIMARY KEY,
        quotation_id TEXT NOT NULL REFERENCES quotations(id) ON DELETE CASCADE,
        product_id TEXT NOT NULL REFERENCES products(id),
        quantity REAL NOT NULL DEFAULT 1,
        unit_price REAL NOT NULL DEFAULT 0,
        total_price REAL NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_quotation_items_quotation ON quotation_items(quotation_id)');
  }
}
