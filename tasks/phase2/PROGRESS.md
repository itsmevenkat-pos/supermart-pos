# Phase 2 (Enterprise Features) — Progress

Cross-run state for the `feature/phase2-enterprise` branch. See
[README.md](README.md) for what differs from Phase 1, and
[../README.md](../README.md) for the conventions that still apply.
Update this at the end of every run.

## Status

| # | Task | State |
|---|------|-------|
| 2.1 | [01-bank-reconciliation.md](01-bank-reconciliation.md) — bank reconciliation | ✅ Done |
| 2.2 | [02-loyalty-points.md](02-loyalty-points.md) — loyalty gap-closing | ✅ Done |
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
- Start of the Task 2.2 run, re-measured: **182 issues, 0 errors**, **308 passing** —
  unchanged, nothing landed on `main` in between.
- After Task 2.2: **182 issues (0 new,** identical to baseline by file+rule**)**,
  **365 passing** (+57 new).

Compare analyze by file + rule, not raw line, since inserting lines shifts
every issue below them:

```bash
norm() { sed -E 's/:[0-9]+:[0-9]+ •/ •/' "$1" | sed -E 's/^ *//' | sort | uniq -c; }
diff <(norm /tmp/analyze_baseline.txt) <(norm /tmp/analyze_after.txt)
```

### Migration version — read fresh, every run

Task 2.1 took **v29**. At the start of the Task 2.2 run `AppConstants.dbVersion`
read **29** and the highest `if (oldVersion < N)` block was 29, so Task 2.2 took
**v30**. Both are now **30**. The next migration takes **31 — unless** another
automation has landed one on `main` in the meantime, so re-check both places
before writing a line of DDL. Do not trust this paragraph over the source.

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

### Task 2.2 — Loyalty points gap-closing (done)

The README was right that this is not a from-scratch build, and it understated
the case: a *fourth* piece already existed that neither the README nor the task
file mentions. See "deviation 1" below.

New architecture doc: **[docs/LOYALTY_ARCHITECTURE.md](../../docs/LOYALTY_ARCHITECTURE.md)**
— written for the same reason Phase 1 has `GL_ARCHITECTURE.md`: the task file
for this module was stale, and the next run needs a description of what is
really there. Trust that doc over any task file.

Files added:
- `lib/core/database/migrations/migration_v30.dart` — five columns on
  `bonus_points`, one on `stores`, three indexes.
- `lib/models/loyalty_point_event_model.dart` — `LoyaltyPointEvent` +
  `LoyaltyEventType`.
- `lib/repositories/loyalty_event_repository.dart`
- `lib/services/loyalty_service.dart`, `loyalty_exceptions.dart`
- `lib/features/loyalty/screens/loyalty_summary_screen.dart`
- `docs/LOYALTY_ARCHITECTURE.md`
- `test/repositories/loyalty_event_repository_test.dart` (19 tests),
  `test/services/loyalty_service_test.dart` (38 tests)

Files changed:
- `lib/core/database/database_helper.dart` — `if (oldVersion < 30)` + import.
- `lib/core/database/migrations/migration_v1.dart` — calls `MigrationV30.up()`
  + import.
- `lib/constants/app_constants.dart` — `dbVersion` 29 → 30.
- `lib/repositories/store_repository.dart` — `get/updateLoyaltyExpiryDays`.
- `lib/repositories/sale_repository.dart` — the existing `bonus_points` insert
  now stamps `event_type` and `expires_at`.
- `lib/repositories/sale_cancellation_repository.dart` — points reversal fixed,
  see deviation 4.
- `lib/features/reports/screens/customer_history_screen.dart` — third tab.
- `lib/core/routes/app_router.dart`, `lib/core/widgets/app_scaffold.dart` —
  `/loyalty` route + sidebar tile.

Decisions and deviations, with reasons:

