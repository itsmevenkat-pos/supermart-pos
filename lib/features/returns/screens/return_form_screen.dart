import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/permissions/price_override_guard.dart';
import '../../../core/utils/quantity_utils.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../models/customer_model.dart';
import '../../../models/sales_return_item_model.dart';
import '../../../models/sales_return_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/customer_provider.dart';
import '../../../providers/sales_return_provider.dart';
import '../../../repositories/product_repository.dart';
import '../../../repositories/sale_repository.dart';
import '../../../repositories/store_repository.dart';

/// Records a return/refund — either against a specific past sale
/// ([saleId] set, reached from Sales History) or "untied" (no originating
/// sale, e.g. a lost receipt), reached directly from the Returns list.
///
/// Sale-linked lines are pre-filled from the original sale_items (quantity
/// capped at what was actually sold, price/tax snapshotted from that sale —
/// never re-priced at today's rates). Untied lines are added by searching
/// the product catalog and price at today's MRP, since there's no prior
/// sale to snapshot from.
class ReturnFormScreen extends ConsumerStatefulWidget {
  final String? saleId;

  const ReturnFormScreen({super.key, this.saleId});

  @override
  ConsumerState<ReturnFormScreen> createState() => _ReturnFormScreenState();
}

class _ReturnLine {
  final String? saleItemId;
  final String productId;
  final String productName;
  final double? maxQuantity;
  double quantity;
  final double unitPrice;
  final double taxRate;
  final double costPrice;
  /// Set by the per-line toggle rather than at construction — a returned
  /// item goes back into stock unless someone marks it damaged.
  bool restocked = true;
  bool included;

  _ReturnLine({
    this.saleItemId,
    required this.productId,
    required this.productName,
    this.maxQuantity,
    required this.quantity,
    required this.unitPrice,
    required this.taxRate,
    required this.costPrice,
    this.included = true,
  });

  double get taxAmount => unitPrice * quantity * taxRate / 100;
  double get totalPrice => (unitPrice * quantity) + taxAmount;
}

class _ReturnFormScreenState extends ConsumerState<ReturnFormScreen> {
  bool _loading = true;
  bool _submitting = false;
  String? _saleInvoiceLabel;
  final List<_ReturnLine> _lines = [];
  Customer? _customer;
  String _refundMethod = 'cash';

  final _reasonController = TextEditingController();
  final _searchController = TextEditingController();

