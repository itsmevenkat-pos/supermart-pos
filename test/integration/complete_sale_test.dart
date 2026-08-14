import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Complete Sale Integration', () {

    test('product -> bill -> payment -> stock', () {

      // Product
      const price = 100.0;
      const quantity = 5.0;

      // Stock
      const openingStock = 20.0;

      // Billing
      const subtotal =
          price * quantity;

      expect(subtotal, 500.0);

      // Discount
      const discountPercent = 10.0;

      final discount =
          subtotal *
              discountPercent /
              100;

      expect(discount, 50.0);

      // Tax
      final taxableAmount =
          subtotal - discount;

      const gstRate = 18.0;

      final gst =
          taxableAmount *
              gstRate /
              100;

      // Grand total
      final grandTotal =
          taxableAmount + gst;

      expect(grandTotal, 531.0);

      // Payment
      const payment = 531.0;

      final balance =
          grandTotal - payment;

      expect(balance, 0.0);

      // Stock
      const closingStock =
          openingStock - quantity;

      expect(closingStock, 15.0);
    });
  });
}
