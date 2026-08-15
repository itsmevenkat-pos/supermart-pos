import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:supermart_pos/core/database/database_helper.dart';
import 'package:supermart_pos/models/payment_gateway_transaction_model.dart';
import 'package:supermart_pos/repositories/gl_repository.dart';
import 'package:supermart_pos/repositories/payment_gateway_repository.dart';
import 'package:supermart_pos/services/gateways/payment_gateway.dart';
import 'package:supermart_pos/services/gl_service.dart';
import 'package:supermart_pos/services/payment_gateway_exceptions.dart';
import 'package:supermart_pos/services/payment_gateway_service.dart';

class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this._path);
  final String _path;

  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
}

/// A gateway that answers however a test needs it to, with no network and no
/// keys. Injected through `PaymentGatewayService(gatewayOverride: ...)`, which
/// is the whole reason that parameter exists.
class _FakeGateway implements PaymentGateway {
  _FakeGateway({
    this.configured = true,
    this.failCreateOrder = false,
  });

  final String orderId = 'order_FAKE';

  /// Mutated directly by tests to steer the next verification.
  GatewayTransactionStatus verificationStatus = GatewayTransactionStatus.success;
  bool signatureValid = true;

  final bool configured;
  final bool failCreateOrder;

  int createOrderCalls = 0;
  int verifyCalls = 0;
  int refundCalls = 0;
  int statusCalls = 0;
  double? lastOrderAmount;
  String? lastReceipt;

  @override
  PaymentGatewayName get name => PaymentGatewayName.razorpay;

  @override
  bool get isConfigured => configured;

  @override
  Future<GatewayOrder> createOrder({
    required double amount,
    required String receipt,
    String currency = 'INR',
  }) async {
    createOrderCalls++;
    lastOrderAmount = amount;
    lastReceipt = receipt;
    if (failCreateOrder) {
      throw const PaymentGatewayException(PaymentGatewayName.razorpay, 'gateway is down');
    }
    return GatewayOrder(
      orderId: orderId,
      amount: amount,
      currency: currency,
      rawResponse: jsonEncode({'id': orderId, 'amount': (amount * 100).round()}),
    );
  }

  @override
  Future<GatewayVerification> verifyPayment({
    required String orderId,
    required String gatewayTransactionId,
    required String signature,
  }) async {
    verifyCalls++;
    return GatewayVerification(
      isValid: signatureValid && verificationStatus == GatewayTransactionStatus.success,
      signatureValid: signatureValid,
      status: signatureValid ? verificationStatus : GatewayTransactionStatus.failed,
      gatewayTransactionId: gatewayTransactionId,
      rawResponse: jsonEncode({'id': gatewayTransactionId, 'status': verificationStatus.name}),
      failureReason: signatureValid ? null : 'Signature did not match.',
    );
  }

  @override
  Future<GatewayRefund> refund({required String gatewayTransactionId, double? amount}) async {
    refundCalls++;
    return GatewayRefund(
      refundId: 'rfnd_FAKE',
      amount: amount ?? 0,
      rawResponse: jsonEncode({'id': 'rfnd_FAKE'}),
    );
  }

  @override
  Future<GatewayVerification> getStatus(String gatewayTransactionId) async {
    statusCalls++;
    return GatewayVerification(
      isValid: verificationStatus == GatewayTransactionStatus.success,
      status: verificationStatus,
      gatewayTransactionId: gatewayTransactionId,
      rawResponse: jsonEncode({'id': gatewayTransactionId, 'status': verificationStatus.name}),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late PaymentGatewayRepository repository;
  late GLRepository glRepository;
  late _FakeGateway fakeGateway;
  late PaymentGatewayService service;

  late String cashAccountId;
  late String bankAccountId;
  late String receivableAccountId;
  late String revenueAccountId;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('payment_gateway_service_test');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
    await DatabaseHelper.instance.database;
    final gl = GLRepository();
    cashAccountId = (await gl.getAccountByCode('1000'))!.id;
    bankAccountId = (await gl.getAccountByCode('1010'))!.id;
    receivableAccountId = (await gl.getAccountByCode('1100'))!.id;
    revenueAccountId = (await gl.getAccountByCode('4000'))!.id;
  });

