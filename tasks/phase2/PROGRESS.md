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
| 2.3 | [03-payment-gateways.md](03-payment-gateways.md) — payment gateways | ✅ Done |
| 2.4 | [04-collections-commission.md](04-collections-commission.md) — collections/commission | ✅ Done |

**All four modules are complete.** See "Next run" at the bottom for what is
left (PR state, and the open questions no single task could decide).

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
- Start of the Task 2.3 run, re-measured: **182 issues, 0 errors**, **365 passing** —
  unchanged again, nothing landed on `main` between runs.
- After Task 2.3: **182 issues (0 new,** identical to baseline by file+rule**)**,
  **455 passing** (+90 new).
- Start of the Task 2.4 run, re-measured: **182 issues, 0 errors**, **455 passing** —
  unchanged again, nothing landed on `main` between runs.
- After Task 2.4: **182 issues (0 new,** identical to baseline by file+rule**)**,
  **567 passing** (+112 new).

Compare analyze by file + rule, not raw line, since inserting lines shifts
every issue below them:

```bash
norm() { sed -E 's/:[0-9]+:[0-9]+ •/ •/' "$1" | sed -E 's/^ *//' | sort | uniq -c; }
diff <(norm /tmp/analyze_baseline.txt) <(norm /tmp/analyze_after.txt)
```

### Migration version — read fresh, every run

Task 2.1 took **v29**, Task 2.2 took **v30**, Task 2.3 took **v31**, Task 2.4
took **v32** (checked fresh at the start of that run: `dbVersion` and the
highest `if (oldVersion < N)` block both read 31). Both now read **32**. The
next migration takes **33 — unless** another automation has landed one on
`main` in the meantime, so re-check both places before writing a line of DDL.
Do not trust this paragraph over the source.

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

### Task 2.3 — Payment gateways (done)

The Task 2.2 lesson repeated itself, in the opposite direction: this task
file's stale assumption was about something that **doesn't** exist rather than
something that already did. See deviation 1.

New architecture doc:
**[docs/PAYMENT_GATEWAY_ARCHITECTURE.md](../../docs/PAYMENT_GATEWAY_ARCHITECTURE.md)**
— same reason as the other two. Trust it over the task file.

Files added:
- `lib/core/database/migrations/migration_v31.dart` — two tables, four
  indexes, three `stores` credential columns.
- `lib/models/payment_gateway_transaction_model.dart` (holds
  `PaymentGatewayName` and `GatewayTransactionStatus`),
  `payment_settlement_model.dart`.
- `lib/services/gateways/payment_gateway.dart` (interface + result types +
  `PaymentGatewayException` / `GatewayNotConfigured`),
  `razorpay_gateway.dart`, `stub_gateways.dart`.
- `lib/repositories/payment_gateway_repository.dart`
- `lib/services/payment_gateway_service.dart`,
  `payment_gateway_exceptions.dart`
- `lib/features/payments/screens/payment_gateway_screen.dart`,
  `lib/features/payments/widgets/gateway_collect_dialog.dart`
- `docs/PAYMENT_GATEWAY_ARCHITECTURE.md`
- `test/repositories/payment_gateway_repository_test.dart` (20 tests),
  `test/services/razorpay_gateway_test.dart` (26 tests),
  `test/services/payment_gateway_service_test.dart` (44 tests)

Files changed:
- `lib/core/database/database_helper.dart` — `if (oldVersion < 31)` + import.
- `lib/core/database/migrations/migration_v1.dart` — calls `MigrationV31.up()`
  + import.
- `lib/constants/app_constants.dart` — `dbVersion` 30 → 31.
- `lib/services/gl_service.dart` — `bankAccountCode`,
  `gatewayPaymentReferenceType`, `postGatewayPaymentEntries()`.
- `lib/repositories/store_repository.dart` — `get/updateRazorpayConfig`.
- `lib/features/settings/screens/settings_screen.dart` — credentials tile.
- `lib/features/billing/widgets/payment_dialog.dart` — gateway method +
  Collect flow, `onPay` gained a 5th argument.
- `lib/features/billing/screens/billing_screen.dart` — links gateway payments
  to the sale after `processSale`.
