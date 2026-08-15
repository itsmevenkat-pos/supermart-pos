# Task 2.2: Loyalty Points — Gap Closing (NOT a from-scratch build)

Read [README.md](README.md)'s loyalty section first — most of this feature
already exists. **Start this task by re-confirming that inventory is still
accurate** (grep for the files listed in README.md), since this is a fast-
moving codebase and it may have moved further since these notes were
written. Do not create `LoyaltyAccountModel`, `LoyaltyRuleModel`,
`PointsTransactionModel`, a `loyalty_accounts` table, or a
`LoyaltyRepository` — equivalents already exist as fields on `Customer`/`Sale`
and logic in `loyalty_utils.dart`/`billing_service.dart`. Building parallel
versions would leave two disagreeing sources of truth for the same number.

## What already exists (verify, don't rebuild)

- Points earned and redeemed per sale: `Customer.loyaltyPoints`,
  `Sale.loyaltyPointsRedeemed`.
- Tiering: `computeTier()` in `loyalty_utils.dart`, 4 tiers
  (regular/bronze/silver/gold, not the task-file's Silver/Gold/Platinum),
  multiplier via `pointMultiplierForRating()`, thresholds configurable per
  store via `StoreRepository.getTierThresholds()`.
- Redemption at checkout: `billing_screen.dart`'s `_showRedeemPointsDialog`
  + `cart_provider.dart`'s `loyaltyPointsToRedeem`, applied in
  `billing_service.dart`.
- Per-store earn rate and redemption value: `bonus_points_threshold` /
  `loyalty_value_per_point` settings (`migration_v26.dart`).

## Actual gaps (this is the real scope of this task)

1. **No points transaction history / audit log.** `Customer.loyaltyPoints`
   is a running total with no record of individual earn/redeem events
   beyond what's implicit in `Sale.loyaltyPointsRedeemed` — there's no way
   to answer "how many points did this customer earn on March 3rd" or
   "show me every redemption this month." Add a `loyalty_point_events`
   table (`id, customer_id, event_type ('earn'|'redeem'|'adjust'), points,
   sale_id, created_at`), populated from the same call sites that already
   update `Customer.loyaltyPoints`, not a new parallel calculation.

2. **No point expiry.** Points never lapse. Add an optional
   `expires_at` per earn event on `loyalty_point_events`, and a service
   method (`expireOldPoints()`, callable on demand — don't assume a
   background scheduler exists in this app, check before relying on one)
   that sums still-valid points and reduces `Customer.loyaltyPoints` by
   whatever's expired, logging an `'expire'` event for the delta.

3. **No loyalty dashboard/analytics screen.** A per-customer view (points
   balance, tier, recent events from the new table) and a store-wide
   summary (points outstanding liability — sum of all `loyaltyPoints` ×
   `loyalty_value_per_point`, useful for the accountant since that's a real
   liability the Balance Sheet currently doesn't show — flag this as a
   possible future GL integration, don't build it now, out of scope creep
   territory). Check `lib/features/customers/screens/customer_history_screen.dart`
   for where a per-customer loyalty section could slot in before creating a
   new top-level screen.

4. **Tier count/names mismatch with the original audit** (3 tiers vs. 4).
   Don't change the tier count or names — `regular/bronze/silver/gold` is
   what's live and referenced from multiple files; renaming to
   Silver/Gold/Platinum would be a breaking, unrequested rename. If the
   business genuinely wants 3-tier naming, that's a product decision for
   the user, not something to silently change here.

## Tests

Add tests for the new event log and expiry logic (`test/services/` or
`test/repositories/`, whichever holds the code you add — check
`loyalty_utils_test.dart` for this repo's existing loyalty test
conventions first). Don't write new tests for earning/redemption/tiering
logic that already has coverage — check `test/core/utils/loyalty_utils_test.dart`
and `test/core/services/loyalty_service_test.dart` before assuming a gap
that isn't one.

## Done when

`flutter analyze` clean, full suite green, and specifically: existing
loyalty tests still pass unmodified (a sign nothing already-working was
touched) plus new tests for event log + expiry.
