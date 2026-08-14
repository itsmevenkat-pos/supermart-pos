# General Ledger — Architecture

Phase 1 of the accounting module: a double-entry general ledger that records
every sale, purchase and sales return as balanced journal entries, and reports
on them as a Trial Balance, Profit & Loss and Balance Sheet.

This describes **what was actually built**, including the places where the
implementation deliberately diverges from the original Phase 1 task notes.
Where it does, the reason is given — those are the parts most likely to look
like mistakes later.

## Schema

Three tables, added by `lib/core/database/migrations/migration_v28.dart` at
`AppConstants.dbVersion` 28.

### `chart_of_accounts`

The accounts master. `code` is unique and is how the rest of the app addresses
an account (`'1000'`, `'4000'`) — a code is stable and readable where a uuid is
neither.

| Column | Notes |
|---|---|
| `id` | text primary key |
| `code` | unique; the app's real handle on an account |
| `name`, `description` | free text, user-editable |
| `account_type` | `asset` / `liability` / `equity` / `revenue` / `expense` |
| `sub_type` | load-bearing — see below |
| `parent_id` | self-reference, `ON DELETE SET NULL` |
| `is_active` | accounts are deactivated, never deleted |
| `opening_balance` | reserved; nothing writes it yet |
| `is_system` | seeded accounts, which the UI must not offer to delete |

`sub_type` is **not decoration**. The Balance Sheet splits on it and the P&L
uses it to reason about expense classes, so its values are part of the
contract between the migration and `FinancialStatementService`:

- assets — `current_asset`, `fixed_asset`
- liabilities — `current_liability`, `long_term_liability`
- equity — `equity`
- revenue — `operating_revenue`, `other_income`
- expenses — `cogs`, `operating_expense`, `other_expense`

An asset or liability whose `sub_type` isn't recognised is filed as *current*
rather than dropped: a mislabelled asset on the wrong line is a labelling
problem, a dropped one silently unbalances the statement.

### `gl_entries`

The journal. **Append-only** — nothing updates or deletes a posted row.
Corrections are reversals (see below).

Each row is one side of a transaction: exactly one of `debit` / `credit` is
positive and the other is exactly zero. `GLEntry`'s constructor throws
`ArgumentError` on a two-sided, zero or negative line, so a malformed line
cannot reach the table even via the repository.

`reversal_of_entry_id` points at the entry a reversal corrects — chosen over a
"reversed" boolean so a correction can be traced back to its original.

There is deliberately **no** `UNIQUE(reference_type, reference_id, account_id)`
constraint: one sale can legitimately post several lines to the same account,
e.g. revenue split across categories.

### `gl_balances`

A cache of debit/credit totals, keyed `UNIQUE(account_id, financial_year)` —
per year, not one running total forever, because this app closes financial
years and each year's books stand on their own.

Entirely derived: `GLRepository.recalculateBalance` is the only writer, and it
re-sums `gl_entries` from scratch. A wrong balance is therefore always fixable
by recalculating, never by editing the number.

### Both migration paths

`MigrationV1` (which `onCreate` runs for a fresh install) calls
`MigrationV28.up()` rather than inlining a second copy of the DDL, even though
`migration_v1.dart` otherwise duplicates every other table from its original
migration. A fresh database and one upgraded from v27 must end up with
identical GL schema, and a hand-copied second DDL block is exactly how that
stops being true over time. `test/core/database/gl_schema_test.dart` asserts
the two paths match column-for-column and index-for-index.

## Classes

| Layer | File | Responsibility |
|---|---|---|
| Models | `lib/models/chart_of_account_model.dart` | `AccountType`, `ChartOfAccount`, and the debit/credit-nature rule |
| | `lib/models/gl_entry_model.dart` | `GLEntry` + its one-sided-line invariant |
| | `lib/models/gl_balance_model.dart` | `GLBalance` |
| Repository | `lib/repositories/gl_repository.dart` | Storage only — no rules |
| Service | `lib/services/gl_service.dart` | Posting rules, reversal, running balances |
| | `lib/services/gl_exceptions.dart` | `AccountNotFound`, `UnbalancedEntry`, `ClosedPeriod`, `EntryNotFound` |
| Reports | `lib/services/financial_statement_service.dart` | Trial Balance, P&L, Balance Sheet (read-only) |
| Screens | `lib/features/reports/screens/{trial_balance,pl_statement,balance_sheet}_screen.dart` | |
| | `lib/features/reports/widgets/financial_statement_shell.dart` | Year selector, load/error handling, CSV export |

### One definition of debit/credit nature

`isNormallyDebit(AccountType)` and `signedBalance(debit, credit, type)` are
top-level functions in `chart_of_account_model.dart`. Assets and expenses
increase on the debit side; the other three increase on the credit side.

Everything routes through these — `GLBalance.normalBalanceNature`,
`GLService.getRunningBalance`, `FinancialStatementService`. Do not re-derive
the rule anywhere: two copies that drift apart produce a Trial Balance that
balances next to a Balance Sheet that does not, with nothing obviously wrong
in either.

### The three invariants `GLService` enforces

1. **Compound entries balance.** `postCompoundEntry` takes a map of account id
   to signed amount (positive = debit, negative = credit), sums both sides and
   throws `UnbalancedEntry` **before the first insert** if they differ by more
   than 0.01. An unbalanced entry never lands, not even partially.
2. **Nothing posts into a closed year.** Checked against
   `FinancialYearCloseService.isFinancialYearClosed` before every post.
