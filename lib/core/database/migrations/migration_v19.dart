import 'package:sqflite/sqflite.dart';

/// Completes Customer/CRM & Loyalty: configurable membership-tier spend
/// thresholds + loyalty redemption value (mirrors how `return_threshold_no_
/// approval`/`max_discount_percent_no_approval` were promoted from hardcoded
/// constants to real per-store settings), a customer date-of-birth field for
/// birthday campaigns, and the two sale-side fields needed to record a
/// loyalty-point redemption on the bill it happened on.
class MigrationV19 {
  static Future<void> up(Database db) async {
    for (final column in [
      'tier_bronze_min_spent REAL DEFAULT 2000',
      'tier_silver_min_spent REAL DEFAULT 10000',
      'tier_gold_min_spent REAL DEFAULT 25000',
      'loyalty_value_per_point REAL DEFAULT 0.5',
    ]) {
      try {
        await db.execute('ALTER TABLE stores ADD COLUMN $column');
      } catch (_) {
        // Column may already exist on some upgrade paths — safe to ignore.
      }
    }

    try {
      await db.execute('ALTER TABLE customers ADD COLUMN date_of_birth INTEGER');
    } catch (_) {
      // Column may already exist on some upgrade paths — safe to ignore.
    }

    for (final column in [
      'loyalty_points_redeemed INTEGER DEFAULT 0',
      'loyalty_redemption_amount REAL DEFAULT 0',
    ]) {
      try {
        await db.execute('ALTER TABLE sales ADD COLUMN $column');
      } catch (_) {
        // Column may already exist on some upgrade paths — safe to ignore.
      }
    }
  }
}
