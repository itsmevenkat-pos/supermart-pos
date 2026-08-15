# Task 2.1: Bank Reconciliation Module

Read [README.md](README.md) first. This one genuinely doesn't exist yet —
confirmed by grep, the only "bank" hits in `lib/` are payment-method strings
and `AdvancedReportService.getBankStatement()`, which is explicitly
documented there as *not* reconciled ("this app has no bank-transaction
import").

## Tables

```sql
CREATE TABLE bank_accounts (
  id TEXT PRIMARY KEY,
  account_number TEXT NOT NULL,
  account_holder TEXT NOT NULL,
  bank_name TEXT NOT NULL,
  opening_balance REAL NOT NULL DEFAULT 0,
  gl_account_id TEXT REFERENCES chart_of_accounts(id),
  reconciled_up_to INTEGER,
  is_active INTEGER NOT NULL DEFAULT 1,
  created_at INTEGER NOT NULL
);

CREATE TABLE bank_statements (
  id TEXT PRIMARY KEY,
  bank_account_id TEXT NOT NULL REFERENCES bank_accounts(id),
  statement_date INTEGER NOT NULL,
  beginning_balance REAL NOT NULL,
  ending_balance REAL NOT NULL,
  import_date INTEGER NOT NULL
);

CREATE TABLE bank_transactions (
  id TEXT PRIMARY KEY,
  bank_statement_id TEXT NOT NULL REFERENCES bank_statements(id),
  transaction_date INTEGER NOT NULL,
  reference TEXT,
  description TEXT,
  amount REAL NOT NULL, -- signed: positive = credit (money in), negative = debit
  matched_gl_entry_id TEXT REFERENCES gl_entries(id),
  match_status TEXT NOT NULL DEFAULT 'unmatched' -- 'unmatched' | 'matched' | 'ignored'
);

CREATE INDEX idx_bank_transactions_statement ON bank_transactions(bank_statement_id);
CREATE INDEX idx_bank_transactions_date ON bank_transactions(transaction_date);
```

`gl_account_id` on `bank_accounts` links to the `chart_of_accounts` row it
reconciles against (typically `1010` Bank, from Phase 1's default seed) —
reconciliation compares this account's `gl_entries` to imported
`bank_transactions`, it doesn't invent a parallel balance concept.

No separate `bank_reconciliations` result table — a reconciliation *is* the
state of `bank_transactions.match_status` plus `bank_accounts.reconciled_up_to`
at a point in time; don't duplicate that as a second table to keep in sync.

## Models / Repository / Service

Follow README.md's conventions (Equatable, `.create()`, `DatabaseHelper.instance`,
provider-at-bottom). `lib/repositories/bank_reconciliation_repository.dart`,
`lib/services/bank_reconciliation_service.dart`.

**CSV import**: `Date,Reference,Description,Amount` (single signed amount
column, not separate debit/credit columns — simpler to match against
`gl_entries`' signed nature). Use whatever CSV package is already a
dependency (check `pubspec.yaml`) before adding a new one.

**Matching algorithm**: date within ±2 days, amount within ±0.01 (exact —
don't use the original draft's ±5% tolerance for amount; a reconciliation
tool that accepts a 5%-off amount as "matched" would hide real errors,
which is the opposite of the point). Match against `gl_entries` for the
linked `gl_account_id`, unmatched-only, in the statement's date range.
Auto-match is a suggestion — leave `match_status = 'unmatched'` for a human
to confirm via `matchTransaction`, don't auto-set `'matched'` without
confirmation for anything but an exact date+amount hit.

## UI

New screens under `lib/features/reports/` or a new `lib/features/banking/`
feature folder (check which existing folders group by "record-keeping
workflow" vs "report" in this codebase before picking) — bank account list,
statement import + transaction matching view, reconciliation summary
(GL balance vs statement balance, variance, unmatched count).

## Tests

`test/repositories/bank_reconciliation_repository_test.dart`,
`test/services/bank_reconciliation_service_test.dart` — follow the real
in-memory-DB pattern from `test/services/financial_year_close_service_test.dart`
(temp dir + `DatabaseHelper.instance`), not the pure-arithmetic style some
other test files use. Cover: CSV parse, exact-match, no-match, and a
reconciliation where GL and statement balances agree vs. where they don't.

## Done when

`flutter analyze` clean, new tests pass, full suite still green.
