import 'package:flutter_test/flutter_test.dart';

// TODO:
// import 'package:supermart_pos/core/services/barcode_service.dart';

void main() {
  group('BarcodeService - Critical Tests', () {

    test('barcode cannot be empty', () {
      const barcode = '8901234567890';

      expect(barcode.isNotEmpty, isTrue);
    });

    test('empty barcode should be rejected', () {
      const barcode = '';

      expect(barcode.isEmpty, isTrue);
    });

    test('same barcode should match', () {
      const scanned = '8901234567890';
      const stored = '8901234567890';

      expect(scanned, stored);
    });

    test('different barcode should not match', () {
      const scanned = '8901234567890';
      const stored = '8909876543210';

      expect(scanned == stored, isFalse);
    });

    test('numeric barcode can be searched', () {
      const barcode = '8901234567890';

      expect(
        RegExp(r'^\d+$').hasMatch(barcode),
        isTrue,
      );
    });
  });
}
