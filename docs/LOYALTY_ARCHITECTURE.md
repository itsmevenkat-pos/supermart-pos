# Loyalty Points — Architecture

Phase 2, Task 2.2. This describes **what is actually in the codebase**,
including the parts that predate Phase 2 — because the Phase 2 task file was
written from an audit that had already gone stale, and the next person to work
on loyalty needs the real inventory, not that audit.

Read this before trusting any task file's claims about what loyalty does or
does not have.

## What already existed before Phase 2

None of this was built by Task 2.2. It was all live already and is unchanged:

| Concern | Where it lives |
|---|---|
| Running points balance | `customers.loyalty_points` (`Customer.loyaltyPoints`) |
| Points spent on a bill | `sales.loyalty_points_redeemed` (`Sale.loyaltyPointsRedeemed`) |
| Tier computation | `computeTier()` in `lib/core/utils/loyalty_utils.dart` |
| Tier multiplier | `pointMultiplierForRating()`, same file |
| Earning + redeeming on a sale | `SaleRepository.create` (inside the sale transaction) |
| Redemption at checkout | `billing_screen.dart` `_showRedeemPointsDialog`, `cart_provider.dart` |
| Earn rate per store | `stores.bonus_points_threshold` (₹ per point), MigrationV26 |
| Redemption value per store | `stores.loyalty_value_per_point` |
| Tier thresholds per store | `stores.tier_{bronze,silver,gold}_min_spent` |

**There are four tiers — `regular`, `bronze`, `silver`, `gold`** (see
`CustomerRating`). Task-file drafts that describe a three-tier
Silver/Gold/Platinum ladder are describing a system this app has never had.
Renaming would break several files and is a product decision, not a cleanup.

## What Task 2.2 added

Three gaps: no readable history, no expiry, no reporting.

### The event log is `bonus_points`, not a new table

`bonus_points` has existed since the original schema and `SaleRepository` has
written one row per points-moving sale since before Phase 2. Task 2.2's file
called for a new `loyalty_point_events` table; that was not built, because two
tables recording the same events is the "two disagreeing sources of truth"
problem the same task file warns about elsewhere.

`MigrationV31` widens the existing table instead:

| Column | Notes |
|---|---|
| `event_type` | `sale` \| `cancellation` \| `adjust` \| `expire`. Defaults to `sale`, which backfills every pre-existing row correctly — no data migration was needed. |
| `expires_at` | Seconds since epoch when *this row's* earned points lapse; NULL means never. |
| `expired_points` | How much of `points_earned` an expiry run has already written off. Makes sweeps re-runnable. |
| `note` | Why, for manual adjustments. |
| `created_by_user_id` | Who, for manual adjustments. |

Plus `stores.loyalty_points_expiry_days`, **defaulting to 0 = never expire**,
so upgrading to v31 cannot change any existing customer's balance.

`points_earned` and `points_redeemed` are kept as two non-negative magnitudes
rather than collapsed into one signed column — that is the shape the table has
always had and the shape existing rows are in. `LoyaltyPointEvent.netPoints`
gives the signed value where a caller wants it.

### `customers.loyalty_points` stays authoritative

The event log explains the balance; it does not replace it. Everything that
moves points writes both in one transaction. `LoyaltyService
.recomputeBalanceFromEvents()` rebuilds the balance from the log for
comparison, and deliberately **does not repair a mismatch** — points earned
before `bonus_points` had a writer legitimately have no events behind them, so
an automatic overwrite would destroy real balances.

### Expiry is FIFO, and idempotent

`LoyaltyService.expireOldPoints()` (all customers) and
`expireOldPointsForCustomer()` (one). The rule:

1. Earn lots are the rows with `points_earned > 0`, oldest first.
2. Every point ever *spent* (all `points_redeemed` except on `expire` rows)
   drains those lots oldest-first.
3. A lot whose `expires_at` has passed writes off whatever spending never
   reached. A customer who spent everything loses nothing.

Re-running is safe because what a sweep takes is written back to each lot's
`expired_points` (shrinking its capacity) while the `expire` row it writes is
excluded from the spending total — so the second pass sees smaller lots and
identical spending, and finds nothing.

The write-off is clamped at the customer's actual balance, so a log/balance
drift can never produce negative points.

**There is no scheduler.** This app runs no background jobs (no
`Timer.periodic` outside UI refresh, no workmanager/cron dependency), so expiry
only happens when a manager presses "Run Expiry Sweep" on the loyalty screen.
Turning the setting on does not, by itself, expire anything.

### Manual adjustments

`LoyaltyService.adjustPoints()` requires a non-zero amount, a reason and an
acting user, refuses to deduct more than the customer holds, and writes an
`audit_log` row inside the same transaction as the balance change.

### Cancellation reversal was wrong and is fixed

`SaleCancellationRepository` used to reverse points by recomputing
`netAmount / bonus_points_threshold`. That silently dropped the tier
multiplier, so cancelling a gold customer's bill clawed back roughly half the
points they had been given — and points the customer had *redeemed* on that
bill were never handed back at all.

It now reads the sale's `bonus_points` row and reverses exactly what was
recorded, clamped so a reversal cannot drive a balance negative, and logs the
reversal as a `cancellation` event. Sales predating the event log fall back to
the old estimate, since nothing recorded what they actually did.

## UI

- **Per customer** — a "Loyalty" tab on
  `lib/features/reports/screens/customer_history_screen.dart`: balance, worth,
  tier, lifetime totals, expiry warning, event history, and a manager-gated
  Adjust Points dialog.
- **Store-wide** — `lib/features/loyalty/screens/loyalty_summary_screen.dart`
  at `/loyalty`, manager-gated: outstanding liability, period activity, the
  expiry window setting and the sweep.

## Known gaps

- **The points liability is not posted to the General Ledger.** Outstanding
  points × redemption value is a real liability that the Phase 1 Balance Sheet
  does not show. The number is surfaced on the loyalty screen so a human can
  see it; booking it needs a chart-of-accounts addition and a posting rule for
  every earn and redeem, which is an accounting decision, not a gap-closing
  detail.
- **"Expiring soon" is an upper bound.** It sums lots due within 30 days
  without running the FIFO walk, then caps at the customer's balance. It can
  overstate for a customer who has spent recently. Exact would mean a full walk
  per customer per screen paint.
- **No widget tests.** Consistent with the rest of this codebase; service and
  repository logic is covered by 57 tests, UI is not.
- **Legacy points have no history.** Customers who earned points before
  `SaleRepository` started writing `bonus_points` have a balance with no events
  behind it. The UI says so explicitly rather than showing an empty list.
- **The old placeholder test still exists.** `test/core/services/
  loyalty_service_test.dart` asserts arithmetic on literals against a
  hardcoded ₹100/point that does not match this app's configurable rate, and
  imports nothing. It was left untouched — Task 2.2's brief was that existing
  loyalty tests pass unmodified. Real coverage is in
  `test/services/loyalty_service_test.dart`.
