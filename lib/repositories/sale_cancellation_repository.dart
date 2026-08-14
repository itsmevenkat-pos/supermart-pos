import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/database/database_helper.dart';
import '../models/sale_cancellation_model.dart';
import '../models/sale_model.dart';
import '../models/sale_item_model.dart';
import '../models/stock_ledger_model.dart';
import '../models/customer_ledger_model.dart';
import 'stock_group_repository.dart';

/// Fully reverses a completed sale's stock/customer effects and marks it
/// `cancelled` — same compensating-row philosophy as `PurchaseRepository.delete`
/// (subtract stock back in, negative-of-the-original `stock_ledger`/
/// `customer_ledger` entries, never mutate the original `sales`/`sale_items`
/// rows other than flipping `status`).
class SaleCancellationRepository {
  SaleCancellationRepository({DatabaseHelper? dbHelper, StockGroupRepository? stockGroupRepo})
      : _dbHelper = dbHelper ?? DatabaseHelper.instance,
        _stockGroupRepo = stockGroupRepo ?? StockGroupRepository();

  final DatabaseHelper _dbHelper;
  final StockGroupRepository _stockGroupRepo;

  Future<SaleCancellation> cancelSale({
    required Sale sale,
    required List<SaleItem> items,
    required String reason,
    required String refundMethod,
    required String userId,
    String? approvedByUserId,
  }) async {
    final db = await _dbHelper.database;
    late SaleCancellation saved;
    await db.transaction((txn) async {
      // Re-fetch fresh inside the transaction — don't trust the `sale` param's
      // staleness for the status check (race-safety).
      final saleRows = await txn.query('sales', where: 'id = ?', whereArgs: [sale.id]);
      if (saleRows.isEmpty) {
        throw Exception('Sale not found — it may have been deleted.');
      }
      final freshSale = Sale.fromJson(saleRows.first);
      if (freshSale.status == 'cancelled') {
        throw Exception('This sale has already been cancelled.');
      }

      final returnRows = await txn.query('sales_returns', where: 'sale_id = ?', whereArgs: [sale.id]);
      if (returnRows.isNotEmpty) {
        throw Exception('Cannot cancel a sale that has already been returned against.');
      }

      final cancellation = SaleCancellation.create(
        saleId: sale.id,
        customerId: sale.customerId,
        reason: reason,
        refundMethod: refundMethod,
        refundAmount: sale.netAmount,
        userId: userId,
        approvedByUserId: approvedByUserId,
      );

      for (final item in items) {
        await txn.rawUpdate(
          '''
          UPDATE products
          SET stock_quantity = stock_quantity + ?, updated_at = ?
          WHERE id = ?
          ''',
          [item.quantity, DateTime.now().millisecondsSinceEpoch ~/ 1000, item.productId],
        );
        await _stockGroupRepo.propagateDelta(item.productId, item.quantity, executor: txn);

        final ledger = StockLedger.create(
          productId: item.productId,
          storeId: sale.storeId ?? '',
          referenceType: 'sale_cancellation',
          referenceId: cancellation.id,
          quantityChange: item.quantity,
          costPrice: item.costPrice,
          sellingPrice: item.unitPrice,
        );
        await txn.insert('stock_ledger', ledger.toJson());
      }

      if (sale.customerId != null) {
        final customerRows = await txn.query('customers', where: 'id = ?', whereArgs: [sale.customerId]);
        if (customerRows.isNotEmpty) {
          final currentBalance = (customerRows.first['outstanding_balance'] as num).toDouble();

          // Same DB-backed setting SaleRepository used to earn these points
          // (`stores.bonus_points_threshold`) — must match exactly or the
          // reversal drifts from what was actually earned.
          final storeRows = await txn.query(
            'stores',
            columns: ['bonus_points_threshold'],
            where: 'id = ?',
            whereArgs: [sale.storeId ?? 'store_default'],
            limit: 1,
          );
          final bonusPointsThreshold =
              storeRows.isNotEmpty ? (storeRows.first['bonus_points_threshold'] as num?)?.toDouble() ?? 300 : 300;
          final pointsEarned = (sale.netAmount / bonusPointsThreshold).floor();

          final ledgerRows = await txn.query(
            'customer_ledger',
            where: 'reference_type = ? AND reference_id = ?',
            whereArgs: ['sale', sale.id],
          );

          double newBalance = currentBalance;
          if (ledgerRows.isNotEmpty) {
            final originalAmount = (ledgerRows.first['amount'] as num).toDouble();
            newBalance = currentBalance - originalAmount;
          }

          await txn.rawUpdate(
            '''
            UPDATE customers
            SET outstanding_balance = ?,
                total_spent = total_spent - ?,
                loyalty_points = loyalty_points - ?,
                updated_at = ?
            WHERE id = ?
            ''',
            [
              newBalance,
              sale.netAmount,
              pointsEarned,
              DateTime.now().millisecondsSinceEpoch ~/ 1000,
              sale.customerId,
            ],
          );

          if (ledgerRows.isNotEmpty) {
            final originalAmount = (ledgerRows.first['amount'] as num).toDouble();
            final reversalEntry = CustomerLedger.create(
              customerId: sale.customerId!,
              referenceType: 'sale_cancellation',
              referenceId: cancellation.id,
              amount: -originalAmount,
              balance: newBalance,
              note: 'Sale cancellation reversal',
            );
            await txn.insert('customer_ledger', reversalEntry.toJson());
          }
        }
      }

      await txn.update('sales', {'status': 'cancelled'}, where: 'id = ?', whereArgs: [sale.id]);

      await txn.insert('sale_cancellations', cancellation.toJson());

      await _dbHelper.logAudit(
        userId: userId,
        actionType: 'SALE_CANCELLED',
        tableName: 'sales',
        recordId: sale.id,
        newValue: jsonEncode({
          'saleId': sale.id,
          'reason': reason,
          'refundMethod': refundMethod,
          'refundAmount': sale.netAmount,
          'approvedByUserId': approvedByUserId,
        }),
        executor: txn,
      );

      await _dbHelper.queueSync('sale_cancellations', cancellation.id, 'INSERT', cancellation.toJson(), executor: txn);

      saved = cancellation;
    });
    return saved;
  }

  Future<List<SaleCancellation>> getRecent({int limit = 50}) async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'sale_cancellations',
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return result.map((e) => SaleCancellation.fromJson(e)).toList();
  }

  Future<SaleCancellation?> getBySaleId(String saleId) async {
    final db = await _dbHelper.database;
    final result = await db.query('sale_cancellations', where: 'sale_id = ?', whereArgs: [saleId]);
    if (result.isEmpty) return null;
    return SaleCancellation.fromJson(result.first);
  }
}

final saleCancellationRepositoryProvider = Provider<SaleCancellationRepository>((ref) {
  return SaleCancellationRepository();
});
