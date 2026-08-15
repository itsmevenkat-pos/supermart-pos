# Phase 2: Enterprise Features — Execution Guide

Same deal as [../README.md](../README.md) (Phase 1's guide) — read that first,
its conventions section (models/repos/services style, dynamic migration
version rule, financial year format) applies here unchanged. This file only
covers what's different for Phase 2.

**The fictional `claude-code` CLI, `.clauderc-phase2`, and `develop` branch
referenced in the original Phase 2 drafts don't exist / aren't used here.**
This repo has one long-lived branch, `main`. Work on `feature/phase2-<name>`,
same protocol as Phase 1: track cross-run state in
`tasks/phase2/PROGRESS.md`, pull latest `main` at the start of every run,
commit + push per task, open a PR when a module is done.

## Phase 1 is merged

`main` now has `GLService`, `GLRepository`, `FinancialStatementService`,
the `chart_of_accounts`/`gl_entries`/`gl_balances` tables, and
`isNormallyDebit`/`signedBalance` from `chart_of_account_model.dart`. Use
these directly — don't re-derive GL posting logic. See
`docs/GL_ARCHITECTURE.md` for what's actually there (some things deviated
from Phase 1's task files during implementation — that doc reflects reality,
these Phase 2 files' assumptions about Phase 1 do not).

**Known Phase 1 gaps that affect Phase 2 work:**
- **COGS is not posted** (account `5000` stays at 0). If a Phase 2 feature
  needs COGS (none currently do), that's a Phase 1 follow-up, not something
  to patch around inside Phase 2.
- **Sale cancellations don't post to GL.** If Task 4 (Collections) or
  anything else needs to reconcile against cancelled sales, account for this
  gap rather than assuming GL is authoritative for cancellations.
- **GST isn't split from Sales Revenue** — the whole bill credits account
  `4000`.

## Migration versions

Read at execution time, same rule as Phase 1 — **do not** use the `v26`
`v27` `v28` numbers the original Task 2.1/2.2/2.3 drafts specify. Those are
already taken (`v26` = loyalty earn-rate setting, `v27` = purchase-unit
conversion, `v28` = Phase 1 GL). Check `AppConstants.dbVersion` and the
highest `if (oldVersion < N)` block in `database_helper.dart` fresh, every
run — this codebase has multiple things landing on `main` concurrently
(there are at least two other automations touching this repo).

## Read this before starting Task 2: Loyalty Points

**Most of what `02-loyalty-points.md` describes already exists.** Before
writing a single line for that task, read:
- `lib/models/customer_model.dart` — `loyaltyPoints` field already there.
- `lib/models/sale_model.dart` — `loyaltyPointsRedeemed` already there.
- `lib/core/utils/loyalty_utils.dart` — tier computation
  (`computeTier`) and point multipliers (`pointMultiplierForRating`) by
  `CustomerRating` (regular/bronze/silver/gold — **4 tiers, not the 3
  Silver/Gold/Platinum the task file assumes**), already there.
- `lib/features/billing/screens/billing_screen.dart` (`_showRedeemPointsDialog`)
  and `lib/providers/cart_provider.dart` — redemption at checkout, already
  wired into billing.
- `lib/services/billing_service.dart` — points earned/redeemed already
  applied on sale completion.
- `migration_v26.dart` / `StoreRepository` — per-store configurable earn
  rate (`bonus_points_threshold`) and redemption value
  (`loyalty_value_per_point`), already there.

The task file was written from a feature audit that's now stale on this
point. Task 2.2 (corrected) below is scoped to the **actual gaps**, not a
rebuild — see that file.

## Task order

Unlike Phase 1, these four are largely independent of each other (only
Collections/Commission touches anything the others do) — the original
"strict order" isn't load-bearing. Suggested order, still sequential per
run for the same reason as Phase 1 (bounded sessions, one thing done well
beats four things half-started):

1. [01-bank-reconciliation.md](01-bank-reconciliation.md)
2. [02-loyalty-points.md](02-loyalty-points.md) — gap-closing, not from-scratch
3. [03-payment-gateways.md](03-payment-gateways.md)
4. [04-collections-commission.md](04-collections-commission.md)

## What "done" means

Same standard as Phase 1: `flutter analyze` clean against the current
baseline (re-measure it fresh, Phase 1 changed it), full `flutter test`
suite green, and every new public service/repository method has a test —
not a literal "90% coverage" number pulled from an estimate that never saw
this codebase.
