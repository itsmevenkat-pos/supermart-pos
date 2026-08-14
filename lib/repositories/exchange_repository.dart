import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/database/database_helper.dart';
import '../models/customer_ledger_model.dart';
import '../models/exchange_model.dart';
import '../models/sale_item_model.dart';
import '../models/sale_model.dart';
import '../models/sales_return_item_model.dart';
import '../models/sales_return_model.dart';
import 'sale_repository.dart';
import 'sales_return_repository.dart';

/// Composes a [SalesReturn] (items coming back) with a new [Sale]
/// (replacement items) as ONE atomic transaction, then links the two with
/// an [Exchange] row and settles any price difference.
class ExchangeRepository {
  ExchangeRepository({DatabaseHelper? dbHelper}) : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _dbHelper;

  Future<Exchange> processExchange({
    required SalesReturn returnHeader,
    required List<SalesReturnItem> returnItems,
    required Sale newSale,
    required List<SaleItem> newSaleItems,
    required String settlementMethod,
    required String userId,
    String? approvedByUserId,
    required String storeId,
  }) async {
    final db = await _dbHelper.database;
    late Exchange savedExchange;

    await db.transaction((txn) async {
      // SalesReturnRepository.insertReturn independently adjusts the
      // customer's outstanding_balance when refundMethod == 'credit_adjust'
      // — but this repository already applies ONE consolidated adjustment
      // for the net price difference below. Passing 'credit_adjust' through
      // unchanged would double-count the return's portion of that
      // adjustment. Recorded reason/refund amount are preserved for the
      // audit trail; only the method that would trigger a second ledger
      // write is swapped out.
      final returnHeaderForInsert = returnHeader.refundMethod == 'credit_adjust'
          ? SalesReturn(
              id: returnHeader.id,
              saleId: returnHeader.saleId,
              customerId: returnHeader.customerId,
              storeId: returnHeader.storeId,
              sessionId: returnHeader.sessionId,
              userId: returnHeader.userId,
              approvedByUserId: returnHeader.approvedByUserId,
              reason: returnHeader.reason,
              refundMethod: 'exchange_settled',
              refundAmount: returnHeader.refundAmount,
              isUntied: returnHeader.isUntied,
              createdAt: returnHeader.createdAt,
            )
          : returnHeader;

      final savedReturn = await SalesReturnRepository().insertReturn(
        header: returnHeaderForInsert,
        items: returnItems,
        txn: txn,
      );

      final savedNewSale = await SaleRepository().insertSaleWithItems(
        sale: newSale,
        items: newSaleItems,
        storeId: storeId,
        customerId: returnHeader.customerId,
        txn: txn,
      );

      // Positive = customer owes more; negative = refund due to customer.
      final priceDifference = savedNewSale.netAmount - returnHeader.refundAmount;

      final exchange = Exchange.create(
        returnId: savedReturn.id,
        newSaleId: savedNewSale.id,
        customerId: returnHeader.customerId,
        priceDifference: priceDifference,
        settlementMethod: settlementMethod,
        userId: userId,
        approvedByUserId: approvedByUserId,
      );

      if (priceDifference != 0 &&
          settlementMethod == 'credit_adjust' &&
          returnHeader.customerId != null) {
        final customerResult = await txn.query(
          'customers',
          where: 'id = ?',
          whereArgs: [returnHeader.customerId],
        );
        if (customerResult.isNotEmpty) {
          final currentBalance = (customerResult.first['outstanding_balance'] as num).toDouble();
          final newBalance = currentBalance + priceDifference;

          await txn.rawUpdate(
            '''
            UPDATE customers
            SET outstanding_balance = ?, updated_at = ?
            WHERE id = ?
            ''',
            [newBalance, DateTime.now().millisecondsSinceEpoch ~/ 1000, returnHeader.customerId],
          );

          final ledgerEntry = CustomerLedger.create(
            customerId: returnHeader.customerId!,
            referenceType: 'exchange',
            referenceId: exchange.id,
            amount: priceDifference,
            balance: newBalance,
            note: 'Exchange settlement',
          );
          await txn.insert('customer_ledger', ledgerEntry.toJson());
        }
      }

      await txn.insert('exchanges', exchange.toJson());

      await _dbHelper.logAudit(
        userId: userId,
        actionType: 'EXCHANGE_PROCESSED',
        tableName: 'exchanges',
        recordId: exchange.id,
        executor: txn,
      );

      await _dbHelper.queueSync('exchanges', exchange.id, 'INSERT', exchange.toJson(), executor: txn);

      savedExchange = exchange;
    });

    return savedExchange;
  }

  Future<List<Exchange>> getRecent({int limit = 50}) async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'exchanges',
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return result.map((e) => Exchange.fromJson(e)).toList();
  }

  Future<Exchange?> getById(String id) async {
    final db = await _dbHelper.database;
    final result = await db.query('exchanges', where: 'id = ?', whereArgs: [id]);
    if (result.isEmpty) return null;
    return Exchange.fromJson(result.first);
  }
}

final exchangeRepositoryProvider = Provider<ExchangeRepository>((ref) {
  return ExchangeRepository();
});
