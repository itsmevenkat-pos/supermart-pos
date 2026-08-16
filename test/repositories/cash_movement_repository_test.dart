import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:supermart_pos/core/database/database_helper.dart';
import 'package:supermart_pos/models/customer_model.dart';
import 'package:supermart_pos/models/product_model.dart';
import 'package:supermart_pos/models/sale_model.dart';
import 'package:supermart_pos/models/sale_item_model.dart';
import 'package:supermart_pos/repositories/cash_movement_repository.dart';
import 'package:supermart_pos/repositories/customer_repository.dart';
import 'package:supermart_pos/repositories/product_repository.dart';
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
}
