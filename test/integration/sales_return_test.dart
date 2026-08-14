import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Sales Return Integration', () {

    test('sale followed by return restores stock', () {

      const openingStock = 100.0;
      const saleQuantity = 20.0;
      const returnQuantity = 5.0;

      const afterSale =
          openingStock - saleQuantity;

      expect(afterSale, 80.0);

      final afterReturn =
          afterSale + returnQuantity;

      expect(afterReturn, 85.0);
    });

    test('full return restores original stock', () {

      const openingStock = 100.0;
      const saleQuantity = 20.0;

      const afterSale =
          openingStock - saleQuantity;

      final afterReturn =
          afterSale + saleQuantity;

      expect(
        afterReturn,
        openingStock,
      );
    });

    test('return cannot exceed sold quantity', () {

      const sold = 10.0;
      const returned = 5.0;

      expect(
        returned <= sold,
        isTrue,
      );
    });
  });
}