1. **The event log extends the existing `bonus_points` table; the task file's
   `loyalty_point_events` table was NOT created.** This is the big one. The
   README's stale-audit warning did not go far enough — beyond
   `loyalty_utils.dart` and the `Customer`/`Sale` fields it lists,
   `bonus_points` has existed since the original schema *and*
   `SaleRepository` already writes one row per points-moving sale (there is a
   comment in that file calling itself "the first real writer `bonus_points`
   has ever had"). Building `loyalty_point_events` next to it would have
   produced exactly the two-disagreeing-sources-of-truth problem the same task
   file warns against two paragraphs earlier. `MigrationV30` adds
   `event_type` / `expires_at` / `expired_points` / `note` /
   `created_by_user_id` instead. Existing rows default to `event_type='sale'`,
   which is correct for every one of them, so there was no data migration.

2. **Migration version 30**, per the dynamic rule; `dbVersion` and the highest
   `onUpgrade` block both read 29 at the start of this run.

3. **`stores.loyalty_points_expiry_days` defaults to 0 = never expire, and
   `expires_at` is frozen at earn time.** Two separate deliberate choices.
   Defaulting to off means upgrading to v30 cannot silently lapse any existing
   customer's points — a balance quietly dropping after an upgrade nobody asked
   for is a customer-facing regression, not a feature. Freezing the window onto
   each earn event (rather than deriving it from the store setting at read
   time) means shortening the setting later cannot retroactively expire points
   a customer has already been told they hold.

4. **Fixed a real bug in `SaleCancellationRepository` rather than working
   around it.** The reversal recomputed points as
   `netAmount / bonus_points_threshold`, which drops `pointMultiplierForRating`
   — so cancelling a gold customer's bill clawed back about half the points
   they were actually given, and points *redeemed* on the cancelled bill were
   destroyed rather than returned. It now reads the sale's `bonus_points` row
   and reverses what was really recorded, clamps so a reversal cannot drive a
   balance negative, and logs a `cancellation` event. Sales predating the event
   log keep the old estimate, since nothing recorded what they did. This is
   outside the letter of Task 2.2 but squarely inside its purpose: the whole
   point of an audit log is that reversals stop being guesses.

5. **Expiry is FIFO with per-lot write-back, making sweeps idempotent.**
   Redemptions consume the oldest lot first; a lapsed lot only writes off what
   spending never reached. What a sweep takes is added to that lot's
   `expired_points`, and `expire` rows are excluded from the spending total, so
   a second sweep sees smaller lots and the same spending and takes nothing.
   Tested explicitly (three consecutive sweeps, including one a year later).

6. **`expireOldPoints()` is on-demand only — no scheduler.** Checked before
   relying on one, as the task file asks: this app has no background job
   runner (the only `Timer.periodic` calls are UI refresh in
   `billing_screen.dart`, and there is no workmanager/cron dependency). A
   manager runs the sweep from the loyalty screen. Turning the expiry setting
   on does not by itself expire anything, and the screen says so.

7. **A `LoyaltyEventRepository` and `LoyaltyService` were created despite the
   task file saying "do not create a `LoyaltyRepository`".** That prohibition
   is aimed at a parallel *account/rules* store competing with
   `Customer.loyaltyPoints` — and no such thing was built. What was built is
   data access for the existing event table and the expiry/adjust/report logic
   over it, which has to live somewhere, and this codebase's convention is
   repository + service. Neither class owns the balance: `LoyaltyService`
   updates `customers.loyalty_points` in the same transaction as the event, and
   `LoyaltyEventRepository` never touches it.

8. **`recomputeBalanceFromEvents()` deliberately does not repair a mismatch.**
   Customers who earned points before `SaleRepository` started writing
   `bonus_points` legitimately hold a balance with no events behind it, so an
   automatic rebuild would destroy real points. It reports, a human decides.
   The per-customer UI says the same thing in words rather than showing an
   empty history that implies the customer never earned anything.

9. **`adjustPoints` requires an acting user and writes its audit row inside the
   transaction.** The audit write was initially outside it, which the tests
   caught: a failed audit left the points already moved. Moved inside, matching
   `SaleCancellationRepository`'s convention — the balance change and the
   record of who made it now commit together or not at all.

10. **UI lives in `lib/features/loyalty/`, not `features/reports/`** — same
    reasoning as Task 2.1 deviation 7: `reports/` is read-only output, and this
    screen runs an expiry sweep and edits a store setting.

11. **`/loyalty` is manager-gated and NOT in `_accountantAllowedRoutes`** —
    same open policy question flagged in Task 2.1 deviation 8, and the same
    answer: that set is documented as read-only, and the outstanding-points
    liability is arguably an accountant's business. **If accountants should see
    the loyalty liability, add `/loyalty` to that set** — a human's call.

12. **Tier count and names untouched**, as the task file instructs: still
    `regular`/`bronze`/`silver`/`gold`.

### Known gaps left open by Task 2.2

Listed rather than silently dropped:

- **The points liability is not posted to the GL.** Outstanding points ×
  redemption value is a real liability the Phase 1 Balance Sheet does not show.
  The loyalty screen surfaces the number and states plainly that it is not in
  the ledger. Booking it needs a chart-of-accounts addition plus a posting rule
  on every earn and redeem — an accounting decision for a human, and the task
  file explicitly calls it out of scope.
- **"Expiring soon" is an upper bound**, not exact. It sums lots due within 30
  days without running the FIFO walk, then caps at the customer's balance, so
  it can overstate for someone who has spent recently. Exact would mean a full
  walk per customer per screen paint.
- **No widget tests** for the new tab or screen — same local convention as
  Task 2.1; this codebase has essentially none.
- **The stale placeholder test was left alone.**
  `test/core/services/loyalty_service_test.dart` asserts arithmetic on literals
  against a hardcoded ₹100-per-point that does not match this app's
  configurable rate, and imports nothing (its import is commented out behind a
  `TODO`). Task 2.2's brief was that existing loyalty tests pass unmodified, so
  it was not touched — but it tests nothing and its filename now collides
  conceptually with the real `test/services/loyalty_service_test.dart`.
  **Worth deleting in a follow-up**, which is a call for a human since it is
  pre-existing.
- **Expiry has no UI on the customer-facing side.** Nothing warns a customer at
  the till that their points are about to lapse; the warning is only on the
  customer history screen a manager opens.

## Branch / PR state

Both Task 2.1 and Task 2.2 are on **`feature/phase2-enterprise`**, and PR
**#2** covers both.

The run instructions suggested a PR per module. That was not done, and the
reason is `tasks/phase2/PROGRESS.md` itself: it exists only on this branch, not
on `main`. Two module branches cut from `main` would each create their own copy
of this file and conflict on merge, losing exactly the cross-run state the
protocol depends on. Keeping one branch — which is also what step 2 of the run
instructions names explicitly — avoids that. PR #2's title and body were
updated to say it carries both modules rather than leaving it labelled as
Task 2.1 only.

**If per-module PRs are wanted**, the fix is to land `tasks/phase2/PROGRESS.md`
on `main` first; after that, module branches can be cut independently.

## Next run

Start Task 2.3 ([03-payment-gateways.md](03-payment-gateways.md)). Nothing from
Task 2.2 blocks it — the four modules are independent.

Before writing any DDL, re-read `AppConstants.dbVersion` and the highest
`if (oldVersion < N)` block. They are **30** as of this run; assume nothing.

**Repeat the Task 2.2 lesson on Task 2.3 and 2.4**: this codebase has more
already built than the task files credit. Before implementing anything a task
file describes as new, grep for it. Task 2.2's file called for a new events
table that was already there in all but five columns, and the README's own
warning about the stale audit had itself missed that. Check
`docs/GL_ARCHITECTURE.md` and `docs/LOYALTY_ARCHITECTURE.md` first — those
describe reality.
