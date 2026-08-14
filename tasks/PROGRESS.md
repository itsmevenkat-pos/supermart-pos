# Phase 1 (General Ledger) — Progress

Cross-run state for the `feature/phase1-gl` branch. See [README.md](README.md)
for the protocol. Update this at the end of every run.

## Status

| # | Task | State |
|---|------|-------|
| 1.1 | [01-gl-schema.md](01-gl-schema.md) — database schema | ✅ Done |
| 1.2 | [02-gl-models-repos.md](02-gl-models-repos.md) — models + repository | ✅ Done |
| 1.3 | [03-gl-service-logic.md](03-gl-service-logic.md) — posting/balance logic | ✅ Done |
| 1.4 | [04-financial-statements.md](04-financial-statements.md) — TB/P&L/Balance Sheet | ✅ Done |
| 1.5 | [05-testing.md](05-testing.md) — consolidation testing | ⬜ Not started |
| 1.6 | [06-documentation.md](06-documentation.md) — docs | ⬜ Not started |

**Next run starts at: Task 1.5 (consolidation / end-to-end testing).**

## Environment notes for the next run

The scheduled container starts with **no Flutter SDK installed** — expect to
spend the first few minutes on this before anything else:

```bash
# ~1.5 GB download, then extraction; both are slow, run them in the background
curl -L -o /home/user/flutter.tar.xz \
  "$(curl -s https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json \
     | python3 -c "import json,sys; d=json.load(sys.stdin); c=d['current_release']['stable']; \
       print(next(d['base_url']+'/'+r['archive'] for r in d['releases'] \
       if r['hash']==c and r['channel']=='stable'))")"
tar -xf /home/user/flutter.tar.xz -C /home/user
git config --global --add safe.directory /home/user/flutter   # required, sessions run as root
export PATH="/home/user/flutter/bin:$PATH"
flutter --disable-analytics && flutter pub get
```

Verified working on **Flutter 3.47.0 stable / Dart 3.13.0**.

Two things `flutter pub get` changes on its own, neither of which belongs in a
GL commit — `git checkout` them before committing:
- `analysis_options.yaml` — it appends an `analyzer: exclude:` block for the
  platform directories. (It re-adds this on every `pub get`/`analyze`.)
- `pubspec.lock` — transitive bumps (`meta`, `matcher`, `vector_math`, …) from
  resolving against a newer SDK than the lockfile was written with.

### Baseline to measure "clean" against

`flutter analyze` is **not** zero on this repo. Record the baseline before
touching anything, then diff, rather than reading the total:

```bash
flutter analyze 2>&1 | grep -E "•" | sort > /tmp/analyze_baseline.txt
# ... make changes ...
flutter analyze 2>&1 | grep -E "•" | sort > /tmp/analyze_after.txt
comm -13 /tmp/analyze_baseline.txt /tmp/analyze_after.txt   # must be empty
```

- Pre-existing baseline: **182 issues, 0 errors** (all `info`/`warning`, all in
  pre-existing `test/` and `lib/` files).
- Pre-existing test suite: **151 tests, all passing.**
- After Task 1.1: 182 issues (**0 new**), **167 tests passing** (+16 new).
- After Task 1.2: 182 issues (**0 new**), **197 tests passing** (+30 new).
- After Task 1.3: 182 issues (**0 new**), **238 tests passing** (+41 new).
- After Task 1.4: 182 issues (**0 new**), **263 tests passing** (+25 new).

Note on comparing analyze output: adding lines to an existing file shifts the
line numbers of every issue below, so a raw `comm` diff shows dozens of
false "new" issues. Compare by file + rule instead:

```bash
norm() { sed -E 's/:[0-9]+:[0-9]+ •/ •/' "$1" | sed -E 's/^ *//' | sort | uniq -c; }
diff <(norm /tmp/analyze_baseline.txt) <(norm /tmp/analyze_after.txt)
```

## Completed work

### Task 1.1 — GL database schema (done)

Files added/changed:
- `lib/core/database/migrations/migration_v28.dart` (new) — `chart_of_accounts`,
  `gl_entries`, `gl_balances`, the five indexes, and `seedDefaultAccounts()`.
- `lib/core/database/database_helper.dart` — `if (oldVersion < 28)` block +
  import.
- `lib/core/database/migrations/migration_v1.dart` — calls `MigrationV28.up()`
  at the end of `up()` + import.
- `lib/constants/app_constants.dart` — `dbVersion` 27 → 28.
- `test/core/database/gl_schema_test.dart` (new) — 16 tests, both migration
  paths.

