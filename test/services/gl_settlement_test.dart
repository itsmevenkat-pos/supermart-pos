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
import 'package:supermart_pos/repositories/sale_repository.dart';
import 'package:supermart_pos/repositories/sales_return_repository.dart';
import 'package:supermart_pos/services/gl_service.dart';

/// P2-C2 — the GL must know the difference between notes and a bank transfer.
///
/// The defect these cover: `postSaleEntries` and `postSalesReturnEntries` only
/// distinguished "receivable" from "not receivable" and booked everything else
/// to Cash 1000, while the cash book (Project 1) used the much stricter rule
/// `method == 'cash'`. So GL Cash was neither the drawer nor the bank — it was
/// an unlabelled mixture, overstated by every UPI/card sale and understated by
/// every UPI/card refund.
///
/// Accounting decision AD-1: non-cash settlement posts to Bank 1010, matching
/// what `postGatewayPaymentEntries` already did for gateway payments.
class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this._path);
  final String _path;

  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
}

int _phoneCounter = 0;
String _nextPhone() => (9400000000 + (_phoneCounter++)).toString();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String cashAccountId;
  late String bankAccountId;
  late String receivableAccountId;
  late String revenueAccountId;

  Future<Product> seedProduct({double stock = 100}) async {
    final product = Product.create(
      barcode: 'GLS-${DateTime.now().microsecondsSinceEpoch}',
      name: 'Settlement Product',
      costPrice: 40,
      retailPrice: 100,
      stockQuantity: stock,
    );
    await ProductRepository().insert(product);
    return product;
  }

  /// Net movement on one account across the whole journal, in its natural
  /// direction (debit-positive for assets).
  Future<double> netDebit(String accountId) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.rawQuery(
      'SELECT COALESCE(SUM(debit) - SUM(credit), 0) AS net FROM gl_entries WHERE account_id = ?',
      [accountId],
    );
    return (rows.first['net'] as num).toDouble();
  }

  /// Net movement on one account restricted to a single source document.
  Future<double> netDebitFor(String accountId, String referenceType, String referenceId) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(debit) - SUM(credit), 0) AS net FROM gl_entries
      WHERE account_id = ? AND reference_type = ? AND reference_id = ?
      ''',
      [accountId, referenceType, referenceId],
    );
    return (rows.first['net'] as num).toDouble();
  }

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('gl_settlement_test');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);

    final db = await DatabaseHelper.instance.database;
    await db.insert('users', {
      'id': 'settlement-cashier',
      'username': 'settlement_cashier',
      'password_hash': 'x',
      'role': 'cashier',
      'name': 'Settlement Cashier',
      'must_change_password': 0,
      'is_active': 1,
      'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    });
    await db.insert('users', {
      'id': 'settlement-manager',
      'username': 'settlement_manager',
      'password_hash': 'x',
      'role': 'manager',
      'name': 'Settlement Manager',
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

  group('G1 — a sale posts settlement to the account that actually holds it', () {
    test('a cash sale debits Cash', () async {
      final product = await seedProduct();
      final sale = await SaleRepository().insertSaleWithItems(
        sale: Sale.create(
          storeId: 'store_default',
          userId: 'settlement-cashier',
          netAmount: 500,
          paymentMethods: const {'cash': 500},
        ),
        items: [SaleItem.create(productId: product.id, quantity: 5, unitPrice: 100, totalPrice: 500, costPrice: 40)],
        storeId: 'store_default',
      );

      expect(await netDebitFor(cashAccountId, GLService.saleReferenceType, sale.id), 500);
      expect(await netDebitFor(bankAccountId, GLService.saleReferenceType, sale.id), 0);
      expect(await netDebitFor(revenueAccountId, GLService.saleReferenceType, sale.id), -500);
    });

    test('a UPI sale debits Bank, not Cash', () async {
      final product = await seedProduct();
      final sale = await SaleRepository().insertSaleWithItems(
        sale: Sale.create(
          storeId: 'store_default',
          userId: 'settlement-cashier',
          netAmount: 500,
          paymentMethods: const {'upi': 500},
        ),
        items: [SaleItem.create(productId: product.id, quantity: 5, unitPrice: 100, totalPrice: 500, costPrice: 40)],
        storeId: 'store_default',
      );

      // The drawer did not move, so GL Cash must not either.
      expect(await netDebitFor(cashAccountId, GLService.saleReferenceType, sale.id), 0);
      expect(await netDebitFor(bankAccountId, GLService.saleReferenceType, sale.id), 500);
    });

    test('a card sale debits Bank, not Cash', () async {
      final product = await seedProduct();
      final sale = await SaleRepository().insertSaleWithItems(
        sale: Sale.create(
          storeId: 'store_default',
          userId: 'settlement-cashier',
          netAmount: 300,
          paymentMethods: const {'card': 300},
        ),
        items: [SaleItem.create(productId: product.id, quantity: 3, unitPrice: 100, totalPrice: 300, costPrice: 40)],
        storeId: 'store_default',
      );

      expect(await netDebitFor(cashAccountId, GLService.saleReferenceType, sale.id), 0);
      expect(await netDebitFor(bankAccountId, GLService.saleReferenceType, sale.id), 300);
    });

    test('a split bill splits the settlement across Cash and Bank', () async {
      final product = await seedProduct();
      final sale = await SaleRepository().insertSaleWithItems(
        sale: Sale.create(
          storeId: 'store_default',
          userId: 'settlement-cashier',
          netAmount: 1000,
          paymentMethods: const {'cash': 400, 'upi': 600},
        ),
        items: [SaleItem.create(productId: product.id, quantity: 10, unitPrice: 100, totalPrice: 1000, costPrice: 40)],
        storeId: 'store_default',
      );

      expect(await netDebitFor(cashAccountId, GLService.saleReferenceType, sale.id), 400);
      expect(await netDebitFor(bankAccountId, GLService.saleReferenceType, sale.id), 600);
      expect(await netDebitFor(revenueAccountId, GLService.saleReferenceType, sale.id), -1000);
    });

    test('a part-cash, part-credit bill splits three ways', () async {
      final product = await seedProduct();
      final customer = Customer.create(phone: _nextPhone(), name: 'Split Credit Customer');
      await CustomerRepository().insert(customer);

      final sale = await SaleRepository().insertSaleWithItems(
        sale: Sale.create(
          storeId: 'store_default',
          customerId: customer.id,
          userId: 'settlement-cashier',
          netAmount: 1000,
          paymentMethods: const {'cash': 300, 'upi': 200},
          partialPaymentAmount: 500,
        ),
        items: [SaleItem.create(productId: product.id, quantity: 10, unitPrice: 100, totalPrice: 1000, costPrice: 40)],
        storeId: 'store_default',
        customerId: customer.id,
      );

      expect(await netDebitFor(cashAccountId, GLService.saleReferenceType, sale.id), 300);
      expect(await netDebitFor(bankAccountId, GLService.saleReferenceType, sale.id), 200);
      expect(await netDebitFor(receivableAccountId, GLService.saleReferenceType, sale.id), 500);
      expect(await netDebitFor(revenueAccountId, GLService.saleReferenceType, sale.id), -1000);
    });

    test('a credit sale debits only Accounts Receivable', () async {
      final product = await seedProduct();
      final customer = Customer.create(phone: _nextPhone(), name: 'Pure Credit Customer');
      await CustomerRepository().insert(customer);

      final sale = await SaleRepository().insertSaleWithItems(
        sale: Sale.create(
          storeId: 'store_default',
          customerId: customer.id,
          userId: 'settlement-cashier',
          netAmount: 400,
          creditUsed: 400,
          isCreditSale: true,
        ),
        items: [SaleItem.create(productId: product.id, quantity: 4, unitPrice: 100, totalPrice: 400, costPrice: 40)],
        storeId: 'store_default',
        customerId: customer.id,
      );

      expect(await netDebitFor(cashAccountId, GLService.saleReferenceType, sale.id), 0);
      expect(await netDebitFor(bankAccountId, GLService.saleReferenceType, sale.id), 0);
      expect(await netDebitFor(receivableAccountId, GLService.saleReferenceType, sale.id), 400);
    });
  });

  group('G2 — a refund credits the account the money actually leaves', () {
    Future<Sale> ringSale(Map<String, double> methods, double amount) async {
      final product = await seedProduct();
      return SaleRepository().insertSaleWithItems(
        sale: Sale.create(
          storeId: 'store_default',
          userId: 'settlement-cashier',
          netAmount: amount,
          paymentMethods: methods,
        ),
        items: [
          SaleItem.create(
              productId: product.id, quantity: amount / 100, unitPrice: 100, totalPrice: amount, costPrice: 40),
        ],
        storeId: 'store_default',
      );
    }

    test('a cash refund credits Cash', () async {
      final sale = await ringSale({'cash': 500}, 500);
      final items = await SaleRepository().getItemsBySale(sale.id);

      final ret = await SalesReturnRepository().insertReturn(
        header: SalesReturn.create(
          saleId: sale.id,
          storeId: 'store_default',
          userId: 'settlement-cashier',
          reason: 'Cash refund',
          refundMethod: 'cash',
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

      expect(await netDebitFor(cashAccountId, GLService.returnReferenceType, ret.id), -100);
      expect(await netDebitFor(bankAccountId, GLService.returnReferenceType, ret.id), 0);
      expect(await netDebitFor(revenueAccountId, GLService.returnReferenceType, ret.id), 100);
    });

    test('a UPI refund credits Bank, not Cash', () async {
      final sale = await ringSale({'upi': 500}, 500);
      final items = await SaleRepository().getItemsBySale(sale.id);

      final ret = await SalesReturnRepository().insertReturn(
        header: SalesReturn.create(
          saleId: sale.id,
          storeId: 'store_default',
          userId: 'settlement-cashier',
          reason: 'UPI refund',
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

      // No notes left the drawer, so GL Cash must not move.
      expect(await netDebitFor(cashAccountId, GLService.returnReferenceType, ret.id), 0);
      expect(await netDebitFor(bankAccountId, GLService.returnReferenceType, ret.id), -100);
    });

    test('a credit-adjusted refund credits Accounts Receivable', () async {
      final customer = Customer.create(phone: _nextPhone(), name: 'Refund To Credit');
      await CustomerRepository().insert(customer);
      final sale = await ringSale({'cash': 500}, 500);
      final items = await SaleRepository().getItemsBySale(sale.id);

      final ret = await SalesReturnRepository().insertReturn(
        header: SalesReturn.create(
          saleId: sale.id,
          customerId: customer.id,
          storeId: 'store_default',
          userId: 'settlement-cashier',
          reason: 'Adjust against khata',
          refundMethod: 'credit_adjust',
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

      expect(await netDebitFor(cashAccountId, GLService.returnReferenceType, ret.id), 0);
      expect(await netDebitFor(bankAccountId, GLService.returnReferenceType, ret.id), 0);
      expect(await netDebitFor(receivableAccountId, GLService.returnReferenceType, ret.id), -100);
    });
  });

  group('G1/G2 — GL Cash reconciles with the cash book', () {
    test('across a mixed shift, GL Cash movement equals the cash movement ledger', () async {
      final db = await DatabaseHelper.instance.database;
      final sessionId = 'session-recon-${DateTime.now().microsecondsSinceEpoch}';
      await db.insert('sessions', {
        'id': sessionId,
        'user_id': 'settlement-cashier',
        'opening_time': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'opening_cash': 1000,
        'status': 'open',
        'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      });

      final cashBefore = await netDebit(cashAccountId);

      // Cash sale ₹400, UPI sale ₹600, cash refund ₹100, UPI refund ₹50.
      final p1 = await seedProduct();
      await SaleRepository().insertSaleWithItems(
        sale: Sale.create(
          storeId: 'store_default',
          sessionId: sessionId,
          userId: 'settlement-cashier',
          netAmount: 400,
          paymentMethods: const {'cash': 400},
        ),
        items: [SaleItem.create(productId: p1.id, quantity: 4, unitPrice: 100, totalPrice: 400, costPrice: 40)],
        storeId: 'store_default',
      );

      final p2 = await seedProduct();
      await SaleRepository().insertSaleWithItems(
        sale: Sale.create(
          storeId: 'store_default',
          sessionId: sessionId,
          userId: 'settlement-cashier',
          netAmount: 600,
          paymentMethods: const {'upi': 600},
        ),
        items: [SaleItem.create(productId: p2.id, quantity: 6, unitPrice: 100, totalPrice: 600, costPrice: 40)],
        storeId: 'store_default',
      );

      for (final refund in [
        ('cash', 100.0),
        ('upi', 50.0),
      ]) {
        final p = await seedProduct();
        await SalesReturnRepository().insertReturn(
          header: SalesReturn.create(
            storeId: 'store_default',
            sessionId: sessionId,
            userId: 'settlement-cashier',
            approvedByUserId: 'settlement-manager',
            reason: 'Refund ${refund.$1}',
            refundMethod: refund.$1,
            refundAmount: refund.$2,
            isUntied: true,
          ),
          items: [
            SalesReturnItem.create(
              productId: p.id,
              quantity: 1,
              unitPrice: refund.$2,
              totalPrice: refund.$2,
              costPrice: 40,
              restocked: false,
            ),
          ],
        );
      }

      final glCashMovement = await netDebit(cashAccountId) - cashBefore;
      final cashBookNet = await CashMovementRepository().getSessionNet(sessionId);

      // The invariant this whole change exists to establish: the GL's idea of
      // the drawer and the cash book's idea of the drawer are the same number.
      expect(glCashMovement, closeTo(cashBookNet, 0.01));
      expect(cashBookNet, 300); // +400 cash sale − 100 cash refund
    });
  });

  group('G4 — a credit-adjusted exchange moves the receivable, not cash', () {
    test('the asset side lands in Accounts Receivable and Cash is untouched', () async {
      final customer = Customer.create(phone: _nextPhone(), name: 'Exchange Credit Customer');
      await CustomerRepository().insert(customer);

      final original = await seedProduct();
      final originalSale = await SaleRepository().insertSaleWithItems(
        sale: Sale.create(
          storeId: 'store_default',
          customerId: customer.id,
          userId: 'settlement-cashier',
          netAmount: 200,
          paymentMethods: const {'cash': 200},
        ),
        items: [SaleItem.create(productId: original.id, quantity: 2, unitPrice: 100, totalPrice: 200, costPrice: 40)],
        storeId: 'store_default',
        customerId: customer.id,
      );
      final originalItems = await SaleRepository().getItemsBySale(originalSale.id);

      final cashBefore = await netDebit(cashAccountId);
      final bankBefore = await netDebit(bankAccountId);
      final receivableBefore = await netDebit(receivableAccountId);
      final revenueBefore = await netDebit(revenueAccountId);
      final balanceBefore = (await CustomerRepository().getById(customer.id))!.outstandingBalance;

      final replacement = await seedProduct();
      await ExchangeRepository().processExchange(
        returnHeader: SalesReturn.create(
          saleId: originalSale.id,
          customerId: customer.id,
          storeId: 'store_default',
          userId: 'settlement-cashier',
          reason: 'Swap for a dearer item',
          refundMethod: 'credit_adjust',
          refundAmount: 200,
        ),
        returnItems: [
          SalesReturnItem.create(
            saleItemId: originalItems.first.id,
            productId: originalItems.first.productId,
            quantity: 2,
            unitPrice: 100,
            totalPrice: 200,
            costPrice: 40,
          ),
        ],
        newSale: Sale.create(
          storeId: 'store_default',
          customerId: customer.id,
          userId: 'settlement-cashier',
          netAmount: 300,
        ),
        newSaleItems: [
          SaleItem.create(productId: replacement.id, quantity: 3, unitPrice: 100, totalPrice: 300, costPrice: 40),
        ],
        settlementMethod: 'credit_adjust',
        userId: 'settlement-cashier',
        approvedByUserId: 'settlement-manager',
        storeId: 'store_default',
      );

      // Nothing was settled — the customer simply owes ₹100 more.
      expect(await netDebit(cashAccountId) - cashBefore, closeTo(0, 0.01));
      expect(await netDebit(bankAccountId) - bankBefore, closeTo(0, 0.01));
      expect(await netDebit(receivableAccountId) - receivableBefore, closeTo(100, 0.01));
      expect(await netDebit(revenueAccountId) - revenueBefore, closeTo(-100, 0.01));

      // And the GL agrees with the customer ledger about the same ₹100.
      final balanceAfter = (await CustomerRepository().getById(customer.id))!.outstandingBalance;
      expect(balanceAfter - balanceBefore, closeTo(100, 0.01));
    });

    test('a cash-settled exchange still nets to the price difference in Cash', () async {
      final customer = Customer.create(phone: _nextPhone(), name: 'Exchange Cash Customer');
      await CustomerRepository().insert(customer);

      final original = await seedProduct();
      final originalSale = await SaleRepository().insertSaleWithItems(
        sale: Sale.create(
          storeId: 'store_default',
          customerId: customer.id,
          userId: 'settlement-cashier',
          netAmount: 200,
          paymentMethods: const {'cash': 200},
        ),
        items: [SaleItem.create(productId: original.id, quantity: 2, unitPrice: 100, totalPrice: 200, costPrice: 40)],
        storeId: 'store_default',
        customerId: customer.id,
      );
      final originalItems = await SaleRepository().getItemsBySale(originalSale.id);

      final cashBefore = await netDebit(cashAccountId);
      final replacement = await seedProduct();

      await ExchangeRepository().processExchange(
        returnHeader: SalesReturn.create(
          saleId: originalSale.id,
          customerId: customer.id,
          storeId: 'store_default',
          userId: 'settlement-cashier',
          reason: 'Swap, paying the difference',
          refundMethod: 'cash',
          refundAmount: 200,
        ),
        returnItems: [
          SalesReturnItem.create(
            saleItemId: originalItems.first.id,
            productId: originalItems.first.productId,
            quantity: 2,
            unitPrice: 100,
            totalPrice: 200,
            costPrice: 40,
          ),
        ],
        newSale: Sale.create(
          storeId: 'store_default',
          customerId: customer.id,
          userId: 'settlement-cashier',
          netAmount: 300,
          paymentMethods: const {'cash': 300},
        ),
        newSaleItems: [
          SaleItem.create(productId: replacement.id, quantity: 3, unitPrice: 100, totalPrice: 300, costPrice: 40),
        ],
        settlementMethod: 'cash',
        userId: 'settlement-cashier',
        approvedByUserId: 'settlement-manager',
        storeId: 'store_default',
      );

      // ₹100 of notes crossed the counter, and that is what GL Cash shows.
      expect(await netDebit(cashAccountId) - cashBefore, closeTo(100, 0.01));
    });
  });
}
