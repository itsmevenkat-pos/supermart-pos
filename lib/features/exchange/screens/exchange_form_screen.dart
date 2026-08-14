import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/permissions/price_override_guard.dart';
import '../../../core/utils/quantity_utils.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../models/customer_model.dart';
import '../../../models/sale_item_model.dart';
import '../../../models/sale_model.dart';
import '../../../models/sales_return_item_model.dart';
import '../../../models/sales_return_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../repositories/customer_repository.dart';
import '../../../repositories/exchange_repository.dart';
import '../../../repositories/product_repository.dart';
import '../../../repositories/sale_repository.dart';
import '../../../repositories/store_repository.dart';
import '../../../services/counter_service.dart';
import '../../../services/gst_service.dart';

/// One line of the original sale being (partially) returned — same shape as
/// `return_form_screen.dart`'s `_ReturnLine`: quantity clamped to what was
/// actually sold, a restock switch, and an include checkbox.
class _ReturnLine {
  final String saleItemId;
  final String productId;
  final String productName;
  final double maxQuantity;
  double quantity;
  final double unitPrice;
  final double taxRate;
  final double costPrice;
  bool restocked = true;
  bool included = false;

  _ReturnLine({
    required this.saleItemId,
    required this.productId,
    required this.productName,
    required this.maxQuantity,
    required this.quantity,
    required this.unitPrice,
    required this.taxRate,
    required this.costPrice,
  });

  double get taxAmount => unitPrice * quantity * taxRate / 100;
  double get totalPrice => (unitPrice * quantity) + taxAmount;
}

/// One line of a replacement item being added to the new sale — same shape
/// as a billing cart line, priced at today's retail price.
class _NewItemLine {
  final String productId;
  final String productName;
  double quantity;
  final double unitPrice;
  final double taxRate;
  final double costPrice;

  _NewItemLine({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.taxRate,
    required this.costPrice,
  });

  double get taxAmount => GstService().calculateTax(amount: unitPrice * quantity, taxRate: taxRate);
  double get totalPrice => (unitPrice * quantity) + taxAmount;
}

/// Records an exchange: some items from a past sale come back (reversing
/// their stock, same as a Return) while replacement items go out (a new
/// Sale), both committed atomically by [ExchangeRepository.processExchange].
/// If [saleId] is null, the user first searches for the original sale.
class ExchangeFormScreen extends ConsumerStatefulWidget {
  final String? saleId;

  const ExchangeFormScreen({super.key, this.saleId});

  @override
  ConsumerState<ExchangeFormScreen> createState() => _ExchangeFormScreenState();
}

class _ExchangeFormScreenState extends ConsumerState<ExchangeFormScreen> {
  bool _loading = true;
  bool _submitting = false;

  Sale? _originalSale;
  final List<_ReturnLine> _returnLines = [];
  final List<_NewItemLine> _newItems = [];
  Customer? _customer;
  String _settlementMethod = 'cash';

  final _reasonController = TextEditingController();
  final _saleSearchController = TextEditingController();
  final _productSearchController = TextEditingController();
  List<Sale> _saleSearchResults = [];
  bool _searchingSale = false;

  @override
  void initState() {
    super.initState();
    if (widget.saleId != null) {
      _loadSale(widget.saleId!);
    } else {
      _loading = false;
    }
  }

  @override
  void dispose() {
    _reasonController.dispose();
    _saleSearchController.dispose();
    _productSearchController.dispose();
    super.dispose();
  }

