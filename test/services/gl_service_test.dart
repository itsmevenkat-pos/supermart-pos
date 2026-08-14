import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite/sqflite.dart';

import 'package:supermart_pos/core/database/database_helper.dart';
import 'package:supermart_pos/core/utils/financial_year.dart';
import 'package:supermart_pos/models/chart_of_account_model.dart';
import 'package:supermart_pos/models/gl_entry_model.dart';
import 'package:supermart_pos/models/product_model.dart';
import 'package:supermart_pos/models/sales_return_model.dart';
import 'package:supermart_pos/repositories/gl_repository.dart';
import 'package:supermart_pos/repositories/product_repository.dart';
import 'package:supermart_pos/repositories/sales_return_repository.dart';
import 'package:supermart_pos/services/billing_service.dart';
import 'package:supermart_pos/services/financial_year_close_service.dart';
import 'package:supermart_pos/services/gl_exceptions.dart';
import 'package:supermart_pos/services/gl_service.dart';

/// See the note on the same class in
/// `test/services/financial_year_close_service_test.dart`.
class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this._path);
  final String _path;

  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Database db;
  late GLService service;
  late GLRepository repo;

  const fy = '25-26';

  /// A date inside financial year 25-26 (1 Apr 2025 – 31 Mar 2026).
  final inFy = DateTime(2025, 6, 15);

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('gl_service_test');
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
    service = GLService();
    repo = GLRepository();
    await db.delete('gl_entries');
    await db.delete('gl_balances');
    await db.delete('financial_year_closures');
    await db.update('chart_of_accounts', {'is_active': 1});
  });

  group('postEntry', () {
    test('creates a correctly-signed debit and refreshes the cached balance', () async {
      final entry = await service.postEntry(
        entryDate: inFy,
        accountId: 'coa_1000',
        amount: 500,
        isDebit: true,
        description: 'Opening float',
        referenceType: 'Manual',
        createdBy: 'user_admin',
      );

      expect(entry.debit, 500);
      expect(entry.credit, 0);
      expect(entry.financialYear, fy);
      expect(entry.createdBy, 'user_admin');
      // The balance cache was written as part of the post, not left stale.
      expect((await repo.getAccountBalance('coa_1000', fy))!.balance, 500);
    });

    test('creates a correctly-signed credit', () async {
      final entry = await service.postEntry(
        entryDate: inFy,
        accountId: 'coa_4000',
        amount: 500,
        isDebit: false,
        description: 'Revenue',
        referenceType: 'Manual',
      );

      expect(entry.debit, 0);
      expect(entry.credit, 500);
      // Revenue is credit-nature, so a credit is a positive balance.
      expect(await service.getRunningBalance('coa_4000', financialYear: fy), 500);
    });

    test('rejects a zero or negative amount without writing anything', () async {
      for (final amount in [0.0, -10.0]) {
        expect(
          () => service.postEntry(
            entryDate: inFy,
            accountId: 'coa_1000',
            amount: amount,
            isDebit: true,
            description: 'bad amount',
            referenceType: 'Manual',
          ),
          throwsA(isA<ArgumentError>()),
        );
      }
      expect(await repo.getEntriesByAccount('coa_1000'), isEmpty);
    });

    test('rejects an unknown account with AccountNotFound', () async {
      await expectLater(
        service.postEntry(
          entryDate: inFy,
          accountId: 'coa_nope',
          amount: 10,
          isDebit: true,
          description: 'ghost account',
          referenceType: 'Manual',
        ),
        throwsA(isA<AccountNotFound>()),
      );
    });

    test('rejects a deactivated account', () async {
      await repo.deactivateAccount('coa_5200');

      await expectLater(
        service.postEntry(
          entryDate: inFy,
          accountId: 'coa_5200',
          amount: 10,
          isDebit: true,
          description: 'rent on a closed account',
          referenceType: 'Manual',
        ),
        throwsA(isA<AccountNotFound>()),
      );
    });
  });

  group('postCompoundEntry', () {
    test('a balanced entry posts every line', () async {
      final lines = await service.postCompoundEntry(
        entryDate: inFy,
        description: 'Cash sale',
        referenceType: 'Sale',
        referenceId: 'sale-1',
        accounts: {
          'coa_1000': 1180, // debit cash
          'coa_4000': -1180, // credit revenue
        },
      );

      expect(lines, hasLength(2));
      expect(lines.firstWhere((l) => l.accountId == 'coa_1000').debit, 1180);
      expect(lines.firstWhere((l) => l.accountId == 'coa_4000').credit, 1180);
      expect(await service.getRunningBalance('coa_1000', financialYear: fy), 1180);
      expect(await service.getRunningBalance('coa_4000', financialYear: fy), 1180);
    });

    test('a three-line split entry posts and balances', () async {
      // Half paid in cash, half on credit.
      await service.postCompoundEntry(
        entryDate: inFy,
        description: 'Part-credit sale',
        referenceType: 'Sale',
        referenceId: 'sale-2',
        accounts: {
          'coa_1000': 400,
          'coa_1100': 600,
          'coa_4000': -1000,
        },
      );

      expect(await service.getRunningBalance('coa_1000', financialYear: fy), 400);
      expect(await service.getRunningBalance('coa_1100', financialYear: fy), 600);
      expect(await service.getRunningBalance('coa_4000', financialYear: fy), 1000);
    });

    test('an unbalanced entry throws UnbalancedEntry and writes nothing', () async {
      await expectLater(
        service.postCompoundEntry(
          entryDate: inFy,
          description: 'Broken sale',
          referenceType: 'Sale',
          referenceId: 'sale-broken',
          accounts: {
            'coa_1000': 1000,
            'coa_4000': -900, // 100 short
          },
        ),
        throwsA(isA<UnbalancedEntry>()),
      );

      // Verified through the repository, not through the thrown object: the
      // journal must be untouched, not merely reported as untouched.
      expect(await repo.getEntriesByReference('Sale', 'sale-broken'), isEmpty);
      expect(await repo.getEntriesByAccount('coa_1000'), isEmpty);
      expect(await repo.getEntriesByAccount('coa_4000'), isEmpty);
      expect(await repo.getAccountBalance('coa_1000', fy), isNull);
    });

    test('a sub-paisa difference is tolerated as rounding', () async {
      final lines = await service.postCompoundEntry(
        entryDate: inFy,
        description: 'Rounding',
        referenceType: 'Manual',
        accounts: {
          'coa_1000': 100.005,
          'coa_4000': -100.0,
        },
      );

      expect(lines, hasLength(2));
    });

    test('a difference above the tolerance is rejected', () async {
      await expectLater(
        service.postCompoundEntry(
          entryDate: inFy,
          description: 'Not rounding',
          referenceType: 'Manual',
          accounts: {'coa_1000': 100.02, 'coa_4000': -100.0},
        ),
        throwsA(isA<UnbalancedEntry>()),
      );
    });

    test('zero-amount lines are skipped, not rejected', () async {
      // A fully-cash sale passes a zero receivable line; that must not fail.
      final lines = await service.postCompoundEntry(
        entryDate: inFy,
        description: 'Fully cash sale',
        referenceType: 'Sale',
        referenceId: 'sale-3',
        accounts: {
          'coa_1000': 500,
          'coa_1100': 0,
          'coa_4000': -500,
        },
      );

      expect(lines, hasLength(2));
      expect(lines.any((l) => l.accountId == 'coa_1100'), isFalse);
    });

    test('an entry naming an unknown account writes none of its lines', () async {
      await expectLater(
        service.postCompoundEntry(
          entryDate: inFy,
          description: 'Ghost account',
          referenceType: 'Manual',
          referenceId: 'ghost',
          accounts: {'coa_1000': 100, 'coa_nope': -100},
        ),
        throwsA(isA<AccountNotFound>()),
      );

      // The valid line must not have landed on its own.
      expect(await repo.getEntriesByAccount('coa_1000'), isEmpty);
    });

    test('several lines may hit the same account within one document', () async {
      // Two revenue lines against one cash line — allowed by design.
      await service.postCompoundEntry(
        entryDate: inFy,
        description: 'Split revenue sale',
        referenceType: 'Sale',
        referenceId: 'sale-split',
        accounts: {'coa_1000': 300, 'coa_4000': -200, 'coa_4100': -100},
      );

      expect(await repo.getEntriesByReference('Sale', 'sale-split'), hasLength(3));
      expect(await service.getRunningBalance('coa_4000', financialYear: fy), 200);
      expect(await service.getRunningBalance('coa_4100', financialYear: fy), 100);
    });
  });

  group('getRunningBalance', () {
    test('matches a hand-computed balance after a sequence of postings', () async {
      // Cash: +1000, +250, -400, -50  ->  800
      for (final (amount, isDebit) in [(1000.0, true), (250.0, true), (400.0, false), (50.0, false)]) {
        await service.postEntry(
          entryDate: inFy,
          accountId: 'coa_1000',
          amount: amount,
          isDebit: isDebit,
          description: 'movement',
          referenceType: 'Manual',
        );
      }

      expect(await service.getRunningBalance('coa_1000', financialYear: fy), 800);
    });

    test('returns a credit-nature account in its own direction', () async {
      // Accounts Payable: owe 5000, pay back 2000  ->  3000 still owed.
      await service.postEntry(
        entryDate: inFy,
        accountId: 'coa_2000',
        amount: 5000,
        isDebit: false,
        description: 'Purchase on account',
        referenceType: 'Manual',
      );
      await service.postEntry(
        entryDate: inFy,
        accountId: 'coa_2000',
        amount: 2000,
        isDebit: true,
        description: 'Paid supplier',
        referenceType: 'Manual',
      );

      expect(await service.getRunningBalance('coa_2000', financialYear: fy), 3000);
    });

    test('rebuilds a cache that was deleted behind its back', () async {
      await service.postEntry(
        entryDate: inFy,
        accountId: 'coa_1000',
        amount: 750,
        isDebit: true,
        description: 'movement',
        referenceType: 'Manual',
      );
      await db.delete('gl_balances');

      expect(await service.getRunningBalance('coa_1000', financialYear: fy), 750);
    });

    test('recomputes when the cache is stale relative to the journal', () async {
      await service.postEntry(
        entryDate: inFy,
        accountId: 'coa_1000',
        amount: 100,
        isDebit: true,
        description: 'first',
        referenceType: 'Manual',
      );
      expect(await service.getRunningBalance('coa_1000', financialYear: fy), 100);

      // A second line written straight through the repository, so nothing
      // refreshes the cache — exactly the situation the staleness check
      // exists for. Backdating last_updated makes the new entry unambiguously
      // newer than the cache even within the same one-second timestamp.
      await repo.postEntry(GLEntry.post(
        entryDate: inFy,
        accountId: 'coa_1000',
        amount: 250,
        isDebit: true,
        description: 'written behind the cache’s back',
        referenceType: 'Manual',
      ));
      await db.update('gl_balances', {'last_updated': 0});

      expect(await service.getRunningBalance('coa_1000', financialYear: fy), 350);
    });

    test('defaults to the current financial year when none is given', () async {
      final today = DateTime.now();
      await service.postEntry(
        entryDate: today,
        accountId: 'coa_1000',
        amount: 42,
        isDebit: true,
        description: 'today',
        referenceType: 'Manual',
      );

      expect(await service.getRunningBalance('coa_1000'), 42);
    });

    test('separates one financial year from the next', () async {
      await service.postEntry(
        entryDate: DateTime(2025, 6, 1),
        accountId: 'coa_1000',
        amount: 100,
        isDebit: true,
        description: '25-26',
        referenceType: 'Manual',
      );
      await service.postEntry(
        entryDate: DateTime(2026, 6, 1),
        accountId: 'coa_1000',
        amount: 900,
        isDebit: true,
        description: '26-27',
        referenceType: 'Manual',
      );

      expect(await service.getRunningBalance('coa_1000', financialYear: '25-26'), 100);
      expect(await service.getRunningBalance('coa_1000', financialYear: '26-27'), 900);
    });

    test('throws AccountNotFound for an unknown account', () async {
      await expectLater(
        service.getRunningBalance('coa_nope', financialYear: fy),
        throwsA(isA<AccountNotFound>()),
      );
    });
  });

  group('reverseEntry', () {
    test('posts the exact opposite side and nets the balance back to zero', () async {
      final original = await service.postEntry(
        entryDate: inFy,
        accountId: 'coa_1000',
        amount: 640.50,
        isDebit: true,
        description: 'Cash sale',
        referenceType: 'Sale',
        referenceId: 'sale-9',
      );
      expect(await service.getRunningBalance('coa_1000', financialYear: fy), 640.50);

      final reversal = await service.reverseEntry(original.id, reason: 'Cashier error');

      expect(reversal.debit, 0);
      expect(reversal.credit, 640.50);
      expect(reversal.accountId, original.accountId);
      expect(reversal.reversalOfEntryId, original.id);
      expect(reversal.description, startsWith('Reversal: '));
      expect(reversal.description, contains('Cashier error'));
      expect(await service.getRunningBalance('coa_1000', financialYear: fy), 0);
    });

    test('leaves the original entry exactly as it was', () async {
      final original = await service.postEntry(
        entryDate: inFy,
        accountId: 'coa_1000',
        amount: 100,
        isDebit: true,
        description: 'Cash sale',
        referenceType: 'Sale',
        referenceId: 'sale-10',
      );

      await service.reverseEntry(original.id, reason: 'Correction');

      // Append-only: the correction is a second row, the first is untouched.
      expect(await repo.getEntry(original.id), original);
      expect(await repo.getEntriesByAccount('coa_1000'), hasLength(2));
    });

    test('reverses a credit into a debit', () async {
      final original = await service.postEntry(
        entryDate: inFy,
        accountId: 'coa_4000',
        amount: 250,
        isDebit: false,
        description: 'Revenue',
        referenceType: 'Sale',
      );

      final reversal = await service.reverseEntry(original.id, reason: 'Voided');

      expect(reversal.debit, 250);
      expect(reversal.credit, 0);
      expect(await service.getRunningBalance('coa_4000', financialYear: fy), 0);
    });

    test('throws EntryNotFound for an unknown entry id', () async {
      await expectLater(
        service.reverseEntry('no-such-entry', reason: 'nothing to reverse'),
        throwsA(isA<EntryNotFound>()),
      );
    });

    test('still reverses an entry whose account was since deactivated', () async {
      final original = await service.postEntry(
        entryDate: inFy,
        accountId: 'coa_5200',
        amount: 300,
        isDebit: true,
        description: 'Rent',
        referenceType: 'Manual',
      );
      await repo.deactivateAccount('coa_5200');

      // A wrong balance on a deactivated account must still be fixable.
      final reversal = await service.reverseEntry(original.id, reason: 'Wrong account');

      expect(reversal.credit, 300);
      expect(await service.getRunningBalance('coa_5200', financialYear: fy), 0);
    });

    test('reverseByReference mirrors every line of one document', () async {
      await service.postCompoundEntry(
        entryDate: inFy,
        description: 'Cash sale',
        referenceType: 'Sale',
        referenceId: 'sale-returned',
        accounts: {'coa_1000': 1000, 'coa_4000': -1000},
      );

      final reversals = await service.reverseByReference(
        'Sale',
        'sale-returned',
        reason: 'Sales return',
      );

      expect(reversals, hasLength(2));
      expect(await service.getRunningBalance('coa_1000', financialYear: fy), 0);
      expect(await service.getRunningBalance('coa_4000', financialYear: fy), 0);
    });

    test('reverseByReference twice does not double-reverse', () async {
      await service.postCompoundEntry(
        entryDate: inFy,
        description: 'Cash sale',
        referenceType: 'Sale',
        referenceId: 'sale-twice',
        accounts: {'coa_1000': 500, 'coa_4000': -500},
      );

      await service.reverseByReference('Sale', 'sale-twice', reason: 'Return');
      final second = await service.reverseByReference('Sale', 'sale-twice', reason: 'Return again');

      expect(second, isEmpty, reason: 'already-reversed lines are skipped');
      expect(await service.getRunningBalance('coa_1000', financialYear: fy), 0);
    });
  });

  group('closed financial years', () {
    test('posting into a closed year throws ClosedPeriod', () async {
      await FinancialYearCloseService().closeFinancialYear(financialYear: fy, userId: 'user_admin');

      await expectLater(
        service.postEntry(
          entryDate: inFy,
          accountId: 'coa_1000',
          amount: 100,
          isDebit: true,
          description: 'too late',
          referenceType: 'Manual',
        ),
        throwsA(isA<ClosedPeriod>()),
      );
      expect(await repo.getEntriesByAccount('coa_1000'), isEmpty);
    });

    test('a compound post into a closed year writes nothing', () async {
      await FinancialYearCloseService().closeFinancialYear(financialYear: fy, userId: 'user_admin');

      await expectLater(
        service.postCompoundEntry(
          entryDate: inFy,
          description: 'too late',
          referenceType: 'Sale',
          referenceId: 'sale-closed',
          accounts: {'coa_1000': 100, 'coa_4000': -100},
        ),
        throwsA(isA<ClosedPeriod>()),
      );
      expect(await repo.getEntriesByReference('Sale', 'sale-closed'), isEmpty);
    });

    test('closing one year does not block the next', () async {
      await FinancialYearCloseService().closeFinancialYear(financialYear: fy, userId: 'user_admin');

      final entry = await service.postEntry(
        entryDate: DateTime(2026, 6, 1), // FY 26-27
        accountId: 'coa_1000',
        amount: 100,
        isDebit: true,
        description: 'new year, open books',
        referenceType: 'Manual',
      );

      expect(entry.financialYear, '26-27');
    });

    test('a closed year can no longer be corrected by a reversal', () async {
      final original = await service.postEntry(
        entryDate: inFy,
        accountId: 'coa_1000',
        amount: 100,
        isDebit: true,
        description: 'before closing',
        referenceType: 'Manual',
      );
      await FinancialYearCloseService().closeFinancialYear(financialYear: fy, userId: 'user_admin');

      // The correct accounting outcome: a closed year's books do not move.
      await expectLater(
        service.reverseEntry(original.id, reason: 'too late'),
        throwsA(isA<ClosedPeriod>()),
      );
    });
  });

  group('sale integration (through BillingService, not GLService)', () {
    late ProductRepository productRepo;

    setUp(() async {
      productRepo = ProductRepository();
      await db.delete('sale_items');
      await db.delete('sales');
      await db.delete('stock_ledger');
      await db.delete('products');
    });

    Future<Product> makeProduct({double retailPrice = 100, double stock = 50}) async {
      final product = Product.create(
        storeId: 'store_default',
        barcode: 'GL-TEST-${DateTime.now().microsecondsSinceEpoch}',
        name: 'GL Test Item',
        retailPrice: retailPrice,
        costPrice: retailPrice / 2,
        taxRate: 0,
        stockQuantity: stock,
      );
      await productRepo.insert(product);
      return product;
    }

    test('a completed cash sale posts balanced GL entries by itself', () async {
      final product = await makeProduct(retailPrice: 100);

      final sale = await BillingService().processSale(
        storeId: 'store_default',
        sessionId: null,
        userId: 'user_admin',
        cartItems: [CartItem(productId: product.id, quantity: 2, product: product)],
        payments: {'cash': 200},
        discountTotal: 0,
      );

      // The sale itself posted these — nothing in this test called GLService.
      final lines = await repo.getEntriesByReference('Sale', sale.id);
      expect(lines, hasLength(2), reason: 'a cash sale posts a cash debit and a revenue credit');

      final debits = lines.fold<double>(0, (sum, l) => sum + l.debit);
      final credits = lines.fold<double>(0, (sum, l) => sum + l.credit);
      expect(debits, closeTo(credits, 0.001), reason: 'the posted entry must balance');
      expect(debits, closeTo(sale.netAmount, 0.001));

      expect(lines.firstWhere((l) => l.accountId == 'coa_1000').debit, closeTo(200, 0.001));
      expect(lines.firstWhere((l) => l.accountId == 'coa_4000').credit, closeTo(200, 0.001));

      final saleFy = lines.first.financialYear;
      expect(await service.getRunningBalance('coa_1000', financialYear: saleFy), closeTo(200, 0.001));
      expect(await service.getRunningBalance('coa_4000', financialYear: saleFy), closeTo(200, 0.001));
    });

    test('a credit sale debits Accounts Receivable instead of Cash', () async {
      final product = await makeProduct(retailPrice: 500);

      final sale = await BillingService().processSale(
        storeId: 'store_default',
        sessionId: null,
        userId: 'user_admin',
        cartItems: [CartItem(productId: product.id, quantity: 1, product: product)],
        payments: {'credit': 500},
        discountTotal: 0,
        creditUsed: 500,
      );

      final lines = await repo.getEntriesByReference('Sale', sale.id);
      final byAccount = {for (final l in lines) l.accountId: l};

      expect(byAccount['coa_1100']!.debit, closeTo(500, 0.001), reason: 'the whole bill is owed');
      expect(byAccount.containsKey('coa_1000'), isFalse, reason: 'nothing was taken in cash');
      expect(byAccount['coa_4000']!.credit, closeTo(500, 0.001));
    });

    test('a part-cash part-credit sale splits the debit across both accounts', () async {
      final product = await makeProduct(retailPrice: 1000);

      final sale = await BillingService().processSale(
        storeId: 'store_default',
        sessionId: null,
        userId: 'user_admin',
        cartItems: [CartItem(productId: product.id, quantity: 1, product: product)],
        payments: {'cash': 600},
        discountTotal: 0,
        creditUsed: 400,
      );

      final lines = await repo.getEntriesByReference('Sale', sale.id);
      final byAccount = {for (final l in lines) l.accountId: l};

      expect(byAccount['coa_1000']!.debit, closeTo(600, 0.001));
      expect(byAccount['coa_1100']!.debit, closeTo(400, 0.001));
      expect(byAccount['coa_4000']!.credit, closeTo(1000, 0.001));
    });

    test('a sale into a closed financial year is refused outright', () async {
      final product = await makeProduct();
      // BillingService stamps sales with DateTime.now(), so the year to close
      // is whichever one today falls in — asked for, not hardcoded.
      final currentFy = financialYearLabel(DateTime.now());
      await FinancialYearCloseService().closeFinancialYear(financialYear: currentFy, userId: 'user_admin');

      await expectLater(
        BillingService().processSale(
          storeId: 'store_default',
          sessionId: null,
          userId: 'user_admin',
          cartItems: [CartItem(productId: product.id, quantity: 1, product: product)],
          payments: {'cash': 100},
          discountTotal: 0,
        ),
        throwsA(isA<ClosedPeriod>()),
      );

      // All-or-nothing: the refused sale rolled back completely, so neither
      // the sale, its stock deduction, nor any ledger line survived.
      expect(await db.query('sales'), isEmpty);
      expect(await db.query('gl_entries'), isEmpty);
      expect(
        ((await productRepo.getById(product.id))!).stockQuantity,
        50,
        reason: 'stock must not be deducted by a sale that was refused',
      );
    });
  });

  group('sales return integration', () {
    // Returns are recorded untied (no `sales.id` to point at) so these tests
    // stay focused on the ledger rather than on building a whole sale first —
    // `sales_returns.sale_id` carries a real foreign key.
    tearDown(() async {
      await db.delete('sales_returns');
    });

    test('a cash refund debits Sales Revenue and credits Cash', () async {
      final header = SalesReturn.create(
        storeId: 'store_default',
        userId: 'user_admin',
        reason: 'Damaged',
        refundMethod: 'cash',
        refundAmount: 300,
        isUntied: true,
      );

      await SalesReturnRepository().insertReturn(header: header, items: const []);

      final lines = await repo.getEntriesByReference('Return', header.id);
      final byAccount = {for (final l in lines) l.accountId: l};

      expect(lines, hasLength(2));
      expect(byAccount['coa_4000']!.debit, 300, reason: 'revenue is reduced by a return');
      expect(byAccount['coa_1000']!.credit, 300, reason: 'cash went back to the customer');
    });

    test('a credit-adjusted refund credits Accounts Receivable instead of Cash', () async {
      await db.insert('customers', {
        'id': 'cust-gl-1',
        'name': 'Ledger Test Customer',
        'phone': '9000000001', // NOT NULL on this table
        'outstanding_balance': 1000.0,
        'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      });
      final header = SalesReturn.create(
        customerId: 'cust-gl-1',
        storeId: 'store_default',
        userId: 'user_admin',
        reason: 'Wrong item',
        refundMethod: 'credit_adjust',
        refundAmount: 450,
        isUntied: true,
      );

      await SalesReturnRepository().insertReturn(header: header, items: const []);

      final lines = await repo.getEntriesByReference('Return', header.id);
      final byAccount = {for (final l in lines) l.accountId: l};

      expect(byAccount['coa_4000']!.debit, 450);
      expect(byAccount['coa_1100']!.credit, 450);
      expect(byAccount.containsKey('coa_1000'), isFalse, reason: 'no cash left the till');

      await db.delete('customers', where: 'id = ?', whereArgs: ['cust-gl-1']);
    });

    test('a partial return only reverses what was actually refunded', () async {
      // The case a line-by-line reversal of the original sale would get
      // wrong: a 1000-rupee sale with only 200 returned. Both are dated today
      // so they land in the same financial year and can be compared.
      final today = DateTime.now();
      await service.postCompoundEntry(
        entryDate: today,
        description: 'Original sale',
        referenceType: 'Sale',
        referenceId: 'sale-partial',
        accounts: {'coa_1000': 1000, 'coa_4000': -1000},
      );

      final header = SalesReturn.create(
        storeId: 'store_default',
        userId: 'user_admin',
        reason: 'One item back',
        refundMethod: 'cash',
        refundAmount: 200,
        isUntied: true,
      );
      await SalesReturnRepository().insertReturn(header: header, items: const []);

      // 1000 earned less 200 returned — not zero, which is what reversing the
      // whole sale line by line would have produced.
      final year = financialYearLabel(today);
      expect(await service.getRunningBalance('coa_4000', financialYear: year), 800);
      expect(await service.getRunningBalance('coa_1000', financialYear: year), 800);
    });
  });

  group('account lookup', () {
    test('requireAccountByCode resolves a seeded code', () async {
      final cash = await service.requireAccountByCode(GLService.cashAccountCode);

      expect(cash.code, '1000');
      expect(cash.type, AccountType.asset);
    });

    test('requireAccountByCode throws AccountNotFound for an unknown code', () async {
      await expectLater(
        service.requireAccountByCode('9999'),
        throwsA(isA<AccountNotFound>()),
      );
    });
  });

  group('recalculateAllBalances', () {
    test('rebuilds every account balance for a year from the journal alone', () async {
      await service.postCompoundEntry(
        entryDate: inFy,
        description: 'Cash sale',
        referenceType: 'Sale',
        referenceId: 'sale-rebuild',
        accounts: {'coa_1000': 800, 'coa_4000': -800},
      );
      await db.delete('gl_balances');

      await service.recalculateAllBalances(fy);

      expect((await repo.getAccountBalance('coa_1000', fy))!.balance, 800);
      expect((await repo.getAccountBalance('coa_4000', fy))!.balance, 800);
      // Untouched accounts get a zero row rather than being skipped.
      expect((await repo.getAccountBalance('coa_1500', fy))!.balance, 0);
    });
  });
}