- `lib/core/routes/app_router.dart`, `lib/core/widgets/app_scaffold.dart` —
  `/payment-gateways` route + sidebar tile.

Decisions and deviations, with reasons:

1. **The `payments` table was dead, and this module is its first writer.**
   The big one. The task file states that "every sale's payment already flows
   through this" table — it does not. `payments` shipped in `MigrationV1` and
   had **zero readers and zero writers** anywhere in `lib/` or `test/`; sales
   record their split in the `sales.payment_methods` JSON map. The task file
   also rules out adding a second `sale_id`-linked table, correctly. So
   `PaymentGatewayRepository` writes a real `payments` row for a gateway
   payment and hangs the gateway detail off it one-to-one, which is the shape
   the task file describes. **The consequence is that `payments` is populated
   for gateway payments and nothing else** — listed as a gap below, and stated
   in the architecture doc, because anyone later treating that table as the
   complete record of money taken will be wrong. Making it authoritative for
   all payment types means rewriting the billing path and backfilling
   history — a much larger change than "add a payment gateway".

2. **Collection and sale-linking are split, because the foreign key forces
   it.** `payments.sale_id` really does reference `sales(id)`, and this app
   collects payment inside the payment dialog *before*
   `BillingService.processSale` writes the sale. `createOrder` therefore takes
   no `saleId`, and `attachSale` joins them afterwards. Found by a test
   failing on the constraint, not by reading — worth stating because the task
   file's design implicitly assumes the sale already exists. The link step in
   `billing_screen.dart` is deliberately non-fatal: the money is already taken
   and recorded by then, and failing a completed sale over a missing link
   would be far worse than a row someone joins up by hand.

3. **Migration version 31**, per the dynamic rule; `dbVersion` and the highest
   `onUpgrade` block both read 30 at the start of this run.

4. **A gateway payment posts no revenue — only an asset reclassification.**
   `postGatewayPaymentEntries` debits `1010` Bank and credits `1000` Cash, or
   `1100` Receivable when `settlesReceivable` is set. Phase 1's
   `postSaleEntries` already credited `4000` for the whole bill; posting
   revenue again would double the day's takings. There is an explicit test
   that `4000` stays at zero across a gateway payment, because that is the
   obvious way to get this wrong.

5. **Verification is signature *plus* a server-side status check.** A
   signature proves who sent the callback, not that money moved — so a valid
   signature over a *failed* payment does not settle a sale. Relatedly,
   Razorpay's `authorized` maps to `pending`, not success: money authorised is
   not money taken, and letting a customer leave on an authorisation that is
   never captured is a real way for a shop to lose money.

6. **`signatureValid` is a field on `GatewayVerification`, not something
   inferred from the failure message.** It was briefly the latter; matching on
   prose would have broken the moment the wording changed, and the two
   failures need genuinely different handling — a bad signature is a security
   event, and the claimed payment id is deliberately **not** stamped onto the
   failed row, so an unverified caller cannot burn a real payment id.

7. **Idempotency is enforced twice.** `gateway_transaction_id` is UNIQUE in the
   schema, and `verifyAndRecordPayment` checks for a duplicate before spending
   a network call. Both are tested, including that the constraint catches what
   gets past the check. A replayed callback crediting the shop twice is the
   failure worth designing against here.

8. **Credentials live on the `stores` row**, edited in Settings, following the
   Ollama/printer pattern — no key or secret anywhere in the repo, as the task
   file requires. Note it asks to "follow how this app already handles
   secrets, e.g. Supabase": that one uses hardcoded placeholder constants in
   `supabase_sync_service.dart`, which is exactly what the same paragraph
   forbids, so the settings pattern was followed instead. **The keys are not
   encrypted at rest** — see the gap below.

9. **Only Razorpay is real.** PayPal and Square implement the interface and
   throw `UnimplementedError`, with `isConfigured` permanently false so they
   can never reach the till — per the task file, and tested.

10. **Partial refunds are refused rather than approximated.** The GL posting is
    a two-line reclassification; reversing part of it means deciding how a
    part-refunded sale is represented, which is a sale-level accounting
    question. `SalesReturnService` is where a partial refund belongs.