  Future<void> _loadSale(String saleId) async {
    setState(() => _loading = true);
    final sale = await SaleRepository().getById(saleId);
    if (sale == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final items = await SaleRepository().getItemsBySale(sale.id);
    final productRepo = ProductRepository();
    final lines = <_ReturnLine>[];
    for (final item in items) {
      final product = await productRepo.getById(item.productId);
      final soldAmount = item.unitPrice * item.quantity;
      // Back out the effective tax rate from what was actually charged (not
      // the product's current tax_rate) so a return reverses exactly what
      // the customer was billed — same reasoning as return_form_screen.
      final taxRate = soldAmount > 0 ? (item.taxAmount / soldAmount) * 100 : 0.0;
      lines.add(_ReturnLine(
        saleItemId: item.id,
        productId: item.productId,
        productName: product?.displayName ?? product?.name ?? 'Unknown item',
        maxQuantity: item.quantity,
        quantity: item.quantity,
        unitPrice: item.unitPrice,
        taxRate: taxRate,
        costPrice: item.costPrice,
      ));
    }
    Customer? customer;
    if (sale.customerId != null) {
      customer = await CustomerRepository().getById(sale.customerId!);
    }
    if (!mounted) return;
    setState(() {
      _originalSale = sale;
      _returnLines
        ..clear()
        ..addAll(lines);
      _customer = customer;
      _loading = false;
    });
  }

  Future<void> _searchSales(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() => _saleSearchResults = []);
      return;
    }
    setState(() => _searchingSale = true);
    final db = await DatabaseHelper.instance.database;
    final rows = await db.rawQuery(
      '''
      SELECT s.* FROM sales s
      LEFT JOIN customers c ON c.id = s.customer_id
      WHERE s.status = 'completed'
        AND (s.invoice_display_no LIKE ? OR CAST(s.invoice_no AS TEXT) LIKE ? OR c.name LIKE ? OR c.phone LIKE ?)
      ORDER BY s.created_at DESC
      LIMIT 20
      ''',
      ['%$trimmed%', '%$trimmed%', '%$trimmed%', '%$trimmed%'],
    );
    if (!mounted) return;
    setState(() {
      _saleSearchResults = rows.map((e) => Sale.fromJson(e)).toList();
      _searchingSale = false;
    });
  }

  Future<void> _searchAndAddReplacementProduct(String query) async {
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
      _newItems.add(_NewItemLine(
        productId: product.id,
        productName: product.displayName ?? product.name,
        quantity: 1,
        unitPrice: product.retailPrice,
        taxRate: product.taxRate,
        costPrice: product.costPrice,
      ));
    });
    _productSearchController.clear();
  }

  double get _refundTotal =>
      _returnLines.where((l) => l.included).fold<double>(0, (sum, l) => sum + l.totalPrice);

  double get _newItemsSubtotal => _newItems.fold<double>(0, (sum, l) => sum + l.unitPrice * l.quantity);
  double get _newItemsTax => _newItems.fold<double>(0, (sum, l) => sum + l.taxAmount);
  double get _newItemsNet => _newItems.fold<double>(0, (sum, l) => sum + l.totalPrice);

  double get _priceDifference => _newItemsNet - _refundTotal;

  Future<void> _submit() async {
    final originalSale = _originalSale;
    if (originalSale == null) return;

    final includedReturnLines = _returnLines.where((l) => l.included).toList();
    if (includedReturnLines.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Select at least one item coming back')));
      return;
    }
    if (_newItems.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Add at least one replacement item')));
      return;
    }
    if (_reasonController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('A reason is required')));
      return;
    }
    if (_settlementMethod == 'credit_adjust' && _customer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Attach a customer to settle the difference against credit')));
      return;
    }

    final currentUser = ref.read(authProvider).user;
    if (currentUser == null) return;

    // Exchange is a bigger action than a plain return — always require
    // manager/admin approval, no amount-threshold exemption.
    final approver = await requireApprovalWithApprover(
      context,
      ref,
      actionLabel: 'Process Exchange',
    );
    if (approver == null) return;

    setState(() => _submitting = true);
    try {
      final refundAmount = _refundTotal;

      final returnHeader = SalesReturn.create(
        saleId: originalSale.id,
        customerId: _customer?.id,
        storeId: StoreRepository.defaultStoreId,
        userId: currentUser.id,
        approvedByUserId: approver.id,
        reason: _reasonController.text.trim(),
        refundMethod: _settlementMethod,
        refundAmount: refundAmount,
        isUntied: false,
      );
      final returnItems = includedReturnLines
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

      final activeSession = await CounterService().getActiveSession(currentUser.id);

      // The new sale's own paymentMethods field is just a display record of
      // how the difference was settled — it deliberately does NOT set
      // creditUsed/partialPaymentAmount, since the actual customer-balance
      // impact of the net price difference (new items minus refund) is
      // applied once, consolidated, by ExchangeRepository — setting them
      // here too would double-count it.
      final newSale = Sale.create(
        storeId: StoreRepository.defaultStoreId,
        customerId: _customer?.id,
        sessionId: activeSession?.id,
        userId: currentUser.id,
        subtotal: _newItemsSubtotal,
        taxTotal: _newItemsTax,
        netAmount: _newItemsNet,
        paymentMethods: _settlementMethod == 'credit_adjust' ? null : {_settlementMethod: _newItemsNet},
      );
      final newSaleItems = _newItems
          .map((l) => SaleItem.create(
                productId: l.productId,
                quantity: l.quantity,
                unitPrice: l.unitPrice,
                taxAmount: l.taxAmount,
                totalPrice: l.totalPrice,
                costPrice: l.costPrice,
              ))
          .toList();

      await ref.read(exchangeRepositoryProvider).processExchange(
            returnHeader: returnHeader,
            returnItems: returnItems,
            newSale: newSale,
            newSaleItems: newSaleItems,
            settlementMethod: _settlementMethod,
            userId: currentUser.id,
            approvedByUserId: approver.id,
            storeId: StoreRepository.defaultStoreId,
          );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_priceDifference == 0
              ? 'Exchange processed — no balance due either way'
              : _priceDifference > 0
                  ? 'Exchange processed — customer owes ₹${_priceDifference.toStringAsFixed(2)}'
                  : 'Exchange processed — refund ₹${(-_priceDifference).toStringAsFixed(2)} due to customer'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to process exchange: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: _originalSale != null ? 'Exchange — Invoice ${_originalSale!.invoiceLabel}' : 'New Exchange',
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _originalSale == null
              ? _buildSaleSearch()
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildCustomerCard(),
                    const SizedBox(height: 12),
                    const Text('Items coming back', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 8),
                    _buildReturnLinesCard(),
                    const SizedBox(height: 16),
                    const Text('Replacement items', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 8),
                    _buildReplacementSearch(),
                    const SizedBox(height: 8),
                    _buildNewItemsCard(),
                    const SizedBox(height: 16),
                    _buildReasonAndSettlement(),
                    const SizedBox(height: 16),
                    _buildSummaryAndSubmit(),
                  ],
                ),
    );
  }

  Widget _buildSaleSearch() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _saleSearchController,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Search by invoice number or customer name/phone',
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              suffixIcon: _searchingSale
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : null,
            ),
            onChanged: _searchSales,
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _saleSearchResults.isEmpty
                ? const Center(child: Text('Search for the original sale to exchange against'))
                : ListView.builder(
                    itemCount: _saleSearchResults.length,
                    itemBuilder: (_, index) {
                      final s = _saleSearchResults[index];
                      return Card(
                        child: ListTile(
                          leading: const Icon(Icons.receipt),
                          title: Text('Invoice ${s.invoiceLabel}'),
                          subtitle: Text(
                            '₹${s.netAmount.toStringAsFixed(2)} • '
                            '${DateTime.fromMillisecondsSinceEpoch(s.createdAt * 1000).toLocal().toString().split(' ')[0]}',
                          ),
                          onTap: () => _loadSale(s.id),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerCard() {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.person_outline),
        title: Text(_customer?.name ?? 'Walk-in customer'),
        subtitle: _customer != null
            ? Text(
                '${_customer!.phone}${_customer!.outstandingBalance > 0 ? '  •  ₹${_customer!.outstandingBalance.toStringAsFixed(0)} due' : ''}')
            : const Text('No customer attached to the original sale'),
      ),
    );
  }

  Widget _buildReturnLinesCard() {
    if (_returnLines.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: Text('No items on this sale')),
        ),
      );
    }
    return Card(
      child: Column(children: _returnLines.map(_buildReturnLineTile).toList()),
    );
  }

  Widget _buildReturnLineTile(_ReturnLine line) {
    final qtyController = TextEditingController(text: formatQty(line.quantity));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
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
              enabled: line.included,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Qty', isDense: true),
              onChanged: (value) {
                final parsed = parseQty(value);
                if (parsed == null || parsed <= 0) return;
                final capped = parsed > line.maxQuantity ? line.maxQuantity : parsed;
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
                  onChanged: line.included ? (v) => setState(() => line.restocked = v) : null,
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
        ],
      ),
    );
  }

  Widget _buildReplacementSearch() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: TextField(
          controller: _productSearchController,
          decoration: InputDecoration(
            labelText: 'Scan barcode or search product to add',
            prefixIcon: const Icon(Icons.search),
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: const Icon(Icons.add),
              onPressed: () => _searchAndAddReplacementProduct(_productSearchController.text),
            ),
          ),
          onSubmitted: _searchAndAddReplacementProduct,
        ),
      ),
    );
  }

  Widget _buildNewItemsCard() {
    if (_newItems.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: Text('No replacement items yet')),
        ),
      );
    }
    return Card(
      child: Column(
        children: _newItems.map((line) {
          final qtyController = TextEditingController(text: formatQty(line.quantity));
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Expanded(flex: 3, child: Text(line.productName, overflow: TextOverflow.ellipsis)),
                SizedBox(
                  width: 80,
                  child: TextField(
                    controller: qtyController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Qty', isDense: true),
                    onChanged: (value) {
                      final parsed = parseQty(value);
                      if (parsed == null || parsed <= 0) return;
                      setState(() => line.quantity = parsed);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 90,
                  child: Text(
                    '₹${line.totalPrice.toStringAsFixed(2)}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => setState(() => _newItems.remove(line)),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildReasonAndSettlement() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            TextField(
              controller: _reasonController,
              decoration: const InputDecoration(labelText: 'Reason for exchange', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _settlementMethod,
              decoration: const InputDecoration(labelText: 'Settlement method', border: OutlineInputBorder()),
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
              onChanged: (value) => setState(() => _settlementMethod = value ?? 'cash'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryAndSubmit() {
    final diff = _priceDifference;
    final diffColor = diff > 0 ? Colors.red : (diff < 0 ? Colors.green : Colors.grey);
    final diffLabel = diff > 0
        ? 'Customer owes ₹${diff.toStringAsFixed(2)}'
        : diff < 0
            ? 'Refund due ₹${(-diff).toStringAsFixed(2)}'
            : 'No difference';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('Return: ₹${_refundTotal.toStringAsFixed(2)}'),
            const SizedBox(width: 16),
            Text('New items: ₹${_newItemsNet.toStringAsFixed(2)}'),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          diffLabel,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: diffColor),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Spacer(),
            ElevatedButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.swap_horiz),
              label: const Text('Process Exchange'),
            ),
          ],
        ),
      ],
    );
  }
}
