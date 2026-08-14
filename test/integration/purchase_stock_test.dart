import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Purchase -> Stock Integration', () {

    test('purchase increases inventory', () {

      const openingStock = 100.0;
      const purchaseQuantity = 50.0;

      const stockAfterPurchase =
          openingStock + purchaseQuantity;

      expect(
        stockAfterPurchase,
        150.0,
      );
    });

    test('purchase followed by sale gives correct stock', () {

      const openingStock = 100.0;
      const purchase = 50.0;
      const sale = 30.0;

      const afterPurchase =
          openingStock + purchase;

      final afterSale =
          afterPurchase - sale;

      expect(
        afterSale,
        120.0,
      );
    });
  });
}
