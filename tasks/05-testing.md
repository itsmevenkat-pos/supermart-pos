# Task 1.5: Consolidation Testing

Depends on: 01–04. Most of the real test-writing already happened inline
in each earlier task (that's deliberate — write tests next to the code
they cover, not as one giant deferred task). This task is the integration
pass across all of it.

## Add

`test/integration/gl_end_to_end_test.dart` — one full-cycle scenario using
the real DB migration path (not hand-inserted rows):
1. Fresh DB → default chart of accounts present.
2. Post a sale through `billing_service.dart` → correct GL entries exist,
   `getRunningBalance` on Cash and Sales Revenue reflect it.
3. Post a purchase → Inventory and Accounts Payable reflect it.
4. Generate Trial Balance → balanced.
5. Generate Balance Sheet → balanced.
6. Reverse one entry (simulate a correction) → balances net back correctly.
7. Close the financial year via `FinancialYearCloseService` → a further
   post attempt into that same year throws `ClosedPeriod`.

## Run and fix, don't just add more tests

```bash
flutter analyze
flutter test
```

Run the **entire** suite, not `-k GL`. This phase edits shared files
(`billing_service.dart`, `purchase_repository.dart`,
`database_helper.dart`) — a regression is more likely to show up in an
existing unrelated test than in a new GL-specific one. If anything existing
breaks, fix the GL code, not the pre-existing test (unless the pre-existing
test was asserting the specific bug this phase intentionally changes —
justify that explicitly in the commit message if so).

Skip the "generate a coverage percentage number" step from the original
draft of this task — it wasn't grounded in this codebase's actual test
tooling and chasing a numeric target isn't the goal. The goal is: every new
public method in `GLRepository`, `GLService`, and
`FinancialStatementService` has at least one test, and the full suite is
green.

## Done when

`flutter analyze` is clean and `flutter test` passes in full, including the
new end-to-end test.
