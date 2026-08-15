import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/database/database_helper.dart';
import '../models/payment_gateway_transaction_model.dart';
import '../models/payment_settlement_model.dart';
import '../repositories/payment_gateway_repository.dart';
import '../repositories/store_repository.dart';
import 'gateways/payment_gateway.dart';
import 'gateways/razorpay_gateway.dart';
import 'gateways/stub_gateways.dart';
import 'gl_service.dart';
import 'payment_gateway_exceptions.dart';

/// What a settlement payout claims versus what this app recorded collecting.
///
/// [recordedTotal] is the sum of successful gateway transactions completed on
/// the settlement date; [recordedCount] is how many. A gateway batches by its
/// own cut-off, not by the shop's calendar day, so a difference here is
/// routine and is reported rather than treated as an error — the point is to
/// make it visible, the way the Task 2.1 reconciliation summary does.
class SettlementReconciliation extends Equatable {
  const SettlementReconciliation({
    required this.settlement,
    required this.recordedTotal,
    required this.recordedCount,
  });

  final PaymentSettlement settlement;
  final double recordedTotal;
  final int recordedCount;

  /// Gross the gateway says it processed, minus gross this app recorded.
  /// Positive means the gateway counted more than the shop did.
  double get grossVariance => settlement.totalAmount - recordedTotal;

  int get countVariance => settlement.transactionCount - recordedCount;

  /// Whether the payout's gross and count both line up with what was
  /// recorded. Uses the same one-paisa tolerance as the rest of this app.
  bool get agrees => grossVariance.abs() <= 0.01 && countVariance == 0;

  @override
  List<Object?> get props => [settlement, recordedTotal, recordedCount];
}

/// Orchestrates a payment through an external gateway: create the order, take
/// the customer's confirmation, prove it, record it, post it to the ledger.
///
/// **Three rules shape everything here.**
///
/// 1. *Nothing is recorded until the gateway confirms it.* A client-side
///    callback is a claim, not a payment. [verifyAndRecordPayment] proves the
///    claim through [PaymentGateway.verifyPayment] — signature plus a
///    server-side status check — before a single row moves.
///
/// 2. *The money row and the ledger entries commit together.* The `payments`
///    row, the gateway detail and the GL posting all happen inside one
///    database transaction. A crash between them would otherwise leave the
///    shop with a payment it cannot see in the ledger, or a ledger entry for
///    money it cannot trace.
///
/// 3. *A gateway payment id can only ever be recorded once.* Checked here and
///    enforced by a UNIQUE constraint underneath, because a retried callback
///    that credits the shop twice is worse than one that is refused.
///
/// This service creates the `payments` row itself. That table has existed
/// since `MigrationV1` with no writers at all — see
/// `docs/PAYMENT_GATEWAY_ARCHITECTURE.md` for why becoming its first writer
/// was preferred to inventing a third place a payment could live.
class PaymentGatewayService {
  PaymentGatewayService({
    PaymentGatewayRepository? repository,
    StoreRepository? storeRepository,
    GLService? glService,
    DatabaseHelper? dbHelper,
    PaymentGateway? gatewayOverride,
  })  : _repository = repository ?? PaymentGatewayRepository(),
        _storeRepository = storeRepository ?? StoreRepository(),
        _glService = glService ?? GLService(),
        _dbHelper = dbHelper ?? DatabaseHelper.instance,
        _gatewayOverride = gatewayOverride;

  final PaymentGatewayRepository _repository;
  final StoreRepository _storeRepository;
  final GLService _glService;
  final DatabaseHelper _dbHelper;

  /// Injected gateway, used by tests to run the whole flow against a fake.
  /// When set it replaces credential lookup entirely — nothing in the suite
  /// needs a Razorpay key or a network.
  final PaymentGateway? _gatewayOverride;

  /// The `payments.method` value gateway payments are recorded under.
  ///
  /// Deliberately the gateway's own name rather than a generic `'Online'`:
  /// existing reports group by this column, and a shop running two gateways
  /// needs to tell them apart in those reports without joining to another
  /// table.
  static String methodFor(PaymentGatewayName gateway) => gateway.name;

  // --------------------------------------------------------- gateway lookup

