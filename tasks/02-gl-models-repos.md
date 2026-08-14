# Task 1.2: GL Models & Repository

Depends on: 01-gl-schema.md. Read [README.md](README.md) for the
model/repository conventions (Equatable, `.create()` factory, provider at
bottom of repo file) — follow those exactly, not generic Dart style.

## Models

`lib/models/chart_of_account_model.dart`:

```dart
enum AccountType { asset, liability, equity, revenue, expense }

class ChartOfAccount extends Equatable {
  final String id;
  final String code;
  final String name;
  final AccountType type;
  final String? subType;
  final String? parentId;
  final bool isActive;
  final String? description;
  final double openingBalance;
  final int createdAt;
  final int? updatedAt;
  final bool isSystem;

  const ChartOfAccount({ ... required fields ... });

  factory ChartOfAccount.create({
    required String code,
    required String name,
    required AccountType type,
    String? subType,
    String? parentId,
    String? description,
    double openingBalance = 0,
    bool isSystem = false,
  }) => ChartOfAccount(
        id: const Uuid().v4(),
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        ... ,
      );

  Map<String, dynamic> toJson() => { 'account_type': type.name, ... }; // snake_case, enum -> .name
  factory ChartOfAccount.fromJson(Map<String, dynamic> map) => ChartOfAccount(
        type: AccountType.values.byName(map['account_type'] as String),
        ...
      );
}
```

`lib/models/gl_entry_model.dart` — mirror the table from Task 1.1
(`entryDate`, `referenceType`, `referenceId`, `description`, `accountId`,
`debit`, `credit`, `financialYear`, `createdBy`, `createdAt`,
`reversalOfEntryId`). Validate in the constructor or a `factory .post(...)`
that exactly one of `debit`/`credit` is > 0 and the other is 0 — throw
`ArgumentError` otherwise, don't silently allow garbage in.

`lib/models/gl_balance_model.dart` — `accountId`, `financialYear`,
`totalDebit`, `totalCredit`, `balance`, `lastUpdated`. Add a
`normalBalanceNature` helper (see 03-gl-service-logic.md for the
debit/credit-nature rule per `AccountType` — put that rule in one place,
either here or the service, not duplicated in both).

## Repository

`lib/repositories/gl_repository.dart`:

- Account CRUD: `createAccount`, `getAccount(id)`, `getAllAccounts({AccountType? type, bool? isActive})`,
  `searchAccounts(query)`, `updateAccount`, `deactivateAccount(id)`.
- Entries: `postEntry(GLEntryModel entry)` (single insert, no balancing
  logic here — that's the service's job), `getEntriesByAccount(accountId, {DateTime? from, DateTime? to})`,
  `getEntriesByReference(referenceType, referenceId)`.
- Balances: `getAccountBalance(accountId, financialYear)`,
  `getAllBalances(financialYear)`, `recalculateBalance(accountId, financialYear)`
  (re-sums `gl_entries` for that account+year and upserts `gl_balances` —
  this is the only place that table gets written).
- `seedDefaultAccounts()` — idempotent (use `ConflictAlgorithm.ignore` on
  `code`), called from the migration in Task 1.1 and safe to call again
  later without duplicating rows.

### Default chart of accounts

```
Assets       1000 Cash · 1010 Bank · 1100 Accounts Receivable · 1200 Inventory · 1500 Fixed Assets
Liabilities  2000 Accounts Payable · 2010 Credit Card · 2100 Short-term Loans · 2200 Long-term Loans
Equity       3000 Capital · 3100 Retained Earnings
Revenue      4000 Sales Revenue · 4100 Service Revenue · 4900 Other Income
Expenses     5000 Cost of Goods Sold · 5100 Salaries & Wages · 5200 Rent · 5300 Utilities · 5400 Depreciation · 5500 Interest Expense
```

All seeded with `isSystem: true` — the UI should refuse to delete (only
deactivate) system accounts.

## Tests

`test/repositories/gl_repository_test.dart` — copy the in-memory-DB setup
pattern from `test/repositories/product_batch_repository_test.dart`. Cover:
account CRUD, duplicate-code rejection, `postEntry` + `recalculateBalance`
producing the correct `balance`, and that `seedDefaultAccounts()` run twice
doesn't duplicate rows.

## Done when

- `flutter analyze` clean, `flutter test test/repositories/gl_repository_test.dart` passes.
- Default accounts exist after a fresh migration and after calling
  `seedDefaultAccounts()` a second time (still exactly one row per code).
