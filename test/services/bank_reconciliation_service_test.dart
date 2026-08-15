import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:supermart_pos/core/database/database_helper.dart';
import 'package:supermart_pos/models/bank_account_model.dart';
import 'package:supermart_pos/models/bank_transaction_model.dart';
import 'package:supermart_pos/models/gl_entry_model.dart';
import 'package:supermart_pos/repositories/bank_reconciliation_repository.dart';
import 'package:supermart_pos/repositories/gl_repository.dart';
import 'package:supermart_pos/services/bank_reconciliation_exceptions.dart';
import 'package:supermart_pos/services/bank_reconciliation_service.dart';

class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this._path);
  final String _path;

  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late BankReconciliationService service;
  late BankReconciliationRepository repository;
  late GLRepository glRepository;
  late String bankGlAccountId;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('bank_recon_service_test');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
    await DatabaseHelper.instance.database;
    // '1010' Bank, from Phase 1's seeded chart of accounts.
    bankGlAccountId = (await GLRepository().getAccountByCode('1010'))!.id;
  });

  tearDownAll(() async {
    await DatabaseHelper.instance.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  setUp(() async {
    service = BankReconciliationService();
    repository = BankReconciliationRepository();
    glRepository = GLRepository();
    final db = await DatabaseHelper.instance.database;
    await db.delete('bank_transactions');
    await db.delete('bank_statements');
    await db.delete('bank_accounts');
    await db.delete('gl_entries');
    await db.delete('gl_balances');
  });

  Future<BankAccount> makeAccount({
    double openingBalance = 0,
    bool linked = true,
  }) async {
    return repository.createAccount(BankAccount.create(
      accountNumber: '00112233445566',
      accountHolder: 'SuperMart Retail',
      bankName: 'State Bank',
      openingBalance: openingBalance,
      glAccountId: linked ? bankGlAccountId : null,
    ));
  }

  /// Posts a one-sided line straight to the bank GL account. Reconciliation
  /// only ever reads one account's side, so a full balanced pair would add
  /// noise without changing any assertion here.
  Future<GLEntry> postBankEntry({
    required DateTime date,
    required double amount,
    required bool isDebit,
    String description = 'Test entry',
  }) {
    return glRepository.postEntry(GLEntry.post(
      entryDate: date,
      accountId: bankGlAccountId,
      amount: amount,
      isDebit: isDebit,
      description: description,
      referenceType: 'Manual',
    ));
  }

  group('parseStatementCsv', () {
    test('parses a well-formed file including signed and quoted values', () {
      const csv = 'Date,Reference,Description,Amount\n'
          '2025-04-02,UTR001,Card settlement,1500.50\n'
          '2025-04-03,CHQ441,"Supplier payment, part 1",-900.25\n';

      final lines = service.parseStatementCsv(csv);

      expect(lines, hasLength(2));
      expect(lines.first.date, DateTime(2025, 4, 2));
      expect(lines.first.reference, 'UTR001');
      expect(lines.first.description, 'Card settlement');
      expect(lines.first.amount, 1500.50);
      expect(lines.last.amount, -900.25);
      expect(lines.last.description, 'Supplier payment, part 1');
    });

    test('reads dd/MM/yyyy day-first, the convention this app is built for', () {
      const csv = 'Date,Reference,Description,Amount\n03/04/2025,,Rent,-5000\n';

      final lines = service.parseStatementCsv(csv);

      expect(lines.single.date, DateTime(2025, 4, 3));
    });

    test('accepts accounting negatives, currency symbols and thousands separators', () {
      const csv = 'Date,Reference,Description,Amount\n'
          '2025-04-02,,Deposit,"₹1,20,000.00"\n'
          '2025-04-03,,Charge,(450.75)\n';

      final lines = service.parseStatementCsv(csv);

      expect(lines.first.amount, 120000.00);
      expect(lines.last.amount, -450.75);
    });

    test('skips blank rows and leaves optional columns null', () {
      const csv = 'Date,Reference,Description,Amount\n'
          '2025-04-02,,,100\n'
          '\n'
          '2025-04-04,,,200\n';

      final lines = service.parseStatementCsv(csv);

      expect(lines, hasLength(2));
      expect(lines.first.reference, isNull);
      expect(lines.first.description, isNull);
    });

    test('rejects a wrong header rather than guessing the columns', () {
      const csv = 'Date,Description,Amount,Reference\n2025-04-02,x,100,y\n';

      expect(
        () => service.parseStatementCsv(csv),
        throwsA(isA<StatementParseException>()),
      );
    });

    test('reports the row number of an unparseable date', () {
      const csv = 'Date,Reference,Description,Amount\n'
          '2025-04-02,,,100\n'
          'not-a-date,,,200\n';

      expect(
        () => service.parseStatementCsv(csv),
        throwsA(isA<StatementParseException>().having((e) => e.rowNumber, 'rowNumber', 3)),
      );
    });

    test('rejects an impossible calendar date instead of rolling it forward', () {
      const csv = 'Date,Reference,Description,Amount\n31/02/2025,,,100\n';

      expect(
        () => service.parseStatementCsv(csv),
        throwsA(isA<StatementParseException>()),
      );
    });

    test('rejects a non-numeric and a zero amount', () {
      expect(
        () => service.parseStatementCsv('Date,Reference,Description,Amount\n2025-04-02,,,abc\n'),
        throwsA(isA<StatementParseException>()),
      );
      expect(
        () => service.parseStatementCsv('Date,Reference,Description,Amount\n2025-04-02,,,0\n'),
        throwsA(isA<StatementParseException>()),
      );
    });

    test('rejects an empty file', () {
      expect(() => service.parseStatementCsv(''), throwsA(isA<StatementParseException>()));
    });
  });

  group('importStatement', () {
    test('writes the statement and every line, deriving the ending balance', () async {
      final account = await makeAccount(openingBalance: 1000);
      const csv = 'Date,Reference,Description,Amount\n'
          '2025-04-02,UTR001,Card settlement,1500\n'
          '2025-04-03,CHQ441,Supplier payment,-500\n';

      final statement = await service.importStatement(
        bankAccountId: account.id,
        statementDate: DateTime(2025, 4, 30),
        beginningBalance: 1000,
        csv: csv,
      );

      expect(statement.beginningBalance, 1000);
      expect(statement.endingBalance, 2000);
      final lines = await repository.getTransactionsForStatement(statement.id);
      expect(lines, hasLength(2));
      expect(lines.every((l) => l.matchStatus == BankMatchStatus.unmatched), isTrue);
    });

    test('keeps the bank\'s own stated ending balance when one is given', () async {
      final account = await makeAccount(openingBalance: 1000);
      const csv = 'Date,Reference,Description,Amount\n2025-04-02,,Deposit,1500\n';

      final statement = await service.importStatement(
        bankAccountId: account.id,
        statementDate: DateTime(2025, 4, 30),
        beginningBalance: 1000,
        endingBalance: 2600,
        csv: csv,
      );

      // Deliberately not 2500: the gap between the stated and derived figure is
      // a finding, and deriving it away would hide it.
      expect(statement.endingBalance, 2600);
    });

    test('writes nothing when a later row fails to parse', () async {
      final account = await makeAccount();
      const csv = 'Date,Reference,Description,Amount\n'
          '2025-04-02,,,100\n'
          'garbage,,,200\n';

      await expectLater(
        service.importStatement(
          bankAccountId: account.id,
          statementDate: DateTime(2025, 4, 30),
          beginningBalance: 0,
          csv: csv,
        ),
        throwsA(isA<StatementParseException>()),
      );

      expect(await repository.getStatementsForAccount(account.id), isEmpty);
      expect(await repository.getTransactionsForAccount(account.id), isEmpty);
    });

    test('rejects an unknown bank account', () async {
      await expectLater(
        service.importStatement(
          bankAccountId: 'nope',
          statementDate: DateTime(2025, 4, 30),
          beginningBalance: 0,
          csv: 'Date,Reference,Description,Amount\n2025-04-02,,,100\n',
        ),
        throwsA(isA<BankAccountNotFound>()),
      );
    });
  });

  group('suggestMatches', () {
    test('pairs a same-day, same-amount line with its ledger entry', () async {
      final account = await makeAccount();
      await service.importStatement(
        bankAccountId: account.id,
        statementDate: DateTime(2025, 4, 30),
        beginningBalance: 0,
        csv: 'Date,Reference,Description,Amount\n2025-04-02,,Card settlement,1500\n',
      );
      final entry = await postBankEntry(date: DateTime(2025, 4, 2), amount: 1500, isDebit: true);

      final suggestions = await service.suggestMatches(account.id);

      expect(suggestions, hasLength(1));
      expect(suggestions.single.entry.id, entry.id);
      expect(suggestions.single.isExact, isTrue);
      // Suggesting must not write.
      final line = (await repository.getTransactionsForAccount(account.id)).single;
      expect(line.matchStatus, BankMatchStatus.unmatched);
    });

    test('matches a money-out line against a ledger credit', () async {
      final account = await makeAccount();
      await service.importStatement(
        bankAccountId: account.id,
        statementDate: DateTime(2025, 4, 30),
        beginningBalance: 0,
        csv: 'Date,Reference,Description,Amount\n2025-04-05,,Supplier payment,-900\n',
      );
      await postBankEntry(date: DateTime(2025, 4, 5), amount: 900, isDebit: false);

      final suggestions = await service.suggestMatches(account.id);

      expect(suggestions, hasLength(1));
      expect(suggestions.single.isExact, isTrue);
    });

    test('allows a two-day posting delay but not a three-day one', () async {
      final account = await makeAccount();
      await service.importStatement(
        bankAccountId: account.id,
        statementDate: DateTime(2025, 4, 30),
        beginningBalance: 0,
        csv: 'Date,Reference,Description,Amount\n2025-04-10,,Late posting,750\n',
      );
      await postBankEntry(date: DateTime(2025, 4, 8), amount: 750, isDebit: true);

      final within = await service.suggestMatches(account.id);
      expect(within, hasLength(1));
      expect(within.single.dayDifference, 2);
      expect(within.single.isExact, isFalse);

      final db = await DatabaseHelper.instance.database;
      await db.delete('gl_entries');
      await postBankEntry(date: DateTime(2025, 4, 7), amount: 750, isDebit: true);

      expect(await service.suggestMatches(account.id), isEmpty);
    });

    test('will not match an amount that is off by more than a paisa', () async {
      final account = await makeAccount();
      await service.importStatement(
        bankAccountId: account.id,
        statementDate: DateTime(2025, 4, 30),
        beginningBalance: 0,
        csv: 'Date,Reference,Description,Amount\n2025-04-02,,Card settlement,1000\n',
      );
      // 5% off — the tolerance the original draft proposed, deliberately
      // rejected here: a reconciliation that accepts this hides real errors.
      await postBankEntry(date: DateTime(2025, 4, 2), amount: 950, isDebit: true);

      expect(await service.suggestMatches(account.id), isEmpty);
    });

    test('never suggests the same ledger entry for two statement lines', () async {
      final account = await makeAccount();
      await service.importStatement(
        bankAccountId: account.id,
        statementDate: DateTime(2025, 4, 30),
        beginningBalance: 0,
        csv: 'Date,Reference,Description,Amount\n'
            '2025-04-02,,Settlement A,500\n'
            '2025-04-02,,Settlement B,500\n',
      );
      await postBankEntry(date: DateTime(2025, 4, 2), amount: 500, isDebit: true);

      final suggestions = await service.suggestMatches(account.id);

      expect(suggestions, hasLength(1));
    });

    test('excludes ledger entries already claimed by a confirmed match', () async {
      final account = await makeAccount();
      await service.importStatement(
        bankAccountId: account.id,
        statementDate: DateTime(2025, 4, 30),
        beginningBalance: 0,
        csv: 'Date,Reference,Description,Amount\n'
            '2025-04-02,,Settlement A,500\n'
            '2025-04-02,,Settlement B,500\n',
      );
      final entry = await postBankEntry(date: DateTime(2025, 4, 2), amount: 500, isDebit: true);
      final lines = await repository.getTransactionsForAccount(account.id);
      await service.matchTransaction(lines.first.id, entry.id);

      expect(await service.suggestMatches(account.id), isEmpty);
    });

    test('refuses an account with no linked chart-of-accounts row', () async {
      final account = await makeAccount(linked: false);

      await expectLater(
        service.suggestMatches(account.id),
        throwsA(isA<BankAccountNotLinked>()),
      );
    });
  });

  group('autoMatch', () {
    test('confirms only the exact hits and leaves the near ones for a human', () async {
      final account = await makeAccount();
      await service.importStatement(
        bankAccountId: account.id,
        statementDate: DateTime(2025, 4, 30),
        beginningBalance: 0,
        csv: 'Date,Reference,Description,Amount\n'
            '2025-04-02,,Exact,500\n'
            '2025-04-10,,Delayed,750\n',
      );
      await postBankEntry(date: DateTime(2025, 4, 2), amount: 500, isDebit: true);
      await postBankEntry(date: DateTime(2025, 4, 8), amount: 750, isDebit: true);

      final confirmed = await service.autoMatch(account.id);

      expect(confirmed, 1);
      final lines = await repository.getTransactionsForAccount(account.id);
      expect(lines.firstWhere((l) => l.amount == 500).matchStatus, BankMatchStatus.matched);
      expect(lines.firstWhere((l) => l.amount == 750).matchStatus, BankMatchStatus.unmatched);
    });

    test('returns 0 and writes nothing when there is nothing exact', () async {
      final account = await makeAccount();
      await service.importStatement(
        bankAccountId: account.id,
        statementDate: DateTime(2025, 4, 30),
        beginningBalance: 0,
        csv: 'Date,Reference,Description,Amount\n2025-04-02,,Unmatched,500\n',
      );

      expect(await service.autoMatch(account.id), 0);
      final line = (await repository.getTransactionsForAccount(account.id)).single;
      expect(line.matchStatus, BankMatchStatus.unmatched);
    });
  });

  group('matchTransaction', () {
    test('rejects a GL entry that does not exist', () async {
      final account = await makeAccount();
      await service.importStatement(
        bankAccountId: account.id,
        statementDate: DateTime(2025, 4, 30),
        beginningBalance: 0,
        csv: 'Date,Reference,Description,Amount\n2025-04-02,,Line,500\n',
      );
      final line = (await repository.getTransactionsForAccount(account.id)).single;

      await expectLater(
        service.matchTransaction(line.id, 'no-such-entry'),
        throwsA(isA<BankReconciliationException>()),
      );
    });

    test('rejects a bank transaction that does not exist', () async {
      final entry = await postBankEntry(date: DateTime(2025, 4, 2), amount: 500, isDebit: true);

      await expectLater(
        service.matchTransaction('no-such-line', entry.id),
        throwsA(isA<BankStatementNotFound>()),
      );
    });
  });

  group('reconcile', () {
    test('reports no variance when the ledger and the statement agree', () async {
      final account = await makeAccount(openingBalance: 1000);
      await service.importStatement(
        bankAccountId: account.id,
        statementDate: DateTime(2025, 4, 30),
        beginningBalance: 1000,
        csv: 'Date,Reference,Description,Amount\n'
            '2025-04-02,,Card settlement,1500\n'
            '2025-04-03,,Supplier payment,-500\n',
      );
      await postBankEntry(date: DateTime(2025, 4, 2), amount: 1500, isDebit: true);
      await postBankEntry(date: DateTime(2025, 4, 3), amount: 500, isDebit: false);
      await service.autoMatch(account.id);

      final summary = await service.reconcile(account.id);

      expect(summary.glBalance, 2000);
      expect(summary.statementBalance, 2000);
      expect(summary.variance, 0);
      expect(summary.matchedCount, 2);
      expect(summary.unmatchedCount, 0);
      expect(summary.isReconciled, isTrue);
    });

    test('reports the variance and outstanding total when they disagree', () async {
      final account = await makeAccount(openingBalance: 1000);
      await service.importStatement(
        bankAccountId: account.id,
        statementDate: DateTime(2025, 4, 30),
        beginningBalance: 1000,
        csv: 'Date,Reference,Description,Amount\n'
            '2025-04-02,,Card settlement,1500\n'
            '2025-04-04,,Bank charge,-200\n',
      );
      // Only the settlement was ever booked; the bank charge never reached the
      // ledger, which is exactly the kind of thing this module exists to find.
      await postBankEntry(date: DateTime(2025, 4, 2), amount: 1500, isDebit: true);
      await service.autoMatch(account.id);

      final summary = await service.reconcile(account.id);

      expect(summary.glBalance, 2500);
      expect(summary.statementBalance, 2300);
      expect(summary.variance, -200);
      expect(summary.unmatchedCount, 1);
      expect(summary.unmatchedTotal, -200);
      expect(summary.isReconciled, isFalse);
    });

    test('a zero variance with lines still open is not reconciled', () async {
      final account = await makeAccount();
      await service.importStatement(
        bankAccountId: account.id,
        statementDate: DateTime(2025, 4, 30),
        beginningBalance: 0,
        csv: 'Date,Reference,Description,Amount\n2025-04-02,,Card settlement,1500\n',
      );
      await postBankEntry(date: DateTime(2025, 4, 2), amount: 1500, isDebit: true);

      final summary = await service.reconcile(account.id);

      expect(summary.variance, 0);
      expect(summary.unmatchedCount, 1);
      expect(summary.isReconciled, isFalse);
    });

    test('ignored lines stop counting as outstanding but still move the balance', () async {
      final account = await makeAccount();
      await service.importStatement(
        bankAccountId: account.id,
        statementDate: DateTime(2025, 4, 30),
        beginningBalance: 0,
        csv: 'Date,Reference,Description,Amount\n2025-04-04,,Bank charge,-200\n',
      );
      final line = (await repository.getTransactionsForAccount(account.id)).single;

      await service.ignoreTransaction(line.id);
      final summary = await service.reconcile(account.id);

      expect(summary.ignoredCount, 1);
      expect(summary.unmatchedCount, 0);
      expect(summary.statementBalance, -200);
      expect(summary.variance, -200);
    });

    test('honours the date window on both the ledger and the statement side', () async {
      final account = await makeAccount();
      await service.importStatement(
        bankAccountId: account.id,
        statementDate: DateTime(2025, 5, 31),
        beginningBalance: 0,
        csv: 'Date,Reference,Description,Amount\n'
            '2025-04-02,,April,100\n'
            '2025-05-02,,May,200\n',
      );
      await postBankEntry(date: DateTime(2025, 4, 2), amount: 100, isDebit: true);
      await postBankEntry(date: DateTime(2025, 5, 2), amount: 200, isDebit: true);

      final april = await service.reconcile(
        account.id,
        from: DateTime(2025, 4, 1),
        to: DateTime(2025, 4, 30),
      );

      expect(april.statementBalance, 100);
      expect(april.glBalance, 100);
      expect(april.unmatchedCount, 1);
    });

    test('refuses an unlinked account rather than reporting a false zero variance', () async {
      final account = await makeAccount(linked: false);

      await expectLater(service.reconcile(account.id), throwsA(isA<BankAccountNotLinked>()));
    });
  });

  group('markReconciled', () {
    test('moves the watermark once the period balances', () async {
      final account = await makeAccount();
      await service.importStatement(
        bankAccountId: account.id,
        statementDate: DateTime(2025, 4, 30),
        beginningBalance: 0,
        csv: 'Date,Reference,Description,Amount\n2025-04-02,,Card settlement,1500\n',
      );
      await postBankEntry(date: DateTime(2025, 4, 2), amount: 1500, isDebit: true);
      await service.autoMatch(account.id);

      await service.markReconciled(account.id, through: DateTime(2025, 4, 30));

      final loaded = await repository.getAccount(account.id);
      expect(loaded!.reconciledUpToDate, DateTime(2025, 4, 30));
    });

    test('refuses an unbalanced period, and leaves the watermark alone', () async {
      final account = await makeAccount();
      await service.importStatement(
        bankAccountId: account.id,
        statementDate: DateTime(2025, 4, 30),
        beginningBalance: 0,
        csv: 'Date,Reference,Description,Amount\n2025-04-04,,Bank charge,-200\n',
      );

      await expectLater(
        service.markReconciled(account.id, through: DateTime(2025, 4, 30)),
        throwsA(isA<BankReconciliationException>()),
      );
      final loaded = await repository.getAccount(account.id);
      expect(loaded!.reconciledUpTo, isNull);
    });

    test('force lets a manager accept a known variance explicitly', () async {
      final account = await makeAccount();
      await service.importStatement(
        bankAccountId: account.id,
        statementDate: DateTime(2025, 4, 30),
        beginningBalance: 0,
        csv: 'Date,Reference,Description,Amount\n2025-04-04,,Bank charge,-200\n',
      );

      final summary = await service.markReconciled(
        account.id,
        through: DateTime(2025, 4, 30),
        force: true,
      );

      expect(summary.isReconciled, isFalse);
      final loaded = await repository.getAccount(account.id);
      expect(loaded!.reconciledUpToDate, DateTime(2025, 4, 30));
    });
  });
}
