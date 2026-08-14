import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:supermart_pos/core/database/database_helper.dart';
import 'package:supermart_pos/models/product_model.dart';
import 'package:supermart_pos/models/purchase_model.dart';
import 'package:supermart_pos/models/purchase_item_model.dart';
import 'package:supermart_pos/models/supplier_model.dart';
import 'package:supermart_pos/repositories/product_repository.dart';
import 'package:supermart_pos/repositories/supplier_repository.dart';
import 'package:supermart_pos/repositories/purchase_repository.dart';

/// Same path_provider-faking harness as `exchange_repository_test.dart` /
/// `price_history_repository_test.dart` — a real sqflite (ffi) database
/// under a throwaway temp directory, built from the app's real migrations.
class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this._path);
  final String _path;

  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
}

int _barcodeCounter = 0;
String _nextBarcode() => 'PUR-TEST-${DateTime.now().microsecondsSinceEpoch}-${_barcodeCounter++}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late PurchaseRepository repo;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('purchase_repository_test');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
    // Force the database to actually open once so later `await database`
    // calls in the repositories under test hit a ready connection.
    await DatabaseHelper.instance.database;
  });

  tearDownAll(() async {
    await DatabaseHelper.instance.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  setUp(() {
    repo = PurchaseRepository();
  });

  /// A product bought in "Box" purchase units — 12 base-unit (Pcs) per Box —
  /// with an empty starting stock, plus a supplier to buy it from.
  Future<(Product, Supplier)> seedBoxProductAndSupplier({double unitsPerPurchaseUnit = 12}) async {
    final product = Product.create(
      barcode: _nextBarcode(),
      name: 'Boxed Product',
      unit: 'Pcs',
      costPrice: 10,
      retailPrice: 15,
      stockQuantity: 0,
      purchaseUnit: 'Box',
      unitsPerPurchaseUnit: unitsPerPurchaseUnit,
    );
    await ProductRepository().insert(product);

    final supplier = Supplier.create(name: 'Test Supplier ${DateTime.now().microsecondsSinceEpoch}');
    await SupplierRepository().insert(supplier);

    return (product, supplier);
  }

  PurchaseItem boxItem({
    required Product product,
    required double boxQuantity,
    double purchasePricePerBox = 120,
  }) {
    return PurchaseItem.create(
      productId: product.id,
      barcode: product.barcode,
      productName: product.name,
      mrp: product.mrp,
      quantity: boxQuantity,
      purchasePrice: purchasePricePerBox,
      salesPrice: product.retailPrice,
      costPrice: product.costPrice,
      isPurchaseUnitEntry: true,
      purchaseUnitFactor: product.unitsPerPurchaseUnit,
    );
  }

  group('PurchaseRepository — purchase-unit (Box/Case) stock conversion', () {
    test('purchasing 2 boxes of a 12-per-box product adds 24 to stock_quantity, not 2', () async {
      final (product, supplier) = await seedBoxProductAndSupplier();

      final purchase = Purchase.create(
        storeId: 'store_default',
        supplierId: supplier.id,
        grnNo: 'GRN-BOX-${DateTime.now().microsecondsSinceEpoch}',
        netAmount: 240,
      );
      final item = boxItem(product: product, boxQuantity: 2);

      await repo.insertWithItems(purchase, [item]);

      final after = await ProductRepository().getById(product.id);
      expect(after!.stockQuantity, 24); // 2 boxes * 12 units/box, not 2
    });

    test('a legacy line with no purchase-unit selected still adds the raw quantity (backward compatible)', () async {
      final (product, supplier) = await seedBoxProductAndSupplier();

      final purchase = Purchase.create(
        storeId: 'store_default',
        supplierId: supplier.id,
        grnNo: 'GRN-LEGACY-${DateTime.now().microsecondsSinceEpoch}',
        netAmount: 100,
      );
      // isPurchaseUnitEntry defaults to false — same as every purchase line
      // entered before this feature existed.
      final item = PurchaseItem.create(
        productId: product.id,
        barcode: product.barcode,
        productName: product.name,
        mrp: product.mrp,
        quantity: 10,
        purchasePrice: 10,
        salesPrice: product.retailPrice,
        costPrice: product.costPrice,
      );

      await repo.insertWithItems(purchase, [item]);

      final after = await ProductRepository().getById(product.id);
      expect(after!.stockQuantity, 10); // raw quantity, unmultiplied
    });

    test('a product with unitsPerPurchaseUnit = 1 (the default) behaves exactly as before, even in purchase-unit mode', () async {
      final (product, supplier) = await seedBoxProductAndSupplier(unitsPerPurchaseUnit: 1);

      final purchase = Purchase.create(
        storeId: 'store_default',
        supplierId: supplier.id,
        grnNo: 'GRN-NOOP-${DateTime.now().microsecondsSinceEpoch}',
        netAmount: 50,
      );
      final item = boxItem(product: product, boxQuantity: 5);

      await repo.insertWithItems(purchase, [item]);

      final after = await ProductRepository().getById(product.id);
      expect(after!.stockQuantity, 5); // 5 * 1 == 5, a true no-op multiplier
    });

    test('editing a 2-box purchase down to 1 box nets to +12 total, not double-counted', () async {
      final (product, supplier) = await seedBoxProductAndSupplier();

      final purchase = Purchase.create(
        storeId: 'store_default',
        supplierId: supplier.id,
        grnNo: 'GRN-EDIT-${DateTime.now().microsecondsSinceEpoch}',
        netAmount: 240,
      );
      final originalItem = boxItem(product: product, boxQuantity: 2);
      await repo.insertWithItems(purchase, [originalItem]);

      final afterInsert = await ProductRepository().getById(product.id);
      expect(afterInsert!.stockQuantity, 24);

      // Edit down to 1 box, same purchase id — updateWithItems must reverse
      // the original +24 (not the raw "2") before applying the new +12.
      final editedPurchase = purchase.copyWith(netAmount: 120);
      final editedItem = boxItem(product: product, boxQuantity: 1);
      await repo.updateWithItems(editedPurchase, [editedItem]);

      final afterEdit = await ProductRepository().getById(product.id);
      expect(afterEdit!.stockQuantity, 12); // net +12 from zero, not +24+12=36
    });

    test('deleting a 1-box (after edit) purchase reverses the full 12', () async {
      final (product, supplier) = await seedBoxProductAndSupplier();

      final purchase = Purchase.create(
        storeId: 'store_default',
        supplierId: supplier.id,
        grnNo: 'GRN-DELETE-${DateTime.now().microsecondsSinceEpoch}',
        netAmount: 240,
      );
      final originalItem = boxItem(product: product, boxQuantity: 2);
      await repo.insertWithItems(purchase, [originalItem]);

      final editedPurchase = purchase.copyWith(netAmount: 120);
      final editedItem = boxItem(product: product, boxQuantity: 1);
      await repo.updateWithItems(editedPurchase, [editedItem]);

      final beforeDelete = await ProductRepository().getById(product.id);
      expect(beforeDelete!.stockQuantity, 12);

      await repo.delete(purchase.id);

      final afterDelete = await ProductRepository().getById(product.id);
      expect(afterDelete!.stockQuantity, 0); // fully reversed back to opening stock
    });
  });
}
