import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:supermart_pos/core/database/database_helper.dart';
import 'package:supermart_pos/models/payment_gateway_transaction_model.dart';
import 'package:supermart_pos/models/payment_settlement_model.dart';
import 'package:supermart_pos/repositories/payment_gateway_repository.dart';

class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this._path);
  final String _path;

  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late PaymentGatewayRepository repository;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('payment_gateway_repo_test');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
    await DatabaseHelper.instance.database;
  });

  tearDownAll(() async {
    await DatabaseHelper.instance.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  setUp(() async {
    repository = PaymentGatewayRepository();
    final db = await DatabaseHelper.instance.database;
    await db.delete('payment_gateway_transactions');
    await db.delete('payment_settlements');
    await db.delete('payments');
    await db.delete('sales');
  });

  /// `payments.sale_id` is a real foreign key, so a linked payment needs a
  /// sale that actually exists. Minimal row — only what the schema demands.
  Future<String> makeSale({int invoiceNo = 1, double netAmount = 500}) async {
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

  Future<String> makePayment({double amount = 500, String? saleId}) {
    return repository.createPayment(
      saleId: saleId,
      customerId: null,
      amount: amount,
      method: 'razorpay',
      referenceNo: 'order_ABC',
    );
  }

  group('payments (this repository is the table\'s first writer)', () {
    test('creates a payments row and reads it back', () async {
      final saleId = await makeSale();
      final id = await makePayment(amount: 1250.50, saleId: saleId);
      final row = await repository.getPayment(id);

      expect(row, isNotNull);
      expect(row!['amount'], 1250.50);
      expect(row['method'], 'razorpay');
      expect(row['sale_id'], saleId);
      expect(row['reference_no'], 'order_ABC');
    });

    test('a payment starts with no sale — the till collects before the sale exists', () async {
      final id = await makePayment();
      final row = await repository.getPayment(id);
      expect(row!['sale_id'], isNull);
    });

    test('attachSaleToPayment links the payment once the sale has been written', () async {
      final id = await makePayment();
      final saleId = await makeSale(invoiceNo: 7);

      await repository.attachSaleToPayment(id, saleId);

      expect((await repository.getPayment(id))!['sale_id'], saleId);
    });

    test('linking to a sale that does not exist is refused by the foreign key', () async {
      final id = await makePayment();
      // Better to fail loudly than to leave a payment pointing at a sale that
      // was never written.
      expect(
        () => repository.attachSaleToPayment(id, 'no-such-sale'),
        throwsA(anything),
      );
    });

    test('getPayment returns null for an unknown id', () async {
      expect(await repository.getPayment('nope'), isNull);
    });

    test('updatePaymentReference replaces the stored reference', () async {
      final id = await makePayment();
      await repository.updatePaymentReference(id, 'pay_XYZ');
      final row = await repository.getPayment(id);
      expect(row!['reference_no'], 'pay_XYZ');
    });
  });

  group('gateway transactions', () {
    test('creates and reads a transaction', () async {
      final paymentId = await makePayment();
      final created = await repository.createTransaction(
        PaymentGatewayTransaction.create(
          paymentId: paymentId,
          gateway: PaymentGatewayName.razorpay,
          gatewayOrderId: 'order_ABC',
        ),
      );

      final read = await repository.getTransaction(created.id);
      expect(read, isNotNull);
      expect(read!.gatewayOrderId, 'order_ABC');
      expect(read.status, GatewayTransactionStatus.pending);
      expect(read.completedAt, isNull);
      expect(read.paymentId, paymentId);
    });

    test('round-trips every field through toJson/fromJson', () async {
      final paymentId = await makePayment();
      final created = await repository.createTransaction(
        PaymentGatewayTransaction.create(
          paymentId: paymentId,
          gateway: PaymentGatewayName.razorpay,
          gatewayOrderId: 'order_ABC',
          gatewayTransactionId: 'pay_ABC',
          status: GatewayTransactionStatus.success,
          gatewayResponse: '{"status":"captured"}',
        ),
      );

      final read = await repository.getTransaction(created.id);
      expect(read, created);
    });

    test('looks a transaction up by the gateway payment id', () async {
      final paymentId = await makePayment();
      await repository.createTransaction(
        PaymentGatewayTransaction.create(
          paymentId: paymentId,
          gateway: PaymentGatewayName.razorpay,
          gatewayTransactionId: 'pay_LOOKUP',
        ),
      );

      final found = await repository.getByGatewayTransactionId('pay_LOOKUP');
      expect(found, isNotNull);
      expect(found!.gatewayTransactionId, 'pay_LOOKUP');
      expect(await repository.getByGatewayTransactionId('pay_MISSING'), isNull);
    });

    test('the gateway payment id is UNIQUE — a replayed callback cannot insert twice', () async {
      final first = await makePayment();
      final second = await makePayment();

      await repository.createTransaction(
        PaymentGatewayTransaction.create(
          paymentId: first,
          gateway: PaymentGatewayName.razorpay,
          gatewayTransactionId: 'pay_DUPLICATE',
        ),
      );

      // This is the database-level guarantee behind the service's friendlier
      // duplicate check: even if that check were bypassed, the shop cannot be
      // credited twice for one gateway payment.
      expect(
        () => repository.createTransaction(
          PaymentGatewayTransaction.create(
            paymentId: second,
            gateway: PaymentGatewayName.razorpay,
            gatewayTransactionId: 'pay_DUPLICATE',
          ),
        ),
        throwsA(anything),
      );
    });

    test('several pending transactions may coexist with no gateway payment id', () async {
      // NULLs do not collide in a UNIQUE index, which is what lets an order
      // exist before any payment id does.
      for (var i = 0; i < 3; i++) {
        final paymentId = await makePayment();
        await repository.createTransaction(
          PaymentGatewayTransaction.create(
            paymentId: paymentId,
            gateway: PaymentGatewayName.razorpay,
            gatewayOrderId: 'order_$i',
          ),
        );
      }
      expect((await repository.getTransactions()).length, 3);
    });

    test('looks a transaction up by order id and by payment id', () async {
      final paymentId = await makePayment();
      final created = await repository.createTransaction(
        PaymentGatewayTransaction.create(
          paymentId: paymentId,
          gateway: PaymentGatewayName.razorpay,
          gatewayOrderId: 'order_FIND',
        ),
      );

      expect((await repository.getByOrderId('order_FIND'))!.id, created.id);
      expect((await repository.getByPaymentId(paymentId))!.id, created.id);
      expect(await repository.getByOrderId('order_NOPE'), isNull);
    });

    test('markStatus moves the status and stamps a completion time', () async {
      final paymentId = await makePayment();
      final created = await repository.createTransaction(
        PaymentGatewayTransaction.create(
          paymentId: paymentId,
          gateway: PaymentGatewayName.razorpay,
          gatewayOrderId: 'order_ABC',
        ),
      );

      final when = DateTime(2025, 6, 1, 10, 30);
      await repository.markStatus(
        created.id,
        status: GatewayTransactionStatus.success,
        gatewayTransactionId: 'pay_OK',
        gatewayResponse: '{"status":"captured"}',
        completedAt: when,
      );

      final read = await repository.getTransaction(created.id);
      expect(read!.status, GatewayTransactionStatus.success);
      expect(read.gatewayTransactionId, 'pay_OK');
      expect(read.completedAtDateTime, when);
      expect(read.isTerminal, isTrue);
    });

    test('markStatus back to pending clears the completion time', () async {
      final paymentId = await makePayment();
      final created = await repository.createTransaction(
        PaymentGatewayTransaction.create(
          paymentId: paymentId,
          gateway: PaymentGatewayName.razorpay,
        ),
      );

      await repository.markStatus(created.id, status: GatewayTransactionStatus.success);
      expect((await repository.getTransaction(created.id))!.completedAt, isNotNull);

      await repository.markStatus(created.id, status: GatewayTransactionStatus.pending);
      expect((await repository.getTransaction(created.id))!.completedAt, isNull);
    });

    test('updateTransaction persists a whole changed row', () async {
      final paymentId = await makePayment();
      final created = await repository.createTransaction(
        PaymentGatewayTransaction.create(
          paymentId: paymentId,
          gateway: PaymentGatewayName.razorpay,
          gatewayOrderId: 'order_ABC',
        ),
      );

      await repository.updateTransaction(
        created.copyWith(
          status: GatewayTransactionStatus.refunded,
          gatewayTransactionId: 'pay_REFUNDED',
        ),
      );

      final read = await repository.getTransaction(created.id);
      expect(read!.status, GatewayTransactionStatus.refunded);
      expect(read.gatewayTransactionId, 'pay_REFUNDED');
      // The id must not have been rewritten by the update.
      expect(read.id, created.id);
    });

    test('filters transactions by gateway and status', () async {
      final a = await makePayment();
      final b = await makePayment();

      await repository.createTransaction(PaymentGatewayTransaction.create(
        paymentId: a,
        gateway: PaymentGatewayName.razorpay,
        gatewayTransactionId: 'pay_A',
        status: GatewayTransactionStatus.success,
      ));
      await repository.createTransaction(PaymentGatewayTransaction.create(
        paymentId: b,
        gateway: PaymentGatewayName.razorpay,
        gatewayTransactionId: 'pay_B',
        status: GatewayTransactionStatus.failed,
      ));

      final successes = await repository.getTransactions(
        gateway: PaymentGatewayName.razorpay,
        status: GatewayTransactionStatus.success,
      );
      expect(successes.length, 1);
      expect(successes.single.gatewayTransactionId, 'pay_A');

      expect(
        (await repository.getTransactions(gateway: PaymentGatewayName.paypal)).isEmpty,
        isTrue,
      );
    });

    test('filters transactions by created_at range, so pending ones stay visible', () async {
      final old = await makePayment();
      final recent = await makePayment();

      await repository.createTransaction(PaymentGatewayTransaction.create(
        paymentId: old,
        gateway: PaymentGatewayName.razorpay,
        gatewayOrderId: 'order_OLD',
        createdAt: DateTime(2025, 1, 1),
      ));
      await repository.createTransaction(PaymentGatewayTransaction.create(
        paymentId: recent,
        gateway: PaymentGatewayName.razorpay,
        gatewayOrderId: 'order_NEW',
        createdAt: DateTime(2025, 6, 1),
      ));

      final inRange = await repository.getTransactions(
        from: DateTime(2025, 5, 1),
        to: DateTime(2025, 7, 1),
      );
      expect(inRange.length, 1);
      // A pending transaction has no completed_at at all — ranging on
      // created_at is what keeps it findable.
      expect(inRange.single.gatewayOrderId, 'order_NEW');
      expect(inRange.single.completedAt, isNull);
    });
  });

  group('settlements', () {
    test('creates and reads a settlement', () async {
      final created = await repository.createSettlement(PaymentSettlement.create(
        gateway: PaymentGatewayName.razorpay,
        settlementDate: DateTime(2025, 6, 2),
        transactionCount: 12,
        totalAmount: 24000,
        feesCharged: 480,
        settledAmount: 23520,
        settlementReference: 'setl_ABC',
      ));

      final read = await repository.getSettlement(created.id);
      expect(read, created);
      expect(read!.settledAmount, 23520);
      expect(read.settlementReference, 'setl_ABC');
    });

    test('filters settlements by gateway and date range, newest first', () async {
      await repository.createSettlement(PaymentSettlement.create(
        gateway: PaymentGatewayName.razorpay,
        settlementDate: DateTime(2025, 6, 1),
        transactionCount: 1,
        totalAmount: 100,
        settledAmount: 98,
      ));
      await repository.createSettlement(PaymentSettlement.create(
        gateway: PaymentGatewayName.razorpay,
        settlementDate: DateTime(2025, 6, 5),
        transactionCount: 2,
        totalAmount: 200,
        settledAmount: 196,
      ));

      final all = await repository.getSettlements(gateway: PaymentGatewayName.razorpay);
      expect(all.length, 2);
      expect(all.first.settlementDateTime, DateTime(2025, 6, 5));

      final ranged = await repository.getSettlements(
        from: DateTime(2025, 6, 3),
        to: DateTime(2025, 6, 10),
      );
      expect(ranged.length, 1);
      expect(ranged.single.totalAmount, 200);
    });

    test('getSettlement returns null for an unknown id', () async {
      expect(await repository.getSettlement('nope'), isNull);
    });
  });
}
