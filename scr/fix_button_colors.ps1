# fix_button_colors.ps1 – Fixes payment button colors
$base = "lib"

$files = @{

    # ---------- FIXED BILLING SCREEN ----------
    "features/billing/screens/billing_screen.dart" = @'
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../providers/cart_provider.dart';
import '../../../providers/product_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/sale_provider.dart';
import '../../../providers/quotation_provider.dart';
import '../../../models/product_model.dart';
import '../../../models/quotation_model.dart';
import '../../../services/billing_service.dart';
import '../../../services/whatsapp_share_service.dart';
import '../widgets/product_grid.dart';
import '../widgets/cart_list_view.dart';
import '../widgets/payment_dialog.dart';
import '../widgets/quotation_dialog.dart';
import '../../products/screens/product_form_screen.dart';
import '../../customers/screens/customer_form_screen.dart';

class BillingScreen extends ConsumerStatefulWidget {
  const BillingScreen({super.key});

  @override
  ConsumerState<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends ConsumerState<BillingScreen> {
  final TextEditingController _barcodeController = TextEditingController();
  final FocusNode _barcodeFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _barcodeFocus.requestFocus();
  }

  @override
  void dispose() {
    _barcodeController.dispose();
    _barcodeFocus.dispose();
    super.dispose();
  }

  void _handleBarcode(String value) async {
    if (value.isEmpty) return;
    final products = await ref.read(productNotifierProvider.notifier).fetchByBarcode(value);
    if (products.isNotEmpty) {
      if (products.length == 1) {
        ref.read(cartProvider.notifier).addItem(products.first);
        _barcodeController.clear();
      } else {
        _showMRPSelectionDialog(products);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Product not found'), backgroundColor: Colors.red),
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

  void _showCustomerDialog() async {
    showDialog(
      context: context,
      builder: (_) => CustomerFormScreen(
        onSaved: (customer) {
          ref.read(cartProvider.notifier).setCustomer(customer);
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

  @override
  Widget build(BuildContext context) {
    final cartItems = ref.watch(cartProvider);
    final notifier = ref.read(cartProvider.notifier);
    final authState = ref.watch(authProvider);
    final user = authState.user;

    final subtotal = cartItems.fold(
      0.0,
      (sum, item) => sum + (item.product.retailPrice * item.quantity),
    );
    final totalTax = cartItems.fold(
      0.0,
      (sum, item) => sum + ((item.product.retailPrice * item.quantity * item.product.taxRate) / 100),
    );
    final grandTotal = subtotal + totalTax + notifier.deliveryCharge - notifier.discount;

    // Get theme color
    final primaryColor = Theme.of(context).primaryColor;
    final buttonColor = primaryColor;
    final buttonTextColor = Colors.white;

    return AppScaffold(
      title: 'Billing',
      actions: [
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
                onProductSelected: (product) {
                  ref.read(cartProvider.notifier).addItem(product);
                },
              ),
            ),
          ),
          Expanded(
            flex: 6,
            child: Column(
              children: [
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
                                  ? '${notifier.customer!.name}'
                                  : 'No Customer',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 16),
                            if (notifier.customer != null) ...[
                              Text(
                                'Points: ${notifier.customer!.loyaltyPoints}',
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
                Expanded(
                  child: CartListView(
                    items: cartItems,
                    onQuantityChange: (id, qty) =>
                        ref.read(cartProvider.notifier).updateQuantity(id, qty),
                    onRemove: (id) => ref.read(cartProvider.notifier).removeItem(id),
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
                            Text('Discount:'),
                            Text(' -₹${notifier.discount.toStringAsFixed(2)}'),
                          ],
                        ),
                      const Divider(thickness: 2),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Total:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                          Text(
                            '₹${grandTotal.toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          // All buttons now use the same theme color
                          _actionButton('Customer', Icons.person, buttonColor, 'F1', _showCustomerDialog),
                          _actionButton('Discount', Icons.percent, buttonColor, 'F2', _showDiscountDialog),
                          _actionButton('Hold', Icons.save, buttonColor, 'F3', () {
                            ref.read(cartProvider.notifier).clearCart();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Bill held!'), backgroundColor: Colors.blue),
                            );
                          }),
                          _actionButton('Cash', Icons.money, buttonColor, 'F4', () {
                            _showPaymentDialog({'cash': grandTotal});
                          }),
                          _actionButton('UPI', Icons.qr_code, buttonColor, 'F5', () {
                            _showPaymentDialog({'upi': grandTotal});
                          }),
                          _actionButton('Card', Icons.credit_card, buttonColor, 'F6', () {
                            _showPaymentDialog({'card': grandTotal});
                          }),
                          _actionButton('Credit', Icons.account_balance, buttonColor, 'F7', () {
                            if (notifier.customer == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Please select a customer for credit payment'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                              return;
                            }
                            _showPaymentDialog({'credit': grandTotal});
                          }),
                          _actionButton('Share', Icons.share, buttonColor, 'F8', () async {
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
                          }),
                          _actionButton('Quotation', Icons.description, buttonColor, 'F9', _showQuotationDialog),
                          _actionButton('Pay', Icons.payment, Colors.green.shade700, 'Enter', () {
                            _showPaymentDialog(null);
                          }),
                        ],
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
  }

  Widget _actionButton(String label, IconData icon, Color color, String shortcut, VoidCallback onPressed) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          Text(shortcut, style: const TextStyle(fontSize: 9, color: Colors.white70)),
        ],
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        minimumSize: const Size(55, 42),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
        elevation: 2,
      ),
    );
  }

  void _showPaymentDialog(Map<String, double>? preFilled) {
    final cartItems = ref.watch(cartProvider);
    final notifier = ref.read(cartProvider.notifier);

    final subtotal = cartItems.fold(
      0.0,
      (sum, item) => sum + (item.product.retailPrice * item.quantity),
    );
    final totalTax = cartItems.fold(
      0.0,
      (sum, item) => sum + ((item.product.retailPrice * item.quantity * item.product.taxRate) / 100),
    );
    final grandTotal = subtotal + totalTax + notifier.deliveryCharge - notifier.discount;

    if (cartItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cart is empty'), backgroundColor: Colors.red),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (_) => PaymentDialog(
        total: grandTotal,
        customer: notifier.customer,
        onPay: (payments, partialAmount, creditUsed) async {
          try {
            final authState = ref.watch(authProvider);
            final user = authState.user;

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
                customerName: customerName,
                total: sale.netAmount,
                items: invoiceLines,
                date: DateTime.now(),
              );
            }

            ref.invalidate(recentSalesProvider);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Sale completed!'), backgroundColor: Colors.green),
            );
          } catch (e) {
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

    final subtotal = cartItems.fold(
      0.0,
      (sum, item) => sum + (item.product.retailPrice * item.quantity),
    );
    final totalTax = cartItems.fold(
      0.0,
      (sum, item) => sum + ((item.product.retailPrice * item.quantity * item.product.taxRate) / 100),
    );
    final grandTotal = subtotal + totalTax + notifier.deliveryCharge - notifier.discount;

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

          await ref.read(quotationNotifierProvider.notifier).addQuotation(quotation);

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
'@

}

# Write all files
foreach ($key in $files.Keys) {
    $fullPath = Join-Path $base $key
    $dir = Split-Path $fullPath
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    Set-Content -Path $fullPath -Value $files[$key] -Force
    Write-Host "Fixed: $key" -ForegroundColor Green
}

Write-Host "`n✅ Button colors fixed!" -ForegroundColor Cyan
Write-Host "`nNow run:" -ForegroundColor Yellow
Write-Host "flutter run -d windows" -ForegroundColor White