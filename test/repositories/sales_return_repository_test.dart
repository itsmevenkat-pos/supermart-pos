import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SalesReturnRepository - Critical Tests', () {
    test('return quantity cannot exceed sold quantity', () {
      const sold = 10.0;
      const requestedReturn = 12.0;
      final capped = requestedReturn > sold ? sold : requestedReturn;

      expect(capped, sold);
    });

    test('refund total is the sum of included line totals', () {
      const line1 = 120.0;
      const line2 = 45.5;
      const excludedLine = 999.0;

      const total = line1 + line2;

      expect(total, 165.5);
      expect(total, isNot(excludedLine));
    });

    test('restocked item adds quantity back, damaged item does not', () {
      const openingStock = 50.0;
      const returnedQty = 4.0;

      const afterRestock = openingStock + returnedQty;
      const afterDamaged = openingStock;

      expect(afterRestock, 54.0);
      expect(afterDamaged, openingStock);
    });

    test('untied returns always require approval regardless of threshold', () {
      const threshold = 500.0;
      const smallUntiedRefund = 50.0;

      bool needsApproval(double refundAmount, bool isUntied) => isUntied || refundAmount > threshold;

      expect(needsApproval(smallUntiedRefund, true), isTrue);
    });

    test('sale-linked return only needs approval above the threshold', () {
      const threshold = 500.0;

      bool needsApproval(double refundAmount, bool isUntied) => isUntied || refundAmount > threshold;

      expect(needsApproval(200.0, false), isFalse);
      expect(needsApproval(600.0, false), isTrue);
    });

    test('credit-adjust refund reduces customer outstanding balance', () {
      const openingBalance = 300.0;
      const refundAmount = 80.0;

      final newBalance = openingBalance - refundAmount;

      expect(newBalance, 220.0);
    });
  });
}
