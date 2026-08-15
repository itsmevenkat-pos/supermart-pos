import 'package:sqflite/sqflite.dart';

/// Loyalty point event log + point expiry (Phase 2, Task 2.2).
///
/// **This extends the existing `bonus_points` table rather than adding the
/// `loyalty_point_events` table the task file describes.** `bonus_points` has
/// existed since the original schema and `SaleRepository` already writes one
/// row per sale that earns or redeems points. A second table recording the
/// same events is precisely the "two disagreeing sources of truth" the task
/// file warns against — so the event log is the table that already holds the
/// events, widened to say more about each one.
///
/// What the four new columns add:
/// - `event_type` — `sale` | `adjust` | `expire` | `cancellation`. Existing
///   rows all came from `SaleRepository`, so the default backfills them
///   correctly as `sale` with no data migration.
/// - `expires_at` — seconds since epoch at which *this row's* earned points
///   lapse, or NULL for points that never expire. Set per earn event rather
///   than derived at read time from a store setting, so changing the store's
///   expiry window later cannot retroactively expire points a customer was
///   already told they had.
/// - `expired_points` — how many of this row's `points_earned` have since been
///   consumed by an expiry run. Lets [LoyaltyService.expireOldPoints] be
///   re-runnable: a lot that has already given up its remainder cannot give it
///   up twice.
/// - `note` / `created_by_user_id` — who made a manual adjustment and why.
///   Meaningless for `sale` rows, required in practice for `adjust` ones.
///
/// `stores.loyalty_points_expiry_days` defaults to **0, meaning never expire**,
/// so every existing installation keeps today's behaviour until a manager
/// deliberately turns expiry on. Points silently vanishing after an upgrade
/// nobody asked for would be a customer-facing regression, not a feature.
///
/// Like [MigrationV28] and [MigrationV29] this runs from both paths —
/// `onUpgrade` (`oldVersion < 30`) and `onCreate` (via `MigrationV1`, which
/// delegates here). Every statement is `ADD COLUMN` in a try/catch or
/// `IF NOT EXISTS`, so running it against a database that already has the
/// columns is a no-op.
class MigrationV30 {
  static Future<void> up(Database db) async {
    // --------------------------------------------------- bonus_points columns
    try {
      await db.execute("ALTER TABLE bonus_points ADD COLUMN event_type TEXT NOT NULL DEFAULT 'sale'");
    } catch (_) {
      // Column may already exist on some upgrade paths — safe to ignore.
    }
    try {
      await db.execute('ALTER TABLE bonus_points ADD COLUMN expires_at INTEGER');
    } catch (_) {
      // Column may already exist on some upgrade paths — safe to ignore.
    }
    try {
      await db.execute('ALTER TABLE bonus_points ADD COLUMN expired_points INTEGER NOT NULL DEFAULT 0');
    } catch (_) {
      // Column may already exist on some upgrade paths — safe to ignore.
    }
    try {
      await db.execute('ALTER TABLE bonus_points ADD COLUMN note TEXT');
    } catch (_) {
      // Column may already exist on some upgrade paths — safe to ignore.
    }
    try {
      await db.execute('ALTER TABLE bonus_points ADD COLUMN created_by_user_id TEXT');
    } catch (_) {
      // Column may already exist on some upgrade paths — safe to ignore.
    }

    // ------------------------------------------------------ store expiry knob
    try {
      await db.execute('ALTER TABLE stores ADD COLUMN loyalty_points_expiry_days INTEGER NOT NULL DEFAULT 0');
    } catch (_) {
      // Column may already exist on some upgrade paths — safe to ignore.
    }

    // ------------------------------------------------------------- indexes
    // Every read of this table is "one customer, in date order" — the
    // per-customer history screen, the FIFO expiry walk, and the balance
    // recomputation all start here.
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_bonus_points_customer_date ON bonus_points(customer_id, date)',
    );
    // The expiry sweep asks the opposite question — "which lots are due,
    // across all customers" — and would otherwise scan the whole table.
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_bonus_points_expires_at ON bonus_points(expires_at)',
    );
    // Reversing a cancelled sale looks its original event up by sale.
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_bonus_points_sale ON bonus_points(sale_id)',
    );
  }
}
