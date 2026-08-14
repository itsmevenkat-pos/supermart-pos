# final_billing_update.ps1 – Complete Billing Module Redesign
$ErrorActionPreference = "Stop"
$base = "lib"

Write-Host "🚀 Generating SuperMart POS - Complete Billing Module..." -ForegroundColor Cyan

$files = @{

    # ---------- APP SCAFFOLD (Updated with FAB) ----------
    "core/widgets/app_scaffold.dart" = @'
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AppScaffold extends StatelessWidget {
  final Widget body;
  final String title;
  final bool showBackButton;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;

  const AppScaffold({
    super.key,
    required this.body,
    required this.title,
    this.showBackButton = true,
    this.actions,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: showBackButton
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/dashboard');
                  }
                },
              )
            : null,
        actions: actions,
      ),
      drawer: _buildDrawer(context),
      body: body,
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: floatingActionButtonLocation,
    );
  }

  Widget _buildDrawer(BuildContext context) {
    return Drawer(
      child: ListView(
        children: [
          const DrawerHeader(
            child: Text('SuperMart POS', style: TextStyle(fontSize: 24)),
          ),
          _drawerTile(context, 'Dashboard', Icons.dashboard, '/dashboard'),
          _drawerTile(context, 'Billing', Icons.point_of_sale, '/billing'),
          _drawerTile(context, 'Products', Icons.inventory, '/products'),
          _drawerTile(context, 'Customers', Icons.people, '/customers'),
          _drawerTile(context, 'Suppliers', Icons.business, '/suppliers'),
          _drawerTile(context, 'Purchases', Icons.receipt_long, '/purchases'),
          _drawerTile(context, 'Sales History', Icons.history, '/sales-history'),
          _drawerTile(context, 'Sales Summary', Icons.pie_chart, '/sales-summary'),
          _drawerTile(context, 'Quotations', Icons.description, '/quotations'),
          _drawerTile(context, 'Reports', Icons.assessment, '/reports/sales'),
          _drawerTile(context, 'Users', Icons.people_outline, '/users'),
          _drawerTile(context, 'Settings', Icons.settings, '/settings'),
        ],
      ),
    );
  }

  Widget _drawerTile(BuildContext context, String title, IconData icon, String route) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      onTap: () {
        Navigator.pop(context);
        context.go(route);
      },
    );
  }
}
'@

    # ---------- QUOTATION MODEL ----------
    "models/quotation_model.dart" = @'
import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

class Quotation extends Equatable {
  final String id;
  final String? storeId;
  final String? customerId;
  final String customerName;
  final String? customerPhone;
  final String? customerEmail;
  final String quoteNo;
  final double subtotal;
  final double taxTotal;
  final double discountTotal;
  final String? discountReason;
  final double netAmount;
  final String? notes;
  final int expiryDate; // Unix timestamp
  final String status; // pending, converted, expired
  final int createdAt;
  final int? updatedAt;

  const Quotation({
    required this.id,
    this.storeId,
    this.customerId,
    required this.customerName,
    this.customerPhone,
    this.customerEmail,
    required this.quoteNo,
    this.subtotal = 0,
    this.taxTotal = 0,
    this.discountTotal = 0,
    this.discountReason,
    this.netAmount = 0,
    this.notes,
    this.expiryDate = 0,
    this.status = 'pending',
    this.createdAt = 0,
    this.updatedAt,
  });

  factory Quotation.create({
    String? storeId,
    String? customerId,
    required String customerName,
    String? customerPhone,
    String? customerEmail,
    double subtotal = 0,
    double taxTotal = 0,
    double discountTotal = 0,
    String? discountReason,
    double netAmount = 0,
    String? notes,
    int expiryDate = 0,
  }) {
    return Quotation(
      id: const Uuid().v4(),
      storeId: storeId,
      customerId: customerId,
      customerName: customerName,
      customerPhone: customerPhone,
      customerEmail: customerEmail,
      quoteNo: 'QUOT-${DateTime.now().millisecondsSinceEpoch}',
      subtotal: subtotal,
      taxTotal: taxTotal,
      discountTotal: discountTotal,
      discountReason: discountReason,
      netAmount: netAmount,
      notes: notes,
      expiryDate: expiryDate,
    );
  }

