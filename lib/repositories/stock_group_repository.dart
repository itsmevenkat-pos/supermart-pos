import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import '../core/database/database_helper.dart';
import '../models/product_model.dart';
import '../models/stock_group_model.dart';

class StockGroupRepository {
  StockGroupRepository({DatabaseHelper? dbHelper}) : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _dbHelper;

  Future<List<StockGroup>> getAll() async {
    final db = await _dbHelper.database;
    final result = await db.query('stock_groups', orderBy: 'name ASC');
    return result.map((e) => StockGroup.fromJson(e)).toList();
  }

  Future<List<Product>> getMembers(String groupId) async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'products',
      where: 'stock_group_id = ? AND is_deleted = 0',
      whereArgs: [groupId],
      orderBy: 'name ASC',
    );
    return result.map((e) => Product.fromJson(e)).toList();
  }

  Future<StockGroup> createGroup(String name) async {
    final group = StockGroup.create(name: name);
    final db = await _dbHelper.database;
    await db.insert('stock_groups', group.toJson());
    return group;
  }

  Future<void> renameGroup(String id, String name) async {
    final db = await _dbHelper.database;
    await db.update('stock_groups', {'name': name}, where: 'id = ?', whereArgs: [id]);
  }

  /// Deletes the group and ungroups every member — each one's current
  /// (pooled) stock_quantity becomes its own independent starting count,
  /// same as [removeMember].
  Future<void> deleteGroup(String id) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      await txn.update('products', {'stock_group_id': null}, where: 'stock_group_id = ?', whereArgs: [id]);
      await txn.delete('stock_groups', where: 'id = ?', whereArgs: [id]);
    });
  }

  /// Adds [productId] to [groupId]. Requires the same price and tax rate
  /// as any existing member (keeps revenue reporting clean across the
  /// group) — throws if they don't match. The new member's own stock
  /// merges into the pool (summed, not overwritten) so shelf stock already
  /// counted for either side isn't silently discarded; every member (old
  /// and new) ends up at the same combined total.
  Future<void> addMember(String productId, String groupId) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      final productRows = await txn.query('products', where: 'id = ?', whereArgs: [productId]);
      if (productRows.isEmpty) throw Exception('Product not found: $productId');
      final product = Product.fromJson(productRows.first);

      final existingMembers = await txn.query('products', where: 'stock_group_id = ?', whereArgs: [groupId]);
      if (existingMembers.isNotEmpty) {
        final first = Product.fromJson(existingMembers.first);
        if ((first.retailPrice - product.retailPrice).abs() > 0.005 || first.taxRate != product.taxRate) {
          throw Exception(
            'Group members must share the same price and tax rate '
            '(this group is ₹${first.retailPrice.toStringAsFixed(2)} at ${first.taxRate}% tax).',
          );
        }
      }

      final pooledTotal = existingMembers.fold<double>(
            0,
            (sum, row) => sum + ((row['stock_quantity'] as num?)?.toDouble() ?? 0),
          ) +
          product.stockQuantity;

      await txn.update(
        'products',
        {'stock_group_id': groupId, 'stock_quantity': pooledTotal},
        where: 'id = ?',
        whereArgs: [productId],
      );
      for (final row in existingMembers) {
        await txn.update(
          'products',
          {'stock_quantity': pooledTotal},
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }
    });
  }

  /// Removes [productId] from its group — a supported "split back into
  /// individually tracked SKUs" edit. Its current (pooled) stock becomes
  /// its own independent count going forward; siblings keep sharing theirs.
  Future<void> removeMember(String productId) async {
    final db = await _dbHelper.database;
    await db.update('products', {'stock_group_id': null}, where: 'id = ?', whereArgs: [productId]);
  }

  /// Called right after a normal stock-affecting write to [productId]
  /// succeeds elsewhere (sale, purchase, return, cancellation — always
  /// with [executor] set to that same transaction) — mirrors the same
  /// [delta] onto every OTHER member of its stock group, if any, so the
  /// pool stays in sync. Doesn't touch [productId] itself (its own row was
  /// already updated by the caller) and doesn't re-run negative-stock
  /// checks per sibling — group members share one pool, so that check
  /// already happened once, on [productId]'s own guarded UPDATE.
  Future<void> propagateDelta(String productId, double delta, {DatabaseExecutor? executor}) async {
    if (delta == 0) return;
    final db = executor ?? await _dbHelper.database;
    final rows = await db.query('products', columns: ['stock_group_id'], where: 'id = ?', whereArgs: [productId]);
    if (rows.isEmpty) return;
    final groupId = rows.first['stock_group_id'] as String?;
    if (groupId == null) return;
    await db.rawUpdate(
      'UPDATE products SET stock_quantity = stock_quantity + ? WHERE stock_group_id = ? AND id != ?',
      [delta, groupId, productId],
    );
  }
}

final stockGroupRepositoryProvider = Provider<StockGroupRepository>((ref) {
  return StockGroupRepository();
});
