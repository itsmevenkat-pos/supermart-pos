import 'package:sqflite/sqflite.dart';

/// Adds a "Packing Date" (when a batch was packed/manufactured, distinct
/// from Expiry Date and from when it was received into this shop) to
/// `purchase_items` (entered per purchase line) and `product_batches`
/// (the queryable batch-history record it flows into) — needed so the
/// barcode label can print a real Packing Date instead of guessing at it.
class MigrationV29 {
  static Future<void> up(Database db) async {
    try {
      await db.execute('ALTER TABLE purchase_items ADD COLUMN packing_date INTEGER');
    } catch (_) {
      // Column may already exist on some upgrade paths — safe to ignore.
    }
    try {
      await db.execute('ALTER TABLE product_batches ADD COLUMN packing_date INTEGER');
    } catch (_) {
      // Column may already exist on some upgrade paths — safe to ignore.
    }
  }
}