  Quotation copyWith({
    String? customerId,
    String? customerName,
    String? customerPhone,
    String? customerEmail,
    double? subtotal,
    double? taxTotal,
    double? discountTotal,
    String? discountReason,
    double? netAmount,
    String? notes,
    int? expiryDate,
    String? status,
  }) {
    return Quotation(
      id: id,
      storeId: storeId,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      customerEmail: customerEmail ?? this.customerEmail,
      quoteNo: quoteNo,
      subtotal: subtotal ?? this.subtotal,
      taxTotal: taxTotal ?? this.taxTotal,
      discountTotal: discountTotal ?? this.discountTotal,
      discountReason: discountReason ?? this.discountReason,
      netAmount: netAmount ?? this.netAmount,
      notes: notes ?? this.notes,
      expiryDate: expiryDate ?? this.expiryDate,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'store_id': storeId,
        'customer_id': customerId,
        'customer_name': customerName,
        'customer_phone': customerPhone,
        'customer_email': customerEmail,
        'quote_no': quoteNo,
        'subtotal': subtotal,
        'tax_total': taxTotal,
        'discount_total': discountTotal,
        'discount_reason': discountReason,
        'net_amount': netAmount,
        'notes': notes,
        'expiry_date': expiryDate,
        'status': status,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory Quotation.fromJson(Map<String, dynamic> map) => Quotation(
        id: map['id'] as String,
        storeId: map['store_id'] as String?,
        customerId: map['customer_id'] as String?,
        customerName: map['customer_name'] as String,
        customerPhone: map['customer_phone'] as String?,
        customerEmail: map['customer_email'] as String?,
        quoteNo: map['quote_no'] as String,
        subtotal: (map['subtotal'] as num?)?.toDouble() ?? 0,
        taxTotal: (map['tax_total'] as num?)?.toDouble() ?? 0,
        discountTotal: (map['discount_total'] as num?)?.toDouble() ?? 0,
        discountReason: map['discount_reason'] as String?,
        netAmount: (map['net_amount'] as num?)?.toDouble() ?? 0,
        notes: map['notes'] as String?,
        expiryDate: map['expiry_date'] as int? ?? 0,
        status: map['status'] as String? ?? 'pending',
        createdAt: map['created_at'] as int? ?? 0,
        updatedAt: map['updated_at'] as int?,
      );

  @override
  List<Object?> get props => [id, quoteNo, customerName, netAmount, status];
}
'@

    # ---------- QUOTATION REPOSITORY ----------
    "repositories/quotation_repository.dart" = @'
import '../core/database/database_helper.dart';
import '../models/quotation_model.dart';

class QuotationRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<void> insert(Quotation quotation) async {
    final db = await _dbHelper.database;
    await db.insert('quotations', quotation.toJson());
    await _dbHelper.queueSync('quotations', quotation.id, 'INSERT', quotation.toJson());
  }

  Future<void> update(Quotation quotation) async {
    final db = await _dbHelper.database;
    await db.update('quotations', quotation.toJson(), where: 'id = ?', whereArgs: [quotation.id]);
    await _dbHelper.queueSync('quotations', quotation.id, 'UPDATE', quotation.toJson());
  }

  Future<List<Quotation>> getAll({String? status}) async {
    final db = await _dbHelper.database;
    final where = status != null ? 'WHERE status = ?' : '';
    final args = status != null ? [status] : <Object?>[];
    final result = await db.query(
      'quotations',
      where: where.isNotEmpty ? where : null,
      whereArgs: args.isNotEmpty ? args : null,
      orderBy: 'created_at DESC',
    );
    return result.map((e) => Quotation.fromJson(e)).toList();
  }

  Future<Quotation?> getById(String id) async {
    final db = await _dbHelper.database;
    final result = await db.query('quotations', where: 'id = ?', whereArgs: [id]);
    if (result.isEmpty) return null;
    return Quotation.fromJson(result.first);
  }

  Future<void> delete(String id) async {
    final db = await _dbHelper.database;
    await db.delete('quotations', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateStatus(String id, String status) async {
    final db = await _dbHelper.database;
    await db.update(
      'quotations',
      {'status': status, 'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
'@

    # ---------- QUOTATION PROVIDER ----------
    "providers/quotation_provider.dart" = @'
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../models/quotation_model.dart';
import '../repositories/quotation_repository.dart';

part 'quotation_provider.g.dart';

@riverpod
class QuotationNotifier extends _$QuotationNotifier {
  final QuotationRepository _repo = QuotationRepository();

  @override
  Future<List<Quotation>> build() async {
    return await _repo.getAll();
  }

  Future<void> addQuotation(Quotation quotation) async {
    await _repo.insert(quotation);
    ref.invalidateSelf();
  }

  Future<void> updateQuotation(Quotation quotation) async {
    await _repo.update(quotation);
    ref.invalidateSelf();
  }

  Future<void> deleteQuotation(String id) async {
    await _repo.delete(id);
    ref.invalidateSelf();
  }

  Future<void> updateStatus(String id, String status) async {
    await _repo.updateStatus(id, status);
    ref.invalidateSelf();
  }

  Future<List<Quotation>> getByStatus(String status) async {
    return await _repo.getAll(status: status);
  }

  Future<Quotation?> getById(String id) async {
    return await _repo.getById(id);
  }
}
'@

    # ---------- SALES SUMMARY SERVICE ----------
    "services/sales_summary_service.dart" = @'
import '../core/database/database_helper.dart';
import '../models/sale_model.dart';

class SalesSummaryService {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<Map<String, dynamic>> getSummary({DateTime? from, DateTime? to}) async {
    final db = await _dbHelper.database;
    final fromTime = from != null ? from.millisecondsSinceEpoch ~/ 1000 : 0;
    final toTime = to != null ? to.millisecondsSinceEpoch ~/ 1000 : DateTime.now().millisecondsSinceEpoch ~/ 1000;

    // Get all sales in date range
    final result = await db.query(
      'sales',
      where: 'created_at >= ? AND created_at <= ? AND status = "completed"',
      whereArgs: [fromTime, toTime],
    );

    double totalCash = 0;
    double totalUpi = 0;
    double totalCard = 0;
    double totalCredit = 0;
    double totalPartial = 0;
    double totalAmount = 0;
    int totalCount = 0;

    for (final row in result) {
      final sale = Sale.fromJson(row);
      totalAmount += sale.netAmount;
      totalCount++;

      final methods = sale.paymentMethods ?? {};
      for (final entry in methods.entries) {
        if (entry.value <= 0) continue;
        final method = entry.key.toLowerCase();
        final amount = entry.value;

        if (method == 'cash') {
          totalCash += amount;
        } else if (method == 'upi') {
          totalUpi += amount;
        } else if (method == 'card') {
          totalCard += amount;
        } else if (method == 'credit') {
          totalCredit += amount;
        }

        // Check if partial payment (multiple methods)
        if (methods.length > 1) {
          totalPartial += amount;
        }
      }
    }

    return {
      'totalSales': totalAmount,
      'totalCount': totalCount,
      'cash': totalCash,
      'upi': totalUpi,
      'card': totalCard,
      'credit': totalCredit,
      'partial': totalPartial,
    };
  }

  Future<Map<String, dynamic>> getTodaySummary() async {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);
    return await getSummary(from: start);
  }
}
'@

    # ---------- QUOTATION DIALOG ----------
    "features/billing/widgets/quotation_dialog.dart" = @'
import 'package:flutter/material.dart';
import '../../../models/quotation_model.dart';

class QuotationDialog extends StatefulWidget {
  final double subtotal;
  final double totalTax;
  final double discountTotal;
  final String? discountReason;
  final double grandTotal;
  final List<Map<String, dynamic>> cartItems;

  const QuotationDialog({
    super.key,
    required this.subtotal,
    required this.totalTax,
    required this.discountTotal,
    this.discountReason,
    required this.grandTotal,
    required this.cartItems,
  });

  @override
  State<QuotationDialog> createState() => _QuotationDialogState();
}

class _QuotationDialogState extends State<QuotationDialog> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _expiryController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Generate Quotation'),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Customer Name *'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _phoneController,
              decoration: const InputDecoration(labelText: 'Phone'),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(labelText: 'Notes'),
              maxLines: 2,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _expiryController,
              decoration: const InputDecoration(labelText: 'Expiry Date (YYYY-MM-DD)'),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Items:'),
                      Text('${widget.cartItems.length}'),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Subtotal:'),
                      Text('₹${widget.subtotal.toStringAsFixed(2)}'),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Tax:'),
                      Text('₹${widget.totalTax.toStringAsFixed(2)}'),
                    ],
                  ),
                  if (widget.discountTotal > 0)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Discount:'),
                        Text(' -₹${widget.discountTotal.toStringAsFixed(2)}'),
                      ],
                    ),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total:', style: TextStyle(fontWeight: FontWeight.bold)),
                      Text(
                        '₹${widget.grandTotal.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: () {
            if (_nameController.text.trim().isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Please enter customer name'), backgroundColor: Colors.red),
              );
              return;
            }
            Navigator.pop(context, {
              'customerName': _nameController.text.trim(),
              'customerPhone': _phoneController.text.trim(),
              'customerEmail': _emailController.text.trim(),
              'notes': _notesController.text.trim(),
              'expiryDate': _expiryController.text.trim(),
            });
          },
          icon: const Icon(Icons.description),
          label: const Text('Generate'),
        ),
      ],
    );
  }
}
'@

    # ---------- PAYMENT DIALOG ----------
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
  List<Map<String, dynamic>> _payments = [];
  bool _partialPayment = false;
  double _remainingAmount = 0;

  final List<String> _paymentMethods = ['Cash', 'UPI', 'Card', 'Credit'];

  @override
  void initState() {
    super.initState();
    _payments.add({
      'method': 'Cash',
      'amount': 0.0,
      'controller': TextEditingController(),
    });
    _remainingAmount = widget.total;
  }

  @override
  void dispose() {
    for (final p in _payments) {
      (p['controller'] as TextEditingController).dispose();
    }
    super.dispose();
  }

  void _addPayment() {
    setState(() {
      _payments.add({
        'method': 'Cash',
        'amount': 0.0,
        'controller': TextEditingController(),
      });
    });
  }

  void _removePayment(int index) {
    if (_payments.length <= 1) return;
    ( _payments[index]['controller'] as TextEditingController).dispose();
    setState(() {
      _payments.removeAt(index);
    });
    _calculateRemaining();
  }

  void _calculateRemaining() {
    double totalPaid = 0;
    for (final p in _payments) {
      totalPaid += p['amount'] as double;
    }
    setState(() {
      _remainingAmount = widget.total - totalPaid;
    });
  }

  bool get _canPay {
    final totalPaid = _payments.fold(0.0, (sum, p) => sum + (p['amount'] as double));
    if (_partialPayment) return totalPaid > 0 && totalPaid <= widget.total;
    return totalPaid >= widget.total;
  }

  @override
  Widget build(BuildContext context) {
    final canUseCredit = widget.customer != null && widget.customer!.outstandingBalance > 0;

    return AlertDialog(
      title: const Text('Payment'),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Total: ₹${widget.total.toStringAsFixed(2)}', style: const TextStyle(fontSize: 20)),
              const SizedBox(height: 16),
              ..._payments.asMap().entries.map((entry) {
                final index = entry.key;
                final p = entry.value;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<String>(
                          value: p['method'],
                          decoration: const InputDecoration(border: OutlineInputBorder()),
                          items: _paymentMethods.map((m) {
                            return DropdownMenuItem(value: m, child: Text(m));
                          }).toList(),
                          onChanged: (val) {
                            setState(() {
                              p['method'] = val!;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: p['controller'] as TextEditingController,
                          decoration: const InputDecoration(border: OutlineInputBorder()),
                          keyboardType: TextInputType.number,
                          onChanged: (v) {
                            final amount = double.tryParse(v) ?? 0;
                            p['amount'] = amount;
                            _calculateRemaining();
                          },
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.remove_circle, color: Colors.red),
                        onPressed: () => _removePayment(index),
                      ),
                    ],
                  ),
                );
              }),
              TextButton.icon(
                onPressed: _addPayment,
                icon: const Icon(Icons.add),
                label: const Text('Add Payment Method'),
              ),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Remaining:', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(
                    '₹${_remainingAmount.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: _remainingAmount > 0 ? Colors.red : Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: _partialPayment,
                onChanged: (val) {
                  if (val == true && widget.customer == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please select a customer for partial payment'), backgroundColor: Colors.red),
                    );
                    return;
                  }
                  setState(() {
                    _partialPayment = val ?? false;
                  });
                },
                title: const Text('Partial Payment (Remaining as Credit)'),
              ),
              if (_partialPayment && widget.customer != null)
                Padding(
                  padding: const EdgeInsets.only(left: 32.0),
                  child: Text(
                    'Customer: ${widget.customer!.name} (Balance: ₹${widget.customer!.outstandingBalance.toStringAsFixed(2)})',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _canPay
              ? () {
                  if (_partialPayment && widget.customer == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please select a customer for partial payment'), backgroundColor: Colors.red),
                    );
                    return;
                  }
                  final payments = <String, double>{};
                  for (final p in _payments) {
                    final amount = p['amount'] as double;
                    if (amount > 0) {
                      payments[p['method'].toLowerCase()] = amount;
                    }
                  }
                  final totalPaid = payments.values.fold(0.0, (sum, v) => sum + v);
                  final partialAmount = _partialPayment ? widget.total - totalPaid : null;
                  final creditUsed = payments.containsKey('credit') ? payments['credit'] : null;
                  widget.onPay(payments, partialAmount, creditUsed);
                }
              : null,
          child: const Text('Pay'),
        ),
      ],
    );
  }
}
'@

    # ---------- PRODUCT GRID ----------
    "features/billing/widgets/product_grid.dart" = @'
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/product_model.dart';
import '../../../models/category_model.dart';
import '../../../repositories/category_repository.dart';

