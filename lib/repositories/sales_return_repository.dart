import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import '../core/database/database_helper.dart';
import '../models/sales_return_model.dart';
import '../models/sales_return_item_model.dart';
import '../models/customer_ledger_model.dart';
import '../models/stock_ledger_model.dart';
import 'stock_group_repository.dart';
import '../services/gl_service.dart';

class SalesReturnRepository {
  SalesReturnRepository({
    DatabaseHelper? dbHelper,
    StockGroupRepository? stockGroupRepo,
    GLService? glService,
  })  : _dbHelper = dbHelper ?? DatabaseHelper.instance,
        _stockGroupRepo = stockGroupRepo ?? StockGroupRepository(),
        _glService = glService ?? GLService();

  final DatabaseHelper _dbHelper;
  final StockGroupRepository _stockGroupRepo;
  final GLService _glService;

  /// Inserts a return header + its lines in one transaction. Never mutates
  /// the original `sales`/`sale_items` rows — same compensating-row
  /// philosophy as `PurchaseRepository.delete`'s reversal ledger entries.
  ///
  /// For each item: if [SalesReturnItem.restocked] is true, stock is put
  /// back (atomic increment + a `stock_ledger` row with referenceType
  /// `sales_return`). Damaged/no-restock items are recorded on
  /// `sales_return_items` only — no stock or ledger effect.
  ///
  /// If [header.customerId] is set and [header.refundMethod] is
  /// `credit_adjust`, the customer's outstanding balance is reduced and a
  /// `customer_ledger` entry is written, mirroring the credit-sale entry
  /// `SaleRepository.insertSaleWithItems` writes, just negative.
  /// Pass [txn] to run inside an already-open transaction (e.g. from
  /// [ExchangeRepository], which composes a return with a new sale
  /// atomically) instead of opening a new one — default behavior
  /// (omitting [txn]) is unchanged for existing callers.
  Future<SalesReturn> insertReturn({
    required SalesReturn header,
    required List<SalesReturnItem> items,
    Transaction? txn,
  }) async {
    if (txn != null) {
      return _insertReturnBody(txn, header, items);
    }
    final db = await _dbHelper.database;
    late SalesReturn saved;
    await db.transaction((t) async {
      saved = await _insertReturnBody(t, header, items);
    });
    return saved;
  }

  Future<SalesReturn> _insertReturnBody(
    Transaction txn,
    SalesReturn header,
    List<SalesReturnItem> items,
  ) async {
    final saved = header;
    await txn.insert('sales_returns', saved.toJson());

      for (final item in items) {
        final toInsert = SalesReturnItem(
          id: item.id,
          returnId: saved.id,
          saleItemId: item.saleItemId,
          productId: item.productId,
          quantity: item.quantity,
          unitPrice: item.unitPrice,
          taxAmount: item.taxAmount,
          totalPrice: item.totalPrice,
          costPrice: item.costPrice,
          restocked: item.restocked,
        );
        await txn.insert('sales_return_items', toInsert.toJson());

        if (toInsert.restocked) {
          await txn.rawUpdate(
            '''
            UPDATE products
            SET stock_quantity = stock_quantity + ?, updated_at = ?
            WHERE id = ?
            ''',
            [toInsert.quantity, DateTime.now().millisecondsSinceEpoch ~/ 1000, toInsert.productId],
          );
          await _stockGroupRepo.propagateDelta(toInsert.productId, toInsert.quantity, executor: txn);

          final ledger = StockLedger.create(
            productId: toInsert.productId,
            storeId: header.storeId ?? '',
            referenceType: 'sales_return',
            referenceId: saved.id,
            quantityChange: toInsert.quantity,
            batchNo: null,
            expiryDate: null,
            costPrice: toInsert.costPrice,
            sellingPrice: toInsert.unitPrice,
          );
          await txn.insert('stock_ledger', ledger.toJson());
        }
      }

      if (header.customerId != null && header.refundMethod == 'credit_adjust') {
        final customerResult = await txn.query(
          'customers',
          where: 'id = ?',
          whereArgs: [header.customerId],
        );
        if (customerResult.isNotEmpty) {
          final currentBalance = (customerResult.first['outstanding_balance'] as num).toDouble();
          final newBalance = currentBalance - header.refundAmount;

          await txn.rawUpdate(
            '''
            UPDATE customers
            SET outstanding_balance = ?, updated_at = ?
            WHERE id = ?
            ''',
            [newBalance, DateTime.now().millisecondsSinceEpoch ~/ 1000, header.customerId],
          );

          final ledgerEntry = CustomerLedger.create(
            customerId: header.customerId!,
            referenceType: 'sales_return',
            referenceId: saved.id,
            amount: -header.refundAmount,
            balance: newBalance,
            note: 'Return refund adjusted against credit',
          );
          await txn.insert('customer_ledger', ledgerEntry.toJson());
        }
      }

    // General Ledger: revenue the shop no longer earned. Debit Sales Revenue
    // and credit whatever gave the money back — Accounts Receivable when the
    // refund is adjusted against the customer's outstanding balance (the
    // `credit_adjust` branch just above), Cash otherwise. Posted with `txn`
    // so the ledger commits or rolls back with the return itself.
    final returnDate = saved.createdAt > 0
        ? DateTime.fromMillisecondsSinceEpoch(saved.createdAt * 1000)
        : DateTime.now();
    await _glService.postSalesReturnEntries(
      returnId: saved.id,
      saleId: saved.saleId,
      returnDate: returnDate,
      refundAmount: saved.refundAmount,
      refundedAgainstCredit: saved.customerId != null && saved.refundMethod == 'credit_adjust',
      createdBy: saved.userId,
      executor: txn,
    );

    await _dbHelper.queueSync('sales_returns', saved.id, 'INSERT', saved.toJson(), executor: txn);

    return saved;
  }

  Future<List<SalesReturn>> getBySale(String saleId) async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'sales_returns',
      where: 'sale_id = ?',
      whereArgs: [saleId],
      orderBy: 'created_at DESC',
    );
    return result.map((e) => SalesReturn.fromJson(e)).toList();
  }

  Future<List<SalesReturn>> getRecent({int limit = 50}) async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'sales_returns',
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return result.map((e) => SalesReturn.fromJson(e)).toList();
  }

  Future<SalesReturn?> getById(String id) async {
    final db = await _dbHelper.database;
    final result = await db.query('sales_returns', where: 'id = ?', whereArgs: [id]);
    if (result.isEmpty) return null;
    return SalesReturn.fromJson(result.first);
  }

  Future<List<SalesReturnItem>> getItemsByReturn(String returnId) async {
    final db = await _dbHelper.database;
    final result = await db.query('sales_return_items', where: 'return_id = ?', whereArgs: [returnId]);
    return result.map((e) => SalesReturnItem.fromJson(e)).toList();
  }
}

final salesReturnRepositoryProvider = Provider<SalesReturnRepository>((ref) {
  return SalesReturnRepository();
});
