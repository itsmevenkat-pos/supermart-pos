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
import 'package:supermart_pos/services/gl_service.dart';

/// P2-C2 — cancellation and refund accounting, checked as a whole rather than
/// entry by entry.
///
/// The finding Project 1 left open was "cancellation posts no GL entry for the
/// refund itself". On inspection that was the wrong diagnosis and **no extra
/// entry belongs here** (accounting decision AD-4): for a cash sale the
/// reversal's own `Cr Cash` *is* the refund, and adding a second entry would
/// pay it twice. What was actually wrong was the *original* posting — it sent
/// every non-credit rupee to Cash regardless of how the bill was settled. Fix
/// that (P2-C2 / G1) and the reversal becomes correct by construction, which
/// is what these tests demonstrate.
class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this._path);
  final String _path;

  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
}

int _phoneCounter = 0;
String _nextPhone() => (9600000000 + (_phoneCounter++)).toString();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String cashAccountId;
  late String bankAccountId;
  late String receivableAccountId;
  late String revenueAccountId;

  Future<double> netDebit(String accountId) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.rawQuery(
      'SELECT COALESCE(SUM(debit) - SUM(credit), 0) AS net FROM gl_entries WHERE account_id = ?',
      [accountId],
    );
    return (rows.first['net'] as num).toDouble();
  }

  Future<Product> seedProduct({double stock = 100}) async {
    final product = Product.create(
      barcode: 'CANC-${DateTime.now().microsecondsSinceEpoch}',
      name: 'Cancellation Product',
      costPrice: 40,
      retailPrice: 100,
      stockQuantity: stock,
    );
    await ProductRepository().insert(product);
    return product;
  }

  Future<String> openShift() async {
    final db = await DatabaseHelper.instance.database;
    final id = 'session-${DateTime.now().microsecondsSinceEpoch}';
    await db.insert('sessions', {
      'id': id,
      'user_id': 'canc-cashier',
      'opening_time': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'opening_cash': 2000,
      'status': 'open',
      'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    });
    return id;
  }

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('cancellation_accounting_test');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);

    final db = await DatabaseHelper.instance.database;
    await db.insert('users', {
      'id': 'canc-cashier',
      'username': 'canc_cashier',
      'password_hash': 'x',
      'role': 'cashier',
      'name': 'Cancellation Cashier',
      'must_change_password': 0,
      'is_active': 1,
      'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    });

    await db.insert('users', {
      'id': 'canc-manager',
      'username': 'canc_manager',
      'password_hash': 'x',
      'role': 'manager',
      'name': 'Cancellation Manager',
      'must_change_password': 0,
      'is_active': 1,
      'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    });

    final gl = GLService();
    cashAccountId = (await gl.requireAccountByCode(GLService.cashAccountCode)).id;
    bankAccountId = (await gl.requireAccountByCode(GLService.bankAccountCode)).id;
    receivableAccountId = (await gl.requireAccountByCode(GLService.receivableAccountCode)).id;
    revenueAccountId = (await gl.requireAccountByCode(GLService.salesRevenueAccountCode)).id;
  });

  tearDownAll(() async {
    await DatabaseHelper.instance.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('P2-C2 — cancellation', () {
    test('a cash sale cancellation returns exactly what it took, in the GL and the drawer', () async {
      final session = await openShift();
      final product = await seedProduct();

      final cashBefore = await netDebit(cashAccountId);
      final sale = await SaleRepository().insertSaleWithItems(
        sale: Sale.create(
          storeId: 'store_default',
          sessionId: session,
          userId: 'canc-cashier',
          netAmount: 600,
          paymentMethods: const {'cash': 600},
        ),
        items: [SaleItem.create(productId: product.id, quantity: 6, unitPrice: 100, totalPrice: 600, costPrice: 40)],
        storeId: 'store_default',
      );

      await SaleCancellationRepository().cancelSale(
        sale: sale,
        items: await SaleRepository().getItemsBySale(sale.id),
        reason: 'Rung up in error',
        refundMethod: 'cash',
        userId: 'canc-cashier',
        approvedByUserId: 'canc-manager',
      );

      // Both the GL and the cash book are back where they started, and no
      // second refund entry was posted on top of the reversal (AD-4).
      expect(await netDebit(cashAccountId), closeTo(cashBefore, 0.01));
      expect(await CashMovementRepository().getSessionNet(session), 0);
      expect((await ProductRepository().getById(product.id))!.stockQuantity, 100);
    });

    test('a split-bill cancellation unwinds each leg to its own account', () async {
      final session = await openShift();
      final product = await seedProduct();

      final cashBefore = await netDebit(cashAccountId);
      final bankBefore = await netDebit(bankAccountId);

      // ₹300 notes + ₹700 UPI.
      final sale = await SaleRepository().insertSaleWithItems(
        sale: Sale.create(
          storeId: 'store_default',
          sessionId: session,
          userId: 'canc-cashier',
          netAmount: 1000,
          paymentMethods: const {'cash': 300, 'upi': 700},
        ),
        items: [SaleItem.create(productId: product.id, quantity: 10, unitPrice: 100, totalPrice: 1000, costPrice: 40)],
        storeId: 'store_default',
      );

      expect(await netDebit(cashAccountId), closeTo(cashBefore + 300, 0.01));
      expect(await netDebit(bankAccountId), closeTo(bankBefore + 700, 0.01));
      expect(await CashMovementRepository().getSessionNet(session), 300);

      await SaleCancellationRepository().cancelSale(
        sale: sale,
        items: await SaleRepository().getItemsBySale(sale.id),
        reason: 'Wrong items',
        refundMethod: 'cash',
        userId: 'canc-cashier',
        approvedByUserId: 'canc-manager',
      );

      // This is the case Project 1 could not get right: the drawer gives back
      // only its ₹300 (P1's cap), and now the GL agrees — it credits Cash ₹300
      // and Bank ₹700 rather than crediting Cash for the whole ₹1,000.
      expect(await netDebit(cashAccountId), closeTo(cashBefore, 0.01));
      expect(await netDebit(bankAccountId), closeTo(bankBefore, 0.01));
      expect(await CashMovementRepository().getSessionNet(session), 0);
    });

    test('a credit sale cancellation moves the receivable and pays out nothing', () async {
      final session = await openShift();
      final product = await seedProduct();
      final customer = Customer.create(phone: _nextPhone(), name: 'Credit Cancel');
      await CustomerRepository().insert(customer);

      final cashBefore = await netDebit(cashAccountId);
      final receivableBefore = await netDebit(receivableAccountId);

      final sale = await SaleRepository().insertSaleWithItems(
        sale: Sale.create(
          storeId: 'store_default',
          customerId: customer.id,
          sessionId: session,
          userId: 'canc-cashier',
          netAmount: 500,
          creditUsed: 500,
          isCreditSale: true,
        ),
        items: [SaleItem.create(productId: product.id, quantity: 5, unitPrice: 100, totalPrice: 500, costPrice: 40)],
        storeId: 'store_default',
        customerId: customer.id,
      );

      await SaleCancellationRepository().cancelSale(
        sale: sale,
        items: await SaleRepository().getItemsBySale(sale.id),
        reason: 'Customer changed their mind',
        refundMethod: 'cash', // operator picked cash; no cash was ever taken
        userId: 'canc-cashier',
        approvedByUserId: 'canc-manager',
      );

      expect(await netDebit(cashAccountId), closeTo(cashBefore, 0.01));
      expect(await netDebit(receivableAccountId), closeTo(receivableBefore, 0.01));
      expect(await CashMovementRepository().getSessionNet(session), 0);
      expect((await CustomerRepository().getById(customer.id))!.outstandingBalance, 0);
    });

    test('cancelling a credit sale already part-collected leaves the customer in credit, in both books', () async {
      final session = await openShift();
      final product = await seedProduct();
      final customer = Customer.create(phone: _nextPhone(), name: 'Part Collected');
      await CustomerRepository().insert(customer);

      final cashBefore = await netDebit(cashAccountId);
      final receivableBefore = await netDebit(receivableAccountId);

      // ₹1,000 on credit…
      final sale = await SaleRepository().insertSaleWithItems(
        sale: Sale.create(
          storeId: 'store_default',
          customerId: customer.id,
          sessionId: session,
          userId: 'canc-cashier',
          netAmount: 1000,
          creditUsed: 1000,
          isCreditSale: true,
        ),
        items: [SaleItem.create(productId: product.id, quantity: 10, unitPrice: 100, totalPrice: 1000, costPrice: 40)],
        storeId: 'store_default',
        customerId: customer.id,
      );

      // …of which ₹400 is collected in cash…
      await CustomerRepository().receivePayment(
        customerId: customer.id,
        amount: 400,
        method: 'cash',
        userId: 'canc-cashier',
        sessionId: session,
      );
      expect((await CustomerRepository().getById(customer.id))!.outstandingBalance, 600);

      // …and then the sale is cancelled.
      await SaleCancellationRepository().cancelSale(
        sale: sale,
        items: await SaleRepository().getItemsBySale(sale.id),
        reason: 'Order cancelled after part payment',
        refundMethod: 'cash',
        userId: 'canc-cashier',
        approvedByUserId: 'canc-manager',
      );

      // The shop now owes ₹400 it was genuinely paid. That is a credit on the
      // customer's account, not a till payout — the cancellation hands back
      // nothing, because handing back cash here would be a second refund on
      // top of the credit the customer already holds.
      final balance = (await CustomerRepository().getById(customer.id))!.outstandingBalance;
      expect(balance, -400);
      expect(await CashMovementRepository().getSessionNet(session), 400);

      // GL: cash up ₹400 (real money taken), receivable down ₹400 (what the
      // shop owes). Both agree with the customer ledger.
      expect(await netDebit(cashAccountId), closeTo(cashBefore + 400, 0.01));
      expect(await netDebit(receivableAccountId) - receivableBefore, closeTo(balance, 0.01));
    });
  });

  group('P2-C2 — refunds are not cancellations', () {
    test('a partial return posts only what was refunded and leaves the sale standing', () async {
      final session = await openShift();
      final product = await seedProduct();

      final revenueBefore = await netDebit(revenueAccountId);
      final sale = await SaleRepository().insertSaleWithItems(
        sale: Sale.create(
          storeId: 'store_default',
          sessionId: session,
          userId: 'canc-cashier',
          netAmount: 500,
          paymentMethods: const {'cash': 500},
        ),
        items: [SaleItem.create(productId: product.id, quantity: 5, unitPrice: 100, totalPrice: 500, costPrice: 40)],
        storeId: 'store_default',
      );
      final items = await SaleRepository().getItemsBySale(sale.id);

      // Two of the five come back.
      await SalesReturnRepository().insertReturn(
        header: SalesReturn.create(
          saleId: sale.id,
          storeId: 'store_default',
          sessionId: session,
          userId: 'canc-cashier',
          reason: 'Two items unwanted',
          refundMethod: 'cash',
          refundAmount: 200,
        ),
        items: [
          SalesReturnItem.create(
            saleItemId: items.first.id,
            productId: items.first.productId,
            quantity: 2,
            unitPrice: 100,
            totalPrice: 200,
            costPrice: 40,
          ),
        ],
      );

      final db = await DatabaseHelper.instance.database;
      // The sale itself is untouched — no reversal, still completed.
      final saleRow = await db.query('sales', where: 'id = ?', whereArgs: [sale.id]);
      expect(saleRow.first['status'], 'completed');
      expect(
        await db.query(
          'gl_entries',
          where: 'reference_type = ? AND reference_id = ? AND reversal_of_entry_id IS NOT NULL',
          whereArgs: [GLService.saleReferenceType, sale.id],
        ),
        isEmpty,
        reason: 'a partial return must not reverse the whole sale',
      );

      // Revenue kept: ₹500 sold less ₹200 given back.
      expect(await netDebit(revenueAccountId) - revenueBefore, closeTo(-300, 0.01));
      expect(await CashMovementRepository().getSessionNet(session), 300);
      expect((await ProductRepository().getById(product.id))!.stockQuantity, 97);
    });

    test('a UPI refund leaves the drawer alone and comes out of the bank', () async {
      final session = await openShift();
      final product = await seedProduct();

      final cashBefore = await netDebit(cashAccountId);
      final bankBefore = await netDebit(bankAccountId);

      final sale = await SaleRepository().insertSaleWithItems(
        sale: Sale.create(
          storeId: 'store_default',
          sessionId: session,
          userId: 'canc-cashier',
          netAmount: 400,
          paymentMethods: const {'upi': 400},
        ),
        items: [SaleItem.create(productId: product.id, quantity: 4, unitPrice: 100, totalPrice: 400, costPrice: 40)],
        storeId: 'store_default',
      );
      final items = await SaleRepository().getItemsBySale(sale.id);

      await SalesReturnRepository().insertReturn(
        header: SalesReturn.create(
          saleId: sale.id,
          storeId: 'store_default',
          sessionId: session,
          userId: 'canc-cashier',
          reason: 'Refunded to the same UPI handle',
          refundMethod: 'upi',
          refundAmount: 100,
        ),
        items: [
          SalesReturnItem.create(
            saleItemId: items.first.id,
            productId: items.first.productId,
            quantity: 1,
            unitPrice: 100,
            totalPrice: 100,
            costPrice: 40,
          ),
        ],
      );

      expect(await netDebit(cashAccountId), closeTo(cashBefore, 0.01));
      expect(await netDebit(bankAccountId), closeTo(bankBefore + 300, 0.01));
      expect(await CashMovementRepository().getSessionNet(session), 0);
    });
  });
}