  tearDownAll(() async {
    await DatabaseHelper.instance.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  setUp(() async {
    repository = PaymentGatewayRepository();
    glRepository = GLRepository();
    fakeGateway = _FakeGateway();
    service = PaymentGatewayService(gatewayOverride: fakeGateway);

    final db = await DatabaseHelper.instance.database;
    await db.delete('payment_gateway_transactions');
    await db.delete('payment_settlements');
    await db.delete('payments');
    await db.delete('sales');
    await db.delete('gl_entries');
    await db.delete('gl_balances');
  });

  Future<String> makeSale({int invoiceNo = 1, double netAmount = 1000}) async {
    final db = await DatabaseHelper.instance.database;
    final id = 'sale-$invoiceNo';
    await db.insert('sales', {
      'id': id,
      'invoice_no': invoiceNo,
      'net_amount': netAmount,
      'created_at': DateTime(2025, 6, 1).millisecondsSinceEpoch ~/ 1000,
    });
    return id;
  }

  /// Signed total for an account: debits positive, credits negative.
  Future<double> signedTotal(String accountId) async {
    final entries = await glRepository.getEntriesByAccount(accountId);
    var total = 0.0;
    for (final entry in entries) {
      total += entry.isDebit ? entry.debit : -entry.credit;
    }
    return total;
  }

  Future<PaymentGatewayTransaction> paidTransaction({
    double amount = 1000,
    bool settlesReceivable = false,
    DateTime? paidAt,
  }) async {
    final created = await service.createOrder(
      gateway: PaymentGatewayName.razorpay,
      amount: amount,
    );
    return service.verifyAndRecordPayment(
      transactionId: created.id,
      gatewayTransactionId: 'pay_${created.id.substring(0, 8)}',
      signature: 'good-signature',
      settlesReceivable: settlesReceivable,
      paidAt: paidAt,
    );
  }

  group('gateway availability', () {
    test('the injected gateway is the one used', () async {
      expect(await service.gatewayFor(PaymentGatewayName.razorpay), same(fakeGateway));
    });

    test('asking for a gateway this service is not pinned to is refused', () async {
      expect(
        () => service.gatewayFor(PaymentGatewayName.paypal),
        throwsA(isA<GatewayUnavailable>()),
      );
    });

    test('an unconfigured gateway is not offered at the till', () async {
      final off = PaymentGatewayService(gatewayOverride: _FakeGateway(configured: false));
      expect(await off.availableGateways(), isEmpty);
      expect(await service.availableGateways(), [PaymentGatewayName.razorpay]);
    });

    test('PayPal and Square are unavailable through the real lookup', () async {
      final real = PaymentGatewayService();
      expect(() => real.gatewayFor(PaymentGatewayName.paypal), throwsA(isA<GatewayUnavailable>()));
      expect(() => real.gatewayFor(PaymentGatewayName.square), throwsA(isA<GatewayUnavailable>()));
    });

    test('Razorpay is unavailable while it is switched off in settings', () async {
      // Default store config is disabled with empty keys, so a fresh install
      // never offers a gateway nobody set up.
      final real = PaymentGatewayService();
      expect(() => real.gatewayFor(PaymentGatewayName.razorpay), throwsA(isA<GatewayUnavailable>()));
      expect(await real.availableGateways(), isEmpty);
    });
  });

  group('createOrder', () {
    test('writes a pending payment and transaction, and posts nothing to the ledger', () async {
      final created = await service.createOrder(
        gateway: PaymentGatewayName.razorpay,
        amount: 1500,
      );

      expect(created.status, GatewayTransactionStatus.pending);
      expect(created.gatewayOrderId, 'order_FAKE');
      expect(created.completedAt, isNull);

      final payment = await repository.getPayment(created.paymentId);
      expect(payment!['amount'], 1500);
      expect(payment['method'], 'razorpay');
      // An unproven payment must not reach the ledger.
      expect(await signedTotal(bankAccountId), 0);
      expect(await signedTotal(cashAccountId), 0);
    });

    test('records the payment method as the gateway name so reports can group on it', () async {
      final created = await service.createOrder(gateway: PaymentGatewayName.razorpay, amount: 100);
      final payment = await repository.getPayment(created.paymentId);
      expect(payment!['method'], PaymentGatewayService.methodFor(PaymentGatewayName.razorpay));
    });

    test('has no sale id at the till, because the sale does not exist yet', () async {
      final created = await service.createOrder(gateway: PaymentGatewayName.razorpay, amount: 100);
      final payment = await repository.getPayment(created.paymentId);
      expect(payment!['sale_id'], isNull);
      // A receipt is still sent so the payment is traceable from the
      // gateway's own dashboard.
      expect(fakeGateway.lastReceipt, isNotEmpty);
    });

    test('uses the sale id as the gateway receipt when one is known', () async {
      final saleId = await makeSale();
      await service.createOrder(gateway: PaymentGatewayName.razorpay, amount: 100, saleId: saleId);
      expect(fakeGateway.lastReceipt, saleId);
    });

    test('rejects a zero or negative amount before calling the gateway', () async {
      await expectLater(
        service.createOrder(gateway: PaymentGatewayName.razorpay, amount: 0),
        throwsA(isA<PaymentGatewayServiceException>()),
      );
      expect(fakeGateway.createOrderCalls, 0);
    });

    test('a gateway failure writes nothing at all', () async {
      final failing = PaymentGatewayService(gatewayOverride: _FakeGateway(failCreateOrder: true));

      await expectLater(
        failing.createOrder(gateway: PaymentGatewayName.razorpay, amount: 100),
        throwsA(isA<PaymentGatewayException>()),
      );
      expect(await repository.getTransactions(), isEmpty);
    });

    test('attachSale links the payment once the sale has been written', () async {
      final created = await service.createOrder(gateway: PaymentGatewayName.razorpay, amount: 100);
      final saleId = await makeSale(invoiceNo: 2);

      await service.attachSale(transactionId: created.id, saleId: saleId);

      expect((await repository.getPayment(created.paymentId))!['sale_id'], saleId);
    });

    test('attaching against an unknown transaction is refused', () async {
      expect(
        () => service.attachSale(transactionId: 'nope', saleId: 'x'),
        throwsA(isA<GatewayTransactionNotFound>()),
      );
    });
  });

  group('verifyAndRecordPayment — the ledger', () {
    test('a paid sale moves cash to bank and posts NO new revenue', () async {
      await paidTransaction(amount: 1000);

      // The sale's own entries already credited revenue; a gateway payment is
      // only how the money arrived. Posting revenue again would double the
      // day's takings.
      expect(await signedTotal(revenueAccountId), 0);
      expect(await signedTotal(bankAccountId), 1000);
      expect(await signedTotal(cashAccountId), -1000);
    });

    test('settling a receivable credits 1100 instead of 1000', () async {
      await paidTransaction(amount: 750, settlesReceivable: true);

      expect(await signedTotal(bankAccountId), 750);
      expect(await signedTotal(receivableAccountId), -750);
      expect(await signedTotal(cashAccountId), 0);
      expect(await signedTotal(revenueAccountId), 0);
    });

    test('the posting is balanced — debits equal credits', () async {
      await paidTransaction(amount: 1234.56);

      final entries = await glRepository.getEntriesByReference(
        GLService.gatewayPaymentReferenceType,
        (await repository.getTransactions()).single.paymentId,
      );
      var debits = 0.0;
      var credits = 0.0;
      for (final entry in entries) {
        if (entry.isDebit) {
          debits += entry.debit;
        } else {
          credits += entry.credit;
        }
      }
      expect(entries.length, 2);
      expect(debits, closeTo(credits, 0.001));
      expect(debits, closeTo(1234.56, 0.001));
    });

    test('the entries are tagged so they can be found and reversed', () async {
      final transaction = await paidTransaction(amount: 500);
      final entries = await glRepository.getEntriesByReference(
        GLService.gatewayPaymentReferenceType,
        transaction.paymentId,
      );
      expect(entries, hasLength(2));
      expect(entries.every((e) => e.referenceType == GLService.gatewayPaymentReferenceType), isTrue);
    });
  });

  group('verifyAndRecordPayment — records and guards', () {
    test('a verified payment is marked successful and stamped with its gateway id', () async {
      final transaction = await paidTransaction(amount: 400);

      expect(transaction.status, GatewayTransactionStatus.success);
      expect(transaction.gatewayTransactionId, isNotNull);
      expect(transaction.completedAt, isNotNull);
      // The generic payments row carries the gateway reference too, so the
      // payment is traceable without joining.
      final payment = await repository.getPayment(transaction.paymentId);
      expect(payment!['reference_no'], transaction.gatewayTransactionId);
    });

    test('a bad signature records a failure, posts nothing, and is flagged as a security event', () async {
      fakeGateway.signatureValid = false;
      final created = await service.createOrder(gateway: PaymentGatewayName.razorpay, amount: 900);

      await expectLater(
        service.verifyAndRecordPayment(
          transactionId: created.id,
          gatewayTransactionId: 'pay_FORGED',
          signature: 'forged',
        ),
        throwsA(isA<PaymentVerificationFailed>().having((e) => e.signatureValid, 'signatureValid', isFalse)),
      );

      final after = await repository.getTransaction(created.id);
      expect(after!.status, GatewayTransactionStatus.failed);
      // The claimed payment id is deliberately NOT stamped: an unverified
      // caller must not be able to burn a real payment id.
      expect(after.gatewayTransactionId, isNull);
      expect(await signedTotal(bankAccountId), 0);
    });

    test('a genuinely failed payment with a good signature posts nothing either', () async {
      fakeGateway.verificationStatus = GatewayTransactionStatus.failed;
      final created = await service.createOrder(gateway: PaymentGatewayName.razorpay, amount: 900);

      await expectLater(
        service.verifyAndRecordPayment(
          transactionId: created.id,
          gatewayTransactionId: 'pay_FAILED',
          signature: 'good-signature',
        ),
        throwsA(isA<PaymentVerificationFailed>().having((e) => e.signatureValid, 'signatureValid', isTrue)),
      );

      final after = await repository.getTransaction(created.id);
      expect(after!.status, GatewayTransactionStatus.failed);
      // Signature was fine, so the id is recorded — the attempt is real, the
      // payment simply did not succeed.
      expect(after.gatewayTransactionId, 'pay_FAILED');
      expect(await signedTotal(bankAccountId), 0);
    });

    test('a replayed callback cannot credit the shop twice', () async {
      final first = await paidTransaction(amount: 1000);
      final second = await service.createOrder(gateway: PaymentGatewayName.razorpay, amount: 1000);

      await expectLater(
        service.verifyAndRecordPayment(
          transactionId: second.id,
          gatewayTransactionId: first.gatewayTransactionId!,
          signature: 'good-signature',
        ),
        throwsA(isA<DuplicateGatewayPayment>()
            .having((e) => e.existingTransactionId, 'existingTransactionId', first.id)),
      );

      // Bank still holds one payment, not two.
      expect(await signedTotal(bankAccountId), 1000);
      expect(fakeGateway.verifyCalls, 1);
    });

    test('verifying an already-terminal transaction is refused', () async {
      final transaction = await paidTransaction(amount: 100);

      await expectLater(
        service.verifyAndRecordPayment(
          transactionId: transaction.id,
          gatewayTransactionId: 'pay_AGAIN',
          signature: 'good-signature',
        ),
        throwsA(isA<InvalidTransactionState>()),
      );
    });

    test('verifying an unknown transaction is refused', () async {
      expect(
        () => service.verifyAndRecordPayment(
          transactionId: 'nope',
          gatewayTransactionId: 'pay_X',
          signature: 's',
        ),
        throwsA(isA<GatewayTransactionNotFound>()),
      );
    });
  });

  group('refreshStatus', () {
    test('records a failure the callback never reported', () async {
      final created = await service.createOrder(gateway: PaymentGatewayName.razorpay, amount: 100);
      await repository.markStatus(
        created.id,
        status: GatewayTransactionStatus.pending,
        gatewayTransactionId: 'pay_STUCK',
      );

      fakeGateway.verificationStatus = GatewayTransactionStatus.failed;
      final status = await service.refreshStatus(created.id);

      expect(status, GatewayTransactionStatus.failed);
      expect((await repository.getTransaction(created.id))!.status, GatewayTransactionStatus.failed);
    });

    test('a success found here is reported but NOT settled without a signature check', () async {
      final created = await service.createOrder(gateway: PaymentGatewayName.razorpay, amount: 100);
      await repository.markStatus(
        created.id,
        status: GatewayTransactionStatus.pending,
        gatewayTransactionId: 'pay_MAYBE',
      );

      final status = await service.refreshStatus(created.id);

      expect(status, GatewayTransactionStatus.success);
      // Still pending, and nothing posted — settling here would skip the
      // signature check that verifyAndRecordPayment exists to perform.
      expect((await repository.getTransaction(created.id))!.status, GatewayTransactionStatus.pending);
      expect(await signedTotal(bankAccountId), 0);
    });

    test('an abandoned checkout with no payment id asks the gateway nothing', () async {
      final created = await service.createOrder(gateway: PaymentGatewayName.razorpay, amount: 100);

      expect(await service.refreshStatus(created.id), GatewayTransactionStatus.pending);
      expect(fakeGateway.statusCalls, 0);
    });

    test('refreshing an unknown transaction is refused', () async {
      expect(() => service.refreshStatus('nope'), throwsA(isA<GatewayTransactionNotFound>()));
    });
  });

  group('refunds', () {
    test('a refund reverses the ledger entries and marks the transaction refunded', () async {
      final transaction = await paidTransaction(amount: 1000);
      expect(await signedTotal(bankAccountId), 1000);

      final refunded = await service.refundPayment(transactionId: transaction.id);

      expect(refunded.status, GatewayTransactionStatus.refunded);
      expect(fakeGateway.refundCalls, 1);
      // The pair nets to zero — the money left the bank again.
      expect(await signedTotal(bankAccountId), 0);
      expect(await signedTotal(cashAccountId), 0);
      expect(await signedTotal(revenueAccountId), 0);
    });

    test('refunding leaves the reversal visible as its own entries', () async {
      final transaction = await paidTransaction(amount: 250);
      await service.refundPayment(transactionId: transaction.id);

      final entries = await glRepository.getEntriesByReference(
        GLService.gatewayPaymentReferenceType,
        transaction.paymentId,
      );
      // Two original lines plus two reversals — the journal shows both, it
      // does not erase the original.
      expect(entries.length, 4);
      expect(entries.where((e) => e.reversalOfEntryId != null).length, 2);
    });

    test('only a successful payment can be refunded', () async {
      final created = await service.createOrder(gateway: PaymentGatewayName.razorpay, amount: 100);

      await expectLater(
        service.refundPayment(transactionId: created.id),
        throwsA(isA<InvalidTransactionState>()),
      );
      expect(fakeGateway.refundCalls, 0);
    });

    test('refunding twice is refused', () async {
      final transaction = await paidTransaction(amount: 100);
      await service.refundPayment(transactionId: transaction.id);

      await expectLater(
        service.refundPayment(transactionId: transaction.id),
        throwsA(isA<InvalidTransactionState>()),
      );
    });

    test('refunding an unknown transaction is refused', () async {
      expect(
        () => service.refundPayment(transactionId: 'nope'),
        throwsA(isA<GatewayTransactionNotFound>()),
      );
    });
  });

  group('settlements', () {
    test('records a payout and reports its fee', () async {
      final settlement = await service.recordSettlement(
        gateway: PaymentGatewayName.razorpay,
        settlementDate: DateTime(2025, 6, 2),
        transactionCount: 2,
        totalAmount: 2000,
        feesCharged: 40,
        settledAmount: 1960,
        settlementReference: 'setl_ABC',
      );

      expect(settlement.settledAmount, 1960);
      expect(settlement.feeVariance, 0);
      expect(settlement.effectiveFeePercent, closeTo(2.0, 0.001));
    });

    test('a payout whose own figures do not add up shows a variance', () async {
      final settlement = await service.recordSettlement(
        gateway: PaymentGatewayName.razorpay,
        settlementDate: DateTime(2025, 6, 2),
        transactionCount: 1,
        totalAmount: 1000,
        feesCharged: 20,
        settledAmount: 900, // should have been 980
      );

      expect(settlement.feeVariance, closeTo(-80, 0.001));
    });

    test('rejects negative counts and amounts', () async {
      await expectLater(
        service.recordSettlement(
          gateway: PaymentGatewayName.razorpay,
          settlementDate: DateTime(2025, 6, 2),
          transactionCount: -1,
          totalAmount: 100,
          feesCharged: 0,
          settledAmount: 100,
        ),
        throwsA(isA<PaymentGatewayServiceException>()),
      );
      await expectLater(
        service.recordSettlement(
          gateway: PaymentGatewayName.razorpay,
          settlementDate: DateTime(2025, 6, 2),
          transactionCount: 1,
          totalAmount: -100,
          feesCharged: 0,
          settledAmount: 100,
        ),
        throwsA(isA<PaymentGatewayServiceException>()),
      );
    });

    test('recording a settlement posts nothing to the ledger', () async {
      await service.recordSettlement(
        gateway: PaymentGatewayName.razorpay,
        settlementDate: DateTime(2025, 6, 2),
        transactionCount: 1,
        totalAmount: 1000,
        feesCharged: 20,
        settledAmount: 980,
      );

      // The money reached 1010 Bank when the payment was verified. A payout
      // is the gateway moving its own float — see recordSettlement's doc for
      // why the fee is surfaced rather than booked.
      expect(await signedTotal(bankAccountId), 0);
    });

    test('reconciles a payout against what was actually recorded that day', () async {
      await paidTransaction(amount: 600, paidAt: DateTime(2025, 6, 2, 11));
      await paidTransaction(amount: 400, paidAt: DateTime(2025, 6, 2, 15));

      final settlement = await service.recordSettlement(
        gateway: PaymentGatewayName.razorpay,
        settlementDate: DateTime(2025, 6, 2),
        transactionCount: 2,
        totalAmount: 1000,
        feesCharged: 20,
        settledAmount: 980,
      );

      final reconciliation = await service.reconcileSettlement(settlement.id);

      expect(reconciliation.recordedTotal, 1000);
      expect(reconciliation.recordedCount, 2);
      expect(reconciliation.grossVariance, 0);
      expect(reconciliation.agrees, isTrue);
    });

    test('a payout covering a payment from another day shows a variance rather than an error', () async {
      await paidTransaction(amount: 600, paidAt: DateTime(2025, 6, 2, 11));
      // The gateway batches on its own cut-off, so this one lands in the
      // payout but not in the shop's calendar day.
      await paidTransaction(amount: 400, paidAt: DateTime(2025, 6, 1, 23, 30));

      final settlement = await service.recordSettlement(
        gateway: PaymentGatewayName.razorpay,
        settlementDate: DateTime(2025, 6, 2),
        transactionCount: 2,
        totalAmount: 1000,
        feesCharged: 20,
        settledAmount: 980,
      );

      final reconciliation = await service.reconcileSettlement(settlement.id);

      expect(reconciliation.recordedTotal, 600);
      expect(reconciliation.recordedCount, 1);
      expect(reconciliation.grossVariance, closeTo(400, 0.001));
      expect(reconciliation.countVariance, 1);
      expect(reconciliation.agrees, isFalse);
    });

    test('only successful payments count toward a reconciliation', () async {
      await paidTransaction(amount: 600, paidAt: DateTime(2025, 6, 2, 11));
      // A failed attempt on the same day must not inflate the recorded total.
      fakeGateway.verificationStatus = GatewayTransactionStatus.failed;
      final failing = await service.createOrder(gateway: PaymentGatewayName.razorpay, amount: 999);
      await expectLater(
        service.verifyAndRecordPayment(
          transactionId: failing.id,
          gatewayTransactionId: 'pay_NOPE',
          signature: 'good-signature',
          paidAt: DateTime(2025, 6, 2, 12),
        ),
        throwsA(isA<PaymentVerificationFailed>()),
      );

      final settlement = await service.recordSettlement(
        gateway: PaymentGatewayName.razorpay,
        settlementDate: DateTime(2025, 6, 2),
        transactionCount: 1,
        totalAmount: 600,
        feesCharged: 12,
        settledAmount: 588,
      );

      final reconciliation = await service.reconcileSettlement(settlement.id);
      expect(reconciliation.recordedTotal, 600);
      expect(reconciliation.recordedCount, 1);
      expect(reconciliation.agrees, isTrue);
    });

    test('reconciling an unknown settlement is refused', () async {
      expect(
        () => service.reconcileSettlement('nope'),
        throwsA(isA<PaymentGatewayServiceException>()),
      );
    });

    test('lists settlements through the service', () async {
      await service.recordSettlement(
        gateway: PaymentGatewayName.razorpay,
        settlementDate: DateTime(2025, 6, 2),
        transactionCount: 1,
        totalAmount: 100,
        feesCharged: 2,
        settledAmount: 98,
      );
      expect((await service.getSettlements()).length, 1);
    });
  });

  group('reporting', () {
    test('collectedByGateway counts only successful payments', () async {
      await paidTransaction(amount: 600, paidAt: DateTime(2025, 6, 2, 11));
      await paidTransaction(amount: 400, paidAt: DateTime(2025, 6, 2, 12));
      // A pending order is not money.
      await service.createOrder(gateway: PaymentGatewayName.razorpay, amount: 5000);

      final totals = await service.collectedByGateway();
      expect(totals[PaymentGatewayName.razorpay], 1000);
    });

    test('collectedByGateway is empty when nothing succeeded', () async {
      await service.createOrder(gateway: PaymentGatewayName.razorpay, amount: 100);
      expect(await service.collectedByGateway(), isEmpty);
    });

    test('getTransactions filters by status through the service', () async {
      await paidTransaction(amount: 100);
      await service.createOrder(gateway: PaymentGatewayName.razorpay, amount: 200);

      expect((await service.getTransactions(status: GatewayTransactionStatus.success)).length, 1);
      expect((await service.getTransactions(status: GatewayTransactionStatus.pending)).length, 1);
      expect((await service.getTransactions()).length, 2);
    });
  });
}
