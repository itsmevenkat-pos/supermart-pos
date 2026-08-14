import 'package:sqflite/sqflite.dart';

/// Completes the Product & Item Master feature set: local-language name,
/// purchase-unit conversion, weighed-item flag, max stock level, parent/
/// variant linking, kit/service flags, item image, plus two new tables —
/// `product_batches` (a real, queryable batch/MRP/expiry history per item,
/// written on every purchase) and `product_kit_components` (what a kit/
/// bundle product is made of, consumed by SaleRepository at sale time).
class MigrationV17 {
  static Future<void> up(Database db) async {
    for (final column in [
      'local_name TEXT',
      'purchase_unit TEXT',
      'units_per_purchase_unit REAL DEFAULT 1',
      'is_weighted INTEGER DEFAULT 0',
      'max_stock_level REAL',
      'parent_product_id TEXT REFERENCES products(id) ON DELETE SET NULL',
      'is_kit INTEGER DEFAULT 0',
      'is_service INTEGER DEFAULT 0',
      'image_path TEXT',
    ]) {
      try {
        await db.execute('ALTER TABLE products ADD COLUMN $column');
      } catch (_) {
        // Column may already exist on some upgrade paths — safe to ignore.
      }
    }

    await db.execute('''
      CREATE TABLE IF NOT EXISTS product_batches (
        id TEXT PRIMARY KEY,
        product_id TEXT NOT NULL REFERENCES products(id) ON DELETE CASCADE,
        purchase_id TEXT REFERENCES purchases(id) ON DELETE SET NULL,
        batch_no TEXT,
        mrp REAL,
        cost_price REAL,
        selling_price REAL,
        expiry_date INTEGER,
        quantity_received REAL NOT NULL,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_product_batches_product ON product_batches(product_id)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS product_kit_components (
        id TEXT PRIMARY KEY,
        kit_product_id TEXT NOT NULL REFERENCES products(id) ON DELETE CASCADE,
        component_product_id TEXT NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
        quantity REAL NOT NULL DEFAULT 1
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_kit_components_kit ON product_kit_components(kit_product_id)');
  }
}