11. **The cashier types the payment id and signature by hand.** A phone app
    would use Razorpay's checkout SDK; this is a desktop POS with no such SDK.
    Nothing typed is trusted — it goes straight to signature verification
    against the shop's own secret and then a status check, so an invented
    value records a failed attempt and cannot settle a bill.

12. **UI lives in `lib/features/payments/`**, not `features/reports/` — same
    reasoning as Task 2.1 deviation 7 and Task 2.2 deviation 10.

13. **`/payment-gateways` is manager-gated and NOT in
    `_accountantAllowedRoutes`** — the same open policy question flagged twice
    before, and the same answer. **If accountants should see gateway
    settlements, add `/payment-gateways` to that set** — a human's call.

### Known gaps left open by Task 2.3

Listed rather than silently dropped:

- **`payments` is populated only for gateway payments.** See deviation 1. The
  honest completion is to write `payments` rows for every method from
  `BillingService` and backfill, which is its own task. Until then, do not
  read both `payments` and `sales.payment_methods` and assume they agree.
- **Settlement fees are not posted to the GL.** The money reached `1010` Bank
  when each payment was verified; a payout is the gateway moving its own
  float. The fee is a real expense, but booking it needs a gateway-clearing
  account plus a posting rule for the gap between "collected" and "deposited"
  — an accounting decision for a human, and the chart of accounts has no
  payment-processing-fee account either. `reconcileSettlement` surfaces the
  fee and the screen says plainly that it is not in the ledger.
