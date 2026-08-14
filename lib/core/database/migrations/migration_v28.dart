import 'package:sqflite/sqflite.dart';

/// General Ledger (Phase 1): double-entry bookkeeping tables.
///
/// Three tables — an accounts master (`chart_of_accounts`), an append-only
/// transaction log (`gl_entries`), and a per-financial-year balance cache
/// (`gl_balances`).
///
/// Two deliberate design points worth knowing before changing anything here:
/// - `gl_balances` is keyed by `(account_id, financial_year)`, not by account
///   alone. This app closes financial years (`FinancialYearCloseService`), so
///   each year needs its own cached balance rather than one running total that
///   never resets.
/// - `gl_entries` carries `reversal_of_entry_id` instead of a "reversed" flag,
///   so a correction can be traced back to the entry it corrects and the
///   original is never mutated or deleted.
///
/// There is deliberately NO `UNIQUE(reference_type, reference_id, account_id)`
/// constraint: one sale can legitimately post several lines to the same
/// account (e.g. revenue split across categories).
///
/// This runs from both migration paths — `onUpgrade` (`oldVersion < 28`) and
/// `onCreate` (via [MigrationV1], which delegates here rather than inlining a
/// second copy of the DDL) — so a freshly created database and an upgraded one
/// end up with byte-identical GL schema and the same seeded accounts.
class MigrationV28 {
  static Future<void> up(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS chart_of_accounts (
        id TEXT PRIMARY KEY,
        code TEXT UNIQUE NOT NULL,
        name TEXT NOT NULL,
        account_type TEXT NOT NULL,
        sub_type TEXT,
        parent_id TEXT REFERENCES chart_of_accounts(id) ON DELETE SET NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        description TEXT,
        opening_balance REAL NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER,
        is_system INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS gl_entries (
        id TEXT PRIMARY KEY,
        entry_date INTEGER NOT NULL,
        reference_type TEXT NOT NULL,
        reference_id TEXT,
        description TEXT NOT NULL,
        account_id TEXT NOT NULL REFERENCES chart_of_accounts(id),
        debit REAL NOT NULL DEFAULT 0,
        credit REAL NOT NULL DEFAULT 0,
        financial_year TEXT NOT NULL,
        created_by TEXT,
        created_at INTEGER NOT NULL,
        reversal_of_entry_id TEXT REFERENCES gl_entries(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS gl_balances (
        id TEXT PRIMARY KEY,
        account_id TEXT NOT NULL REFERENCES chart_of_accounts(id),
        financial_year TEXT NOT NULL,
        total_debit REAL NOT NULL DEFAULT 0,
        total_credit REAL NOT NULL DEFAULT 0,
        balance REAL NOT NULL DEFAULT 0,
        last_updated INTEGER NOT NULL,
        UNIQUE(account_id, financial_year)
      )
    ''');

    await db.execute('CREATE INDEX IF NOT EXISTS idx_gl_entries_account ON gl_entries(account_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_gl_entries_date ON gl_entries(entry_date)');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_gl_entries_reference ON gl_entries(reference_type, reference_id)',
    );
    await db.execute('CREATE INDEX IF NOT EXISTS idx_chart_of_accounts_code ON chart_of_accounts(code)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_chart_of_accounts_parent ON chart_of_accounts(parent_id)');

    await seedDefaultAccounts(db);
  }

  /// Inserts the default chart of accounts. Idempotent — every row has a
  /// deterministic id and a UNIQUE `code`, and `ConflictAlgorithm.ignore`
  /// means a second call leaves the existing rows (including any edits a user
  /// made to their names) untouched instead of duplicating or overwriting.
  ///
  /// `GLRepository.seedDefaultAccounts()` calls straight through to this, so
  /// the migration and the repository can never seed different account lists.
  static Future<void> seedDefaultAccounts(DatabaseExecutor db) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    for (final account in defaultAccounts) {
      await db.insert(
        'chart_of_accounts',
        {...account, 'created_at': now},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  /// The seeded accounts. `is_system` marks them undeletable by the UI (they
  /// can still be deactivated), because the posting code in `GLService` and
  /// the sale/purchase integrations look accounts up by these exact codes.
  ///
  /// `sub_type` is what the Balance Sheet splits on (current vs. fixed assets,
  /// current vs. long-term liabilities) and what the P&L uses to separate COGS
  /// from other expenses — so it is not free-text decoration, keep the values
  /// consistent with `FinancialStatementService`.
  static const List<Map<String, Object?>> defaultAccounts = [
    // Assets
    {'id': 'coa_1000', 'code': '1000', 'name': 'Cash', 'account_type': 'asset', 'sub_type': 'current_asset', 'is_system': 1},
    {'id': 'coa_1010', 'code': '1010', 'name': 'Bank', 'account_type': 'asset', 'sub_type': 'current_asset', 'is_system': 1},
    {
      'id': 'coa_1100',
      'code': '1100',
      'name': 'Accounts Receivable',
      'account_type': 'asset',
      'sub_type': 'current_asset',
      'is_system': 1,
    },
    {'id': 'coa_1200', 'code': '1200', 'name': 'Inventory', 'account_type': 'asset', 'sub_type': 'current_asset', 'is_system': 1},
    {'id': 'coa_1500', 'code': '1500', 'name': 'Fixed Assets', 'account_type': 'asset', 'sub_type': 'fixed_asset', 'is_system': 1},

    // Liabilities
    {
      'id': 'coa_2000',
      'code': '2000',
      'name': 'Accounts Payable',
      'account_type': 'liability',
      'sub_type': 'current_liability',
      'is_system': 1,
    },
    {
      'id': 'coa_2010',
      'code': '2010',
      'name': 'Credit Card',
      'account_type': 'liability',
      'sub_type': 'current_liability',
      'is_system': 1,
    },
    {
      'id': 'coa_2100',
      'code': '2100',
      'name': 'Short-term Loans',
      'account_type': 'liability',
      'sub_type': 'current_liability',
      'is_system': 1,
    },
    {
      'id': 'coa_2200',
      'code': '2200',
      'name': 'Long-term Loans',
      'account_type': 'liability',
      'sub_type': 'long_term_liability',
      'is_system': 1,
    },

    // Equity
    {'id': 'coa_3000', 'code': '3000', 'name': 'Capital', 'account_type': 'equity', 'sub_type': 'equity', 'is_system': 1},
    {
      'id': 'coa_3100',
      'code': '3100',
      'name': 'Retained Earnings',
      'account_type': 'equity',
      'sub_type': 'equity',
      'is_system': 1,
    },

    // Revenue
    {
      'id': 'coa_4000',
      'code': '4000',
      'name': 'Sales Revenue',
      'account_type': 'revenue',
      'sub_type': 'operating_revenue',
      'is_system': 1,
    },
    {
      'id': 'coa_4100',
      'code': '4100',
      'name': 'Service Revenue',
      'account_type': 'revenue',
      'sub_type': 'operating_revenue',
      'is_system': 1,
    },
    {
      'id': 'coa_4900',
      'code': '4900',
      'name': 'Other Income',
      'account_type': 'revenue',
      'sub_type': 'other_income',
      'is_system': 1,
    },

    // Expenses
    {
      'id': 'coa_5000',
      'code': '5000',
      'name': 'Cost of Goods Sold',
      'account_type': 'expense',
      'sub_type': 'cogs',
      'is_system': 1,
    },
    {
      'id': 'coa_5100',
      'code': '5100',
      'name': 'Salaries & Wages',
      'account_type': 'expense',
      'sub_type': 'operating_expense',
      'is_system': 1,
    },
    {'id': 'coa_5200', 'code': '5200', 'name': 'Rent', 'account_type': 'expense', 'sub_type': 'operating_expense', 'is_system': 1},
    {
      'id': 'coa_5300',
      'code': '5300',
      'name': 'Utilities',
      'account_type': 'expense',
      'sub_type': 'operating_expense',
      'is_system': 1,
    },
    {
      'id': 'coa_5400',
      'code': '5400',
      'name': 'Depreciation',
      'account_type': 'expense',
      'sub_type': 'operating_expense',
      'is_system': 1,
    },
    {
      'id': 'coa_5500',
      'code': '5500',
      'name': 'Interest Expense',
      'account_type': 'expense',
      'sub_type': 'other_expense',
      'is_system': 1,
    },
  ];
}
