# Task 1.4: Financial Statements

Depends on: 03-gl-service-logic.md.

## Reports

`lib/services/financial_statement_service.dart`:

- `generateTrialBalance(financialYear)` → for every active account, its
  signed balance split back into a debit column (if normally-debit and
  positive, or normally-credit and negative) and credit column, plus
  `totalDebits`/`totalCredits`/`isBalanced` (`(totalDebits - totalCredits).abs() < 0.01`).
- `generatePLStatement({required String financialYear})` → sum Revenue
  accounts, sum Expense accounts (COGS broken out separately using account
  `5000`), `grossProfit = revenue - cogs`, `netProfit = revenue - cogs - otherExpenses`.
  Don't invent an opening/closing inventory calculation from scratch —
  check whether `lib/services/report_service.dart` or
  `lib/services/advanced_report_service.dart` already computes inventory
  valuation, and reuse it rather than recomputing independently (two
  independent COGS calculations that can silently drift apart is worse
  than importing one).
- `generateBalanceSheet({required String financialYear, DateTime? asOf})` →
  Assets (current vs. fixed, split by `sub_type` on `chart_of_accounts`),
  Liabilities (current vs. long-term), Equity (including current-year net
  profit from P&L rolled into Retained Earnings for display — don't
  actually post it as a GL entry until the year is closed). Expose
  `isBalanced` the same way as Trial Balance.

Keep all three read-only — they compute from `gl_entries`/`gl_balances`,
never write.

## UI

Add three entries to the existing reports screen
(`lib/features/reports/screens/reports_screen.dart`) the same way the
current reports are registered there — don't build a separate
navigation entry point. New screens:
- `lib/features/reports/screens/trial_balance_screen.dart`
- `lib/features/reports/screens/pl_statement_screen.dart`
- `lib/features/reports/screens/balance_sheet_screen.dart`

Match the layout/widget conventions of an existing report screen in that
folder (e.g. `party_statement_screen.dart`) rather than designing new UI
patterns. Financial year selector should reuse whatever widget/provider the
app already uses elsewhere for financial-year selection, if one exists —
check `lib/providers/` before adding a new one.

Export: check what export mechanism existing reports already use (PDF/CSV)
before adding a new dependency — this app already does PDF invoices, so a
PDF package is likely already in `pubspec.yaml`.

## Tests

`test/services/financial_statement_service_test.dart` — post a known set of
compound GL entries via `GLService` in test setup, then assert:
- Trial Balance `isBalanced == true` and totals match hand-computed sums.
- P&L gross/net profit match hand-computed values for the posted data.
- Balance Sheet `isBalanced == true` (Assets == Liabilities + Equity).
- An intentionally-impossible scenario (if you can construct one without
  bypassing `GLService`'s balancing check) correctly reports `isBalanced ==
  false` rather than throwing — these are read-only diagnostic reports,
  they should surface a broken state, not crash on one.

## Done when

`flutter analyze` clean, new test file passes, and the three screens are
reachable from Reports in a normal app run (verify by actually launching
the app, not just compiling — see if this repo's `README.md` documents how
to run it, e.g. `flutter run -d windows`).
