import 'dart:convert';
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
import 'package:supermart_pos/services/approval_service.dart';

/// AD-P3-3 — Exchange approval enforcement at the repository level.
///
/// Defect D5: ExchangeRepository.processExchange accepts any
/// approvedByUserId without validation. A cashier can process an exchange
/// of any value with no approver.
///
/// Rule: exchanges always require manager/admin (authoriseAlways).
/// The screen already enforces this; the repository must too.
class _FakePathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this._path);
  final String _path;

  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
}

int _phoneCounter = 0;
String _nextPhone() => (8500000000 + (_phoneCounter++)).toString();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late ExchangeRepository repo;
  late Product oldProduct;
  late Product newProduct;

  Future<void> seedUser(String id, String role, {bool active = true}) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert('users', {
      'id': id,
      'username': 'user_$id',
      'password_hash': 'x',
      'role': role,
      'name': 'User $id',
      'must_change_password': 0,
      'is_active': active ? 1 : 0,
      'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    });
  }

  Future<(Customer, Sale)> seedOriginalSale() async {
    final customer = Customer.create(phone: _nextPhone(), name: 'Exchange Customer');
    await CustomerRepository().insert(customer);

    final item = SaleItem.create(
      productId: oldProduct.id,
      quantity: 2,
      unitPrice: 50,
      totalPrice: 100,
      costPrice: 20,
    );
    final sale = Sale.create(customerId: customer.id, netAmount: 100);
    final savedSale = await SaleRepository().insertSaleWithItems(
      sale: sale,
      items: [item],
      storeId: 'store_default',
      customerId: customer.id,
    );
    return (customer, savedSale);
  }

  ({SalesReturn returnHeader, List<SalesReturnItem> returnItems,
    Sale newSale, List<SaleItem> newSaleItems}) makeExchangeArgs({
    required String saleId,
    required String? customerId,
    String? approvedByUserId,
  }) {
    final returnHeader = SalesReturn.create(
      saleId: saleId,
      customerId: customerId,
      storeId: 'store_default',
      userId: 'cashier-1',
      approvedByUserId: approvedByUserId,
      reason: 'Wrong size',
      refundMethod: 'credit_adjust',
      refundAmount: 50,
    );
    final returnItems = [
      SalesReturnItem.create(
        productId: oldProduct.id,
        quantity: 1,
        unitPrice: 50,
        totalPrice: 50,
        costPrice: 20,
      ),
    ];
    final newSale = Sale.create(customerId: customerId, netAmount: 60);
    final newSaleItems = [
      SaleItem.create(
        productId: newProduct.id,
        quantity: 1,
        unitPrice: 60,
        totalPrice: 60,
        costPrice: 25,
      ),
    ];
    return (
      returnHeader: returnHeader,
      returnItems: returnItems,
      newSale: newSale,
      newSaleItems: newSaleItems,
    );
  }

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('exchange_approval_test');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
    await DatabaseHelper.instance.database;

    repo = ExchangeRepository();

    await seedUser('cashier-1', 'cashier');
    await seedUser('cashier-2', 'cashier');
    await seedUser('manager-1', 'manager');
    await seedUser('admin-1', 'admin');
    await seedUser('manager-retired', 'manager', active: false);

    oldProduct = Product.create(
      barcode: 'EXCH-OLD-001',
      name: 'Old Exchange Widget',
      costPrice: 20,
      retailPrice: 50,
      stockQuantity: 1000,
    );
    await ProductRepository().insert(oldProduct);

    newProduct = Product.create(
      barcode: 'EXCH-NEW-001',
      name: 'New Exchange Widget',
      costPrice: 25,
      retailPrice: 60,
      stockQuantity: 1000,
    );
    await ProductRepository().insert(newProduct);
  });

  tearDownAll(() async {
    await DatabaseHelper.instance.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('AD-P3-3.01 — exchange with valid manager', () {
    test('succeeds', () async {
      final (customer, sale) = await seedOriginalSale();
      final args = makeExchangeArgs(
        saleId: sale.id,
        customerId: customer.id,
        approvedByUserId: 'manager-1',
      );
      final exchange = await repo.processExchange(
        returnHeader: args.returnHeader,
        returnItems: args.returnItems,
        newSale: args.newSale,
        newSaleItems: args.newSaleItems,
        settlementMethod: 'credit_adjust',
        userId: 'cashier-1',
        approvedByUserId: 'manager-1',
        storeId: 'store_default',
      );
      expect(exchange.newSaleId, isNotNull);
    });
  });

  group('AD-P3-3.02 — exchange without approver', () {
    test('throws ApprovalRequired', () async {
      final (customer, sale) = await seedOriginalSale();
      final args = makeExchangeArgs(
        saleId: sale.id,
        customerId: customer.id,
      );
      await expectLater(
        repo.processExchange(
          returnHeader: args.returnHeader,
          returnItems: args.returnItems,
          newSale: args.newSale,
          newSaleItems: args.newSaleItems,
          settlementMethod: 'credit_adjust',
          userId: 'cashier-1',
          storeId: 'store_default',
        ),
        throwsA(isA<ApprovalRequired>()),
      );

      final db = await DatabaseHelper.instance.database;
      final rows = await db.query('exchanges');
      final matching = rows.where((r) => r['return_id'] == args.returnHeader.id);
      expect(matching, isEmpty, reason: 'a refused exchange must leave nothing behind');
    });
  });

  group('AD-P3-3.03 — exchange with cashier approver', () {
    test('throws UnauthorizedApprover', () async {
      final (customer, sale) = await seedOriginalSale();
      final args = makeExchangeArgs(
        saleId: sale.id,
        customerId: customer.id,
        approvedByUserId: 'cashier-2',
      );
      await expectLater(
        repo.processExchange(
          returnHeader: args.returnHeader,
          returnItems: args.returnItems,
          newSale: args.newSale,
          newSaleItems: args.newSaleItems,
          settlementMethod: 'credit_adjust',
          userId: 'cashier-1',
          approvedByUserId: 'cashier-2',
          storeId: 'store_default',
        ),
        throwsA(isA<UnauthorizedApprover>()),
      );
    });
  });

  group('AD-P3-3.04 — exchange with non-existent approver', () {
    test('throws UnauthorizedApprover', () async {
      final (customer, sale) = await seedOriginalSale();
      final args = makeExchangeArgs(
        saleId: sale.id,
        customerId: customer.id,
        approvedByUserId: 'ghost-manager',
      );
      await expectLater(
        repo.processExchange(
          returnHeader: args.returnHeader,
          returnItems: args.returnItems,
          newSale: args.newSale,
          newSaleItems: args.newSaleItems,
          settlementMethod: 'credit_adjust',
          userId: 'cashier-1',
          approvedByUserId: 'ghost-manager',
          storeId: 'store_default',
        ),
        throwsA(isA<UnauthorizedApprover>()),
      );
    });
  });

  group('AD-P3-3.05 — exchange with admin approver', () {
    test('succeeds', () async {
      final (customer, sale) = await seedOriginalSale();
      final args = makeExchangeArgs(
        saleId: sale.id,
        customerId: customer.id,
        approvedByUserId: 'admin-1',
      );
      final exchange = await repo.processExchange(
        returnHeader: args.returnHeader,
        returnItems: args.returnItems,
        newSale: args.newSale,
        newSaleItems: args.newSaleItems,
        settlementMethod: 'credit_adjust',
        userId: 'cashier-1',
        approvedByUserId: 'admin-1',
        storeId: 'store_default',
      );
      expect(exchange.newSaleId, isNotNull);
    });
  });

  group('AD-P3-3.06 — exchange with deactivated manager', () {
    test('throws UnauthorizedApprover', () async {
      final (customer, sale) = await seedOriginalSale();
      final args = makeExchangeArgs(
        saleId: sale.id,
        customerId: customer.id,
        approvedByUserId: 'manager-retired',
      );
      await expectLater(
        repo.processExchange(
          returnHeader: args.returnHeader,
          returnItems: args.returnItems,
          newSale: args.newSale,
          newSaleItems: args.newSaleItems,
          settlementMethod: 'credit_adjust',
          userId: 'cashier-1',
          approvedByUserId: 'manager-retired',
          storeId: 'store_default',
        ),
        throwsA(isA<UnauthorizedApprover>()),
      );
    });
  });

  group('D6 — exchange audit contains financial detail', () {
    test('EXCHANGE_PROCESSED audit row has newValue with correct JSON', () async {
      final (customer, sale) = await seedOriginalSale();
      final args = makeExchangeArgs(
        saleId: sale.id,
        customerId: customer.id,
        approvedByUserId: 'manager-1',
      );
      final exchange = await repo.processExchange(
        returnHeader: args.returnHeader,
        returnItems: args.returnItems,
        newSale: args.newSale,
        newSaleItems: args.newSaleItems,
        settlementMethod: 'credit_adjust',
        userId: 'cashier-1',
        approvedByUserId: 'manager-1',
        storeId: 'store_default',
      );

      final db = await DatabaseHelper.instance.database;
      final auditRows = await db.query(
        'audit_log',
        where: "action_type = 'EXCHANGE_PROCESSED' AND record_id = ?",
        whereArgs: [exchange.id],
      );
      expect(auditRows, hasLength(1));
      expect(auditRows.first['table_name'], 'exchanges');

      final rawValue = auditRows.first['new_value'] as String?;
      expect(rawValue, isNotNull, reason: 'newValue must not be null');
      expect(rawValue, isNotEmpty, reason: 'newValue must not be empty');

      final detail = jsonDecode(rawValue!) as Map<String, dynamic>;

      expect(detail['exchangeId'], exchange.id);
      expect(detail['saleId'], sale.id);
      expect(detail['returnAmount'], 50);
      expect(detail['replacementAmount'], 60);
      expect(detail['priceDifference'], 10);
      expect(detail['settlementMethod'], 'credit_adjust');
      expect(detail['approvedByUserId'], 'manager-1');
      expect(detail['returnItemCount'], 1);
      expect(detail['replacementItemCount'], 1);
    });

    test('a refused exchange leaves no audit row', () async {
      final (customer, sale) = await seedOriginalSale();
      final args = makeExchangeArgs(
        saleId: sale.id,
        customerId: customer.id,
      );
      await expectLater(
        repo.processExchange(
          returnHeader: args.returnHeader,
          returnItems: args.returnItems,
          newSale: args.newSale,
          newSaleItems: args.newSaleItems,
          settlementMethod: 'credit_adjust',
          userId: 'cashier-1',
          storeId: 'store_default',
        ),
        throwsA(isA<ApprovalRequired>()),
      );

      final db = await DatabaseHelper.instance.database;
      final auditRows = await db.query(
        'audit_log',
        where: "action_type = 'EXCHANGE_PROCESSED' AND record_id = ?",
        whereArgs: [args.returnHeader.id],
      );
      expect(auditRows, isEmpty,
          reason: 'a rolled-back exchange must not leave an audit trail');
    });
  });
}