- **No webhook listener.** This app has no server and no background job runner
  (re-confirmed, same as Task 2.2's expiry finding), so a payment whose
  callback never arrives is recovered by a cashier pressing "Check with
  gateway". `refreshStatus` deliberately cannot settle a payment it finds
  successful — doing so would skip the signature check.
- **Settlement figures are entered by hand**, not fetched from Razorpay's
  settlements API. Fine at shop scale; an obvious next increment.
- **Gateway keys are not encrypted at rest.** They are out of source control,
  which is the thing that actually matters, but the SQLite file on the till
  holds the key secret in plain text. Encrypting it needs a key this app has
  nowhere to keep. Use a restricted key; treat the till's disk as sensitive.
- **Reconciliation windows on the settlement's own calendar day.** A gateway
  batches on its cut-off, so a late-evening payment can land in the next day's
  payout and shows as a variance. Reported rather than treated as an error,
  same stance as Task 2.1 — but it means `agrees` will often be false in
  normal operation.
- **No widget tests** for the new screen or dialog — same local convention as
  Tasks 2.1 and 2.2.
- **The Phase 1 gap that sale cancellations don't post to GL still bites
  here**: a cancelled sale paid by gateway leaves the reclassification entry
  in place with no sale reversal against it. Nothing in Task 2.3 can fix that.

### Task 2.4 — Collections & commission (done)

The last of the four. Both halves were genuinely unbuilt, as its task file
claimed — the first task file this phase whose assumptions about the codebase
held up in both directions. **`Sale.salesmanId` exists** (`sales.salesman_id`
since `MigrationV1`); the run instructions singled it out as the prerequisite
worth confirming before starting, and it is real.

New architecture doc:
**[docs/COLLECTIONS_COMMISSION_ARCHITECTURE.md](../../docs/COLLECTIONS_COMMISSION_ARCHITECTURE.md)**
— same reason as the other three. Trust it over the task file.

Files added:
- `lib/core/database/migrations/migration_v32.dart` — three tables, six indexes.
- `lib/models/collection_activity_model.dart` (holds `CollectionActivityType`
  and `CollectionActivityStatus`), `commission_rule_model.dart` (holds
  `CommissionTier` and `CommissionRuleType`), `commission_settlement_model.dart`.
- `lib/repositories/collections_repository.dart`, `commission_repository.dart`
- `lib/services/collections_service.dart`, `collections_exceptions.dart`,
  `commission_service.dart`, `commission_exceptions.dart`
- `lib/features/collections/screens/collections_screen.dart`,
  `lib/features/commission/screens/commission_screen.dart`
- `docs/COLLECTIONS_COMMISSION_ARCHITECTURE.md`
- `test/repositories/collections_repository_test.dart` (14 tests),
  `test/services/collections_service_test.dart` (43 tests),
  `test/repositories/commission_repository_test.dart` (19 tests),
  `test/services/commission_service_test.dart` (36 tests)

Files changed:
- `lib/core/database/database_helper.dart` — `if (oldVersion < 32)` + import.
- `lib/core/database/migrations/migration_v1.dart` — calls `MigrationV32.up()`
  + import.
- `lib/constants/app_constants.dart` — `dbVersion` 31 → 32.
- `lib/core/routes/app_router.dart`, `lib/core/widgets/app_scaffold.dart` —
  `/collections` and `/commission` routes + sidebar tiles.

No existing table gained a column and aging is derived rather than stored, so
upgrading to v32 cannot change what any customer is shown to owe.

Decisions and deviations, with reasons:

1. **Migration version 32**, per the dynamic rule; `dbVersion` and the highest
   `onUpgrade` block both read 31 at the start of this run.

2. **The task file's `referenceType='Sale'` is wrong — the real value is
   lowercase `'sale'`.** The aging walk does not filter on reference type at
   all; it uses the **sign** of `amount`, which is the convention
   `CustomerLedger`'s own doc comment defines and all five of its writers
   follow (`sale`, `payment`, `advance`, `sales_return`, `exchange`,
   `sale_cancellation`). Filtering on a string would have silently dropped
   returns and cancellations from the receivable.

3. **Aging buckets are lower-inclusive, upper-exclusive**, so a charge exactly
   30 days old is in the 30-60 bucket. The task file asks for this call to be
   made, documented and tested; it is pinned at 0, 29, 30, 59, 60, 89 and 90
   days. The reasoning: the label names the age a debt has *reached*.

4. **Payments clear the oldest debt first (FIFO), including the advance case.**
   A charge arriving while the customer is in advance absorbs that advance
   before counting as outstanding, mirroring how `CustomerRepository` already
   splits a payment into "payment" and "advance" portions. The consequence
   worth knowing: part-paying an old debt does *not* make the remainder recent
   — the remnant keeps the original charge's date.

5. **Commission excludes cancelled sales; `SalesmanRepository.getPerformance()`
   was left counting them.** Paying commission on a reversed bill is wrong, so
   the payable excludes them. The older performance leaderboard has counted
   every row regardless of status since long before this module, and a
   leaderboard and a payable are not obliged to agree. Changing it would alter
   a number managers already read. **Flagged for a human**: if they should
   agree, `getPerformance()` is the one to fix.

6. **Tiers are marginal, not cliff-edged.** With bands 2% to ₹50,000 then 3%,
   ₹60,000 earns ₹1,300 and not ₹1,800. A cliff would make one extra rupee of
   sales worth ₹500, which is a direct incentive to game the period boundary.
   Band upper bounds are exclusive, tested at exactly ₹50,000 and at ₹50,001.

7. **No rule, several overlapping rules, or partial coverage are all
   refusals.** A rule covering half a month gives no honest rate for the other
   half, and two overlapping rules mean the shop's own records disagree about
   what it promised to pay. Returning ₹0 would look like a salesman who sold
   nothing. The exception messages say to settle the stretches separately.

8. **Commission is not posted to the GL.** The chart of accounts has neither a
   commission-expense nor an accrued-commission account (`5100 Salaries &
   Wages` is the nearest, and commission is not salary). Adding accounts plus a
   posting rule is an accounting decision for a human — the same call, for the
   same reason, as the loyalty liability in 2.2 and gateway fees in 2.3.

9. **`commission_ledger` gained two columns the task file's DDL omits.**
   `salary_reference` because the same file's *prose* explicitly calls for it
   ("a settlement record with a free-text `salary_reference` field"), and
   `created_at` because every other table in this schema has one and without it
   there is no way to tell when a settlement was raised as opposed to which
   period it covers.

10. **No `aging_analysis` and no `dunning_schedules` table**, as the task file
    instructs. Aging is computed on demand; a scheduled reminder is a
    `collection_activities` row with a future `scheduled_date`.

11. **Reminders reuse `WhatsAppShareService.sendCampaignMessage`** — checked
    for an existing hook before building anything, as the task file asks, and
    found the one the Campaigns screen uses. It opens WhatsApp's compose
    screen; the user presses send. **No SMS gateway was added**, per the task
    file's explicit instruction; `sms` and `email` activity types exist for
    recording a message sent by other means. The message builder is a pure,
    separately tested function, and the sender is injectable the way
    `PaymentGatewayService` takes a `gatewayOverride`.

12. **Logging a `payment` activity records money collected; it does not move
    it.** The payment still goes through `CustomerRepository.recordPayment`.
    Keeping them apart stops the activity log from becoming a second,
    disagreeing account of what a customer owes, and the UI says so on the
    field.

13. **UI lives in `lib/features/collections/` and `lib/features/commission/`**,
    not `features/reports/` — same reasoning as Task 2.1 deviation 7.

14. **`/collections` and `/commission` are manager-gated and NOT in
    `_accountantAllowedRoutes`** — the same open policy question flagged in
    2.1, 2.2 and 2.3, and the same answer. **If accountants should see the
    receivable aging or the commission liability, add these two routes to that
    set** — a human's call, now outstanding for four modules.

### Known gaps left open by Task 2.4

Listed rather than silently dropped:

- **Sales returns are not deducted from commissionable sales.** Cancelled sales
  are excluded (the sale is void), but a *returned* sale keeps its
  `net_amount`. Deducting returns needs a product decision the task file does
  not make: whether a return reduces the period it was returned in, or the
  period the sale was made in. Matters most where returns are large and late.
- **The service would accept overlapping settlement periods.** The
  `UNIQUE(salesman_id, period_from, period_to)` constraint only catches an
  exact repeat, so 1–31 Jan and 15 Jan–15 Feb would double-pay the overlap. The
  screen offers whole calendar months only, which makes this unreachable
  through the UI, but a caller could do it. The real fix is a range-overlap
  check in `createSettlement`.
- **Aging is a full ledger scan** walked in Dart. Correct, and fine at shop
  scale; a shop with years of history and thousands of credit customers would
  want it incrementalised.
- **No SMS or email sending**, and WhatsApp only opens the compose screen. A
  real messaging integration is separate and out of scope.
- **No dunning automation.** No background job runner exists in this app
  (re-confirmed for the third time — the only `Timer.periodic` is UI refresh in
  `billing_screen.dart`). Overdue follow-ups surface when a manager opens the
  screen; nothing chases anyone on its own.
- **The Phase 1 gap that sale cancellations don't post to GL still bites**, in
  a way worth stating precisely: `customer_ledger` *does* record cancellations,
  so the aging report is right — but the GL and the receivable will disagree
  for any cancelled credit sale. Reconcile against the ledger, not the GL,
  until that Phase 1 follow-up lands.
- **No widget tests** for the two new screens — same local convention as
  2.1–2.3.

## Branch / PR state

Tasks 2.1, 2.2 and 2.3 are all on **`feature/phase2-enterprise`**, and PR
**#2** covers all three.

The run instructions suggested a PR per module. That was not done, and the
reason is `tasks/phase2/PROGRESS.md` itself: it exists only on this branch, not
on `main`. Two module branches cut from `main` would each create their own copy
of this file and conflict on merge, losing exactly the cross-run state the
protocol depends on. Keeping one branch — which is also what step 2 of the run
instructions names explicitly — avoids that.

By the Task 2.3 run there was a second reason: **PR #2 was still open and
unmerged**, so a branch cut from `main` for Task 2.3 would not have contained
Tasks 2.1 and 2.2 at all, and the two PRs would have raced on
`app_router.dart`, `app_scaffold.dart`, `database_helper.dart`,
`migration_v1.dart` and `app_constants.dart` — every one of which all three
modules touch. Stacking on the open branch is the lower-risk option while #2
is unmerged. PR #2's title and body are updated each run to say what it
actually carries.

**Task 2.4 was checked against this again rather than assumed.** At the start
of that run PR #2 was still `open`, `merged: false`, `mergeable_state: clean`,
7 commits, base `main` at `43a0c32` — so both reasons still held, unchanged,
and Task 2.4 stacked onto the same branch and the same PR. Task 2.4 touches
`app_router.dart`, `app_scaffold.dart`, `database_helper.dart`,
`migration_v1.dart` and `app_constants.dart`, the same five files, so a
separate branch would have raced on every one of them.

**If per-module PRs are wanted**, the fix is to merge PR #2 (which lands
`tasks/phase2/PROGRESS.md` on `main`); after that, module branches can be cut
independently — though the shared migration/router files will still need
sequencing. With all four modules now done, this matters less than it did:
there is no fifth module queued behind the decision.

