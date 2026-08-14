import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import '../core/database/database_helper.dart';
import '../models/product_kit_component_model.dart';

class ProductKitRepository {
  ProductKitRepository({DatabaseHelper? dbHelper}) : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _dbHelper;

  /// Pass [executor] to read within an already-open transaction (e.g. from
  /// `SaleRepository`, so the component list is consistent with the rest of
  /// that sale's writes).
  Future<List<ProductKitComponent>> getComponents(String kitProductId, {DatabaseExecutor? executor}) async {
    final db = executor ?? await _dbHelper.database;
    final result = await db.query(
      'product_kit_components',
      where: 'kit_product_id = ?',
      whereArgs: [kitProductId],
    );
    return result.map((e) => ProductKitComponent.fromJson(e)).toList();
  }

  /// Replaces the full component list for a kit — same replace-all pattern
  /// `PurchaseRepository.updateWithItems` uses for purchase items, since
  /// there's no meaningful "diff" between an old and new components list
  /// for a small, form-edited set of rows.
  Future<void> setComponents(String kitProductId, List<ProductKitComponent> components) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      await txn.delete('product_kit_components', where: 'kit_product_id = ?', whereArgs: [kitProductId]);
      for (final component in components) {
        await txn.insert('product_kit_components', component.toJson());
      }
    });
  }
}

final productKitRepositoryProvider = Provider<ProductKitRepository>((ref) {
  return ProductKitRepository();
});
