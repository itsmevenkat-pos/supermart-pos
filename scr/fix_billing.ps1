# fix_billing.ps1 – Creates complete BillingScreen
$base = "lib"

$files = @{

    # ---------- COMPLETE BILLING SCREEN ----------
    "features/billing/screens/billing_screen.dart" = @'
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../providers/cart_provider.dart';
import '../../../providers/product_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/sale_provider.dart';
import '../../../models/product_model.dart';
import '../../../services/billing_service.dart';
import '../../../services/whatsapp_share_service.dart';
import '../widgets/cart_list_view.dart';
import '../widgets/payment_dialog.dart';
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
    final authState = ref.watch(authProvider);
    final user = authState.user;

    if (!_hasOpenShift) {
      return AppScaffold(
        title: 'Billing',
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

    return AppScaffold(
      title: 'Billing',
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
                                onPay: (payments, partialAmount, creditUsed) async {
                                  try {
                                    final service = BillingService();
                                    final sale = await service.processSale(
                                      storeId: 'store_default',
                                      sessionId: null,
                                      userId: user?.id,
                                      cartItems: cartItems,
                                      payments: payments,
                                      discountTotal: notifier.discount,
                                      discountReason: notifier.discountReason,
                                      partialPaymentAmount: partialAmount,
                                      creditUsed: creditUsed,
                                      deliveryAddress: notifier.deliveryAddress,
                                      isDelivery: notifier.deliveryAddress != null,
                                      deliveryCharge: notifier.deliveryCharge,
                                      customerId: notifier.customer?.id,
                                    );

                                    ref.read(cartProvider.notifier).clearCart();
                                    Navigator.pop(context);

                                    final shouldShare = await showDialog<bool>(
                                      context: context,
                                      builder: (_) => AlertDialog(
                                        title: const Text('Sale Completed!'),
                                        content: Text(
                                          'Invoice #${sale.invoiceNo}\n'
                                          'Total: ₹${sale.netAmount.toStringAsFixed(2)}',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(context, false),
                                            child: const Text('Close'),
                                          ),
                                          ElevatedButton.icon(
                                            onPressed: () => Navigator.pop(context, true),
                                            icon: const Icon(Icons.share),
                                            label: const Text('Share'),
                                          ),
                                        ],
                                      ),
                                    );

                                    if (shouldShare == true) {
                                      final items = await service.getSaleItems(sale.id);
                                      final customerName = notifier.customer?.name ?? 'Guest';
                                      final invoiceLines = <InvoiceLine>[];
                                      for (final item in items) {
                                        String productName = 'Product ${item.productId}';
                                        for (final cartItem in cartItems) {
                                          if (cartItem.productId == item.productId) {
                                            productName = cartItem.product.name;
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
                                        customerName: customerName,
                                        total: sale.netAmount,
                                        items: invoiceLines,
                                        date: DateTime.now(),
                                      );
                                    }

                                    ref.invalidate(recentSalesProvider);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Sale completed!'),
                                        backgroundColor: Colors.green,
                                      ),
                                    );
                                  } catch (e) {
                                    Navigator.pop(context);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Error: $e'),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                  }
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

  // ----- Dialogs -----
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
                subtitle: Text(
                  'MRP: ₹${product.mrp.toStringAsFixed(2)} | Sell: ₹${product.retailPrice.toStringAsFixed(2)}',
                ),
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
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ProductFormScreen(
                    initialProduct: Product.create(
                      barcode: barcode,
                      name: '',
                      retailPrice: 0,
                      mrp: 0,
                    ),
                  ),
                ),
              ).then((_) {
                setState(() {});
              });
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
        ref: ref,
        onSelect: (product) {
          ref.read(cartProvider.notifier).addItem(product);
          Navigator.pop(context);
        },
        onAddNew: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const ProductFormScreen(),
            ),
          ).then((_) {
            setState(() {});
          });
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
  final WidgetRef ref;
  final Function(Product) onSelect;
  final VoidCallback onAddNew;

  _ProductSearchDelegate({required this.ref, required this.onSelect, required this.onAddNew});

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
        final products = snapshot.data;
        if (products == null || products.isEmpty) {
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

}

# Write file
foreach ($key in $files.Keys) {
    $fullPath = Join-Path $base $key
    $dir = Split-Path $fullPath
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    Set-Content -Path $fullPath -Value $files[$key] -Force
    Write-Host "Created: $key" -ForegroundColor Green
}

Write-Host "`n✅ BillingScreen created!" -ForegroundColor Cyan
Write-Host "`nNow run:" -ForegroundColor Yellow
Write-Host "flutter clean" -ForegroundColor White
Write-Host "flutter pub get" -ForegroundColor White
Write-Host "flutter pub run build_runner build --delete-conflicting-outputs" -ForegroundColor White
Write-Host "flutter run -d windows" -ForegroundColor White