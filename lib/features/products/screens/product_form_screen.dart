import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../models/product_model.dart';
import '../../../models/product_batch_model.dart';
import '../../../models/product_kit_component_model.dart';
import '../../../models/category_model.dart';
import '../../../core/utils/quantity_utils.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/product_provider.dart';
import '../../../repositories/category_repository.dart';
import '../../../repositories/price_history_repository.dart';
import '../../../repositories/product_repository.dart';
import '../../../repositories/product_batch_repository.dart';
import '../../../repositories/product_kit_repository.dart';
import '../widgets/product_picker_dialog.dart';
import 'price_history_screen.dart';
import 'package:uuid/uuid.dart';

class ProductFormScreen extends ConsumerStatefulWidget {
  final Product? initialProduct;

  const ProductFormScreen({super.key, this.initialProduct});

  @override
  ConsumerState<ProductFormScreen> createState() => _ProductFormScreenState();
}

/// Local wrapper so the Components list can show a name without a repeated
/// lookup on every rebuild.
class _KitComponentRow {
  final String componentProductId;
  final String componentName;
  double quantity;

  _KitComponentRow({required this.componentProductId, required this.componentName, required this.quantity});
}

class _ProductFormScreenState extends ConsumerState<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _barcodeController;
  late final TextEditingController _nameController;
  late final TextEditingController _searchNameController;
  late final TextEditingController _displayNameController;
  late final TextEditingController _localNameController;
  late final TextEditingController _hsnCodeController;
  late final TextEditingController _mrpController;
  late final TextEditingController _retailPriceController;
  late final TextEditingController _wholesalePriceController;
  late final TextEditingController _costPriceController;
  late final TextEditingController _taxRateController;
  late final TextEditingController _stockController;
  late final TextEditingController _reorderController;
  late final TextEditingController _maxStockController;
  late final TextEditingController _unitController;
  late final TextEditingController _purchaseUnitController;
  late final TextEditingController _unitsPerPurchaseUnitController;

  Product? _product;
  String? _selectedCategoryId;
  bool _bonusEligible = true;
  bool _allowNegativeStock = false;
  bool _isActive = true;
  bool _isWeighted = false;
  bool _isService = false;
  bool _isKit = false;
  bool _isSaving = false;

  String? _parentProductId;
  String? _parentProductName;
  String? _imagePath;
  List<_KitComponentRow> _kitComponents = [];
  Future<List<ProductBatch>>? _batchesFuture;

  @override
  void initState() {
    super.initState();
    _product = widget.initialProduct;

    _barcodeController = TextEditingController(text: _product?.barcode ?? '');
    _nameController = TextEditingController(text: _product?.name ?? '');
    _searchNameController = TextEditingController(text: _product?.searchName ?? '');
    _displayNameController = TextEditingController(text: _product?.displayName ?? '');
    _localNameController = TextEditingController(text: _product?.localName ?? '');
    _hsnCodeController = TextEditingController(text: _product?.hsnCode ?? '');
    _mrpController = TextEditingController(text: _product?.mrp.toString() ?? '0');
    _retailPriceController = TextEditingController(text: _product?.retailPrice.toString() ?? '0');
    _wholesalePriceController = TextEditingController(text: _product?.wholesalePrice.toString() ?? '0');
    _costPriceController = TextEditingController(text: _product?.costPrice.toString() ?? '0');
    _taxRateController = TextEditingController(text: _product?.taxRate.toString() ?? '0');
    _stockController = TextEditingController(text: formatQty(_product?.stockQuantity ?? 0));
    _reorderController = TextEditingController(text: _product?.reorderLevel.toString() ?? '5');
    _maxStockController = TextEditingController(text: _product?.maxStockLevel?.toString() ?? '');
    _unitController = TextEditingController(text: _product?.unit ?? 'Pcs');
    _purchaseUnitController = TextEditingController(text: _product?.purchaseUnit ?? '');
    _unitsPerPurchaseUnitController =
        TextEditingController(text: _product?.unitsPerPurchaseUnit.toString() ?? '1');
    _selectedCategoryId = _product?.categoryId;
    _bonusEligible = _product?.bonusEligible ?? true;
    _allowNegativeStock = _product?.allowNegativeStock ?? false;
    _isActive = _product?.isActive ?? true;
    _isWeighted = _product?.isWeighted ?? false;
    _isService = _product?.isService ?? false;
    _isKit = _product?.isKit ?? false;
    _parentProductId = _product?.parentProductId;
    _imagePath = _product?.imagePath;

    // Margin display recomputes off these two, nothing else needs a listener.
    _costPriceController.addListener(_refresh);
    _retailPriceController.addListener(_refresh);

    if (_product != null) {
      _loadParentName();
      _loadKitComponents();
      _batchesFuture = ProductBatchRepository().getByProduct(_product!.id);
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _loadParentName() async {
    if (_product?.parentProductId == null) return;
    final parent = await ProductRepository().getById(_product!.parentProductId!);
    if (mounted) setState(() => _parentProductName = parent?.displayName ?? parent?.name);
  }

  Future<void> _loadKitComponents() async {
    if (_product == null) return;
    final components = await ProductKitRepository().getComponents(_product!.id);
    final rows = <_KitComponentRow>[];
    for (final c in components) {
      final componentProduct = await ProductRepository().getById(c.componentProductId);
      rows.add(_KitComponentRow(
        componentProductId: c.componentProductId,
        componentName: componentProduct?.displayName ?? componentProduct?.name ?? 'Unknown item',
        quantity: c.quantity,
      ));
    }
    if (mounted) setState(() => _kitComponents = rows);
  }

  @override
  void dispose() {
    _barcodeController.dispose();
    _nameController.dispose();
    _searchNameController.dispose();
    _displayNameController.dispose();
    _localNameController.dispose();
    _hsnCodeController.dispose();
    _mrpController.dispose();
    _retailPriceController.dispose();
    _wholesalePriceController.dispose();
    _costPriceController.dispose();
    _taxRateController.dispose();
    _stockController.dispose();
    _reorderController.dispose();
    _maxStockController.dispose();
    _unitController.dispose();
    _purchaseUnitController.dispose();
    _unitsPerPurchaseUnitController.dispose();
    super.dispose();
  }

  double get _marginPercent {
    final retail = double.tryParse(_retailPriceController.text) ?? 0;
    final cost = double.tryParse(_costPriceController.text) ?? 0;
    return retail > 0 ? ((retail - cost) / retail) * 100 : 0;
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      dialogTitle: 'Select item image',
    );
    final path = result?.files.single.path;
    if (path == null) return;
    setState(() => _imagePath = path);
  }

  Future<void> _pickParent() async {
    final picked = await showDialog<Product>(
      context: context,
      builder: (_) => ProductPickerDialog(excludeProductId: _product?.id),
    );
    if (picked != null) {
      setState(() {
        _parentProductId = picked.id;
        _parentProductName = picked.displayName ?? picked.name;
      });
    }
  }

  Future<void> _addKitComponent() async {
    final picked = await showDialog<Product>(
      context: context,
      builder: (_) => ProductPickerDialog(excludeProductId: _product?.id, excludeKits: true),
    );
    if (picked == null) return;
    if (_kitComponents.any((c) => c.componentProductId == picked.id)) return;
    setState(() {
      _kitComponents.add(_KitComponentRow(
        componentProductId: picked.id,
        componentName: picked.displayName ?? picked.name,
        quantity: 1,
      ));
    });
  }

  /// Logs an audit row per changed price field. Wrapped so a logging
  /// failure (e.g. a transient DB hiccup) never blocks the price update
  /// that already succeeded — but it's not swallowed silently either, it
  /// shows up in debug output for diagnosis.
  Future<void> _logPriceChanges(Product before, Product after) async {
    try {
      final userId = ref.read(authProvider).user?.id;
      final repo = PriceHistoryRepository();
      final changes = <(String, double, double)>[
        ('retail_price', before.retailPrice, after.retailPrice),
        ('mrp', before.mrp, after.mrp),
        ('cost_price', before.costPrice, after.costPrice),
        ('wholesale_price', before.wholesalePrice, after.wholesalePrice),
      ];
      for (final (field, oldValue, newValue) in changes) {
        if (oldValue != newValue) {
          await repo.logChange(after.id, field, oldValue, newValue, userId);
        }
      }
    } catch (e) {
      debugPrint('Failed to log price history for product ${after.id}: $e');
    }
  }

  /// Logs a BARCODE_ASSIGNED (new product) or BARCODE_CHANGED (edit) audit
  /// row. Wrapped the same way as [_logPriceChanges] so a logging failure
  /// never blocks the product save that already succeeded.
  Future<void> _logBarcodeChange({
    required String productId,
    required String actionType,
    String? oldBarcode,
    required String newBarcode,
  }) async {
    try {
      final userId = ref.read(authProvider).user?.id;
      if (userId == null) return;
      await DatabaseHelper.instance.logAudit(
        userId: userId,
        actionType: actionType,
        tableName: 'products',
        recordId: productId,
        oldValue: oldBarcode,
        newValue: newBarcode,
      );
    } catch (e) {
      debugPrint('Failed to log barcode change for product $productId: $e');
    }
  }

  /// Shows existing products sharing the entered barcode (excluding the
  /// product being edited) and asks the user to confirm before saving.
  /// Duplicate barcodes across MRP/pack-size variants are legitimate and
  /// common in this app, so this is a dismissible warning, not a hard block.
  Future<bool> _confirmDuplicateBarcode(String barcode, List<Product> existing) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Barcode already in use'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Barcode $barcode is already used by:'),
              const SizedBox(height: 8),
              ...existing.map(
                (p) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text('• ${p.displayName ?? p.name} (MRP ₹${p.mrp.toStringAsFixed(2)})'),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                "This is fine if you're adding a different MRP/pack size of the same item — "
                'otherwise check the barcode. Continue?',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continue')),
        ],
      ),
    );
    return result ?? false;
  }

  /// Fills the barcode field with a new internal barcode, using the same
  /// `PLU<millis>` scheme as the quick-add-product dialog in
  /// purchase_form_screen.dart, so there's one consistent internal-barcode
  /// format across the app. Checks for a (practically impossible) collision
  /// and regenerates once if needed.
  Future<void> _generateBarcode() async {
    var candidate = 'PLU${DateTime.now().millisecondsSinceEpoch}';
    var matches = await ProductRepository().getByBarcode(candidate);
    if (matches.isNotEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
      candidate = 'PLU${DateTime.now().millisecondsSinceEpoch}';
      matches = await ProductRepository().getByBarcode(candidate);
    }
    if (!mounted) return;
    setState(() => _barcodeController.text = candidate);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final enteredBarcode = _barcodeController.text.trim();
    final barcodeMatches = await ProductRepository().getByBarcode(enteredBarcode);
    final duplicateOwners = barcodeMatches.where((p) => p.id != _product?.id).toList();
    if (duplicateOwners.isNotEmpty) {
      if (!mounted) return;
      final proceed = await _confirmDuplicateBarcode(enteredBarcode, duplicateOwners);
      if (!proceed) return;
    }
    if (!mounted) return;

    setState(() => _isSaving = true);

    final product = Product(
      id: _product?.id ?? const Uuid().v4(),
      storeId: 'store_default',
      barcode: _barcodeController.text.trim(),
      name: _nameController.text.trim(),
      searchName: _searchNameController.text.trim(),
      displayName: _displayNameController.text.trim(),
      localName: _localNameController.text.trim().isEmpty ? null : _localNameController.text.trim(),
      hsnCode: _hsnCodeController.text.trim().isEmpty ? null : _hsnCodeController.text.trim(),
      categoryId: _selectedCategoryId,
      unit: _unitController.text.trim(),
      purchaseUnit: _purchaseUnitController.text.trim().isEmpty ? null : _purchaseUnitController.text.trim(),
      unitsPerPurchaseUnit: double.tryParse(_unitsPerPurchaseUnitController.text) ?? 1,
      mrp: double.tryParse(_mrpController.text) ?? 0,
      retailPrice: double.tryParse(_retailPriceController.text) ?? 0,
      wholesalePrice: double.tryParse(_wholesalePriceController.text) ?? 0,
      costPrice: double.tryParse(_costPriceController.text) ?? 0,
      taxRate: double.tryParse(_taxRateController.text) ?? 0,
      stockQuantity: _isService ? 0 : (double.tryParse(_stockController.text) ?? 0),
      reorderLevel: _isService ? 0 : (int.tryParse(_reorderController.text) ?? 5),
      maxStockLevel: _isService ? null : double.tryParse(_maxStockController.text),
      bonusEligible: _bonusEligible,
      allowNegativeStock: _isService ? false : _allowNegativeStock,
      isActive: _isActive,
      isWeighted: _isWeighted,
      isService: _isService,
      isKit: _isKit,
      parentProductId: _parentProductId,
      imagePath: _imagePath,
      isDeleted: false,
      createdAt: _product?.createdAt ?? DateTime.now().millisecondsSinceEpoch,
      updatedAt: _product?.updatedAt,
    );

    try {
      final notifier = ref.read(productNotifierProvider.notifier);
      if (_product == null) {
        await notifier.addProduct(product);
        await _logBarcodeChange(
          productId: product.id,
          actionType: 'BARCODE_ASSIGNED',
          newBarcode: product.barcode,
        );
      } else {
        await notifier.updateProduct(product);
        await _logPriceChanges(_product!, product);
        if (_product!.barcode != product.barcode) {
          await _logBarcodeChange(
            productId: product.id,
            actionType: 'BARCODE_CHANGED',
            oldBarcode: _product!.barcode,
            newBarcode: product.barcode,
          );
        }
      }

      if (_isKit) {
        await ProductKitRepository().setComponents(
          product.id,
          _kitComponents
              .map((c) => ProductKitComponent.create(
                    kitProductId: product.id,
                    componentProductId: c.componentProductId,
                    quantity: c.quantity,
                  ))
              .toList(),
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Product saved successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
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
      title: _product == null ? 'New Product' : 'Edit Product',
      actions: _product == null
          ? null
          : [
              IconButton(
                icon: const Icon(Icons.history),
                tooltip: 'Price History',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PriceHistoryScreen(
                        productId: _product!.id,
                        productName: _product!.displayName ?? _product!.name,
                      ),
                    ),
                  );
                },
              ),
            ],
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              _buildImagePicker(),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _barcodeController,
                      decoration: const InputDecoration(labelText: 'Barcode *'),
                      validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.qr_code),
                    tooltip: 'Generate a new barcode',
                    onPressed: _generateBarcode,
                  ),
                ],
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
              TextFormField(
                controller: _localNameController,
                decoration: const InputDecoration(
                  labelText: 'Local Name (Tamil / Hindi / regional)',
                  helperText: 'Second name in the local script, stored separately from the English name',
                ),
              ),
              const SizedBox(height: 12),
              _buildCategoryDropdown(),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _unitController,
                      decoration: const InputDecoration(labelText: 'Unit (e.g., Pcs, Kg, Ltr)'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _hsnCodeController,
                      decoration: const InputDecoration(labelText: 'HSN/SAC Code'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _purchaseUnitController,
                      decoration: const InputDecoration(labelText: 'Purchase Unit (e.g., Box)'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _unitsPerPurchaseUnitController,
                      decoration: InputDecoration(
                        labelText: 'Units per ${_purchaseUnitController.text.trim().isEmpty ? "Purchase Unit" : _purchaseUnitController.text.trim()}',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.only(top: 4, left: 4),
                child: Text(
                  'Used when receiving stock in a different unit than you sell it in — e.g. 1 Box = 12 Pcs.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
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
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  'Margin: ${_marginPercent.toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: _marginPercent >= 0 ? Colors.green.shade700 : Colors.red.shade700,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _taxRateController,
                decoration: const InputDecoration(labelText: 'Tax Rate (%)'),
                keyboardType: TextInputType.number,
              ),
              if (!_isService) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _stockController,
                  decoration: const InputDecoration(
                    labelText: 'Stock Quantity',
                    helperText: 'Decimals allowed for weighed items, e.g. 2.5',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _reorderController,
                        decoration: const InputDecoration(labelText: 'Reorder Level (min)'),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _maxStockController,
                        decoration: const InputDecoration(
                          labelText: 'Max Stock Level',
                          helperText: 'Optional overstocking ceiling',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              CheckboxListTile(
                value: _bonusEligible,
                onChanged: (val) => setState(() => _bonusEligible = val ?? true),
                title: const Text('Bonus Eligible'),
              ),
              if (!_isService)
                CheckboxListTile(
                  value: _allowNegativeStock,
                  onChanged: (val) => setState(() => _allowNegativeStock = val ?? false),
                  title: const Text('Allow Negative Stock'),
                  subtitle:
                      const Text('Sell this even when stock shows 0 or below (e.g. sold before restock is entered)'),
                ),
              SwitchListTile(
                value: _isActive,
                onChanged: (val) => setState(() => _isActive = val),
                title: const Text('Active'),
                subtitle: const Text(
                  'Inactive items are hidden from billing search/scan, but keep their stock, sales '
                  'history, and reports. Use this instead of deleting a duplicate or discontinued barcode.',
                ),
              ),
              SwitchListTile(
                value: _isWeighted,
                onChanged: (val) => setState(() => _isWeighted = val),
                title: const Text('Sold by Weight'),
                subtitle: const Text('Loose produce, meat, etc. — priced per unit weight, decimal quantities.'),
              ),
              SwitchListTile(
                value: _isService,
                onChanged: (val) => setState(() {
                  _isService = val;
                  if (val) _isKit = false;
                }),
                title: const Text('Non-Inventory / Service Item'),
                subtitle: const Text('Carry bag, delivery charge, repair charge — billable, never stock-tracked.'),
              ),
              SwitchListTile(
                value: _isKit,
                onChanged: (val) => setState(() {
                  _isKit = val;
                  if (val) _isService = false;
                }),
                title: const Text('Kit / Bundle'),
                subtitle: const Text('Selling this deducts stock from its components instead of its own stock.'),
              ),
              if (_isKit) _buildKitComponents(),
              const SizedBox(height: 8),
              _buildParentPicker(),
              if (_product != null) ...[
                const SizedBox(height: 16),
                _buildBatchesSection(),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: _isSaving
                    ? const Center(child: CircularProgressIndicator())
                    : ElevatedButton(
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

  Widget _buildImagePicker() {
    return Center(
      child: GestureDetector(
        onTap: _pickImage,
        child: Stack(
          children: [
            CircleAvatar(
              radius: 44,
              backgroundColor: Colors.grey.shade200,
              backgroundImage: _imagePath != null ? FileImage(File(_imagePath!)) : null,
              child: _imagePath == null
                  ? const Icon(Icons.inventory_2_outlined, size: 32, color: Colors.grey)
                  : null,
            ),
            Positioned(
              bottom: 0,
              right: 0,
              child: CircleAvatar(
                radius: 14,
                backgroundColor: Colors.white,
                child: Icon(Icons.edit, size: 14, color: Theme.of(context).colorScheme.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildParentPicker() {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.account_tree_outlined),
        title: Text(_parentProductName != null ? 'Variant of $_parentProductName' : 'Not linked to a parent product'),
        subtitle: const Text('Optionally group size/pack variants (500ml, 1L, 2L) under one parent for reporting.'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_parentProductId != null)
              IconButton(
                icon: const Icon(Icons.clear, size: 20),
                onPressed: () => setState(() {
                  _parentProductId = null;
                  _parentProductName = null;
                }),
              ),
            TextButton(onPressed: _pickParent, child: Text(_parentProductId == null ? 'Link' : 'Change')),
          ],
        ),
      ),
    );
  }

  Widget _buildKitComponents() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Components', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (_kitComponents.isEmpty) const Text('No components added yet', style: TextStyle(color: Colors.grey)),
            ..._kitComponents.map((c) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(child: Text(c.componentName)),
                      SizedBox(
                        width: 70,
                        child: TextFormField(
                          initialValue: c.quantity.toString(),
                          decoration: const InputDecoration(labelText: 'Qty', isDense: true),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onChanged: (v) => c.quantity = double.tryParse(v) ?? 1,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setState(() => _kitComponents.remove(c)),
                      ),
                    ],
                  ),
                )),
            OutlinedButton.icon(
              onPressed: _addKitComponent,
              icon: const Icon(Icons.add),
              label: const Text('Add Component'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBatchesSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Batches', style: TextStyle(fontWeight: FontWeight.bold)),
            const Text(
              'Batch/MRP/expiry history from purchases — quantity received, not live remaining stock.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            FutureBuilder<List<ProductBatch>>(
              future: _batchesFuture,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final batches = snapshot.data!;
                if (batches.isEmpty) {
                  return const Text('No purchases recorded yet', style: TextStyle(color: Colors.grey));
                }
                return Column(
                  children: batches
                      .map((b) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.inventory, size: 20),
                            title: Text(b.batchNo?.isNotEmpty == true ? 'Batch ${b.batchNo}' : 'Unlabeled batch'),
                            subtitle: Text(
                              'MRP ₹${b.mrp?.toStringAsFixed(2) ?? '-'}  •  '
                              '${b.expiryDate != null ? 'Expires ${DateTime.fromMillisecondsSinceEpoch(b.expiryDate! * 1000).toLocal().toString().split(' ')[0]}' : 'No expiry'}  •  '
                              '${DateTime.fromMillisecondsSinceEpoch(b.createdAt * 1000).toLocal().toString().split(' ')[0]}',
                            ),
                            trailing: Text('+${formatQty(b.quantityReceived)}'),
                          ))
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryDropdown() {
    return FutureBuilder<List<Category>>(
      future: CategoryRepository().getAll(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return DropdownButtonFormField<String>(
            decoration: const InputDecoration(labelText: 'Category'),
            items: const [],
            onChanged: null,
          );
        }
        final categories = snapshot.data!;
        return DropdownButtonFormField<String>(
          decoration: const InputDecoration(labelText: 'Category'),
          initialValue: _selectedCategoryId,
          items: [
            const DropdownMenuItem(value: null, child: Text('None')),
            ...categories.map((c) => DropdownMenuItem(
                  value: c.id,
                  child: Text(c.name),
                )),
          ],
          onChanged: (val) => setState(() => _selectedCategoryId = val),
        );
      },
    );
  }
}