Decisions and deviations, with reasons:

1. **Migration version 28**, per README's dynamic rule: `AppConstants.dbVersion`
   read as `27` at the start of this run and the highest existing block in
   `database_helper.dart` was `if (oldVersion < 27)`. **Re-check this rule
   again on the next run** — if concurrent work on `main` has since landed a
   v28, the merge will need the GL migration renumbered to whatever is free,
   in `migration_vN.dart`'s name, the `onUpgrade` block, and `dbVersion`.

2. **`MigrationV1` delegates to `MigrationV28.up()` instead of inlining the
   DDL.** This is a deliberate deviation from the file's existing style —
   `migration_v1.dart` is otherwise a hand-maintained copy of the whole current
   schema (36 tables duplicated from their original migrations). Task 1.1
   requires that a fresh `onCreate` database and an upgraded `onUpgrade` one end
   up with *identical* GL schema; a second hand-copied DDL block is exactly how
   that stops being true six months from now. One implementation, called from
   both paths, makes it structurally impossible to drift. The schema test
   asserts the two paths match column-for-column and index-for-index, so if a
   later run reverts to inlining, that test is what will catch the divergence.

3. **`sub_type` is populated on every seeded account**, not left null:
   `current_asset` / `fixed_asset`, `current_liability` /
   `long_term_liability`, `equity`, `operating_revenue` / `other_income`,
   `cogs` / `operating_expense` / `other_expense`. Task 1.4 splits the Balance
   Sheet on exactly this column and separates COGS in the P&L, so these values
   are load-bearing — `FinancialStatementService` must use these same strings.

4. **Deterministic account ids** (`coa_1000`, `coa_1010`, …) rather than UUIDs.
   Seeding has to be idempotent, and the sale/purchase integrations in Task 1.3
   look accounts up by code; a stable id makes both trivial and lets tests
   reference `coa_1000` directly.

5. **`seedDefaultAccounts` lives on `MigrationV28`**, taking a
   `DatabaseExecutor`. Task 1.2 asks for `GLRepository.seedDefaultAccounts()` —
   have it call straight through to this rather than keeping a second copy of
   the account list, so the migration and the repository can never seed
   different charts of accounts.

