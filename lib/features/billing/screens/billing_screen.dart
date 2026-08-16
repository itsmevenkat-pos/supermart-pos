import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey, KeyEvent, KeyDownEvent, HardwareKeyboard, KeyboardLockMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../providers/cart_provider.dart';
import '../../../providers/product_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/sale_provider.dart';
import '../../../providers/quotation_provider.dart';
import '../../../providers/hold_provider.dart'; // ✅ Added for hold bills
import '../../../models/product_model.dart';
import '../../../models/quotation_model.dart';
import '../../../models/quotation_item_model.dart';
import '../../../models/customer_model.dart';
import '../../../models/category_model.dart';
import '../../../models/salesman_model.dart';
import '../../../repositories/category_repository.dart';
import '../../../repositories/salesman_repository.dart';
import '../../../repositories/store_repository.dart';
import '../../../repositories/promotion_repository.dart';
import '../../../repositories/coupon_repository.dart';
import '../../../services/billing_service.dart';
import '../../../services/whatsapp_share_service.dart';
import '../../../services/invoice_service.dart';
import '../../../services/thermal_print_service.dart';
import '../../../services/counter_service.dart';
import '../../../repositories/sale_repository.dart';
import '../widgets/product_grid.dart';
import '../widgets/cart_list_view.dart';
import '../widgets/payment_dialog.dart';
import '../widgets/quotation_dialog.dart';
import '../widgets/customer_picker_dialog.dart';
import '../../../core/permissions/price_override_guard.dart';
import '../../../core/utils/quantity_utils.dart';
import '../../../core/utils/weighing_barcode.dart';
import '../../holds/screens/hold_bills_screen.dart'; // ✅ Import holds screen
import '../../../services/payment_gateway_service.dart';

class BillingScreen extends ConsumerStatefulWidget {
  const BillingScreen({super.key});

