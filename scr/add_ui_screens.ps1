# add_ui_screens.ps1 – Adds all missing UI screens
$base = "lib"

$uiFiles = @{

    # ========================== AUTH SCREENS ==========================
    "features/auth/screens/change_password_screen.dart" = @'
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../providers/auth_provider.dart';

class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  bool _isLoading = false;

  Future<void> _changePassword() async {
    final newPass = _newPasswordController.text.trim();
    final confirm = _confirmController.text.trim();

    if (newPass.isEmpty || confirm.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter new password'), backgroundColor: Colors.red),
      );
      return;
    }
    if (newPass != confirm) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passwords do not match'), backgroundColor: Colors.red),
      );
      return;
    }
    if (newPass.length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password must be at least 4 characters'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isLoading = true);
    final success = await ref.read(authProvider.notifier).changePassword(newPass);
    setState(() => _isLoading = false);

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password changed successfully!'), backgroundColor: Colors.green),
      );
      context.go('/dashboard');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to change password'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Change Password')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('You must change your password before continuing.', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 24),
            TextField(
              controller: _newPasswordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'New Password', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _confirmController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Confirm Password', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton(
                      onPressed: _changePassword,
                      child: const Text('CHANGE PASSWORD', style: TextStyle(fontSize: 16)),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
'@

    # ========================== BILLING SCREEN ==========================
    "features/billing/screens/billing_screen.dart" = @'
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../providers/cart_provider.dart';
import '../../../providers/product_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../models/product_model.dart';
import '../widgets/cart_list_view.dart';
import '../widgets/payment_dialog.dart';
import '../../counter/screens/counter_open_screen.dart';
import '../../products/screens/product_form_screen.dart';

class BillingScreen extends ConsumerStatefulWidget {
  const BillingScreen({super.key});

  @override
  ConsumerState<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends ConsumerState<BillingScreen> {
  final TextEditingController _barcodeController = TextEditingController();
  final FocusNode _barcodeFocus = FocusNode();
  bool _hasOpenShift = false;

  @override
  void initState() {
    super.initState();
    _barcodeFocus.requestFocus();
    _checkShift();
  }

  Future<void> _checkShift() async {
    // Placeholder – we'll check if shift is open
    // For now, assume true to allow billing
    setState(() => _hasOpenShift = true);
  }

  @override
  void dispose() {
    _barcodeController.dispose();
    _barcodeFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cartItems = ref.watch(cartProvider);
    final notifier = ref.read(cartProvider.notifier);
    final user = ref.watch(authProvider);

    if (!_hasOpenShift) {
      return Scaffold(
        appBar: AppBar(title: const Text('Billing')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock, size: 64, color: Colors.orange),
              const SizedBox(height: 16),
              const Text('No open shift found.', style: TextStyle(fontSize: 18)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => context.go('/counter/open'),
                child: const Text('OPEN SHIFT'),
              ),
            ],
          ),
        ),
      );
    }

    final subtotal = cartItems.fold(
      0.0,
      (sum, item) => sum + (item.product.retailPrice * item.quantity),
    );
    final totalTax = cartItems.fold(
      0.0,
      (sum, item) => sum + ((item.product.retailPrice * item.quantity * item.product.taxRate) / 100),
    );
    final grandTotal = subtotal + totalTax + notifier.deliveryCharge - notifier.discount;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Billing'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => _showProductSearch(context),
          ),
          IconButton(
            icon: const Icon(Icons.save_alt),
            onPressed: cartItems.isEmpty ? null : _holdBill,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _barcodeController,
                    focusNode: _barcodeFocus,
                    decoration: const InputDecoration(
                      hintText: 'Scan or type barcode',
                      prefixIcon: Icon(Icons.qr_code_scanner),
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (value) async {
                      if (value.isNotEmpty) {
                        final products = await ref
                            .read(productNotifierProvider.notifier)
                            .fetchByBarcode(value);
                        if (products.isNotEmpty) {
                          if (products.length == 1) {
                            ref.read(cartProvider.notifier).addItem(products.first);
                          } else {
                            _showMRPSelectionDialog(products);
                          }
                          _barcodeController.clear();
                        } else {
                          _showProductNotFoundDialog(value);
                        }
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          if (notifier.customer != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Row(
                children: [
                  const Icon(Icons.person, size: 16),
                  const SizedBox(width: 4),
                  Text('Customer: ${notifier.customer!.name}'),
                  const Spacer(),
                  Text('Points: ${notifier.customer!.loyaltyPoints}'),
                ],
              ),
            ),
          Expanded(
            child: CartListView(
              items: cartItems,
              onQuantityChange: (id, qty) =>
                  ref.read(cartProvider.notifier).updateQuantity(id, qty),
              onRemove: (id) => ref.read(cartProvider.notifier).removeItem(id),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Column(
              children: [
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
                if (notifier.deliveryCharge > 0)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Delivery:'),
                      Text('₹${notifier.deliveryCharge.toStringAsFixed(2)}'),
                    ],
                  ),
                if (notifier.discount > 0)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Discount:'),
                      Text(' -₹${notifier.discount.toStringAsFixed(2)}'),
                    ],
                  ),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    Text('₹${grandTotal.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 40,
                        child: OutlinedButton(
                          onPressed: () => _showDiscountDialog(),
                          child: const Text('Discount'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SizedBox(
                        height: 40,
                        child: OutlinedButton(
                          onPressed: () => _showCustomerSearch(),
                          child: const Text('Customer'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SizedBox(
                        height: 40,
                        child: OutlinedButton(
                          onPressed: () => _showHoldBills(),
                          child: const Text('Holds'),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: cartItems.isEmpty
                        ? null
                        : () {
                            showDialog(
                              context: context,
                              builder: (_) => PaymentDialog(
                                total: grandTotal,
                                customer: notifier.customer,
                                onPay: (payments, partialAmount, creditUsed) {
                                  // Process sale
                                  ref.read(cartProvider.notifier).clearCart();
                                  Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Sale completed!'),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                },
                              ),
                            );
                          },
                    icon: const Icon(Icons.payment),
                    label: const Text('PAY NOW', style: TextStyle(fontSize: 18)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
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
                  ref.read(cartProvider.notifier).addItem(product);
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

  void _showProductNotFoundDialog(String barcode) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Product Not Found'),
        content: Text('No product found with barcode: $barcode'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              context.push('/products/form', extra: Product.create(
                barcode: barcode,
                name: '',
                retailPrice: 0,
                mrp: 0,
              ));
            },
            child: const Text('Add New'),
          ),
        ],
      ),
    );
  }

  void _showProductSearch(BuildContext context) {
    showSearch(
      context: context,
      delegate: _ProductSearchDelegate(
        onSelect: (product) {
          ref.read(cartProvider.notifier).addItem(product);
          Navigator.pop(context);
        },
        onAddNew: () {
          Navigator.pop(context);
          context.go('/products/form');
        },
      ),
    );
  }

  void _showDiscountDialog() {
    final discountController = TextEditingController();
    final reasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Apply Discount'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: discountController,
              decoration: const InputDecoration(labelText: 'Discount Amount (₹)'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(labelText: 'Reason (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              final amount = double.tryParse(discountController.text) ?? 0;
              ref.read(cartProvider.notifier).setDiscount(amount, reason: reasonController.text);
              Navigator.pop(context);
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  void _showCustomerSearch() {
    // Navigate to customer search/selection
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Customer selection coming soon')),
    );
  }

  void _showHoldBills() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Hold bills coming soon')),
    );
  }

  void _holdBill() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Bill held!')),
    );
    ref.read(cartProvider.notifier).clearCart();
  }
}

class _ProductSearchDelegate extends SearchDelegate<Product?> {
  final Function(Product) onSelect;
  final VoidCallback onAddNew;

  _ProductSearchDelegate({required this.onSelect, required this.onAddNew});

  @override
  List<Widget> buildActions(BuildContext context) => [
    IconButton(
      icon: const Icon(Icons.clear),
      onPressed: () => query = '',
    ),
  ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
    icon: const Icon(Icons.arrow_back),
    onPressed: () => close(context, null),
  );

  @override
  Widget buildResults(BuildContext context) => buildSuggestions(context);

  @override
  Widget buildSuggestions(BuildContext context) {
    if (query.isEmpty) {
      return const Center(child: Text('Start typing to search products'));
    }

    return FutureBuilder(
      future: ref.read(productNotifierProvider.notifier).search(query),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        final products = snapshot.data ?? [];
        if (products.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('No products found'),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: onAddNew,
                  child: const Text('Add New Product'),
                ),
              ],
            ),
          );
        }
        return ListView.builder(
          itemCount: products.length,
          itemBuilder: (context, index) {
            final product = products[index];
            return ListTile(
              leading: const Icon(Icons.inventory),
              title: Text(product.name),
              subtitle: Text('Barcode: ${product.barcode} | ₹${product.retailPrice.toStringAsFixed(2)}'),
              trailing: Text('Stock: ${product.stockQuantity}'),
              onTap: () {
                onSelect(product);
                close(context, product);
              },
            );
          },
        );
      },
    );
  }
}
'@

    # ========================== BILLING WIDGETS ==========================
    "features/billing/widgets/cart_list_view.dart" = @'
import 'package:flutter/material.dart';
import '../../../models/product_model.dart';
import '../../../providers/cart_provider.dart';

class CartListView extends StatelessWidget {
  final List<CartItem> items;
  final Function(String, int) onQuantityChange;
  final Function(String) onRemove;

  const CartListView({
    super.key,
    required this.items,
    required this.onQuantityChange,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shopping_cart, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('Cart is empty', style: TextStyle(fontSize: 16)),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (_, index) {
        final item = items[index];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.green.shade100,
              child: Text(item.quantity.toString()),
            ),
            title: Text(item.product.name),
            subtitle: Text(
              '₹${item.product.retailPrice.toStringAsFixed(2)} x ${item.quantity}',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.remove_circle, color: Colors.red),
                  onPressed: () => onQuantityChange(item.productId, item.quantity - 1),
                ),
                Text('${item.quantity}'),
                IconButton(
                  icon: const Icon(Icons.add_circle, color: Colors.green),
                  onPressed: () => onQuantityChange(item.productId, item.quantity + 1),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_forever, color: Colors.red),
                  onPressed: () => onRemove(item.productId),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
'@

    "features/billing/widgets/payment_dialog.dart" = @'
import 'package:flutter/material.dart';
import '../../../models/customer_model.dart';

class PaymentDialog extends StatefulWidget {
  final double total;
  final Customer? customer;
  final Function(Map<String, double>, double?, double?) onPay;

  const PaymentDialog({
    super.key,
    required this.total,
    this.customer,
    required this.onPay,
  });

  @override
  State<PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<PaymentDialog> {
  double cash = 0;
  double upi = 0;
  double card = 0;
  double credit = 0;
  bool useCredit = false;
  bool partialPayment = false;
  double partialAmount = 0;

  @override
  Widget build(BuildContext context) {
    final totalPaid = cash + upi + card + (useCredit ? credit : 0);
    final remaining = widget.total - totalPaid;
    final canUseCredit = widget.customer != null && widget.customer!.outstandingBalance > 0;

    return AlertDialog(
      title: const Text('Payment'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Total: ₹${widget.total.toStringAsFixed(2)}', style: const TextStyle(fontSize: 20)),
            const SizedBox(height: 16),
            _paymentField('Cash', cash, (v) => setState(() => cash = v)),
            _paymentField('UPI', upi, (v) => setState(() => upi = v)),
            _paymentField('Card', card, (v) => setState(() => card = v)),
            if (canUseCredit)
              CheckboxListTile(
                value: useCredit,
                onChanged: (val) {
                  setState(() {
                    useCredit = val ?? false;
                    if (useCredit) credit = remaining;
                  });
                },
                title: Text('Use Credit (₹${widget.customer!.outstandingBalance.toStringAsFixed(2)} available)'),
              ),
            if (useCredit)
              _paymentField('Credit Amount', credit, (v) => setState(() => credit = v)),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total Paid:', style: TextStyle(fontWeight: FontWeight.bold)),
                Text('₹${totalPaid.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            if (remaining > 0)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Remaining:', style: TextStyle(color: Colors.red)),
                  Text('₹${remaining.toStringAsFixed(2)}', style: const TextStyle(color: Colors.red)),
                ],
              ),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: partialPayment,
              onChanged: (val) => setState(() => partialPayment = val ?? false),
              title: const Text('Partial Payment'),
            ),
            if (partialPayment)
              _paymentField('Partial Amount', partialAmount, (v) => setState(() => partialAmount = v)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () {
            final payments = <String, double>{};
            if (cash > 0) payments['cash'] = cash;
            if (upi > 0) payments['upi'] = upi;
            if (card > 0) payments['card'] = card;
            if (useCredit && credit > 0) payments['credit'] = credit;

            final partial = partialPayment ? partialAmount : null;
            final creditUsed = useCredit ? credit : null;

            if (payments.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Enter at least one payment method'), backgroundColor: Colors.red),
              );
              return;
            }

            if (partialPayment && partialAmount <= 0) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Enter partial amount'), backgroundColor: Colors.red),
              );
              return;
            }

            widget.onPay(payments, partial, creditUsed);
          },
          child: const Text('Pay'),
        ),
      ],
    );
  }

  Widget _paymentField(String label, double value, Function(double) onChanged) {
    return TextField(
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      keyboardType: TextInputType.number,
      onChanged: (v) => onChanged(double.tryParse(v) ?? 0),
    );
  }
}
'@

    # ========================== PRODUCT SCREENS ==========================
    "features/products/screens/product_list_screen.dart" = @'
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../providers/product_provider.dart';
import 'product_form_screen.dart';