  /// Builds the gateway implementation for [name], reading credentials from
  /// the store settings.
  ///
  /// Throws [GatewayUnavailable] rather than returning null: every caller
  /// would otherwise have to invent the same error, and "the gateway is off"
  /// needs to reach the cashier as a sentence, not a null check.
  Future<PaymentGateway> gatewayFor(PaymentGatewayName name) async {
    final override = _gatewayOverride;
    if (override != null) {
      if (override.name != name) {
        throw GatewayUnavailable(
          'This service is pinned to ${override.name.name}, so ${name.name} cannot be used.',
        );
      }
      return override;
    }

    switch (name) {
      case PaymentGatewayName.razorpay:
        final config = await _storeRepository.getRazorpayConfig();
        if (!config.enabled) {
          throw GatewayUnavailable('Razorpay is switched off. Turn it on in Settings → Payment Gateways.');
        }
        final gateway = RazorpayGateway(keyId: config.keyId, keySecret: config.keySecret);
        if (!gateway.isConfigured) {
          throw GatewayUnavailable(
            'Razorpay is switched on but its key id or secret is missing. Add them in Settings → Payment Gateways.',
          );
        }
        return gateway;
      case PaymentGatewayName.paypal:
        throw GatewayUnavailable('PayPal is not implemented in this app.');
      case PaymentGatewayName.square:
        throw GatewayUnavailable('Square is not implemented in this app.');
    }
  }

  /// Which gateways the till should offer. Only ever the configured ones —
  /// the stubs report [PaymentGateway.isConfigured] false and so never
  /// appear, without the UI needing to know which are built.
  Future<List<PaymentGatewayName>> availableGateways() async {
    final override = _gatewayOverride;
    if (override != null) {
      return override.isConfigured ? [override.name] : const [];
    }

    final available = <PaymentGatewayName>[];
    final razorpay = await _storeRepository.getRazorpayConfig();
    if (razorpay.enabled && razorpay.keyId.trim().isNotEmpty && razorpay.keySecret.trim().isNotEmpty) {
      available.add(PaymentGatewayName.razorpay);
    }
    // PayPal and Square are deliberately absent — see StubGateways.
    const PayPalGateway();
    const SquareGateway();
    return available;
  }

  // ---------------------------------------------------------- order → payment

  /// Registers an intent to collect [amount] and records the pending
  /// transaction.
  ///
  /// The `payments` row is written now, at `pending`, rather than on success.
  /// It has to be: the gateway transaction references it, and a payment the
  /// customer abandoned is itself worth being able to see. What the row does
  /// *not* do at this stage is reach the ledger — nothing is posted until the
  /// money is proven, which is [verifyAndRecordPayment]'s job.
  ///
  /// **[saleId] is optional, and at the till it is normally null.** This app
  /// takes payment inside the payment dialog and only then calls
  /// `BillingService.processSale`, so at the moment an order is created the
  /// sale row does not exist yet — and `payments.sale_id` is a real foreign
  /// key to `sales(id)`, so passing an id for a sale that has not been
  /// written fails at the database. Collect first, then call [attachSale]
  /// once the sale has an id. [reference] is what the gateway sees as its
  /// receipt when there is no sale id yet.
  Future<PaymentGatewayTransaction> createOrder({
    required PaymentGatewayName gateway,
    required double amount,
    String? saleId,
    String? reference,
    String? customerId,
    DateTime? createdAt,
  }) async {
    if (amount <= 0) {
      throw PaymentGatewayServiceException(
        'A gateway payment must be for more than zero (got ${amount.toStringAsFixed(2)}).',
      );
    }

    final impl = await gatewayFor(gateway);
    // The gateway's receipt is the shop's own reference, so a payment can be
    // traced back to a bill from the gateway's dashboard. Falls back to a
    // timestamped marker when neither a sale nor a caller reference exists —
    // Razorpay requires *some* receipt.
    final receipt = saleId ??
        reference ??
        'pos-${(createdAt ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000}';
    final order = await impl.createOrder(amount: amount, receipt: receipt);

    final db = await _dbHelper.database;
    late PaymentGatewayTransaction created;
    await db.transaction((txn) async {
      final paymentId = await _repository.createPayment(
        saleId: saleId,
        customerId: customerId,
        amount: amount,
        method: methodFor(gateway),
        referenceNo: order.orderId,
        paymentDate: createdAt,
        executor: txn,
      );
      created = await _repository.createTransaction(
        PaymentGatewayTransaction.create(
          paymentId: paymentId,
          gateway: gateway,
          gatewayOrderId: order.orderId,
          gatewayResponse: order.rawResponse,
          createdAt: createdAt,
        ),
        executor: txn,
      );
    });
    return created;
  }

