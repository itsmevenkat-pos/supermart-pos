import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:supermart_pos/core/database/database_helper.dart';
import 'package:supermart_pos/models/customer_model.dart';
import 'package:supermart_pos/models/product_model.dart';
import 'package:supermart_pos/models/sale_model.dart';
import 'package:supermart_pos/models/sale_item_model.dart';
import 'package:supermart_pos/models/sales_return_model.dart';
import 'package:supermart_pos/models/sales_return_item_model.dart';
import 'package:supermart_pos/repositories/cash_movement_repository.dart';
import 'package:supermart_pos/repositories/customer_repository.dart';
import 'package:supermart_pos/repositories/product_repository.dart';
import 'package:supermart_pos/repositories/sale_cancellation_repository.dart';
import 'package:supermart_pos/repositories/sale_repository.dart';
import 'package:supermart_pos/repositories/sales_return_repository.dart';
import 'package:supermart_pos/services/cash_management_service.dart';
import 'package:supermart_pos/services/counter_service.dart';
import 'package:supermart_pos/services/gl_service.dart';

/// Project 2's cross-module scenario: one shift containing every kind of
/// financial event this project touched, reconciled at the end across the
/// customer ledger, the cash book, the GL, stock, audit and the session.
///
/// Written as one ordered test because it is one continuous piece of business.
/// Nothing is hardcoded ahead of the accounting model — the closing assertions
/// are relationships between figures the application produced.
class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this._path);
  final String _path;

  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('accounting_integration_test');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);

    final db = await DatabaseHelper.instance.database;
    for (final user in [
      ('acct-cashier', 'cashier', 'Accounting Cashier'),
      ('acct-manager', 'manager', 'Accounting Manager'),
    ]) {
      await db.insert('users', {
        'id': user.$1,
        'username': user.$1.replaceAll('-', '_'),
        'password_hash': 'x',
        'role': user.$2,
        'name': user.$3,
        'must_change_password': 0,
        'is_active': 1,
        'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      });
    }
  });

  tearDownAll(() async {
    await DatabaseHelper.instance.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('a full shift reconciles across ledger, cash, GL, stock, audit and session', () async {
    final db = await DatabaseHelper.instance.database;
    final gl = GLService();
    final cashBook = CashMovementRepository();
    final customers = CustomerRepository();
    final cashMgmt = CashManagementService();
    const cashier = 'acct-cashier';

    final cashAccount = await gl.requireAccountByCode(GLService.cashAccountCode);
    final bankAccount = await gl.requireAccountByCode(GLService.bankAccountCode);
    final receivableAccount = await gl.requireAccountByCode(GLService.receivableAccountCode);
    final revenueAccount = await gl.requireAccountByCode(GLService.salesRevenueAccountCode);
    final utilitiesAccount = await gl.requireAccountByCode('5300');

    Future<double> netDebit(String accountId) async {
      final rows = await db.rawQuery(
        'SELECT COALESCE(SUM(debit) - SUM(credit), 0) AS net FROM gl_entries WHERE account_id = ?',
        [accountId],
      );
      return (rows.first['net'] as num).toDouble();
    }

    // ------------------------------------------------------------- 1. open
    final session = await CounterService().openShift(userId: cashier, openingCash: 2000);

    // ------------------------------------------------- 2. customer + product
    final ravi = Customer.create(phone: '9876511111', name: 'Ravi');
    await customers.insert(ravi);

    final demo = Product.create(
      barcode: 'ACCT-DEMO-1',
      name: 'Demo Product',
      costPrice: 60,
      retailPrice: 100,
      stockQuantity: 100,
    );
    await ProductRepository().insert(demo);

    // ------------------------------------------------------- 3. cash sale ₹500
    await SaleRepository().insertSaleWithItems(
      sale: Sale.create(
        storeId: 'store_default',
        sessionId: session.id,
        userId: cashier,
        netAmount: 500,
        paymentMethods: const {'cash': 500},
      ),
      items: [SaleItem.create(productId: demo.id, quantity: 5, unitPrice: 100, totalPrice: 500, costPrice: 60)],
      storeId: 'store_default',
    );
    expect(await cashBook.getSessionNet(session.id), 500);
    expect((await ProductRepository().getById(demo.id))!.stockQuantity, 95);

    // ----------------------------------------------------- 4. credit sale ₹300
    final creditSale = await SaleRepository().insertSaleWithItems(
      sale: Sale.create(
        storeId: 'store_default',
        customerId: ravi.id,
        sessionId: session.id,
        userId: cashier,
        netAmount: 300,
        creditUsed: 300,
        isCreditSale: true,
      ),
      items: [SaleItem.create(productId: demo.id, quantity: 3, unitPrice: 100, totalPrice: 300, costPrice: 60)],
      storeId: 'store_default',
      customerId: ravi.id,
    );
    expect((await customers.getById(ravi.id))!.outstandingBalance, 300);
    expect((await ProductRepository().getById(demo.id))!.stockQuantity, 92);

    // -------------------------------------------- 5. khata collection ₹150 cash
    final cashCollectionRef = await customers.receivePayment(
      customerId: ravi.id,
      amount: 150,
      method: 'cash',
      userId: cashier,
      sessionId: session.id,
    );
    expect((await customers.getById(ravi.id))!.outstandingBalance, 150);
    expect(await cashBook.getSessionNet(session.id), 650);

    // --------------------------------------------- 6. khata collection ₹100 UPI
    final upiCollectionRef = await customers.receivePayment(
      customerId: ravi.id,
      amount: 100,
      method: 'upi',
      userId: cashier,
      sessionId: session.id,
    );
    expect((await customers.getById(ravi.id))!.outstandingBalance, 50);
    // UPI moved no notes, so the drawer is unchanged.
    expect(await cashBook.getSessionNet(session.id), 650);

    // ------------------------------------------------------ 7. cash refund ₹50
    await SalesReturnRepository().insertReturn(
      header: SalesReturn.create(
        storeId: 'store_default',
        sessionId: session.id,
        userId: cashier,
        approvedByUserId: 'acct-manager',
        reason: 'Damaged packaging — goodwill refund',
        refundMethod: 'cash',
        refundAmount: 50,
        isUntied: true,
      ),
      items: [
        SalesReturnItem.create(
          productId: demo.id,
          quantity: 1,
          unitPrice: 50,
          totalPrice: 50,
          costPrice: 60,
          restocked: false,
        ),
      ],
    );
    expect(await cashBook.getSessionNet(session.id), 600);
    expect((await ProductRepository().getById(demo.id))!.stockQuantity, 92, reason: 'nothing came back on the shelf');

    // -------------------------------------------------------- 8. cash drop ₹200
    final dropId = await cashMgmt.cashDrop(
      amount: 200,
      userId: cashier,
      destination: 'Main safe',
      sessionId: session.id,
    );
    expect(await cashBook.getSessionNet(session.id), 400);

    // ----------------------------------------------------- 9. cash expense ₹100
    final expenseId = await cashMgmt.cashOut(
      amount: 100,
      reason: 'Electricity top-up paid in cash',
      userId: cashier,
      sessionId: session.id,
      expenseAccountCode: '5300',
    );
    expect(await cashBook.getSessionNet(session.id), 300);

    // ------------------------------------------- 10. cancel the credit sale
    await SaleCancellationRepository().cancelSale(
      sale: creditSale,
      items: await SaleRepository().getItemsBySale(creditSale.id),
      reason: 'Customer returned the whole credit order',
      refundMethod: 'cash',
      userId: cashier,
      approvedByUserId: 'acct-manager',
    );

    // Ravi paid ₹250 toward a ₹300 order that was then voided, so he ends up
    // ₹250 in credit. No notes are handed back: the cancellation refunds a
    // receivable, and paying cash on top would refund him twice.
    final ravisBalance = (await customers.getById(ravi.id))!.outstandingBalance;
    expect(ravisBalance, -250);
    expect(await cashBook.getSessionNet(session.id), 300, reason: 'the cancellation moved no cash');
    expect((await ProductRepository().getById(demo.id))!.stockQuantity, 95, reason: 'three units came back');

    // --------------------------------------------------------- 11. close shift
    final closed = await CounterService().closeShift(
      sessionId: session.id,
      closingCash: 2300,
      denominations: null,
      notes: 'Project 2 integration scenario',
    );

    // =====================================================================
    // Reconciliation
    // =====================================================================

    // --- the till -------------------------------------------------------
    // 2,000 float + 500 cash sale + 150 collection − 50 refund − 200 drop
    // − 100 expense = 2,300.
    expect(closed.expectedCash, 2300);
    expect(closed.difference, 0);

    final book = await cashBook.getBySession(session.id);
    final reconstructed = book.fold<double>(
      session.openingCash,
      (running, m) => running + ((m['direction'] == 'in' ? 1 : -1) * (m['amount'] as num).toDouble()),
    );
    expect(reconstructed, closed.expectedCash, reason: 'the drawer figure is reconstructible line by line');

    // --- customer ledger against GL receivable ---------------------------
    // The invariant AD-3 was chosen to buy: what Ravi's account says and what
    // the GL says about receivables are the same number.
    expect(await netDebit(receivableAccount.id), closeTo(ravisBalance, 0.01));
    expect(await netDebit(receivableAccount.id), closeTo(-250, 0.01));

    // --- GL cash against the cash book -----------------------------------
    // These are two different questions and the difference is exactly the
    // drop. GL Cash is cash held by the *business*; the session cash book is
    // cash in the *till*. A drop to the safe leaves the till without leaving
    // the business, and under a chart of accounts with one Cash account it
    // has no GL effect at all (AD-5) — so the two figures differ by precisely
    // the amount dropped, and by nothing else.
    final glCashMovement = await netDebit(cashAccount.id);
    final tillMovement = await cashBook.getSessionNet(session.id);
    const droppedToSafe = 200.0;
    expect(glCashMovement, closeTo(tillMovement + droppedToSafe, 0.01));
    expect(glCashMovement, closeTo(500, 0.01)); // 500 sale + 150 collection − 50 refund − 100 expense

    // --- GL bank ---------------------------------------------------------
    // The one UPI collection, and nothing else.
    expect(await netDebit(bankAccount.id), closeTo(100, 0.01));

    // --- revenue ---------------------------------------------------------
    // ₹500 cash sale + ₹300 credit sale − ₹300 cancelled − ₹50 refunded.
    expect(await netDebit(revenueAccount.id), closeTo(-450, 0.01));

    // --- expense ---------------------------------------------------------
    expect(await netDebit(utilitiesAccount.id), closeTo(100, 0.01));

    // --- the books balance ----------------------------------------------
    final trialBalance = await db.rawQuery(
      'SELECT COALESCE(SUM(debit) - SUM(credit), 0) AS net FROM gl_entries',
    );
    expect(
      (trialBalance.first['net'] as num).toDouble(),
      closeTo(0, 0.01),
      reason: 'every entry posted this shift is balanced',
    );

    // --- audit -----------------------------------------------------------
    Future<int> auditCount(String action, String recordId) async => (await db.query(
          'audit_log',
          where: 'action_type = ? AND record_id = ?',
          whereArgs: [action, recordId],
        ))
        .length;

    expect(await auditCount('CUSTOMER_PAYMENT_RECEIVED', ravi.id), 2);
    expect(await auditCount('SALE_CANCELLED', creditSale.id), 1);
    expect(await auditCount(CashManagementService.auditAction, dropId), 1);
    expect(await auditCount(CashManagementService.auditAction, expenseId), 1);

    // --- traceability ----------------------------------------------------
    // Every financial movement carries one reference that walks the chain:
    // customer → ledger → cash/bank → GL → audit → session.
    for (final ref in [cashCollectionRef, upiCollectionRef]) {
      expect(
        await db.query('customer_ledger', where: 'reference_id = ?', whereArgs: [ref]),
        hasLength(1),
      );
      expect(
        await db.query(
          'gl_entries',
          where: 'reference_type = ? AND reference_id = ?',
          whereArgs: [GLService.customerPaymentReferenceType, ref],
        ),
        hasLength(2),
      );
    }
    // Only the cash one reached the drawer.
    expect(await db.query('cash_movements', where: 'source_id = ?', whereArgs: [cashCollectionRef]), hasLength(1));
    expect(await db.query('cash_movements', where: 'source_id = ?', whereArgs: [upiCollectionRef]), isEmpty);

    // --- session attribution ---------------------------------------------
    for (final movement in book) {
      expect(movement['session_id'], session.id);
      expect(movement['user_id'], cashier);
    }
    // The manual movements carry the extra explanation v35 added for them.
    final dropRow = (await db.query('cash_movements', where: 'id = ?', whereArgs: [dropId])).first;
    expect(dropRow['counterparty'], 'Main safe');
    expect(dropRow['reason'], isNotNull);
  });
}
