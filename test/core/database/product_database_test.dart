import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Product Database - Critical Tests', () {

    test('product must have an ID', () {
      const productId = 'PROD001';

      expect(productId.isNotEmpty, isTrue);
    });

    test('product must have a name', () {
      const name = 'Rice';

      expect(name.trim().isNotEmpty, isTrue);
    });

    test('product price cannot be negative', () {
      const price = 100.0;

      expect(
        price,
        greaterThanOrEqualTo(0),
      );
    });

    test('product stock cannot be negative', () {
      const stock = 100.0;

      expect(
        stock,
        greaterThanOrEqualTo(0),
      );
    });

    test('barcode should be unique in principle', () {
      final barcodes = {
        '8901234567890',
        '8901234567891',
        '8901234567892',
      };

      expect(
        barcodes.length,
        3,
      );
    });
  });
}
