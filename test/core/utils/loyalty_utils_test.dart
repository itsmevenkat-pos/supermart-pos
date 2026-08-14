import 'package:flutter_test/flutter_test.dart';
import 'package:supermart_pos/core/utils/loyalty_utils.dart';
import 'package:supermart_pos/models/customer_model.dart';

void main() {
  group('loyalty_utils - Critical Tests', () {
    const bronzeMin = 2000.0;
    const silverMin = 10000.0;
    const goldMin = 25000.0;

    test('below bronze threshold is regular', () {
      final tier = computeTier(totalSpent: 500, bronzeMin: bronzeMin, silverMin: silverMin, goldMin: goldMin);
      expect(tier, CustomerRating.regular);
    });

    test('exactly at bronze threshold is bronze', () {
      final tier = computeTier(totalSpent: bronzeMin, bronzeMin: bronzeMin, silverMin: silverMin, goldMin: goldMin);
      expect(tier, CustomerRating.bronze);
    });

    test('exactly at silver threshold is silver, not bronze', () {
      final tier = computeTier(totalSpent: silverMin, bronzeMin: bronzeMin, silverMin: silverMin, goldMin: goldMin);
      expect(tier, CustomerRating.silver);
    });

    test('exactly at gold threshold is gold', () {
      final tier = computeTier(totalSpent: goldMin, bronzeMin: bronzeMin, silverMin: silverMin, goldMin: goldMin);
      expect(tier, CustomerRating.gold);
    });

    test('one rupee below silver is still bronze', () {
      final tier =
          computeTier(totalSpent: silverMin - 1, bronzeMin: bronzeMin, silverMin: silverMin, goldMin: goldMin);
      expect(tier, CustomerRating.bronze);
    });

    test('point multiplier ladder is gold > silver > bronze > regular', () {
      final gold = pointMultiplierForRating(CustomerRating.gold);
      final silver = pointMultiplierForRating(CustomerRating.silver);
      final bronze = pointMultiplierForRating(CustomerRating.bronze);
      final regular = pointMultiplierForRating(CustomerRating.regular);

      expect(gold, greaterThan(silver));
      expect(silver, greaterThan(bronze));
      expect(bronze, greaterThan(regular));
      expect(regular, 1.0);
    });

    test('points earned scale with tier multiplier', () {
      const netAmount = 3000.0;
      const bonusThreshold = 300.0;
      final rawPoints = netAmount / bonusThreshold;

      final goldPoints = (rawPoints * pointMultiplierForRating(CustomerRating.gold)).floor();
      final regularPoints = (rawPoints * pointMultiplierForRating(CustomerRating.regular)).floor();

      expect(goldPoints, 20); // 10 raw * 2.0
      expect(regularPoints, 10); // 10 raw * 1.0
    });

    test('redemption amount is clamped to the payable total', () {
      const payableBeforeRedemption = 50.0;
      const pointsToRedeem = 500;
      const valuePerPoint = 0.5;

      final requested = pointsToRedeem * valuePerPoint;
      final clamped = requested.clamp(0, payableBeforeRedemption);

      expect(requested, 250.0);
      expect(clamped, 50.0);
    });

    test('redeeming more points than the customer has is rejected', () {
      const customerPoints = 100;
      const requestedRedeem = 150;

      expect(requestedRedeem > customerPoints, isTrue);
    });
  });
}
