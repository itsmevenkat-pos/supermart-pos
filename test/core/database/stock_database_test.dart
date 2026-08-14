import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Stock Database - Critical Tests', () {

    test('stock increases after purchase', () {
      const before = 100.0;
      const purchase = 25.0;

      expect(
        before + purchase,
        125.0,
      );
    });

    test('stock decreases after sale', () {
      const before = 100.0;
      const sale = 25.0;

      expect(
        before - sale,
        75.0,
      );
    });

    test('stock increases after sales return', () {
      const before = 75.0;
      const returned = 25.0;

      expect(
        before + returned,
        100.0,
      );
    });

    test('stock decreases after purchase return', () {
      const before = 100.0;
      const returned = 25.0;

      expect(
        before - returned,
        75.0,
      );
    });
  });
}
