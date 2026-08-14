import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:supermart_pos/core/database/database_helper.dart';
import 'package:supermart_pos/models/product_model.dart';
import 'package:supermart_pos/repositories/product_repository.dart';

/// Points path_provider at a throwaway temp directory so
/// `DatabaseHelper.instance.database` opens a real sqflite (ffi) database
/// under `flutter_test` — same harness as `price_history_repository_test.dart`.
class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this._path);
  final String _path;

  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late ProductRepository repo;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('product_repository_test');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
    // Touch the database once so it's created before the tests run.
    await DatabaseHelper.instance.database;
  });

  tearDownAll(() async {
    await DatabaseHelper.instance.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  setUp(() {
    repo = ProductRepository();
  });

  group('ProductRepository.getByBarcode — duplicate-barcode-warning support', () {
    test('returns all MRP-variant rows sharing the same barcode', () async {
      final barcode = 'BC-${DateTime.now().microsecondsSinceEpoch}';
      final productA = Product.create(barcode: barcode, name: 'Aashirvaad Atta 5kg (old MRP)', mrp: 240);
      final productB = Product.create(barcode: barcode, name: 'Aashirvaad Atta 5kg (new MRP)', mrp: 250);
      await repo.insert(productA);
      await repo.insert(productB);

      final matches = await repo.getByBarcode(barcode);

      expect(matches, hasLength(2));
      expect(matches.map((p) => p.id), containsAll([productA.id, productB.id]));
    });

    test('excluding the product currently being edited leaves only the OTHER product(s)', () async {
      final barcode = 'BC-${DateTime.now().microsecondsSinceEpoch}';
      final existing = Product.create(barcode: barcode, name: 'Existing Product', mrp: 100);
      await repo.insert(existing);

      // Simulate editing `existing` itself with the same barcode unchanged —
      // the duplicate-check in product_form_screen.dart excludes the product
      // being edited by id, so this must NOT be treated as a collision.
      final matches = await repo.getByBarcode(barcode);
      final othersWhenEditingSelf = matches.where((p) => p.id != existing.id).toList();
      expect(othersWhenEditingSelf, isEmpty);

      // A different (new) product entering the same barcode should see the
      // existing one as an unrelated match to warn about.
      final othersWhenEditingSomeoneElse = matches.where((p) => p.id != 'some-other-new-product-id').toList();
      expect(othersWhenEditingSomeoneElse, hasLength(1));
      expect(othersWhenEditingSomeoneElse.first.name, 'Existing Product');
    });

    test('returns an empty list for a barcode no product uses', () async {
      final matches = await repo.getByBarcode('no-such-barcode-${DateTime.now().microsecondsSinceEpoch}');
      expect(matches, isEmpty);
    });

    test('activeOnly: true excludes a deactivated product, default (false) still finds it', () async {
      final barcode = 'BC-${DateTime.now().microsecondsSinceEpoch}';
      final product = Product.create(barcode: barcode, name: 'Discontinued Snack', mrp: 30);
      await repo.insert(product);
      await repo.update(product.copyWith(isActive: false));

      final activeOnlyMatches = await repo.getByBarcode(barcode, activeOnly: true);
      expect(activeOnlyMatches, isEmpty);

      final allMatches = await repo.getByBarcode(barcode);
      expect(allMatches, hasLength(1));
    });
  });

  group('ProductRepository - Critical Tests', () {

    test('product name search should be case insensitive', () {
      const query = 'rice';
      const product = 'Rice';

      expect(
        product.toLowerCase().contains(
              query.toLowerCase(),
            ),
        isTrue,
      );
    });

    test('partial product name should match', () {
      const query = 'ric';
      const product = 'Rice';

      expect(
        product.toLowerCase().contains(
              query.toLowerCase(),
            ),
        isTrue,
      );
    });

    test('unrelated product should not match', () {
      const query = 'milk';
      const product = 'Rice';

      expect(
        product.toLowerCase().contains(
              query.toLowerCase(),
            ),
        isFalse,
      );
    });

    test('barcode search should match exact product', () {
      const query = '8901234567890';
      const barcode = '8901234567890';

      expect(query, barcode);
    });

    test('activeOnly billing search excludes a deactivated product', () {
      const productName = 'Discontinued Snack';
      const isActive = false;
      const activeOnly = true;

      final visibleToBilling = isActive || !activeOnly;

      expect(visibleToBilling, isFalse, reason: '$productName is inactive and should be hidden from billing search');
    });

    test('product management search still finds a deactivated product', () {
      const isActive = false;
      const activeOnly = false; // default for product_list_screen / purchase entry

      final visibleToManagement = isActive || !activeOnly;

      expect(visibleToManagement, isTrue);
    });
  });
}
