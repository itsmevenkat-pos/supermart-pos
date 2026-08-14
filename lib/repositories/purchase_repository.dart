import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import '../core/database/database_helper.dart';
import '../models/purchase_model.dart';
import '../models/purchase_item_model.dart';
import '../models/product_model.dart';
import '../models/stock_ledger_model.dart';
import '../models/supplier_ledger_model.dart';
import '../models/product_batch_model.dart';
import 'stock_ledger_repository.dart';
import 'supplier_ledger_repository.dart';
import 'product_batch_repository.dart';
import 'stock_group_repository.dart';

class PurchaseRepository {
  PurchaseRepository({
    DatabaseHelper? dbHelper,
    StockLedgerRepository? ledgerRepo,
    SupplierLedgerRepository? supplierLedgerRepo,
    ProductBatchRepository? batchRepo,
    StockGroupRepository? stockGroupRepo,
  })  : _dbHelper = dbHelper ?? DatabaseHelper.instance,
        _ledgerRepo = ledgerRepo ?? StockLedgerRepository(),
        _supplierLedgerRepo = supplierLedgerRepo ?? SupplierLedgerRepository(),
        _batchRepo = batchRepo ?? ProductBatchRepository(),
        _stockGroupRepo = stockGroupRepo ?? StockGroupRepository();

  final DatabaseHelper _dbHelper;
  final StockLedgerRepository _ledgerRepo;
  final SupplierLedgerRepository _supplierLedgerRepo;
  final ProductBatchRepository _batchRepo;
  final StockGroupRepository _stockGroupRepo;

  /// The actual stock-unit quantity a purchase line contributes.
  ///
  /// - Repack lines (buy 1 unit, split into N retail units) use
  ///   [PurchaseItem.packCount] directly — untouched, pre-existing logic.
  /// - Purchase-unit lines (buy in the product's `purchaseUnit`, e.g. a Box
  ///   of 12) have `quantity`/`freeQuantity` entered as box counts; those
  ///   get multiplied by the line's snapshotted [PurchaseItem.purchaseUnitFactor]
  ///   to get the base-unit (stock) quantity.
  /// - Everything else (the common case) is unchanged: quantity + freeQuantity,
  ///   since [PurchaseItem.purchaseUnitFactor] defaults to 1 and
  ///   [PurchaseItem.isPurchaseUnitEntry] defaults to false.
  ///
  /// Used identically for adding stock (insert/edit) and reversing it
  /// (edit's pre-reversal, delete) — since it's a pure function of fields
  /// already persisted on the item row, insert and reversal always agree,
  /// even if the product's conversion factor changes later.
  double _stockQtyForItem(PurchaseItem item) {
    if (item.isRepack) return item.packCount.toDouble();
    final rawQty = item.quantity + item.freeQuantity;
    final factor = item.isPurchaseUnitEntry ? item.purchaseUnitFactor : 1.0;
    return rawQty * factor;
  }

  Future<void> insertWithItems(
    Purchase purchase,
    List<PurchaseItem> items,
  ) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      await txn.insert('purchases', purchase.toJson());

      // Same barcode can now come in at more than one MRP (e.g. a new
      // batch priced higher than what's already on the shelf). Cache
      // resolved variants per productId+mrp so two lines in the same
      // purchase for the same new price reuse one product row instead of
      // creating a duplicate each.
      final variantCache = <String, String>{};

