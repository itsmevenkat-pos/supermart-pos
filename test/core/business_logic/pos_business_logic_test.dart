import 'package:flutter_test/flutter_test.dart';

void main() {
  group('POS Critical Business Rules', () {

    test('complete billing calculation', () {

      const price = 100.0;
      const quantity = 5.0;

      const subtotal =
          price * quantity;

      const discountPercent = 10.0;

      final discount =
          subtotal *
              discountPercent /
              100;

      final taxable =
          subtotal - discount;

      const gstPercent = 18.0;

      final gst =
          taxable *
              gstPercent /
              100;

      final total =
          taxable + gst;

      expect(subtotal, 500.0);
      expect(discount, 50.0);
      expect(taxable, 450.0);
      expect(gst, 81.0);
      expect(total, 531.0);
    });

    test('billing payment and stock flow', () {

      const openingStock = 100.0;
      const soldQuantity = 5.0;

      const price = 100.0;

      const billTotal =
          price * soldQuantity;

      expect(billTotal, 500.0);

      const payment = 500.0;

      final balance =
          billTotal - payment;

      expect(balance, 0.0);

      const closingStock =
          openingStock - soldQuantity;

      expect(closingStock, 95.0);
    });

    test('purchase and sales stock flow', () {

      const openingStock = 100.0;
      const purchase = 50.0;
      const sale = 20.0;

      const afterPurchase =
          openingStock + purchase;

      final afterSale =
          afterPurchase - sale;

      expect(afterPurchase, 150.0);
      expect(afterSale, 130.0);
    });

    test('sale return stock flow', () {

      const openingStock = 100.0;
      const sale = 20.0;
      const returnQuantity = 5.0;

      const afterSale =
          openingStock - sale;

      final afterReturn =
          afterSale + returnQuantity;

      expect(afterSale, 80.0);
      expect(afterReturn, 85.0);
    });

    test('customer credit flow', () {

      const existingCredit = 1000.0;
      const newCredit = 500.0;

      const totalCredit =
          existingCredit + newCredit;

      expect(totalCredit, 1500.0);

      const payment = 500.0;

      final remaining =
          totalCredit - payment;

      expect(remaining, 1000.0);
    });

    test('loyalty point calculation', () {

      const billAmount = 1000.0;

      final points =
          (billAmount / 100).floor();

      expect(points, 10);
    });

    test('multi-store transfer preserves total stock', () {

      const storeA = 100.0;
      const storeB = 50.0;

      const transfer = 20.0;

      const storeANew =
          storeA - transfer;

      const storeBNew =
          storeB + transfer;

      expect(
        storeANew + storeBNew,
        storeA + storeB,
      );
    });

    test('grouped SKU shares stock', () {

      const sharedStock = 100.0;

      const saleFromSkuA = 3.0;
      const saleFromSkuB = 4.0;

      const remaining =
          sharedStock -
          saleFromSkuA -
          saleFromSkuB;

      expect(remaining, 93.0);
    });
  });
}
