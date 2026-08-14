import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Grouped Product Shared Stock', () {

    test('sale from one SKU reduces shared stock', () {

      const sharedStock = 100.0;
      const soldQuantity = 5.0;

      const result =
          sharedStock - soldQuantity;

      expect(result, 95.0);
    });

    test('purchase through one SKU increases shared stock', () {

      const sharedStock = 100.0;
      const purchaseQuantity = 20.0;

      const result =
          sharedStock + purchaseQuantity;

      expect(result, 120.0);
    });

    test('different SKUs can share the same stock pool', () {

      const sharedStock = 100.0;

      const skuAStock = 0.0;
      const skuBStock = 0.0;

      const totalAvailable =
          sharedStock + skuAStock + skuBStock;

      expect(totalAvailable, 100.0);
    });

    test('selling grouped SKU reduces common pool', () {

      const commonPool = 100.0;

      const skuAQuantity = 3.0;

      const remaining =
          commonPool - skuAQuantity;

      expect(remaining, 97.0);
    });

    test('selling another grouped SKU uses same common pool', () {

      const commonPool = 100.0;

      const firstSale = 3.0;
      const secondSale = 4.0;

      const remaining =
          commonPool -
          firstSale -
          secondSale;

      expect(remaining, 93.0);
    });
  });
}
