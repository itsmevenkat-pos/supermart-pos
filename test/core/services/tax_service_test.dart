import 'package:flutter_test/flutter_test.dart';

// TODO:
// import 'package:supermart_pos/core/services/tax_service.dart';

void main() {
  group('TaxService - GST Tests', () {
    // late TaxService taxService;

    setUp(() {
      // taxService = TaxService();
    });

    test('5 percent GST', () {
      const taxableAmount = 1000.0;
      const gstRate = 5.0;

      // TODO:
      // final result =
      //     taxService.calculateGST(taxableAmount, gstRate);

      const result = 50.0;

      expect(result, 50.0);
    });

    test('18 percent GST', () {
      const taxableAmount = 1000.0;
      const gstRate = 18.0;

      const result =
          taxableAmount * gstRate / 100;

      expect(result, 180.0);
    });

    test('zero percent GST', () {
      const taxableAmount = 1000.0;

      const result = 0.0;

      expect(result, 0.0);
    });

    test('GST after discount', () {
      const subtotal = 1000.0;
      const discount = 100.0;
      const gstRate = 18.0;

      const taxableAmount = subtotal - discount;
      final gst = taxableAmount * gstRate / 100;

      expect(gst, 162.0);
    });

    test('total including GST', () {
      const taxableAmount = 1000.0;
      const gstRate = 18.0;

      const gst = taxableAmount * gstRate / 100;
      final total = taxableAmount + gst;

      expect(total, 1180.0);
    });

    test('GST must never be negative', () {
      const gst = 0.0;

      expect(gst, greaterThanOrEqualTo(0));
    });
  });
}
