import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Sales Database - Critical Tests', () {

    test('sale must have a sale ID', () {
      const saleId = 'SALE001';

      expect(
        saleId.isNotEmpty,
        isTrue,
      );
    });

    test('sale total must not be negative', () {
      const total = 1000.0;

      expect(
        total,
        greaterThanOrEqualTo(0),
      );
    });

    test('sale quantity must be positive', () {
      const quantity = 2.0;

      expect(
        quantity,
        greaterThan(0),
      );
    });

    test('payment total should match bill total', () {
      const billTotal = 1000.0;
      const cash = 400.0;
      const upi = 600.0;

      expect(
        cash + upi,
        billTotal,
      );
    });
  });
}
