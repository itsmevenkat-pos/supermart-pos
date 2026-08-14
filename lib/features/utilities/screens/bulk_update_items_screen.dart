import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_scaffold.dart';
import '../../../models/product_model.dart';
import '../../../repositories/product_repository.dart';

class _RowControllers {
  _RowControllers(Product product)
      : mrp = TextEditingController(text: _fmt(product.mrp)),
        retailPrice = TextEditingController(text: _fmt(product.retailPrice)),
        wholesalePrice = TextEditingController(text: _fmt(product.wholesalePrice)),
        costPrice = TextEditingController(text: _fmt(product.costPrice)),
        taxRate = TextEditingController(text: _fmt(product.taxRate)),
        stockQuantity = TextEditingController(text: _fmt(product.stockQuantity)),
        reorderLevel = TextEditingController(text: product.reorderLevel.toString());

  final TextEditingController mrp;
  final TextEditingController retailPrice;
  final TextEditingController wholesalePrice;
  final TextEditingController costPrice;
  final TextEditingController taxRate;
  final TextEditingController stockQuantity;
  final TextEditingController reorderLevel;

  static String _fmt(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toString();
  }

  void dispose() {
    mrp.dispose();
    retailPrice.dispose();
    wholesalePrice.dispose();
    costPrice.dispose();
    taxRate.dispose();
    stockQuantity.dispose();
    reorderLevel.dispose();
  }
}

class BulkUpdateItemsScreen extends ConsumerStatefulWidget {
  const BulkUpdateItemsScreen({super.key});

  @override
  ConsumerState<BulkUpdateItemsScreen> createState() => _BulkUpdateItemsScreenState();
}

class _BulkUpdateItemsScreenState extends ConsumerState<BulkUpdateItemsScreen> {
  bool _isLoading = true;
  bool _isSaving = false;
  List<Product> _products = [];
  final Map<String, _RowControllers> _controllers = {};
  final TextEditingController _filterController = TextEditingController();
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _load();
    _filterController.addListener(() {
      setState(() => _filter = _filterController.text.trim().toLowerCase());
    });
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final products = await ref.read(productRepositoryProvider).getAll();
      for (final controllers in _controllers.values) {
        controllers.dispose();
      }
      _controllers.clear();
      for (final product in products) {
        _controllers[product.id] = _RowControllers(product);
      }
      if (mounted) {
        setState(() {
          _products = products;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading items: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    for (final controllers in _controllers.values) {
      controllers.dispose();
    }
    _filterController.dispose();
    super.dispose();
  }

  List<Product> get _visibleProducts {
    if (_filter.isEmpty) return _products;
    return _products
        .where((p) =>
            p.name.toLowerCase().contains(_filter) ||
            p.barcode.toLowerCase().contains(_filter))
        .toList();
  }

  Future<void> _saveAll() async {
    setState(() => _isSaving = true);
    try {
      final updated = <Product>[];
      for (final product in _products) {
        final c = _controllers[product.id];
        if (c == null) continue;
        updated.add(
          product.copyWith(
            mrp: double.tryParse(c.mrp.text) ?? product.mrp,
            retailPrice: double.tryParse(c.retailPrice.text) ?? product.retailPrice,
            wholesalePrice: double.tryParse(c.wholesalePrice.text) ?? product.wholesalePrice,
            costPrice: double.tryParse(c.costPrice.text) ?? product.costPrice,
            taxRate: double.tryParse(c.taxRate.text) ?? product.taxRate,
            stockQuantity: double.tryParse(c.stockQuantity.text) ?? product.stockQuantity,
            reorderLevel: int.tryParse(c.reorderLevel.text) ?? product.reorderLevel,
          ),
        );
      }

      await ref.read(productRepositoryProvider).bulkUpdate(updated);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Updated ${updated.length} items'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Update Items In Bulk',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: _isLoading || _isSaving ? null : _load,
        ),
      ],
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _filterController,
                    decoration: const InputDecoration(
                      labelText: 'Search by name or barcode',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: _visibleProducts.isEmpty
                        ? const Center(child: Text('No items found'))
                        : SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: SingleChildScrollView(
                              child: DataTable(
                                columns: const [
                                  DataColumn(label: Text('Name')),
                                  DataColumn(label: Text('MRP')),
                                  DataColumn(label: Text('Retail')),
                                  DataColumn(label: Text('Wholesale')),
                                  DataColumn(label: Text('Cost')),
                                  DataColumn(label: Text('Tax %')),
                                  DataColumn(label: Text('Stock')),
                                  DataColumn(label: Text('Reorder')),
                                ],
                                rows: _visibleProducts.map((product) {
                                  final c = _controllers[product.id]!;
                                  return DataRow(
                                    cells: [
                                      DataCell(SizedBox(
                                        width: 160,
                                        child: Text(product.name, overflow: TextOverflow.ellipsis),
                                      )),
                                      DataCell(_cellField(c.mrp)),
                                      DataCell(_cellField(c.retailPrice)),
                                      DataCell(_cellField(c.wholesalePrice)),
                                      DataCell(_cellField(c.costPrice)),
                                      DataCell(_cellField(c.taxRate)),
                                      DataCell(_cellField(c.stockQuantity, decimal: true)),
                                      DataCell(_cellField(c.reorderLevel, integerOnly: true)),
                                    ],
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: _isSaving
                        ? const Center(child: CircularProgressIndicator())
                        : ElevatedButton(
                            onPressed: _saveAll,
                            child: const Text('Save All'),
                          ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _cellField(
    TextEditingController controller, {
    bool decimal = false,
    bool integerOnly = false,
  }) {
    return SizedBox(
      width: 90,
      child: TextFormField(
        controller: controller,
        keyboardType: integerOnly
            ? TextInputType.number
            : TextInputType.numberWithOptions(decimal: decimal),
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          border: OutlineInputBorder(),
        ),
      ),
    );
  }
}
