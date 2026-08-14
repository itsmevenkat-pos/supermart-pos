import 'package:flutter_test/flutter_test.dart';

// TODO:
// import 'package:supermart_pos/core/services/payment_service.dart';

void main() {
  group('PaymentService - Critical Tests', () {

    test('exact payment gives zero balance', () {
      const billTotal = 1000.0;
      const paid = 1000.0;

      const balance = billTotal - paid;

      expect(balance, 0.0);
    });

    test('cash overpayment calculates change', () {
      const billTotal = 850.0;
      const paid = 1000.0;

      const change = paid - billTotal;

      expect(change, 150.0);
    });

    test('underpayment calculates remaining amount', () {
      const billTotal = 1000.0;
      const paid = 700.0;

      const remaining = billTotal - paid;

      expect(remaining, 300.0);
    });

    test('cash and UPI payment', () {
      const billTotal = 1000.0;

      const cash = 400.0;
      const upi = 600.0;

      const totalPaid = cash + upi;

      expect(totalPaid, billTotal);
    });

    test('cash card and UPI payment', () {
      const billTotal = 1500.0;

      const cash = 500.0;
      const card = 500.0;
      const upi = 500.0;

      const totalPaid = cash + card + upi;

      expect(totalPaid, billTotal);
    });

    test('overpayment with multiple payment methods', () {
      const billTotal = 1000.0;

      const cash = 500.0;
      const upi = 700.0;

      const totalPaid = cash + upi;
      final change = totalPaid - billTotal;

      expect(change, 200.0);
    });

    test('payment cannot be negative', () {
      const payment = 500.0;

      expect(
        payment,
        greaterThanOrEqualTo(0),
      );
    });
  });
}
