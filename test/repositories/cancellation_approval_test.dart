import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:supermart_pos/core/database/database_helper.dart';
import 'package:supermart_pos/models/product_model.dart';
import 'package:supermart_pos/models/sale_model.dart';
import 'package:supermart_pos/models/sale_item_model.dart';
import 'package:supermart_pos/repositories/product_repository.dart';
import 'package:supermart_pos/repositories/sale_repository.dart';
import 'package:supermart_pos/repositories/sale_cancellation_repository.dart';
import 'package:supermart_pos/services/approval_service.dart';

/// AD-P3-2 — Cancellation approval enforcement at the repository level.
///
/// Defect D4: SaleCancellationRepository.cancelSale accepts any
/// approvedByUserId without validation. A cashier can void a sale of any
/// size with no approver, or stamp a fabricated id.
///
/// Rule: cancellation always requires manager/admin (authoriseAlways).
/// The screen already enforces this; the repository must too.
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
  late SaleCancellationRepository repo;
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

  Future<(Sale, List<SaleItem>)> seedSale() async {
    final item = SaleItem.create(
      productId: product.id,
      quantity: 2,
      unitPrice: 100,
      totalPrice: 200,
      costPrice: 50,
    );
    final sale = Sale.create(
      storeId: 'store_default',
      netAmount: 200,
      paymentMethods: const {'cash': 200},
    );
    final saved = await SaleRepository().insertSaleWithItems(
      sale: sale,
      items: [item],
      storeId: 'store_default',
    );
    final savedItems = await SaleRepository().getItemsBySale(saved.id);
    return (saved, savedItems);
  }

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('cancel_approval_test');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
    await DatabaseHelper.instance.database;

    repo = SaleCancellationRepository();

    await seedUser('cashier-1', 'cashier');
    await seedUser('cashier-2', 'cashier');
    await seedUser('manager-1', 'manager');
    await seedUser('admin-1', 'admin');
    await seedUser('manager-retired', 'manager', active: false);

    product = Product.create(
      barcode: 'CANCEL-TEST-001',
      name: 'Cancel Test Widget',
      costPrice: 50,
      retailPrice: 100,
      stockQuantity: 1000,
    );
    await ProductRepository().insert(product);
  });

  tearDownAll(() async {
    await DatabaseHelper.instance.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('AD-P3-2.01 — cancel with valid manager', () {
    test('succeeds', () async {
      final (sale, items) = await seedSale();
      final cancellation = await repo.cancelSale(
        sale: sale,
        items: items,
        reason: 'Customer changed mind',
        refundMethod: 'cash',
        userId: 'cashier-1',
        approvedByUserId: 'manager-1',
      );
      expect(cancellation.saleId, sale.id);
    });
  });

  group('AD-P3-2.02 — cancel without approver', () {
    test('throws ApprovalRequired', () async {
      final (sale, items) = await seedSale();
      await expectLater(
        repo.cancelSale(
          sale: sale,
          items: items,
          reason: 'No approver',
          refundMethod: 'cash',
          userId: 'cashier-1',
        ),
        throwsA(isA<ApprovalRequired>()),
      );

      final db = await DatabaseHelper.instance.database;
      final saleRow = await db.query('sales', where: 'id = ?', whereArgs: [sale.id]);
      expect(saleRow.first['status'], 'completed',
          reason: 'a refused cancellation must not change the sale status');
    });
  });

  group('AD-P3-2.03 — cancel with cashier approver', () {
    test('throws UnauthorizedApprover', () async {
      final (sale, items) = await seedSale();
      await expectLater(
        repo.cancelSale(
          sale: sale,
          items: items,
          reason: 'Bad approver',
          refundMethod: 'cash',
          userId: 'cashier-1',
          approvedByUserId: 'cashier-2',
        ),
        throwsA(isA<UnauthorizedApprover>()),
      );

      final db = await DatabaseHelper.instance.database;
      final saleRow = await db.query('sales', where: 'id = ?', whereArgs: [sale.id]);
      expect(saleRow.first['status'], 'completed');
    });
  });

  group('AD-P3-2.04 — cancel with non-existent approver', () {
    test('throws UnauthorizedApprover', () async {
      final (sale, items) = await seedSale();
      await expectLater(
        repo.cancelSale(
          sale: sale,
          items: items,
          reason: 'Ghost approver',
          refundMethod: 'cash',
          userId: 'cashier-1',
          approvedByUserId: 'ghost-manager',
        ),
        throwsA(isA<UnauthorizedApprover>()),
      );
    });
  });

  group('AD-P3-2.05 — cancel with admin approver', () {
    test('succeeds', () async {
      final (sale, items) = await seedSale();
      final cancellation = await repo.cancelSale(
        sale: sale,
        items: items,
        reason: 'Admin approved',
        refundMethod: 'cash',
        userId: 'cashier-1',
        approvedByUserId: 'admin-1',
      );
      expect(cancellation.saleId, sale.id);
    });
  });

  group('AD-P3-2.06 — cancel with deactivated manager', () {
    test('throws UnauthorizedApprover', () async {
      final (sale, items) = await seedSale();
      await expectLater(
        repo.cancelSale(
          sale: sale,
          items: items,
          reason: 'Retired manager',
          refundMethod: 'cash',
          userId: 'cashier-1',
          approvedByUserId: 'manager-retired',
        ),
        throwsA(isA<UnauthorizedApprover>()),
      );
    });
  });
}
