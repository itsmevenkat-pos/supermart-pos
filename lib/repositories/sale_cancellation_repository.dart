import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
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

          // Reverse the points this sale *actually* moved, read back from the
          // `bonus_points` row SaleRepository wrote for it.
          //
          // This used to recompute the figure from `netAmount /
          // bonus_points_threshold`, which silently dropped the customer's
          // tier multiplier (`pointMultiplierForRating`) — so cancelling a
          // gold customer's bill clawed back half the points they had been
          // given, and cancelling any bill left redeemed points destroyed.
          // Since MigrationV30 the earn event is an authoritative record, so
          // the reversal reads it instead of re-deriving it.
          final pointsRows = await txn.query(
            'bonus_points',
            columns: ['points_earned', 'points_redeemed'],
            where: 'sale_id = ? AND event_type = ?',
            whereArgs: [sale.id, 'sale'],
            limit: 1,
          );

          int pointsEarned;
          int pointsRedeemed;
          if (pointsRows.isNotEmpty) {
            pointsEarned = (pointsRows.first['points_earned'] as num?)?.toInt() ?? 0;
            pointsRedeemed = (pointsRows.first['points_redeemed'] as num?)?.toInt() ?? 0;
          } else {
            // Sales completed before `bonus_points` had a writer have no event
            // to read. Fall back to the old un-multiplied estimate — it is what
            // this code has always done for them and there is no way to
            // recover the tier they held at the time. Redeemed points are not
            // restored in this path for the same reason: nothing recorded them.
            final storeRows = await txn.query(
              'stores',
              columns: ['bonus_points_threshold'],
              where: 'id = ?',
              whereArgs: [sale.storeId ?? 'store_default'],
              limit: 1,
            );
            final bonusPointsThreshold =
                storeRows.isNotEmpty ? (storeRows.first['bonus_points_threshold'] as num?)?.toDouble() ?? 300 : 300;
            pointsEarned = (sale.netAmount / bonusPointsThreshold).floor();
            pointsRedeemed = 0;
          }

          // Net effect on the balance: take back what the sale gave, hand back
          // what it spent. Clamped so a reversal can never push a customer
          // negative — if they have already spent the points this sale earned,
          // the shop absorbs the difference rather than showing a debt in
          // points that no screen in this app can represent.
          final currentPoints = (customerRows.first['loyalty_points'] as num?)?.toInt() ?? 0;
          var pointsDelta = pointsRedeemed - pointsEarned;
          if (currentPoints + pointsDelta < 0) {
            pointsDelta = -currentPoints;
          }

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

          final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

          await txn.rawUpdate(
            '''
            UPDATE customers
            SET outstanding_balance = ?,
                total_spent = total_spent - ?,
                loyalty_points = loyalty_points + ?,
                updated_at = ?
            WHERE id = ?
            ''',
            [
              newBalance,
              sale.netAmount,
              pointsDelta,
              now,
              sale.customerId,
            ],
          );

          // Log the reversal as its own event rather than deleting the sale's
          // earn row: the history should show that points were given and then
          // taken back, not pretend the sale never happened. Points handed
          // back to the customer become a fresh lot; the expiry window is
          // deliberately left null so a refunded point is not on a shorter
          // clock than the one it replaces.
          if (pointsDelta != 0) {
            await txn.insert('bonus_points', {
              'id': const Uuid().v4(),
              'customer_id': sale.customerId,
              'sale_id': sale.id,
              'points_earned': pointsDelta > 0 ? pointsDelta : 0,
              'points_redeemed': pointsDelta < 0 ? -pointsDelta : 0,
              'date': now,
              'event_type': 'cancellation',
              'note': 'Sale cancellation reversal',
              'created_by_user_id': userId,
            });
          }

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