## Re-verification (later run of 2026-08-15, Flutter 3.47.0)

A scheduled firing found **no incomplete task to pick up** — all four modules
were already done and pushed. Rather than stack unrequested work onto an
already-large PR, the run re-verified the branch from a clean container. **No
code was changed.**

- `flutter analyze` — **182 issues, 0 errors** (161 info + 21 warning),
  matching the baseline exactly, and **0 issues in any Phase 2 file**
  (banking, loyalty, payment gateway, collections, commission).
- `flutter test` (full suite) — **567 tests, all passed**, matching the count
  recorded after Task 2.4.
- Migration chain checked at the source rather than trusted from these notes:
  `AppConstants.dbVersion` reads **32**, `onUpgrade` has contiguous
  `oldVersion < 29/30/31/32` blocks, and `MigrationV1` delegates to all four
  of `MigrationV29..V32.up()`, so `onCreate` and `onUpgrade` cannot diverge.
- `origin/main` still at `43a0c32` (unmoved since the branch was cut), so no
  renumbering is needed at merge time and **33 remains the next free version**.
- PR **#2** still **open**, `merged: false`, `mergeable_state: clean`, 9
  commits, base `main` at `43a0c32` — with **no reviews and no comments** on
  it yet.

The `flutter pub get` churn behaved exactly as documented above
(`analysis_options.yaml` + `pubspec.lock` only); both were `git checkout --`'d
and nothing from them is in any commit.

