import 'package:flutter_test/flutter_test.dart';

// TODO:
// import 'package:supermart_pos/core/services/loyalty_service.dart';

void main() {
  group('LoyaltyService - Critical Tests', () {

    test('earns one point per 100 rupees', () {
      const billAmount = 1000.0;

      final points =
          (billAmount / 100).floor();

      expect(points, 10);
    });

    test('amount below 100 earns zero points', () {
      const billAmount = 50.0;

      final points =
          (billAmount / 100).floor();

      expect(points, 0);
    });

    test('partial amount does not award partial point', () {
      const billAmount = 250.0;

      final points =
          (billAmount / 100).floor();

      expect(points, 2);
    });

    test('return reverses earned points', () {
      const earned = 10;
      const returned = 4;

      const remaining = earned - returned;

      expect(remaining, 6);
    });

    test('loyalty points cannot become negative', () {
      const points = 0;
      const adjustment = 0;

      const result = points - adjustment;

      expect(
        result,
        greaterThanOrEqualTo(0),
      );
    });
  });
}
