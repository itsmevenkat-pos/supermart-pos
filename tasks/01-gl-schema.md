# Task 1.1: General Ledger Database Schema

Read [README.md](README.md) first for conventions and the migration-version
rule — don't skip that, the version number is dynamic, not fixed.

## Overview

Add three tables to support double-entry bookkeeping: an accounts master, a
transaction log, and a balance cache.

## Tables

```sql
CREATE TABLE chart_of_accounts (
  id TEXT PRIMARY KEY,
  code TEXT UNIQUE NOT NULL,
  name TEXT NOT NULL,
  account_type TEXT NOT NULL, -- 'asset' | 'liability' | 'equity' | 'revenue' | 'expense'
  sub_type TEXT,
  parent_id TEXT REFERENCES chart_of_accounts(id),
  is_active INTEGER NOT NULL DEFAULT 1,
  description TEXT,
  opening_balance REAL NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER,
  is_system INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE gl_entries (
  id TEXT PRIMARY KEY,
  entry_date INTEGER NOT NULL,
  reference_type TEXT NOT NULL, -- 'Sale' | 'Purchase' | 'Manual' | 'Return' | ...
  reference_id TEXT,
  description TEXT NOT NULL,
  account_id TEXT NOT NULL REFERENCES chart_of_accounts(id),
  debit REAL NOT NULL DEFAULT 0,
  credit REAL NOT NULL DEFAULT 0,
  financial_year TEXT NOT NULL, -- e.g. "25-26", from financialYearLabel()
  created_by TEXT,
  created_at INTEGER NOT NULL,
  reversal_of_entry_id TEXT REFERENCES gl_entries(id)
);

CREATE TABLE gl_balances (
  id TEXT PRIMARY KEY,
  account_id TEXT NOT NULL REFERENCES chart_of_accounts(id),
  financial_year TEXT NOT NULL,
  total_debit REAL NOT NULL DEFAULT 0,
  total_credit REAL NOT NULL DEFAULT 0,
  balance REAL NOT NULL DEFAULT 0,
  last_updated INTEGER NOT NULL,
  UNIQUE(account_id, financial_year)
);

CREATE INDEX idx_gl_entries_account ON gl_entries(account_id);
CREATE INDEX idx_gl_entries_date ON gl_entries(entry_date);
CREATE INDEX idx_gl_entries_reference ON gl_entries(reference_type, reference_id);
CREATE INDEX idx_chart_of_accounts_code ON chart_of_accounts(code);
CREATE INDEX idx_chart_of_accounts_parent ON chart_of_accounts(parent_id);
```

Notes on the design, deliberately different from a naive version:
- `gl_balances` is keyed by `(account_id, financial_year)`, not just
  `account_id` — this app supports closing financial years
  (`financial_year_close_service.dart`), so each year needs its own cached
  balance, not one running total forever.
- `reversal_of_entry_id` replaces a separate "reversed" flag — lets you
  trace a correction back to the entry it corrects.
- No `UNIQUE(reference_type, reference_id, account_id)` constraint (the
  original draft had one) — a single sale can legitimately post more than
  one line to the same account (e.g. splitting revenue across categories),
  so don't block that.

## Implementation

1. Determine the next migration version per README.md's rule. Add the
   `if (oldVersion < N) { ... }` block to `database_helper.dart`'s
   `onUpgrade`, executing the `CREATE TABLE`/`CREATE INDEX` statements
   above. Bump `AppConstants.dbVersion` to `N`.
2. Seed a default chart of accounts in the same migration (see
   `02-gl-models-repos.md` for the exact account list — seed it here via
   raw `db.insert` calls with `ConflictAlgorithm.ignore`, since the models
   don't exist as Dart classes until Task 1.2).
3. Write `test/core/database/gl_schema_test.dart` following the pattern in
   `test/repositories/product_batch_repository_test.dart` (in-memory DB,
   real migration path) — verify: tables exist, required columns exist, the
   default accounts seeded, and that a duplicate `code` insert throws.

## Done when

- `flutter analyze` clean.
- `flutter test test/core/database/gl_schema_test.dart` passes.
- A fresh DB (`onCreate`) and an upgraded DB (`onUpgrade` from an older
  version) both end up with identical GL schema — test both paths if the
  existing test file for this area already does (check
  `test/core/database/` for the pattern before assuming).
