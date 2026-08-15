# Phase 2 (Enterprise Features) — Progress

Cross-run state for the `feature/phase2-enterprise` branch. See
[README.md](README.md) for what differs from Phase 1, and
[../README.md](../README.md) for the conventions that still apply.
Update this at the end of every run.

## Status

| # | Task | State |
|---|------|-------|
| 2.1 | [01-bank-reconciliation.md](01-bank-reconciliation.md) — bank reconciliation | ✅ Done |
| 2.2 | [02-loyalty-points.md](02-loyalty-points.md) — loyalty gap-closing | ⬜ Not started |
| 2.3 | [03-payment-gateways.md](03-payment-gateways.md) — payment gateways | ⬜ Not started |
| 2.4 | [04-collections-commission.md](04-collections-commission.md) — collections/commission | ⬜ Not started |

These four are largely independent — do the next one fresh, there is no
dependency chain to respect. **One module per run, fully**, not four started.

## Environment notes for the next run

Unchanged from Phase 1: the scheduled container starts with **no Flutter SDK**.
The install recipe in [../PROGRESS.md](../PROGRESS.md) still works verbatim —
`curl` the current stable release JSON, extract to `/home/user/flutter`,
`git config --global --add safe.directory /home/user/flutter`, then
`flutter pub get`.

Two timing notes that cost this run a few minutes:
- The download and the `tar -xf` are **both** slow (~20s download, several
  minutes to extract). `flutter --version` exiting non-zero with
  `internal/shared.sh: No such file or directory` means extraction is still
  running, not that the install failed — wait for the tar, don't re-download.
- Don't launch `flutter analyze` for a baseline until extraction has finished
  *and* `pub get` has run, or it silently produces an empty issue list.

Verified working this run on **Flutter 3.47.0 stable / Dart 3.13.0** — same as
Phase 1 recorded.

`flutter pub get` still rewrites two files that must **not** be committed —
`git checkout --` them before every commit:
- `analysis_options.yaml` (appends an `analyzer: exclude:` block)
- `pubspec.lock` (transitive bumps from resolving against a newer SDK)

### Baseline, re-measured this run

Phase 1's numbers still hold for analyze; the test count has grown.

- `flutter analyze`: **182 issues, 0 errors** — identical to Phase 1's baseline.
- `flutter test`: **264 passing** at the start of this run.
- After Task 2.1: **182 issues (0 new)**, **308 passing** (+44 new).

Compare analyze by file + rule, not raw line, since inserting lines shifts
every issue below them:

```bash
norm() { sed -E 's/:[0-9]+:[0-9]+ •/ •/' "$1" | sed -E 's/^ *//' | sort | uniq -c; }
diff <(norm /tmp/analyze_baseline.txt) <(norm /tmp/analyze_after.txt)
```

### Migration version — read fresh, every run

At the start of this run `AppConstants.dbVersion` was **28** and the highest
`if (oldVersion < N)` block was 28, so Task 2.1 took **v29**. Both are now
**29**. The next migration takes **30 — unless** another automation has landed
one on `main` in the meantime, so re-check both places before writing a line
of DDL. Do not trust this paragraph over the source.

## Completed work

### Task 2.1 — Bank reconciliation (done)

Files added:
- `lib/core/database/migrations/migration_v29.dart` — the three tables + three
  indexes.
- `lib/models/bank_account_model.dart`, `bank_statement_model.dart`,
  `bank_transaction_model.dart` (the latter also holds the `BankMatchStatus`
  enum).
- `lib/repositories/bank_reconciliation_repository.dart`
- `lib/services/bank_reconciliation_service.dart`,
  `bank_reconciliation_exceptions.dart`
- `lib/features/banking/screens/bank_account_list_screen.dart`,
  `bank_reconciliation_screen.dart`
- `test/repositories/bank_reconciliation_repository_test.dart` (13 tests),
  `test/services/bank_reconciliation_service_test.dart` (31 tests)

Files changed:
- `lib/core/database/database_helper.dart` — `if (oldVersion < 29)` block + import.
- `lib/core/database/migrations/migration_v1.dart` — calls `MigrationV29.up()` + import.
- `lib/constants/app_constants.dart` — `dbVersion` 28 → 29.
- `lib/core/routes/app_router.dart` — `/banking` and `/banking/reconcile` routes
  + role gate.
- `lib/core/widgets/app_scaffold.dart` — "Bank Accounts" sidebar tile.
- `test/core/database/gl_schema_test.dart` — see deviation 5 below.

Decisions and deviations, with reasons:

1. **Migration version 29**, per the dynamic rule. Re-check before the next
   migration; see the section above.

2. **Amount tolerance is ±0.01, not the original draft's ±5%.** The task file
   already called for this and it is worth restating: a reconciliation tool
   that accepts a 5%-off amount as a match hides the exact class of error it
   exists to find. Dates keep ±2 days of slack because banks genuinely post
   late; amounts get one paisa of floating-point slack and nothing else.

