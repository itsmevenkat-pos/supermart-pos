import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/database/database_helper.dart';
import '../models/product_model.dart';

/// Injected via constructor so tests can pass a fake/in-memory [DatabaseHelper]
/// instead of the real singleton. Existing call sites that used
/// `ProductRepository()` still compile unchanged because [dbHelper] defaults
/// to the app-wide singleton.
class ProductRepository {
  ProductRepository({DatabaseHelper? dbHelper})
      : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _dbHelper;

  Future<List<Product>> getAll({bool includeDeleted = false, bool activeOnly = true}) async {
    final db = await _dbHelper.database;
    var where = '';
    final args = <Object?>[];
    if (activeOnly) {
      where = 'is_active = 1 AND is_deleted = 0';
    } else if (!includeDeleted) {
      where = 'is_deleted = 0';
    }
    final result = await db.query(
      'products',
      where: where.isNotEmpty ? where : null,
      whereArgs: args.isNotEmpty ? args : null,
      orderBy: 'name ASC',
    );
    return result.map((e) => Product.fromJson(e)).toList();
  }

  /// [activeOnly] excludes deactivated items — pass true for billing/sale
  /// lookups (a deactivated item shouldn't be scannable at the till), leave
  /// false (default) for purchase entry, where finding and restocking an
  /// existing-but-deactivated item is preferable to creating a duplicate.
  Future<List<Product>> getByBarcode(String barcode, {bool activeOnly = false}) async {
    final db = await _dbHelper.database;
    final where = activeOnly ? 'barcode = ? AND is_deleted = 0 AND is_active = 1' : 'barcode = ? AND is_deleted = 0';
    final result = await db.query(
      'products',
      where: where,
      whereArgs: [barcode],
    );
    return result.map((e) => Product.fromJson(e)).toList();
  }

  Future<Product?> getById(String id) async {
    final db = await _dbHelper.database;
    final result = await db.query('products', where: 'id = ?', whereArgs: [id]);
    if (result.isEmpty) return null;
    return Product.fromJson(result.first);
  }

  Future<void> insert(Product product) async {
    final db = await _dbHelper.database;
    await db.insert('products', product.toJson());
    await _dbHelper.queueSync('products', product.id, 'INSERT', product.toJson());
  }

  Future<void> update(Product product) async {
    final db = await _dbHelper.database;
    await db.update('products', product.toJson(), where: 'id = ?', whereArgs: [product.id]);
    await _dbHelper.queueSync('products', product.id, 'UPDATE', product.toJson());
  }

  /// Inserts many products in a single transaction — used by Import Items /
  /// Import Parties-style bulk-load screens so a large CSV either lands
  /// entirely or not at all, and doesn't pay a separate commit per row.
  Future<void> bulkInsert(List<Product> products) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      for (final product in products) {
        await txn.insert('products', product.toJson());
        await _dbHelper.queueSync('products', product.id, 'INSERT', product.toJson(), executor: txn);
      }
    });
  }

  /// Updates many products in a single transaction — used by the
  /// Update Items In Bulk screen.
  Future<void> bulkUpdate(List<Product> products) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      for (final product in products) {
        await txn.update('products', product.toJson(), where: 'id = ?', whereArgs: [product.id]);
        await _dbHelper.queueSync('products', product.id, 'UPDATE', product.toJson(), executor: txn);
      }
    });
  }

  Future<void> updateStock(String productId, double quantityChange) async {
    final db = await _dbHelper.database;
    await db.rawUpdate(
      'UPDATE products SET stock_quantity = stock_quantity + ?, updated_at = ? WHERE id = ?',
      [quantityChange, DateTime.now().millisecondsSinceEpoch ~/ 1000, productId],
    );
  }

  /// [activeOnly] excludes deactivated items — pass true for billing search
  /// (see [getByBarcode]), leave false (default) for product management,
  /// purchase entry, and reports, which all need to still find them.
  Future<List<Product>> search(String query, {bool activeOnly = false}) async {
    final db = await _dbHelper.database;
    final where = activeOnly
        ? '(name LIKE ? OR search_name LIKE ? OR barcode LIKE ?) AND is_deleted = 0 AND is_active = 1'
        : '(name LIKE ? OR search_name LIKE ? OR barcode LIKE ?) AND is_deleted = 0';
    final result = await db.query(
      'products',
      where: where,
      whereArgs: ['%$query%', '%$query%', '%$query%'],
      limit: 20,
    );
    return result.map((e) => Product.fromJson(e)).toList();
  }

  /// Low-stock items, aggregated by barcode. Multi-MRP support means the
  /// same physical item can have several rows (one per price revision) —
  /// evaluating each row against its own reorder level independently is
  /// wrong: an item with 40 units on the old-MRP row and 0 on the new-MRP
  /// row isn't actually low on stock, and the reverse (thin new-MRP row,
  /// healthy old-MRP row) shouldn't trigger a false alert either. Returns
  /// one [Product] per barcode — the variant with the most stock, as the
  /// best representative of current pricing — with [Product.stockQuantity]
  /// overridden to the summed total across all of that barcode's rows.
  Future<List<Product>> getLowStock() async {
    final all = await getAll(activeOnly: true);
    final byBarcode = <String, List<Product>>{};
    for (final product in all) {
      byBarcode.putIfAbsent(product.barcode, () => []).add(product);
    }

    final result = <Product>[];
    for (final variants in byBarcode.values) {
      final totalStock = variants.fold<double>(0, (sum, p) => sum + p.stockQuantity);
      // Every MRP variant of a barcode is seeded from the same reorder
      // level at purchase time (see PurchaseRepository._resolveProductId),
      // so any one of them is representative.
      final reorderLevel = variants.first.reorderLevel;
      if (totalStock <= reorderLevel) {
        final representative = variants.reduce((a, b) => a.stockQuantity >= b.stockQuantity ? a : b);
        result.add(representative.copyWith(stockQuantity: totalStock));
      }
    }
    result.sort((a, b) => a.stockQuantity.compareTo(b.stockQuantity));
    return result;
  }
}

/// Riverpod provider — override this in tests with a fake DatabaseHelper-backed
/// repository, e.g.:
///   ProviderScope(overrides: [
///     productRepositoryProvider.overrideWithValue(ProductRepository(dbHelper: fakeDb)),
///   ])
final productRepositoryProvider = Provider<ProductRepository>((ref) {
  return ProductRepository();
});