import 'package:sqflite/sqflite.dart';

/// Loyalty points were earned at a rate hardcoded in `AppConstants`
/// (₹300 = 1 point) while the redemption value (`loyalty_value_per_point`)
/// was already a real per-store setting — that mismatch is what showed up
/// as "two bonus point options" in Settings, one editable and one not. This
/// makes the earn rate a real per-store setting too, consistent with the
/// redemption side.
class MigrationV26 {
  static Future<void> up(Database db) async {
    try {
      await db.execute('ALTER TABLE stores ADD COLUMN bonus_points_threshold REAL DEFAULT 300');
    } catch (_) {
      // Column may already exist on some upgrade paths — safe to ignore.
    }
  }
}