  @override
  ConsumerState<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends ConsumerState<BillingScreen> {
  final TextEditingController _barcodeController = TextEditingController();
  final FocusNode _barcodeFocus = FocusNode();

  // Search-as-you-type state for the product search box.
  List<Product> _searchResults = [];
  int _highlightedIndex = -1;
  Timer? _searchDebounce;

  // One FocusNode per product so we can jump the cursor straight to a
  // cart line's quantity field right after it's added from search.
  final Map<String, FocusNode> _qtyFocusNodes = {};

  FocusNode _qtyFocusNodeFor(String productId) =>
      _qtyFocusNodes.putIfAbsent(productId, () => FocusNode());

  // Needed to check Category.allowNegativeStock before warning about
  // insufficient stock — categories like Dairy/Fruits & Veg allow it.
  List<Category> _categories = [];

  // Optional salesman attribution for the bill — purely additive, defaults
  // to unselected ("No Salesman") so existing billing flows are unaffected
  // when nobody picks one.
  List<Salesman> _salesmen = [];
  String? _selectedSalesmanId;

  // Free-text note printed/saved on the bill — e.g. "Gift wrap requested",
  // "Customer will collect Friday". Optional, cleared after each sale.

  // ₹ value of one loyalty point — fetched once and cached, same pattern as
  // _categories/_salesmen above, so the Redeem dialog doesn't need to await
  // a store-settings query on every open.
  double _loyaltyValuePerPoint = 0.5;

  @override
  void initState() {
    super.initState();
    _barcodeFocus.requestFocus();
    CategoryRepository().getAll().then((cats) {
      if (mounted) setState(() => _categories = cats);
    });
    ref.read(salesmanRepositoryProvider).getAll(activeOnly: true).then((salesmen) {
      if (mounted) setState(() => _salesmen = salesmen);
    });
    StoreRepository().getLoyaltyValuePerPoint().then((value) {
      if (mounted) setState(() => _loyaltyValuePerPoint = value);
    });
    // Feeds cart_provider's PromotionEngine — it recomputes on every cart
    // mutation from here on, this call just needs to happen once per
    // billing session (promotions don't change mid-sale).
    PromotionRepository().getActivePromotions().then((promotions) {
      if (mounted) ref.read(cartProvider.notifier).setActivePromotions(promotions);
    });
  }

  @override
  void dispose() {
    _barcodeController.dispose();
    _barcodeFocus.dispose();
    _searchDebounce?.cancel();
    for (final node in _qtyFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  /// Debounced fuzzy search (by name, alternate name, or barcode) as the
  /// cashier types — this is what was missing before; the box only ever
  /// did an exact barcode match, so partial names or typos returned nothing.
  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _highlightedIndex = -1;
      });
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 250), () async {
      final results = await ref.read(productNotifierProvider.notifier).search(query, activeOnly: true);
      if (!mounted) return;
      setState(() {
        _searchResults = results;
        _highlightedIndex = results.isEmpty ? -1 : 0;
      });
    });
  }

  /// Handles Arrow Up/Down to move the highlight, and Enter to add the
  /// highlighted product. Returning `handled` here is what stops Enter from
  /// falling through to the screen-wide Pay shortcut while you're searching.
  KeyEventResult _handleSearchKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_searchResults.isNotEmpty) {
        setState(() => _highlightedIndex = (_highlightedIndex + 1) % _searchResults.length);
      }
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (_searchResults.isNotEmpty) {
        setState(() => _highlightedIndex =
            (_highlightedIndex - 1 + _searchResults.length) % _searchResults.length);
      }
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      final text = _barcodeController.text.trim();
      if (_searchResults.isNotEmpty) {
        final index = _highlightedIndex >= 0 ? _highlightedIndex : 0;
        _selectProduct(_searchResults[index]);
        return KeyEventResult.handled;
      } else if (text.isNotEmpty) {
        // Fast barcode-gun scans can out-race the debounce timer above, so
        // fall back to an immediate exact lookup rather than saying
        // "not found" too eagerly.
        _handleExactBarcodeFallback(text);
        return KeyEventResult.handled;
      }
      // Empty box: let Enter bubble up to the screen-wide Pay shortcut.
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _barcodeController.clear();
      setState(() {
        _searchResults = [];
        _highlightedIndex = -1;
      });
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _selectProduct(Product product, {double quantity = 1}) {
    final existing = ref.read(cartProvider).where((i) => i.productId == product.id);
    final currentQtyInCart = existing.isEmpty ? 0.0 : existing.first.quantity;
    final wouldBe = currentQtyInCart + quantity;

    Category? category;
    for (final c in _categories) {
      if (c.id == product.categoryId) {
        category = c;
        break;
      }
    }
    // Either the product itself or its category can allow negative stock —
    // the product-level flag is the more specific override.
    final allowsNegative = product.allowNegativeStock || (category?.allowNegativeStock ?? false);

    // A service item has no stock to check, and a kit's own stock_quantity
    // is unused (SaleRepository checks its components instead at sale
    // time) — this pre-flight warning would otherwise misfire on both,
    // since their own stockQuantity is always 0/irrelevant.
    if (product.isService || product.isKit) {
      _addProductToCart(product, quantity: quantity);
      return;
    }

    if (!allowsNegative && wouldBe > product.stockQuantity) {
      _confirmAddDespiteLowStock(product, currentQtyInCart, quantity: quantity);
      return;
    }

    _addProductToCart(product, quantity: quantity);
  }

  Future<void> _confirmAddDespiteLowStock(Product product, double currentQtyInCart, {double quantity = 1}) async {
    final available = product.stockQuantity - currentQtyInCart;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Low Stock'),
        content: Text(
          available <= 0
              ? '${product.displayName ?? product.name} is out of stock (0 available). Add anyway?'
              : 'Only ${formatQty(available)} of ${product.displayName ?? product.name} left in stock. Add anyway?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Add Anyway'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      _addProductToCart(product, quantity: quantity);
    } else {
      // Keep the search box focused either way so scanning can continue.
      _barcodeFocus.requestFocus();
    }
  }

  void _addProductToCart(Product product, {double quantity = 1}) {
    ref.read(cartProvider.notifier).addItem(product, quantity: quantity);
    _barcodeController.clear();
    setState(() {
      _searchResults = [];
      _highlightedIndex = -1;
    });
    // Wait a frame so the cart list has rebuilt with the new row before we
    // try to focus its quantity field.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _qtyFocusNodeFor(product.id).requestFocus();
    });
  }

  void _handleExactBarcodeFallback(String value) async {
    if (value.isEmpty) return;

    // Weighing-scale barcodes carry an embedded weight/price rather than
    // matching a product's real barcode outright — check for that first
    // (only actually decodes anything if a prefix is configured in
    // Settings, otherwise this is a no-op). See weighing_barcode.dart.
    final weighingConfig = await StoreRepository().getWeighingBarcodeConfig();
    final decoded = decodeWeighingBarcode(
      value,
      prefix: weighingConfig.prefix,
      valueType: weighingConfig.valueType,
    );
    if (decoded != null) {
      final weighedProducts =
          await ref.read(productNotifierProvider.notifier).fetchByBarcode(decoded.itemCode, activeOnly: true);
      if (weighedProducts.isNotEmpty) {
        final product = weighedProducts.first;
        final quantity = decoded.priceRupees != null && product.retailPrice > 0
            ? decoded.priceRupees! / product.retailPrice
            : decoded.weightKg;
        _selectProduct(product, quantity: quantity);
        return;
      }
      // Decoded the shape but no product matches that item code — fall
      // through to a normal lookup below rather than reporting "not found"
      // on the raw 13-digit scan, in case this wasn't actually a weighing
      // barcode after all (an unlucky coincidental prefix match).
    }

    final products = await ref.read(productNotifierProvider.notifier).fetchByBarcode(value, activeOnly: true);
    if (products.isNotEmpty) {
      final inStock = products.where((p) => p.stockQuantity > 0).toList();
      if (products.length == 1) {
        _selectProduct(products.first);
      } else if (inStock.length == 1) {
        // Only one MRP variant of this barcode actually has stock — the
        // others are old price points sitting at 0 from before an MRP
        // change. Skip straight to the one that can actually be sold
        // instead of making the cashier pick past dead rows every scan.
        _selectProduct(inStock.first);
      } else {
        // Multiple in-stock variants (or all at 0, e.g. negative-stock
        // override) — let the cashier choose, with the ones that actually
        // have stock listed first.
        final sorted = [...products]..sort((a, b) => b.stockQuantity.compareTo(a.stockQuantity));
        _showMRPSelectionDialog(sorted);
      }
    } else {
      _showUnknownBarcodeDialog(value);
    }
  }

  /// A scanned/typed code that matches no product used to just show a
  /// "Product not found" snackbar and leave the cashier stuck. Offers a way
  /// forward without leaving the billing screen — mirrors the quick-add
  /// dialog already used for the same purpose in `purchase_form_screen.dart`.
  Future<void> _showUnknownBarcodeDialog(String barcode) async {
    final action = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Unknown Barcode'),
        content: Text('No product matches "$barcode".'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'ignore'),
            child: const Text('Ignore'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'search'),
            child: const Text('Search Instead'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, 'create'),
            child: const Text('Create Product'),
          ),
        ],
      ),
    );

    if (action == 'create') {
      // Same manager/admin approval gate used for discounts — a cashier can
      // still create the product mid-sale, just not unsupervised.
      final approved = await requirePriceOverrideAuth(context, ref, actionLabel: 'Creating a new product');
      if (!approved) return;
      if (!mounted) return;
      await _showQuickAddProductDialog(barcode);
      return;
    }

    // 'search' or 'ignore' or the dialog was dismissed — either way, clear
    // the box and get the scanner focus ready for the next attempt.
    _barcodeController.clear();
    setState(() {
      _searchResults = [];
      _highlightedIndex = -1;
    });
    _barcodeFocus.requestFocus();
  }

  /// Lets the cashier create a brand-new product right from Billing instead
  /// of having to stop, go to Products, add it there, then come back and
  /// scan again — mirrors `purchase_form_screen.dart`'s dialog of the same
  /// name/shape, adjusted to add straight into the cart via [_selectProduct]
  /// instead of a purchase line.
  Future<void> _showQuickAddProductDialog(String initialQuery) async {
    final looksLikeBarcode = RegExp(r'^\d{4,}$').hasMatch(initialQuery);
    final nameController = TextEditingController(text: looksLikeBarcode ? '' : initialQuery);
    final barcodeController = TextEditingController(text: looksLikeBarcode ? initialQuery : '');
    final mrpController = TextEditingController();
    final retailPriceController = TextEditingController();
    final taxController = TextEditingController(text: '5');
    final unitController = TextEditingController(text: 'Pcs');
    String? categoryId = _categories.isNotEmpty ? _categories.first.id : null;
    final formKey = GlobalKey<FormState>();

    final product = await showDialog<Product>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('New Product'),
          content: SizedBox(
            width: 420,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: nameController,
                      autofocus: !looksLikeBarcode,
                      decoration: const InputDecoration(labelText: 'Product Name *', border: OutlineInputBorder()),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: barcodeController,
                      autofocus: looksLikeBarcode,
                      decoration:
                          const InputDecoration(labelText: 'Barcode (leave blank to auto-generate)', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    if (_categories.isNotEmpty)
                      DropdownButtonFormField<String>(
                        initialValue: categoryId,
                        decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
                        items: _categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
                        onChanged: (v) => setDialogState(() => categoryId = v),
                      ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: unitController,
                            decoration: const InputDecoration(labelText: 'Unit', border: OutlineInputBorder()),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: taxController,
                            decoration: const InputDecoration(labelText: 'Tax %', border: OutlineInputBorder()),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: mrpController,
                            decoration: const InputDecoration(labelText: 'MRP', border: OutlineInputBorder()),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: retailPriceController,
                            decoration: const InputDecoration(labelText: 'Selling Price *', border: OutlineInputBorder()),
                            keyboardType: TextInputType.number,
                            validator: (v) =>
                                (double.tryParse(v?.trim() ?? '') ?? 0) <= 0 ? 'Required, must be > 0' : null,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                if (!formKey.currentState!.validate()) return;
                final barcode = barcodeController.text.trim().isEmpty
                    ? 'PLU${DateTime.now().millisecondsSinceEpoch}'
                    : barcodeController.text.trim();
                final retailPrice = double.tryParse(retailPriceController.text.trim()) ?? 0;
                final newProduct = Product.create(
                  barcode: barcode,
                  name: nameController.text.trim(),
                  categoryId: categoryId,
                  unit: unitController.text.trim().isEmpty ? 'Pcs' : unitController.text.trim(),
                  taxRate: double.tryParse(taxController.text.trim()) ?? 0,
                  mrp: double.tryParse(mrpController.text.trim()) ?? retailPrice,
                  retailPrice: retailPrice,
                );
                Navigator.pop(dialogContext, newProduct);
              },
              child: const Text('Add Product'),
            ),
          ],
        ),
      ),
    );

    if (product == null) return;

    try {
      await ref.read(productNotifierProvider.notifier).addProduct(product);
      if (!mounted) return;
      _selectProduct(product);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${product.name} added to your product list and the cart'), backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create product: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _showMRPSelectionDialog(List<Product> products) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Multiple Products Found'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: ListView.builder(
            itemCount: products.length,
            itemBuilder: (context, index) {
              final product = products[index];
              return ListTile(
                title: Text(product.name),
                subtitle: Text('MRP: ₹${product.mrp.toStringAsFixed(2)} | Sell: ₹${product.retailPrice.toStringAsFixed(2)}'),
                trailing: Text('Stock: ${product.stockQuantity}'),
                onTap: () {
                  Navigator.pop(context);
                  _selectProduct(product);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _showCustomerDialog() async {
    showDialog(
      context: context,
      builder: (_) => const CustomerPickerDialog(),
    );
  }

  Future<void> _showRedeemPointsDialog(Cart notifier) async {
    final customer = notifier.customer;
    if (customer == null) return;

    // Can't redeem more than the customer has, or more value than the bill
    // is actually worth — matches the clamp BillingService applies again
    // server-side at checkout.
    final payableBeforeRedemption = notifier.grandTotal + notifier.loyaltyRedemptionAmount;
    final maxByValue = _loyaltyValuePerPoint > 0 ? (payableBeforeRedemption / _loyaltyValuePerPoint).floor() : 0;
    final maxPoints = [customer.loyaltyPoints, maxByValue].reduce((a, b) => a < b ? a : b);

    final controller = TextEditingController(
      text: notifier.loyaltyPointsToRedeem > 0 ? notifier.loyaltyPointsToRedeem.toString() : '',
    );
    final points = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Redeem Loyalty Points'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${customer.name} has ${customer.loyaltyPoints} points '
                '(₹${(customer.loyaltyPoints * _loyaltyValuePerPoint).toStringAsFixed(2)} value).'),
            const SizedBox(height: 4),
            Text('Up to $maxPoints points can be applied to this bill.',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Points to redeem', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          if (notifier.loyaltyPointsToRedeem > 0)
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 0),
              child: const Text('Clear'),
            ),
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final entered = int.tryParse(controller.text) ?? 0;
              Navigator.pop(dialogContext, entered.clamp(0, maxPoints));
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (points == null) return;
    notifier.setLoyaltyRedemption(points, points * _loyaltyValuePerPoint);
  }

  /// Approval used to be required for ANY discount, regardless of size. Now
  /// a cashier can apply up to the store's configured percent-of-subtotal
  /// cap on their own; only a discount above that cap needs manager sign-off
  /// — checked when they hit Apply, once the actual amount is known, rather
  /// than gating the whole dialog upfront.
  void _showDiscountDialog() async {
    final subtotal = ref.read(cartProvider.notifier).subtotal;
    final maxPercent = await StoreRepository().getMaxDiscountPercent();
    if (!mounted) return;

    final discountController = TextEditingController();
    final reasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final amount = double.tryParse(discountController.text) ?? 0;
          final percent = subtotal > 0 ? (amount / subtotal) * 100 : 0;
          final needsApproval = percent > maxPercent;

          return AlertDialog(
            title: const Text('Apply Discount'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: discountController,
                  decoration: const InputDecoration(labelText: 'Discount Amount (₹)'),
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setDialogState(() {}),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: reasonController,
                  decoration: const InputDecoration(labelText: 'Reason (optional)'),
                ),
                const SizedBox(height: 8),
                Text(
                  'Up to ${maxPercent.toStringAsFixed(0)}% (₹${(subtotal * maxPercent / 100).toStringAsFixed(2)}) '
                  'needs no approval. ${needsApproval ? 'This discount needs manager approval.' : ''}',
                  style: TextStyle(
                    fontSize: 12,
                    color: needsApproval ? Colors.red : Colors.grey,
                    fontWeight: needsApproval ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  if (needsApproval) {
                    final approved =
                        await requirePriceOverrideAuth(context, ref, actionLabel: 'Applying a discount above ${maxPercent.toStringAsFixed(0)}%');
                    if (!approved) return;
                    if (!dialogContext.mounted) return;
                  }
                  ref.read(cartProvider.notifier).setDiscount(amount, reason: reasonController.text);
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                },
                child: const Text('Apply'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Customer-entered coupon code, distinct from auto-applied promotions —
  /// validated against the current bill total (before this coupon) via
  /// CouponRepository.validate, which checks active/date-range/usage-cap/
  /// min-bill all in one call.
  void _showApplyCouponDialog() {
    final notifier = ref.read(cartProvider.notifier);
    final existing = notifier.appliedCoupon;
    if (existing != null) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Coupon Applied'),
          content: Text('"${existing.code}" is applied, saving ₹${notifier.couponDiscount.toStringAsFixed(2)}.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () {
                notifier.removeCoupon();
                Navigator.pop(context);
              },
              child: const Text('Remove'),
            ),
          ],
        ),
      );
      return;
    }

    final codeController = TextEditingController();
    String? error;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return AlertDialog(
            title: const Text('Apply Coupon'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: codeController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'Coupon Code'),
                  autofocus: true,
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                  ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () async {
                  final code = codeController.text.trim();
                  if (code.isEmpty) return;
                  final result = await CouponRepository().validate(code: code, billAmount: notifier.grandTotal);
                  if (!dialogContext.mounted) return;
                  if (!result.isValid) {
                    setDialogState(() => error = result.errorMessage);
                    return;
                  }
                  notifier.applyCoupon(result.coupon!, result.discountAmount);
                  Navigator.pop(dialogContext);
                },
                child: const Text('Apply'),
              ),
            ],
          );
        },
      ),
    );
  }

  // ---------- Hold Bills Methods ----------
  /// F12 — discard the current bill entirely (not the same as Hold, which
  /// saves it for later). Confirms first since this is destructive and
  /// there's no undo.
  void _startNewBill() async {
    final cartItems = ref.read(cartProvider);
    if (cartItems.isEmpty) {
      // Nothing to lose — just make sure the search box is ready to go.
      _barcodeFocus.requestFocus();
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Start New Bill?'),
        content: Text(
          'This will discard the current bill (${cartItems.length} item${cartItems.length == 1 ? '' : 's'}) '
          'without saving it. If you want to come back to it later, use Hold (F3) instead.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard & Start New'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      ref.read(cartProvider.notifier).clearCart();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Started a new bill'), backgroundColor: Colors.blue),
        );
        _barcodeFocus.requestFocus();
      }
    }
  }

  void _holdBill() {
    final cartItems = ref.read(cartProvider);
    final notifier = ref.read(cartProvider.notifier);
    if (cartItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cart is empty'), backgroundColor: Colors.red),
      );
      return;
    }

    // Build JSON data from cart
    final data = {
      'items': cartItems.map((item) => {
        'productId': item.productId,
        'quantity': item.quantity,
        'product': item.product.toJson(),
      }).toList(),
      'customer': notifier.customer?.toJson(),
      'discount': notifier.discount,
      'discountReason': notifier.discountReason,
      'deliveryAddress': notifier.deliveryAddress,
      'deliveryCharge': notifier.deliveryCharge,
    };

    final user = ref.read(authProvider).user;
    if (user == null) return;

    final jsonString = jsonEncode(data);
    ref.read(holdNotifierProvider.notifier).saveHold(user.id, jsonString, note: 'Held at ${DateTime.now()}');
    ref.read(cartProvider.notifier).clearCart();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Bill held!'), backgroundColor: Colors.blue),
    );
  }

  void _showHoldBills() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const HoldBillsScreen()),
    );
    if (result != null) {
      _restoreHold(result);
    }
  }

  void _restoreHold(String jsonString) {
    try {
      final data = jsonDecode(jsonString);
      final items = data['items'] as List;
      for (final itemData in items) {
        final product = Product.fromJson(itemData['product']);
        final quantity = (itemData['quantity'] as num).toDouble();
        ref.read(cartProvider.notifier).addItem(product, quantity: quantity);
      }
      if (data['customer'] != null) {
        final customer = Customer.fromJson(data['customer']);
        ref.read(cartProvider.notifier).setCustomer(customer);
      }
      final discount = (data['discount'] as num?)?.toDouble() ?? 0;
      if (discount > 0) {
        ref.read(cartProvider.notifier).setDiscount(discount, reason: data['discountReason']);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bill restored!'), backgroundColor: Colors.green),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error restoring hold: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cartItems = ref.watch(cartProvider);
    final notifier = ref.read(cartProvider.notifier);
    final authState = ref.watch(authProvider);

    // Single source of truth for these figures now lives on the Cart
    // notifier (it already accounts for per-line discounts) instead of
    // being recomputed three different ways across this file.
    final subtotal = notifier.subtotal;
    final totalTax = notifier.totalTax;
    final grandTotal = notifier.grandTotal;
    // Round to the nearest rupee — standard Indian retail practice. This
    // rounded figure is what's actually charged and printed; roundOffAmount
    // is the small adjustment shown separately so it's never a mystery.
    final roundedTotal = grandTotal.roundToDouble();
    final roundOffAmount = roundedTotal - grandTotal;
    final totalQty = cartItems.fold(0.0, (sum, item) => sum + item.quantity);

    final primaryColor = Theme.of(context).primaryColor;
    final buttonColor = primaryColor;
    const buttonTextColor = Colors.white;

    final scaffold = AppScaffold(
      title: 'Billing',
      actions: [
        // Minimal, honest status strip — store name, cashier, live clock,
        // next bill number, and Caps Lock (useful since barcode/product
        // codes are often case-sensitive). Network/cloud-sync/printer
        // indicators aren't included since there's no such subsystem
        // behind them yet — a fake status light would just be misleading.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (authState.user != null) ...[
                const Icon(Icons.person_outline, size: 16),
                const SizedBox(width: 4),
                Text(authState.user!.name, style: const TextStyle(fontSize: 13)),
                const SizedBox(width: 16),
              ],
              const _BillNumberBadge(),
              const SizedBox(width: 16),
              // "NOS" (number of distinct items) + total quantity — kept
              // in the header so it's visible even when the cart list is
              // scrolled, same as the bottom summary panel shows it too.
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.inventory_2_outlined, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    '${cartItems.length} NOS · Qty ${formatQty(totalQty)}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              const _LiveClock(),
              const SizedBox(width: 12),
              const _CapsLockIndicator(),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.barcode_reader),
          onPressed: () => _barcodeFocus.requestFocus(),
        ),
      ],
      body: Row(
        children: [
          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: ProductGrid(
                onProductSelected: (product) => _selectProduct(product),
              ),
            ),
          ),
          Expanded(
            flex: 6,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: Focus(
                    onKeyEvent: _handleSearchKeyEvent,
                    child: TextField(
                      controller: _barcodeController,
                      focusNode: _barcodeFocus,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Scan barcode or search by name — ↓ to pick, Enter to add',
                        prefixIcon: const Icon(Icons.qr_code_scanner),
                        border: const OutlineInputBorder(),
                        isDense: true,
                        suffixIcon: _barcodeController.text.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _barcodeController.clear();
                                  setState(() {
                                    _searchResults = [];
                                    _highlightedIndex = -1;
                                  });
                                },
                              ),
                      ),
                      onChanged: _onSearchChanged,
                    ),
                  ),
                ),
                if (_searchResults.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: Card(
                      margin: const EdgeInsets.only(top: 2),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 220),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: _searchResults.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final product = _searchResults[i];
                            final isHighlighted = i == _highlightedIndex;
                            return Container(
                              color: isHighlighted ? Colors.green.withValues(alpha: 0.15) : null,
                              child: ListTile(
                                dense: true,
                                title: Text(product.displayName ?? product.name),
                                subtitle: Text('₹${product.retailPrice.toStringAsFixed(2)} · Stock: ${product.stockQuantity}'),
                                onTap: () => _selectProduct(product),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            const Icon(Icons.person, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              notifier.customer != null
                                  ? notifier.customer!.name
                                  : 'No Customer',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 16),
                            if (notifier.customer != null) ...[
                              Text(
                                'Points: ${notifier.customer!.loyaltyPoints}'
                                '${notifier.loyaltyPointsToRedeem > 0 ? ' (redeeming ${notifier.loyaltyPointsToRedeem})' : ''}',
                                style: const TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Credit: ₹${notifier.customer!.outstandingBalance.toStringAsFixed(2)}',
                                style: const TextStyle(fontSize: 12, color: Colors.orange),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (notifier.customer != null && notifier.customer!.loyaltyPoints > 0) ...[
                        TextButton.icon(
                          onPressed: () => _showRedeemPointsDialog(notifier),
                          icon: const Icon(Icons.redeem, size: 16),
                          label: const Text('Redeem', style: TextStyle(fontSize: 12)),
                        ),
                        const SizedBox(width: 4),
                      ],
                      ElevatedButton.icon(
                        onPressed: _showCustomerDialog,
                        icon: const Icon(Icons.person_add, size: 16),
                        label: const Text('Customer', style: TextStyle(fontSize: 12)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: buttonColor,
                          foregroundColor: buttonTextColor,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_salesmen.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    child: Row(
                      children: [
                        const Icon(Icons.badge_outlined, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonFormField<String?>(
                            initialValue: _selectedSalesmanId,
                            isDense: true,
                            decoration: const InputDecoration(
                              labelText: 'Salesman (optional)',
                              border: OutlineInputBorder(),
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('No Salesman'),
                              ),
                              ..._salesmen.map(
                                (s) => DropdownMenuItem<String?>(
                                  value: s.id,
                                  child: Text(s.name),
                                ),
                              ),
                            ],
                            onChanged: (value) => setState(() => _selectedSalesmanId = value),
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: CartListView(
                    items: cartItems,
                    onQuantityChange: (id, qty) =>
                        ref.read(cartProvider.notifier).updateQuantity(id, qty),
                    onRemove: (id) => ref.read(cartProvider.notifier).removeItem(id),
                    onDiscountChange: (id, discount) =>
                        ref.read(cartProvider.notifier).updateLineDiscount(id, discount),
                    focusNodeForProduct: _qtyFocusNodeFor,
                    onQuantitySubmitted: () => _barcodeFocus.requestFocus(),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Items: ${cartItems.length}   •   Qty: ${formatQty(totalQty)}',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Subtotal:'),
                          Text('₹${subtotal.toStringAsFixed(2)}'),
                        ],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Tax:'),
                          Text('₹${totalTax.toStringAsFixed(2)}'),
                        ],
                      ),
                      if (notifier.discount > 0)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Discount:'),
                            Text(' -₹${notifier.discount.toStringAsFixed(2)}'),
                          ],
                        ),
                      if (notifier.promoDiscountTotal > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  'Promo: ${notifier.appliedPromotions.map((p) => p.name).join(', ')}',
                                  style: const TextStyle(color: Colors.green, fontSize: 12),
                                ),
                              ),
                              Text(
                                ' -₹${notifier.promoDiscountTotal.toStringAsFixed(2)}',
                                style: const TextStyle(color: Colors.green),
                              ),
                            ],
                          ),
                        ),
                      if (notifier.appliedCoupon != null)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Coupon (${notifier.appliedCoupon!.code}):', style: const TextStyle(color: Colors.blue)),
                            Text(
                              ' -₹${notifier.couponDiscount.toStringAsFixed(2)}',
                              style: const TextStyle(color: Colors.blue),
                            ),
                          ],
                        ),
                      if (notifier.loyaltyRedemptionAmount > 0)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Loyalty Redemption (${notifier.loyaltyPointsToRedeem} pts):'),
                            Text(' -₹${notifier.loyaltyRedemptionAmount.toStringAsFixed(2)}'),
                          ],
                        ),
                      if (roundOffAmount != 0)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Round Off:', style: TextStyle(fontSize: 12)),
                            Text(
                              '${roundOffAmount > 0 ? '+' : ''}₹${roundOffAmount.toStringAsFixed(2)}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      const Divider(thickness: 2),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Total:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                          Text(
                            '₹${roundedTotal.toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Bill-level actions: smaller, secondary row.
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        alignment: WrapAlignment.center,
                        children: [
                          _secondaryButton('Customer', Icons.person, 'F1', _showCustomerDialog),
                          _secondaryButton('Discount', Icons.percent, 'F2', _showDiscountDialog),
                          OutlinedButton.icon(
                            onPressed: _showApplyCouponDialog,
                            icon: const Icon(Icons.local_offer_outlined, size: 14),
                            label: Text(
                              notifier.appliedCoupon != null ? 'Coupon: ${notifier.appliedCoupon!.code}' : 'Coupon',
                              style: const TextStyle(fontSize: 11),
                            ),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              minimumSize: const Size(0, 32),
                              foregroundColor: notifier.appliedCoupon != null ? Colors.green : null,
                            ),
                          ),
                          _secondaryButton('Hold', Icons.save, 'F3', _holdBill),
                          _secondaryButton('Holds', Icons.list, 'F4', _showHoldBills),
                          _secondaryButton('Quotation', Icons.description, 'F10', _showQuotationDialog),
                          _secondaryButton('New Bill', Icons.note_add_outlined, 'F12', _startNewBill),
                          _secondaryButton('Share', Icons.share, 'F9', () => _shareOnWhatsApp(cartItems, notifier, grandTotal)),
                        ],
                      ),
                      const Divider(height: 20),
                      // Payment is now a single entry point — Cash/UPI/Card/
                      // Credit/Partial all live inside the Payment dialog
                      // itself instead of cluttering the screen with one
                      // button per method. F11 still jumps straight into
                      // Partial mode for a keyboard-only workflow.
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton.icon(
                          onPressed: () => _showPaymentDialog(),
                          icon: const Icon(Icons.payment, size: 22),
                          label: const Text(
                            'Complete Payment   (F5)',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade700,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f1): _showCustomerDialog,
        const SingleActivator(LogicalKeyboardKey.f2): _showDiscountDialog,
        const SingleActivator(LogicalKeyboardKey.f3): _holdBill,
        const SingleActivator(LogicalKeyboardKey.f4): _showHoldBills,
        const SingleActivator(LogicalKeyboardKey.f5): () => _showPaymentDialog(),
        const SingleActivator(LogicalKeyboardKey.f6): () => _barcodeFocus.requestFocus(),
        const SingleActivator(LogicalKeyboardKey.f7): () {
          // Jump to the quantity box of the last item added, so Tab/Enter
          // from there continues the keyboard-only flow.
          if (cartItems.isNotEmpty) {
            _qtyFocusNodeFor(cartItems.last.productId).requestFocus();
          }
        },
        const SingleActivator(LogicalKeyboardKey.f8): () {
          // Removes whichever cart line's quantity box currently has focus
          // (tab/F7 into a row first) — avoids an accidental delete from a
          // stray keypress when nothing specific is selected.
          String? focusedId;
          for (final entry in _qtyFocusNodes.entries) {
            if (entry.value.hasFocus) {
              focusedId = entry.key;
              break;
            }
          }
          if (focusedId != null) {
            ref.read(cartProvider.notifier).removeItem(focusedId);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Select an item (F7) before removing with F8')),
            );
          }
        },
        const SingleActivator(LogicalKeyboardKey.f9): () => _shareOnWhatsApp(cartItems, notifier, grandTotal),
        const SingleActivator(LogicalKeyboardKey.f10): _showQuotationDialog,
        const SingleActivator(LogicalKeyboardKey.f12): _startNewBill,
        const SingleActivator(LogicalKeyboardKey.f11): () {
          if (notifier.customer == null) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Please select a customer for partial payment'), backgroundColor: Colors.red),
            );
            return;
          }
          _showPaymentDialog(startWithPartial: true);
        },
        const SingleActivator(LogicalKeyboardKey.enter): () => _showPaymentDialog(),
      },
      child: Focus(
        autofocus: true,
        // Note: this outer Focus is what makes F1-F11/Enter work anywhere on
        // this screen (previously the labels on the buttons were purely
        // decorative — no keyboard listener existed at all).
        child: scaffold,
      ),
    );
  }

  Future<void> _shareOnWhatsApp(List<CartItem> cartItems, Cart notifier, double grandTotal) async {
    final items = cartItems.map((item) => InvoiceLine(
      name: item.product.displayName ?? item.product.name,
      qty: item.quantity,
      price: item.product.retailPrice,
      total: item.product.retailPrice * item.quantity,
    )).toList();
    await WhatsAppShareService.shareInvoice(
      invoiceNo: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      customerName: notifier.customer?.name ?? 'Guest',
      total: grandTotal,
      items: items,
      date: DateTime.now(),
    );
  }

  Widget _secondaryButton(String label, IconData icon, String shortcut, VoidCallback onPressed) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 14),
      label: Text('$label  ($shortcut)', style: const TextStyle(fontSize: 11)),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: const Size(0, 32),
      ),
    );
  }


  void _showPaymentDialog({String? preFilledMethod, bool startWithPartial = false}) {
    final cartItems = ref.watch(cartProvider);
    final notifier = ref.read(cartProvider.notifier);

    // Single source of truth for these figures now lives on the Cart
    // notifier (it already accounts for per-line discounts) instead of
    // being recomputed three different ways across this file.
    final grandTotal = notifier.grandTotal;
    final roundedTotal = grandTotal.roundToDouble();
    final roundOffAmount = roundedTotal - grandTotal;

    if (cartItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cart is empty'), backgroundColor: Colors.red),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (_) => PaymentDialog(
        total: roundedTotal,
        customer: notifier.customer,
        preFilledMethod: preFilledMethod,
        startWithPartial: startWithPartial,
        onPay: (payments, partialAmount, creditUsed, changeDue, gatewayTransactionIds) async {
          try {
            final authState = ref.watch(authProvider);
            final user = authState.user;

            // Sales were previously always saved with sessionId: null, which
            // meant shift closing could never find them to reconcile cash.
            // Fetches whatever shift is currently open for this cashier, if
            // any — deliberately non-blocking (still allows billing without
            // an open shift) so this doesn't lock anyone out before they've
            // adopted the Open/Close Shift screens.
            final activeSession = user != null ? await CounterService().getActiveSession(user.id) : null;

            final service = BillingService();
            final sale = await service.processSale(
              storeId: 'store_default',
              sessionId: activeSession?.id,
              roundOff: roundOffAmount,
              userId: user?.id,
              cartItems: cartItems,
              payments: payments,
              // Coupon discount is bill-level, same as the F2 discount —
              // folded together here so it actually reduces netAmount;
              // CouponRepository.recordUsage (below, after the sale
              // succeeds) is what actually consumes the coupon's use.
              discountTotal: notifier.discount + notifier.couponDiscount,
              discountReason: notifier.appliedCoupon != null
                  ? [notifier.discountReason, 'Coupon: ${notifier.appliedCoupon!.code}']
                      .where((s) => s != null && s.isNotEmpty)
                      .join(' + ')
                  : notifier.discountReason,
              partialPaymentAmount: partialAmount,
              creditUsed: creditUsed,
              deliveryAddress: notifier.deliveryAddress,
              isDelivery: notifier.deliveryAddress != null,
              deliveryCharge: notifier.deliveryCharge,
              customerId: notifier.customer?.id,
              salesmanId: _selectedSalesmanId,
              remarks: null,
              loyaltyPointsRedeemed: notifier.loyaltyPointsToRedeem,
            );

            // Gateway payments were collected and verified before this sale
            // existed (payments.sale_id is a real foreign key, so it could
            // not have been set earlier). Link them now that it does.
            // Deliberately non-fatal: the money is already taken and recorded,
            // and failing the completed sale over a missing link would be far
            // worse than a payment row that needs joining up by hand.
            for (final gatewayTransactionId in gatewayTransactionIds) {
              try {
                await PaymentGatewayService().attachSale(
                  transactionId: gatewayTransactionId,
                  saleId: sale.id,
                );
              } catch (_) {
                // Left unlinked rather than losing the sale.
              }
            }

            final cashReceived = payments['cash'] != null ? payments['cash']! + changeDue : null;

            // Captured before clearCart() wipes it — recorded now that the
            // sale actually went through, not at Apply time, so a coupon
            // that's checked but the sale then abandoned doesn't burn a use.
            final usedCouponId = notifier.appliedCoupon?.id;
            if (usedCouponId != null) {
              await CouponRepository().recordUsage(usedCouponId);
            }

            // Clear cart before showing dialog to prevent double-sale
            ref.read(cartProvider.notifier).clearCart();
            if (mounted) {
              setState(() => _selectedSalesmanId = null);
            }
            Navigator.pop(context);

            // Ask user what to do: Print, Share, or Close
            final action = await showDialog<String>(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('Sale Completed!'),
                content: Text(
                  'Invoice ${sale.invoiceLabel}\n'
                  'Total: ₹${sale.netAmount.toStringAsFixed(2)}'
                  '${changeDue > 0 ? '\nChange to return: ₹${changeDue.toStringAsFixed(2)}' : ''}',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, 'close'),
                    child: const Text('Close'),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context, 'print'),
                    icon: const Icon(Icons.print),
                    label: const Text('Save & Print Invoice'),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context, 'share'),
                    icon: const Icon(Icons.share),
                    label: const Text('Share'),
                  ),
                ],
              ),
            );

            if (action == 'print') {
              final items = await service.getSaleItems(sale.id);
              final printerConfig = await StoreRepository().getPrinterConfig();

              var printedViaThermal = false;
              if (printerConfig.type != 'none') {
                final receiptItems = items.map((item) {
                  var productName = 'Product ${item.productId}';
                  for (final cartItem in cartItems) {
                    if (cartItem.productId == item.productId) {
                      productName = cartItem.product.displayName ?? cartItem.product.name;
                      break;
                    }
                  }
                  return {'name': productName, 'qty': item.quantity, 'price': item.unitPrice};
                }).toList();

                final receiptBytes = ThermalPrintService.buildEscPosReceipt(
                  storeName: 'SuperMart POS',
                  storeAddress: '123 Main Street, City',
                  storePhone: '+91-9876543210',
                  storeGstin: '33ABCDE1234F1Z5',
                  invoiceLabel: sale.invoiceLabel,
                  date: DateTime.fromMillisecondsSinceEpoch(sale.createdAt * 1000),
                  customerName: notifier.customer?.name ?? 'Guest',
                  items: receiptItems,
                  subtotal: sale.subtotal,
                  tax: sale.taxTotal,
                  discount: sale.discountTotal,
                  total: sale.netAmount,
                  charsPerLine: printerConfig.charsPerLine,
                );
                printedViaThermal = await ThermalPrintService.printEscPos(
                  printerType: printerConfig.type,
                  printerTarget: printerConfig.target ?? '',
                  printerPort: printerConfig.port,
                  receiptBytes: receiptBytes,
                );
                if (!printedViaThermal && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Thermal printer unreachable — falling back to PDF print'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                }
              }

              // Falls back to the PDF/OS print dialog path whenever no
              // thermal printer is configured, or sending to a configured
              // one failed — a cashier should always get a receipt option,
              // not silence.
              if (!printedViaThermal) {
                final pdfData = await InvoiceService().generateInvoice(
                  sale: sale,
                  items: items,
                  storeName: 'SuperMart POS',
                  storeAddress: '123 Main Street, City',
                  storePhone: '+91-9876543210',
                  storeGstin: '33ABCDE1234F1Z5',
                  storeFssai: '12421031000236',
                  cashReceived: cashReceived,
                  changeDue: changeDue,
                );
                await InvoiceService.printPDF(context, pdfData);
              }
            } else if (action == 'share') {
              final items = await service.getSaleItems(sale.id);
              final customerName = notifier.customer?.name ?? 'Guest';
              final invoiceLines = <InvoiceLine>[];
              for (final item in items) {
                String productName = 'Product ${item.productId}';
                for (final cartItem in cartItems) {
                  if (cartItem.productId == item.productId) {
                    productName = cartItem.product.displayName ?? cartItem.product.name;
                    break;
                  }
                }
                invoiceLines.add(
                  InvoiceLine(
                    name: productName,
                    qty: item.quantity,
                    price: item.unitPrice,
                    total: item.totalPrice,
                  ),
                );
              }
              await WhatsAppShareService.shareInvoice(
                invoiceNo: sale.invoiceNo,
                invoiceLabel: sale.invoiceLabel,
                customerName: customerName,
                total: sale.netAmount,
                items: invoiceLines,
                date: DateTime.now(),
                cashReceived: cashReceived,
                changeDue: changeDue,
              );
            }

            // Refresh sales history
            ref.invalidate(recentSalesProvider);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Sale completed!'), backgroundColor: Colors.green),
            );
          } catch (e) {
            // Ensure dialog is closed on error
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
            );
          }
        },
      ),
    );
  }

  void _showQuotationDialog() {
    final cartItems = ref.watch(cartProvider);
    final notifier = ref.read(cartProvider.notifier);

    if (cartItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cart is empty'), backgroundColor: Colors.red),
      );
      return;
    }

    // Single source of truth for these figures now lives on the Cart
    // notifier (it already accounts for per-line discounts) instead of
    // being recomputed three different ways across this file.
    final subtotal = notifier.subtotal;
    final totalTax = notifier.totalTax;
    final grandTotal = notifier.grandTotal;

    showDialog(
      context: context,
      builder: (_) => QuotationDialog(
        subtotal: subtotal,
        totalTax: totalTax,
        discountTotal: notifier.discount,
        discountReason: notifier.discountReason,
        grandTotal: grandTotal,
        cartItems: cartItems.map((item) => {
          'name': item.product.displayName ?? item.product.name,
          'qty': item.quantity,
          'price': item.product.retailPrice,
          'total': item.product.retailPrice * item.quantity,
        }).toList(),
      ),
    ).then((result) async {
      if (result != null && result is Map) {
        try {
          final quotation = Quotation.create(
            storeId: 'store_default',
            customerId: notifier.customer?.id,
            customerName: result['customerName'] ?? 'Guest',
            customerPhone: result['customerPhone'],
            customerEmail: result['customerEmail'],
            subtotal: subtotal,
            taxTotal: totalTax,
            discountTotal: notifier.discount,
            discountReason: notifier.discountReason,
            netAmount: grandTotal,
            notes: result['notes'],
            expiryDate: result['expiryDate'] != null && result['expiryDate'].isNotEmpty
                ? DateTime.parse(result['expiryDate']).millisecondsSinceEpoch ~/ 1000
                : 0,
          );

          final quotationItems = cartItems
              .map((item) => QuotationItem.create(
                    productId: item.productId,
                    quantity: item.quantity,
                    unitPrice: item.product.retailPrice,
                    totalPrice: item.product.retailPrice * item.quantity,
                  ))
              .toList();
          await ref.read(quotationNotifierProvider.notifier).addQuotation(quotation, items: quotationItems);

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Quotation generated!'), backgroundColor: Colors.green),
          );
        } catch (e) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    });
  }
}

