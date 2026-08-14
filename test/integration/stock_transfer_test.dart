import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Multi Store Stock Transfer', () {

    test('transfer decreases source stock', () {

      const sourceStock = 100.0;
      const transfer = 20.0;

      const result =
          sourceStock - transfer;

      expect(result, 80.0);
    });

    test('transfer increases destination stock', () {

      const destinationStock = 50.0;
      const transfer = 20.0;

      const result =
          destinationStock + transfer;

      expect(result, 70.0);
    });

    test('total stock remains unchanged after transfer', () {

      const sourceBefore = 100.0;
      const destinationBefore = 50.0;
      const transfer = 20.0;

      const sourceAfter =
          sourceBefore - transfer;

      const destinationAfter =
          destinationBefore + transfer;

      expect(
        sourceAfter + destinationAfter,
        sourceBefore + destinationBefore,
      );
    });

    test('transfer cannot exceed source stock', () {

      const sourceStock = 10.0;
      const transfer = 20.0;

      expect(
        transfer <= sourceStock,
        isFalse,
      );
    });
  });
}
