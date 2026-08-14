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
import 'package:supermart_pos/repositories/customer_repository.dart';
import 'package:supermart_pos/repositories/product_repository.dart';
import 'package:supermart_pos/repositories/sale_repository.dart';
import 'package:supermart_pos/repositories/exchange_repository.dart';

/// Same path_provider-faking harness as `financial_year_close_service_test.dart`
/// / `sale_cancellation_repository_test.dart` — a real sqflite (ffi) database
/// under a throwaway temp directory.
class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this._path);
  final String _path;

  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
}

int _phoneCounter = 0;
/// A fresh-looking 10-digit phone per call — `DateTime.now()`'s leading
/// digits barely change between calls a few milliseconds apart, so a plain
/// timestamp substring collides under `customers.phone`'s UNIQUE constraint.
String _nextPhone() => (8000000000 + (_phoneCounter++)).toString();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late ExchangeRepository repo;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('exchange_test');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);

    final db = await DatabaseHelper.instance.database;
    await db.insert('users', {
      'id': 'test-user-1',
      'username': 'test_admin',
      'password_hash': 'x',
      'role': 'admin',
      'name': 'Test Admin',
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

  setUp(() {
    repo = ExchangeRepository();
  });

  /// A customer with an original ₹100 (2 x ₹50) sale of `oldProduct`, plus a
  /// `newProduct` priced at ₹60 to exchange into.
  Future<(Customer, Product, Product, Sale, List<SaleItem>)> seedOriginalSale() async {
    final oldProduct = Product.create(
      barcode: 'OLD-${DateTime.now().microsecondsSinceEpoch}',
      name: 'Old Product',
      costPrice: 20,
      retailPrice: 50,
      stockQuantity: 10,
    );
    await ProductRepository().insert(oldProduct);

    final newProduct = Product.create(
      barcode: 'NEW-${DateTime.now().microsecondsSinceEpoch}',
      name: 'New Product',
      costPrice: 25,
      retailPrice: 60,
      stockQuantity: 10,
    );
    await ProductRepository().insert(newProduct);

    final customer = Customer.create(
      phone: _nextPhone(),
      name: 'Exchange Customer',
    );
    await CustomerRepository().insert(customer);

    final item = SaleItem.create(productId: oldProduct.id, quantity: 2, unitPrice: 50, totalPrice: 100, costPrice: 20);
    final sale = Sale.create(customerId: customer.id, netAmount: 100);

    final savedSale = await SaleRepository().insertSaleWithItems(
      sale: sale,
      items: [item],
      storeId: 'store_default',
      customerId: customer.id,
    );

    return (customer, oldProduct, newProduct, savedSale, [item]);
  }

  group('ExchangeRepository', () {
    test('processExchange atomically returns old items, sells new items, and settles the price difference', () async {
      final (customer, oldProduct, newProduct, savedSale, _) = await seedOriginalSale();

      // Return 1 unit of the old product (₹50 refund), buy 1 unit of the new
      // product (₹60) — customer owes ₹10 more, settled against credit.
      final returnHeader = SalesReturn.create(
        saleId: savedSale.id,
        customerId: customer.id,
        storeId: 'store_default',
        userId: 'test-user-1',
        reason: 'Wrong size',
        refundMethod: 'credit_adjust',
        refundAmount: 50,
      );
      final returnItems = [
        SalesReturnItem.create(productId: oldProduct.id, quantity: 1, unitPrice: 50, totalPrice: 50, costPrice: 20),
      ];
      final newSale = Sale.create(customerId: customer.id, netAmount: 60);
      final newSaleItems = [
        SaleItem.create(productId: newProduct.id, quantity: 1, unitPrice: 60, totalPrice: 60, costPrice: 25),
      ];

      final exchange = await repo.processExchange(
        returnHeader: returnHeader,
        returnItems: returnItems,
        newSale: newSale,
        newSaleItems: newSaleItems,
        settlementMethod: 'credit_adjust',
        userId: 'test-user-1',
        storeId: 'store_default',
      );

      expect(exchange.priceDifference, 10); // 60 - 50
      expect(exchange.newSaleId, isNotNull);

      final afterOldProduct = await ProductRepository().getById(oldProduct.id);
      expect(afterOldProduct!.stockQuantity, 9); // 10 - 2 (original sale) + 1 (returned)

      final afterNewProduct = await ProductRepository().getById(newProduct.id);
      expect(afterNewProduct!.stockQuantity, 9); // 10 - 1 (new sale)

      final afterCustomer = await CustomerRepository().getById(customer.id);
      expect(afterCustomer!.outstandingBalance, 10); // net owes ₹10 more, settled on credit

      final db = await DatabaseHelper.instance.database;
      final exchangeRows = await db.query('exchanges', where: 'id = ?', whereArgs: [exchange.id]);
      expect(exchangeRows, hasLength(1));
      expect(exchangeRows.first['return_id'], isNotNull);
      expect(exchangeRows.first['new_sale_id'], exchange.newSaleId);

      final returnRows = await db.query('sales_returns', where: 'sale_id = ?', whereArgs: [savedSale.id]);
      expect(returnRows, hasLength(1)); // the return half was written atomically
    });

    test('a refund-due exchange (new items cheaper than returned items) computes a negative price difference', () async {
      final (customer, oldProduct, newProduct, savedSale, _) = await seedOriginalSale();

      final returnHeader = SalesReturn.create(
        saleId: savedSale.id,
        customerId: customer.id,
        storeId: 'store_default',
        userId: 'test-user-1',
        reason: 'Downgrade',
        refundMethod: 'cash',
        refundAmount: 100,
      );
      final returnItems = [
        SalesReturnItem.create(productId: oldProduct.id, quantity: 2, unitPrice: 50, totalPrice: 100, costPrice: 20),
      ];
      final newSale = Sale.create(customerId: customer.id, netAmount: 60);
      final newSaleItems = [
        SaleItem.create(productId: newProduct.id, quantity: 1, unitPrice: 60, totalPrice: 60, costPrice: 25),
      ];

      final exchange = await repo.processExchange(
        returnHeader: returnHeader,
        returnItems: returnItems,
        newSale: newSale,
        newSaleItems: newSaleItems,
        settlementMethod: 'cash',
        userId: 'test-user-1',
        storeId: 'store_default',
      );

      expect(exchange.priceDifference, -40); // 60 - 100: refund of ₹40 due

      // Cash settlement doesn't touch the customer's ledger/balance.
      final afterCustomer = await CustomerRepository().getById(customer.id);
      expect(afterCustomer!.outstandingBalance, 0);
    });
  });
}