/// Small self-contained ticking clock so the rest of the billing screen
/// doesn't rebuild every second just to keep the time current.
/// Shows a preview of the next invoice number (real sequential numbers now,
/// not the old timestamp-based ones — see SaleRepository.previewNextInvoiceNo).
/// Refreshes periodically since there's no direct event hook from a
/// completed sale into this widget; a few seconds of staleness right after
/// a sale is a non-issue in practice.
class _BillNumberBadge extends StatefulWidget {
  const _BillNumberBadge();

  @override
  State<_BillNumberBadge> createState() => _BillNumberBadgeState();
}

class _BillNumberBadgeState extends State<_BillNumberBadge> {
  int? _nextInvoiceNo;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _refresh());
  }

  Future<void> _refresh() async {
    try {
      final next = await SaleRepository().previewNextInvoiceNo();
      if (mounted) setState(() => _nextInvoiceNo = next);
    } catch (_) {
      // Non-critical display — fail silently rather than disrupt billing.
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_nextInvoiceNo == null) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.receipt_long_outlined, size: 16),
        const SizedBox(width: 4),
        Text('Bill #$_nextInvoiceNo', style: const TextStyle(fontSize: 13)),
      ],
    );
  }
}

/// Caps Lock is worth surfacing on a screen where cashiers are constantly
/// typing barcodes/SKUs that are often case-sensitive.
class _CapsLockIndicator extends StatefulWidget {
  const _CapsLockIndicator();

