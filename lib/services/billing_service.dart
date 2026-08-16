import '../models/sale_model.dart';
import '../models/sale_item_model.dart';
import '../models/product_model.dart';
import '../repositories/sale_repository.dart';
import '../repositories/product_repository.dart';
import '../repositories/store_repository.dart';
import 'gst_service.dart';

class CartItem {
  final String productId;
  final double quantity;
  final Product product;
  final double discountAmount;
  /// Auto-computed by PromotionEngine — kept separate from [discountAmount]
  /// (the cashier's manual F2/line discount) so the UI can show them
  /// distinctly, even though both reduce the line's taxable amount the
  /// same way at checkout. See CartNotifier.setActivePromotions.
  final double promoDiscount;
  final String? promoLabel;

  CartItem({
    required this.productId,
    required this.quantity,
    required this.product,
    this.discountAmount = 0,
    this.promoDiscount = 0,
    this.promoLabel,
  });
}

class BillingService {
  final SaleRepository _saleRepo = SaleRepository();
  final ProductRepository _productRepo = ProductRepository();
  final GstService _gstService = GstService();

  Future<Sale> processSale({
    required String storeId,
    required String? sessionId,
    required String? userId,
    required List<CartItem> cartItems,
    required Map<String, double> payments,
    required double discountTotal,
    String? discountReason,
    double roundOff = 0,
    double? partialPaymentAmount,
    double? creditUsed,
    String? deliveryAddress,
    bool isDelivery = false,
    double deliveryCharge = 0,
    String? customerId,
    String? salesmanId,
    String? remarks,
    int loyaltyPointsRedeemed = 0,
  }) async {
    double subtotal = 0;
    double totalTax = 0;
    double totalLineDiscount = 0;
    final saleItems = <SaleItem>[];

    for (final cartItem in cartItems) {
      final product = await _productRepo.getById(cartItem.productId);
      if (product == null) throw Exception('Product not found: ${cartItem.productId}');

      final grossLine = product.retailPrice * cartItem.quantity;
      // Manual (F2/line) discount and auto-applied promotion discount both
      // reduce this line's taxable amount the same way — combined into one
      // SaleItem.discountAmount, same as the rest of this app treats
      // "discount" (see Sale.discountTotal, which likewise doesn't
      // distinguish bill-level from per-line). Which promotions applied is
      // available separately via CartNotifier.appliedPromotions for
      // display/receipt purposes, just not persisted as structured data on
      // the sale itself.
      final manualDiscount = cartItem.discountAmount.clamp(0, grossLine).toDouble();
      final promoDiscount = cartItem.promoDiscount.clamp(0, grossLine - manualDiscount).toDouble();
      final lineDiscount = manualDiscount + promoDiscount;
      final taxableAmount = grossLine - lineDiscount;
      final taxAmount = _gstService.calculateTax(
        amount: taxableAmount,
        taxRate: product.taxRate,
      );
      final lineTotal = taxableAmount + taxAmount;

      subtotal += grossLine;
      totalTax += taxAmount;
      totalLineDiscount += lineDiscount;

      saleItems.add(
        SaleItem.create(
          productId: product.id,
          quantity: cartItem.quantity,
          unitPrice: product.retailPrice,
          taxAmount: taxAmount,
          discountAmount: lineDiscount,
          totalPrice: lineTotal,
          costPrice: product.costPrice,
        ),
      );
    }

    // discountTotal is the bill-level discount (F2); per-line discounts are
    // separate and already baked into subtotal/taxTotal above. Both are
    // combined here so netAmount reflects the true amount owed either way.
    final payableBeforeRedemption = subtotal + totalTax + deliveryCharge - discountTotal - totalLineDiscount + roundOff;

    // Redemption amount is kept separate from discountTotal so reporting can
    // tell a cashier discount apart from a customer spending their own
    // points — clamped so it can never make the bill negative, same
    // defensive spirit as the per-line discount clamp above.
    double loyaltyRedemptionAmount = 0;
    if (loyaltyPointsRedeemed > 0) {
      final valuePerPoint = await StoreRepository().getLoyaltyValuePerPoint();
      loyaltyRedemptionAmount = (loyaltyPointsRedeemed * valuePerPoint).clamp(0, payableBeforeRedemption).toDouble();
    }
    final netAmount = payableBeforeRedemption - loyaltyRedemptionAmount;

    final sale = Sale.create(
      storeId: storeId,
      customerId: customerId,
      sessionId: sessionId,
      userId: userId,
      salesmanId: salesmanId,
      subtotal: subtotal,
      taxTotal: totalTax,
      discountTotal: discountTotal + totalLineDiscount,
      discountReason: discountReason,
      roundOff: roundOff,
      netAmount: netAmount,
      paymentMethods: payments,
      partialPaymentAmount: partialPaymentAmount,
      creditUsed: creditUsed,
      deliveryAddress: deliveryAddress,
      isDelivery: isDelivery,
      deliveryCharge: deliveryCharge,
      isCreditSale: creditUsed != null && creditUsed > 0,
      remarks: remarks,
      loyaltyPointsRedeemed: loyaltyPointsRedeemed,
      loyaltyRedemptionAmount: loyaltyRedemptionAmount,
    );

    await _saleRepo.insertSaleWithItems(
      sale: sale,
      items: saleItems,
      storeId: storeId,
      customerId: customerId,
    );

    return sale;
  }

  Future<Sale?> getSaleById(String id) => _saleRepo.getById(id);
  Future<List<SaleItem>> getSaleItems(String saleId) => _saleRepo.getItemsBySale(saleId);
  Future<List<Sale>> getRecentSales({int limit = 50}) => _saleRepo.getRecent(limit: limit);
}