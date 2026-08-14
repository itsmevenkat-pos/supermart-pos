# Phase 1 (General Ledger) — Progress

Cross-run state for the `feature/phase1-gl` branch. See [README.md](README.md)
for the protocol. Update this at the end of every run.

## Status

| # | Task | State |
|---|------|-------|
| 1.1 | [01-gl-schema.md](01-gl-schema.md) — database schema | ✅ Done |
| 1.2 | [02-gl-models-repos.md](02-gl-models-repos.md) — models + repository | ⬜ Not started |
| 1.3 | [03-gl-service-logic.md](03-gl-service-logic.md) — posting/balance logic | ⬜ Not started |
| 1.4 | [04-financial-statements.md](04-financial-statements.md) — TB/P&L/Balance Sheet | ⬜ Not started |
| 1.5 | [05-testing.md](05-testing.md) — consolidation testing | ⬜ Not started |
| 1.6 | [06-documentation.md](06-documentation.md) — docs | ⬜ Not started |

**Next run starts at: Task 1.2 (models + repository).**

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

## Open questions / notes for later tasks

- **Task 1.3, GL posting inside vs. alongside the sale transaction.** The task
  file asks for this to be decided and documented in the PR. Not yet decided —
  read `billing_service.dart` and `purchase_repository.dart` first. The README
  points at `stock_group_repository.dart`'s `propagateDelta(executor:)` as the
  existing "side-effect inside the caller's transaction" pattern, and
  `GLRepository`/`GLService` will likely need the same optional
  `DatabaseExecutor? executor` parameter to participate in the sale's
  transaction rather than opening its own.
- **Task 1.4 UI verification.** That task says to verify the three new report
  screens by actually launching the app. This container is headless with no
  Linux desktop toolchain configured, so `flutter run -d linux` is unlikely to
  work. Plan to verify by compilation + widget tests and say so explicitly in
  the PR rather than claiming a manual run that did not happen.
- `test/core/database/*_test.dart` and
  `test/repositories/product_batch_repository_test.dart` (the file the task
  docs point at as the "real in-memory-DB setup pattern") are actually
  pure-arithmetic tests with no database at all. The genuine real-database
  pattern in this repo is
  `test/services/financial_year_close_service_test.dart` — temp dir +
  `_FakePathProviderPlatform` + `DatabaseHelper.instance`. That is what
  `gl_schema_test.dart` follows, and what later GL tests should follow too.
