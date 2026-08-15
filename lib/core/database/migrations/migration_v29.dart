import 'package:sqflite/sqflite.dart';

/// Bank reconciliation (Phase 2): imported bank statements matched against the
/// General Ledger.
///
/// Three tables — a bank-account master (`bank_accounts`), one row per imported
/// statement (`bank_statements`), and the statement's individual lines
/// (`bank_transactions`).
///
/// Design points worth knowing before changing anything here:
/// - **There is no `bank_reconciliations` result table.** A reconciliation is
///   not a document, it is a *state*: the `match_status` of the transactions in
///   range plus `bank_accounts.reconciled_up_to`. Storing the outcome a second
///   time would mean two sources of truth that drift the moment somebody
///   unmatches a line after the "reconciliation" was saved.
/// - **`bank_accounts.gl_account_id` points at the `chart_of_accounts` row this
///   account reconciles against** (typically `1010` Bank from the Phase 1
///   seed). Reconciliation compares that account's `gl_entries` to the imported
///   `bank_transactions`; it deliberately does not invent a parallel balance
///   concept that could disagree with the ledger.
/// - **`bank_transactions.amount` is signed** — positive is money into the
///   account (a credit on the statement, a *debit* to the asset account in
///   double-entry terms), negative is money out. A single signed column matches
///   how a real bank CSV exports and keeps the matching arithmetic to one
///   comparison instead of a debit/credit case split.
///
/// Like [MigrationV28], this runs from both paths — `onUpgrade`
/// (`oldVersion < 29`) and `onCreate` (via `MigrationV1`, which delegates here)
/// — so a fresh install and an upgraded database end up with identical schema.
class MigrationV29 {
  static Future<void> up(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS bank_accounts (
        id TEXT PRIMARY KEY,
        account_number TEXT NOT NULL,
        account_holder TEXT NOT NULL,
        bank_name TEXT NOT NULL,
        opening_balance REAL NOT NULL DEFAULT 0,
        gl_account_id TEXT REFERENCES chart_of_accounts(id),
        reconciled_up_to INTEGER,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS bank_statements (
        id TEXT PRIMARY KEY,
        bank_account_id TEXT NOT NULL REFERENCES bank_accounts(id),
        statement_date INTEGER NOT NULL,
        beginning_balance REAL NOT NULL,
        ending_balance REAL NOT NULL,
        import_date INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS bank_transactions (
        id TEXT PRIMARY KEY,
        bank_statement_id TEXT NOT NULL REFERENCES bank_statements(id),
        transaction_date INTEGER NOT NULL,
        reference TEXT,
        description TEXT,
        amount REAL NOT NULL,
        matched_gl_entry_id TEXT REFERENCES gl_entries(id),
        match_status TEXT NOT NULL DEFAULT 'unmatched'
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_bank_transactions_statement ON bank_transactions(bank_statement_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_bank_transactions_date ON bank_transactions(transaction_date)',
    );
    // Not in the task file's DDL, but every reconciliation query filters by
    // account: statements-for-account and the unmatched-count summary both
    // start here.
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_bank_statements_account ON bank_statements(bank_account_id)',
    );
  }
}
