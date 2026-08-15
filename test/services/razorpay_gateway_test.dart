import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:supermart_pos/models/payment_gateway_transaction_model.dart';
import 'package:supermart_pos/services/gateways/payment_gateway.dart';
import 'package:supermart_pos/services/gateways/razorpay_gateway.dart';
import 'package:supermart_pos/services/gateways/stub_gateways.dart';

/// Every test here runs against canned responses — nothing in this file talks
/// to Razorpay, and no real key is needed to run the suite.
void main() {
  const keyId = 'rzp_test_key';
  const keySecret = 'rzp_test_secret';

  /// Signs the way Razorpay does, so the "valid signature" tests are checking
  /// the implementation against the documented rule rather than against
  /// itself.
  String sign(String orderId, String paymentId) {
    return Hmac(sha256, utf8.encode(keySecret)).convert(utf8.encode('$orderId|$paymentId')).toString();
  }

  RazorpayGateway gatewayWith(
    Future<http.Response> Function(http.Request request) handler, {
    String secret = keySecret,
  }) {
    return RazorpayGateway(
      keyId: keyId,
      keySecret: secret,
      client: MockClient(handler),
    );
  }

  group('configuration', () {
    test('is configured only when both key id and secret are present', () {
      expect(RazorpayGateway(keyId: keyId, keySecret: keySecret).isConfigured, isTrue);
      expect(RazorpayGateway(keyId: '', keySecret: keySecret).isConfigured, isFalse);
      expect(RazorpayGateway(keyId: keyId, keySecret: '   ').isConfigured, isFalse);
    });

    test('refuses to act at all without credentials', () async {
      final gateway = RazorpayGateway(keyId: '', keySecret: '');
      expect(
        () => gateway.createOrder(amount: 100, receipt: 'sale-1'),
        throwsA(isA<GatewayNotConfigured>()),
      );
      expect(
        () => gateway.getStatus('pay_ABC'),
        throwsA(isA<GatewayNotConfigured>()),
      );
    });

    test('reports itself as razorpay', () {
      expect(RazorpayGateway(keyId: keyId, keySecret: keySecret).name, PaymentGatewayName.razorpay);
    });
  });

  group('createOrder', () {
    test('sends the amount in paise and returns the order in rupees', () async {
      late Map<String, dynamic> sentBody;
      final gateway = gatewayWith((request) async {
        sentBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({'id': 'order_ABC', 'amount': 125050, 'currency': 'INR'}),
          200,
        );
      });

      final order = await gateway.createOrder(amount: 1250.50, receipt: 'sale-1');

      // The wire is in paise; nothing outside this class ever sees that.
      expect(sentBody['amount'], 125050);
      expect(sentBody['currency'], 'INR');
      expect(sentBody['receipt'], 'sale-1');
      expect(order.orderId, 'order_ABC');
      expect(order.amount, 1250.50);
    });

    test('rounds sub-paise amounts rather than truncating them', () async {
      late Map<String, dynamic> sentBody;
      final gateway = gatewayWith((request) async {
        sentBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(jsonEncode({'id': 'order_ABC', 'amount': 1001}), 200);
      });

      // ₹10.005 truncates to ₹10.00 and undercharges; rounding is the lesser
      // error and matches how the bill total is displayed.
      await gateway.createOrder(amount: 10.005, receipt: 'sale-1');
      expect(sentBody['amount'], 1001);
    });

    test('authenticates with HTTP basic auth over key id and secret', () async {
      late String authHeader;
      final gateway = gatewayWith((request) async {
        authHeader = request.headers['Authorization'] ?? '';
        return http.Response(jsonEncode({'id': 'order_ABC', 'amount': 10000}), 200);
      });

      await gateway.createOrder(amount: 100, receipt: 'sale-1');

      expect(authHeader.startsWith('Basic '), isTrue);
      expect(
        utf8.decode(base64Decode(authHeader.substring('Basic '.length))),
        '$keyId:$keySecret',
      );
    });

    test('truncates a receipt longer than Razorpay accepts', () async {
      late Map<String, dynamic> sentBody;
      final gateway = gatewayWith((request) async {
        sentBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(jsonEncode({'id': 'order_ABC', 'amount': 10000}), 200);
      });

      await gateway.createOrder(amount: 100, receipt: 'x' * 60);
      expect((sentBody['receipt'] as String).length, 40);
    });

    test('rejects a zero or negative order before making any call', () async {
      var called = false;
      final gateway = gatewayWith((request) async {
        called = true;
        return http.Response('{}', 200);
      });

      expect(
        () => gateway.createOrder(amount: 0, receipt: 'sale-1'),
        throwsA(isA<PaymentGatewayException>()),
      );
      expect(called, isFalse);
    });

    test('surfaces a Razorpay error body as a PaymentGatewayException', () async {
      final gateway = gatewayWith((request) async {
        return http.Response(
          jsonEncode({
            'error': {'code': 'BAD_REQUEST_ERROR', 'description': 'Amount exceeds maximum'}
          }),
          400,
        );
      });

      await expectLater(
        gateway.createOrder(amount: 100, receipt: 'sale-1'),
        throwsA(isA<PaymentGatewayException>()
            .having((e) => e.gatewayCode, 'gatewayCode', 'BAD_REQUEST_ERROR')
            .having((e) => e.statusCode, 'statusCode', 400)
            .having((e) => e.message, 'message', contains('Amount exceeds maximum'))),
      );
    });

    test('survives a non-JSON error body without a parse crash', () async {
      final gateway = gatewayWith((request) async => http.Response('<html>502 Bad Gateway</html>', 502));

      await expectLater(
        gateway.createOrder(amount: 100, receipt: 'sale-1'),
        throwsA(isA<PaymentGatewayException>().having((e) => e.statusCode, 'statusCode', 502)),
      );
    });

    test('a 200 with no order id is still a failure', () async {
      final gateway = gatewayWith((request) async => http.Response(jsonEncode({'amount': 10000}), 200));

      await expectLater(
        gateway.createOrder(amount: 100, receipt: 'sale-1'),
        throwsA(isA<PaymentGatewayException>().having((e) => e.message, 'message', contains('no order id'))),
      );
    });

    test('wraps a transport failure rather than leaking it', () async {
      final gateway = gatewayWith((request) async => throw const SocketExceptionStub());

      await expectLater(
        gateway.createOrder(amount: 100, receipt: 'sale-1'),
        throwsA(isA<PaymentGatewayException>().having((e) => e.message, 'message', contains('Could not reach'))),
      );
    });
  });

  group('signature verification', () {
    test('computes the documented HMAC-SHA256 over "order_id|payment_id"', () {
      final gateway = RazorpayGateway(keyId: keyId, keySecret: keySecret);
      expect(
        gateway.expectedSignature(orderId: 'order_ABC', gatewayTransactionId: 'pay_ABC'),
        sign('order_ABC', 'pay_ABC'),
      );
    });

    test('a wrong signature fails without ever asking the gateway', () async {
      var called = false;
      final gateway = gatewayWith((request) async {
        called = true;
        return http.Response(jsonEncode({'id': 'pay_ABC', 'status': 'captured'}), 200);
      });

      final result = await gateway.verifyPayment(
        orderId: 'order_ABC',
        gatewayTransactionId: 'pay_ABC',
        signature: 'not-the-right-signature',
      );

      expect(result.isValid, isFalse);
      expect(result.signatureValid, isFalse);
      expect(result.failureReason, contains('Signature'));
      // Never asks about a payment id it has no reason to trust.
      expect(called, isFalse);
    });

    test('a signature from the wrong secret does not verify', () async {
      final gateway = gatewayWith(
        (request) async => http.Response(jsonEncode({'id': 'pay_ABC', 'status': 'captured'}), 200),
        secret: 'a-different-secret',
      );

      final result = await gateway.verifyPayment(
        orderId: 'order_ABC',
        gatewayTransactionId: 'pay_ABC',
        signature: sign('order_ABC', 'pay_ABC'),
      );

      expect(result.isValid, isFalse);
      expect(result.signatureValid, isFalse);
    });

    test('a valid signature over a captured payment verifies', () async {
      final gateway = gatewayWith((request) async {
        expect(request.url.path, contains('/payments/pay_ABC'));
        return http.Response(
          jsonEncode({'id': 'pay_ABC', 'status': 'captured', 'amount': 125050}),
          200,
        );
      });

      final result = await gateway.verifyPayment(
        orderId: 'order_ABC',
        gatewayTransactionId: 'pay_ABC',
        signature: sign('order_ABC', 'pay_ABC'),
      );

      expect(result.isValid, isTrue);
      expect(result.signatureValid, isTrue);
      expect(result.status, GatewayTransactionStatus.success);
      expect(result.amount, 1250.50);
    });

    test('a valid signature over a failed payment does NOT verify', () async {
      final gateway = gatewayWith(
        (request) async => http.Response(jsonEncode({'id': 'pay_ABC', 'status': 'failed'}), 200),
      );

      final result = await gateway.verifyPayment(
        orderId: 'order_ABC',
        gatewayTransactionId: 'pay_ABC',
        signature: sign('order_ABC', 'pay_ABC'),
      );

      // The signature proves who sent the callback, not that money moved.
      expect(result.signatureValid, isTrue);
      expect(result.isValid, isFalse);
      expect(result.status, GatewayTransactionStatus.failed);
    });

    test('an authorized-but-not-captured payment is pending, not success', () async {
      final gateway = gatewayWith(
        (request) async => http.Response(jsonEncode({'id': 'pay_ABC', 'status': 'authorized'}), 200),
      );

      final result = await gateway.verifyPayment(
        orderId: 'order_ABC',
        gatewayTransactionId: 'pay_ABC',
        signature: sign('order_ABC', 'pay_ABC'),
      );

      // Money is held, not taken — settling a sale on this would let a
      // customer leave on an authorisation that is never captured.
      expect(result.status, GatewayTransactionStatus.pending);
      expect(result.isValid, isFalse);
    });
  });

  group('getStatus', () {
    test('maps Razorpay states onto this app\'s four', () async {
      Future<GatewayTransactionStatus> statusFor(String razorpayStatus) async {
        final gateway = gatewayWith(
          (request) async => http.Response(jsonEncode({'id': 'pay_ABC', 'status': razorpayStatus}), 200),
        );
        return (await gateway.getStatus('pay_ABC')).status;
      }

      expect(await statusFor('captured'), GatewayTransactionStatus.success);
      expect(await statusFor('failed'), GatewayTransactionStatus.failed);
      expect(await statusFor('refunded'), GatewayTransactionStatus.refunded);
      expect(await statusFor('created'), GatewayTransactionStatus.pending);
      expect(await statusFor('authorized'), GatewayTransactionStatus.pending);
      expect(await statusFor('something_new'), GatewayTransactionStatus.pending);
    });

    test('surfaces an HTTP failure', () async {
      final gateway = gatewayWith(
        (request) async => http.Response(
          jsonEncode({
            'error': {'code': 'NOT_FOUND', 'description': 'no such payment'}
          }),
          404,
        ),
      );

      await expectLater(gateway.getStatus('pay_NOPE'), throwsA(isA<PaymentGatewayException>()));
    });
  });

  group('refund', () {
    test('a full refund sends no amount', () async {
      late Map<String, dynamic> sentBody;
      final gateway = gatewayWith((request) async {
        expect(request.url.path, contains('/payments/pay_ABC/refund'));
        sentBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(jsonEncode({'id': 'rfnd_ABC', 'amount': 125050}), 200);
      });

      final refund = await gateway.refund(gatewayTransactionId: 'pay_ABC');

      expect(sentBody.containsKey('amount'), isFalse);
      expect(refund.refundId, 'rfnd_ABC');
      expect(refund.amount, 1250.50);
    });

    test('a partial refund sends the amount in paise', () async {
      late Map<String, dynamic> sentBody;
      final gateway = gatewayWith((request) async {
        sentBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(jsonEncode({'id': 'rfnd_ABC', 'amount': 50000}), 200);
      });

      await gateway.refund(gatewayTransactionId: 'pay_ABC', amount: 500);
      expect(sentBody['amount'], 50000);
    });

    test('rejects a non-positive refund amount', () async {
      final gateway = gatewayWith((request) async => http.Response('{}', 200));
      expect(
        () => gateway.refund(gatewayTransactionId: 'pay_ABC', amount: 0),
        throwsA(isA<PaymentGatewayException>()),
      );
    });

    test('a 200 with no refund id is still a failure', () async {
      final gateway = gatewayWith((request) async => http.Response(jsonEncode({'amount': 100}), 200));
      await expectLater(
        gateway.refund(gatewayTransactionId: 'pay_ABC'),
        throwsA(isA<PaymentGatewayException>()),
      );
    });
  });

  group('unimplemented gateways', () {
    test('PayPal and Square are never configured, so the till never offers them', () {
      expect(const PayPalGateway().isConfigured, isFalse);
      expect(const SquareGateway().isConfigured, isFalse);
      expect(const PayPalGateway().name, PaymentGatewayName.paypal);
      expect(const SquareGateway().name, PaymentGatewayName.square);
    });

    test('every operation throws UnimplementedError rather than faking success', () async {
      for (final gateway in <PaymentGateway>[const PayPalGateway(), const SquareGateway()]) {
        await expectLater(
          gateway.createOrder(amount: 100, receipt: 'sale-1'),
          throwsA(isA<UnimplementedError>()),
        );
        await expectLater(
          gateway.verifyPayment(orderId: 'o', gatewayTransactionId: 'p', signature: 's'),
          throwsA(isA<UnimplementedError>()),
        );
        await expectLater(
          gateway.refund(gatewayTransactionId: 'p'),
          throwsA(isA<UnimplementedError>()),
        );
        await expectLater(
          gateway.getStatus('p'),
          throwsA(isA<UnimplementedError>()),
        );
      }
    });
  });
}

/// Stands in for a network failure without importing dart:io into a test that
/// otherwise has no need of it.
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
  @override
  String toString() => 'connection refused';
}