  bool get _isUntied => widget.saleId == null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (widget.saleId != null) {
      final sale = await SaleRepository().getById(widget.saleId!);
      if (sale == null) {
        setState(() => _loading = false);
        return;
      }
      final items = await SaleRepository().getItemsBySale(sale.id);
      final productRepo = ProductRepository();
      for (final item in items) {
        final product = await productRepo.getById(item.productId);
        final soldAmount = item.unitPrice * item.quantity;
        // Back out an effective tax rate from what was actually charged,
        // rather than reading the product's *current* tax_rate — a return
        // should reverse exactly what the customer was billed, even if the
        // rate has since changed.
        final taxRate = soldAmount > 0 ? (item.taxAmount / soldAmount) * 100 : 0.0;
        _lines.add(_ReturnLine(
          saleItemId: item.id,
          productId: item.productId,
          productName: product?.displayName ?? product?.name ?? 'Unknown item',
          maxQuantity: item.quantity,
          quantity: item.quantity,
          unitPrice: item.unitPrice,
          taxRate: taxRate,
          costPrice: item.costPrice,
          included: false,
        ));
      }
      if (sale.customerId != null) {
        _customer = await ref.read(customerNotifierProvider.notifier).getById(sale.customerId!);
      }
      _saleInvoiceLabel = sale.invoiceLabel;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _searchAndAddProduct(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    final repo = ProductRepository();
    var results = await repo.getByBarcode(trimmed);
    if (results.isEmpty) results = await repo.search(trimmed);
    if (results.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No matching product found')));
      return;
    }
    final product = results.first;
    setState(() {
      _lines.add(_ReturnLine(
        productId: product.id,
        productName: product.displayName ?? product.name,
        quantity: 1,
        unitPrice: product.mrp,
        taxRate: product.taxRate,
        costPrice: product.costPrice,
      ));
    });
    _searchController.clear();
  }

  Future<void> _pickCustomer() async {
    final searchController = TextEditingController();
    final selected = await showDialog<Customer>(
      context: context,
      builder: (dialogContext) {
        List<Customer> results = [];
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Attach Customer'),
              content: SizedBox(
                width: 380,
                height: 380,
                child: Column(
                  children: [
                    TextField(
                      controller: searchController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        hintText: 'Search by name or phone',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) async {
                        final found = value.trim().isEmpty
                            ? <Customer>[]
                            : await ref.read(customerNotifierProvider.notifier).search(value.trim());
                        setDialogState(() => results = found);
                      },
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        itemCount: results.length,
                        itemBuilder: (_, i) {
                          final c = results[i];
                          return ListTile(
                            leading: const Icon(Icons.person),
                            title: Text(c.name),
                            subtitle: Text(c.phone),
                            onTap: () => Navigator.pop(dialogContext, c),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
              ],
            );
          },
        );
      },
    );
    searchController.dispose();
    if (selected != null) setState(() => _customer = selected);
  }

  String _refundMethodLabel(String method) {
    switch (method) {
      case 'upi':
        return 'UPI';
      case 'card':
        return 'Card';
      case 'credit_adjust':
        return 'Adjusted against credit';
      default:
        return 'Cash';
    }
  }

  double get _refundTotal {
    final included = _isUntied ? _lines : _lines.where((l) => l.included);
    return included.fold<double>(0, (sum, l) => sum + l.totalPrice);
  }

  Future<void> _submit() async {
    final includedLines = _isUntied ? _lines : _lines.where((l) => l.included).toList();
    if (includedLines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select at least one item to return')));
      return;
    }
    if (_reasonController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('A reason is required')));
      return;
    }
    if (_refundMethod == 'credit_adjust' && _customer == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Attach a customer to adjust the refund against credit')));
      return;
    }

    final currentUser = ref.read(authProvider).user;
    if (currentUser == null) return;

    final refundAmount = _refundTotal;
    final threshold = await StoreRepository().getReturnThreshold();
    final needsApproval = _isUntied || refundAmount > threshold;

    String? approvedByUserId;
    if (needsApproval) {
      if (!mounted) return;
      final approver = await requireApprovalWithApprover(
        context,
        ref,
        actionLabel: _isUntied
            ? 'Return with no originating sale (₹${refundAmount.toStringAsFixed(2)})'
            : 'Return of ₹${refundAmount.toStringAsFixed(2)}',
      );
      if (approver == null) return;
      approvedByUserId = approver.id;
    }

    setState(() => _submitting = true);
    try {
      final header = SalesReturn.create(
        saleId: widget.saleId,
        customerId: _customer?.id,
        storeId: StoreRepository.defaultStoreId,
        userId: currentUser.id,
        approvedByUserId: approvedByUserId,
        reason: _reasonController.text.trim(),
        refundMethod: _refundMethod,
        refundAmount: refundAmount,
        isUntied: _isUntied,
      );
      final items = includedLines
          .map((l) => SalesReturnItem.create(
                saleItemId: l.saleItemId,
                productId: l.productId,
                quantity: l.quantity,
                unitPrice: l.unitPrice,
                taxAmount: l.taxAmount,
                totalPrice: l.totalPrice,
                costPrice: l.costPrice,
                restocked: l.restocked,
              ))
          .toList();

      final saved = await ref.read(salesReturnNotifierProvider).createReturn(header: header, items: items);

      if (approvedByUserId != null) {
        await DatabaseHelper.instance.logAudit(
          userId: approvedByUserId,
          actionType: 'SALES_RETURN_APPROVED',
          tableName: 'sales_returns',
          recordId: saved.id,
          newValue: 'Return of ₹${refundAmount.toStringAsFixed(2)} approved for cashier ${currentUser.name}',
        );
      }

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Return Recorded'),
          content:
              Text('Refund of ₹${refundAmount.toStringAsFixed(2)} recorded via ${_refundMethodLabel(_refundMethod)}.'),
          actions: [ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
        ),
      );
      if (!mounted) return;
      context.pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to record return: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: _isUntied ? 'Record a Return' : 'Return — Invoice ${_saleInvoiceLabel ?? ''}',
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_isUntied) _buildProductSearch(),
                const SizedBox(height: 8),
                _buildLinesCard(),
                const SizedBox(height: 12),
                _buildCustomerCard(),
                const SizedBox(height: 12),
                _buildReasonAndMethod(),
                const SizedBox(height: 16),
                _buildSummaryAndSubmit(),
              ],
            ),
    );
  }

  Widget _buildProductSearch() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: TextField(
          controller: _searchController,
          decoration: InputDecoration(
            labelText: 'Scan barcode or search product to add',
            prefixIcon: const Icon(Icons.search),
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: const Icon(Icons.add),
              onPressed: () => _searchAndAddProduct(_searchController.text),
            ),
          ),
          onSubmitted: _searchAndAddProduct,
        ),
      ),
    );
  }

  Widget _buildLinesCard() {
    if (_lines.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: Text('No items yet')),
        ),
      );
    }
    return Card(
      child: Column(
        children: _lines.map((line) => _buildLineTile(line)).toList(),
      ),
    );
  }

  Widget _buildLineTile(_ReturnLine line) {
    final qtyController = TextEditingController(text: formatQty(line.quantity));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (!_isUntied)
            Checkbox(
              value: line.included,
              onChanged: (v) => setState(() => line.included = v ?? false),
            ),
          Expanded(
            flex: 3,
            child: Text(line.productName, overflow: TextOverflow.ellipsis),
          ),
          SizedBox(
            width: 80,
            child: TextField(
              controller: qtyController,
              enabled: line.included || _isUntied,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Qty', isDense: true),
              onChanged: (value) {
                final parsed = parseQty(value);
                if (parsed == null || parsed <= 0) return;
                final capped = line.maxQuantity != null && parsed > line.maxQuantity!
                    ? line.maxQuantity!
                    : parsed;
                setState(() => line.quantity = capped);
              },
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 130,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Restock', style: TextStyle(fontSize: 12)),
                Switch(
                  value: line.restocked,
                  onChanged: (line.included || _isUntied) ? (v) => setState(() => line.restocked = v) : null,
                ),
              ],
            ),
          ),
          SizedBox(
            width: 90,
            child: Text(
              '₹${line.totalPrice.toStringAsFixed(2)}',
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          if (_isUntied)
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => setState(() => _lines.remove(line)),
            ),
        ],
      ),
    );
  }

  Widget _buildCustomerCard() {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.person_outline),
        title: Text(_customer?.name ?? 'No customer attached'),
        subtitle: _customer != null
            ? Text(
                '${_customer!.phone}${_customer!.outstandingBalance > 0 ? '  •  ₹${_customer!.outstandingBalance.toStringAsFixed(0)} due' : ''}')
            : const Text('Attach a customer to refund via credit adjustment'),
        trailing: _isUntied
            ? TextButton(onPressed: _pickCustomer, child: Text(_customer == null ? 'Attach' : 'Change'))
            : null,
      ),
    );
  }

  Widget _buildReasonAndMethod() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            TextField(
              controller: _reasonController,
              decoration: const InputDecoration(labelText: 'Reason for return', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _refundMethod,
              decoration: const InputDecoration(labelText: 'Refund method', border: OutlineInputBorder()),
              items: [
                const DropdownMenuItem(value: 'cash', child: Text('Cash')),
                const DropdownMenuItem(value: 'upi', child: Text('UPI')),
                const DropdownMenuItem(value: 'card', child: Text('Card')),
                DropdownMenuItem(
                  value: 'credit_adjust',
                  enabled: _customer != null,
                  child: Text('Adjust against credit', style: TextStyle(color: _customer == null ? Colors.grey : null)),
                ),
              ],
              onChanged: (value) => setState(() => _refundMethod = value ?? 'cash'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryAndSubmit() {
    return Row(
      children: [
        Text('Refund total: ₹${_refundTotal.toStringAsFixed(2)}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const Spacer(),
        ElevatedButton.icon(
          onPressed: _submitting ? null : _submit,
          icon: _submitting
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.assignment_return),
          label: const Text('Record Return'),
        ),
      ],
    );
  }
}
