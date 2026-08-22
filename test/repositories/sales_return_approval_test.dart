import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:supermart_pos/core/database/database_helper.dart';
import 'package:supermart_pos/models/product_model.dart';
import 'package:supermart_pos/models/sale_model.dart';
import 'package:supermart_pos/models/sale_item_model.dart';
import 'package:supermart_pos/models/sales_return_model.dart';
import 'package:supermart_pos/models/sales_return_item_model.dart';
import 'package:supermart_pos/repositories/product_repository.dart';
import 'package:supermart_pos/repositories/sale_repository.dart';
import 'package:supermart_pos/repositories/sales_return_repository.dart';
import 'package:supermart_pos/repositories/store_repository.dart';
import 'package:supermart_pos/services/approval_service.dart';

/// AD-P3-1 — Return approval enforcement at the repository level.
///
/// Defect D1: SalesReturnRepository.insertReturn accepts any approvedByUserId
/// without validation. A cashier can stamp a fabricated manager id on a return
/// of any size, or omit the approver entirely on a high-value return, and the
/// repository writes it as-is.
///
/// Rules being enforced (matches the screen logic, now moved to the service):
///   - Tied return, amount <= threshold: no approval needed
///   - Tied return, amount > threshold: manager/admin approval required
///   - Untied return (no originating sale): always requires manager/admin
///   - Amount exactly equal to threshold does NOT require approval (> not >=)
///   - A supplied approver below threshold is still validated (bad ids rejected)
class _FakePathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this._path);
  final String _path;

  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late SalesReturnRepository returns;
  late Product product;

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

  Future<Sale> seedSale() async {
    final item = SaleItem.create(
      productId: product.id,
      quantity: 5,
      unitPrice: 100,
      totalPrice: 500,
      costPrice: 50,
    );
    final sale = Sale.create(netAmount: 500);
    return SaleRepository().insertSaleWithItems(
      sale: sale,
      items: [item],
      storeId: StoreRepository.defaultStoreId,
    );
  }

  SalesReturn makeHeader({
    String? saleId,
    double refundAmount = 100,
    String? approvedByUserId,
    bool isUntied = false,
  }) {
    return SalesReturn.create(
      saleId: saleId,
      storeId: StoreRepository.defaultStoreId,
      userId: 'cashier-1',
      approvedByUserId: approvedByUserId,
      reason: 'Defective item',
      refundMethod: 'cash',
      refundAmount: refundAmount,
      isUntied: isUntied,
    );
  }

  List<SalesReturnItem> makeItems() {
    return [
      SalesReturnItem.create(
        productId: product.id,
        quantity: 1,
        unitPrice: 100,
        totalPrice: 100,
        costPrice: 50,
      ),
    ];
  }

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('return_approval_test');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
    await DatabaseHelper.instance.database;

    returns = SalesReturnRepository();

    await seedUser('cashier-1', 'cashier');
    await seedUser('cashier-2', 'cashier');
    await seedUser('manager-1', 'manager');
    await seedUser('admin-1', 'admin');
    await seedUser('manager-retired', 'manager', active: false);
    await seedUser('accountant-1', 'accountant');

    product = Product.create(
      barcode: 'RTN-TEST-001',
      name: 'Return Test Widget',
      costPrice: 50,
      retailPrice: 100,
      stockQuantity: 1000,
    );
    await ProductRepository().insert(product);

    final db = await DatabaseHelper.instance.database;
    await db.update(
      'stores',
      {'return_threshold_no_approval': 500.0},
      where: 'id = ?',
      whereArgs: [StoreRepository.defaultStoreId],
    );
  });

  tearDownAll(() async {
    await DatabaseHelper.instance.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('AD-P3-1.01 — tied return below threshold', () {
    test('succeeds without an approver', () async {
      final sale = await seedSale();
      final header = makeHeader(
        saleId: sale.id,
        refundAmount: 300,
      );
      final saved = await returns.insertReturn(
        header: header,
        items: makeItems(),
      );
      expect(saved.id, header.id);
    });
  });

  group('AD-P3-1.02 — tied return above threshold without approver', () {
    test('throws ApprovalRequired', () async {
      final sale = await seedSale();
      final header = makeHeader(
        saleId: sale.id,
        refundAmount: 800,
      );
      await expectLater(
        returns.insertReturn(header: header, items: makeItems()),
        throwsA(isA<ApprovalRequired>()),
      );

      final db = await DatabaseHelper.instance.database;
      final rows = await db.query(
        'sales_returns',
        where: 'id = ?',
        whereArgs: [header.id],
      );
      expect(rows, isEmpty, reason: 'a refused return must leave nothing behind');
    });
  });

  group('AD-P3-1.03 — tied return above threshold with valid manager', () {
    test('succeeds', () async {
      final sale = await seedSale();
      final header = makeHeader(
        saleId: sale.id,
        refundAmount: 800,
        approvedByUserId: 'manager-1',
      );
      final saved = await returns.insertReturn(
        header: header,
        items: makeItems(),
      );
      expect(saved.id, header.id);
    });
  });

  group('AD-P3-1.04 — tied return above threshold with cashier approver', () {
    test('throws UnauthorizedApprover', () async {
      final sale = await seedSale();
      final header = makeHeader(
        saleId: sale.id,
        refundAmount: 800,
        approvedByUserId: 'cashier-2',
      );
      await expectLater(
        returns.insertReturn(header: header, items: makeItems()),
        throwsA(isA<UnauthorizedApprover>()),
      );

      final db = await DatabaseHelper.instance.database;
      final rows = await db.query(
        'sales_returns',
        where: 'id = ?',
        whereArgs: [header.id],
      );
      expect(rows, isEmpty, reason: 'a refused return must leave nothing behind');
    });
  });

  group('AD-P3-1.05 — tied return above threshold with non-existent approver', () {
    test('throws UnauthorizedApprover', () async {
      final sale = await seedSale();
      final header = makeHeader(
        saleId: sale.id,
        refundAmount: 800,
        approvedByUserId: 'ghost-manager',
      );
      await expectLater(
        returns.insertReturn(header: header, items: makeItems()),
        throwsA(isA<UnauthorizedApprover>()),
      );
    });
  });

  group('AD-P3-1.06 — untied return without approver', () {
    test('throws ApprovalRequired regardless of amount', () async {
      final header = makeHeader(
        refundAmount: 100,
        isUntied: true,
      );
      await expectLater(
        returns.insertReturn(header: header, items: makeItems()),
        throwsA(isA<ApprovalRequired>()),
      );

      final db = await DatabaseHelper.instance.database;
      final rows = await db.query(
        'sales_returns',
        where: 'id = ?',
        whereArgs: [header.id],
      );
      expect(rows, isEmpty, reason: 'a refused return must leave nothing behind');
    });
  });

  group('AD-P3-1.07 — untied return with valid manager', () {
    test('succeeds', () async {
      final header = makeHeader(
        refundAmount: 100,
        isUntied: true,
        approvedByUserId: 'manager-1',
      );
      final saved = await returns.insertReturn(
        header: header,
        items: makeItems(),
      );
      expect(saved.id, header.id);
    });
  });

  group('AD-P3-1.08 — below-threshold return with bad approver', () {
    test('still throws UnauthorizedApprover', () async {
      final sale = await seedSale();
      final header = makeHeader(
        saleId: sale.id,
        refundAmount: 200,
        approvedByUserId: 'cashier-2',
      );
      await expectLater(
        returns.insertReturn(header: header, items: makeItems()),
        throwsA(isA<UnauthorizedApprover>()),
      );
    });
  });

  group('AD-P3-1.09 — boundary: amount exactly equal to threshold', () {
    test('does NOT require approval (> not >=)', () async {
      final sale = await seedSale();
      final header = makeHeader(
        saleId: sale.id,
        refundAmount: 500,
      );
      final saved = await returns.insertReturn(
        header: header,
        items: makeItems(),
      );
      expect(saved.id, header.id);
    });
  });

  group('AD-P3-5 — return audit inside transaction', () {
    test('a successful return writes a SALES_RETURN_PROCESSED audit row with JSON detail', () async {
      final sale = await seedSale();
      final header = makeHeader(
        saleId: sale.id,
        refundAmount: 200,
      );
      final saved = await returns.insertReturn(
        header: header,
        items: makeItems(),
      );

      final db = await DatabaseHelper.instance.database;
      final auditRows = await db.query(
        'audit_log',
        where: "action_type = 'SALES_RETURN_PROCESSED' AND record_id = ?",
        whereArgs: [saved.id],
      );
      expect(auditRows, hasLength(1));
      expect(auditRows.first['table_name'], 'sales_returns');
      expect(auditRows.first['user_id'], saved.userId);

      final detail = auditRows.first['new_value'] as String;
      expect(detail, contains('"returnId"'));
      expect(detail, contains('"refundAmount"'));
      expect(detail, contains('"refundMethod"'));
    });

    test('a refused return writes no audit row', () async {
      final header = makeHeader(
        refundAmount: 100,
        isUntied: true,
      );
      await expectLater(
        returns.insertReturn(header: header, items: makeItems()),
        throwsA(isA<ApprovalRequired>()),
      );

      final db = await DatabaseHelper.instance.database;
      final auditRows = await db.query(
        'audit_log',
        where: "action_type = 'SALES_RETURN_PROCESSED' AND record_id = ?",
        whereArgs: [header.id],
      );
      expect(auditRows, isEmpty, reason: 'a rolled-back return must not leave an audit trail');
    });

    test('the old SALES_RETURN_APPROVED action type is no longer written', () async {
      final sale = await seedSale();
      final header = makeHeader(
        saleId: sale.id,
        refundAmount: 600,
        approvedByUserId: 'manager-1',
      );
      await returns.insertReturn(header: header, items: makeItems());

      final db = await DatabaseHelper.instance.database;
      final oldRows = await db.query(
        'audit_log',
        where: "action_type = 'SALES_RETURN_APPROVED' AND record_id = ?",
        whereArgs: [header.id],
      );
      expect(oldRows, isEmpty, reason: 'the screen-level audit must be gone');
    });
  });
}