class ProductGrid extends ConsumerStatefulWidget {
  final Function(Product) onProductSelected;

  const ProductGrid({super.key, required this.onProductSelected});

  @override
  ConsumerState<ProductGrid> createState() => _ProductGridState();
}

class _ProductGridState extends ConsumerState<ProductGrid> {
  String _selectedCategory = 'All';
  final TextEditingController _searchController = TextEditingController();
  List<Category> _categories = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final cats = await CategoryRepository().getAll();
      setState(() {
        _categories = cats;
        _isLoading = false;
      });
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productNotifierProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              hintText: 'Search by name or barcode',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              suffixIcon: Icon(Icons.qr_code_scanner),
            ),
            onChanged: (value) {
              setState(() {});
            },
          ),
        ),
        // Category Tabs
        if (!_isLoading)
          SizedBox(
            height: 40,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _categories.length + 1,
              itemBuilder: (context, index) {
                final isAll = index == 0;
                final category = isAll ? null : _categories[index - 1];
                final isSelected = isAll
                    ? _selectedCategory == 'All'
                    : _selectedCategory == category!.id;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                  child: FilterChip(
                    label: Text(isAll ? 'All' : category!.name),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        _selectedCategory = isAll ? 'All' : category!.id;
                      });
                    },
                  ),
                );
              },
            ),
          ),
        Expanded(
          child: productsAsync.when(
            data: (products) {
              final filtered = _searchController.text.isNotEmpty
                  ? products.where((p) =>
                      p.name.toLowerCase().contains(_searchController.text.toLowerCase()) ||
                      (p.searchName?.toLowerCase().contains(_searchController.text.toLowerCase()) ?? false) ||
                      p.barcode.contains(_searchController.text))
                      .toList()
                  : products;

              final categoryFiltered = _selectedCategory == 'All'
                  ? filtered
                  : filtered.where((p) => p.categoryId == _selectedCategory).toList();

              if (categoryFiltered.isEmpty) {
                return const Center(child: Text('No products found'));
              }

              return GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  childAspectRatio: 1.1,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: categoryFiltered.length,
                itemBuilder: (context, index) {
                  final product = categoryFiltered[index];
                  return _ProductCard(
                    product: product,
                    onTap: () => widget.onProductSelected(product),
                  );
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, stack) => Center(child: Text('Error: $err')),
          ),
        ),
      ],
    );
  }
}