class ProductListScreen extends ConsumerStatefulWidget {
  const ProductListScreen({super.key});

  @override
  ConsumerState<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends ConsumerState<ProductListScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Products'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(productNotifierProvider),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Search by name or barcode',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                if (value.isNotEmpty) {
                  ref.read(productNotifierProvider.notifier).search(value);
                } else {
                  ref.invalidate(productNotifierProvider);
                }
              },
            ),
          ),
          Expanded(
            child: productsAsync.when(
              data: (products) {
                if (products.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inventory, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text('No products found'),
                        SizedBox(height: 8),
                        Text('Tap + to add your first product'),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: products.length,
                  itemBuilder: (context, index) {
                    final product = products[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: product.stockQuantity > 0
                              ? Colors.green.shade100
                              : Colors.red.shade100,
                          child: Text(
                            product.stockQuantity.toString(),
                            style: TextStyle(
                              color: product.stockQuantity > 0
                                  ? Colors.green.shade800
                                  : Colors.red.shade800,
                            ),
                          ),
                        ),
                        title: Text(product.name),
                        subtitle: Text(
                          'Barcode: ${product.barcode} | MRP: ₹${product.mrp.toStringAsFixed(2)}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '₹${product.retailPrice.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.edit, size: 20),
                              onPressed: () => _navigateToForm(product),
                            ),
                          ],
                        ),
                        onTap: () => _navigateToForm(product),
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => Center(
                child: Text(
                  'Error: $err',
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _navigateToForm(),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _navigateToForm([Product? product]) {
    context.push('/products/form', extra: product);
  }
}
'@

    "features/products/screens/product_form_screen.dart" = @'
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../models/product_model.dart';
import '../../../models/category_model.dart';
import '../../../providers/product_provider.dart';
import '../../../repositories/category_repository.dart';

class ProductFormScreen extends ConsumerStatefulWidget {
  const ProductFormScreen({super.key});

  @override
  ConsumerState<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends ConsumerState<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _barcodeController;
  late final TextEditingController _nameController;
  late final TextEditingController _searchNameController;
  late final TextEditingController _displayNameController;
  late final TextEditingController _mrpController;
  late final TextEditingController _retailPriceController;
  late final TextEditingController _wholesalePriceController;
  late final TextEditingController _costPriceController;
  late final TextEditingController _taxRateController;
  late final TextEditingController _stockController;
  late final TextEditingController _reorderController;
  late final TextEditingController _unitController;

  Product? _product;
  String? _selectedCategoryId;
  bool _bonusEligible = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final extra = ModalRoute.of(context)?.settings.extra;
    _product = extra is Product ? extra : null;

    _barcodeController = TextEditingController(text: _product?.barcode ?? '');
    _nameController = TextEditingController(text: _product?.name ?? '');
    _searchNameController = TextEditingController(text: _product?.searchName ?? '');
    _displayNameController = TextEditingController(text: _product?.displayName ?? '');
    _mrpController = TextEditingController(text: _product?.mrp.toString() ?? '0');
    _retailPriceController = TextEditingController(text: _product?.retailPrice.toString() ?? '0');
    _wholesalePriceController = TextEditingController(text: _product?.wholesalePrice.toString() ?? '0');
    _costPriceController = TextEditingController(text: _product?.costPrice.toString() ?? '0');
    _taxRateController = TextEditingController(text: _product?.taxRate.toString() ?? '0');
    _stockController = TextEditingController(text: _product?.stockQuantity.toString() ?? '0');
    _reorderController = TextEditingController(text: _product?.reorderLevel.toString() ?? '5');
    _unitController = TextEditingController(text: _product?.unit ?? 'Pcs');
    _selectedCategoryId = _product?.categoryId;
    _bonusEligible = _product?.bonusEligible ?? true;
  }

  @override
  void dispose() {
    _barcodeController.dispose();
    _nameController.dispose();
    _searchNameController.dispose();
    _displayNameController.dispose();
    _mrpController.dispose();
    _retailPriceController.dispose();
    _wholesalePriceController.dispose();
    _costPriceController.dispose();
    _taxRateController.dispose();
    _stockController.dispose();
    _reorderController.dispose();
    _unitController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final product = Product(
      id: _product?.id ?? '',
      storeId: 'store_default',
      barcode: _barcodeController.text.trim(),
      name: _nameController.text.trim(),
      searchName: _searchNameController.text.trim(),
      displayName: _displayNameController.text.trim(),
      categoryId: _selectedCategoryId,
      unit: _unitController.text.trim(),
      mrp: double.tryParse(_mrpController.text) ?? 0,
      retailPrice: double.tryParse(_retailPriceController.text) ?? 0,
      wholesalePrice: double.tryParse(_wholesalePriceController.text) ?? 0,
      costPrice: double.tryParse(_costPriceController.text) ?? 0,
      taxRate: double.tryParse(_taxRateController.text) ?? 0,
      stockQuantity: int.tryParse(_stockController.text) ?? 0,
      reorderLevel: int.tryParse(_reorderController.text) ?? 5,
      bonusEligible: _bonusEligible,
      isActive: true,
      isDeleted: false,
      createdAt: _product?.createdAt ?? 0,
      updatedAt: _product?.updatedAt,
    );

    final notifier = ref.read(productNotifierProvider.notifier);

    if (_product == null) {
      await notifier.addProduct(product);
    } else {
      await notifier.updateProduct(product);
    }

    if (mounted) context.go('/products');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_product == null ? 'New Product' : 'Edit Product'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _barcodeController,
                decoration: const InputDecoration(labelText: 'Barcode *'),
                validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Product Name *'),
                validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _searchNameController,
                decoration: const InputDecoration(labelText: 'Search Name (English)'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _displayNameController,
                decoration: const InputDecoration(labelText: 'Display Name (Receipt)'),
              ),
              const SizedBox(height: 12),
              _buildCategoryDropdown(),
              const SizedBox(height: 12),
              TextFormField(
                controller: _unitController,
                decoration: const InputDecoration(labelText: 'Unit (e.g., Pcs, Kg, Ltr)'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _mrpController,
                decoration: const InputDecoration(labelText: 'MRP *'),
                keyboardType: TextInputType.number,
                validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _retailPriceController,
                decoration: const InputDecoration(labelText: 'Retail Price *'),
                keyboardType: TextInputType.number,
                validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _wholesalePriceController,
                decoration: const InputDecoration(labelText: 'Wholesale Price'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _costPriceController,
                decoration: const InputDecoration(labelText: 'Cost Price'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _taxRateController,
                decoration: const InputDecoration(labelText: 'Tax Rate (%)'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _stockController,
                decoration: const InputDecoration(labelText: 'Stock Quantity'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _reorderController,
                decoration: const InputDecoration(labelText: 'Reorder Level'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: _bonusEligible,
                onChanged: (val) => setState(() => _bonusEligible = val ?? true),
                title: const Text('Bonus Eligible'),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _save,
                  child: Text(_product == null ? 'CREATE PRODUCT' : 'UPDATE PRODUCT'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryDropdown() {
    return FutureBuilder(
      future: CategoryRepository().getAll(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const DropdownButtonFormField<String>(
            decoration: InputDecoration(labelText: 'Category'),
            items: [],
            onChanged: null,
          );
        }
        final categories = snapshot.data!;
        return DropdownButtonFormField<String>(
          decoration: const InputDecoration(labelText: 'Category'),
          value: _selectedCategoryId,
          items: [
            const DropdownMenuItem(value: null, child: Text('None')),
            ...categories.map((c) {
              return DropdownMenuItem(
                value: c.id,
                child: Text(c.name),
              );
            }),
          ],
          onChanged: (val) => setState(() => _selectedCategoryId = val),
        );
      },
    );
  }
}
'@

    # ========================== CUSTOMER SCREENS ==========================
    "features/customers/screens/customer_list_screen.dart" = @'
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../providers/customer_provider.dart';
import 'customer_form_screen.dart';

class CustomerListScreen extends ConsumerStatefulWidget {
  const CustomerListScreen({super.key});

  @override
  ConsumerState<CustomerListScreen> createState() => _CustomerListScreenState();
}

class _CustomerListScreenState extends ConsumerState<CustomerListScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final customersAsync = ref.watch(customerNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customers'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(customerNotifierProvider),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Search by name or phone',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                if (value.isNotEmpty) {
                  ref.read(customerNotifierProvider.notifier).search(value);
                } else {
                  ref.invalidate(customerNotifierProvider);
                }
              },
            ),
          ),
          Expanded(
            child: customersAsync.when(
              data: (customers) {
                if (customers.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.people, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text('No customers found'),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: customers.length,
                  itemBuilder: (context, index) {
                    final customer = customers[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.purple.shade100,
                          child: Text(
                            customer.name.isNotEmpty ? customer.name[0].toUpperCase() : '?',
                            style: const TextStyle(color: Colors.purple),
                          ),
                        ),
                        title: Text(customer.name),
                        subtitle: Text(
                          '${customer.phone} | ₹${customer.totalSpent.toStringAsFixed(0)} spent',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${customer.loyaltyPoints} pts',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.edit, size: 20),
                              onPressed: () => _navigateToForm(customer),
                            ),
                          ],
                        ),
                        onTap: () => _navigateToForm(customer),
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => Center(
                child: Text(
                  'Error: $err',
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _navigateToForm(),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _navigateToForm([Customer? customer]) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CustomerFormScreen(customer: customer),
      ),
    ).then((_) => ref.invalidate(customerNotifierProvider));
  }
}
'@

    "features/customers/screens/customer_form_screen.dart" = @'
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/customer_model.dart';
import '../../../providers/customer_provider.dart';

class CustomerFormScreen extends ConsumerStatefulWidget {
  final Customer? customer;

  const CustomerFormScreen({super.key, this.customer});

  @override
  ConsumerState<CustomerFormScreen> createState() => _CustomerFormScreenState();
}

class _CustomerFormScreenState extends ConsumerState<CustomerFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late final TextEditingController _addressController;
  late final TextEditingController _localityController;
  late final TextEditingController _creditLimitController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.customer?.name ?? '');
    _phoneController = TextEditingController(text: widget.customer?.phone ?? '');
    _emailController = TextEditingController(text: widget.customer?.email ?? '');
    _addressController = TextEditingController(text: widget.customer?.address ?? '');
    _localityController = TextEditingController(text: widget.customer?.locality ?? '');
    _creditLimitController = TextEditingController(
      text: widget.customer?.creditLimit.toString() ?? '0',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _localityController.dispose();
    _creditLimitController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final customer = Customer(
      id: widget.customer?.id ?? '',
      storeId: 'store_default',
      phone: _phoneController.text.trim(),
      name: _nameController.text.trim(),
      email: _emailController.text.trim().isNotEmpty ? _emailController.text.trim() : null,
      address: _addressController.text.trim().isNotEmpty ? _addressController.text.trim() : null,
      locality: _localityController.text.trim().isNotEmpty ? _localityController.text.trim() : null,
      creditLimit: double.tryParse(_creditLimitController.text) ?? 0,
      loyaltyPoints: widget.customer?.loyaltyPoints ?? 0,
      totalSpent: widget.customer?.totalSpent ?? 0,
      outstandingBalance: widget.customer?.outstandingBalance ?? 0,
      rating: widget.customer?.rating ?? CustomerRating.regular,
      ratingManualOverride: widget.customer?.ratingManualOverride,
      isDeleted: false,
      createdAt: widget.customer?.createdAt ?? 0,
      updatedAt: widget.customer?.updatedAt,
    );

    final notifier = ref.read(customerNotifierProvider.notifier);
    if (widget.customer == null) {
      await notifier.addCustomer(customer);
    } else {
      await notifier.updateCustomer(customer);
    }

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.customer == null ? 'New Customer' : 'Edit Customer'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Full Name *'),
                validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(labelText: 'Phone Number *'),
                keyboardType: TextInputType.phone,
                validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'Email (optional)'),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _addressController,
                decoration: const InputDecoration(labelText: 'Address (optional)'),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _localityController,
                decoration: const InputDecoration(labelText: 'Locality (optional)'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _creditLimitController,
                decoration: const InputDecoration(labelText: 'Credit Limit (₹)'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _save,
                  child: Text(widget.customer == null ? 'CREATE CUSTOMER' : 'UPDATE CUSTOMER'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
'@

    # ========================== SUPPLIER SCREENS ==========================
    "features/suppliers/screens/supplier_list_screen.dart" = @'
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../providers/supplier_provider.dart';
import 'supplier_form_screen.dart';

class SupplierListScreen extends ConsumerStatefulWidget {
  const SupplierListScreen({super.key});

  @override
  ConsumerState<SupplierListScreen> createState() => _SupplierListScreenState();
}

class _SupplierListScreenState extends ConsumerState<SupplierListScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final suppliersAsync = ref.watch(supplierNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Suppliers'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(supplierNotifierProvider),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Search by name or phone',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                if (value.isNotEmpty) {
                  ref.read(supplierNotifierProvider.notifier).search(value);
                } else {
                  ref.invalidate(supplierNotifierProvider);
                }
              },
            ),
          ),
          Expanded(
            child: suppliersAsync.when(
              data: (suppliers) {
                if (suppliers.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.business, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text('No suppliers found'),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: suppliers.length,
                  itemBuilder: (context, index) {
                    final supplier = suppliers[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.blue.shade100,
                          child: Text(supplier.name[0].toUpperCase()),
                        ),
                        title: Text(supplier.name),
                        subtitle: Text('${supplier.phone ?? ''} | Balance: ₹${supplier.openingBalance.toStringAsFixed(0)}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () => _navigateToForm(supplier),
                        ),
                        onTap: () => _navigateToForm(supplier),
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => Center(child: Text('Error: $err')),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _navigateToForm(),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _navigateToForm([Supplier? supplier]) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SupplierFormScreen(supplier: supplier),
      ),
    ).then((_) => ref.invalidate(supplierNotifierProvider));
  }
}
'@

    "features/suppliers/screens/supplier_form_screen.dart" = @'
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/supplier_model.dart';
import '../../../providers/supplier_provider.dart';

class SupplierFormScreen extends ConsumerStatefulWidget {
  final Supplier? supplier;

  const SupplierFormScreen({super.key, this.supplier});

  @override
  ConsumerState<SupplierFormScreen> createState() => _SupplierFormScreenState();
}

class _SupplierFormScreenState extends ConsumerState<SupplierFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late final TextEditingController _addressController;
  late final TextEditingController _openingBalanceController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.supplier?.name ?? '');
    _phoneController = TextEditingController(text: widget.supplier?.phone ?? '');
    _emailController = TextEditingController(text: widget.supplier?.email ?? '');
    _addressController = TextEditingController(text: widget.supplier?.address ?? '');
    _openingBalanceController = TextEditingController(
      text: widget.supplier?.openingBalance.toString() ?? '0',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _openingBalanceController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final supplier = Supplier(
      id: widget.supplier?.id ?? '',
      storeId: 'store_default',
      name: _nameController.text.trim(),
      phone: _phoneController.text.trim().isNotEmpty ? _phoneController.text.trim() : null,
      email: _emailController.text.trim().isNotEmpty ? _emailController.text.trim() : null,
      address: _addressController.text.trim().isNotEmpty ? _addressController.text.trim() : null,
      openingBalance: double.tryParse(_openingBalanceController.text) ?? 0,
      isDeleted: false,
      createdAt: widget.supplier?.createdAt ?? 0,
    );

    final notifier = ref.read(supplierNotifierProvider.notifier);
    if (widget.supplier == null) {
      await notifier.addSupplier(supplier);
    } else {
      await notifier.updateSupplier(supplier);
    }

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.supplier == null ? 'New Supplier' : 'Edit Supplier'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Supplier Name *'),
                validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(labelText: 'Phone'),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _addressController,
                decoration: const InputDecoration(labelText: 'Address'),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _openingBalanceController,
                decoration: const InputDecoration(labelText: 'Opening Balance (₹)'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _save,
                  child: Text(widget.supplier == null ? 'CREATE SUPPLIER' : 'UPDATE SUPPLIER'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
'@

    # ========================== PURCHASE SCREENS ==========================
    # These are large files – I'll include minimal working versions

    "features/purchases/screens/purchase_list_screen.dart" = @'
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../providers/purchase_provider.dart';
import 'purchase_form_screen.dart';

class PurchaseListScreen extends ConsumerStatefulWidget {
  const PurchaseListScreen({super.key});

  @override
  ConsumerState<PurchaseListScreen> createState() => _PurchaseListScreenState();
}

class _PurchaseListScreenState extends ConsumerState<PurchaseListScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final purchasesAsync = ref.watch(purchaseNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Purchases'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(purchaseNotifierProvider.notifier).refresh(),
          ),
        ],
      ),
      body: purchasesAsync.when(
        data: (purchases) {
          if (purchases.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.receipt_long, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('No purchase records'),
                  SizedBox(height: 8),
                  Text('Tap + to record a new purchase'),
                ],
              ),
            );
          }
          return ListView.builder(
            itemCount: purchases.length,
            itemBuilder: (context, index) {
              final purchase = purchases[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: ListTile(
                  leading: const Icon(Icons.receipt),
                  title: Text('GRN: ${purchase.grnNo}'),
                  subtitle: Text(
                    'Supplier: ${purchase.supplierName ?? "N/A"} | ₹${purchase.netAmount.toStringAsFixed(2)}',
                  ),
                  trailing: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        DateTime.fromMillisecondsSinceEpoch(
                          purchase.createdAt * 1000,
                        ).toLocal().toString().split(' ')[0],
                        style: const TextStyle(fontSize: 12),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: purchase.received ? Colors.green : Colors.orange,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          purchase.received ? 'Received' : 'Pending',
                          style: const TextStyle(fontSize: 10, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PurchaseFormScreen(existingPurchase: purchase),
                      ),
                    ).then((_) => ref.read(purchaseNotifierProvider.notifier).refresh());
                  },
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const PurchaseFormScreen()),
          ).then((_) => ref.read(purchaseNotifierProvider.notifier).refresh());
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
'@

    "features/purchases/screens/purchase_form_screen.dart" = @'
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/purchase_model.dart';
import '../../../models/purchase_item_model.dart';
import '../../../models/product_model.dart';
import '../../../models/supplier_model.dart';
import '../../../providers/product_provider.dart';
import '../../../providers/supplier_provider.dart';
import '../../../repositories/purchase_repository.dart';

class PurchaseFormScreen extends ConsumerStatefulWidget {
  final Purchase? existingPurchase;

  const PurchaseFormScreen({super.key, this.existingPurchase});

  @override
  ConsumerState<PurchaseFormScreen> createState() => _PurchaseFormScreenState();
}

class _PurchaseFormScreenState extends ConsumerState<PurchaseFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();

  // Basic fields only for now – full implementation would include all GRN fields
  late final TextEditingController _grnController;
  late final TextEditingController _supplierController;
  List<PurchaseItem> _items = [];
  Supplier? _selectedSupplier;

  @override
  void initState() {
    super.initState();
    _grnController = TextEditingController(text: widget.existingPurchase?.grnNo ?? '');
    _supplierController = TextEditingController();
  }

  @override
  void dispose() {
    _grnController.dispose();
    _supplierController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Purchase form coming soon')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existingPurchase == null ? 'New Purchase' : 'Edit Purchase'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _save,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextFormField(
              controller: _grnController,
              decoration: const InputDecoration(labelText: 'GRN No'),
            ),
            const SizedBox(height: 12),
            Consumer(
              builder: (context, ref, child) {
                final suppliersAsync = ref.watch(supplierNotifierProvider);
                return suppliersAsync.when(
                  data: (suppliers) {
                    return DropdownButtonFormField<Supplier>(
                      value: _selectedSupplier,
                      decoration: const InputDecoration(labelText: 'Supplier'),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('Select Supplier')),
                        ...suppliers.map((s) {
                          return DropdownMenuItem(
                            value: s,
                            child: Text(s.name),
                          );
                        }),
                      ],
                      onChanged: (val) => setState(() => _selectedSupplier = val),
                    );
                  },
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (err, stack) => Text('Error: $err'),
                );
              },
            ),
            const SizedBox(height: 24),
            const Expanded(
              child: Center(child: Text('Purchase items grid coming soon')),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _save,
                child: const Text('SAVE PURCHASE'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
'@

    # ========================== COUNTER SCREENS ==========================
    "features/counter/screens/counter_open_screen.dart" = @'
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../services/counter_service.dart';
import '../../../providers/auth_provider.dart';

class CounterOpenScreen extends ConsumerStatefulWidget {
  const CounterOpenScreen({super.key});

  @override
  ConsumerState<CounterOpenScreen> createState() => _CounterOpenScreenState();
}

class _CounterOpenScreenState extends ConsumerState<CounterOpenScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _cashController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  bool _isLoading = false;

  // Denomination controllers
  final Map<String, TextEditingController> _denomControllers = {
    '2000': TextEditingController(),
    '500': TextEditingController(),
    '200': TextEditingController(),
    '100': TextEditingController(),
    '50': TextEditingController(),
    '20': TextEditingController(),
    '10': TextEditingController(),
    '5': TextEditingController(),
    '2': TextEditingController(),
    '1': TextEditingController(),
  };

  @override
  void dispose() {
    _cashController.dispose();
    _notesController.dispose();
    for (final c in _denomControllers.values) c.dispose();
    super.dispose();
  }

  Future<void> _openShift() async {
    if (!_formKey.currentState!.validate()) return;

    final openingCash = double.tryParse(_cashController.text) ?? 0;
    final notes = _notesController.text.trim();

    // Build denomination map
    final denoms = <String, int>{};
    for (final entry in _denomControllers.entries) {
      final count = int.tryParse(entry.value.text) ?? 0;
      if (count > 0) {
        denoms[entry.key] = count;
      }
    }

    setState(() => _isLoading = true);

    final user = ref.read(authProvider);
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login first'), backgroundColor: Colors.red),
      );
      setState(() => _isLoading = false);
      return;
    }

    try {
      final service = CounterService();
      await service.openShift(
        userId: user.id,
        openingCash: openingCash,
        denominations: denoms,
        notes: notes.isNotEmpty ? notes : null,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Shift opened successfully!'), backgroundColor: Colors.green),
      );
      context.go('/dashboard');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }

    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Open Shift')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            TextFormField(
              controller: _cashController,
              decoration: const InputDecoration(labelText: 'Opening Cash (₹) *'),
              keyboardType: TextInputType.number,
              validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            const Text('Opening Denominations:', style: TextStyle(fontWeight: FontWeight.bold)),
            ..._denomControllers.keys.map((denom) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Row(
                  children: [
                    SizedBox(width: 60, child: Text('₹$denom x')),
                    Expanded(
                      child: TextFormField(
                        controller: _denomControllers[denom],
                        decoration: const InputDecoration(border: OutlineInputBorder()),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 16),
            TextFormField(
              controller: _notesController,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
              maxLines: 2,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton(
                      onPressed: _openShift,
                      child: const Text('OPEN SHIFT', style: TextStyle(fontSize: 16)),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
'@

    "features/counter/screens/counter_close_screen.dart" = @'
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../services/counter_service.dart';
import '../../../providers/auth_provider.dart';

class CounterCloseScreen extends ConsumerStatefulWidget {
  const CounterCloseScreen({super.key});

  @override
  ConsumerState<CounterCloseScreen> createState() => _CounterCloseScreenState();
}

class _CounterCloseScreenState extends ConsumerState<CounterCloseScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _cashController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  bool _isLoading = false;

  final Map<String, TextEditingController> _denomControllers = {
    '2000': TextEditingController(),
    '500': TextEditingController(),
    '200': TextEditingController(),
    '100': TextEditingController(),
    '50': TextEditingController(),
    '20': TextEditingController(),
    '10': TextEditingController(),
    '5': TextEditingController(),
    '2': TextEditingController(),
    '1': TextEditingController(),
  };

  @override
  void dispose() {
    _cashController.dispose();
    _notesController.dispose();
    for (final c in _denomControllers.values) c.dispose();
    super.dispose();
  }

  Future<void> _closeShift() async {
    if (!_formKey.currentState!.validate()) return;

    final closingCash = double.tryParse(_cashController.text) ?? 0;
    final notes = _notesController.text.trim();

    final denoms = <String, int>{};
    for (final entry in _denomControllers.entries) {
      final count = int.tryParse(entry.value.text) ?? 0;
      if (count > 0) denoms[entry.key] = count;
    }

    setState(() => _isLoading = true);

    final user = ref.read(authProvider);
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login first'), backgroundColor: Colors.red),
      );
      setState(() => _isLoading = false);
      return;
    }

    try {
      final service = CounterService();
      final session = await service.getActiveSession(user.id);
      if (session == null) {
        throw Exception('No open shift found.');
      }
      final closed = await service.closeShift(
        sessionId: session.id,
        closingCash: closingCash,
        denominations: denoms,
        notes: notes.isNotEmpty ? notes : null,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Shift closed successfully!'), backgroundColor: Colors.green),
      );
      context.go('/dashboard');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }

    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Close Shift')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            TextFormField(
              controller: _cashController,
              decoration: const InputDecoration(labelText: 'Closing Cash (₹) *'),
              keyboardType: TextInputType.number,
              validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            const Text('Closing Denominations:', style: TextStyle(fontWeight: FontWeight.bold)),
            ..._denomControllers.keys.map((denom) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Row(
                  children: [
                    SizedBox(width: 60, child: Text('₹$denom x')),
                    Expanded(
                      child: TextFormField(
                        controller: _denomControllers[denom],
                        decoration: const InputDecoration(border: OutlineInputBorder()),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 16),
            TextFormField(
              controller: _notesController,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
              maxLines: 2,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton(
                      onPressed: _closeShift,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('CLOSE SHIFT', style: TextStyle(fontSize: 16)),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
'@

    # ========================== REPORT SCREENS ==========================
    "features/reports/screens/sales_report_screen.dart" = @'
import 'package:flutter/material.dart';

class SalesReportScreen extends StatelessWidget {
  const SalesReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sales Report')),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.assessment, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('Sales Report coming soon'),
          ],
        ),
      ),
    );
  }
}
'@

    "features/reports/screens/customer_history_screen.dart" = @'
import 'package:flutter/material.dart';

class CustomerHistoryScreen extends StatelessWidget {
  const CustomerHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Customer History')),
      body: const Center(child: Text('Customer history coming soon')),
    );
  }
}
'@

    "features/reports/screens/product_performance_screen.dart" = @'
import 'package:flutter/material.dart';

class ProductPerformanceScreen extends StatelessWidget {
  const ProductPerformanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Product Performance')),
      body: const Center(child: Text('Product performance coming soon')),
    );
  }
}
'@

    "features/reports/screens/ai_analysis_screen.dart" = @'
import 'package:flutter/material.dart';

class AIAnalysisScreen extends StatelessWidget {
  const AIAnalysisScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI Analysis')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.auto_awesome, size: 64, color: Colors.purple),
              SizedBox(height: 16),
              Text('AI Analysis coming soon'),
              SizedBox(height: 8),
              Text('This will use OpenAI API for insights', style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }
}
'@

    # ========================== SETTINGS SCREEN ==========================
    "features/settings/screens/settings_screen.dart" = @'
import 'package:flutter/material.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const ListTile(
            leading: Icon(Icons.currency_rupee),
            title: Text('Currency'),
            subtitle: Text('INR (₹)'),
          ),
          const Divider(),
          const ListTile(
            leading: Icon(Icons.local_tax),
            title: Text('Default Tax Rate'),
            subtitle: Text('5%'),
          ),
          const Divider(),
          const ListTile(
            leading: Icon(Icons.card_giftcard),
            title: Text('Bonus Threshold'),
            subtitle: Text('₹300'),
          ),
          const Divider(),
          const ListTile(
            leading: Icon(Icons.warning),
            title: Text('MRP Warning Multiplier'),
            subtitle: Text('2x'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.backup),
            title: const Text('Export Database'),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Export coming soon')),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.restore),
            title: const Text('Import Database'),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Import coming soon')),
              );
            },
          ),
        ],
      ),
    );
  }
}
'@

    # ========================== USER SCREENS ==========================
    "features/users/screens/user_list_screen.dart" = @'
import 'package:flutter/material.dart';

class UserListScreen extends StatelessWidget {
  const UserListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Users')),
      body: const Center(child: Text('User management coming soon')),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        child: const Icon(Icons.add),
      ),
    );
  }
}
'@

    "features/users/screens/user_form_screen.dart" = @'
import 'package:flutter/material.dart';

class UserFormScreen extends StatelessWidget {
  const UserFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('User Form')),
      body: const Center(child: Text('User form coming soon')),
    );
  }
}
'@

    # ========================== CREDIT SCREEN ==========================
    "features/credit/screens/receive_payment_screen.dart" = @'
import 'package:flutter/material.dart';

class ReceivePaymentScreen extends StatelessWidget {
  const ReceivePaymentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Receive Payment')),
      body: const Center(child: Text('Receive payment coming soon')),
    );
  }
}
'@
}

# Write all UI files
foreach ($key in $uiFiles.Keys) {
    $fullPath = Join-Path $base $key
    $dir = Split-Path $fullPath
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    Set-Content -Path $fullPath -Value $uiFiles[$key] -Force
    Write-Host "Added: $key" -ForegroundColor Green
}

Write-Host "`n✅ All UI screens added successfully!" -ForegroundColor Green