  @override
  State<_CapsLockIndicator> createState() => _CapsLockIndicatorState();
}

class _CapsLockIndicatorState extends State<_CapsLockIndicator> {
  bool _capsOn = false;

  @override
  void initState() {
    super.initState();
    _capsOn = HardwareKeyboard.instance.lockModesEnabled.contains(KeyboardLockMode.capsLock);
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  bool _onKey(KeyEvent event) {
    final isOn = HardwareKeyboard.instance.lockModesEnabled.contains(KeyboardLockMode.capsLock);
    if (isOn != _capsOn && mounted) {
      setState(() => _capsOn = isOn);
    }
    return false; // never consume — this is observation only.
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_capsOn) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.orange.shade100,
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text('CAPS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange)),
    );
  }
}

class _LiveClock extends StatefulWidget {
  const _LiveClock();

  @override
  State<_LiveClock> createState() => _LiveClockState();
}

class _LiveClockState extends State<_LiveClock> {
  late DateTime _now;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _twoDigits(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final hour12 = _now.hour % 12 == 0 ? 12 : _now.hour % 12;
    final ampm = _now.hour >= 12 ? 'PM' : 'AM';
    final text =
        '${_twoDigits(_now.day)}/${_twoDigits(_now.month)}/${_now.year}  ${_twoDigits(hour12)}:${_twoDigits(_now.minute)}:${_twoDigits(_now.second)} $ampm';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.access_time, size: 16),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(fontSize: 13)),
      ],
    );
  }
}