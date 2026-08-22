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
import 'package:supermart_pos/repositories/exchange_repository.dart';
import 'package:supermart_pos/repositories/product_repository.dart';
import 'package:supermart_pos/repositories/sale_cancellation_repository.dart';
import 'package:supermart_pos/repositories/sale_repository.dart';

/// Same harness as `sale_cancellation_repository_test.dart` — a real sqflite
/// (ffi) database in a temp directory, so migrations and transactions run
/// exactly as they do in the app.
class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this._path);
  final String _path;

  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
}

int _phoneCounter = 0;
String _nextPhone() => (9100000000 + (_phoneCounter++)).toString();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late CashMovementRepository cashRepo;

  /// Opens a shift for `test-cashier` and returns its id. Each test gets its
  /// own so their movements cannot bleed into one another's totals.
  Future<String> openShift({double openingCash = 2000}) async {
    final db = await DatabaseHelper.instance.database;
    final id = 'session-${DateTime.now().microsecondsSinceEpoch}';
    await db.insert('sessions', {
      'id': id,
      'user_id': 'test-cashier',
      'opening_time': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'opening_cash': openingCash,
      'status': 'open',
      'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    });
    return id;
  }

  Future<Product> seedProduct() async {
    final product = Product.create(
      barcode: 'CM-${DateTime.now().microsecondsSinceEpoch}',
      name: 'Cash Test Product',
      costPrice: 20,
      retailPrice: 40,
      stockQuantity: 100,
    );
    await ProductRepository().insert(product);
    return product;
  }

  /// A completed sale in [sessionId] paid with the given method split.
  Future<Sale> ringSale({
    required String sessionId,
    required Map<String, double> paymentMethods,
    required double netAmount,
  }) async {
    final product = await seedProduct();
    final item = SaleItem.create(
      productId: product.id,
      quantity: 1,
      unitPrice: netAmount,
      totalPrice: netAmount,
      costPrice: 20,
    );
    return SaleRepository().insertSaleWithItems(
      sale: Sale.create(
        storeId: 'store_default',
        sessionId: sessionId,
        userId: 'test-cashier',
        netAmount: netAmount,
        paymentMethods: paymentMethods,
      ),
      items: [item],
      storeId: 'store_default',
    );
  }

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('cash_movement_test');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);

    final db = await DatabaseHelper.instance.database;
    await db.insert('users', {
      'id': 'test-cashier',
      'username': 'test_cashier',
      'password_hash': 'x',
      'role': 'cashier',
      'name': 'Test Cashier',
      'must_change_password': 0,
      'is_active': 1,
      'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    });
    // Collections above the ₹500 cashier discretion limit need a manager to
    // approve them (P2-C4), so the larger figures below carry one.
    await db.insert('users', {
      'id': 'test-manager',
      'username': 'test_manager',
      'password_hash': 'x',
      'role': 'manager',
      'name': 'Test Manager',
      'must_change_password': 0,
      'is_active': 1,
      'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    });
    cashRepo = CashMovementRepository();
  });

  tearDownAll(() async {
    await DatabaseHelper.instance.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('cash movements — what reaches the drawer', () {
    test('a cash sale records exactly the cash leg, not the whole bill', () async {
      final session = await openShift();

      // ₹1,000 bill: ₹400 cash + ₹600 UPI. Only ₹400 is in the drawer.
      await ringSale(
        sessionId: session,
        netAmount: 1000,
        paymentMethods: {'cash': 400, 'upi': 600},
      );

      expect(await cashRepo.getSessionNet(session), 400);
    });

    test('a fully non-cash sale moves no cash at all', () async {
      final session = await openShift();
      await ringSale(sessionId: session, netAmount: 500, paymentMethods: {'upi': 500});
      expect(await cashRepo.getSessionNet(session), 0);
    });

    test('a khata cash collection reaches the drawer — the C1 hole', () async {
      final session = await openShift();
      final customer = Customer.create(phone: _nextPhone(), name: 'Khata Customer');
      await CustomerRepository().insert(customer);

      // Put the customer in debt, then collect ₹5,000 of it in cash.
      await CustomerRepository().update(customer.copyWith(outstandingBalance: 8000));
      await CustomerRepository().receivePayment(
        customerId: customer.id,
        amount: 5000,
        method: 'cash',
        userId: 'test-cashier',
        sessionId: session,
        approvedByUserId: 'test-manager', // above the ₹500 cashier limit (P2-C4)
      );

      // Before the fix this read 0 — the collection was invisible to shift
      // reconciliation, so a cashier could pocket exactly ₹5,000 and still
      // close a balanced till.
      expect(await cashRepo.getSessionNet(session), 5000);
    });

    test('a khata collection paid by UPI moves no cash', () async {
      final session = await openShift();
      final customer = Customer.create(phone: _nextPhone(), name: 'UPI Customer');
      await CustomerRepository().insert(customer);
      await CustomerRepository().update(customer.copyWith(outstandingBalance: 3000));

      await CustomerRepository().receivePayment(
        customerId: customer.id,
        amount: 3000,
        method: 'upi',
        userId: 'test-cashier',
        approvedByUserId: 'test-manager', // above the ₹500 cashier limit (P2-C4)
        sessionId: session,
      );

      expect(await cashRepo.getSessionNet(session), 0);
    });

    test('receiving a payment writes an audit row naming who took the money', () async {
      final session = await openShift();
      final customer = Customer.create(phone: _nextPhone(), name: 'Audited Customer');
      await CustomerRepository().insert(customer);
      await CustomerRepository().update(customer.copyWith(outstandingBalance: 1000));

      await CustomerRepository().receivePayment(
        customerId: customer.id,
        amount: 1000,
        method: 'cash',
        approvedByUserId: 'test-manager', // above the ₹500 cashier limit (P2-C4)
        userId: 'test-cashier',
        sessionId: session,
      );

      final db = await DatabaseHelper.instance.database;
      final audit = await db.query(
        'audit_log',
        where: 'action_type = ? AND record_id = ?',
        whereArgs: ['CUSTOMER_PAYMENT_RECEIVED', customer.id],
      );
      expect(audit, hasLength(1));
      expect(audit.first['user_id'], 'test-cashier');
    });

    test('cash in and cash out net against each other within a shift', () async {
      final session = await openShift();

      await ringSale(sessionId: session, netAmount: 1000, paymentMethods: {'cash': 1000});
      await cashRepo.recordOut(
        amount: 300,
        sourceType: CashMovementSource.salesReturn,
        sourceId: 'manual-probe',
        sessionId: session,
        userId: 'test-cashier',
        executor: await DatabaseHelper.instance.database,
      );

      expect(await cashRepo.getSessionNet(session), 700);
    });

    test('a movement is attributed to the shift that made it, not another', () async {
      final sessionA = await openShift();
      final sessionB = await openShift();

      await ringSale(sessionId: sessionA, netAmount: 250, paymentMethods: {'cash': 250});

      expect(await cashRepo.getSessionNet(sessionA), 250);
      expect(await cashRepo.getSessionNet(sessionB), 0);
    });

    test('a zero-amount movement is not recorded', () async {
      final session = await openShift();
      await cashRepo.recordIn(
        amount: 0,
        sourceType: CashMovementSource.manualAdjustment,
        sessionId: session,
        userId: 'test-cashier',
        executor: await DatabaseHelper.instance.database,
      );
      expect(await cashRepo.getBySession(session), isEmpty);
    });

    test('direction governs the sign, so a negative amount cannot invert the drawer', () async {
      final session = await openShift();
      await cashRepo.recordOut(
        amount: -500, // caller passed a signed refund by mistake
        sourceType: CashMovementSource.salesReturn,
        sessionId: session,
        userId: 'test-cashier',
        executor: await DatabaseHelper.instance.database,
      );
      // Still counts as ₹500 leaving, not ₹500 arriving.
      expect(await cashRepo.getSessionNet(session), -500);
    });

    test('an unattributed movement still lands in the cash book, just not a shift', () async {
      final session = await openShift();
      await cashRepo.recordIn(
        amount: 100,
        sourceType: CashMovementSource.manualAdjustment,
        userId: null,
        executor: await DatabaseHelper.instance.database,
      );
      // Recorded, but belongs to no shift — so it cannot silently inflate one.
      expect(await cashRepo.getSessionNet(session), 0);
      final db = await DatabaseHelper.instance.database;
      final orphan = await db.query('cash_movements', where: 'session_id IS NULL');
      expect(orphan, isNotEmpty);
    });
  });

  group('C1-05 — cancellation', () {
    test('cancelling a cash sale takes the cash it took back out of the drawer', () async {
      final session = await openShift();
      final sale = await ringSale(
        sessionId: session,
        netAmount: 600,
        paymentMethods: {'cash': 600},
      );
      expect(await cashRepo.getSessionNet(session), 600);

      await SaleCancellationRepository().cancelSale(
        sale: sale,
        items: await SaleRepository().getItemsBySale(sale.id),
        reason: 'Rung up in error',
        refundMethod: 'cash',
        userId: 'test-cashier',
        approvedByUserId: 'test-manager',
      );

      expect(await cashRepo.getSessionNet(session), 0);
    });

    test('cancelling a credit sale for cash pays out nothing — no cash was ever taken', () async {
      final session = await openShift();
      final customer = Customer.create(phone: _nextPhone(), name: 'Credit Cancel Customer');
      await CustomerRepository().insert(customer);

      final product = await seedProduct();
      final sale = await SaleRepository().insertSaleWithItems(
        sale: Sale.create(
          storeId: 'store_default',
          sessionId: session,
          userId: 'test-cashier',
          customerId: customer.id,
          netAmount: 300,
          creditUsed: 300,
          isCreditSale: true,
        ),
        items: [
          SaleItem.create(
            productId: product.id,
            quantity: 1,
            unitPrice: 300,
            totalPrice: 300,
            costPrice: 20,
          ),
        ],
        storeId: 'store_default',
        customerId: customer.id,
      );
      expect(await cashRepo.getSessionNet(session), 0);

      // The operator picks "cash" on the cancel form. The receivable reversal
      // is the real refund here; handing over ₹300 of notes the customer never
      // paid would be the shop paying for its own cancelled sale.
      await SaleCancellationRepository().cancelSale(
        sale: sale,
        items: await SaleRepository().getItemsBySale(sale.id),
        reason: 'Customer changed their mind',
        refundMethod: 'cash',
        userId: 'test-cashier',
        approvedByUserId: 'test-manager',
      );

      expect(await cashRepo.getSessionNet(session), 0);

      // The customer's debt is what actually got cleared.
      final after = await CustomerRepository().getById(customer.id);
      expect(after!.outstandingBalance, 0);
    });

    test('cancelling a split bill returns only the cash leg', () async {
      final session = await openShift();
      final sale = await ringSale(
        sessionId: session,
        netAmount: 1000,
        paymentMethods: {'cash': 400, 'upi': 600},
      );
      expect(await cashRepo.getSessionNet(session), 400);

      await SaleCancellationRepository().cancelSale(
        sale: sale,
        items: await SaleRepository().getItemsBySale(sale.id),
        reason: 'Wrong items',
        refundMethod: 'cash',
        userId: 'test-cashier',
        approvedByUserId: 'test-manager',
      );

      // The ₹600 goes back through UPI, which is not a till movement.
      expect(await cashRepo.getSessionNet(session), 0);
    });

    test('cancelling with a non-cash refund method moves no cash at all', () async {
      final session = await openShift();
      final customer = Customer.create(phone: _nextPhone(), name: 'Adjust Cancel Customer');
      await CustomerRepository().insert(customer);
      final sale = await ringSale(
        sessionId: session,
        netAmount: 500,
        paymentMethods: {'cash': 500},
      );

      await SaleCancellationRepository().cancelSale(
        sale: sale,
        items: await SaleRepository().getItemsBySale(sale.id),
        reason: 'Settled against credit',
        refundMethod: 'credit_adjust',
        userId: 'test-cashier',
        approvedByUserId: 'test-manager',
      );

      // Only the original sale's ₹500 in — nothing paid back over the counter.
      expect(await cashRepo.getSessionNet(session), 500);
    });
  });

  group('C1-06 — exchange is not double counted', () {
    test('a cash-settled exchange nets to the price difference, not to both legs', () async {
      final session = await openShift();
      final customer = Customer.create(phone: _nextPhone(), name: 'Exchange Customer');
      await CustomerRepository().insert(customer);

      final originalSale = await ringSale(
        sessionId: session,
        netAmount: 200,
        paymentMethods: {'cash': 200},
      );
      final originalItems = await SaleRepository().getItemsBySale(originalSale.id);
      expect(await cashRepo.getSessionNet(session), 200);

      final replacement = await seedProduct();

      // Customer brings back the ₹200 item and takes a ₹300 one: they hand
      // over ₹100 at the counter, and that is all the drawer should move.
      await ExchangeRepository().processExchange(
        returnHeader: SalesReturn.create(
          saleId: originalSale.id,
          customerId: customer.id,
          storeId: 'store_default',
          sessionId: session,
          userId: 'test-cashier',
          reason: 'Wrong size',
          refundMethod: 'cash',
          refundAmount: 200,
          isUntied: false,
        ),
        returnItems: [
          SalesReturnItem.create(
            saleItemId: originalItems.first.id,
            productId: originalItems.first.productId,
            quantity: 1,
            unitPrice: 200,
            totalPrice: 200,
            costPrice: 20,
            restocked: true,
          ),
        ],
        newSale: Sale.create(
          storeId: 'store_default',
          customerId: customer.id,
          sessionId: session,
          userId: 'test-cashier',
          netAmount: 300,
          paymentMethods: const {'cash': 300},
        ),
        newSaleItems: [
          SaleItem.create(
            productId: replacement.id,
            quantity: 1,
            unitPrice: 300,
            totalPrice: 300,
            costPrice: 20,
          ),
        ],
        settlementMethod: 'cash',
        userId: 'test-cashier',
        approvedByUserId: 'test-manager',
        storeId: 'store_default',
      );

      // 200 (original) - 200 (return leg) + 300 (replacement) = 300, i.e. the
      // original sale plus the ₹100 difference. The two exchange legs net to
      // the difference instead of counting the whole swap twice.
      expect(await cashRepo.getSessionNet(session), 300);
    });

    test('a credit-adjusted exchange moves no cash on either leg', () async {
      final session = await openShift();
      final customer = Customer.create(phone: _nextPhone(), name: 'Credit Exchange Customer');
      await CustomerRepository().insert(customer);

      final originalSale = await ringSale(
        sessionId: session,
        netAmount: 200,
        paymentMethods: {'cash': 200},
      );
      final originalItems = await SaleRepository().getItemsBySale(originalSale.id);
      final replacement = await seedProduct();

      await ExchangeRepository().processExchange(
        returnHeader: SalesReturn.create(
          saleId: originalSale.id,
          customerId: customer.id,
          storeId: 'store_default',
          sessionId: session,
          userId: 'test-cashier',
          reason: 'Wrong size',
          refundMethod: 'credit_adjust',
          refundAmount: 200,
          isUntied: false,
        ),
        returnItems: [
          SalesReturnItem.create(
            saleItemId: originalItems.first.id,
            productId: originalItems.first.productId,
            quantity: 1,
            unitPrice: 200,
            totalPrice: 200,
            costPrice: 20,
            restocked: true,
          ),
        ],
        newSale: Sale.create(
          storeId: 'store_default',
          customerId: customer.id,
          sessionId: session,
          userId: 'test-cashier',
          netAmount: 300,
        ),
        newSaleItems: [
          SaleItem.create(
            productId: replacement.id,
            quantity: 1,
            unitPrice: 300,
            totalPrice: 300,
            costPrice: 20,
          ),
        ],
        settlementMethod: 'credit_adjust',
        userId: 'test-cashier',
        approvedByUserId: 'test-manager',
        storeId: 'store_default',
      );

      // Unchanged from the original sale: `exchange_settled` and a
      // payment-method-less replacement sale are both correctly silent here.
      expect(await cashRepo.getSessionNet(session), 200);

      final db = await DatabaseHelper.instance.database;
      final settledRows = await db.query(
        'cash_movements',
        where: 'session_id = ? AND source_type = ?',
        whereArgs: [session, CashMovementSource.salesReturn],
      );
      expect(settledRows, isEmpty);
    });
  });

  group('C1-08 — a failed operation leaves no cash behind', () {
    test('a sale that runs out of stock mid-transaction records no cash', () async {
      final session = await openShift();
      final plenty = await seedProduct();

      // Second line asks for more than exists, so the atomic stock guard in
      // SaleRepository fails the whole sale — after the header (and its cash
      // movement) have already been written inside the same transaction.
      final scarce = Product.create(
        barcode: 'SCARCE-${DateTime.now().microsecondsSinceEpoch}',
        name: 'Nearly Sold Out',
        costPrice: 10,
        retailPrice: 50,
        stockQuantity: 1,
      );
      await ProductRepository().insert(scarce);

      await expectLater(
        SaleRepository().insertSaleWithItems(
          sale: Sale.create(
            storeId: 'store_default',
            sessionId: session,
            userId: 'test-cashier',
            netAmount: 700,
            paymentMethods: const {'cash': 700},
          ),
          items: [
            SaleItem.create(productId: plenty.id, quantity: 1, unitPrice: 200, totalPrice: 200, costPrice: 20),
            SaleItem.create(productId: scarce.id, quantity: 10, unitPrice: 50, totalPrice: 500, costPrice: 10),
          ],
          storeId: 'store_default',
        ),
        throwsA(isA<Exception>()),
      );

      // The whole point of writing the movement inside the caller's
      // transaction: a rolled-back sale cannot leave ₹700 of phantom cash
      // that the cashier would then be held short against.
      expect(await cashRepo.getSessionNet(session), 0);
      expect(await cashRepo.getBySession(session), isEmpty);
    });

    test('a payment to a customer that does not exist leaves no cash and no ledger row', () async {
      final session = await openShift();

      await expectLater(
        CustomerRepository().receivePayment(
          customerId: 'no-such-customer',
          amount: 4000,
          method: 'cash',
          userId: 'test-cashier',
          sessionId: session,
        ),
        throwsA(isA<Exception>()),
      );

      expect(await cashRepo.getSessionNet(session), 0);
      final db = await DatabaseHelper.instance.database;
      final ledger = await db.query(
        'customer_ledger',
        where: 'customer_id = ?',
        whereArgs: ['no-such-customer'],
      );
      expect(ledger, isEmpty);
    });
  });

  group('C1-09 — duplicate financial movements are prevented', () {
    test('re-committing the same sale cannot record its cash twice', () async {
      final session = await openShift();
      final sale = await ringSale(
        sessionId: session,
        netAmount: 450,
        paymentMethods: {'cash': 450},
      );
      expect(await cashRepo.getSessionNet(session), 450);

      // Replaying the identical sale — the id is the idempotency key, and
      // `sales.id` being the primary key is what enforces it.
      await expectLater(
        SaleRepository().insertSaleWithItems(
          sale: sale,
          items: await SaleRepository().getItemsBySale(sale.id),
          storeId: 'store_default',
        ),
        throwsA(anything),
      );

      expect(await cashRepo.getSessionNet(session), 450);
      final db = await DatabaseHelper.instance.database;
      final rows = await db.query(
        'cash_movements',
        where: 'source_type = ? AND source_id = ?',
        whereArgs: [CashMovementSource.sale, sale.id],
      );
      expect(rows, hasLength(1));
    });

    test('a sale cannot be cancelled twice, so its refund cannot leave twice', () async {
      final session = await openShift();
      final sale = await ringSale(
        sessionId: session,
        netAmount: 800,
        paymentMethods: {'cash': 800},
      );
      final items = await SaleRepository().getItemsBySale(sale.id);

      await SaleCancellationRepository().cancelSale(
        sale: sale,
        items: items,
        reason: 'First cancel',
        refundMethod: 'cash',
        userId: 'test-cashier',
        approvedByUserId: 'test-manager',
      );
      expect(await cashRepo.getSessionNet(session), 0);

      await expectLater(
        SaleCancellationRepository().cancelSale(
          sale: sale,
          items: items,
          reason: 'Replayed cancel',
          refundMethod: 'cash',
          userId: 'test-cashier',
          approvedByUserId: 'test-manager',
        ),
        throwsA(isA<Exception>()),
      );

      // Not -800: the second attempt paid nothing out.
      expect(await cashRepo.getSessionNet(session), 0);
      final db = await DatabaseHelper.instance.database;
      final refunds = await db.query(
        'cash_movements',
        where: 'session_id = ? AND source_type = ?',
        whereArgs: [session, CashMovementSource.saleCancellation],
      );
      expect(refunds, hasLength(1));
    });

    test('each khata collection is a distinct receipt, traceable on its own reference', () async {
      final session = await openShift();
      final customer = Customer.create(phone: _nextPhone(), name: 'Repeat Payer');
      await CustomerRepository().insert(customer);
      await CustomerRepository().update(customer.copyWith(outstandingBalance: 1000));

      // Two genuine ₹400 collections are two movements, not a duplicate —
      // but each must be tied to its own receipt rather than to the customer,
      // or the cash book cannot say which payment a movement came from.
      final firstRef = await CustomerRepository().receivePayment(
        customerId: customer.id,
        amount: 400,
        method: 'cash',
        userId: 'test-cashier',
        sessionId: session,
      );
      final secondRef = await CustomerRepository().receivePayment(
        customerId: customer.id,
        amount: 400,
        method: 'cash',
        userId: 'test-cashier',
        sessionId: session,
      );

      expect(firstRef, isNot(secondRef));
      expect(await cashRepo.getSessionNet(session), 800);

      final db = await DatabaseHelper.instance.database;
      for (final ref in [firstRef, secondRef]) {
        final movement = await db.query(
          'cash_movements',
          where: 'source_type = ? AND source_id = ?',
          whereArgs: [CashMovementSource.customerPayment, ref],
        );
        expect(movement, hasLength(1));
        expect((movement.first['amount'] as num).toDouble(), 400);

        final ledger = await db.query(
          'customer_ledger',
          where: 'reference_id = ?',
          whereArgs: [ref],
        );
        expect(ledger, hasLength(1));
      }
    });
  });
}
