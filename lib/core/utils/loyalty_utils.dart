import '../../models/customer_model.dart';

/// Auto-computes a customer's tier from lifetime spend against the store's
/// configurable thresholds (see `StoreRepository.getTierThresholds`). This
/// is what populates `Customer.rating` — separate from `ratingManualOverride`,
/// which always takes precedence via `Customer.effectiveRating` regardless
/// of what this function returns.
CustomerRating computeTier({
  required double totalSpent,
  required double bronzeMin,
  required double silverMin,
  required double goldMin,
}) {
  if (totalSpent >= goldMin) return CustomerRating.gold;
  if (totalSpent >= silverMin) return CustomerRating.silver;
  if (totalSpent >= bronzeMin) return CustomerRating.bronze;
  return CustomerRating.regular;
}

/// Fixed multiplier ladder applied to loyalty points earned on a sale — the
/// thing that genuinely varies store-to-store is the spend needed to reach
/// each tier (configurable, see [computeTier]); the multiplier itself is a
/// simple, fixed product decision.
double pointMultiplierForRating(CustomerRating rating) {
  switch (rating) {
    case CustomerRating.gold:
      return 2.0;
    case CustomerRating.silver:
      return 1.5;
    case CustomerRating.bronze:
      return 1.2;
    case CustomerRating.regular:
      return 1.0;
  }
}
