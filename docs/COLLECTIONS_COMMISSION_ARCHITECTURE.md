# Collections & Commission Architecture

What Phase 2 Task 2.4 actually built, and why it differs where it differs from
`tasks/phase2/04-collections-commission.md`. Like `GL_ARCHITECTURE.md`,
`LOYALTY_ARCHITECTURE.md` and `PAYMENT_GATEWAY_ARCHITECTURE.md`, **this file
describes reality — trust it over the task file.**

Two independent halves share a migration and a screen group but nothing else:

- **Collections** — accounts-receivable aging and follow-up tracking.
- **Commission** — per-salesman commission rules and settlements.

---

## Part A: Collections

### There is no aging table

Aging is computed on demand by `CollectionsService.generateAgingReport()` from
`customer_ledger`. Nothing is stored.

`customer_ledger` has recorded every movement in a customer's balance since
`MigrationV1`, written by five repositories:

| Writer | `reference_type` | Sign |
|---|---|---|
| `SaleRepository` | `sale` | positive (owes more) |
| `CustomerRepository` | `payment`, `advance` | negative |
| `SalesReturnRepository` | `sales_return` | negative |
| `ExchangeRepository` | `exchange` | either |
| `SaleCancellationRepository` | `sale_cancellation` | negative |

A stored aging snapshot would disagree with that ledger the moment the next
payment landed, and this app already has one answer to "what does this customer
owe". The task file called for exactly this, and it is the right call.

> **Note for anyone reading the task file:** it says credit sales are
> `referenceType='Sale'`. The real value is lowercase `'sale'`. The
> implementation does not filter on reference type at all — it uses the sign,
> which is the convention `CustomerLedger`'s own doc comment defines and every
> writer above follows.

### Debts are aged from the transaction date

**This app has no invoice due date.** The only `due_date` in the schema is on
`purchases` — what the shop owes *suppliers*. So a debt is aged from the
`created_at` of the ledger entry that created it.

In a shop selling on informal credit that is the honest reading of "how long
has this been outstanding": there was never a promised date to be late against.
If a due date is ever added to sales, aging should switch to it, and this
paragraph is the place to start.

### Payments clear the oldest debt first (FIFO)

`CollectionsService._walkFifo` walks a customer's ledger in order:

- A **charge** first absorbs any advance on hand, then whatever is left becomes
  an open charge.
- A **payment** consumes the oldest open charge, then the next, and any
  leftover becomes an advance.

The alternative — spreading each payment proportionally across all open charges
— would leave every charge partly unpaid forever and put a slice of a two-year-
old debt in the `current` bucket, which is the exact picture an aging report
exists to prevent.

Consequences worth knowing:

- A customer either owes something or is in advance, never both.
- Part-paying an old debt does **not** make the remainder recent. The remnant
  keeps the original charge's date.
- The aged total equals the customer's ledger balance. There is a test for it.
- Rupee dust below ₹0.005 is treated as zero, so `0.1 + 0.2 - 0.3` does not
  leave a ₹0.00 open charge that can never be cleared.

### Bucket boundaries: lower-inclusive, upper-exclusive

| Bucket | Age |
|---|---|
| `current` | 0–29 days |
| `days30` | 30–59 days |
| `days60` | 60–89 days |
| `days90Plus` | 90+ days |

The task file asks for this call to be made explicitly, so: **a charge exactly
30 days old is in the 30-60 bucket**, not 0-30. The label names the age a debt
has *reached*. Pinned by tests at 0, 29, 30, 59, 60, 89 and 90 days.

### Dunning is a `collection_activities` row

There is no `dunning_schedules` table. A scheduled reminder is an activity with
`status = 'pending'` and a future `scheduled_date`, so a reminder and the call
that answers it are the same kind of record rather than two tables that must
agree.

Scheduling in the past is refused: a reminder born overdue cannot be told apart
in the worklist from one the shop genuinely missed.

### Messaging: WhatsApp only, and it does not actually send

`sendDuesReminder` reuses `WhatsAppShareService.sendCampaignMessage` — the same
path the Campaigns screen uses. **That opens WhatsApp's compose screen with the
text filled in; the user presses send.** The activity is logged as "opened in
WhatsApp", which is the most this app can honestly claim.