  /// Links a recorded gateway payment to the sale it settled, once that sale
  /// exists.
  ///
  /// The other half of [createOrder]'s null [saleId]: the till collects the
  /// money, `BillingService.processSale` writes the sale, and this joins the
  /// two. Separated rather than folded into `processSale` so the billing path
  /// keeps no knowledge of gateways — see
  /// `docs/PAYMENT_GATEWAY_ARCHITECTURE.md`.
  Future<void> attachSale({
    required String transactionId,
    required String saleId,
  }) async {
    final transaction = await _repository.getTransaction(transactionId);
    if (transaction == null) {
      throw GatewayTransactionNotFound('No gateway transaction $transactionId.');
    }
    await _repository.attachSaleToPayment(transaction.paymentId, saleId);
  }

  /// Proves a payment the customer says they made, records it and posts it.
  ///
  /// The order of operations is the point of this method:
  /// 1. Refuse a gateway payment id already on file (idempotency).
  /// 2. Ask the gateway — signature check, then its own status.
  /// 3. Only then, in one transaction: mark the transaction successful, stamp
  ///    the gateway reference onto the `payments` row, and post the ledger
  ///    entries.
  ///
  /// [settlesReceivable] is passed through to
  /// [GLService.postGatewayPaymentEntries] and says which asset account the
  /// payment clears — see that method for why a gateway payment never posts
  /// revenue.
  ///
  /// Throws [PaymentVerificationFailed] when the signature is wrong or the
  /// gateway does not report the payment as captured. Nothing is written in
  /// either case beyond marking the transaction failed, so the sale cannot be
  /// settled on an unproven payment.
  Future<PaymentGatewayTransaction> verifyAndRecordPayment({
    required String transactionId,
    required String gatewayTransactionId,
    required String signature,
    bool settlesReceivable = false,
    String? createdBy,
    DateTime? paidAt,
  }) async {
    final existing = await _repository.getTransaction(transactionId);
    if (existing == null) {
      throw GatewayTransactionNotFound('No gateway transaction $transactionId.');
    }
    if (existing.isTerminal) {
      throw InvalidTransactionState(
        'Transaction $transactionId is already ${existing.status.name} and cannot be verified again.',
      );
    }
    final orderId = existing.gatewayOrderId;
    if (orderId == null) {
      throw InvalidTransactionState(
        'Transaction $transactionId has no gateway order id, so its signature cannot be checked.',
      );
    }

    // Idempotency, checked before spending a network call. The UNIQUE index
    // on the column is the real guarantee; this is the friendly version of it.
    final duplicate = await _repository.getByGatewayTransactionId(gatewayTransactionId);
    if (duplicate != null) {
      throw DuplicateGatewayPayment(
        'Gateway payment $gatewayTransactionId is already recorded.',
        existingTransactionId: duplicate.id,
      );
    }

    final impl = await gatewayFor(existing.gateway);
    final verification = await impl.verifyPayment(
      orderId: orderId,
      gatewayTransactionId: gatewayTransactionId,
      signature: signature,
    );

    if (!verification.isValid) {
      // Recorded as failed so the attempt is not invisible — but the gateway
      // payment id is deliberately NOT stamped onto the row when the
      // signature itself failed: an unverified caller must not be able to
      // burn a real payment id by claiming it against a bad signature.
      await _repository.markStatus(
        transactionId,
        status: GatewayTransactionStatus.failed,
        gatewayTransactionId: verification.signatureValid ? gatewayTransactionId : null,
        gatewayResponse: verification.rawResponse,
        completedAt: paidAt,
      );
      throw PaymentVerificationFailed(
        verification.failureReason ?? 'The gateway did not confirm this payment.',
        signatureValid: verification.signatureValid,
      );
    }

    final payment = await _repository.getPayment(existing.paymentId);
    final amount = (payment?['amount'] as num?)?.toDouble() ?? 0;
    final saleId = payment?['sale_id'] as String?;
    final when = paidAt ?? DateTime.now();

    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      await _repository.markStatus(
        transactionId,
        status: GatewayTransactionStatus.success,
        gatewayTransactionId: gatewayTransactionId,
        gatewayResponse: verification.rawResponse,
        completedAt: when,
        executor: txn,
      );
      await _repository.updatePaymentReference(
        existing.paymentId,
        gatewayTransactionId,
        executor: txn,
      );
      // Posted inside the same transaction so the money and its ledger
      // entries cannot come apart — rule 2 in the class doc.
      await _glService.postGatewayPaymentEntries(
        paymentId: existing.paymentId,
        paymentDate: when,
        amount: amount,
        settlesReceivable: settlesReceivable,
        saleId: saleId,
        createdBy: createdBy,
        executor: txn,
      );
    });

    final updated = await _repository.getTransaction(transactionId);
    return updated!;
  }

  /// Asks the gateway what really happened to a transaction still sitting at
  /// `pending`, and records a definite failure.
  ///
  /// This is the recovery path for a callback that never arrived — the
  /// customer closed the browser, the till lost network mid-payment. It
  /// deliberately does **not** settle a payment it finds to be successful:
  /// doing so would post to the ledger without the signature check that
  /// [verifyAndRecordPayment] exists to perform. A success found here is
  /// reported so a human can confirm it through the normal path.
  Future<GatewayTransactionStatus> refreshStatus(String transactionId) async {
    final existing = await _repository.getTransaction(transactionId);
    if (existing == null) {
      throw GatewayTransactionNotFound('No gateway transaction $transactionId.');
    }
    final gatewayTransactionId = existing.gatewayTransactionId;
    if (gatewayTransactionId == null) {
      // Nothing was ever paid against the order, so there is nothing to ask
      // about — it is an abandoned checkout, not an unknown state.
      return existing.status;
    }

    final impl = await gatewayFor(existing.gateway);
    final status = await impl.getStatus(gatewayTransactionId);

    if (status.status == GatewayTransactionStatus.failed) {
      await _repository.markStatus(
        transactionId,
        status: GatewayTransactionStatus.failed,
        gatewayResponse: status.rawResponse,
      );
    }
    return status.status;
  }

  // ---------------------------------------------------------------- refunds

  /// Refunds a successful gateway payment and reverses its ledger entries.
  ///
  /// **The reversal is a full one, and partial refunds are refused.** A
  /// partial refund would need the ledger entry split, and this module's GL
  /// posting is a two-line reclassification between Bank and Cash/Receivable
  /// — reversing part of it correctly means deciding how a part-refunded sale
  /// is represented, which is a sale-level accounting question, not a gateway
  /// one. `SalesReturnService` is where a partial refund belongs. Refusing is
  /// honest; silently reversing the whole entry for a partial refund would
  /// not be.
  Future<PaymentGatewayTransaction> refundPayment({
    required String transactionId,
    String? createdBy,
    DateTime? refundedAt,
  }) async {
    final existing = await _repository.getTransaction(transactionId);
    if (existing == null) {
      throw GatewayTransactionNotFound('No gateway transaction $transactionId.');
    }
    if (existing.status != GatewayTransactionStatus.success) {
      throw InvalidTransactionState(
        'Only a successful payment can be refunded; transaction $transactionId is ${existing.status.name}.',
      );
    }
    final gatewayTransactionId = existing.gatewayTransactionId;
    if (gatewayTransactionId == null) {
      throw InvalidTransactionState(
        'Transaction $transactionId is marked successful but has no gateway payment id to refund.',
      );
    }

    final impl = await gatewayFor(existing.gateway);
    final refund = await impl.refund(gatewayTransactionId: gatewayTransactionId);

    final when = refundedAt ?? DateTime.now();
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      await _repository.markStatus(
        transactionId,
        status: GatewayTransactionStatus.refunded,
        gatewayResponse: refund.rawResponse,
        completedAt: when,
        executor: txn,
      );
      // Reverses by reference rather than posting a mirrored entry, so the
      // journal shows the original and its reversal as a pair — the same
      // convention Phase 1 uses for a full void.
      await _glService.reverseByReference(
        GLService.gatewayPaymentReferenceType,
        existing.paymentId,
        reason: 'Refund of gateway payment $gatewayTransactionId',
        createdBy: createdBy,
        executor: txn,
      );
    });

    final updated = await _repository.getTransaction(transactionId);
    return updated!;
  }

  // ------------------------------------------------------------ settlements

  /// Records a payout the gateway reports having made.
  ///
  /// **No GL entries are posted for a settlement, including its fees.** The
  /// money already reached account `1010` Bank when each payment was
  /// verified; a payout is the gateway moving its own float, not a new event
  /// for the shop's ledger. The fee genuinely is an expense the shop has
  /// borne, but booking it correctly needs a gateway-clearing account and a
  /// posting rule for the gap between "collected" and "deposited" — an
  /// accounting design decision, and one the task file does not ask for.
  /// [reconcileSettlement] surfaces the fee rather than burying it. This is
  /// listed as a known gap in `tasks/phase2/PROGRESS.md`.
  Future<PaymentSettlement> recordSettlement({
    required PaymentGatewayName gateway,
    required DateTime settlementDate,
    required int transactionCount,
    required double totalAmount,
    required double feesCharged,
    required double settledAmount,
    String? settlementReference,
  }) async {
    if (transactionCount < 0) {
      throw PaymentGatewayServiceException('A settlement cannot cover a negative number of transactions.');
    }
    if (totalAmount < 0 || settledAmount < 0) {
      throw PaymentGatewayServiceException('A settlement cannot have a negative gross or net amount.');
    }

    return _repository.createSettlement(
      PaymentSettlement.create(
        gateway: gateway,
        settlementDate: settlementDate,
        transactionCount: transactionCount,
        totalAmount: totalAmount,
        feesCharged: feesCharged,
        settledAmount: settledAmount,
        settlementReference: settlementReference,
      ),
    );
  }

  /// Compares a payout against the successful transactions this app recorded
  /// on the same day.
  ///
  /// The comparison window is the settlement's own calendar day. A gateway
  /// batches on its cut-off rather than the shop's midnight, so a non-zero
  /// variance is common and is reported, not flagged as an error — same
  /// stance as the Task 2.1 bank reconciliation summary.
  Future<SettlementReconciliation> reconcileSettlement(String settlementId) async {
    final settlement = await _repository.getSettlement(settlementId);
    if (settlement == null) {
      throw PaymentGatewayServiceException('No settlement $settlementId.');
    }

    final day = settlement.settlementDateTime;
    final dayStart = DateTime(day.year, day.month, day.day);
    final dayEnd = dayStart.add(const Duration(days: 1)).subtract(const Duration(seconds: 1));

    final transactions = await _repository.getTransactions(
      gateway: settlement.gateway,
      status: GatewayTransactionStatus.success,
    );

    var total = 0.0;
    var count = 0;
    for (final transaction in transactions) {
      final completed = transaction.completedAtDateTime;
      if (completed == null) continue;
      if (completed.isBefore(dayStart) || completed.isAfter(dayEnd)) continue;
      final payment = await _repository.getPayment(transaction.paymentId);
      total += (payment?['amount'] as num?)?.toDouble() ?? 0;
      count++;
    }

    return SettlementReconciliation(
      settlement: settlement,
      recordedTotal: total,
      recordedCount: count,
    );
  }

  // --------------------------------------------------------------- querying

  Future<List<PaymentGatewayTransaction>> getTransactions({
    PaymentGatewayName? gateway,
    GatewayTransactionStatus? status,
    DateTime? from,
    DateTime? to,
  }) =>
      _repository.getTransactions(gateway: gateway, status: status, from: from, to: to);

  Future<List<PaymentSettlement>> getSettlements({
    PaymentGatewayName? gateway,
    DateTime? from,
    DateTime? to,
  }) =>
      _repository.getSettlements(gateway: gateway, from: from, to: to);

  /// The amount collected through gateways in a period, by gateway.
  ///
  /// Successful transactions only — pending and failed ones are not money.
  Future<Map<PaymentGatewayName, double>> collectedByGateway({
    DateTime? from,
    DateTime? to,
  }) async {
    final transactions = await _repository.getTransactions(
      status: GatewayTransactionStatus.success,
      from: from,
      to: to,
    );
    final totals = <PaymentGatewayName, double>{};
    for (final transaction in transactions) {
      final payment = await _repository.getPayment(transaction.paymentId);
      final amount = (payment?['amount'] as num?)?.toDouble() ?? 0;
      totals[transaction.gateway] = (totals[transaction.gateway] ?? 0) + amount;
    }
    return totals;
  }
}

final paymentGatewayServiceProvider = Provider<PaymentGatewayService>((ref) {
  return PaymentGatewayService();
});
