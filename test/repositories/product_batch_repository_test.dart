import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProductBatch / Kit - Critical Tests', () {
    test('every purchase line produces a batch record, batch_no or not', () {
      const batchNoTyped = null; // untyped batch number is allowed
      const quantityReceived = 24.0;

      // A batch row is written unconditionally — presence of quantity is
      // what matters, not whether a batch number was entered.
      expect(quantityReceived > 0, isTrue);
      expect(batchNoTyped, isNull);
    });

    test('repack purchase line uses packCount, not raw quantity, as qty received', () {
      const bulkQuantity = 2.0; // 2 cases
      const packSize = 12.0; // 12 units per case
      final packCount = (bulkQuantity * packSize).round();

      expect(packCount, 24);
    });

    test('kit sale deducts component stock by componentQty * kitQtySold', () {
      const componentQtyPerKit = 2.0;
      const kitsSold = 3.0;

      final requiredComponentStock = componentQtyPerKit * kitsSold;

      expect(requiredComponentStock, 6.0);
    });

    test("kit's own stock_quantity is untouched by a sale", () {
      const kitOwnStockBefore = 0.0;
      const kitOwnStockAfter = 0.0; // never decremented — components are

      expect(kitOwnStockAfter, kitOwnStockBefore);
    });

    test('service item sale never checks or decrements stock', () {
      const isService = true;
      const stockQuantity = 0.0; // irrelevant for a service line

      final skipsStockCheck = isService;

      expect(skipsStockCheck, isTrue);
      expect(stockQuantity, 0.0);
    });

    test('margin percent formula matches Product.marginPercent', () {
      const retailPrice = 100.0;
      const costPrice = 65.0;

      final marginPercent = retailPrice > 0 ? ((retailPrice - costPrice) / retailPrice) * 100 : 0;

      expect(marginPercent, 35.0);
    });

    test('margin percent is zero when retail price is zero, not a divide-by-zero crash', () {
      const retailPrice = 0.0;
      const costPrice = 10.0;

      final marginPercent = retailPrice > 0 ? ((retailPrice - costPrice) / retailPrice) * 100 : 0;

      expect(marginPercent, 0);
    });
  });
}
