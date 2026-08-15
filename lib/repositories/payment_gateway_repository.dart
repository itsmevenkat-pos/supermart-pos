import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../core/database/database_helper.dart';
import '../models/payment_gateway_transaction_model.dart';
import '../models/payment_settlement_model.dart';

/// Data access for gateway payments and payouts. Storage only — it does not
/// talk to any gateway, verify a signature or decide what to post to the
/// ledger. That is `PaymentGatewayService`'s job.
///
/// Same `executor` convention as `GLRepository` and
/// `BankReconciliationRepository`: every writing method takes an optional
/// [DatabaseExecutor] so the service can make "insert the payment, insert the
/// gateway detail, post the ledger entries" one transaction, while the same
/// methods still work standalone.
///
/// **This class is the first and only writer of the `payments` table.** That
/// table shipped in `MigrationV1` and, until this module, had no writers and
/// no readers anywhere in the app — sales record their payment split in the
/// `sales.payment_methods` JSON map instead. See
/// `docs/PAYMENT_GATEWAY_ARCHITECTURE.md`.
class PaymentGatewayRepository {
  PaymentGatewayRepository({DatabaseHelper? dbHelper}) : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _dbHelper;

  Future<DatabaseExecutor> _db(DatabaseExecutor? executor) async => executor ?? await _dbHelper.database;

  // --------------------------------------------------------------- payments

