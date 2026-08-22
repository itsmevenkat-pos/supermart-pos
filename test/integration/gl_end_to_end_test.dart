import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite/sqflite.dart';

import 'package:supermart_pos/core/database/database_helper.dart';
import 'package:supermart_pos/core/database/migrations/migration_v28.dart';
import 'package:supermart_pos/core/utils/financial_year.dart';
import 'package:supermart_pos/models/product_model.dart';
import 'package:supermart_pos/models/purchase_item_model.dart';
import 'package:supermart_pos/models/purchase_model.dart';
import 'package:supermart_pos/models/sales_return_model.dart';
import 'package:supermart_pos/repositories/gl_repository.dart';
import 'package:supermart_pos/repositories/product_repository.dart';
import 'package:supermart_pos/repositories/purchase_repository.dart';
import 'package:supermart_pos/repositories/sales_return_repository.dart';
import 'package:supermart_pos/services/billing_service.dart';
import 'package:supermart_pos/services/financial_statement_service.dart';
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

/// One full trip through the General Ledger, against a real database built by
/// the real migration path — no hand-inserted `gl_entries` rows anywhere in
/// the main scenario. Every ledger entry below is a side effect of an actual
/// sale, purchase or return going through the app's own repositories, which
/// is the only way to prove the integration fires at all.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Database db;
  late GLRepository glRepo;
  late GLService gl;
  late FinancialStatementService statements;

  /// The scenario runs "today" because BillingService stamps sales with
  /// DateTime.now() — so the year under test is whichever one today is in.
  final today = DateTime.now();
  late final String fy = financialYearLabel(today);

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('gl_e2e_test');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
    db = await DatabaseHelper.instance.database;
  });

  tearDownAll(() async {
    await DatabaseHelper.instance.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  setUp(() {
    glRepo = GLRepository();
    gl = GLService();
    statements = FinancialStatementService();
  });

  test('a full sale / purchase / return / close cycle keeps the books balanced', () async {
    // ---------------------------------------------------------------- step 1
    // A freshly migrated database already has its chart of accounts.
    final accounts = await glRepo.getAllAccounts();
    expect(accounts, hasLength(MigrationV28.defaultAccounts.length));
    expect(accounts.every((a) => a.isSystem), isTrue);
    for (final code in ['1000', '1100', '1200', '2000', '4000', '5000']) {
      expect(await glRepo.getAccountByCode(code), isNotNull, reason: 'account $code must be seeded');
    }
    expect(await glRepo.getEntriesByFinancialYear(fy), isEmpty, reason: 'a fresh ledger has no entries');

    // ---------------------------------------------------------------- step 2
    // A sale through BillingService — nothing here touches GLService.
    final product = Product.create(
      storeId: 'store_default',
      barcode: 'E2E-0001',
      name: 'E2E Test Item',
      retailPrice: 250,
      costPrice: 150,
      taxRate: 0,
      stockQuantity: 100,
    );
    await ProductRepository().insert(product);

    final sale = await BillingService().processSale(
      storeId: 'store_default',
      sessionId: null,
      userId: 'user_admin',
      cartItems: [CartItem(productId: product.id, quantity: 4, product: product)],
      payments: {'cash': 1000},
      discountTotal: 0,
    );
    expect(sale.netAmount, 1000);

    final saleLines = await glRepo.getEntriesByReference('Sale', sale.id);
    expect(saleLines, hasLength(2), reason: 'the sale posted its own ledger entries');
    expect(await gl.getRunningBalance('coa_1000', financialYear: fy), 1000, reason: 'Cash');
    expect(await gl.getRunningBalance('coa_4000', financialYear: fy), 1000, reason: 'Sales Revenue');

    // ---------------------------------------------------------------- step 3
    // A purchase through PurchaseRepository — again, no direct GL call.
    await db.insert('suppliers', {
      'id': 'sup-e2e-1',
      'store_id': 'store_default',
      'name': 'E2E Supplier',
      'created_at': today.millisecondsSinceEpoch ~/ 1000,
    });
    final purchase = Purchase.create(
      storeId: 'store_default',
      supplierId: 'sup-e2e-1',
      grnNo: 'GRN-E2E-1',
      purchaseDate: today.millisecondsSinceEpoch ~/ 1000,
      netAmount: 600,
      total: 600,
      totalQty: 4,
    );
    await PurchaseRepository().insertWithItems(purchase, [
      PurchaseItem.create(
        productId: product.id,
        quantity: 4,
        purchasePrice: 150,
        costPrice: 150,
        total: 600,
        // Receiving stock rewrites the product's selling price from the
        // line's salesPrice, and matches the line to an existing product by
        // mrp — so both are set to keep this receiving the *same* product at
        // its existing 250 price rather than spawning a 0-priced variant.
        salesPrice: 250,
        mrp: 0,
      ),
    ]);

    final purchaseLines = await glRepo.getEntriesByReference('Purchase', purchase.id);
    expect(purchaseLines, hasLength(2), reason: 'the purchase posted its own ledger entries');
    expect(await gl.getRunningBalance('coa_1200', financialYear: fy), 600, reason: 'Inventory');
    expect(await gl.getRunningBalance('coa_2000', financialYear: fy), 600, reason: 'Accounts Payable');

    // ---------------------------------------------------------------- step 4
    final tb = await statements.generateTrialBalance(fy);
    // Debits: Cash 1000 + Inventory 600. Credits: Revenue 1000 + Payables 600.
    expect(tb.totalDebits, 1600);
    expect(tb.totalCredits, 1600);
    expect(tb.isBalanced, isTrue);

    // ---------------------------------------------------------------- step 5
    final bs = await statements.generateBalanceSheet(financialYear: fy);
    expect(bs.totalAssets, 1600, reason: 'cash 1000 + inventory 600');
    expect(bs.totalLiabilities, 600, reason: 'accounts payable');
    expect(bs.netProfit, 1000, reason: 'revenue 1000, no expenses posted yet');
    expect(bs.totalEquity, 1000);
    expect(bs.isBalanced, isTrue, reason: 'assets == liabilities + equity');

    // ---------------------------------------------------------------- step 6
    // A return through SalesReturnRepository: 250 of the 1000 sale comes back.
    final salesReturn = SalesReturn.create(
      storeId: 'store_default',
      userId: 'user_admin',
      approvedByUserId: 'user_admin',
      reason: 'Customer changed their mind',
      refundMethod: 'cash',
      refundAmount: 250,
      isUntied: true,
    );
    await SalesReturnRepository().insertReturn(header: salesReturn, items: const []);

    expect(await gl.getRunningBalance('coa_1000', financialYear: fy), 750, reason: 'cash refunded');
    expect(await gl.getRunningBalance('coa_4000', financialYear: fy), 750, reason: 'revenue reduced');
    expect((await statements.generateTrialBalance(fy)).isBalanced, isTrue);

    // A correction on top of that: reverse the whole return, and both
    // accounts must land back exactly where they were before it.
    await gl.reverseByReference('Return', salesReturn.id, reason: 'Return entered twice');

    expect(await gl.getRunningBalance('coa_1000', financialYear: fy), 1000);
    expect(await gl.getRunningBalance('coa_4000', financialYear: fy), 1000);

    final afterReversal = await statements.generateTrialBalance(fy);
    expect(afterReversal.isBalanced, isTrue);
    // The Trial Balance shows each account's *net* balance, so the return and
    // its reversal cancel out here and the columns land back exactly where
    // they were before the return — while all four lines stay in the journal
    // (asserted just below). That is the whole point of correcting by
    // reversal rather than by deletion.
    expect(afterReversal.totalDebits, tb.totalDebits);
    expect(afterReversal.totalCredits, tb.totalCredits);
    expect((await statements.generateBalanceSheet(financialYear: fy)).isBalanced, isTrue);

    // Nothing was deleted along the way — the ledger is append-only.
    final allEntries = await glRepo.getEntriesByFinancialYear(fy);
    expect(allEntries, hasLength(8), reason: '2 sale + 2 purchase + 2 return + 2 reversal lines');
    expect(allEntries.where((e) => e.reversalOfEntryId != null), hasLength(2));

    // ---------------------------------------------------------------- step 7
    // Close the year, and the books stop moving.
    await FinancialYearCloseService().closeFinancialYear(financialYear: fy, userId: 'user_admin');

    await expectLater(
      gl.postEntry(
        entryDate: today,
        accountId: 'coa_1000',
        amount: 100,
        isDebit: true,
        description: 'after the year was closed',
        referenceType: 'Manual',
      ),
      throwsA(isA<ClosedPeriod>()),
    );

    // And a real sale is refused outright rather than committing without
    // its ledger entries.
    await expectLater(
      BillingService().processSale(
        storeId: 'store_default',
        sessionId: null,
        userId: 'user_admin',
        cartItems: [CartItem(productId: product.id, quantity: 1, product: product)],
        payments: {'cash': 250},
        discountTotal: 0,
      ),
      throwsA(isA<ClosedPeriod>()),
    );

    // The refused sale left nothing at all behind: no sale row, no ledger
    // line, and the stock it would have deducted is untouched.
    expect(await db.query('sales'), hasLength(1), reason: 'only the original sale');
    expect(await glRepo.getEntriesByFinancialYear(fy), hasLength(8));
    expect((await ProductRepository().getById(product.id))!.stockQuantity, 100,
        reason: '100 opening − 4 sold + 4 purchased');

    // The statements still balance on a closed year.
    expect((await statements.generateTrialBalance(fy)).isBalanced, isTrue);
    expect((await statements.generateBalanceSheet(financialYear: fy)).isBalanced, isTrue);
  });
}
