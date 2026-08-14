import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../models/product_model.dart';
import '../../../models/stock_ledger_model.dart';
import '../../../repositories/product_repository.dart';
import '../../../repositories/stock_ledger_repository.dart';

final _dateFormat = DateFormat('dd MMM yyyy, hh:mm a');

/// One row of "which sales included this item" — built from a raw
/// `sale_items` JOIN `sales` query, since neither [SaleRepository] nor any
/// other repository exposes a per-product lookup like this.
class _SaleRow {
  final int createdAt;
  final String invoiceLabel;
  final double quantity;
  final double amount;

  const _SaleRow({
    required this.createdAt,
    required this.invoiceLabel,
    required this.quantity,
    required this.amount,
  });
}

/// One row of "which purchases brought this item in" — built from a raw
/// `purchase_items` JOIN `purchases` query, for the same reason as
/// [_SaleRow] above.
class _PurchaseRow {
  final int createdAt;
  final String grnNo;
  final double quantity;
  final double cost;

  const _PurchaseRow({
    required this.createdAt,
    required this.grnNo,
    required this.quantity,
    required this.cost,
  });
}

class ItemDetailScreen extends ConsumerStatefulWidget {
  const ItemDetailScreen({super.key});

  @override
  ConsumerState<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends ConsumerState<ItemDetailScreen> with SingleTickerProviderStateMixin {
  final _searchController = TextEditingController();
  late final TabController _tabController;

  List<Product> _searchResults = [];
  bool _isSearching = false;

  Product? _selectedProduct;
  bool _isLoadingDetail = false;
  bool _isExporting = false;

  List<StockLedger> _stockLedger = [];
  List<_SaleRow> _salesRows = [];
  List<_PurchaseRow> _purchaseRows = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _clearSelection() {
    setState(() {
      _selectedProduct = null;
      _stockLedger = [];
      _salesRows = [];
      _purchaseRows = [];
      _searchController.clear();
      _searchResults = [];
      _tabController.index = 0;
    });
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    setState(() => _isSearching = true);
    try {
      final results = await ref.read(productRepositoryProvider).search(query);
      if (mounted) setState(() => _searchResults = results);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Search error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _selectProduct(Product product) async {
    setState(() {
      _selectedProduct = product;
      _isLoadingDetail = true;
      _stockLedger = [];
      _salesRows = [];
      _purchaseRows = [];
    });
    try {
      final stockLedger = await ref.read(stockLedgerRepositoryProvider).getByProduct(product.id, limit: 200);

      final db = await DatabaseHelper.instance.database;
      final saleRows = await db.rawQuery('''
        SELECT s.created_at AS created_at, s.invoice_no AS invoice_no, s.invoice_display_no AS invoice_display_no,
               si.quantity AS quantity, si.total_price AS total_price
        FROM sale_items si
        INNER JOIN sales s ON s.id = si.sale_id
        WHERE si.product_id = ?
        ORDER BY s.created_at DESC
      ''', [product.id]);

      final purchaseRows = await db.rawQuery('''
        SELECT p.created_at AS created_at, p.grn_no AS grn_no,
               pi.quantity AS quantity, pi.total AS total
        FROM purchase_items pi
        INNER JOIN purchases p ON p.id = pi.purchase_id
        WHERE pi.product_id = ?
        ORDER BY p.created_at DESC
      ''', [product.id]);

      if (!mounted) return;
      setState(() {
        _stockLedger = stockLedger;
        _salesRows = saleRows
            .map((r) => _SaleRow(
                  createdAt: r['created_at'] as int? ?? 0,
                  invoiceLabel: (r['invoice_display_no'] as String?) ?? '#${r['invoice_no']}',
                  quantity: (r['quantity'] as num?)?.toDouble() ?? 0,
                  amount: (r['total_price'] as num?)?.toDouble() ?? 0,
                ))
            .toList();
        _purchaseRows = purchaseRows
            .map((r) => _PurchaseRow(
                  createdAt: r['created_at'] as int? ?? 0,
                  grnNo: (r['grn_no'] as String?) ?? '',
                  quantity: (r['quantity'] as num?)?.toDouble() ?? 0,
                  cost: (r['total'] as num?)?.toDouble() ?? 0,
                ))
            .toList();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading item detail: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingDetail = false);
    }
  }

  Future<void> _saveCsv(String label, List<List<dynamic>> rows) async {
    if (rows.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nothing to export')));
      return;
    }
    setState(() => _isExporting = true);
    try {
      final csvString = const ListToCsvConverter().convert(rows);
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'item_${label}_$timestamp.csv';

      String? savedPath;
      try {
        savedPath = await FilePicker.platform.saveFile(
          dialogTitle: 'Save Item Export',
          fileName: fileName,
          bytes: utf8.encode(csvString),
        );
      } catch (_) {
        savedPath = await FilePicker.platform.saveFile(
          dialogTitle: 'Save Item Export',
          fileName: fileName,
        );
        if (savedPath != null) {
          await File(savedPath).writeAsString(csvString);
        }
      }

      if (!mounted) return;

      if (savedPath == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Export cancelled')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Exported ${rows.length - 1} row(s) to $savedPath'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _export() async {
    switch (_tabController.index) {
      case 0:
        await _saveCsv('stock_ledger', [
          ['Date', 'Reference Type', 'Quantity Change', 'Batch No', 'Cost Price', 'Selling Price'],
          for (final e in _stockLedger)
            [
              _dateFormat.format(DateTime.fromMillisecondsSinceEpoch(e.createdAt * 1000)),
              e.referenceType,
              e.quantityChange,
              e.batchNo ?? '',
              e.costPrice,
              e.sellingPrice,
            ],
        ]);
        break;
      case 1:
        await _saveCsv('sales', [
          ['Date', 'Invoice No', 'Quantity', 'Amount'],
          for (final r in _salesRows)
            [
              _dateFormat.format(DateTime.fromMillisecondsSinceEpoch(r.createdAt * 1000)),
              r.invoiceLabel,
              r.quantity,
              r.amount,
            ],
        ]);
        break;
      default:
        await _saveCsv('purchases', [
          ['Date', 'GRN No', 'Quantity', 'Cost'],
          for (final r in _purchaseRows)
            [
              _dateFormat.format(DateTime.fromMillisecondsSinceEpoch(r.createdAt * 1000)),
              r.grnNo,
              r.quantity,
              r.cost,
            ],
        ]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final product = _selectedProduct;

    return AppScaffold(
      title: 'Item Detail',
      body: product == null
          ? Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      labelText: 'Search by name / barcode',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: _search,
                  ),
                  const SizedBox(height: 8),
                  if (_isSearching) const LinearProgressIndicator(),
                  Expanded(child: _buildSearchResults()),
                ],
              ),
            )
          : Column(
              children: [
                _buildProductHeader(product),
                TabBar(
                  controller: _tabController,
                  labelColor: Theme.of(context).colorScheme.primary,
                  tabs: const [
                    Tab(text: 'Stock Ledger'),
                    Tab(text: 'Sales'),
                    Tab(text: 'Purchases'),
                  ],
                ),
                Expanded(
                  child: _isLoadingDetail
                      ? const Center(child: CircularProgressIndicator())
                      : TabBarView(
                          controller: _tabController,
                          children: [
                            _buildStockLedgerTab(),
                            _buildSalesTab(),
                            _buildPurchasesTab(),
                          ],
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: (_isExporting || _isLoadingDetail) ? null : _export,
                      icon: _isExporting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.download),
                      label: const Text('Export CSV'),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSearchResults() {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      return const Center(child: Text('Search for an item to view its detail'));
    }
    if (!_isSearching && _searchResults.isEmpty) {
      return const Center(child: Text('No matching items'));
    }
    return ListView.separated(
      itemCount: _searchResults.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, index) {
        final product = _searchResults[index];
        return ListTile(
          leading: const CircleAvatar(child: Icon(Icons.inventory_2)),
          title: Text(product.name),
          subtitle: Text('Barcode: ${product.barcode}'),
          trailing: Text(product.stockQuantity.toStringAsFixed(2)),
          onTap: () => _selectProduct(product),
        );
      },
    );
  }

  Widget _buildProductHeader(Product product) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text('Barcode: ${product.barcode}'),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _statTile(
                      'Stock',
                      product.stockQuantity.toStringAsFixed(2),
                      product.isLowStock ? Colors.red : Colors.green,
                    ),
                    _statTile('MRP', '₹${product.mrp.toStringAsFixed(2)}', Colors.blueGrey),
                    _statTile('Retail Price', '₹${product.retailPrice.toStringAsFixed(2)}', Colors.blueGrey),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Change item',
            onPressed: _clearSelection,
          ),
        ],
      ),
    );
  }

  Widget _statTile(String label, String value, Color color) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _buildStockLedgerTab() {
    if (_stockLedger.isEmpty) {
      return const Center(child: Text('No stock ledger entries yet'));
    }
    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Date')),
            DataColumn(label: Text('Reference')),
            DataColumn(label: Text('Qty Change'), numeric: true),
            DataColumn(label: Text('Batch No')),
            DataColumn(label: Text('Cost Price'), numeric: true),
            DataColumn(label: Text('Selling Price'), numeric: true),
          ],
          rows: _stockLedger
              .map(
                (e) => DataRow(cells: [
                  DataCell(Text(_dateFormat.format(DateTime.fromMillisecondsSinceEpoch(e.createdAt * 1000)))),
                  DataCell(Text(e.referenceType)),
                  DataCell(Text(e.quantityChange.toStringAsFixed(2))),
                  DataCell(Text(e.batchNo ?? '')),
                  DataCell(Text(e.costPrice.toStringAsFixed(2))),
                  DataCell(Text(e.sellingPrice.toStringAsFixed(2))),
                ]),
              )
              .toList(),
        ),
      ),
    );
  }

  Widget _buildSalesTab() {
    if (_salesRows.isEmpty) {
      return const Center(child: Text('This item has not been sold yet'));
    }
    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Date')),
            DataColumn(label: Text('Invoice No')),
            DataColumn(label: Text('Quantity'), numeric: true),
            DataColumn(label: Text('Amount'), numeric: true),
          ],
          rows: _salesRows
              .map(
                (r) => DataRow(cells: [
                  DataCell(Text(_dateFormat.format(DateTime.fromMillisecondsSinceEpoch(r.createdAt * 1000)))),
                  DataCell(Text(r.invoiceLabel)),
                  DataCell(Text(r.quantity.toStringAsFixed(2))),
                  DataCell(Text(r.amount.toStringAsFixed(2))),
                ]),
              )
              .toList(),
        ),
      ),
    );
  }

  Widget _buildPurchasesTab() {
    if (_purchaseRows.isEmpty) {
      return const Center(child: Text('This item has not been purchased yet'));
    }
    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Date')),
            DataColumn(label: Text('GRN No')),
            DataColumn(label: Text('Quantity'), numeric: true),
            DataColumn(label: Text('Cost'), numeric: true),
          ],
          rows: _purchaseRows
              .map(
                (r) => DataRow(cells: [
                  DataCell(Text(_dateFormat.format(DateTime.fromMillisecondsSinceEpoch(r.createdAt * 1000)))),
                  DataCell(Text(r.grnNo)),
                  DataCell(Text(r.quantity.toStringAsFixed(2))),
                  DataCell(Text(r.cost.toStringAsFixed(2))),
                ]),
              )
              .toList(),
        ),
      ),
    );
  }
}