      for (final item in items) {
        final productId = await _resolveProductId(txn, item, variantCache);

        final itemJson = item.toJson();
        itemJson['product_id'] = productId;
        // Fixed alongside this purchase-unit change: `purchase_id` was
        // never set here — callers (e.g. PurchaseFormScreen) build each
        // PurchaseItem via `.create()`, which always leaves `purchaseId`
        // null, and it was never stamped with the just-inserted purchase's
        // id before writing the row. Every purchase_items row was therefore
        // written with purchase_id = NULL, so `getItemsByPurchase`, the
        // edit-reversal query below, and delete()'s reversal query — all
        // `WHERE purchase_id = ?` — matched nothing. Editing or deleting a
        // purchase never actually reversed the original stock addition; it
        // just piled a second addition on top.
        itemJson['purchase_id'] = purchase.id;
        await txn.insert('purchase_items', itemJson);

        final double stockQtyToAdd = _stockQtyForItem(item);
        final double costPriceToSet = item.purchasePrice;
        final double sellingPriceToSet = item.salesPrice;

        if (productId == item.productId) {
          // Same MRP as what's already on this product row — safe to
          // update cost/selling price and add stock in place.
          await txn.rawUpdate('''
            UPDATE products
            SET stock_quantity = stock_quantity + ?,
                cost_price = ?,
                retail_price = ?,
                updated_at = ?
            WHERE id = ?
          ''', [
            stockQtyToAdd,
            costPriceToSet,
            sellingPriceToSet,
            DateTime.now().millisecondsSinceEpoch ~/ 1000,
            productId,
          ]);
        } else {
          // A new price-variant row was just created with the correct
          // mrp/cost/selling price — just add the purchased quantity to it.
          await txn.rawUpdate('''
            UPDATE products
            SET stock_quantity = stock_quantity + ?,
                updated_at = ?
            WHERE id = ?
          ''', [
            stockQtyToAdd,
            DateTime.now().millisecondsSinceEpoch ~/ 1000,
            productId,
          ]);
        }
        await _stockGroupRepo.propagateDelta(productId, stockQtyToAdd, executor: txn);

        final ledger = StockLedger.create(
          productId: productId,
          storeId: purchase.storeId!,
          referenceType: 'purchase',
          referenceId: purchase.id,
          quantityChange: stockQtyToAdd,
          batchNo: item.batchNo,
          expiryDate: item.expiryDate,
          costPrice: costPriceToSet,
          sellingPrice: sellingPriceToSet,
        );
        // Fixed: pass `txn` — previously ran on a fresh connection while
        // this transaction was still open, risking a deadlock.
        await _ledgerRepo.insert(ledger, executor: txn);

        // A real, queryable batch history row per purchase line — unlike
        // `stock_ledger`'s batchNo/expiryDate (which are purely descriptive
        // passthrough), this is what the product form's Batches section
        // reads. Written unconditionally (batchNo itself stays nullable) so
        // every purchase leaves a record, not just ones with a batch number
        // typed in.
        final batch = ProductBatch.create(
          productId: productId,
          purchaseId: purchase.id,
          batchNo: item.batchNo,
          mrp: item.mrp,
          costPrice: costPriceToSet,
          sellingPrice: sellingPriceToSet,
          expiryDate: item.expiryDate,
          quantityReceived: stockQtyToAdd,
        );
        await _batchRepo.insert(batch, executor: txn);
      }

      // Fixed: read the running balance through `txn` too, so it reflects
      // a consistent view relative to any writes already made in this
      // same transaction, and doesn't contend with it on a separate
      // connection reference.
      final currentBalance = await _supplierLedgerRepo.getBalance(purchase.supplierId!, executor: txn);
      final newBalance = currentBalance + purchase.netAmount;
      final supplierLedger = SupplierLedger.create(
        supplierId: purchase.supplierId!,
        referenceType: 'purchase',
        referenceId: purchase.id,
        amount: purchase.netAmount,
        balance: newBalance,
      );
      // Fixed: pass `txn` — see note above.
      await _supplierLedgerRepo.insert(supplierLedger, executor: txn);

