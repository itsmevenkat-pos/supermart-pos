import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/permissions/price_override_guard.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../models/customer_model.dart';
import '../../../models/sale_item_model.dart';
import '../../../models/sale_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../repositories/customer_repository.dart';
import '../../../repositories/product_repository.dart';
import '../../../repositories/sale_cancellation_repository.dart';
import '../../../repositories/sale_repository.dart';
import 'sale_cancellations_list_screen.dart';

/// Cancels a whole completed sale — reverses stock, customer ledger, and
/// loyalty effects in one atomic transaction (see
/// `SaleCancellationRepository.cancelSale`). Unlike Returns, there's no
/// per-line quantity picking: cancel is all-or-nothing for the sale.
///
/// If [saleId] is null, the user first searches for the sale to cancel by
/// invoice number or customer name/phone.
class SaleCancelFormScreen extends ConsumerStatefulWidget {
  final String? saleId;

  const SaleCancelFormScreen({super.key, this.saleId});

  @override
  ConsumerState<SaleCancelFormScreen> createState() => _SaleCancelFormScreenState();
}

class _SaleLineDisplay {
  final String productName;
  final double quantity;
  final double unitPrice;
  final double totalPrice;

  _SaleLineDisplay({
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.totalPrice,
  });
}

class _SaleCancelFormScreenState extends ConsumerState<SaleCancelFormScreen> {
  bool _loading = true;
  bool _submitting = false;

  Sale? _sale;
  List<SaleItem> _saleItems = [];
  List<_SaleLineDisplay> _lineDisplays = [];
  Customer? _customer;
  String _refundMethod = 'cash';

  final _reasonController = TextEditingController();
  final _searchController = TextEditingController();
  List<Sale> _searchResults = [];
  bool _searching = false;

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
    _searchController.dispose();
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
    final displays = <_SaleLineDisplay>[];
    for (final item in items) {
      final product = await productRepo.getById(item.productId);
      displays.add(_SaleLineDisplay(
        productName: product?.displayName ?? product?.name ?? 'Unknown item',
        quantity: item.quantity,
        unitPrice: item.unitPrice,
        totalPrice: item.totalPrice,
      ));
    }
    Customer? customer;
    if (sale.customerId != null) {
      customer = await CustomerRepository().getById(sale.customerId!);
    }
    if (!mounted) return;
    setState(() {
      _sale = sale;
      _saleItems = items;
      _lineDisplays = displays;
      _customer = customer;
      _loading = false;
    });
  }

  Future<void> _searchSales(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    setState(() => _searching = true);
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
      _searchResults = rows.map((e) => Sale.fromJson(e)).toList();
      _searching = false;
    });
  }

  Future<void> _submit() async {
    final sale = _sale;
    if (sale == null) return;
    if (_reasonController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('A reason is required')));
      return;
    }
    if (_refundMethod == 'credit_adjust' && _customer == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('This sale has no customer to adjust the refund against credit')));
      return;
    }

    final currentUser = ref.read(authProvider).user;
    if (currentUser == null) return;

    // Cancelling a completed sale is a bigger action than a return — always
    // gate on manager/admin approval, unlike Returns' amount-threshold logic.
    final approver = await requireApprovalWithApprover(
      context,
      ref,
      actionLabel: 'Cancel Sale ${sale.invoiceLabel} (₹${sale.netAmount.toStringAsFixed(2)})',
    );
    if (approver == null) return;

    setState(() => _submitting = true);
    try {
      await ref.read(saleCancellationRepositoryProvider).cancelSale(
            sale: sale,
            items: _saleItems,
            reason: _reasonController.text.trim(),
            refundMethod: _refundMethod,
            userId: currentUser.id,
            approvedByUserId: approver.id,
          );

      ref.invalidate(recentSaleCancellationsProvider);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sale ${sale.invoiceLabel} cancelled'), backgroundColor: Colors.green),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to cancel sale: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: _sale != null ? 'Cancel Sale — Invoice ${_sale!.invoiceLabel}' : 'Cancel a Sale',
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _sale == null
              ? _buildSearch()
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildSaleSummaryCard(),
                    const SizedBox(height: 12),
                    _buildLinesCard(),
                    const SizedBox(height: 12),
                    _buildReasonAndMethod(),
                    const SizedBox(height: 16),
                    _buildSubmit(),
                  ],
                ),
    );
  }

  Widget _buildSearch() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchController,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Search by invoice number or customer name/phone',
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              suffixIcon: _searching
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
            child: _searchResults.isEmpty
                ? const Center(child: Text('Search for a completed sale to cancel'))
                : ListView.builder(
                    itemCount: _searchResults.length,
                    itemBuilder: (_, index) {
                      final s = _searchResults[index];
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

  Widget _buildSaleSummaryCard() {
    final sale = _sale!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Invoice ${sale.invoiceLabel}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            Text('Date: ${DateTime.fromMillisecondsSinceEpoch(sale.createdAt * 1000).toLocal().toString().split(' ')[0]}'),
            Text('Customer: ${_customer?.name ?? 'Walk-in'}'),
            Text('Net amount: ₹${sale.netAmount.toStringAsFixed(2)}'),
          ],
        ),
      ),
    );
  }

  Widget _buildLinesCard() {
    if (_lineDisplays.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: Text('No items on this sale')),
        ),
      );
    }
    return Card(
      child: Column(
        children: _lineDisplays
            .map((line) => ListTile(
                  dense: true,
                  title: Text(line.productName),
                  subtitle: Text('${line.quantity} × ₹${line.unitPrice.toStringAsFixed(2)}'),
                  trailing: Text('₹${line.totalPrice.toStringAsFixed(2)}'),
                ))
            .toList(),
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
              decoration: const InputDecoration(labelText: 'Reason for cancellation', border: OutlineInputBorder()),
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

  Widget _buildSubmit() {
    final sale = _sale!;
    return Row(
      children: [
        Text('Refund total: ₹${sale.netAmount.toStringAsFixed(2)}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const Spacer(),
        ElevatedButton.icon(
          onPressed: _submitting ? null : _submit,
          icon: _submitting
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.cancel_outlined),
          label: const Text('Cancel Sale'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
        ),
      ],
    );
  }
}
