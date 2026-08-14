import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite/sqflite.dart';

import 'package:supermart_pos/core/database/database_helper.dart';
import 'package:supermart_pos/core/database/migrations/migration_v28.dart';
import 'package:supermart_pos/models/chart_of_account_model.dart';
import 'package:supermart_pos/models/gl_entry_model.dart';
import 'package:supermart_pos/repositories/gl_repository.dart';

/// See the note on the same class in
/// `test/services/financial_year_close_service_test.dart` — lets
/// `DatabaseHelper.instance` open a real database under `flutter_test`.
class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this._path);
  final String _path;

  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late GLRepository repo;
  late Database db;

  const fy = '25-26';

  /// A date inside financial year 25-26 (1 Apr 2025 – 31 Mar 2026).
  final inFy = DateTime(2025, 6, 15);

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('gl_repository_test');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
    db = await DatabaseHelper.instance.database;
  });

  tearDownAll(() async {
    await DatabaseHelper.instance.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  setUp(() async {
    repo = GLRepository();
    // Each test starts from the seeded chart of accounts and an empty journal.
    await db.delete('gl_entries');
    await db.delete('gl_balances');
    await db.delete('chart_of_accounts', where: 'is_system = 0');
  });

  group('accounts', () {
    test('createAccount round-trips every field through sqflite', () async {
      final account = ChartOfAccount.create(
        code: '6000',
        name: 'Marketing',
        type: AccountType.expense,
        subType: 'operating_expense',
        description: 'Ads and promotions',
        openingBalance: 1500.50,
      );

      await repo.createAccount(account);

      final loaded = await repo.getAccount(account.id);
      expect(loaded, isNotNull);
      expect(loaded!.code, '6000');
      expect(loaded.name, 'Marketing');
      expect(loaded.type, AccountType.expense);
      expect(loaded.subType, 'operating_expense');
      expect(loaded.description, 'Ads and promotions');
      expect(loaded.openingBalance, 1500.50);
      expect(loaded.isActive, isTrue);
      expect(loaded.isSystem, isFalse);
      expect(loaded.createdAt, greaterThan(0));
      // Equatable equality holds across a database round-trip.
      expect(loaded, account);
    });

    test('getAccount returns null for an unknown id rather than throwing', () async {
      expect(await repo.getAccount('nope'), isNull);
    });

    test('getAccountByCode finds a seeded account', () async {
      final cash = await repo.getAccountByCode('1000');

      expect(cash, isNotNull);
      expect(cash!.name, 'Cash');
      expect(cash.type, AccountType.asset);
      expect(cash.isSystem, isTrue);
      expect(await repo.getAccountByCode('9999'), isNull);
    });

    test('a duplicate account code is rejected', () async {
      final duplicate = ChartOfAccount.create(
        code: '1000', // Cash, already seeded
        name: 'Cash In Hand',
        type: AccountType.asset,
      );

      expect(() => repo.createAccount(duplicate), throwsA(isA<DatabaseException>()));
      // Still exactly one account holding that code.
      final rows = await db.query('chart_of_accounts', where: 'code = ?', whereArgs: ['1000']);
      expect(rows.length, 1);
    });

    test('getAllAccounts filters by type and by active flag', () async {
      final assets = await repo.getAllAccounts(type: AccountType.asset);
      expect(assets.map((a) => a.code), ['1000', '1010', '1100', '1200', '1500']);
      expect(assets.every((a) => a.type == AccountType.asset), isTrue);

      final revenue = await repo.getAllAccounts(type: AccountType.revenue);
      expect(revenue.map((a) => a.code), ['4000', '4100', '4900']);

      final all = await repo.getAllAccounts();
      expect(all.length, MigrationV28.defaultAccounts.length);

      await repo.deactivateAccount('coa_4900');
      final active = await repo.getAllAccounts(isActive: true);
      final inactive = await repo.getAllAccounts(isActive: false);
      expect(active.length, MigrationV28.defaultAccounts.length - 1);
      expect(inactive.map((a) => a.code), ['4900']);
    });

    test('searchAccounts matches on code and on name', () async {
      expect((await repo.searchAccounts('1200')).map((a) => a.name), ['Inventory']);
      expect((await repo.searchAccounts('cash')).map((a) => a.code), ['1000']);
      // A shared word finds every account carrying it.
      expect((await repo.searchAccounts('Revenue')).map((a) => a.code), ['4000', '4100']);
      expect(await repo.searchAccounts('no-such-account'), isEmpty);
    });

    test('updateAccount saves changes and stamps updated_at, without moving created_at', () async {
      final original = (await repo.getAccountByCode('1000'))!;
      expect(original.updatedAt, isNull);

      await repo.updateAccount(ChartOfAccount(
        id: original.id,
        code: original.code,
        name: 'Cash In Hand',
        type: original.type,
        subType: original.subType,
        description: 'Renamed by a store manager',
        isSystem: original.isSystem,
      ));

      final updated = (await repo.getAccount(original.id))!;
      expect(updated.name, 'Cash In Hand');
      expect(updated.description, 'Renamed by a store manager');
      expect(updated.createdAt, original.createdAt, reason: 'created_at must not be rewritten by an update');
      expect(updated.updatedAt, isNotNull);
    });

    test('deactivateAccount hides the account without deleting its history', () async {
      await repo.postEntry(GLEntry.post(
        entryDate: inFy,
        accountId: 'coa_5200',
        amount: 25000,
        isDebit: true,
        description: 'Shop rent',
        referenceType: 'Manual',
      ));

      await repo.deactivateAccount('coa_5200');

      final account = (await repo.getAccount('coa_5200'))!;
      expect(account.isActive, isFalse);
      // The posted entry survives — deactivating is not deleting.
      expect(await repo.getEntriesByAccount('coa_5200'), hasLength(1));
    });

    test('seedDefaultAccounts run a second time does not duplicate rows', () async {
      final before = await repo.getAllAccounts();

      await repo.seedDefaultAccounts();
      await repo.seedDefaultAccounts();

      final after = await repo.getAllAccounts();
      expect(after.length, before.length);
      expect(after.length, MigrationV28.defaultAccounts.length);
      expect(after.map((a) => a.code).toSet().length, after.length, reason: 'every code appears exactly once');
    });

    test('seedDefaultAccounts restores an account someone deleted', () async {
      await db.delete('chart_of_accounts', where: 'code = ?', whereArgs: ['5400']);
      expect(await repo.getAccountByCode('5400'), isNull);

      await repo.seedDefaultAccounts();

      expect((await repo.getAccountByCode('5400'))!.name, 'Depreciation');
    });
  });

  group('entries', () {
    test('postEntry writes a debit line that reads back identically', () async {
      final entry = GLEntry.post(
        entryDate: inFy,
        accountId: 'coa_1000',
        amount: 250.75,
        isDebit: true,
        description: 'Cash sale',
        referenceType: 'Sale',
        referenceId: 'sale-1',
        createdBy: 'user_admin',
      );

      await repo.postEntry(entry);

      final loaded = (await repo.getEntry(entry.id))!;
      expect(loaded, entry);
      expect(loaded.debit, 250.75);
      expect(loaded.credit, 0);
      expect(loaded.isDebit, isTrue);
      expect(loaded.amount, 250.75);
      expect(loaded.financialYear, fy, reason: '15 Jun 2025 falls in FY 25-26');
      expect(loaded.createdBy, 'user_admin');
    });

    test('getEntriesByAccount returns only that account, oldest first', () async {
      await repo.postEntry(GLEntry.post(
        entryDate: DateTime(2025, 8, 1),
        accountId: 'coa_1000',
        amount: 100,
        isDebit: true,
        description: 'August',
        referenceType: 'Manual',
      ));
      await repo.postEntry(GLEntry.post(
        entryDate: DateTime(2025, 5, 1),
        accountId: 'coa_1000',
        amount: 200,
        isDebit: true,
        description: 'May',
        referenceType: 'Manual',
      ));
      await repo.postEntry(GLEntry.post(
        entryDate: DateTime(2025, 6, 1),
        accountId: 'coa_4000',
        amount: 300,
        isDebit: false,
        description: 'Other account',
        referenceType: 'Manual',
      ));

      final entries = await repo.getEntriesByAccount('coa_1000');

      expect(entries.map((e) => e.description), ['May', 'August']);
    });

    test('getEntriesByAccount honours the from/to date window', () async {
      for (final month in [4, 6, 9]) {
        await repo.postEntry(GLEntry.post(
          entryDate: DateTime(2025, month, 10),
          accountId: 'coa_1000',
          amount: 50,
          isDebit: true,
          description: 'month-$month',
          referenceType: 'Manual',
        ));
      }

      final window = await repo.getEntriesByAccount(
        'coa_1000',
        from: DateTime(2025, 5, 1),
        to: DateTime(2025, 8, 1),
      );

      expect(window.map((e) => e.description), ['month-6']);
    });

    test('getEntriesByReference returns both sides of one document', () async {
      await repo.postEntry(GLEntry.post(
        entryDate: inFy,
        accountId: 'coa_1000',
        amount: 500,
        isDebit: true,
        description: 'Cash sale',
        referenceType: 'Sale',
        referenceId: 'sale-42',
      ));
      await repo.postEntry(GLEntry.post(
        entryDate: inFy,
        accountId: 'coa_4000',
        amount: 500,
        isDebit: false,
        description: 'Cash sale',
        referenceType: 'Sale',
        referenceId: 'sale-42',
      ));
      await repo.postEntry(GLEntry.post(
        entryDate: inFy,
        accountId: 'coa_1000',
        amount: 900,
        isDebit: true,
        description: 'A different sale',
        referenceType: 'Sale',
        referenceId: 'sale-43',
      ));

      final lines = await repo.getEntriesByReference('Sale', 'sale-42');

      expect(lines, hasLength(2));
      expect(lines.map((e) => e.accountId).toSet(), {'coa_1000', 'coa_4000'});
      expect(lines.fold<double>(0, (sum, e) => sum + e.debit), 500);
      expect(lines.fold<double>(0, (sum, e) => sum + e.credit), 500);
    });

    test('several lines may hit the same account for one reference', () async {
      // Deliberately allowed: revenue split across categories on one sale.
      for (final amount in [100.0, 250.0]) {
        await repo.postEntry(GLEntry.post(
          entryDate: inFy,
          accountId: 'coa_4000',
          amount: amount,
          isDebit: false,
          description: 'Split revenue',
          referenceType: 'Sale',
          referenceId: 'sale-split',
        ));
      }

      expect(await repo.getEntriesByReference('Sale', 'sale-split'), hasLength(2));
    });

    test('getEntriesByFinancialYear separates one year from the next', () async {
      await repo.postEntry(GLEntry.post(
        entryDate: DateTime(2025, 6, 1), // FY 25-26
        accountId: 'coa_1000',
        amount: 100,
        isDebit: true,
        description: 'this year',
        referenceType: 'Manual',
      ));
      await repo.postEntry(GLEntry.post(
        entryDate: DateTime(2026, 6, 1), // FY 26-27
        accountId: 'coa_1000',
        amount: 200,
        isDebit: true,
        description: 'next year',
        referenceType: 'Manual',
      ));

      expect((await repo.getEntriesByFinancialYear('25-26')).map((e) => e.description), ['this year']);
      expect((await repo.getEntriesByFinancialYear('26-27')).map((e) => e.description), ['next year']);
    });
  });

  group('balances', () {
    /// Posts [amount] to [accountId] on the debit or credit side.
    Future<void> post(String accountId, double amount, {required bool isDebit}) {
      return repo.postEntry(GLEntry.post(
        entryDate: inFy,
        accountId: accountId,
        amount: amount,
        isDebit: isDebit,
        description: 'test',
        referenceType: 'Manual',
      ));
    }

    test('recalculateBalance sums a debit-nature account debit-minus-credit', () async {
      // Cash (asset): 1000 in, 250 out -> 750 on hand.
      await post('coa_1000', 1000, isDebit: true);
      await post('coa_1000', 250, isDebit: false);

      final balance = await repo.recalculateBalance('coa_1000', fy);

      expect(balance.totalDebit, 1000);
      expect(balance.totalCredit, 250);
      expect(balance.balance, 750);
      expect(balance.rawDifference, 750);
      expect(balance.lastUpdated, greaterThan(0));
    });

    test('recalculateBalance sums a credit-nature account credit-minus-debit', () async {
      // Sales Revenue: 900 earned, 100 reversed -> 800 of income, not -800.
      await post('coa_4000', 900, isDebit: false);
      await post('coa_4000', 100, isDebit: true);

      final balance = await repo.recalculateBalance('coa_4000', fy);

      expect(balance.totalDebit, 100);
      expect(balance.totalCredit, 900);
      expect(balance.balance, 800);
      expect(balance.rawDifference, -800, reason: 'raw is always debit minus credit');
    });

    test('recalculateBalance counts only the requested financial year', () async {
      await post('coa_1000', 500, isDebit: true); // FY 25-26
      await repo.postEntry(GLEntry.post(
        entryDate: DateTime(2026, 5, 1), // FY 26-27
        accountId: 'coa_1000',
        amount: 700,
        isDebit: true,
        description: 'next year',
        referenceType: 'Manual',
      ));

      expect((await repo.recalculateBalance('coa_1000', '25-26')).balance, 500);
      expect((await repo.recalculateBalance('coa_1000', '26-27')).balance, 700);
    });

    test('recalculateBalance on an account with no entries yields a zero row', () async {
      final balance = await repo.recalculateBalance('coa_1500', fy);

      expect(balance.totalDebit, 0);
      expect(balance.totalCredit, 0);
      expect(balance.balance, 0);
    });

    test('recalculating twice updates the row in place, keeping its id', () async {
      await post('coa_1000', 100, isDebit: true);
      final first = await repo.recalculateBalance('coa_1000', fy);

      await post('coa_1000', 400, isDebit: true);
      final second = await repo.recalculateBalance('coa_1000', fy);

      expect(second.id, first.id, reason: 'the cached row is updated, not replaced');
      expect(second.balance, 500);
      final rows = await db.query('gl_balances', where: 'account_id = ?', whereArgs: ['coa_1000']);
      expect(rows, hasLength(1));
    });

    test('recalculateBalance rejects an unknown account', () async {
      expect(
        () => repo.recalculateBalance('coa_does_not_exist', fy),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('getAccountBalance returns null until the balance is calculated', () async {
      await post('coa_1000', 100, isDebit: true);
      expect(await repo.getAccountBalance('coa_1000', fy), isNull);

      await repo.recalculateBalance('coa_1000', fy);

      expect((await repo.getAccountBalance('coa_1000', fy))!.balance, 100);
    });

    test('getAllBalances returns one year only', () async {
      await post('coa_1000', 100, isDebit: true);
      await post('coa_4000', 100, isDebit: false);
      await repo.recalculateBalance('coa_1000', fy);
      await repo.recalculateBalance('coa_4000', fy);
      await repo.recalculateBalance('coa_1000', '26-27');

      final thisYear = await repo.getAllBalances(fy);
      expect(thisYear.map((b) => b.accountId).toSet(), {'coa_1000', 'coa_4000'});
      expect(await repo.getAllBalances('26-27'), hasLength(1));
      expect(await repo.getAllBalances('99-00'), isEmpty);
    });
  });

  group('transaction participation', () {
    test('an entry posted inside a rolled-back transaction leaves nothing behind', () async {
      // GL writes have to be able to fail together with the sale that caused
      // them — that is what the `executor` parameter exists for.
      await expectLater(
        db.transaction((txn) async {
          await repo.postEntry(
            GLEntry.post(
              entryDate: inFy,
              accountId: 'coa_1000',
              amount: 100,
              isDebit: true,
              description: 'doomed',
              referenceType: 'Sale',
              referenceId: 'sale-rollback',
            ),
            executor: txn,
          );
          throw Exception('sale failed after the GL line was written');
        }),
        throwsA(isA<Exception>()),
      );

      expect(await repo.getEntriesByReference('Sale', 'sale-rollback'), isEmpty);
    });

    test('a committed transaction persists both the entry and its balance', () async {
      await db.transaction((txn) async {
        await repo.postEntry(
          GLEntry.post(
            entryDate: inFy,
            accountId: 'coa_1000',
            amount: 640,
            isDebit: true,
            description: 'Cash sale',
            referenceType: 'Sale',
            referenceId: 'sale-commit',
          ),
          executor: txn,
        );
        await repo.recalculateBalance('coa_1000', fy, executor: txn);
      });

      expect(await repo.getEntriesByReference('Sale', 'sale-commit'), hasLength(1));
      expect((await repo.getAccountBalance('coa_1000', fy))!.balance, 640);
    });
  });

  group('model invariants', () {
    test('a two-sided entry is rejected at construction', () {
      expect(
        () => GLEntry(
          id: 'x',
          entryDate: 0,
          referenceType: 'Manual',
          description: 'both sides',
          accountId: 'coa_1000',
          debit: 100,
          credit: 100,
          financialYear: fy,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('a zero-amount entry is rejected at construction', () {
      expect(
        () => GLEntry(
          id: 'x',
          entryDate: 0,
          referenceType: 'Manual',
          description: 'no amount',
          accountId: 'coa_1000',
          financialYear: fy,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('a negative amount is rejected at construction', () {
      expect(
        () => GLEntry(
          id: 'x',
          entryDate: 0,
          referenceType: 'Manual',
          description: 'negative',
          accountId: 'coa_1000',
          debit: -100,
          financialYear: fy,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('debit/credit nature is defined once and applies to all five types', () {
      expect(isNormallyDebit(AccountType.asset), isTrue);
      expect(isNormallyDebit(AccountType.expense), isTrue);
      expect(isNormallyDebit(AccountType.liability), isFalse);
      expect(isNormallyDebit(AccountType.equity), isFalse);
      expect(isNormallyDebit(AccountType.revenue), isFalse);

      expect(signedBalance(300, 100, AccountType.asset), 200);
      expect(signedBalance(100, 300, AccountType.revenue), 200);
    });
  });
}
