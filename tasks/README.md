# Phase 1: General Ledger Module — Execution Guide

This directory replaces an earlier, unusable version of these task files. The
originals assumed a `claude-code` CLI with flags like `--autonomous`,
`--auto-commit`, and a `claude-code schedule` command — **none of that
exists**. If you are an autonomous agent reading this, you ARE the execution
mechanism; there is no separate tool to invoke. Just do the work described
below, using your normal file/shell tools, and commit/push with plain `git`.

## Progress tracking across runs

You may be resumed multiple times (a scheduled routine fires periodically,
each firing is its own bounded session — not one continuous 8-hour run).
State is tracked in **`tasks/PROGRESS.md`** (create it on your first run if
missing). At the start of every run:

1. `git pull` (or fetch+merge) the latest `feature/phase1-gl` branch — if it
   doesn't exist yet, create it from `main`.
2. Read `tasks/PROGRESS.md` to see which of the 6 tasks below are already
   marked done, and any notes left for the next run.
3. Do the next incomplete task (or continue a partially-done one — check
   what already compiles/exists before redoing work).
4. Run `flutter analyze` and the relevant test files before committing.
5. Commit with a clear message, update `tasks/PROGRESS.md`, commit that too,
   and `git push`.
6. If you completed Task 6 (Documentation) and everything is green, open a
   PR from `feature/phase1-gl` into `main` (via `gh pr create` if the `gh`
   CLI is available) and stop.

Never work directly on `main`. `main` may receive unrelated commits from
other concurrent work while you're running — always rebase/merge those in
rather than overwriting them.

## Task order (strict dependency chain)

1. [01-gl-schema.md](01-gl-schema.md) — database schema
2. [02-gl-models-repos.md](02-gl-models-repos.md) — models + repository
3. [03-gl-service-logic.md](03-gl-service-logic.md) — posting/balance logic
4. [04-financial-statements.md](04-financial-statements.md) — TB/P&L/Balance Sheet
5. [05-testing.md](05-testing.md) — test coverage
6. [06-documentation.md](06-documentation.md) — docs

## Codebase conventions — read this before writing any code

This is a Flutter/Dart app using `sqflite` directly (no ORM) and
`flutter_riverpod`. Match these exactly — do not invent a different style:

**Models** (see `lib/models/stock_group_model.dart` for a real example):
- `extends Equatable`, plain final fields, no `copyWith` unless genuinely
  needed.
- `factory Foo.create({...})` generates a new instance with `Uuid().v4()`
  for the id — don't put ID generation in the repository.
- `toJson()` / `factory Foo.fromJson(Map<String, dynamic> map)` for sqflite
  row mapping (snake_case keys), not general JSON serialization.

**Repositories** (see `lib/repositories/stock_group_repository.dart`):
- Plain class, constructor `Repo({DatabaseHelper? dbHelper}) : _dbHelper =
  dbHelper ?? DatabaseHelper.instance`.
- No repository interfaces/abstract base classes — this codebase doesn't use
  that pattern.
- Multi-table writes go through `db.transaction((txn) async { ... })`.
- Expose a `final fooRepositoryProvider = Provider<FooRepository>((ref) =>
  FooRepository());` at the bottom of the file.

**Services** (see `lib/services/financial_year_close_service.dart`):
- Same constructor pattern as repositories.
- Business logic and validation lives here, not in the repository.

**Database migrations** — this is the part the original task files got
wrong and it will cause a real conflict if not followed:
- There is **no per-file-per-version migration runner**. Versioned changes
  live as `if (oldVersion < N) { ... }` blocks inside
  `lib/core/database/database_helper.dart`'s `onUpgrade`, in strictly
  ascending order. Larger/reusable ones additionally get a
  `lib/core/database/migrations/migration_vN.dart` file with a static
  `up(db)` method that the `onUpgrade` block calls.
- **Do not hardcode a migration version number.** Before writing your
  migration, open `lib/constants/app_constants.dart`, read the current
  `dbVersion`, and check the highest existing `if (oldVersion < N)` block in
  `database_helper.dart` — use `N = current dbVersion + 1`. This codebase has
  concurrent development happening on it; the version that was free when
  these task docs were written will very likely not be free by the time you
  run. Re-check every time, including on resume.
- Every `ALTER TABLE ... ADD COLUMN` on an existing table should be wrapped
  in `try { } catch (_) { }` (see existing migrations) since `onUpgrade` can
  run against databases at different starting versions.
- Bump `AppConstants.dbVersion` to your new N as part of the same commit.

**Financial year format**: this app uses short two-digit-two-digit labels
like `"25-26"` (1 April – 31 March), produced by
`lib/core/utils/financial_year.dart`'s `financialYearLabel(DateTime)` — use
that function, don't invent a `"2025-2026"` format.

**Existing accounting-adjacent code — read before writing anything new**,
to avoid duplicating or conflicting with it:
- `lib/services/financial_year_close_service.dart` — already locks a
  financial year via a `financial_year_closures` table once closed
  (one-way, no reopen). Your GL entry posting must check
  `isFinancialYearClosed()` before posting and refuse if closed (this is
  the real implementation of the "ClosedPeriod" exception the design below
  describes).
- `lib/services/report_service.dart`, `lib/services/advanced_report_service.dart`
  — existing reporting infrastructure. Don't build a parallel reporting
  system; see if the new Trial Balance / P&L / Balance Sheet reports can
  register into the existing reports screen (`lib/features/reports/screens/reports_screen.dart`)
  the way other reports do.
- `lib/services/tally_xml_service.dart` — exports to Tally (an accounting
  package) already. Worth a skim so the new Chart of Accounts doesn't end up
  incompatible with whatever account structure that export already assumes.

**Testing**: this project uses `flutter_test`, tests live under `test/`
mirroring the `lib/` structure. Look at
`test/repositories/product_batch_repository_test.dart` and
`test/services/financial_year_close_service_test.dart` for the real
in-memory-DB setup pattern used here before writing new test files.

## What "done" means for this phase

Don't chase the original files' "90% coverage" / hour estimates literally —
those numbers were invented without seeing this codebase. Instead:
- `flutter analyze` is clean (no new warnings/errors).
- New GL entry posting is provably double-entry (a compound post with
  unbalanced debit/credit throws before touching the DB).
- Trial Balance totals debits == totals credits for any posted data.
- Balance Sheet: Assets == Liabilities + Equity for any posted data.
- Existing tests still pass — run the full suite, not just new GL tests,
  before opening the PR.
