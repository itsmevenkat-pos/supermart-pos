import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:supermart_pos/core/database/database_helper.dart';
import 'package:supermart_pos/models/customer_model.dart';
import 'package:supermart_pos/models/product_model.dart';
import 'package:supermart_pos/models/sale_model.dart';
import 'package:supermart_pos/models/sale_item_model.dart';
import 'package:supermart_pos/repositories/customer_repository.dart';
import 'package:supermart_pos/repositories/product_repository.dart';
import 'package:supermart_pos/repositories/sale_repository.dart';
import 'package:supermart_pos/repositories/sale_cancellation_repository.dart';

/// Points path_provider at a throwaway temp directory so
/// `DatabaseHelper.instance.database` opens a real sqflite (ffi) database
/// under `flutter_test` — same harness as `financial_year_close_service_test.dart`.
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
String _nextPhone() => (9000000000 + (_phoneCounter++)).toString();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late SaleCancellationRepository repo;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('sale_cancel_test');
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
    repo = SaleCancellationRepository();
  });

  /// Creates a product with 10 units in stock, a customer, and a credit
  /// sale of 3 units against that product/customer — via the real
  /// ProductRepository/CustomerRepository/SaleRepository, so preconditions
  /// exercise the exact code path SaleCancellationRepository must reverse.
  Future<(Product, Customer, Sale, List<SaleItem>)> seedCreditSale() async {
    final product = Product.create(
      barcode: 'BC-${DateTime.now().microsecondsSinceEpoch}',
      name: 'Test Product',
      costPrice: 20,
      retailPrice: 40,
      stockQuantity: 10,
    );
    await ProductRepository().insert(product);

    final customer = Customer.create(phone: _nextPhone(), name: 'Test Customer');
    await CustomerRepository().insert(customer);

    final item = SaleItem.create(
      productId: product.id,
      quantity: 3,
      unitPrice: 40,
      totalPrice: 120,
      costPrice: 20,
    );
    final sale = Sale.create(
      storeId: 'store_default',
      customerId: customer.id,
      netAmount: 120,
      creditUsed: 120,
      isCreditSale: true,
    );

    final savedSale = await SaleRepository().insertSaleWithItems(
      sale: sale,
      items: [item],
      storeId: 'store_default',
      customerId: customer.id,
    );
    final savedItems = await SaleRepository().getItemsBySale(savedSale.id);

    return (product, customer, savedSale, savedItems);
  }

  group('SaleCancellationRepository', () {
    test('cancelSale reverses stock, customer balance and loyalty points, and marks the sale cancelled', () async {
      final (product, customer, savedSale, savedItems) = await seedCreditSale();

      final db = await DatabaseHelper.instance.database;
      final beforeCancelProduct = await ProductRepository().getById(product.id);
      expect(beforeCancelProduct!.stockQuantity, 7); // 10 - 3

      final beforeCancelCustomer = await CustomerRepository().getById(customer.id);
      expect(beforeCancelCustomer!.outstandingBalance, greaterThan(0)); // credit sale added a balance

      final cancellation = await repo.cancelSale(
        sale: savedSale,
        items: savedItems,
        reason: 'Customer changed their mind',
        refundMethod: 'cash',
        userId: 'test-user-1',
      );

      expect(cancellation.saleId, savedSale.id);
      expect(cancellation.refundAmount, savedSale.netAmount);

      final afterProduct = await ProductRepository().getById(product.id);
      expect(afterProduct!.stockQuantity, 10); // fully restocked

      final afterCustomer = await CustomerRepository().getById(customer.id);
      expect(afterCustomer!.outstandingBalance, 0); // credit fully reversed
      expect(afterCustomer.totalSpent, 0);
      expect(afterCustomer.loyaltyPoints, 0);

      final saleRows = await db.query('sales', where: 'id = ?', whereArgs: [savedSale.id]);
      expect(saleRows.first['status'], 'cancelled');
    });

    test('cancelSale reverses the sale\'s GL entries, leaving every touched account net zero', () async {
      final (_, _, savedSale, savedItems) = await seedCreditSale();
      final db = await DatabaseHelper.instance.database;

      // The sale posted real entries — without this the test could pass by
      // reversing nothing at all.
      final beforeEntries = await db.query(
        'gl_entries',
        where: 'reference_type = ? AND reference_id = ?',
        whereArgs: ['Sale', savedSale.id],
      );
      expect(beforeEntries, isNotEmpty, reason: 'the sale should have posted GL entries to reverse');
      final originalCount = beforeEntries.length;

      await repo.cancelSale(
        sale: savedSale,
        items: savedItems,
        reason: 'Customer changed their mind',
        refundMethod: 'cash',
        userId: 'test-user-1',
      );

      final afterEntries = await db.query(
        'gl_entries',
        where: 'reference_type = ? AND reference_id = ?',
        whereArgs: ['Sale', savedSale.id],
      );
      // One reversal per original line, each pointing back at what it reverses.
      expect(afterEntries.length, originalCount * 2);
      expect(
        afterEntries.where((e) => e['reversal_of_entry_id'] != null).length,
        originalCount,
      );

      // The real invariant: revenue and receivable are back to zero, so a
      // period containing this cancellation no longer reads high.
      final netByAccount = <String, double>{};
      for (final e in afterEntries) {
        final account = e['account_id'] as String;
        final net = (e['debit'] as num).toDouble() - (e['credit'] as num).toDouble();
        netByAccount[account] = (netByAccount[account] ?? 0) + net;
      }
      expect(netByAccount, isNotEmpty);
      for (final entry in netByAccount.entries) {
        expect(entry.value, closeTo(0, 0.01), reason: 'account ${entry.key} should net to zero after a full void');
      }
    });

    test('cancelling an already-cancelled sale throws', () async {
      final (_, _, savedSale, savedItems) = await seedCreditSale();

      await repo.cancelSale(
        sale: savedSale,
        items: savedItems,
        reason: 'First cancel',
        refundMethod: 'cash',
        userId: 'test-user-1',
      );

      expect(
        () => repo.cancelSale(
          sale: savedSale,
          items: savedItems,
          reason: 'Second cancel attempt',
          refundMethod: 'cash',
          userId: 'test-user-1',
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('cancelling a sale that has already been returned against throws', () async {
      final (_, _, savedSale, savedItems) = await seedCreditSale();

      final db = await DatabaseHelper.instance.database;
      await db.insert('sales_returns', {
        'id': 'ret-${savedSale.id}',
        'sale_id': savedSale.id,
        'user_id': 'test-user-1',
        'reason': 'Partial return',
        'refund_method': 'cash',
        'refund_amount': 40,
        'is_untied': 0,
        'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      });

      expect(
        () => repo.cancelSale(
          sale: savedSale,
          items: savedItems,
          reason: 'Should be blocked',
          refundMethod: 'cash',
          userId: 'test-user-1',
        ),
        throwsA(isA<Exception>()),
      );
    });
  });
}
