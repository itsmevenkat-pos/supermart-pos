import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../../models/payment_gateway_transaction_model.dart';
import 'payment_gateway.dart';

/// Razorpay, the one gateway implemented for real.
///
/// **Money is passed around this class in rupees and converted to paise only
/// at the HTTP boundary.** Razorpay's API is entirely in the minor unit; the
/// rest of this app is entirely in rupees. Doing the conversion in exactly
/// two places ([_toPaise] and [_fromPaise]) is what keeps a factor-of-100
/// error from being possible anywhere else.
///
/// **Rounding.** [_toPaise] rounds rather than truncates. A bill of ₹10.005
/// (reachable through this app's tax maths) would truncate to ₹10.00 and
/// undercharge; rounding is the lesser error and matches how the bill total
/// is already displayed.
///
/// **Credentials** come from the caller ([keyId]/[keySecret]), read from the
/// store's settings — never from a constant in this repo. The secret is used
/// for HTTP basic auth and for the HMAC signature check.
///
/// The [http.Client] is injectable so the whole class can be tested against
/// canned responses without a network or a live key; nothing in the test
/// suite talks to Razorpay.
class RazorpayGateway implements PaymentGateway {
  static const String _baseUrl = 'https://api.razorpay.com/v1';

  final String keyId;
  final String keySecret;
  final http.Client _client;
  final Duration timeout;

  RazorpayGateway({
    required this.keyId,
    required this.keySecret,
    http.Client? client,
    this.timeout = const Duration(seconds: 30),
  }) : _client = client ?? http.Client();

  @override
  PaymentGatewayName get name => PaymentGatewayName.razorpay;

  @override
  bool get isConfigured => keyId.trim().isNotEmpty && keySecret.trim().isNotEmpty;

  // ------------------------------------------------------------ conversions

  /// Rupees to paise. See the class doc on why this rounds.
  static int _toPaise(double rupees) => (rupees * 100).round();

  static double _fromPaise(num paise) => paise / 100.0;

  Map<String, String> get _authHeaders => {
        'Authorization': 'Basic ${base64Encode(utf8.encode('$keyId:$keySecret'))}',
        'Content-Type': 'application/json',
      };

  void _requireConfigured() {
    if (!isConfigured) {
      throw const GatewayNotConfigured(
        PaymentGatewayName.razorpay,
        'Razorpay key id and secret are not set. Add them in Settings → Payment Gateways.',
      );
    }
  }

