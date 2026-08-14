import 'package:sqflite/sqflite.dart';

/// Adds `products.hsn_code` — powers the HSN/SAC-grouped GST reports in
/// `AdvancedReportService`. Nullable: products without a code yet are shown
/// as "Not set" in those reports rather than blocking them.
class MigrationV13 {
  static Future<void> up(Database db) async {
    try {
      await db.execute('ALTER TABLE products ADD COLUMN hsn_code TEXT');
    } catch (_) {
      // Column may already exist on some upgrade paths — safe to ignore.
    }
  }
}