      // Fixed: pass `txn` — see note above.
      await _dbHelper.queueSync('purchases', purchase.id, 'INSERT', purchase.toJson(), executor: txn);
    });
  }

  Future<void> updateWithItems(
    Purchase purchase,
    List<PurchaseItem> items,
  ) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      // Reverse what the CURRENT (pre-edit) items did to stock before
      // applying the new ones. Previously this just added the new
      // quantities on top without ever undoing the original add — editing
      // 50 down to 30 units left stock inflated by 50 instead of net -20.
      final oldPurchaseRows = await txn.query('purchases', where: 'id = ?', whereArgs: [purchase.id]);
      final oldItemRows = await txn.query('purchase_items', where: 'purchase_id = ?', whereArgs: [purchase.id]);
      final oldItems = oldItemRows.map((e) => PurchaseItem.fromJson(e)).toList();
      final oldNetAmount =
          oldPurchaseRows.isNotEmpty ? (oldPurchaseRows.first['net_amount'] as num?)?.toDouble() ?? 0 : 0.0;

      for (final oldItem in oldItems) {
        final oldStockQty = _stockQtyForItem(oldItem);
        await txn.rawUpdate(
          'UPDATE products SET stock_quantity = stock_quantity - ?, updated_at = ? WHERE id = ?',
          [oldStockQty, DateTime.now().millisecondsSinceEpoch ~/ 1000, oldItem.productId],
        );
        await _stockGroupRepo.propagateDelta(oldItem.productId, -oldStockQty, executor: txn);
        final reversalLedger = StockLedger.create(
          productId: oldItem.productId,
          storeId: purchase.storeId ?? '',
          referenceType: 'purchase_edit_reversal',
          referenceId: purchase.id,
          quantityChange: -oldStockQty,
          batchNo: oldItem.batchNo,
          expiryDate: oldItem.expiryDate,
          costPrice: 0,
          sellingPrice: 0,
        );
        await _ledgerRepo.insert(reversalLedger, executor: txn);
      }
      // Note: this reverses stock QUANTITY correctly. It does not attempt
      // to restore the product's cost/retail price to what it was before
      // this purchase — there's no price history to revert to, since
      // other purchases may have changed it since. If price accuracy
      // after an edit matters, re-check the product's price manually.

      await txn.delete('purchase_items', where: 'purchase_id = ?', whereArgs: [purchase.id]);
      await txn.update('purchases', purchase.toJson(), where: 'id = ?', whereArgs: [purchase.id]);

      final variantCache = <String, String>{};

      for (final item in items) {
        final productId = await _resolveProductId(txn, item, variantCache);

        final itemJson = item.toJson();
        itemJson['product_id'] = productId;
        // See matching note in insertWithItems — purchase_id must be
        // stamped explicitly, it's never set on the item itself.
        itemJson['purchase_id'] = purchase.id;
        await txn.insert('purchase_items', itemJson);

        final double stockQtyToAdd = _stockQtyForItem(item);

        if (productId == item.productId) {
          await txn.rawUpdate('''
            UPDATE products
            SET stock_quantity = stock_quantity + ?,
                cost_price = ?,
                retail_price = ?,
                updated_at = ?
            WHERE id = ?
          ''', [
            stockQtyToAdd,
            item.purchasePrice,
            item.salesPrice,
            DateTime.now().millisecondsSinceEpoch ~/ 1000,
            productId,
          ]);
        } else {
          await txn.rawUpdate('''
            UPDATE products
            SET stock_quantity = stock_quantity + ?,
                updated_at = ?
            WHERE id = ?
          ''', [
            stockQtyToAdd,
            DateTime.now().millisecondsSinceEpoch ~/ 1000,
            productId,
          ]);
        }
        await _stockGroupRepo.propagateDelta(productId, stockQtyToAdd, executor: txn);

        final newLedger = StockLedger.create(
          productId: productId,
          storeId: purchase.storeId ?? '',
          referenceType: 'purchase_edit',
          referenceId: purchase.id,
          quantityChange: stockQtyToAdd,
          batchNo: item.batchNo,
          expiryDate: item.expiryDate,
          costPrice: item.purchasePrice,
          sellingPrice: item.salesPrice,
        );
        await _ledgerRepo.insert(newLedger, executor: txn);

        final batch = ProductBatch.create(
          productId: productId,
          purchaseId: purchase.id,
          batchNo: item.batchNo,
          mrp: item.mrp,
          costPrice: item.purchasePrice,
          sellingPrice: item.salesPrice,
          expiryDate: item.expiryDate,
          quantityReceived: stockQtyToAdd,
        );
        await _batchRepo.insert(batch, executor: txn);
      }

      // Supplier ledger stays append-only (no rewriting the original
      // entry) — just record the net change as one adjustment entry.
      if (purchase.supplierId != null) {
        final netAmountDelta = purchase.netAmount - oldNetAmount;
        if (netAmountDelta != 0) {
          final currentBalance = await _supplierLedgerRepo.getBalance(purchase.supplierId!, executor: txn);
          final newBalance = currentBalance + netAmountDelta;
          final adjustmentLedger = SupplierLedger.create(
            supplierId: purchase.supplierId!,
            referenceType: 'purchase_edit_adjustment',
            referenceId: purchase.id,
            amount: netAmountDelta,
            balance: newBalance,
          );
          await _supplierLedgerRepo.insert(adjustmentLedger, executor: txn);
        }
      }

      await _dbHelper.queueSync('purchases', purchase.id, 'UPDATE', purchase.toJson(), executor: txn);
    });
  }

  /// Decides which `products` row a purchase line should update.
  ///
  /// If the product this line points at already carries the same MRP,
  /// it's safe to keep adding stock to that one row. If the MRP is
  /// different — a new batch coming in at a new price — a second row is
  /// created with the same barcode instead of overwriting the existing
  /// one, so older stock keeps showing its original MRP and the cashier
  /// gets prompted to pick the right one at billing (barcode is no
  /// longer UNIQUE — see the v4 migration).
  Future<String> _resolveProductId(
    DatabaseExecutor txn,
    PurchaseItem item,
    Map<String, String> variantCache,
  ) async {
    final rows = await txn.query('products', where: 'id = ?', whereArgs: [item.productId], limit: 1);
    if (rows.isEmpty) {
      // Nothing to compare against — use the id as given.
      return item.productId;
    }

    final base = Product.fromJson(rows.first);
    if ((base.mrp - item.mrp).abs() < 0.005) {
      return item.productId;
    }

    // Cache key is barcode+MRP, not productId+MRP — item.productId is just
    // whichever row this purchase line started from (often the base MRP),
    // which has nothing to do with which MRP variant row is the right
    // target once the MRP differs.
    final cacheKey = '${base.barcode}|${item.mrp.toStringAsFixed(2)}';
    final cached = variantCache[cacheKey];
    if (cached != null) return cached;

    // A row for this exact barcode+MRP may already exist from an earlier,
    // separate purchase (this purchase just started from a different MRP
    // row) — reuse it instead of spawning a duplicate. Without this check,
    // every purchase at a "new" MRP created a fresh row every time, so
    // stock for that MRP fragmented across several rows instead of
    // accumulating in one, making the item look out of stock when it
    // wasn't.
    final existingVariantRows = await txn.query(
      'products',
      where: 'barcode = ? AND ABS(mrp - ?) < 0.005 AND is_deleted = 0',
      whereArgs: [base.barcode, item.mrp],
      limit: 1,
    );
    if (existingVariantRows.isNotEmpty) {
      final existingId = existingVariantRows.first['id'] as String;
      variantCache[cacheKey] = existingId;
      return existingId;
    }

    final variant = Product.create(
      storeId: base.storeId,
      barcode: base.barcode,
      name: base.name,
      searchName: base.searchName,
      displayName: base.displayName,
      categoryId: base.categoryId,
      unit: base.unit,
      mrp: item.mrp,
      retailPrice: item.salesPrice,
      wholesalePrice: base.wholesalePrice,
      costPrice: item.purchasePrice,
      taxRate: item.taxPercent,
      reorderLevel: base.reorderLevel,
      bonusEligible: base.bonusEligible,
    );
    await txn.insert('products', variant.toJson());
    variantCache[cacheKey] = variant.id;
    return variant.id;
  }

  Future<List<Purchase>> getAll({int limit = 100}) async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'purchases',
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return result.map((e) => Purchase.fromJson(e)).toList();
  }

  Future<Purchase?> getByGrn(String grnNo) async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'purchases',
      where: 'grn_no = ?',
      whereArgs: [grnNo],
    );
    if (result.isEmpty) return null;
    return Purchase.fromJson(result.first);
  }

  Future<Purchase?> getById(String id) async {
    final db = await _dbHelper.database;
    final result = await db.query('purchases', where: 'id = ?', whereArgs: [id]);
    if (result.isEmpty) return null;
    return Purchase.fromJson(result.first);
  }

  Future<List<PurchaseItem>> getItemsByPurchase(String purchaseId) async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'purchase_items',
      where: 'purchase_id = ?',
      whereArgs: [purchaseId],
    );
    return result.map((e) => PurchaseItem.fromJson(e)).toList();
  }

  /// Reverses a purchase's stock and supplier-ledger effects before
  /// removing it. Previously this just deleted the `purchases` row —
  /// purchase_items cascaded away too, but the stock that was added and
  /// the supplier balance that was increased stayed exactly as they were,
  /// permanently. That meant you could delete a ₹10,000 purchase and the
  /// +100 units it added would just... stay in stock forever.
  Future<void> delete(String id) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      final purchaseRows = await txn.query('purchases', where: 'id = ?', whereArgs: [id]);
      if (purchaseRows.isEmpty) return; // Already gone — nothing to reverse.
      final purchase = Purchase.fromJson(purchaseRows.first);

      final itemRows = await txn.query('purchase_items', where: 'purchase_id = ?', whereArgs: [id]);
      final items = itemRows.map((e) => PurchaseItem.fromJson(e)).toList();

      for (final item in items) {
        final stockQty = _stockQtyForItem(item);
        await txn.rawUpdate(
          'UPDATE products SET stock_quantity = stock_quantity - ?, updated_at = ? WHERE id = ?',
          [stockQty, DateTime.now().millisecondsSinceEpoch ~/ 1000, item.productId],
        );
        await _stockGroupRepo.propagateDelta(item.productId, -stockQty, executor: txn);
        final reversalLedger = StockLedger.create(
          productId: item.productId,
          storeId: purchase.storeId ?? '',
          referenceType: 'purchase_delete_reversal',
          referenceId: id,
          quantityChange: -stockQty,
          batchNo: item.batchNo,
          expiryDate: item.expiryDate,
          costPrice: 0,
          sellingPrice: 0,
        );
        await _ledgerRepo.insert(reversalLedger, executor: txn);
      }

      if (purchase.supplierId != null && purchase.netAmount != 0) {
        final currentBalance = await _supplierLedgerRepo.getBalance(purchase.supplierId!, executor: txn);
        final newBalance = currentBalance - purchase.netAmount;
        final reversalSupplierLedger = SupplierLedger.create(
          supplierId: purchase.supplierId!,
          referenceType: 'purchase_delete_reversal',
          referenceId: id,
          amount: -purchase.netAmount,
          balance: newBalance,
        );
        await _supplierLedgerRepo.insert(reversalSupplierLedger, executor: txn);
      }

      // purchase_items cascade-deletes with this.
      await txn.delete('purchases', where: 'id = ?', whereArgs: [id]);
      await _dbHelper.queueSync('purchases', id, 'DELETE', {'id': id}, executor: txn);
    });
  }
}

final purchaseRepositoryProvider = Provider<PurchaseRepository>((ref) {
  return PurchaseRepository();
});