import 'package:sqflite/sqflite.dart';

/// Collections & commission settlement (Phase 2, Task 2.4).
///
/// Three tables. Two of them are for commission, which is genuinely new —
/// `salesmen` has carried no commission fields since `MigrationV1`. The
/// third tracks collection follow-ups against overdue credit customers.
///
/// **There is deliberately no aging table.** Accounts-receivable aging is
/// computed on demand by [CollectionsService] from `customer_ledger`, which
/// has recorded every credit sale and every payment since `MigrationV1`. A
/// stored aging snapshot is wrong the moment the next payment lands, and this
/// app already has one source of truth for what a customer owes — see
/// `docs/COLLECTIONS_COMMISSION_ARCHITECTURE.md`.
///
/// Likewise no `dunning_schedules` table: a scheduled reminder is a
/// `collection_activities` row with `status = 'pending'` and a future
/// `scheduled_date`, so a reminder and the call that answers it are the same
/// kind of record rather than two tables that have to agree.
///
/// Like [MigrationV28] through [MigrationV32], this runs from both paths —
/// `onUpgrade` (`oldVersion < 33`) and `onCreate` (via `MigrationV1`, which
/// delegates here). Every statement is `IF NOT EXISTS`, so running it against
/// a database that already has the schema is a no-op.
class MigrationV33 {
  static Future<void> up(Database db) async {
    // ------------------------------------------------- collection follow-ups
    // `amount_collected` is nullable rather than defaulting to 0 because
    // "this call collected nothing" and "this row is a scheduled call that
    // has not happened yet" are different facts, and a 0 default would
    // flatten them into the same value.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS collection_activities (
        id TEXT PRIMARY KEY,
        customer_id TEXT NOT NULL REFERENCES customers(id),
        activity_type TEXT NOT NULL,
        scheduled_date INTEGER,
        completed_date INTEGER,
        status TEXT NOT NULL DEFAULT 'pending',
        notes TEXT,
        amount_collected REAL,
        created_at INTEGER NOT NULL
      )
    ''');

    // "Show this customer's collection history" — the per-customer timeline.
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_collection_activities_customer '
      'ON collection_activities(customer_id)',
    );
    // "What is due to be chased, oldest first" — the follow-up worklist
    // filters on status and orders by scheduled_date, so it gets both.
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_collection_activities_due '
      'ON collection_activities(status, scheduled_date)',
    );

    // ------------------------------------------------------ commission rules
    // `tiered_rates` holds JSON only when `rule_type = 'tiered'`:
    //   [{"upTo": 50000, "rate": 0.02}, {"upTo": null, "rate": 0.03}]
    // A null `upTo` is the open-ended top tier. `base_rate` carries the whole
    // rate for `rule_type = 'percentage'` and is ignored for tiered rules.
    //
    // `effective_to` is nullable = open-ended. CommissionService refuses to
    // calculate a period covered by more than one rule rather than picking
    // one, so overlapping rules are a data error the service surfaces rather
    // than something this schema has to prevent.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS commission_rules (
        id TEXT PRIMARY KEY,
        salesman_id TEXT NOT NULL REFERENCES salesmen(id),
        rule_type TEXT NOT NULL,
        base_rate REAL NOT NULL DEFAULT 0,
        tiered_rates TEXT,
        effective_from INTEGER NOT NULL,
        effective_to INTEGER,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL
      )
    ''');

    // Rule lookup is always "the active rules for this salesman", then the
    // service filters the handful of results by date in Dart.
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_commission_rules_salesman '
      'ON commission_rules(salesman_id, is_active)',
    );

    // --------------------------------------------------- commission settlements
    // The UNIQUE constraint is what makes "calculate this month again" safe:
    // a second settlement for the same salesman and period hits the
    // constraint instead of quietly creating a duplicate payable.
    //
    // `salary_reference` is free text and is the whole of the "salary
    // integration" this app can honestly offer — there is no payroll module
    // to link to. `created_at` is not in the task file's DDL but every other
    // table in this schema has one, and without it there is no way to tell
    // when a settlement was raised as opposed to which period it covers.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS commission_ledger (
        id TEXT PRIMARY KEY,
        salesman_id TEXT NOT NULL REFERENCES salesmen(id),
        period_from INTEGER NOT NULL,
        period_to INTEGER NOT NULL,
        gross_sales REAL NOT NULL,
        commission_amount REAL NOT NULL,
        status TEXT NOT NULL DEFAULT 'calculated',
        settled_date INTEGER,
        salary_reference TEXT,
        created_at INTEGER NOT NULL,
        UNIQUE(salesman_id, period_from, period_to)
      )
    ''');

    // The settlements list is "this salesman, most recent period first"; the
    // payout screen additionally filters unsettled rows by status.
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_commission_ledger_salesman '
      'ON commission_ledger(salesman_id, period_from)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_commission_ledger_status '
      'ON commission_ledger(status)',
    );
  }
}
