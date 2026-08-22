import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:supermart_pos/core/database/database_helper.dart';
import 'package:supermart_pos/core/utils/financial_year.dart';
import 'package:supermart_pos/models/customer_model.dart';
import 'package:supermart_pos/models/product_model.dart';
import 'package:supermart_pos/models/sale_model.dart';
import 'package:supermart_pos/models/sale_item_model.dart';
import 'package:supermart_pos/repositories/cash_movement_repository.dart';
import 'package:supermart_pos/repositories/customer_repository.dart';
import 'package:supermart_pos/repositories/product_repository.dart';
import 'package:supermart_pos/repositories/sale_repository.dart';
import 'package:supermart_pos/repositories/sale_cancellation_repository.dart';
import 'package:supermart_pos/services/financial_year_close_service.dart';
import 'package:supermart_pos/services/gl_service.dart';

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
        approvedByUserId: 'test-user-1',
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
        approvedByUserId: 'test-user-1',
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
        approvedByUserId: 'test-user-1',
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

  group('C3 — the reversal itself', () {
    test('C3-02 every reversal carries the original sale\'s reference and points at the line it undoes', () async {
      final (_, _, savedSale, savedItems) = await seedCreditSale();
      final db = await DatabaseHelper.instance.database;

      final originals = await db.query(
        'gl_entries',
        where: 'reference_type = ? AND reference_id = ?',
        whereArgs: ['Sale', savedSale.id],
      );
      final originalIds = originals.map((e) => e['id'] as String).toSet();

      await repo.cancelSale(
        sale: savedSale,
        items: savedItems,
        reason: 'Reference check',
        refundMethod: 'credit_adjust',
        userId: 'test-user-1',
        approvedByUserId: 'test-user-1',
      );

      final reversals = (await db.query(
        'gl_entries',
        where: 'reference_type = ? AND reference_id = ? AND reversal_of_entry_id IS NOT NULL',
        whereArgs: ['Sale', savedSale.id],
      ))
          .toList();

      expect(reversals, hasLength(originalIds.length));
      for (final r in reversals) {
        // The reversal is filed under the sale it voids, not under a new
        // document — so a sale's whole GL history reads as one reference.
        expect(r['reference_type'], 'Sale');
        expect(r['reference_id'], savedSale.id);
        expect(originalIds, contains(r['reversal_of_entry_id']));
      }
      // Each original is reversed once, not several times.
      expect(reversals.map((r) => r['reversal_of_entry_id']).toSet(), originalIds);
    });

    test('C3-03 each reversal is the exact mirror of its original: same amount, opposite side', () async {
      final (_, _, savedSale, savedItems) = await seedCreditSale();
      final db = await DatabaseHelper.instance.database;

      final originals = await db.query(
        'gl_entries',
        where: 'reference_type = ? AND reference_id = ?',
        whereArgs: ['Sale', savedSale.id],
      );
      final byId = {for (final e in originals) e['id'] as String: e};

      await repo.cancelSale(
        sale: savedSale,
        items: savedItems,
        reason: 'Amount check',
        refundMethod: 'credit_adjust',
        userId: 'test-user-1',
        approvedByUserId: 'test-user-1',
      );

      final reversals = await db.query(
        'gl_entries',
        where: 'reference_type = ? AND reference_id = ? AND reversal_of_entry_id IS NOT NULL',
        whereArgs: ['Sale', savedSale.id],
      );

      expect(reversals, isNotEmpty);
      for (final r in reversals) {
        final original = byId[r['reversal_of_entry_id'] as String]!;
        expect(r['account_id'], original['account_id']);
        // A debit of X comes back as a credit of X on the same account.
        expect((r['debit'] as num).toDouble(), (original['credit'] as num).toDouble());
        expect((r['credit'] as num).toDouble(), (original['debit'] as num).toDouble());
        expect(r['financial_year'], original['financial_year'],
            reason: 'the reversal must land in the year it corrects');
      }
    });

    test('C3-04/C3-05 reversing the same sale again adds nothing', () async {
      final (_, _, savedSale, savedItems) = await seedCreditSale();
      final db = await DatabaseHelper.instance.database;

      await repo.cancelSale(
        sale: savedSale,
        items: savedItems,
        reason: 'First void',
        refundMethod: 'credit_adjust',
        userId: 'test-user-1',
        approvedByUserId: 'test-user-1',
      );

      final afterFirst = await db.query(
        'gl_entries',
        where: 'reference_type = ? AND reference_id = ?',
        whereArgs: ['Sale', savedSale.id],
      );

      // `cancelSale` refuses a second run, so drive the GL layer directly —
      // this is the idempotency guarantee `reverseByReference` itself makes,
      // which is what protects a retry after a partial failure.
      final replay = await GLService().reverseByReference(
        GLService.saleReferenceType,
        savedSale.id,
        reason: 'Replayed void',
        createdBy: 'test-user-1',
      );
      expect(replay, isEmpty);

      final afterSecond = await db.query(
        'gl_entries',
        where: 'reference_type = ? AND reference_id = ?',
        whereArgs: ['Sale', savedSale.id],
      );
      expect(afterSecond.length, afterFirst.length);
    });

    test('C3-07 cancelling a cash sale reverses the GL and returns the cash', () async {
      final db = await DatabaseHelper.instance.database;
      final sessionId = 'session-cash-${DateTime.now().microsecondsSinceEpoch}';
      await db.insert('sessions', {
        'id': sessionId,
        'user_id': 'test-user-1',
        'opening_time': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'opening_cash': 1000,
        'status': 'open',
        'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      });

      final product = Product.create(
        barcode: 'BC-CASH-${DateTime.now().microsecondsSinceEpoch}',
        name: 'Cash Sale Product',
        costPrice: 20,
        retailPrice: 50,
        stockQuantity: 10,
      );
      await ProductRepository().insert(product);

      final savedSale = await SaleRepository().insertSaleWithItems(
        sale: Sale.create(
          storeId: 'store_default',
          sessionId: sessionId,
          userId: 'test-user-1',
          netAmount: 150,
          paymentMethods: const {'cash': 150},
        ),
        items: [
          SaleItem.create(productId: product.id, quantity: 3, unitPrice: 50, totalPrice: 150, costPrice: 20),
        ],
        storeId: 'store_default',
      );

      expect(await CashMovementRepository().getSessionNet(sessionId), 150);

      await repo.cancelSale(
        sale: savedSale,
        items: await SaleRepository().getItemsBySale(savedSale.id),
        reason: 'Cash void',
        refundMethod: 'cash',
        userId: 'test-user-1',
        approvedByUserId: 'test-user-1',
      );

      // Cash: back out of the drawer. GL: every line reversed. Stock: back on
      // the shelf. All three from the one transaction.
      expect(await CashMovementRepository().getSessionNet(sessionId), 0);
      expect((await ProductRepository().getById(product.id))!.stockQuantity, 10);

      final entries = await db.query(
        'gl_entries',
        where: 'reference_type = ? AND reference_id = ?',
        whereArgs: ['Sale', savedSale.id],
      );
      final net = <String, double>{};
      for (final e in entries) {
        final account = e['account_id'] as String;
        net[account] = (net[account] ?? 0) + (e['debit'] as num).toDouble() - (e['credit'] as num).toDouble();
      }
      expect(net, isNotEmpty);
      for (final entry in net.entries) {
        expect(entry.value, closeTo(0, 0.01));
      }
    });

    test('C3-08 cancelling a credit sale leaves ledger, GL and cash mutually consistent', () async {
      final (_, customer, savedSale, savedItems) = await seedCreditSale();
      final db = await DatabaseHelper.instance.database;

      expect((await CustomerRepository().getById(customer.id))!.outstandingBalance, 120);

      final cancellation = await repo.cancelSale(
        sale: savedSale,
        items: savedItems,
        reason: 'Credit void',
        refundMethod: 'credit_adjust',
        userId: 'test-user-1',
        approvedByUserId: 'test-user-1',
      );

      // Customer ledger: a compensating entry, not an edited one.
      final ledger = await db.query(
        'customer_ledger',
        where: 'customer_id = ?',
        whereArgs: [customer.id],
        orderBy: 'created_at ASC',
      );
      expect(ledger.map((r) => r['reference_type']), containsAll(['sale', 'sale_cancellation']));
      final reversalRow = ledger.firstWhere((r) => r['reference_type'] == 'sale_cancellation');
      expect((reversalRow['amount'] as num).toDouble(), -120);
      expect((reversalRow['balance'] as num).toDouble(), 0);
      expect(reversalRow['reference_id'], cancellation.id);

      expect((await CustomerRepository().getById(customer.id))!.outstandingBalance, 0);

      // GL receivable and the customer ledger now agree — the disagreement
      // between them was the whole point of C3.
      final entries = await db.query(
        'gl_entries',
        where: 'reference_type = ? AND reference_id = ?',
        whereArgs: ['Sale', savedSale.id],
      );
      final net = <String, double>{};
      for (final e in entries) {
        final account = e['account_id'] as String;
        net[account] = (net[account] ?? 0) + (e['debit'] as num).toDouble() - (e['credit'] as num).toDouble();
      }
      for (final entry in net.entries) {
        expect(entry.value, closeTo(0, 0.01));
      }

      // No cash moved in either direction: none was ever taken.
      final movements = await db.query(
        'cash_movements',
        where: 'source_id IN (?, ?)',
        whereArgs: [savedSale.id, cancellation.id],
      );
      expect(movements, isEmpty);
    });

    test('C3-09 a discounted, taxed bill reverses on what was actually billed', () async {
      final db = await DatabaseHelper.instance.database;
      final product = Product.create(
        barcode: 'BC-TAX-${DateTime.now().microsecondsSinceEpoch}',
        name: 'Taxed Product',
        costPrice: 100,
        retailPrice: 200,
        stockQuantity: 20,
      );
      await ProductRepository().insert(product);

      // ₹400 of goods, ₹50 off, ₹18 tax → ₹368 actually billed. The reversal
      // must follow netAmount, not the line total or the pre-discount value.
      final savedSale = await SaleRepository().insertSaleWithItems(
        sale: Sale.create(
          storeId: 'store_default',
          userId: 'test-user-1',
          subtotal: 400,
          discountTotal: 50,
          discountReason: 'Festival offer',
          taxTotal: 18,
          netAmount: 368,
          paymentMethods: const {'cash': 368},
        ),
        items: [
          SaleItem.create(productId: product.id, quantity: 2, unitPrice: 200, totalPrice: 400, costPrice: 100),
        ],
        storeId: 'store_default',
      );

      final originals = await db.query(
        'gl_entries',
        where: 'reference_type = ? AND reference_id = ?',
        whereArgs: ['Sale', savedSale.id],
      );
      final revenueLine = originals.firstWhere((e) => (e['credit'] as num).toDouble() > 0);
      expect((revenueLine['credit'] as num).toDouble(), closeTo(368, 0.01));

      await repo.cancelSale(
        sale: savedSale,
        items: await SaleRepository().getItemsBySale(savedSale.id),
        reason: 'Taxed void',
        refundMethod: 'cash',
        userId: 'test-user-1',
        approvedByUserId: 'test-user-1',
      );

      final reversals = await db.query(
        'gl_entries',
        where: 'reference_type = ? AND reference_id = ? AND reversal_of_entry_id IS NOT NULL',
        whereArgs: ['Sale', savedSale.id],
      );
      final revenueReversal =
          reversals.firstWhere((e) => e['reversal_of_entry_id'] == revenueLine['id']);
      expect((revenueReversal['debit'] as num).toDouble(), closeTo(368, 0.01));

      expect((await ProductRepository().getById(product.id))!.stockQuantity, 20);
    });
  });

  group('C3-06 — a cancellation that fails leaves nothing half-done', () {
    test('a GL post refused by a closed year rolls back stock, customer, cash and status', () async {
      final db = await DatabaseHelper.instance.database;
      final sessionId = 'session-fail-${DateTime.now().microsecondsSinceEpoch}';
      await db.insert('sessions', {
        'id': sessionId,
        'user_id': 'test-user-1',
        'opening_time': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'opening_cash': 500,
        'status': 'open',
        'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      });

      final product = Product.create(
        barcode: 'BC-FAIL-${DateTime.now().microsecondsSinceEpoch}',
        name: 'Rollback Product',
        costPrice: 20,
        retailPrice: 60,
        stockQuantity: 10,
      );
      await ProductRepository().insert(product);
      final customer = Customer.create(phone: _nextPhone(), name: 'Rollback Customer');
      await CustomerRepository().insert(customer);

      final savedSale = await SaleRepository().insertSaleWithItems(
        sale: Sale.create(
          storeId: 'store_default',
          customerId: customer.id,
          sessionId: sessionId,
          userId: 'test-user-1',
          netAmount: 180,
          paymentMethods: const {'cash': 180},
        ),
        items: [
          SaleItem.create(productId: product.id, quantity: 3, unitPrice: 60, totalPrice: 180, costPrice: 20),
        ],
        storeId: 'store_default',
        customerId: customer.id,
      );
      final savedItems = await SaleRepository().getItemsBySale(savedSale.id);

      final stockBefore = (await ProductRepository().getById(product.id))!.stockQuantity;
      final customerBefore = (await CustomerRepository().getById(customer.id))!;
      final cashBefore = await CashMovementRepository().getSessionNet(sessionId);
      final glBefore = await db.query(
        'gl_entries',
        where: 'reference_type = ? AND reference_id = ?',
        whereArgs: ['Sale', savedSale.id],
      );

      // Close the year the sale sits in. `GLService` refuses to post into a
      // closed period, so the reversal throws from inside the cancellation's
      // transaction — after stock, customer, status and audit have already
      // been written in it.
      final year = financialYearLabel(DateTime.now());
      await FinancialYearCloseService().closeFinancialYear(
        financialYear: year,
        userId: 'test-user-1',
      );
      addTearDown(() async {
        await db.delete('financial_year_closures', where: 'financial_year = ?', whereArgs: [year]);
      });

      await expectLater(
        repo.cancelSale(
          sale: savedSale,
          items: savedItems,
          reason: 'Should roll back',
          refundMethod: 'cash',
          userId: 'test-user-1',
        ),
        throwsA(isA<Exception>()),
      );

      // Nothing partial survived.
      expect((await ProductRepository().getById(product.id))!.stockQuantity, stockBefore);
      final customerAfter = (await CustomerRepository().getById(customer.id))!;
      expect(customerAfter.outstandingBalance, customerBefore.outstandingBalance);
      expect(customerAfter.totalSpent, customerBefore.totalSpent);
      expect(customerAfter.loyaltyPoints, customerBefore.loyaltyPoints);
      expect(await CashMovementRepository().getSessionNet(sessionId), cashBefore);

      final saleRow = await db.query('sales', where: 'id = ?', whereArgs: [savedSale.id]);
      expect(saleRow.first['status'], 'completed', reason: 'the sale was never actually cancelled');

      expect(
        await db.query('sale_cancellations', where: 'sale_id = ?', whereArgs: [savedSale.id]),
        isEmpty,
      );
      expect(
        await db.query(
          'audit_log',
          where: 'action_type = ? AND record_id = ?',
          whereArgs: ['SALE_CANCELLED', savedSale.id],
        ),
        isEmpty,
      );
      expect(
        (await db.query(
          'gl_entries',
          where: 'reference_type = ? AND reference_id = ?',
          whereArgs: ['Sale', savedSale.id],
        ))
            .length,
        glBefore.length,
      );
    });
  });
}