3. **`ignored` clears `matched_gl_entry_id`.** The task file lists the three
   statuses but not their interaction. An ignored line that still pointed at a
   ledger entry would keep that entry out of the candidate pool for no reason,
   so the repository clears the link in the same write. Ignored lines still
   count toward the statement balance — the variance they cause stays visible
   rather than being quietly written off.

4. **`isReconciled` requires zero variance *and* zero unmatched lines.** A
   period whose variance happens to net to zero while lines are still open is
   a coincidence, not a reconciliation. `markReconciled()` refuses to move
   `reconciled_up_to` over such a period unless `force: true` is passed, which
   exists so a manager who has looked at a variance and accepted it has an
   explicit way through instead of a watermark that means nothing.

5. **Relaxed one Phase 1 test rather than bumping its constant.**
   `gl_schema_test.dart` asserted `expect(AppConstants.dbVersion, 28)`, which
   makes *every* future migration fail a GL schema test — v29 tripped it
   immediately. Changed to `greaterThanOrEqualTo(28)`: below 28 means the GL
   migration was lost (a real failure), above 28 is a later migration doing its
   job and is none of that test's business. Bumping it to 29 would just move
   the tripwire one migration further out.

6. **Statement balance is built from `bank_accounts.opening_balance` plus the
   lines in range, not from a statement's `ending_balance`.** A reconciliation
   period does not have to line up with one statement — it may span several or
   sit inside one — so deriving it from the account's own opening figure is the
   only definition that always has an answer. `bank_statements.ending_balance`
   is still stored as the bank asserted it (and `importStatement` keeps a
   caller-supplied figure rather than overwriting it with the derived sum),
   because the gap between asserted and derived is itself a finding.

7. **UI lives in a new `lib/features/banking/`**, not under
   `features/reports/`. The task file asked for this call to be made by looking
   at how the codebase groups things: `reports/` is read-only output, while
   record-keeping workflows that write (`stock_groups`, `purchases`, `credit`,
   `suppliers`) each get their own folder. Reconciliation writes, so it is a
   workflow.

8. **Routes are manager-gated and deliberately NOT in
   `_accountantAllowedRoutes`.** Reconciliation is arguably an accountant's
   core job, but that set is documented in `app_router.dart` as "a narrow,
   read/export-oriented slice" and every route in it is read-only. Adding the
   first write route to it is a policy decision about what an accountant-role
   user may change, not an implementation detail — flagged here for a human
   rather than decided unilaterally. **If accountants should reconcile, add
   `/banking` and `/banking/reconcile` to that set.**

9. **CSV date parsing is day-first for ambiguous values.** `03/04/2025` reads
   as 3 April, matching Indian convention and the rest of this app. ISO
   `yyyy-MM-dd` is detected by its four-digit first component, so both formats
   work without a format flag the user could get wrong. Amounts accept `₹`,
   thousands separators, and `(123.45)` accounting negatives, since real bank
   exports use all three.

10. **Used the existing `csv` package** (already a dependency at `^5.1.1`) with
    `shouldParseNumbers: false`, so amount parsing goes through one validated
    path instead of the CSV library silently coercing some cells to numbers
    and leaving others as strings.

### Known gaps left open by Task 2.1

Listed rather than silently dropped:

- **No GL posting from reconciliation.** Matching a line records the
  correspondence; it does not create ledger entries for statement lines that
  have no counterpart (bank charges, interest). Those still have to be booked
  through the normal manual-entry path. This is intentional — auto-posting from
  an import is how a ledger fills with entries nobody authorised — but it means
  an ignored bank-charge line leaves a permanent variance until someone books
  it by hand.
- **Reconciliation reads `gl_entries` directly, not the `gl_balances` cache.**
  Correct (the cache is per financial year, a reconciliation period is usually
  a month), but it means the GL side is a full scan of the account's entries in
  range. Fine at shop scale; worth an index-backed aggregate if an account ever
  carries very large volumes.
- **`reconciled_up_to` is advisory.** Nothing prevents importing or unmatching
  a statement line dated before the watermark. Phase 1's
  `FinancialYearCloseService` is the real lock for closed periods; a
  bank-period lock would duplicate that concept and was left out.
- **Sale cancellations still don't post to GL** (a Phase 1 gap noted in
  README.md). A cancelled sale that was paid by bank transfer will therefore
  show as an unmatched statement line with no ledger counterpart. Nothing in
  Task 2.1 can fix this — it needs the Phase 1 follow-up.
- **No widget tests for the two new screens.** This codebase has essentially no
  widget tests, so the module follows the local convention: service and
  repository logic is covered (44 tests), UI is not.

## Next run

Start Task 2.2 ([02-loyalty-points.md](02-loyalty-points.md)). **Read
[README.md](README.md)'s loyalty section first** — most of that module already
exists (`loyalty_utils.dart`, `customer_model.loyaltyPoints`,
`sale_model.loyaltyPointsRedeemed`, redemption already wired into billing,
per-store earn rate already in `migration_v26`). The task is gap-closing, not a
rebuild, and the tier ladder is **4 tiers** (regular/bronze/silver/gold), not
the 3 the task file assumes.
