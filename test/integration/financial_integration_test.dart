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
import 'package:supermart_pos/services/counter_service.dart';
import 'package:supermart_pos/services/gl_service.dart';

/// One shift, start to finish, through the real repositories and a real
/// database — the cross-module check that C1, C2 and C3 hold together rather
/// than only in isolation.
///
/// Written as a single ordered `test` on purpose: this is one continuous piece
/// of business, and each step's expected figures are derived from the state
/// the previous step actually left behind, not restated as literals decided in
/// advance.
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
    tempDir = await Directory.systemTemp.createTemp('financial_integration_test');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);

    final db = await DatabaseHelper.instance.database;
    await db.insert('users', {
      'id': 'cashier-ravi-shift',
      'username': 'shift_cashier',
      'password_hash': 'x',
      'role': 'cashier',
      'name': 'Shift Cashier',
      'must_change_password': 0,
      'is_active': 1,
      'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    });
    await db.insert('users', {
      'id': 'manager-shift',
      'username': 'shift_manager',
      'password_hash': 'x',
      'role': 'manager',
      'name': 'Shift Manager',
      'must_change_password': 0,
      'is_active': 1,
      'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    });
  });

  tearDownAll(() async {
    await DatabaseHelper.instance.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('a full shift keeps cash, customer ledger, stock and GL consistent', () async {
    final db = await DatabaseHelper.instance.database;
    final cash = CashMovementRepository();
    final customers = CustomerRepository();
    final products = ProductRepository();
    final sales = SaleRepository();
    const cashier = 'cashier-ravi-shift';

    // ---------------------------------------------------------------- step 1
    // Open the shift with a ₹2,000 float.
    final session = await CounterService().openShift(userId: cashier, openingCash: 2000);
    expect(session.openingCash, 2000);
    expect(await cash.getSessionNet(session.id), 0);

    // ---------------------------------------------------------------- step 2
    final ravi = Customer.create(phone: '9876500001', name: 'Ravi');
    await customers.insert(ravi);
    expect((await customers.getById(ravi.id))!.outstandingBalance, 0);

    // ---------------------------------------------------------------- step 3
    final demo = Product.create(
      barcode: 'DEMO-0001',
      name: 'Demo Product',
      costPrice: 60,
      retailPrice: 100,
      stockQuantity: 100,
    );
    await products.insert(demo);

    // ---------------------------------------------------------------- step 4
    // Cash sale: 2 × ₹100 = ₹200, paid in notes.
    final cashSale = await sales.insertSaleWithItems(
      sale: Sale.create(
        storeId: 'store_default',
        sessionId: session.id,
        userId: cashier,
        subtotal: 200,
        netAmount: 200,
        paymentMethods: const {'cash': 200},
      ),
      items: [
        SaleItem.create(productId: demo.id, quantity: 2, unitPrice: 100, totalPrice: 200, costPrice: 60),
      ],
      storeId: 'store_default',
    );

    expect((await products.getById(demo.id))!.stockQuantity, 98);
    expect(await cash.getSessionNet(session.id), 200);

    // ---------------------------------------------------------------- step 5
    // Credit sale to Ravi: 3 × ₹100 = ₹300, nothing paid at the till.
    final creditSale = await sales.insertSaleWithItems(
      sale: Sale.create(
        storeId: 'store_default',
        customerId: ravi.id,
        sessionId: session.id,
        userId: cashier,
        subtotal: 300,
        netAmount: 300,
        creditUsed: 300,
        isCreditSale: true,
      ),
      items: [
        SaleItem.create(productId: demo.id, quantity: 3, unitPrice: 100, totalPrice: 300, costPrice: 60),
      ],
      storeId: 'store_default',
      customerId: ravi.id,
    );

    expect((await products.getById(demo.id))!.stockQuantity, 95);
    expect((await customers.getById(ravi.id))!.outstandingBalance, 300);
    // A credit sale puts no notes in the drawer.
    expect(await cash.getSessionNet(session.id), 200);

    // ---------------------------------------------------------------- step 6
    // Collect ₹150 of Ravi's khata in cash. Below the ₹500 default threshold,
    // so no approval is required — ordinary cashier work.
    final paymentRef = await customers.receivePayment(
      customerId: ravi.id,
      amount: 150,
      method: 'cash',
      userId: cashier,
      sessionId: session.id,
    );

    expect((await customers.getById(ravi.id))!.outstandingBalance, 150);
    expect(await cash.getSessionNet(session.id), 350);
    expect(
      await db.query('cash_movements', where: 'source_id = ?', whereArgs: [paymentRef]),
      hasLength(1),
    );
    expect(
      await db.query(
        'audit_log',
        where: 'action_type = ? AND record_id = ?',
        whereArgs: ['CUSTOMER_PAYMENT_RECEIVED', ravi.id],
      ),
      hasLength(1),
    );

    // ---------------------------------------------------------------- step 7
    // A ₹50 cash price adjustment, refunded over the counter. Nothing comes
    // back on the shelf (`restocked: false`), so stock must not move.
    final refund = await SalesReturnRepository().insertReturn(
      header: SalesReturn.create(
        storeId: 'store_default',
        sessionId: session.id,
        userId: cashier,
        approvedByUserId: 'manager-shift',
        reason: 'Price adjustment — damaged packaging',
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

    expect((await products.getById(demo.id))!.stockQuantity, 95);
    expect(await cash.getSessionNet(session.id), 300);
    expect(
      await db.query(
        'cash_movements',
        where: 'source_type = ? AND source_id = ?',
        whereArgs: [CashMovementSource.salesReturn, refund.id],
      ),
      hasLength(1),
    );

    // ---------------------------------------------------------------- step 8
    // Cancel the credit sale. The cash sale is equally eligible; the credit
    // one is chosen because it exercises all four subsystems at once —
    // receivable, stock, GL and (by paying nothing out) the cash rule.
    final creditSaleGlBefore = await db.query(
      'gl_entries',
      where: 'reference_type = ? AND reference_id = ?',
      whereArgs: [GLService.saleReferenceType, creditSale.id],
    );
    expect(creditSaleGlBefore, isNotEmpty);

    final cancellation = await SaleCancellationRepository().cancelSale(
      sale: creditSale,
      items: await sales.getItemsBySale(creditSale.id),
      reason: 'Customer returned the whole order',
      refundMethod: 'cash',
      userId: cashier,
      approvedByUserId: 'manager-shift',
    );

    // Stock: the three units come back.
    expect((await products.getById(demo.id))!.stockQuantity, 98);

    // Customer: the ₹300 receivable is reversed. Ravi had already paid ₹150
    // against it, so he is now ₹150 in credit — the shop owes him, which is
    // the correct outcome, not a bug.
    expect((await customers.getById(ravi.id))!.outstandingBalance, -150);

    // Cash: nothing paid out. The cancelled sale took no notes, so refunding
    // notes would be the shop paying for its own void (see
    // SaleCancellationRepository's cash-book block).
    expect(await cash.getSessionNet(session.id), 300);
    expect(
      await db.query('cash_movements', where: 'source_id = ?', whereArgs: [cancellation.id]),
      isEmpty,
    );

    // Sale status and audit.
    final cancelledRow = await db.query('sales', where: 'id = ?', whereArgs: [creditSale.id]);
    expect(cancelledRow.first['status'], 'cancelled');
    expect(
      await db.query(
        'audit_log',
        where: 'action_type = ? AND record_id = ?',
        whereArgs: ['SALE_CANCELLED', creditSale.id],
      ),
      hasLength(1),
    );

    // GL: every line of the cancelled sale reversed, nothing else touched.
    final creditSaleGlAfter = await db.query(
      'gl_entries',
      where: 'reference_type = ? AND reference_id = ?',
      whereArgs: [GLService.saleReferenceType, creditSale.id],
    );
    expect(creditSaleGlAfter.length, creditSaleGlBefore.length * 2);
    final netOnCancelledSale = <String, double>{};
    for (final e in creditSaleGlAfter) {
      final account = e['account_id'] as String;
      netOnCancelledSale[account] = (netOnCancelledSale[account] ?? 0) +
          (e['debit'] as num).toDouble() -
          (e['credit'] as num).toDouble();
    }
    for (final entry in netOnCancelledSale.entries) {
      expect(entry.value, closeTo(0, 0.01));
    }

    // The cash sale's own entries are untouched by the cancellation.
    final cashSaleGl = await db.query(
      'gl_entries',
      where: 'reference_type = ? AND reference_id = ?',
      whereArgs: [GLService.saleReferenceType, cashSale.id],
    );
    expect(cashSaleGl.where((e) => e['reversal_of_entry_id'] != null), isEmpty);

    // ---------------------------------------------------------------- step 9
    final expectedFromLedger = session.openingCash + await cash.getSessionNet(session.id);
    final closed = await CounterService().closeShift(
      sessionId: session.id,
      closingCash: 2300,
      denominations: null,
      notes: 'Integration scenario',
    );

    // 2,000 float + 200 cash sale + 150 khata collection - 50 refund = 2,300.
    expect(expectedFromLedger, 2300);
    expect(closed.expectedCash, 2300);
    expect(closed.difference, 0);
    expect(closed.status, 'closed');

    // ------------------------------------------------------- whole-shift GL
    // Revenue actually earned this shift: the ₹200 cash sale less the ₹50
    // refund. The ₹300 credit sale nets out with its own reversal.
    final revenueAccount = await GLService().requireAccountByCode(GLService.salesRevenueAccountCode);
    final revenueRows = await db.rawQuery(
      'SELECT COALESCE(SUM(credit) - SUM(debit), 0) AS net FROM gl_entries WHERE account_id = ?',
      [revenueAccount.id],
    );
    expect((revenueRows.first['net'] as num).toDouble(), closeTo(150, 0.01));

    // The divergence Project 1 pinned here is closed (Project 2, P2-C1).
    //
    // This assertion used to read `closeTo(0, 0.01)` with a comment saying a
    // khata collection posted nothing to the GL, so GL Accounts Receivable
    // stayed at 0 while Ravi's ledger showed a ₹150 advance — and that the day
    // it was fixed, this expectation should fail and be updated deliberately.
    // That is what happened: `receivePayment` now posts Dr Cash / Cr AR, so the
    // two figures agree. Ravi paid ₹150 toward a sale that was then cancelled,
    // so both the ledger and the GL now say the shop owes him ₹150.
    final receivableAccount = await GLService().requireAccountByCode(GLService.receivableAccountCode);
    final receivableRows = await db.rawQuery(
      'SELECT COALESCE(SUM(debit) - SUM(credit), 0) AS net FROM gl_entries WHERE account_id = ?',
      [receivableAccount.id],
    );
    final glReceivable = (receivableRows.first['net'] as num).toDouble();
    final ravisBalance = (await customers.getById(ravi.id))!.outstandingBalance;
    expect(ravisBalance, -150);
    expect(glReceivable, closeTo(ravisBalance, 0.01));

    // --------------------------------------------------------- cash book tie
    // The drawer figure is reconstructible line by line, which is the whole
    // reason the cash movement ledger exists.
    final book = await cash.getBySession(session.id);
    expect(book, hasLength(3));
    final bySource = {for (final m in book) m['source_type'] as String: m};
    expect(bySource.keys, containsAll([
      CashMovementSource.sale,
      CashMovementSource.customerPayment,
      CashMovementSource.salesReturn,
    ]));
    for (final movement in book) {
      expect(movement['session_id'], session.id);
      expect(movement['user_id'], cashier);
    }
    final reconstructed = book.fold<double>(
      session.openingCash,
      (running, m) => running + ((m['direction'] == 'in' ? 1 : -1) * (m['amount'] as num).toDouble()),
    );
    expect(reconstructed, closed.expectedCash);
  });
}