class _ProductCard extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;

  const _ProductCard({required this.product, required this.onTap});

  Color get _stockColor {
    if (product.stockQuantity <= 0) return Colors.red;
    if (product.stockQuantity <= product.reorderLevel) return Colors.orange;
    return Colors.green;
  }

  String get _stockText {
    if (product.stockQuantity <= 0) return 'Out of Stock';
    if (product.stockQuantity <= product.reorderLevel) return 'Low Stock';
    return 'In Stock';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: product.stockQuantity > 0 ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: Container(
                  width: double.infinity,
                  color: Colors.grey.shade200,
                  child: const Icon(Icons.inventory, size: 40, color: Colors.grey),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                product.displayName ?? product.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              Text(
                '₹${product.retailPrice.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _stockColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _stockText,
                  style: TextStyle(
                    fontSize: 10,
                    color: _stockColor,
                    fontWeight: FontWeight.bold,
                  ),
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

    # ---------- CART LIST VIEW (Grouped) ----------
    "features/billing/widgets/cart_list_view.dart" = @'
import 'package:flutter/material.dart';
import '../../../services/billing_service.dart';
import '../../../models/product_model.dart';

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
            Text('Add products from the left panel', style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      );
    }

    // Group items by category
    final grouped = <String, List<CartItem>>{};
    for (final item in items) {
      final category = item.product.categoryId ?? 'Other';
      if (!grouped.containsKey(category)) {
        grouped[category] = [];
      }
      grouped[category]!.add(item);
    }

    return ListView.builder(
      itemCount: grouped.keys.length,
      itemBuilder: (context, index) {
        final category = grouped.keys.elementAt(index);
        final groupItems = grouped[category]!;
        final groupSubtotal = groupItems.fold(
          0.0,
          (sum, item) => sum + (item.product.retailPrice * item.quantity),
        );

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      category,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      '₹${groupSubtotal.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const Divider(height: 0),
              ...groupItems.map((item) => _CartItemTile(
                    item: item,
                    onQuantityChange: onQuantityChange,
                    onRemove: onRemove,
                  )),
            ],
          ),
        );
      },
    );
  }
}

