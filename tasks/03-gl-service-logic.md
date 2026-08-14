# Task 1.3: GL Service Logic

Depends on: 02-gl-models-repos.md. Read [README.md](README.md) — in
particular, entries must check `FinancialYearCloseService.isFinancialYearClosed()`
before posting.

## `lib/services/gl_service.dart`

```dart
class GLService {
  GLService({GLRepository? glRepository, FinancialYearCloseService? closeService})
      : _glRepository = glRepository ?? GLRepository(),
        _closeService = closeService ?? FinancialYearCloseService();
  ...
}
```

Methods:

- `postEntry({required DateTime entryDate, required String accountId, required double amount, required bool isDebit, required String description, required String referenceType, String? referenceId, String? createdBy})`
  → validates `amount > 0`, account exists + active, financial year (via
  `financialYearLabel(entryDate)`) not closed → inserts one `GLEntryModel` →
  calls `recalculateBalance` for that account/year → returns the entry.

- `postCompoundEntry({required DateTime entryDate, required String description, required String referenceType, String? referenceId, required Map<String, double> accounts, String? createdBy})`
  → `accounts` maps accountId to a signed amount: positive = debit,
  negative = credit. **Before posting anything**, sum positives and sum
  `-negatives`; if they don't match (within 0.01 for rounding), throw
  `UnbalancedEntry` and post nothing. Wrap the actual inserts in a single
  `db.transaction` so a failure partway through can't leave a half-posted
  compound entry.

- `getRunningBalance(accountId, {String? financialYear})` — reads the
  `gl_balances` cache (recalculating first if stale/missing), applying the
  debit/credit-nature rule below.

- `reverseEntry(entryId, {required String reason})` — loads the original,
  posts a new entry with debit/credit swapped, `reversalOfEntryId` set to
  the original's id, description prefixed `"Reversal: "`. Does not delete
  or mutate the original (audit trail).

- `getTrialBalance(financialYear)` — see 04-financial-statements.md, the
  service can delegate to `FinancialStatementService` or the two can share
  the underlying balance-fetching code; don't duplicate the SQL.

### Debit/credit nature (put this rule in exactly one place, referenced elsewhere)

```dart
bool isNormallyDebit(AccountType type) =>
    type == AccountType.asset || type == AccountType.expense;

double signedBalance(double totalDebit, double totalCredit, AccountType type) =>
    isNormallyDebit(type) ? totalDebit - totalCredit : totalCredit - totalDebit;
```

### Exceptions

`lib/services/gl_exceptions.dart`:
```dart
class GLException implements Exception { final String message; final String code; ... }
class AccountNotFound extends GLException { ... }
class UnbalancedEntry extends GLException { ... }
class ClosedPeriod extends GLException { ... }
```

## Integration with existing transactions

Do **not** touch `lib/services/billing_service.dart` or
`lib/repositories/purchase_repository.dart` speculatively — read them
first to find the single right place a completed sale/purchase becomes
"final" (after totals are computed, inside the existing transaction if
possible), and add one `glService.postCompoundEntry(...)` call there. Keep
it narrow:

- Sale: debit Cash/Receivable (`1000`/`1100` depending on payment mode —
  check how the existing code already distinguishes cash vs. credit sales,
  e.g. `customer_ledger_repository.dart`), credit Sales Revenue (`4000`).
- Purchase: debit Inventory (`1200`), credit Accounts Payable (`2000`).
- Sales return: reverse the original sale's compound entry via
  `reverseEntry` on each line, referenced by the return's id.

If GL posting fails (e.g. closed period), the sale/purchase/return itself
must not silently fail — decide (and document in the PR) whether GL posting
happens inside the same DB transaction as the sale (all-or-nothing) or is
best-effort with a logged failure. Prefer the former; check how
`stock_group_repository.dart`'s `propagateDelta` is called alongside stock
writes for the existing pattern of "side-effect inside the same
transaction."

## Tests

`test/services/gl_service_test.dart` (pattern: see
`test/services/financial_year_close_service_test.dart`):
- `postEntry` creates a correctly-signed entry.
- `postCompoundEntry` with balanced accounts succeeds; unbalanced throws
  `UnbalancedEntry` and nothing is written to `gl_entries` (verify via a
  repository read after the throw).
- `getRunningBalance` matches hand-computed expected balance after a
  sequence of debits/credits.
- `reverseEntry` produces the exact opposite debit/credit and both entries
  net to zero on `getRunningBalance`.
- Posting into a closed financial year throws `ClosedPeriod` (close a year
  via `FinancialYearCloseService` in the test setup, then attempt a post).
- At least one test exercising the real sale-completion path (through
  `billing_service.dart`, not calling `GLService` directly) to prove the
  integration actually fires.

## Done when

`flutter analyze` clean, `flutter test test/services/gl_service_test.dart`
passes, and the full existing test suite (`flutter test`) still passes —
this task touches shared code paths (billing/purchase), regressions here
are the highest-risk part of this phase.