  /// Inserts the generic `payments` row a gateway transaction hangs off, and
  /// returns its id.
  ///
  /// [method] is what reports that group by payment method will see. It is
  /// the gateway's name (`razorpay`), matching how the task file asks for
  /// gateway payments to be labelled.
  Future<String> createPayment({
    required String? saleId,
    required String? customerId,
    required double amount,
    required String method,
    String? referenceNo,
    DateTime? paymentDate,
    DatabaseExecutor? executor,
  }) async {
    final db = await _db(executor);
    final id = const Uuid().v4();
    await db.insert('payments', {
      'id': id,
      'sale_id': saleId,
      'customer_id': customerId,
      'amount': amount,
      'method': method,
      'reference_no': referenceNo,
      'payment_date': (paymentDate ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000,
    });
    return id;
  }

  Future<Map<String, dynamic>?> getPayment(String id, {DatabaseExecutor? executor}) async {
    final db = await _db(executor);
    final rows = await db.query('payments', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  /// Updates the reference stored on a `payments` row — used once the
  /// gateway's payment id is known, so the generic payment record carries a
  /// human-traceable reference too.
  Future<void> updatePaymentReference(
    String paymentId,
    String referenceNo, {
    DatabaseExecutor? executor,
  }) async {
    final db = await _db(executor);
    await db.update(
      'payments',
      {'reference_no': referenceNo},
      where: 'id = ?',
      whereArgs: [paymentId],
    );
  }

  /// Links a `payments` row to the sale it turned out to settle.
  ///
  /// Needed because the money is collected before the sale is written — see
  /// [PaymentGatewayService.createOrder]. `payments.sale_id` is a foreign key
  /// to `sales(id)`, so this can only be called once that row exists.
  Future<void> attachSaleToPayment(
    String paymentId,
    String saleId, {
    DatabaseExecutor? executor,
  }) async {
    final db = await _db(executor);
    await db.update(
      'payments',
      {'sale_id': saleId},
      where: 'id = ?',
      whereArgs: [paymentId],
    );
  }

  // --------------------------------------------------- gateway transactions

  Future<PaymentGatewayTransaction> createTransaction(
    PaymentGatewayTransaction transaction, {
    DatabaseExecutor? executor,
  }) async {
    final db = await _db(executor);
    await db.insert('payment_gateway_transactions', transaction.toJson());
    return transaction;
  }

  Future<PaymentGatewayTransaction?> getTransaction(String id, {DatabaseExecutor? executor}) async {
    final db = await _db(executor);
    final rows = await db.query(
      'payment_gateway_transactions',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : PaymentGatewayTransaction.fromJson(rows.first);
  }

  /// Looks a transaction up by the gateway's own payment id.
  ///
  /// This is the idempotency check: before recording a success, the service
  /// asks whether this gateway payment id has already been seen. The column
  /// is UNIQUE, so a race that gets past this check still fails at the
  /// constraint rather than double-crediting the shop.
  Future<PaymentGatewayTransaction?> getByGatewayTransactionId(
    String gatewayTransactionId, {
    DatabaseExecutor? executor,
  }) async {
    final db = await _db(executor);
    final rows = await db.query(
      'payment_gateway_transactions',
      where: 'gateway_transaction_id = ?',
      whereArgs: [gatewayTransactionId],
      limit: 1,
    );
    return rows.isEmpty ? null : PaymentGatewayTransaction.fromJson(rows.first);
  }

  Future<PaymentGatewayTransaction?> getByOrderId(
    String gatewayOrderId, {
    DatabaseExecutor? executor,
  }) async {
    final db = await _db(executor);
    final rows = await db.query(
      'payment_gateway_transactions',
      where: 'gateway_order_id = ?',
      whereArgs: [gatewayOrderId],
      limit: 1,
    );
    return rows.isEmpty ? null : PaymentGatewayTransaction.fromJson(rows.first);
  }

  /// The gateway detail for a `payments` row — the one-to-one lookup.
  Future<PaymentGatewayTransaction?> getByPaymentId(
    String paymentId, {
    DatabaseExecutor? executor,
  }) async {
    final db = await _db(executor);
    final rows = await db.query(
      'payment_gateway_transactions',
      where: 'payment_id = ?',
      whereArgs: [paymentId],
      limit: 1,
    );
    return rows.isEmpty ? null : PaymentGatewayTransaction.fromJson(rows.first);
  }

  Future<List<PaymentGatewayTransaction>> getTransactions({
    PaymentGatewayName? gateway,
    GatewayTransactionStatus? status,
    DateTime? from,
    DateTime? to,
    DatabaseExecutor? executor,
  }) async {
    final db = await _db(executor);
    final where = <String>[];
    final args = <Object?>[];

    if (gateway != null) {
      where.add('gateway = ?');
      args.add(gateway.name);
    }
    if (status != null) {
      where.add('status = ?');
      args.add(status.name);
    }
    // Ranged on created_at rather than completed_at so a pending transaction
    // — which has no completion time — still shows up in the period it was
    // started in. A stuck payment nobody can see is the thing worth avoiding.
    if (from != null) {
      where.add('created_at >= ?');
      args.add(from.millisecondsSinceEpoch ~/ 1000);
    }
    if (to != null) {
      where.add('created_at <= ?');
      args.add(to.millisecondsSinceEpoch ~/ 1000);
    }

    final rows = await db.query(
      'payment_gateway_transactions',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'created_at DESC',
    );
    return rows.map(PaymentGatewayTransaction.fromJson).toList();
  }

  Future<void> updateTransaction(
    PaymentGatewayTransaction transaction, {
    DatabaseExecutor? executor,
  }) async {
    final db = await _db(executor);
    await db.update(
      'payment_gateway_transactions',
      transaction.toJson()..remove('id'),
      where: 'id = ?',
      whereArgs: [transaction.id],
    );
  }

  /// Moves a transaction to a terminal state, stamping [completedAt].
  ///
  /// Kept as its own method rather than leaving callers to build the row
  /// because the status and the completion stamp must move together — a
  /// `success` with no completion time breaks settlement reconciliation,
  /// which walks transactions by that column.
  Future<void> markStatus(
    String id, {
    required GatewayTransactionStatus status,
    String? gatewayTransactionId,
    String? gatewayResponse,
    DateTime? completedAt,
    DatabaseExecutor? executor,
  }) async {
    final db = await _db(executor);
    await db.update(
      'payment_gateway_transactions',
      {
        'status': status.name,
        if (gatewayTransactionId != null) 'gateway_transaction_id': gatewayTransactionId,
        if (gatewayResponse != null) 'gateway_response': gatewayResponse,
        'completed_at': status == GatewayTransactionStatus.pending
            ? null
            : (completedAt ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ------------------------------------------------------------ settlements

  Future<PaymentSettlement> createSettlement(
    PaymentSettlement settlement, {
    DatabaseExecutor? executor,
  }) async {
    final db = await _db(executor);
    await db.insert('payment_settlements', settlement.toJson());
    return settlement;
  }

  Future<PaymentSettlement?> getSettlement(String id, {DatabaseExecutor? executor}) async {
    final db = await _db(executor);
    final rows = await db.query('payment_settlements', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : PaymentSettlement.fromJson(rows.first);
  }

  Future<List<PaymentSettlement>> getSettlements({
    PaymentGatewayName? gateway,
    DateTime? from,
    DateTime? to,
    DatabaseExecutor? executor,
  }) async {
    final db = await _db(executor);
    final where = <String>[];
    final args = <Object?>[];

    if (gateway != null) {
      where.add('gateway = ?');
      args.add(gateway.name);
    }
    if (from != null) {
      where.add('settlement_date >= ?');
      args.add(from.millisecondsSinceEpoch ~/ 1000);
    }
    if (to != null) {
      where.add('settlement_date <= ?');
      args.add(to.millisecondsSinceEpoch ~/ 1000);
    }

    final rows = await db.query(
      'payment_settlements',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'settlement_date DESC',
    );
    return rows.map(PaymentSettlement.fromJson).toList();
  }
}

final paymentGatewayRepositoryProvider = Provider<PaymentGatewayRepository>((ref) {
  return PaymentGatewayRepository();
});