6. `ON DELETE SET NULL` added to `chart_of_accounts.parent_id`'s self-reference
   (the task's DDL left the action unspecified). `PRAGMA foreign_keys = ON` is
   set on every connection in this app, so an unspecified action would mean
   deleting a parent account is blocked outright; `SET NULL` promotes the
   children to top-level instead, which matches how the rest of the schema
   handles optional parents.

### Task 1.2 — GL models and repository (done)

Files added:
- `lib/models/chart_of_account_model.dart` — `AccountType`, `ChartOfAccount`,
  and the two free functions `isNormallyDebit()` / `signedBalance()`.
- `lib/models/gl_entry_model.dart`, `lib/models/gl_balance_model.dart`.
- `lib/repositories/gl_repository.dart` — accounts, entries, balances,
  `seedDefaultAccounts()`, `glRepositoryProvider`.
- `test/repositories/gl_repository_test.dart` (new) — 30 tests.

Decisions and deviations, with reasons:

1. **The debit/credit-nature rule lives in `chart_of_account_model.dart`**, as
   top-level `isNormallyDebit(AccountType)` and
   `signedBalance(debit, credit, type)` — next to the enum they switch on.
   `GLBalance.normalBalanceNature` delegates there. Tasks 1.3 and 1.4 must
   import these rather than re-deriving the rule; the whole point of one
   definition is that the Trial Balance and the Balance Sheet cannot disagree.

2. **Every repository method takes an optional `DatabaseExecutor? executor`**,
   not just the multi-table ones. Task 1.3 has to post a sale's GL lines inside
   the sale's own transaction; without this the GL write would open a second
   connection and commit independently of the sale it describes. Two tests
   cover it (rollback leaves nothing behind, commit persists both entry and
   balance).

3. **`getAccountByCode()` and `getEntriesByFinancialYear()` added** beyond the
   API the task file lists. The sale/purchase integrations address accounts by
   code ('1000', '4000'), and the financial statements need a year's entries;
   both would otherwise be re-implemented as ad-hoc SQL at the call site.

4. **`recalculateBalance` updates the cached row in place** rather than
   delete-then-insert, so a `gl_balances.id` stays stable. It also loads the
   account to get its `AccountType` — the cached `balance` column is stored in
   the account's natural direction, so it cannot be computed without knowing
   the type.

5. `GLEntry` has a **generative constructor with validation in its body**
   (so it cannot be `const`, unlike the other models here). The invariant is
   worth more than `const`: this is the one place that can stop a malformed
   journal line before it reaches an append-only table.

### Task 1.3 — GL service logic and transaction integration (done)

Files added:
- `lib/services/gl_exceptions.dart` — `GLException` + `AccountNotFound`,
  `UnbalancedEntry`, `ClosedPeriod`, `EntryNotFound`.
- `lib/services/gl_service.dart` — posting, reversal, running balances, the
  sale/purchase/return posting entry points, `glServiceProvider`.
- `test/services/gl_service_test.dart` (new) — 41 tests.

Files changed:
- `lib/repositories/sale_repository.dart`, `purchase_repository.dart`,
  `sales_return_repository.dart` — one GL post each, inside the existing
  transaction.
- `lib/services/financial_year_close_service.dart` — `isFinancialYearClosed`
  gained an optional `executor`.

Decisions and deviations, with reasons:

1. **GL posting is inside the caller's transaction, not best-effort.** Task
   1.3 asked for this to be decided and documented in the PR — this is the
   decision. A sale whose GL post fails now fails as a sale and rolls back
   entirely. The alternative (log and carry on) means the shop keeps the
   customer's money with no ledger record and no one finds out until someone
   reconciles months later. A test posts a sale into a closed financial year
   and asserts that no sale row, no ledger line and no stock deduction
   survive.

2. **The sale's post lives in `sale_repository._insertSaleBody`, not in
   `billing_service.dart`** as the task file's wording suggested. Three
   reasons: that method is where the sale actually becomes final, it already
   owns the transaction, and it is the only place *every* sale passes through
   — `ExchangeRepository` composes its replacement sale by calling
   `insertSaleWithItems` with its own `txn`, so a post added to
   `BillingService.processSale` would silently miss every exchange. The task
   file's own instruction ("find the single right place a completed sale
   becomes final, inside the existing transaction if possible") points here.

3. **A sale's receivable side is `creditUsed + partialPaymentAmount`.** Those
   are the two fields the existing customer-balance update treats as newly
   owed, so using the same pair keeps the GL and the customer ledger telling
   the same story. The remainder is posted to Cash.

4. **Sales returns post a fresh entry rather than reversing the sale's
   lines.** The task file suggested `reverseEntry` per line; that is right for
   a full void but wrong for a partial return, which is the common case —
   reversing the sale's lines reverses the sale's *whole* value, so returning
   two of five items would credit back the entire bill. `postSalesReturnEntries`
   posts the actual `refundAmount` (debit Sales Revenue, credit Cash or
   Accounts Receivable depending on `refundMethod`), which is correct for
   partial and full alike. `reverseEntry` / `reverseByReference` are
   implemented and tested for genuine full voids.

5. **Sale cancellations are not wired up.** Tasks 1.1–1.6 never mention them,
   and `sale_cancellation_repository.dart` is a separate path from returns. A
   cancelled sale therefore still leaves its GL entries standing. This is a
   real gap, deliberately left rather than scope-crept — `reverseByReference`
   already exists and is exactly the right tool, so wiring it is a small
   follow-up. **Worth raising in the PR description.**

6. **`isFinancialYearClosed` gained an optional `executor`.** The closed-year
   check has to run *inside* the sale's transaction; reading through
   `_dbHelper.database` there would issue the query outside the transaction
   and deadlock against it in sqflite. Same `{DatabaseExecutor? executor}`
   convention the ledger repositories already use.

7. **GST is not split out of Sales Revenue.** The whole bill including tax
   credits `4000`, because the default chart of accounts has no output-tax
   liability account. A deliberate Phase 1 simplification, documented on
   `postSaleEntries` — splitting it means adding a tax account and reworking
   the sale split.

8. **`getTrialBalance` is intentionally not on `GLService` yet.** Task 1.3
   says it may delegate to `FinancialStatementService` and that the SQL must
   not be duplicated — so it belongs to Task 1.4, built once there. Add a
   thin delegating method on `GLService` then if it is wanted.

### Task 1.4 — Financial statements (done)

Files added:
- `lib/services/financial_statement_service.dart` — `TrialBalance`,
  `PLStatement`, `BalanceSheet` + their row/section types, and
  `financialStatementServiceProvider`.
- `lib/features/reports/screens/trial_balance_screen.dart`,
  `pl_statement_screen.dart`, `balance_sheet_screen.dart`.
- `lib/features/reports/widgets/financial_statement_shell.dart` — the year
  selector, load/error handling, CSV export and shared statement widgets.
- `test/services/financial_statement_service_test.dart` (new) — 25 tests.

Files changed:
- `lib/features/reports/screens/reports_screen.dart` — a new "Accounts
  (General Ledger)" category under the More Reports tab, registered with the
  same `_reportTile` helper every other report uses.

Decisions and deviations, with reasons:

1. **The statements read `gl_entries`, not the `gl_balances` cache.** One
   indexed `GROUP BY` per statement, and a report can then never show a stale
   figure. It is also the only way the Balance Sheet's `asOf` cut-off can work
   at all, since the cache only knows whole years. All three share
   `_accountTotals`, so there is one piece of SQL behind them.

2. **Typed result classes rather than the `Map<String, dynamic>` that
   `ReportService`/`AdvancedReportService` return.** These statements have real
   structure (sections, per-account lines, `isBalanced`) and the screens
   consume it directly; stringly-typed maps would push that structure into the
   UI as untyped key lookups.

3. **`netProfit` is included in `totalEquity`.** Not a display choice — the
   accounting identity is `Assets = Liabilities + Equity + (Revenue −
   Expenses)`, so leaving the last bracket out would make the statement fail
   to balance. It is shown only; Retained Earnings (`3100`) is deliberately
   never posted to until the year is closed, and a test asserts that account
   stays empty.

4. **COGS reads zero, deliberately and visibly.** Nothing posts to account
   `5000` — Task 1.3's sale integration was cash/receivable against revenue
   only, with no inventory-to-COGS movement. The task file's warning about two
   COGS calculations drifting apart is exactly why this is *not* patched over
   by reading `sale_items.cost_price` the way `ReportService` does. A test
   asserts `cogs == 0` so that adding a COGS posting later fails loudly rather
   than silently changing every P&L. **Worth raising in the PR.**

5. **An asset/liability with an unrecognised `sub_type` is filed as
   current rather than dropped.** A mislabelled asset on the wrong line is a
   labelling problem; a dropped one silently unbalances the statement.

6. **UI verification could not be done by launching the app**, which Task 1.4
   asks for. Three routes were tried:
   - `flutter build linux` — fails, no `gtk+-3.0` in this container.
   - `flutter build web` — fails on **pre-existing** `dart:ffi` usage in
     `lib/services/windows_printer.dart` (plus `win32`/`ffi` packages). This
     app is a Windows/desktop target; a web build was never viable.
   - A widget smoke test pumping the three screens — blocked by a
     **pre-existing** Flutter assertion in `AppScaffold`: `_Sidebar` builds
     `ListTile`s inside a `Container(color: _sidebarBg)`
     (`app_scaffold.dart:112` and `:154`), which throws "ListTile background
     color or ink splashes may be invisible" on every debug render. **This
     affects any widget test of any `AppScaffold`-based screen in this repo,
     not just these three** — worth knowing before anyone tries to add widget
     tests here. Fixing it means wrapping those tiles in their own `Material`,
     which is an app-wide UI change well outside this phase.

   So the screens are verified by `flutter analyze` (they compile clean and
   are wired into `reports_screen.dart` the same way every other report is)
   and by the service tests underneath them — not by a manual run. **Say this
   plainly in the PR rather than implying the UI was exercised.**

## Open questions / notes for later tasks

- **Things the PR description must state** (accumulating as they are decided,
  so the run that opens the PR doesn't have to re-derive them):
  1. GL posting is all-or-nothing inside the sale/purchase/return transaction
     (Task 1.3 asked for this decision to be documented).
  2. Sales returns post the refunded amount rather than reversing the sale's
     lines, so partial returns aren't over-credited.
  3. COGS reads zero until something posts to account `5000`.
  4. Sale cancellations are not wired to the GL.
  5. The report screens were verified by analyze + service tests, not by
     launching the app — see Task 1.4 note 6 for why that wasn't possible.
- `test/core/database/*_test.dart` and
  `test/repositories/product_batch_repository_test.dart` (the file the task
  docs point at as the "real in-memory-DB setup pattern") are actually
  pure-arithmetic tests with no database at all. The genuine real-database
  pattern in this repo is
  `test/services/financial_year_close_service_test.dart` — temp dir +
  `_FakePathProviderPlatform` + `DatabaseHelper.instance`. That is what
  `gl_schema_test.dart` follows, and what later GL tests should follow too.
