import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../models/product_model.dart';
import '../models/customer_model.dart';
import '../models/coupon_model.dart';
import '../models/promotion_model.dart';
import '../services/billing_service.dart';
import '../services/promotion_engine.dart';

part 'cart_provider.g.dart';

@riverpod
class Cart extends _$Cart {
  final List<CartItem> _items = [];
  Customer? _customer;
  double _discount = 0;
  String? _discountReason;
  String? _deliveryAddress;
  double _deliveryCharge = 0;
  int _loyaltyPointsToRedeem = 0;
  double _loyaltyRedemptionAmount = 0;
  List<Promotion> _activePromotions = [];
  PromotionEngineResult _promoResult = PromotionEngineResult.empty;
  Coupon? _appliedCoupon;
  double _couponDiscount = 0;

  @override
  List<CartItem> build() => [];

  void addItem(Product product, {double quantity = 1}) {
    final index = _items.indexWhere((e) => e.productId == product.id);
    if (index != -1) {
      _items[index] = CartItem(
        productId: product.id,
        quantity: _items[index].quantity + quantity,
        product: product,
        discountAmount: _items[index].discountAmount,
      );
    } else {
      _items.add(CartItem(
        productId: product.id,
        quantity: quantity,
        product: product,
      ));
    }
    _recomputePromotions();
    state = [..._items];
  }

  void removeItem(String productId) {
    _items.removeWhere((e) => e.productId == productId);
    _recomputePromotions();
    state = [..._items];
  }

  void updateQuantity(String productId, double newQuantity) {
    final index = _items.indexWhere((e) => e.productId == productId);
    if (index != -1) {
      if (newQuantity <= 0) {
        _items.removeAt(index);
      } else {
        _items[index] = CartItem(
          productId: productId,
          quantity: newQuantity,
          product: _items[index].product,
          discountAmount: _items[index].discountAmount,
        );
      }
      _recomputePromotions();
      state = [..._items];
    }
  }

  /// Per-line discount (₹ amount, not %) — separate from the bill-level
  /// discount set via setDiscount. Clamped so a line can never go negative.
  void updateLineDiscount(String productId, double discountAmount) {
    final index = _items.indexWhere((e) => e.productId == productId);
    if (index != -1) {
      final item = _items[index];
      final maxDiscount = item.product.retailPrice * item.quantity;
      _items[index] = CartItem(
        productId: productId,
        quantity: item.quantity,
        product: item.product,
        discountAmount: discountAmount.clamp(0, maxDiscount).toDouble(),
      );
      // A manual discount changes how much value is left for a percentage/
      // fixed promotion to apply to, so promotions need to re-run too.
      _recomputePromotions();
      state = [..._items];
    }
  }

  /// Called once by billing_screen after it loads today's active
  /// promotions (mirrors how categories/salesmen are loaded). Re-running
  /// this on every cart mutation (see _recomputePromotions call sites
  /// above) keeps auto-applied promotions current as items/quantities
  /// change, without billing_screen needing to know when to recheck.
  void setActivePromotions(List<Promotion> promotions) {
    _activePromotions = promotions;
    _recomputePromotions();
    state = [..._items];
  }

  void _recomputePromotions() {
    final result = PromotionEngine().compute(items: _items, activePromotions: _activePromotions);
    for (var i = 0; i < _items.length; i++) {
      final item = _items[i];
      _items[i] = CartItem(
        productId: item.productId,
        quantity: item.quantity,
        product: item.product,
        discountAmount: item.discountAmount,
        promoDiscount: result.discountFor(item.productId),
        promoLabel: result.labelFor(item.productId),
      );
    }
    _promoResult = result;
  }

  void setCustomer(Customer? customer) {
    _customer = customer;
    // A points redemption is tied to whichever customer it belongs to —
    // switching or clearing the customer must clear it too, otherwise a
    // leftover redemption from a previous customer could silently apply to
    // whoever's attached next.
    _loyaltyPointsToRedeem = 0;
    _loyaltyRedemptionAmount = 0;
    state = [..._items];
  }

  /// [amount] is computed by the caller (billing_screen, which has the
  /// store's ₹-per-point setting already loaded for display) so grandTotal
  /// can reflect it immediately — it's what the payment dialog and checkout
  /// both read, so it has to be the real payable amount, not just a point
  /// count with no monetary meaning until later.
  void setLoyaltyRedemption(int points, double amount) {
    _loyaltyPointsToRedeem = points;
    _loyaltyRedemptionAmount = amount;
    state = [..._items];
  }

  void setDiscount(double discount, {String? reason}) {
    _discount = discount;
    _discountReason = reason;
    state = [..._items];
  }

  /// [discountAmount] is what CouponRepository.validate already computed
  /// against the bill total at the moment of applying — a snapshot, not
  /// re-derived on every subsequent cart edit (same treatment as the F2
  /// bill-level discount above: applied once, stays put until removed).
  void applyCoupon(Coupon coupon, double discountAmount) {
    _appliedCoupon = coupon;
    _couponDiscount = discountAmount;
    state = [..._items];
  }

  void removeCoupon() {
    _appliedCoupon = null;
    _couponDiscount = 0;
    state = [..._items];
  }

  void setDelivery({String? address, double charge = 0}) {
    _deliveryAddress = address;
    _deliveryCharge = charge;
    state = [..._items];
  }

  void clearCart() {
    _items.clear();
    _customer = null;
    _discount = 0;
    _discountReason = null;
    _deliveryAddress = null;
    _deliveryCharge = 0;
    _loyaltyPointsToRedeem = 0;
    _loyaltyRedemptionAmount = 0;
    // Not resetting _activePromotions — those are today's active
    // promotions, loaded once per billing session, not part of this cart.
    _promoResult = PromotionEngineResult.empty;
    _appliedCoupon = null;
    _couponDiscount = 0;
    state = [];
  }

  double get lineDiscountTotal => _items.fold(0, (sum, item) => sum + item.discountAmount);
  double get promoDiscountTotal => _promoResult.totalDiscount;
  List<AppliedPromotion> get appliedPromotions => _promoResult.applied;
  double get subtotal => _items.fold(
        0,
        (sum, item) => sum + (item.product.retailPrice * item.quantity),
      );
  double get totalTax => _items.fold(
        0,
        (sum, item) {
          final gross = item.product.retailPrice * item.quantity;
          final taxable = gross - item.discountAmount - item.promoDiscount;
          return sum + ((taxable * item.product.taxRate) / 100);
        },
      );
  double get grandTotal =>
      subtotal +
      totalTax +
      _deliveryCharge -
      _discount -
      lineDiscountTotal -
      promoDiscountTotal -
      couponDiscount -
      _loyaltyRedemptionAmount;
  Customer? get customer => _customer;
  double get discount => _discount;
  String? get discountReason => _discountReason;
  String? get deliveryAddress => _deliveryAddress;
  double get deliveryCharge => _deliveryCharge;
  int get loyaltyPointsToRedeem => _loyaltyPointsToRedeem;
  double get loyaltyRedemptionAmount => _loyaltyRedemptionAmount;
  Coupon? get appliedCoupon => _appliedCoupon;
  double get couponDiscount => _couponDiscount;
  bool get isEmpty => _items.isEmpty;
  int get itemCount => _items.length;
}