3. **Corrections are reversals.** `reverseEntry` posts the mirror image — same
   account, same amount, opposite side, `reversal_of_entry_id` set — and never
   touches the original. `reverseByReference` does this for every line of one
   document and skips already-reversed lines, so reversing twice is a no-op
   rather than a double swing.

## Integration with sales, purchases and returns

Every GL post happens **inside the caller's own database transaction**, via the
optional `DatabaseExecutor executor` parameter that every repository and
service method accepts — the same "side effect inside the caller's
transaction" pattern `StockGroupRepository.propagateDelta` already uses.

This is all-or-nothing by design. A sale whose ledger post fails — a closed
financial year, a missing chart of accounts — **fails as a sale** and rolls
back completely. The alternative (log the failure, let the sale through) means
the shop keeps the customer's money with no ledger record and nobody finds out
until someone reconciles months later.

| Event | Where | Entry |
|---|---|---|
| Sale | `sale_repository.dart` `_insertSaleBody` | Dr Cash `1000` (settled at the till) · Dr Accounts Receivable `1100` (still owed) · Cr Sales Revenue `4000` (full bill) |
| Purchase | `purchase_repository.dart` `insertWithItems` | Dr Inventory `1200` · Cr Accounts Payable `2000` |
| Sales return | `sales_return_repository.dart` `_insertReturnBody` | Dr Sales Revenue `4000` · Cr Cash `1000`, or Accounts Receivable `1100` when `refundMethod == 'credit_adjust'` |

The receivable side of a sale is `creditUsed + partialPaymentAmount` — the same
two fields the existing customer-balance update treats as newly owed, so the
GL and the customer ledger tell the same story.

### Why the sale posts from the repository, not `BillingService`

The original task notes suggested `billing_service.dart`. The post lives in
`SaleRepository._insertSaleBody` instead because that is where a sale actually
becomes final, it already owns the transaction, and it is the only place every
sale passes through — `ExchangeRepository` composes its replacement sale by
calling `insertSaleWithItems` with its own `txn`, so a post added to
`BillingService.processSale` would silently miss every exchange.

### Why a return posts a new entry instead of reversing the sale

The original notes suggested reversing the sale's lines. That is correct for a
full void but wrong for a partial return, which is the common case: reversing
the sale's lines reverses the sale's *whole* value, so returning two of five
items would credit back the entire bill. `postSalesReturnEntries` posts the
actual `refundAmount`, which is correct for partial and full alike.
`reverseEntry` / `reverseByReference` remain available for genuine full voids.

## Financial statements

`FinancialStatementService` is **strictly read-only**. It never writes, and it
reads `gl_entries` directly rather than the `gl_balances` cache — one indexed
`GROUP BY` per statement, so a report can never show a stale number, and it is
what makes the Balance Sheet's optional `asOf` cut-off possible at all, since
the cache only knows whole years. All three statements share one private
`_accountTotals` query, so they cannot disagree about an account's balance.

**Trial Balance** — every active account's net balance in a debit or a credit
column, plus both totals and `isBalanced`. Because every posted entry balances,
the two columns are equal unless something bypassed `GLService`.

**Profit & Loss** — revenue, COGS (broken out by account `5000`), other
expenses, gross profit, net profit.

**Balance Sheet** — assets (current / fixed), liabilities (current /
long-term), equity, and `isBalanced`.

It balances by construction rather than by luck. Every posted entry has equal
debits and credits, so summing debit-minus-credit across all accounts is zero,
which rearranges to:

```
Assets = Liabilities + Equity + (Revenue − Expenses)
```

That last bracket is the year's net profit, which is why `totalEquity` includes
it — and why omitting it would make the statement fail to balance. It is shown
only. Retained Earnings (`3100`) is **not** posted to until the year is closed.

### Known limitation: COGS reads zero

Nothing currently posts to account `5000`. The sale integration was scoped as
cash/receivable against revenue, with no matching inventory-to-COGS movement,
so `cogs` is 0 and gross profit equals revenue.

This is a **missing posting, not a missing calculation**, and it is left
visible on purpose. `ReportService` already computes a COGS figure from
`sale_items.cost_price`, and reading that here would paper over the gap — two
independent COGS figures that can drift apart is a worse problem than one
that is visibly zero. A test asserts `cogs == 0` so that adding a COGS posting
later fails loudly instead of changing every P&L in silence.

### Diagnostics, not just summaries

All three statements report a broken ledger rather than crashing on one. A
one-sided entry written behind `GLService`'s back surfaces as
`isBalanced == false` with the exact discrepancy, and the screens show it as a
red banner.

## Not yet wired

- **Sale cancellations** (`sale_cancellation_repository.dart`) do not post to
  the GL, so a cancelled sale leaves its entries standing.
  `reverseByReference` is exactly the right tool; it just isn't called yet.
- **GST is not split out.** The whole bill including tax credits Sales Revenue,
  because the default chart has no output-tax liability account.
- **`opening_balance`** on `chart_of_accounts` is stored but never read.

## Tests

| File | Covers |
|---|---|
| `test/core/database/gl_schema_test.dart` | Schema on both migration paths, seeding idempotence |
| `test/repositories/gl_repository_test.dart` | Account CRUD, entries, balances, transaction participation |
| `test/services/gl_service_test.dart` | Posting rules, reversals, closed periods, the real sale path through `BillingService` |
| `test/services/financial_statement_service_test.dart` | All three statements, including deliberately broken ledgers |
| `test/integration/gl_end_to_end_test.dart` | One full sale → purchase → return → reversal → year-close cycle |