`CollectionActivityType.sms` and `.email` exist for *recording* a message sent
by some other means. There is no SMS gateway in this app and Task 2.4
explicitly rules out adding one as a side effect of this work. **SMS/email
sending is a separate, out-of-scope integration.**

### Logging a payment activity does not move money

`logActivity(type: payment, amountCollected: 500)` records that ₹500 was
collected. The payment itself still goes through
`CustomerRepository.recordPayment`, which writes the ledger and the outstanding
balance. Keeping them apart is what stops the activity log from becoming a
second, disagreeing account of what a customer owes. The UI says so on the
amount field.

---

## Part B: Commission

### Prerequisites, confirmed rather than assumed

- `Sale.salesmanId` **exists** (`lib/models/sale_model.dart`, `sales.salesman_id`
  since `MigrationV1`). The run instructions flagged this as worth confirming;
  it is real.
- `Salesman` has **no** commission fields. This half is genuinely new.

### Gross sales = `SUM(sales.net_amount)`, cancelled excluded

`net_amount` is what every existing sales report totals
(`AdvancedReportService` uses it throughout), so commission is worked out on
the same figure the shop already calls a day's sales.

**Cancelled sales are excluded** (`status != 'cancelled'`, with a null status
treated as completed). Paying commission on a bill the shop reversed is simply
wrong. Note this differs from the older `SalesmanRepository.getPerformance()`,
which counts every row regardless of status — that pre-existing inconsistency
was left alone rather than changed, since a performance leaderboard and a
payable are not obliged to agree. **If they should agree, `getPerformance()` is
the one to fix.**

### Tiers are marginal, not cliff-edged

With bands `[{upTo: 50000, rate: 0.02}, {upTo: null, rate: 0.03}]`, sales of
₹60,000 earn 2% on the first ₹50,000 and 3% on the remaining ₹10,000 — ₹1,300,
not ₹1,800.

A cliff would make one extra rupee of sales worth ₹500 in commission, which is
a direct incentive to game the period boundary. Band upper bounds are
exclusive, so ₹50,000 exactly is all at 2% and ₹50,001 earns three paise more.
Both are tested.

Only `percentage` and `tiered` exist. The original draft's `slab` and `target`
types were dropped by the corrected task file because neither is specified
precisely enough to build.

### One rule per period, or a refusal

`calculateCommission` finds active rules overlapping the period and:

- **none** → `NoCommissionRule`
- **more than one** → `AmbiguousCommissionRule`
- **one, but it covers only part of the period** → `NoCommissionRule`

All three are refusals rather than guesses. A rule covering half the month
gives no honest rate for the other half; two overlapping rules mean the shop's
own records disagree about what it promised to pay. The fix in every case is to
settle the stretches separately, and the exception messages say so.

Rules are **deactivated, never deleted**, so a past settlement's reason
survives.

### Settlement periods are whole calendar months

`UNIQUE(salesman_id, period_from, period_to)` makes re-running a month safe: a
repeat hits the constraint instead of duplicating the payable.

**It only catches an exactly repeated period.** Two overlapping but
differently-bounded periods (1–31 Jan and 15 Jan–15 Feb) would double-pay the
overlap. The screen therefore offers only whole calendar months, which makes
overlaps impossible from the UI — but the service would accept them from a
caller that asked. See the gaps below.

### Commission is NOT posted to the general ledger

It is a real expense and a real payable, but the Phase 1 chart of accounts has
neither a commission-expense account nor an accrued-commission liability. The
closest seeded account is `5100 Salaries & Wages`, and commission is not
salary. Adding accounts plus a posting rule is an accounting decision for a
human.

This is the same call made for the loyalty points liability (Task 2.2) and
gateway settlement fees (Task 2.3), and for the same reason.

### `commission_ledger` is not a ledger

The table keeps the name from the task file's DDL; the model is
`CommissionSettlement`, named for what a row actually is. There is no
double-entry involved — it is a payable worked out from sales.

Two columns are not in the task file's DDL:

