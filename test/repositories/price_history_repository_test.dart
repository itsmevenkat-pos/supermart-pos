import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:supermart_pos/core/database/database_helper.dart';
import 'package:supermart_pos/models/product_model.dart';
import 'package:supermart_pos/repositories/price_history_repository.dart';
import 'package:supermart_pos/repositories/product_repository.dart';

/// Points path_provider at a throwaway temp directory so
/// `DatabaseHelper.instance.database` opens a real sqflite (ffi) database
/// under `flutter_test` — same harness as `sale_cancellation_repository_test.dart`.
class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this._path);
  final String _path;

  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late PriceHistoryRepository repo;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('price_history_test');
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
    repo = PriceHistoryRepository();
  });

  Future<Product> seedProduct() async {
    final product = Product.create(
      barcode: 'BC-${DateTime.now().microsecondsSinceEpoch}',
      name: 'Test Product',
      costPrice: 20,
      retailPrice: 40,
      stockQuantity: 10,
    );
    await ProductRepository().insert(product);
    return product;
  }

  group('PriceHistoryRepository', () {
    test('logChange + getHistory returns entries newest-first with correct old/new values', () async {
      final product = await seedProduct();

      // Insert with tiny delays so changed_at (second-resolution) ordering
      // is deterministic even on a fast machine.
      await repo.logChange(product.id, 'retail_price', 40, 45, 'test-user-1');
      await Future.delayed(const Duration(milliseconds: 1100));
      await repo.logChange(product.id, 'cost_price', 20, 22, 'test-user-1');
      await Future.delayed(const Duration(milliseconds: 1100));
      await repo.logChange(product.id, 'retail_price', 45, 50, null);

      final history = await repo.getHistory(product.id);

      expect(history, hasLength(3));

      // Newest first.
      expect(history[0].field, 'retail_price');
      expect(history[0].oldValue, 45);
      expect(history[0].newValue, 50);
      expect(history[0].changedByUserId, isNull);

      expect(history[1].field, 'cost_price');
      expect(history[1].oldValue, 20);
      expect(history[1].newValue, 22);
      expect(history[1].changedByUserId, 'test-user-1');

      expect(history[2].field, 'retail_price');
      expect(history[2].oldValue, 40);
      expect(history[2].newValue, 45);

      // changed_at is non-increasing from newest to oldest.
      expect(history[0].changedAt, greaterThanOrEqualTo(history[1].changedAt));
      expect(history[1].changedAt, greaterThanOrEqualTo(history[2].changedAt));
    });

    test('getHistory returns empty list for a product with no price changes', () async {
      final product = await seedProduct();

      final history = await repo.getHistory(product.id);

      expect(history, isEmpty);
    });

    test('getHistory only returns entries for the requested product', () async {
      final productA = await seedProduct();
      final productB = await seedProduct();

      await repo.logChange(productA.id, 'mrp', 50, 55, 'test-user-1');
      await repo.logChange(productB.id, 'mrp', 60, 65, 'test-user-1');

      final historyA = await repo.getHistory(productA.id);

      expect(historyA, hasLength(1));
      expect(historyA.first.productId, productA.id);
      expect(historyA.first.newValue, 55);
    });
  });
}