  /// Turns a Razorpay error body into a [PaymentGatewayException]. Razorpay
  /// nests its errors under `error`, but a proxy or an outage can return
  /// something else entirely — a non-JSON body must still produce a sensible
  /// exception rather than a parse crash.
  Never _throwHttp(http.Response response) {
    String message = 'HTTP ${response.statusCode}';
    String? code;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['error'] is Map) {
        final error = decoded['error'] as Map;
        message = (error['description'] as String?) ?? message;
        code = error['code'] as String?;
      }
    } catch (_) {
      // Non-JSON body (proxy error page, empty response) — keep the HTTP
      // status as the message rather than failing to report the failure.
    }
    throw PaymentGatewayException(
      PaymentGatewayName.razorpay,
      message,
      gatewayCode: code,
      statusCode: response.statusCode,
    );
  }

  /// Wraps transport-level failures so callers only ever have to catch
  /// [PaymentGatewayException]. A timeout or a dead network is
  /// indistinguishable from the shop's point of view: the payment's outcome
  /// is unknown and the sale must not be settled on it.
  Future<http.Response> _send(Future<http.Response> Function() request) async {
    try {
      return await request().timeout(timeout);
    } on PaymentGatewayException {
      rethrow;
    } catch (e) {
      throw PaymentGatewayException(
        PaymentGatewayName.razorpay,
        'Could not reach Razorpay: $e',
      );
    }
  }

  // --------------------------------------------------------------- ordering

  @override
  Future<GatewayOrder> createOrder({
    required double amount,
    required String receipt,
    String currency = 'INR',
  }) async {
    _requireConfigured();
    if (amount <= 0) {
      throw const PaymentGatewayException(
        PaymentGatewayName.razorpay,
        'Order amount must be greater than zero.',
      );
    }

    final response = await _send(() => _client.post(
          Uri.parse('$_baseUrl/orders'),
          headers: _authHeaders,
          body: jsonEncode({
            'amount': _toPaise(amount),
            'currency': currency,
            // Razorpay caps receipt at 40 characters and rejects longer ones.
            // Sale ids are UUIDs (36), so this only ever bites on a caller
            // passing something unusual — truncating beats a rejected order.
            'receipt': receipt.length > 40 ? receipt.substring(0, 40) : receipt,
          }),
        ));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwHttp(response);
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final orderId = body['id'] as String?;
    if (orderId == null) {
      throw PaymentGatewayException(
        PaymentGatewayName.razorpay,
        'Razorpay accepted the order but returned no order id.',
        statusCode: response.statusCode,
      );
    }

    return GatewayOrder(
      orderId: orderId,
      amount: body['amount'] is num ? _fromPaise(body['amount'] as num) : amount,
      currency: (body['currency'] as String?) ?? currency,
      rawResponse: response.body,
    );
  }

  // ----------------------------------------------------------- verification

  /// Razorpay's signature is `HMAC_SHA256("<order_id>|<payment_id>", secret)`.
  ///
  /// Exposed (rather than inlined into [verifyPayment]) because the signature
  /// rule is the one piece of this integration worth testing directly against
  /// Razorpay's published example.
  String expectedSignature({
    required String orderId,
    required String gatewayTransactionId,
  }) {
    final mac = Hmac(sha256, utf8.encode(keySecret));
    return mac.convert(utf8.encode('$orderId|$gatewayTransactionId')).toString();
  }

  /// Compares two signatures without leaking where they first differ.
  ///
  /// A plain `==` on strings short-circuits at the first differing byte,
  /// which is a (theoretical, here) timing oracle. The cost of doing it
  /// properly is one loop over 64 characters, so there is no reason not to.
  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var difference = 0;
    for (var i = 0; i < a.length; i++) {
      difference |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return difference == 0;
  }

  /// Verifies the callback signature locally, then asks Razorpay what the
  /// payment's real status is.
  ///
  /// Both halves matter. The signature proves the callback came from someone
  /// holding the shared secret; the status call proves the payment actually
  /// captured, which a valid signature on a *failed* payment would not. A bad
  /// signature short-circuits — this never asks the gateway about a payment
  /// id it has no reason to trust.
  @override
  Future<GatewayVerification> verifyPayment({
    required String orderId,
    required String gatewayTransactionId,
    required String signature,
  }) async {
    _requireConfigured();

    final expected = expectedSignature(
      orderId: orderId,
      gatewayTransactionId: gatewayTransactionId,
    );
    if (!_constantTimeEquals(expected, signature)) {
      return GatewayVerification(
        isValid: false,
        signatureValid: false,
        status: GatewayTransactionStatus.failed,
        gatewayTransactionId: gatewayTransactionId,
        rawResponse: jsonEncode({
          'verified': false,
          'reason': 'signature_mismatch',
          'order_id': orderId,
          'payment_id': gatewayTransactionId,
        }),
        failureReason: 'Signature did not match. This payment confirmation cannot be trusted.',
      );
    }

    final status = await getStatus(gatewayTransactionId);
    return GatewayVerification(
      isValid: status.status == GatewayTransactionStatus.success,
      status: status.status,
      gatewayTransactionId: gatewayTransactionId,
      amount: status.amount,
      rawResponse: status.rawResponse,
      failureReason: status.status == GatewayTransactionStatus.success
          ? null
          : 'Signature was valid but Razorpay reports the payment as ${status.status.name}.',
    );
  }

  @override
  Future<GatewayVerification> getStatus(String gatewayTransactionId) async {
    _requireConfigured();

    final response = await _send(() => _client.get(
          Uri.parse('$_baseUrl/payments/$gatewayTransactionId'),
          headers: _authHeaders,
        ));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwHttp(response);
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final status = _mapStatus(body['status'] as String?);

    return GatewayVerification(
      isValid: status == GatewayTransactionStatus.success,
      status: status,
      gatewayTransactionId: (body['id'] as String?) ?? gatewayTransactionId,
      amount: body['amount'] is num ? _fromPaise(body['amount'] as num) : null,
      rawResponse: response.body,
      failureReason: status == GatewayTransactionStatus.success ? null : 'Razorpay status: ${body['status']}',
    );
  }

  /// Razorpay's payment states, collapsed onto this app's four.
  ///
  /// `authorized` is money held but not yet taken. It is mapped to `pending`
  /// on purpose: the shop has not been paid, and treating it as success would
  /// let a customer walk out on an authorisation that is later never
  /// captured. This app only ever settles a sale on `captured`.
  static GatewayTransactionStatus _mapStatus(String? razorpayStatus) {
    switch (razorpayStatus) {
      case 'captured':
        return GatewayTransactionStatus.success;
      case 'refunded':
        return GatewayTransactionStatus.refunded;
      case 'failed':
        return GatewayTransactionStatus.failed;
      case 'created':
      case 'authorized':
      default:
        return GatewayTransactionStatus.pending;
    }
  }

  // ---------------------------------------------------------------- refunds

  @override
  Future<GatewayRefund> refund({
    required String gatewayTransactionId,
    double? amount,
  }) async {
    _requireConfigured();
    if (amount != null && amount <= 0) {
      throw const PaymentGatewayException(
        PaymentGatewayName.razorpay,
        'Refund amount must be greater than zero.',
      );
    }

    final response = await _send(() => _client.post(
          Uri.parse('$_baseUrl/payments/$gatewayTransactionId/refund'),
          headers: _authHeaders,
          // No amount means a full refund, which is what Razorpay does with
          // an empty body.
          body: jsonEncode(amount == null ? <String, dynamic>{} : {'amount': _toPaise(amount)}),
        ));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwHttp(response);
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final refundId = body['id'] as String?;
    if (refundId == null) {
      throw PaymentGatewayException(
        PaymentGatewayName.razorpay,
        'Razorpay accepted the refund but returned no refund id.',
        statusCode: response.statusCode,
      );
    }

    return GatewayRefund(
      refundId: refundId,
      amount: body['amount'] is num ? _fromPaise(body['amount'] as num) : (amount ?? 0),
      rawResponse: response.body,
    );
  }
}
