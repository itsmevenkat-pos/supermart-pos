import '../models/promotion_model.dart';
import 'billing_service.dart' show CartItem;

class AppliedPromotion {
  final String promotionId;
  final String name;
  final double totalDiscount;
  const AppliedPromotion({required this.promotionId, required this.name, required this.totalDiscount});
}

class PromotionEngineResult {
  final Map<String, double> discountByProductId;
  final Map<String, String> labelByProductId;
  final List<AppliedPromotion> applied;

  const PromotionEngineResult({
    required this.discountByProductId,
    required this.labelByProductId,
    required this.applied,
  });

  static const empty = PromotionEngineResult(discountByProductId: {}, labelByProductId: {}, applied: []);

  double discountFor(String productId) => discountByProductId[productId] ?? 0;
  String? labelFor(String productId) => labelByProductId[productId];
  double get totalDiscount => discountByProductId.values.fold(0, (a, b) => a + b);
}

/// Auto-applies promotions to a cart. Deliberately simple, not a general
/// rules engine: each product line gets at most one promotion — the first
/// match in [activePromotions] order, no stacking — which covers "Buy N
/// get X% off", "Buy N get flat ₹ off", and "Buy N of X, get Y free" (only
/// when Y is already in the cart; this never auto-adds a line) without the
/// ambiguity of resolving multiple competing promotions on the same item.
class PromotionEngine {
  PromotionEngineResult compute({
    required List<CartItem> items,
    required List<Promotion> activePromotions,
  }) {
    if (items.isEmpty || activePromotions.isEmpty) return PromotionEngineResult.empty;

    final discountByProductId = <String, double>{};
    final labelByProductId = <String, String>{};
    final applied = <AppliedPromotion>[];
    // Product ids that already had a promotion applied this pass — a line
    // only ever gets one promotion, first match wins.
    final claimed = <String>{};

    double lineValueOf(CartItem item) =>
        (item.product.retailPrice * item.quantity - item.discountAmount).clamp(0, double.infinity);

    for (final promo in activePromotions) {
      // A promotion with neither scope set has nothing to trigger off —
      // deliberately not treated as "applies to everything", since that
      // would be a surprising blanket discount from a probably-incomplete
      // promotion setup.
      if (promo.productId == null && promo.categoryId == null) continue;

      final scopedItems = items.where((item) {
        if (claimed.contains(item.productId)) return false;
        if (promo.productId != null) return item.productId == promo.productId;
        return item.product.categoryId == promo.categoryId;
      }).toList();
      if (scopedItems.isEmpty) continue;

      final totalQty = scopedItems.fold<double>(0, (sum, i) => sum + i.quantity);
      if (totalQty < promo.minQuantity) continue;

      var promoTotal = 0.0;

      switch (promo.type) {
        case PromotionType.percentage:
          final pct = (promo.discountValue ?? 0).clamp(0, 100);
          if (pct <= 0) continue;
          for (final item in scopedItems) {
            final off = lineValueOf(item) * pct / 100;
            discountByProductId[item.productId] = off;
            labelByProductId[item.productId] = promo.name;
            claimed.add(item.productId);
            promoTotal += off;
          }

        case PromotionType.fixed:
          final flat = promo.discountValue ?? 0;
          if (flat <= 0) continue;
          final totalScopeValue = scopedItems.fold<double>(0, (s, i) => s + lineValueOf(i));
          if (totalScopeValue <= 0) continue;
          final cappedFlat = flat.clamp(0, totalScopeValue);
          for (final item in scopedItems) {
            // Distributed proportionally by each line's share of the
            // qualifying total, so the flat amount doesn't dump entirely
            // onto whichever line happens to be first.
            final share = (lineValueOf(item) / totalScopeValue) * cappedFlat;
            discountByProductId[item.productId] = share;
            labelByProductId[item.productId] = promo.name;
            claimed.add(item.productId);
            promoTotal += share;
          }

        case PromotionType.free_item:
          final freeId = promo.freeProductId;
          if (freeId == null) continue;
          CartItem? freeLine;
          for (final item in items) {
            if (item.productId == freeId && !claimed.contains(item.productId)) {
              freeLine = item;
              break;
            }
          }
          // The free product isn't in the cart — nothing to waive. This
          // engine never auto-adds a line on the customer's behalf.
          if (freeLine == null) continue;
          final off = freeLine.product.retailPrice.clamp(0.0, lineValueOf(freeLine));
          discountByProductId[freeLine.productId] = off;
          labelByProductId[freeLine.productId] = promo.name;
          claimed.add(freeLine.productId);
          promoTotal += off;
      }

      if (promoTotal > 0) {
        applied.add(AppliedPromotion(promotionId: promo.id, name: promo.name, totalDiscount: promoTotal));
      }
    }

    return PromotionEngineResult(
      discountByProductId: discountByProductId,
      labelByProductId: labelByProductId,
      applied: applied,
    );
  }
}
