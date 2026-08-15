import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:supermart_pos/core/database/database_helper.dart';
import 'package:supermart_pos/models/bank_account_model.dart';
import 'package:supermart_pos/models/bank_statement_model.dart';
import 'package:supermart_pos/models/bank_transaction_model.dart';
import 'package:supermart_pos/models/gl_entry_model.dart';
import 'package:supermart_pos/repositories/bank_reconciliation_repository.dart';
import 'package:supermart_pos/repositories/gl_repository.dart';

/// Same temp-directory path_provider shim the other DB-backed service tests
/// use, so `DatabaseHelper.instance.database` can open a real sqflite database
/// under `flutter_test`.
class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this._path);
  final String _path;

  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late BankReconciliationRepository repository;
  late GLRepository glRepository;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('bank_recon_repo_test');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
    await DatabaseHelper.instance.database;
  });

  tearDownAll(() async {
    await DatabaseHelper.instance.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  setUp(() async {
    repository = BankReconciliationRepository();
    glRepository = GLRepository();
    // Each test starts from an empty set of bank rows; the seeded chart of
    // accounts stays, since that is what a real database looks like.
    final db = await DatabaseHelper.instance.database;
    await db.delete('bank_transactions');
    await db.delete('bank_statements');
    await db.delete('bank_accounts');
  });

  Future<BankAccount> makeAccount({String? glAccountId}) async {
    final bank = await glRepository.getAccountByCode('1010');
    return repository.createAccount(BankAccount.create(
      accountNumber: '00112233445566',
      accountHolder: 'SuperMart Retail',
      bankName: 'State Bank',
      openingBalance: 1000,
      glAccountId: glAccountId ?? bank!.id,
    ));
  }

  Future<BankStatement> makeStatement(String accountId, {DateTime? date}) {
    return repository.createStatement(BankStatement.create(
      bankAccountId: accountId,
      statementDate: date ?? DateTime(2025, 4, 30),
      beginningBalance: 1000,
      endingBalance: 1500,
    ));
  }

  group('bank accounts', () {
    test('round-trips an account through insert and read', () async {
      final created = await makeAccount();

      final loaded = await repository.getAccount(created.id);

      expect(loaded, isNotNull);
      expect(loaded!.accountNumber, '00112233445566');
      expect(loaded.bankName, 'State Bank');
      expect(loaded.openingBalance, 1000);
      expect(loaded.glAccountId, isNotNull);
      expect(loaded.isActive, isTrue);
      expect(loaded.reconciledUpTo, isNull);
    });

    test('getAllAccounts filters on is_active', () async {
      final active = await makeAccount();
      final other = await repository.createAccount(BankAccount.create(
        accountNumber: '99887766',
        accountHolder: 'SuperMart Retail',
        bankName: 'Axis',
      ));
      await repository.deactivateAccount(other.id);

      final activeOnly = await repository.getAllAccounts(isActive: true);
      final all = await repository.getAllAccounts();

      expect(activeOnly.map((a) => a.id), [active.id]);
      expect(all, hasLength(2));
    });

    test('deactivateAccount keeps the row so its statements stay resolvable', () async {
      final account = await makeAccount();
      await makeStatement(account.id);

      await repository.deactivateAccount(account.id);

      final loaded = await repository.getAccount(account.id);
      expect(loaded, isNotNull);
      expect(loaded!.isActive, isFalse);
      expect(await repository.getStatementsForAccount(account.id), hasLength(1));
    });

    test('setReconciledUpTo stores and clears the watermark', () async {
      final account = await makeAccount();

      await repository.setReconciledUpTo(account.id, DateTime(2025, 4, 30));
      final marked = await repository.getAccount(account.id);
      expect(marked!.reconciledUpToDate, DateTime(2025, 4, 30));

      await repository.setReconciledUpTo(account.id, null);
      final cleared = await repository.getAccount(account.id);
      expect(cleared!.reconciledUpTo, isNull);
    });

    test('updateAccount persists an edited field without changing the id', () async {
      final account = await makeAccount();

      await repository.updateAccount(account.copyWith(bankName: 'HDFC'));

      final loaded = await repository.getAccount(account.id);
      expect(loaded!.bankName, 'HDFC');
      expect(loaded.id, account.id);
    });
  });

  group('statements and transactions', () {
    test('insertTransactions writes a whole batch', () async {
      final account = await makeAccount();
      final statement = await makeStatement(account.id);

      await repository.insertTransactions([
        BankTransaction.create(
          bankStatementId: statement.id,
          transactionDate: DateTime(2025, 4, 2),
          amount: 500,
          reference: 'UTR001',
        ),
        BankTransaction.create(
          bankStatementId: statement.id,
          transactionDate: DateTime(2025, 4, 3),
          amount: -250,
          description: 'Supplier payment',
        ),
      ]);

      final rows = await repository.getTransactionsForStatement(statement.id);
      expect(rows, hasLength(2));
      expect(rows.first.amount, 500);
      expect(rows.first.isCredit, isTrue);
      expect(rows.last.amount, -250);
      expect(rows.last.isCredit, isFalse);
      expect(rows.every((r) => r.matchStatus == BankMatchStatus.unmatched), isTrue);
    });

    test('deleteStatement removes the statement and its lines together', () async {
      final account = await makeAccount();
      final statement = await makeStatement(account.id);
      await repository.insertTransactions([
        BankTransaction.create(
          bankStatementId: statement.id,
          transactionDate: DateTime(2025, 4, 2),
          amount: 500,
        ),
      ]);

      await repository.deleteStatement(statement.id);

      expect(await repository.getStatement(statement.id), isNull);
      expect(await repository.getTransactionsForStatement(statement.id), isEmpty);
    });

    test('getTransactionsForAccount spans statements and honours the date window', () async {
      final account = await makeAccount();
      final april = await makeStatement(account.id, date: DateTime(2025, 4, 30));
      final may = await makeStatement(account.id, date: DateTime(2025, 5, 31));
      await repository.insertTransactions([
        BankTransaction.create(bankStatementId: april.id, transactionDate: DateTime(2025, 4, 10), amount: 100),
        BankTransaction.create(bankStatementId: may.id, transactionDate: DateTime(2025, 5, 10), amount: 200),
      ]);

      final all = await repository.getTransactionsForAccount(account.id);
      final aprilOnly = await repository.getTransactionsForAccount(
        account.id,
        from: DateTime(2025, 4, 1),
        to: DateTime(2025, 4, 30),
      );

      expect(all, hasLength(2));
      expect(aprilOnly, hasLength(1));
      expect(aprilOnly.single.amount, 100);
    });

    test('match status transitions move the GL link with them', () async {
      final account = await makeAccount();
      final statement = await makeStatement(account.id);
      final transaction = BankTransaction.create(
        bankStatementId: statement.id,
        transactionDate: DateTime(2025, 4, 2),
        amount: 500,
      );
      await repository.insertTransactions([transaction]);

      final bank = await glRepository.getAccountByCode('1010');
      final entry = await glRepository.postEntry(GLEntry.post(
        entryDate: DateTime(2025, 4, 2),
        accountId: bank!.id,
        amount: 500,
        isDebit: true,
        description: 'Card settlement',
        referenceType: 'Manual',
      ));

      await repository.markMatched(transaction.id, entry.id);
      var loaded = await repository.getTransaction(transaction.id);
      expect(loaded!.matchStatus, BankMatchStatus.matched);
      expect(loaded.matchedGlEntryId, entry.id);
      expect(loaded.isOutstanding, isFalse);

      await repository.markUnmatched(transaction.id);
      loaded = await repository.getTransaction(transaction.id);
      expect(loaded!.matchStatus, BankMatchStatus.unmatched);
      expect(loaded.matchedGlEntryId, isNull);

      await repository.markIgnored(transaction.id);
      loaded = await repository.getTransaction(transaction.id);
      expect(loaded!.matchStatus, BankMatchStatus.ignored);
      expect(loaded.matchedGlEntryId, isNull);
      expect(loaded.isOutstanding, isFalse);
    });

    test('getMatchedGlEntryIds reports only entries claimed on this account', () async {
      final account = await makeAccount();
      final statement = await makeStatement(account.id);
      final claimedTx = BankTransaction.create(
        bankStatementId: statement.id,
        transactionDate: DateTime(2025, 4, 2),
        amount: 500,
      );
      final freeTx = BankTransaction.create(
        bankStatementId: statement.id,
        transactionDate: DateTime(2025, 4, 3),
        amount: 700,
      );
      await repository.insertTransactions([claimedTx, freeTx]);

      final bank = await glRepository.getAccountByCode('1010');
      final entry = await glRepository.postEntry(GLEntry.post(
        entryDate: DateTime(2025, 4, 2),
        accountId: bank!.id,
        amount: 500,
        isDebit: true,
        description: 'Card settlement',
        referenceType: 'Manual',
      ));
      await repository.markMatched(claimedTx.id, entry.id);

      expect(await repository.getMatchedGlEntryIds(account.id), {entry.id});
    });

    test('getTransactionsForStatement can filter by status', () async {
      final account = await makeAccount();
      final statement = await makeStatement(account.id);
      final a = BankTransaction.create(
        bankStatementId: statement.id,
        transactionDate: DateTime(2025, 4, 2),
        amount: 500,
      );
      final b = BankTransaction.create(
        bankStatementId: statement.id,
        transactionDate: DateTime(2025, 4, 3),
        amount: 700,
      );
      await repository.insertTransactions([a, b]);
      await repository.markIgnored(b.id);

      final unmatched = await repository.getTransactionsForStatement(
        statement.id,
        status: BankMatchStatus.unmatched,
      );
      expect(unmatched.map((t) => t.id), [a.id]);
    });
  });
}
