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
import 'package:supermart_pos/repositories/sale_repository.dart';
import 'package:supermart_pos/repositories/sales_return_repository.dart';
import 'package:supermart_pos/services/counter_service.dart';

/// C1 — shift reconciliation, end to end through the service a cashier
/// actually closes a till with.
///
/// The point of these tests is *not* that `SUM(cash_movements)` adds up; the
/// cash movement repository's own tests cover that. It is that the number
/// `CounterService.closeShift` computes, persists on the session and derives
/// the shortage/overage from is that sum — because the historical defect was
/// precisely a reconciliation that agreed with the drawer only when nothing
/// but selling had happened.
///
/// Every figure below is produced by running the real repositories against a
/// real sqflite (ffi) database, never by arithmetic in the test.
class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this._path);
  final String _path;

  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
}

int _phoneCounter = 0;
String _nextPhone() => (9200000000 + (_phoneCounter++)).toString();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late CounterService counter;

  /// A distinct cashier per test, so `openShift`'s one-open-shift-per-user
  /// guard doesn't make tests depend on each other's teardown.
  int userCounter = 0;
  Future<String> newCashier() async {
    final db = await DatabaseHelper.instance.database;
    final id = 'cashier-${userCounter++}';
    await db.insert('users', {
      'id': id,
      'username': 'user_$id',
      'password_hash': 'x',
      'role': 'cashier',
      'name': 'Cashier $id',
      'must_change_password': 0,
      'is_active': 1,
      'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    });
    return id;
  }

  Future<Product> seedProduct({double retailPrice = 100, double stock = 100}) async {
    final product = Product.create(
      barcode: 'CS-${DateTime.now().microsecondsSinceEpoch}',
      name: 'Counter Test Product',
      costPrice: 40,
      retailPrice: retailPrice,
      stockQuantity: stock,
    );
    await ProductRepository().insert(product);
    return product;
  }

  /// Rings a real sale through `SaleRepository`, paid with [paymentMethods].
  Future<Sale> ringSale({
    required String sessionId,
    required String userId,
    required Map<String, double> paymentMethods,
    required double netAmount,
    String? customerId,
    double creditUsed = 0,
  }) async {
    final product = await seedProduct();
    final item = SaleItem.create(
      productId: product.id,
      quantity: 1,
      unitPrice: netAmount,
      totalPrice: netAmount,
      costPrice: 40,
    );
    return SaleRepository().insertSaleWithItems(
      sale: Sale.create(
        storeId: 'store_default',
        sessionId: sessionId,
        userId: userId,
        customerId: customerId,
        netAmount: netAmount,
        paymentMethods: paymentMethods,
        creditUsed: creditUsed > 0 ? creditUsed : null,
        isCreditSale: creditUsed > 0,
      ),
      items: [item],
      storeId: 'store_default',
      customerId: customerId,
    );
  }

  Future<Customer> seedCustomer({double owes = 0}) async {
    final customer = Customer.create(phone: _nextPhone(), name: 'Counter Customer');
    await CustomerRepository().insert(customer);
    if (owes != 0) {
      await CustomerRepository().update(customer.copyWith(outstandingBalance: owes));
    }
    return customer;
  }

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('counter_service_test');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
    final db = await DatabaseHelper.instance.database;
    // Collections above the ₹500 cashier discretion limit need a manager to
    // approve them (P2-C4), so the larger figures below carry one.
    await db.insert('users', {
      'id': 'shift-manager',
      'username': 'shift_manager',
      'password_hash': 'x',
      'role': 'manager',
      'name': 'Shift Manager',
      'must_change_password': 0,
      'is_active': 1,
      'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    });
    counter = CounterService();
  });

  tearDownAll(() async {
    await DatabaseHelper.instance.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('C1 — expected cash is the cash movement ledger, not just sales', () {
    test('C1-01 opening cash only: a shift with no activity expects its float back', () async {
      final user = await newCashier();
      final session = await counter.openShift(userId: user, openingCash: 2000);

      final closed = await counter.closeShift(
        sessionId: session.id,
        closingCash: 2000,
        denominations: null,
      );

      expect(closed.expectedCash, 2000);
      expect(closed.difference, 0);
      expect(closed.status, 'closed');
    });

    test('C1-02 opening + cash sale', () async {
      final user = await newCashier();
      final session = await counter.openShift(userId: user, openingCash: 2000);

      await ringSale(
        sessionId: session.id,
        userId: user,
        netAmount: 500,
        paymentMethods: {'cash': 500},
      );

      final closed = await counter.closeShift(
        sessionId: session.id,
        closingCash: 2500,
        denominations: null,
      );

      expect(closed.expectedCash, 2500);
      expect(closed.difference, 0);
    });

    test('C1-03 opening + cash sale + khata collection — the historical hole', () async {
      final user = await newCashier();
      final session = await counter.openShift(userId: user, openingCash: 2000);

      await ringSale(
        sessionId: session.id,
        userId: user,
        netAmount: 500,
        paymentMethods: {'cash': 500},
      );

      final customer = await seedCustomer(owes: 1000);
      await CustomerRepository().receivePayment(
        customerId: customer.id,
        amount: 300,
        method: 'cash',
        userId: user,
        sessionId: session.id,
      );

      final closed = await counter.closeShift(
        sessionId: session.id,
        closingCash: 2800,
        denominations: null,
      );

      // Before the fix this expected ₹2,500 against a drawer holding ₹2,800:
      // the cashier could have removed the ₹300 khata collection and still
      // closed balanced. Now the collection is part of what the till owes.
      expect(closed.expectedCash, 2800);
      expect(closed.difference, 0);
    });

    test('C1-03b a pocketed khata collection now shows as a shortage', () async {
      final user = await newCashier();
      final session = await counter.openShift(userId: user, openingCash: 2000);

      final customer = await seedCustomer(owes: 5000);
      await CustomerRepository().receivePayment(
        customerId: customer.id,
        amount: 5000,
        method: 'cash',
        userId: user,
        sessionId: session.id,
        approvedByUserId: 'shift-manager', // above the ₹500 cashier limit (P2-C4)
      );

      // Cashier collects ₹5,000 and hands over a drawer holding only the float.
      final closed = await counter.closeShift(
        sessionId: session.id,
        closingCash: 2000,
        denominations: null,
      );

      expect(closed.expectedCash, 7000);
      expect(closed.difference, -5000);
    });

    test('C1-04 a cash refund reduces what the drawer owes', () async {
      final user = await newCashier();
      final session = await counter.openShift(userId: user, openingCash: 2000);

      final sale = await ringSale(
        sessionId: session.id,
        userId: user,
        netAmount: 1000,
        paymentMethods: {'cash': 1000},
      );
      final saleItems = await SaleRepository().getItemsBySale(sale.id);

      await SalesReturnRepository().insertReturn(
        header: SalesReturn.create(
          saleId: sale.id,
          storeId: 'store_default',
          sessionId: session.id,
          userId: user,
          reason: 'Damaged item',
          refundMethod: 'cash',
          refundAmount: 200,
          isUntied: false,
        ),
        items: [
          SalesReturnItem.create(
            saleItemId: saleItems.first.id,
            productId: saleItems.first.productId,
            quantity: 1,
            unitPrice: 200,
            taxAmount: 0,
            totalPrice: 200,
            costPrice: 40,
            restocked: true,
          ),
        ],
      );

      final closed = await counter.closeShift(
        sessionId: session.id,
        closingCash: 2800,
        denominations: null,
      );

      // An honest cashier who paid out ₹200 used to read ₹200 short.
      expect(closed.expectedCash, 2800);
      expect(closed.difference, 0);
    });

    test('a non-cash collection does not change what the drawer owes', () async {
      final user = await newCashier();
      final session = await counter.openShift(userId: user, openingCash: 2000);

      final customer = await seedCustomer(owes: 3000);
      await CustomerRepository().receivePayment(
        customerId: customer.id,
        amount: 3000,
        method: 'upi',
        userId: user,
        approvedByUserId: 'shift-manager', // above the ₹500 cashier limit (P2-C4)
        sessionId: session.id,
      );

      final closed = await counter.closeShift(
        sessionId: session.id,
        closingCash: 2000,
        denominations: null,
      );

      expect(closed.expectedCash, 2000);
      expect(closed.difference, 0);
    });

    test('a credit sale puts nothing in the drawer', () async {
      final user = await newCashier();
      final session = await counter.openShift(userId: user, openingCash: 2000);
      final customer = await seedCustomer();

      await ringSale(
        sessionId: session.id,
        userId: user,
        netAmount: 300,
        paymentMethods: {},
        customerId: customer.id,
        creditUsed: 300,
      );

      final closed = await counter.closeShift(
        sessionId: session.id,
        closingCash: 2000,
        denominations: null,
      );

      expect(closed.expectedCash, 2000);
      expect(closed.difference, 0);
    });

    test('a split bill contributes only its cash leg', () async {
      final user = await newCashier();
      final session = await counter.openShift(userId: user, openingCash: 1000);

      await ringSale(
        sessionId: session.id,
        userId: user,
        netAmount: 1000,
        paymentMethods: {'cash': 400, 'upi': 600},
      );

      final closed = await counter.closeShift(
        sessionId: session.id,
        closingCash: 1400,
        denominations: null,
      );

      expect(closed.expectedCash, 1400);
      expect(closed.difference, 0);
    });

    test('the persisted expected cash equals opening + the ledger net, exactly', () async {
      final user = await newCashier();
      final session = await counter.openShift(userId: user, openingCash: 2000);

      await ringSale(
        sessionId: session.id,
        userId: user,
        netAmount: 750,
        paymentMethods: {'cash': 750},
      );
      final customer = await seedCustomer(owes: 900);
      await CustomerRepository().receivePayment(
        customerId: customer.id,
        amount: 900,
        method: 'cash',
        approvedByUserId: 'shift-manager', // above the ₹500 cashier limit (P2-C4)
        userId: user,
        sessionId: session.id,
      );

      final ledgerNet = await CashMovementRepository().getSessionNet(session.id);
      final closed = await counter.closeShift(
        sessionId: session.id,
        closingCash: 0,
        denominations: null,
      );

      // Derived from the ledger rather than restated as a literal — the
      // assertion is the *relationship*, which is what regressed before.
      expect(closed.expectedCash, session.openingCash + ledgerNet);
      expect(closed.difference, -(session.openingCash + ledgerNet));
    });
  });

  group('C1-07 — session isolation', () {
    test('two shifts reconcile independently', () async {
      final userA = await newCashier();
      final userB = await newCashier();
      final sessionA = await counter.openShift(userId: userA, openingCash: 2000);
      final sessionB = await counter.openShift(userId: userB, openingCash: 500);

      await ringSale(
        sessionId: sessionA.id,
        userId: userA,
        netAmount: 1000,
        paymentMethods: {'cash': 1000},
      );
      final customerB = await seedCustomer(owes: 250);
      await CustomerRepository().receivePayment(
        customerId: customerB.id,
        amount: 250,
        method: 'cash',
        userId: userB,
        sessionId: sessionB.id,
      );

      final closedA = await counter.closeShift(
        sessionId: sessionA.id,
        closingCash: 3000,
        denominations: null,
      );
      final closedB = await counter.closeShift(
        sessionId: sessionB.id,
        closingCash: 750,
        denominations: null,
      );

      expect(closedA.expectedCash, 3000);
      expect(closedA.difference, 0);
      expect(closedB.expectedCash, 750);
      expect(closedB.difference, 0);
    });

    test('a movement with no shift attribution inflates no shift', () async {
      final user = await newCashier();
      final session = await counter.openShift(userId: user, openingCash: 2000);

      // A collection taken with no session stamped and no open shift to infer
      // one from — it belongs in the cash book but in nobody's reconciliation.
      final orphanUserDb = await DatabaseHelper.instance.database;
      await CashMovementRepository().recordIn(
        amount: 999,
        sourceType: CashMovementSource.manualAdjustment,
        executor: orphanUserDb,
      );

      final closed = await counter.closeShift(
        sessionId: session.id,
        closingCash: 2000,
        denominations: null,
      );

      expect(closed.expectedCash, 2000);
      expect(closed.difference, 0);
    });
  });

  group('shift lifecycle guards', () {
    test('a shift cannot be closed twice', () async {
      final user = await newCashier();
      final session = await counter.openShift(userId: user, openingCash: 100);
      await counter.closeShift(sessionId: session.id, closingCash: 100, denominations: null);

      expect(
        () => counter.closeShift(sessionId: session.id, closingCash: 100, denominations: null),
        throwsA(isA<Exception>()),
      );
    });

    test('a cashier cannot open a second shift while one is open', () async {
      final user = await newCashier();
      await counter.openShift(userId: user, openingCash: 100);

      expect(
        () => counter.openShift(userId: user, openingCash: 100),
        throwsA(isA<Exception>()),
      );
    });
  });
}