- `salary_reference TEXT` — the task file's *prose* calls for it ("a settlement
  record with a free-text `salary_reference` field"), the DDL omits it. Added,
  since the prose is the intent. It is the whole of the "salary integration"
  this app can offer, there being no payroll module.
- `created_at INTEGER NOT NULL` — every other table in this schema has one, and
  without it there is no way to tell when a settlement was *raised* as opposed
  to which period it covers.

---

## Schema (MigrationV32)

`AppConstants.dbVersion` 31 → 32. Read fresh at execution time per the dynamic
migration rule — v26–v31 were already taken.

| Table | Purpose |
|---|---|
| `collection_activities` | Follow-ups: logged touchpoints and scheduled reminders |
| `commission_rules` | Per-salesman agreement, percentage or tiered, effective-dated |
| `commission_ledger` | Calculated/settled commission per salesman per period |

No columns were added to any existing table, and aging is derived rather than
stored, so **upgrading to v32 cannot change what any customer is shown to owe.**

## Files

| File | What |
|---|---|
| `lib/core/database/migrations/migration_v32.dart` | The three tables + six indexes |
| `lib/models/collection_activity_model.dart` | `CollectionActivity`, type/status enums |
| `lib/models/commission_rule_model.dart` | `CommissionRule`, `CommissionTier`, `CommissionRuleType` |
| `lib/models/commission_settlement_model.dart` | `CommissionSettlement`, status enum |
| `lib/repositories/collections_repository.dart` | Activity CRUD + ledger reads for aging |
| `lib/repositories/commission_repository.dart` | Rules, settlements, gross-sales query |
| `lib/services/collections_service.dart` | FIFO aging walk, activities, reminders |
| `lib/services/commission_service.dart` | Rule selection, tier maths, settlements |
| `lib/services/collections_exceptions.dart`, `commission_exceptions.dart` | Typed failures |
| `lib/features/collections/screens/collections_screen.dart` | Aging + follow-up worklist |
| `lib/features/commission/screens/commission_screen.dart` | Rules + settlements |

Both screens live in their own feature folders rather than `features/reports/`,
matching Tasks 2.1–2.3: `reports/` is read-only output, and both of these
write.

Routes `/collections` and `/commission` are **manager-gated and deliberately
not in `_accountantAllowedRoutes`** — the same open policy question flagged in
Tasks 2.1, 2.2 and 2.3, with the same answer: that set is documented as a
read-only slice, and widening it is a human's call. **If accountants should see
the receivable aging or the commission liability, add these two routes to that
set.**

## Known gaps

Listed rather than silently dropped.

- **Sales returns are not deducted from commissionable sales.** Cancelled sales
  are excluded (the sale is void), but a *returned* sale keeps its
  `net_amount`. Deducting returns needs a product decision this task file does
  not make: whether a return reduces the period it was returned in or the
  period the sale was made in. Left as-is, flagged here. It matters most where
  returns are large and late.
- **The service would accept overlapping settlement periods.** The UNIQUE
  constraint only catches an exact repeat. The screen offers whole months only,
  so this cannot happen through the UI, but a caller could double-pay an
  overlap. A real fix is a range-overlap check in `createSettlement`.
- **Commission is not in the GL** — see above.
- **Aging is a full ledger scan.** Every entry at or before the as-of date is
  read and walked in Dart. Correct and fine at shop scale; a shop with years of
  history and thousands of credit customers would want the walk incrementalised
  or a materialised open-charge table.
- **No SMS or email sending.** Only WhatsApp, and only by opening the compose
  screen. See above.
- **No customer-facing dunning automation.** There is no background job runner
  in this app (re-confirmed for the third time — the only `Timer.periodic` is
  UI refresh in `billing_screen.dart`). Overdue follow-ups appear in the
  worklist when a manager opens the screen; nothing chases anyone on its own.
- **The Phase 1 gap that sale cancellations don't post to GL is still open**
  and still relevant here: the aging report reads `customer_ledger`, which
  *does* record cancellations, so aging is correct — but the GL and the
  receivable aging will disagree for any cancelled credit sale. Reconcile
  against the ledger, not the GL, until that Phase 1 follow-up lands.
- **No widget tests** for the two new screens — same local convention as Tasks
  2.1–2.3; this codebase has essentially none.