## Next run

**All four Phase 2 modules are implemented, tested and pushed.** There is no
next task in `tasks/phase2/`. What is actually outstanding is a human's
attention, not more code:

1. **PR #2 needs review and merge.** It now carries all four modules — roughly
   14k added lines across ~60 files, and every Phase 2 migration (v29–v32).
   Nothing further should be stacked on this branch without a good reason;
   at four modules the PR is already large enough to be hard to review.
2. **Four decisions were flagged for a human and none has been answered.**
   They are listed per-task above; the one raised in every single module is
   whether `_accountantAllowedRoutes` should gain `/banking`,
   `/banking/reconcile`, `/loyalty`, `/payment-gateways`, `/collections` and
   `/commission`. That set is documented as a read-only slice and all six
   write, so widening it is a policy call about what an accountant-role user
   may change.
3. **Three liabilities/expenses sit outside the GL** — loyalty points (2.2),
   gateway settlement fees (2.3), commission (2.4). Each was left out for the
   same reason: the Phase 1 chart of accounts has no suitable account, and
   adding one plus a posting rule is an accounting decision. If someone wants
   the Balance Sheet to be complete, that is one coherent follow-up task
   covering all three, not three separate ones.
4. **The Phase 1 gap that sale cancellations don't post to GL is now load-
   bearing in three modules** (2.1, 2.3, 2.4). It is the single highest-value
   Phase 1 follow-up.

Before writing any DDL in any future work, re-read `AppConstants.dbVersion`
and the highest `if (oldVersion < N)` block. They are **32** as of this run;
assume nothing.

**The task files were unreliable about this codebase in both directions.**
Task 2.2's called for an events table that already existed in all but five
columns. Task 2.3's asserted that a `payments` table was already carrying
every sale's payment when nothing had ever written to it. Task 2.4's was the
one that held up — both halves were genuinely unbuilt and `Sale.salesmanId`
was genuinely there — but it still got a detail wrong (`referenceType='Sale'`
is really `'sale'`) that would have silently dropped returns and cancellations
from the receivable had it been trusted. So the rule stands: before
implementing anything a task file calls new, grep for it — and before building
on anything a task file calls existing, grep for its *writers*, not just its
schema.

`docs/GL_ARCHITECTURE.md`, `docs/LOYALTY_ARCHITECTURE.md`,
`docs/PAYMENT_GATEWAY_ARCHITECTURE.md` and
`docs/COLLECTIONS_COMMISSION_ARCHITECTURE.md` describe reality. Trust them
over the task files.
