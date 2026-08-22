import 'package:sqflite/sqflite.dart';

/// Manual cash management: the three things a non-sale cash movement needs to
/// record that `cash_movements` (v34) had nowhere to put.
///
/// **Why this exists.** v34 built the cash book around movements that always
/// had a *document* behind them — a sale, a return, a cancellation, a khata
/// receipt — so `source_type` + `source_id` was enough to explain any row. A
/// manual movement has no document. A ₹5,000 drop to the safe, a ₹200 payout
/// to a delivery driver, a float correction: these are explained by who
/// authorised them, where the money went, and why. Without somewhere to put
/// that, the only options were to encode JSON into the free-text `note` (an
/// approval nobody can query is not a control) or to leave the movements
/// unrecordable, which is what Project 1 found: the shop simply read short.
///
/// **Why additive-only.** Every column here is nullable with no default and no
/// backfill, so:
/// - every existing row stays valid and unchanged;
/// - every existing query, index and `SELECT *` keeps working;
/// - the v34 writers (sale, return, cancellation, customer payment) are
///   untouched — they leave all three null, which is correct, since a sale's
///   authorisation and counterparty live on the sale.
///
/// There is deliberately no CHECK constraint tying `approved_by_user_id` to a
/// direction or amount. Which movements need approval is a business rule that
/// belongs in `CashManagementService`, where it can read a configurable
/// threshold and be tested; freezing it into the schema would make changing
/// the shop's policy a migration.
class MigrationV35 {
  static Future<void> up(Database db) async {
    final existing = await db.rawQuery('PRAGMA table_info(cash_movements)');
    final columns = existing.map((row) => row['name'] as String).toSet();

    // Guarded individually rather than wrapped in one try/catch: SQLite has no
    // `ADD COLUMN IF NOT EXISTS`, and swallowing the error wholesale would
    // also swallow a genuinely broken migration.
    if (!columns.contains('counterparty')) {
      await db.execute('ALTER TABLE cash_movements ADD COLUMN counterparty TEXT');
    }
    if (!columns.contains('approved_by_user_id')) {
      // No REFERENCES clause: SQLite cannot add a column with a foreign key to
      // an existing table. The application validates the approver against
      // `users` before writing (see CashManagementService), which is where the
      // check has to be anyway — a FK could not tell a manager from a cashier.
      await db.execute('ALTER TABLE cash_movements ADD COLUMN approved_by_user_id TEXT');
    }
    if (!columns.contains('reason')) {
      await db.execute('ALTER TABLE cash_movements ADD COLUMN reason TEXT');
    }

    // Manual movements are looked up by counterparty ("everything that went to
    // the safe today") far more than by source id, which is null for them.
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_cash_movements_counterparty ON cash_movements(counterparty)',
    );
  }
}