class _CartItemTile extends StatelessWidget {
  final CartItem item;
  final Function(String, int) onQuantityChange;
  final Function(String) onRemove;

  const _CartItemTile({
    required this.item,
    required this.onQuantityChange,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              item.product.displayName ?? item.product.name,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              '₹${item.product.retailPrice.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 13),
              textAlign: TextAlign.right,
            ),
          ),
          const SizedBox(width: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.remove_circle, color: Colors.red, size: 20),
                onPressed: () => onQuantityChange(item.productId, item.quantity - 1),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 4),
              Text(
                '${item.quantity}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.add_circle, color: Colors.green, size: 20),
                onPressed: () => onQuantityChange(item.productId, item.quantity + 1),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.delete_forever, color: Colors.red, size: 20),
                onPressed: () => onRemove(item.productId),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
'@

    # ---------- BILLING SCREEN (Complete Redesign) ----------
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
import '../../../repositories/customer_repository.dart';

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
    // Quick customer add dialog
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
          // Left Panel – Product Grid (40%)
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
          // Right Panel – Cart (60%)
          Expanded(
            flex: 6,
            child: Column(
              children: [
                // Customer info bar
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
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        ),
                      ),
                    ],
                  ),
                ),
                // Cart List
                Expanded(
                  child: CartListView(
                    items: cartItems,
                    onQuantityChange: (id, qty) =>
                        ref.read(cartProvider.notifier).updateQuantity(id, qty),
                    onRemove: (id) => ref.read(cartProvider.notifier).removeItem(id),
                  ),
                ),
                // Totals & Action Bar
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                  ),
                  child: Column(
                    children: [
                      // Totals
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
                      // Action Buttons with Shortcut Keys
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          _actionButton('Customer', Icons.person, Colors.purple, 'F1', _showCustomerDialog),
                          _actionButton('Discount', Icons.percent, Colors.orange, 'F2', _showDiscountDialog),
                          _actionButton('Hold', Icons.save, Colors.blue, 'F3', () {
                            ref.read(cartProvider.notifier).clearCart();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Bill held!'), backgroundColor: Colors.blue),
                            );
                          }),
                          _actionButton('Cash', Icons.money, Colors.green, 'F4', () {
                            _showPaymentDialog({'cash': grandTotal});
                          }),
                          _actionButton('UPI', Icons.qr_code, Colors.teal, 'F5', () {
                            _showPaymentDialog({'upi': grandTotal});
                          }),
                          _actionButton('Card', Icons.credit_card, Colors.indigo, 'F6', () {
                            _showPaymentDialog({'card': grandTotal});
                          }),
                          _actionButton('Credit', Icons.account_balance, Colors.red, 'F7', () {
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
                          _actionButton('Share', Icons.share, Colors.green, 'F8', () async {
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
                          _actionButton('Quotation', Icons.description, Colors.brown, 'F9', _showQuotationDialog),
                          _actionButton('Pay', Icons.payment, Colors.green, 'Enter', () {
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
      icon: Icon(icon, size: 18),
      label: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 12)),
          Text(shortcut, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ],
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        minimumSize: const Size(60, 48),
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

    # ---------- SALES SUMMARY SCREEN ----------
    "features/sales_summary/screens/sales_summary_screen.dart" = @'
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../services/sales_summary_service.dart';

class SalesSummaryScreen extends ConsumerStatefulWidget {
  const SalesSummaryScreen({super.key});

  @override
  ConsumerState<SalesSummaryScreen> createState() => _SalesSummaryScreenState();
}

class _SalesSummaryScreenState extends ConsumerState<SalesSummaryScreen> {
  Map<String, dynamic> _summary = {};
  bool _isLoading = true;
  String _filter = 'Today';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final service = SalesSummaryService();
    Map<String, dynamic> data;
    if (_filter == 'Today') {
      data = await service.getTodaySummary();
    } else {
      // For other filters, we'll use a date range
      final now = DateTime.now();
      DateTime from;
      if (_filter == 'Week') {
        from = now.subtract(const Duration(days: 7));
      } else if (_filter == 'Month') {
        from = DateTime(now.year, now.month - 1, now.day);
      } else {
        from = DateTime(now.year - 1, now.month, now.day);
      }
      data = await service.getSummary(from: from);
    }
    setState(() {
      _summary = data;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Sales Summary',
      actions: [
        DropdownButton<String>(
          value: _filter,
          items: ['Today', 'Week', 'Month', 'Year'].map((f) {
            return DropdownMenuItem(value: f, child: Text(f));
          }).toList(),
          onChanged: (val) {
            setState(() => _filter = val!);
            _loadData();
          },
        ),
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: _loadData,
        ),
      ],
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Total Sales:', style: TextStyle(fontSize: 18)),
                              Text(
                                '₹${(_summary['totalSales'] ?? 0).toStringAsFixed(2)}',
                                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Total Bills:', style: TextStyle(fontSize: 16)),
                              Text(
                                '${_summary['totalCount'] ?? 0}',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _summaryRow('Cash', _summary['cash'] ?? 0, Colors.green),
                          const Divider(),
                          _summaryRow('UPI', _summary['upi'] ?? 0, Colors.teal),
                          const Divider(),
                          _summaryRow('Card', _summary['card'] ?? 0, Colors.indigo),
                          const Divider(),
                          _summaryRow('Credit', _summary['credit'] ?? 0, Colors.red),
                          const Divider(),
                          _summaryRow('Partial Payments', _summary['partial'] ?? 0, Colors.orange),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _summaryRow(String label, double amount, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontSize: 16)),
          ],
        ),
        Text(
          '₹${amount.toStringAsFixed(2)}',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }
}
'@

    # ---------- QUOTATION LIST SCREEN ----------
    "features/quotation/screens/quotation_list_screen.dart" = @'
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../providers/quotation_provider.dart';

class QuotationListScreen extends ConsumerStatefulWidget {
  const QuotationListScreen({super.key});

  @override
  ConsumerState<QuotationListScreen> createState() => _QuotationListScreenState();
}

class _QuotationListScreenState extends ConsumerState<QuotationListScreen> {
  @override
  Widget build(BuildContext context) {
    final quotationsAsync = ref.watch(quotationNotifierProvider);

    return AppScaffold(
      title: 'Quotations',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () => ref.invalidate(quotationNotifierProvider),
        ),
      ],
      body: quotationsAsync.when(
        data: (quotations) {
          if (quotations.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.description, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('No quotations'),
                  SizedBox(height: 8),
                  Text('Create one from the billing screen', style: TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            );
          }
          return ListView.builder(
            itemCount: quotations.length,
            itemBuilder: (context, index) {
              final q = quotations[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: ListTile(
                  leading: const Icon(Icons.description),
                  title: Text(q.quoteNo),
                  subtitle: Text('${q.customerName} | ₹${q.netAmount.toStringAsFixed(2)}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Chip(
                        label: Text(q.status),
                        backgroundColor: q.status == 'converted' ? Colors.green : Colors.orange,
                        labelStyle: const TextStyle(color: Colors.white, fontSize: 10),
                      ),
                      IconButton(
                        icon: const Icon(Icons.print),
                        onPressed: () {
                          // Print quotation
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () {
                          ref.read(quotationNotifierProvider.notifier).deleteQuotation(q.id);
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
      ),
    );
  }
}
'@

    # ---------- QUOTATION FORM SCREEN (Minimal) ----------
    "features/quotation/screens/quotation_form_screen.dart" = @'
import 'package:flutter/material.dart';
import '../../../core/widgets/app_scaffold.dart';

class QuotationFormScreen extends StatelessWidget {
  const QuotationFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Quotation Form',
      body: const Center(child: Text('Quotation Form – Coming Soon')),
    );
  }
}
'@

    # ---------- CUSTOMER FORM SCREEN (Updated with onSaved callback) ----------
    "features/customers/screens/customer_form_screen.dart" = @'
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../models/customer_model.dart';
import '../../../providers/customer_provider.dart';

class CustomerFormScreen extends ConsumerStatefulWidget {
  final Customer? customer;
  final Function(Customer)? onSaved;

  const CustomerFormScreen({super.key, this.customer, this.onSaved});

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
    _creditLimitController = TextEditingController(text: widget.customer?.creditLimit.toString() ?? '0');
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
      email: _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
      address: _addressController.text.trim().isEmpty ? null : _addressController.text.trim(),
      locality: _localityController.text.trim().isEmpty ? null : _localityController.text.trim(),
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

    if (widget.onSaved != null) {
      widget.onSaved!(customer);
    }

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.customer == null ? 'New Customer' : 'Edit Customer'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Full Name *'),
                  validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _phoneController,
                  decoration: const InputDecoration(labelText: 'Phone Number *'),
                  keyboardType: TextInputType.phone,
                  validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(labelText: 'Email (optional)'),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _addressController,
                  decoration: const InputDecoration(labelText: 'Address (optional)'),
                  maxLines: 2,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _localityController,
                  decoration: const InputDecoration(labelText: 'Locality (optional)'),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _creditLimitController,
                  decoration: const InputDecoration(labelText: 'Credit Limit (₹)'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 40,
                  child: ElevatedButton(
                    onPressed: _save,
                    child: Text(widget.customer == null ? 'CREATE CUSTOMER' : 'UPDATE CUSTOMER'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
'@

    # ---------- UPDATED ROUTER ----------
    "core/routes/app_router.dart" = @'
import 'package:go_router/go_router.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/change_password_screen.dart';
import '../../features/dashboard/screens/dashboard_screen.dart';
import '../../features/billing/screens/billing_screen.dart';
import '../../features/products/screens/product_list_screen.dart';
import '../../features/products/screens/product_form_screen.dart';
import '../../features/customers/screens/customer_list_screen.dart';
import '../../features/customers/screens/customer_form_screen.dart';
import '../../features/reports/screens/customer_history_screen.dart';
import '../../features/suppliers/screens/supplier_list_screen.dart';
import '../../features/suppliers/screens/supplier_form_screen.dart';
import '../../features/purchases/screens/purchase_list_screen.dart';
import '../../features/purchases/screens/purchase_form_screen.dart';
import '../../features/counter/screens/counter_open_screen.dart';
import '../../features/counter/screens/counter_close_screen.dart';
import '../../features/reports/screens/sales_report_screen.dart';
import '../../features/reports/screens/product_performance_screen.dart';
import '../../features/reports/screens/ai_analysis_screen.dart';
import '../../features/settings/screens/settings_screen.dart';
import '../../features/users/screens/user_list_screen.dart';
import '../../features/users/screens/user_form_screen.dart';
import '../../features/credit/screens/receive_payment_screen.dart';
import '../../features/sales_history/screens/sales_history_screen.dart';
import '../../features/sales_summary/screens/sales_summary_screen.dart';
import '../../features/quotation/screens/quotation_list_screen.dart';
import '../../features/quotation/screens/quotation_form_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/login',
  routes: [
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/change-password',
      builder: (context, state) => const ChangePasswordScreen(),
    ),
    GoRoute(
      path: '/dashboard',
      builder: (context, state) => const DashboardScreen(),
    ),
    GoRoute(
      path: '/billing',
      builder: (context, state) => const BillingScreen(),
    ),
    GoRoute(
      path: '/products',
      builder: (context, state) => const ProductListScreen(),
    ),
    GoRoute(
      path: '/products/form',
      builder: (context, state) => const ProductFormScreen(),
    ),
    GoRoute(
      path: '/customers',
      builder: (context, state) => const CustomerListScreen(),
    ),
    GoRoute(
      path: '/customers/form',
      builder: (context, state) => const CustomerFormScreen(),
    ),
    GoRoute(
      path: '/customers/history',
      builder: (context, state) => const CustomerHistoryScreen(),
    ),
    GoRoute(
      path: '/suppliers',
      builder: (context, state) => const SupplierListScreen(),
    ),
    GoRoute(
      path: '/suppliers/form',
      builder: (context, state) => const SupplierFormScreen(),
    ),
    GoRoute(
      path: '/purchases',
      builder: (context, state) => const PurchaseListScreen(),
    ),
    GoRoute(
      path: '/purchases/form',
      builder: (context, state) => const PurchaseFormScreen(),
    ),
    GoRoute(
      path: '/counter/open',
      builder: (context, state) => const CounterOpenScreen(),
    ),
    GoRoute(
      path: '/counter/close',
      builder: (context, state) => const CounterCloseScreen(),
    ),
    GoRoute(
      path: '/reports/sales',
      builder: (context, state) => const SalesReportScreen(),
    ),
    GoRoute(
      path: '/reports/product-performance',
      builder: (context, state) => const ProductPerformanceScreen(),
    ),
    GoRoute(
      path: '/reports/ai-analysis',
      builder: (context, state) => const AIAnalysisScreen(),
    ),
    GoRoute(
      path: '/users',
      builder: (context, state) => const UserListScreen(),
    ),
    GoRoute(
      path: '/users/form',
      builder: (context, state) => const UserFormScreen(),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
    GoRoute(
      path: '/credit/receive-payment',
      builder: (context, state) => const ReceivePaymentScreen(),
    ),
    GoRoute(
      path: '/sales-history',
      builder: (context, state) => const SalesHistoryScreen(),
    ),
    GoRoute(
      path: '/sales-summary',
      builder: (context, state) => const SalesSummaryScreen(),
    ),
    GoRoute(
      path: '/quotations',
      builder: (context, state) => const QuotationListScreen(),
    ),
    GoRoute(
      path: '/quotations/form',
      builder: (context, state) => const QuotationFormScreen(),
    ),
  ],
);
'@

    # ---------- UPDATED DASHBOARD ----------
    "features/dashboard/screens/dashboard_screen.dart" = @'
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../providers/auth_provider.dart';
import '../../../models/user_model.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final user = authState.user;
    final isAdmin = user?.role == UserRole.admin;
    final isManager = user?.role == UserRole.manager || isAdmin;

    return AppScaffold(
      title: 'Dashboard',
      showBackButton: false,
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: GridView.count(
          crossAxisCount: 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          children: [
            _card(context, 'Billing', Icons.point_of_sale, Colors.green, '/billing'),
            _card(context, 'Products', Icons.inventory, Colors.blue, '/products'),
            _card(context, 'Customers', Icons.people, Colors.purple, '/customers'),
            _card(context, 'Suppliers', Icons.business, Colors.orange, '/suppliers'),
            _card(context, 'Purchases', Icons.receipt_long, Colors.teal, '/purchases'),
            _card(context, 'Sales History', Icons.history, Colors.indigo, '/sales-history'),
            _card(context, 'Sales Summary', Icons.pie_chart, Colors.cyan, '/sales-summary'),
            _card(context, 'Quotations', Icons.description, Colors.brown, '/quotations'),
            if (isManager)
              _card(context, 'Reports', Icons.assessment, Colors.red, '/reports/sales'),
            if (isAdmin)
              _card(context, 'Users', Icons.people_outline, Colors.indigo, '/users'),
            _card(context, 'Settings', Icons.settings, Colors.grey, '/settings'),
          ],
        ),
      ),
    );
  }

  Widget _card(BuildContext context, String title, IconData icon, Color color, String route) {
    return Card(
      elevation: 4,
      child: InkWell(
        onTap: () => context.go(route),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: color),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontSize: 16)),
          ],
        ),
      ),
    );
  }
}
'@

    # ---------- DB Migration for Quotations Table ----------
    # We'll add the table via migration script but since we already have the script,
    # I'll include the SQL to add the table in a separate note.

}

# Write all files
foreach ($key in $files.Keys) {
    $fullPath = Join-Path $base $key
    $dir = Split-Path $fullPath
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    Set-Content -Path $fullPath -Value $files[$key] -Force
    Write-Host "Created: $key" -ForegroundColor Green
}

Write-Host "`n✅ All files created!" -ForegroundColor Cyan
Write-Host "`n⚠️ Database Migration Required:" -ForegroundColor Yellow
Write-Host "Add the 'quotations' table to your database." -ForegroundColor White
Write-Host ""
Write-Host "CREATE TABLE quotations (" -ForegroundColor White
Write-Host "  id TEXT PRIMARY KEY," -ForegroundColor White
Write-Host "  store_id TEXT REFERENCES stores(id) ON DELETE CASCADE," -ForegroundColor White
Write-Host "  customer_id TEXT REFERENCES customers(id) ON DELETE SET NULL," -ForegroundColor White
Write-Host "  customer_name TEXT NOT NULL," -ForegroundColor White
Write-Host "  customer_phone TEXT," -ForegroundColor White
Write-Host "  customer_email TEXT," -ForegroundColor White
Write-Host "  quote_no TEXT NOT NULL," -ForegroundColor White
Write-Host "  subtotal REAL NOT NULL DEFAULT 0," -ForegroundColor White
Write-Host "  tax_total REAL NOT NULL DEFAULT 0," -ForegroundColor White
Write-Host "  discount_total REAL NOT NULL DEFAULT 0," -ForegroundColor White
Write-Host "  discount_reason TEXT," -ForegroundColor White
Write-Host "  net_amount REAL NOT NULL DEFAULT 0," -ForegroundColor White
Write-Host "  notes TEXT," -ForegroundColor White
Write-Host "  expiry_date INTEGER," -ForegroundColor White
Write-Host "  status TEXT DEFAULT 'pending'," -ForegroundColor White
Write-Host "  created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))," -ForegroundColor White
Write-Host "  updated_at INTEGER" -ForegroundColor White
Write-Host ");" -ForegroundColor White
Write-Host ""
Write-Host "CREATE INDEX idx_quotations_customer ON quotations(customer_id);" -ForegroundColor White
Write-Host "CREATE INDEX idx_quotations_status ON quotations(status);" -ForegroundColor White
Write-Host ""
Write-Host "Now run:" -ForegroundColor Cyan
Write-Host "flutter clean" -ForegroundColor White
Write-Host "flutter pub get" -ForegroundColor White
Write-Host "flutter pub run build_runner build --delete-conflicting-outputs" -ForegroundColor White
Write-Host "flutter run -d windows" -ForegroundColor White