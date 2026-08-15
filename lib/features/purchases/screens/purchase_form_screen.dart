import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../models/purchase_model.dart';
import '../../../models/purchase_item_model.dart';
import '../../../models/product_model.dart';
import '../../../models/supplier_model.dart';
import '../../../models/category_model.dart';
import '../../../providers/product_provider.dart';
import '../../../providers/supplier_provider.dart';
import '../../../repositories/purchase_repository.dart';
import '../../../repositories/category_repository.dart';
import '../../../core/utils/quantity_utils.dart';

/// Purchase entry screen, redesigned into three short steps
/// (Details / Items / Totals) instead of one long scrolling form,
/// with collapsible item rows and a sticky totals bar.
class PurchaseFormScreen extends ConsumerStatefulWidget {
  final Purchase? existingPurchase;

  const PurchaseFormScreen({super.key, this.existingPurchase});

  @override
  ConsumerState<PurchaseFormScreen> createState() => _PurchaseFormScreenState();
}

const List<String> _kStatuses = ['draft', 'completed', 'cancelled'];

class _PurchaseFormScreenState extends ConsumerState<PurchaseFormScreen> {
  final _formKey = GlobalKey<FormState>();
  int _step = 0; // 0 = Details, 1 = Items, 2 = Totals

  // Header
  late final TextEditingController _grnController;
  late final TextEditingController _dateController;
  late final TextEditingController _locationController;
  late String _status;

  // Supplier
  Supplier? _selectedSupplier;
  late final TextEditingController _merchantController;
  late final TextEditingController _addressController;

  // Financial
  late final TextEditingController _billTotalController;
  late final TextEditingController _totalController;
  late final TextEditingController _differenceController;
  late final TextEditingController _accountPercentController;
  late final TextEditingController _accountController;
  late final TextEditingController _taxRateController;
  late final TextEditingController _taxPercentController;
  late final TextEditingController _taxController;
  late final TextEditingController _chessController;
  late final TextEditingController _netAmountController;

  // Logistics
  late final TextEditingController _transportStatusController;
  late final TextEditingController _transportController;
  late final TextEditingController _labourStatusController;
  late final TextEditingController _labourChargesController;
  late final TextEditingController _transportChargeController;

  // Other
  late final TextEditingController _totalQtyController;
  late final TextEditingController _remarksController;
  bool _received = false;
  late final TextEditingController _cFormController;
  late final TextEditingController _dueStatusController;
  late final TextEditingController _closeStatusController;
  late final TextEditingController _dueDateController;

  // Items
  List<PurchaseItem> _items = [];
  // Keyed by item.id: the MRP the product master had when this item was
  // added, so we can flag in the UI when an edited MRP will create a new
  // priced variant instead of silently overwriting the master record.
  final Map<String, double> _originalMrp = {};
  // Keyed by item.id: the Product this line was added for, so the "Buying
  // in" unit selector knows whether the product even has a purchaseUnit
  // configured and can label it (e.g. "Box (12 Pcs each)"). Populated
  // immediately on add, and looked up by productId when re-opening an
  // existing purchase for edit.
  final Map<String, Product> _itemProducts = {};
  final Set<int> _expandedItems = {};
  final TextEditingController _productSearchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  List<Product> _searchResults = [];
  Timer? _searchDebounce;
  bool _searching = false;
  List<Category> _categories = [];

  @override
  void initState() {
    super.initState();

    CategoryRepository().getAll().then((cats) {
      if (mounted) setState(() => _categories = cats);
    });

    final p = widget.existingPurchase;

    _grnController = TextEditingController(text: p?.grnNo ?? '');
    _dateController = TextEditingController(
      text: p != null
          ? DateTime.fromMillisecondsSinceEpoch(p.purchaseDate * 1000).toLocal().toString().split(' ')[0]
          : DateTime.now().toLocal().toString().split(' ')[0],
    );
    _locationController = TextEditingController(text: p?.location ?? '');
    _status = _kStatuses.contains(p?.status) ? p!.status : 'draft';

    _merchantController = TextEditingController(text: p?.supplierMerchant ?? '');
    _addressController = TextEditingController(text: p?.supplierAddress ?? '');

    _totalController = TextEditingController(text: p?.total.toString() ?? '0');
    _billTotalController = TextEditingController(text: p?.billTotal.toString() ?? '0');
    _differenceController = TextEditingController(text: p?.difference.toString() ?? '0');
    _accountPercentController = TextEditingController(text: p?.accountPercent.toString() ?? '0');
    _accountController = TextEditingController(text: p?.account.toString() ?? '0');
    _taxRateController = TextEditingController(text: p?.taxRate.toString() ?? '0');
    _taxPercentController = TextEditingController(text: p?.taxPercent.toString() ?? '0');
    _taxController = TextEditingController(text: p?.tax.toString() ?? '0');
    _chessController = TextEditingController(text: p?.chess ?? '');
    _netAmountController = TextEditingController(text: p?.netAmount.toString() ?? '0');

    _transportStatusController = TextEditingController(text: p?.transportStatus ?? '');
    _transportController = TextEditingController(text: p?.transport ?? '');
    _labourStatusController = TextEditingController(text: p?.labourStatus ?? '');
    _labourChargesController = TextEditingController(text: p?.labourCharges.toString() ?? '0');
    _transportChargeController = TextEditingController(text: p?.transportCharge.toString() ?? '0');

    _totalQtyController = TextEditingController(text: formatQty(p?.totalQty ?? 0));
    _remarksController = TextEditingController(text: p?.remarks ?? '');
    _received = p?.received ?? false;
    _cFormController = TextEditingController(text: p?.cForm ?? '');
    _dueStatusController = TextEditingController(text: p?.dueStatus ?? '');
    _closeStatusController = TextEditingController(text: p?.closeStatus ?? '');
    _dueDateController = TextEditingController(
      text: p != null && p.dueDate > 0
          ? DateTime.fromMillisecondsSinceEpoch(p.dueDate * 1000).toLocal().toString().split(' ')[0]
          : '',
    );

    if (p != null) {
      _loadItems(p.id);
    }

    _billTotalController.addListener(_recalculate);
    _accountPercentController.addListener(_recalculate);
    _taxRateController.addListener(_recalculate);
  }

  @override
  void dispose() {
    _grnController.dispose();
    _dateController.dispose();
    _locationController.dispose();
    _merchantController.dispose();
    _addressController.dispose();
    _totalController.dispose();
    _billTotalController.dispose();
    _differenceController.dispose();
    _accountPercentController.dispose();
    _accountController.dispose();
    _taxRateController.dispose();
    _taxPercentController.dispose();
    _taxController.dispose();
    _chessController.dispose();
    _netAmountController.dispose();
    _transportStatusController.dispose();
    _transportController.dispose();
    _labourStatusController.dispose();
    _labourChargesController.dispose();
    _transportChargeController.dispose();
    _totalQtyController.dispose();
    _remarksController.dispose();
    _cFormController.dispose();
    _dueStatusController.dispose();
    _closeStatusController.dispose();
    _dueDateController.dispose();
    _productSearchController.dispose();
    _searchFocus.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  // ----- Data -----

  Future<void> _loadItems(String purchaseId) async {
    final repo = PurchaseRepository();
    final items = await repo.getItemsByPurchase(purchaseId);
    setState(() => _items = items);
    _recalculate();
    await _hydrateItemProducts(items);
  }

  /// Looks up the current Product for each loaded line so the "Buying in"
  /// selector can tell whether it's eligible (purchaseUnit configured) and
  /// what to label it — the persisted `isPurchaseUnitEntry`/
  /// `purchaseUnitFactor` on the item itself stay authoritative regardless
  /// of whether this lookup succeeds.
  Future<void> _hydrateItemProducts(List<PurchaseItem> items) async {
    for (final item in items) {
      if (_itemProducts.containsKey(item.id)) continue;
      final product = await ref.read(productNotifierProvider.notifier).getProduct(item.productId);
      if (!mounted) return;
      if (product != null) {
        setState(() => _itemProducts[item.id] = product);
      }
    }
  }

  void _addProduct(Product product) {
    int existingIndex = -1;
    for (int i = 0; i < _items.length; i++) {
      if (_items[i].productId == product.id) {
        existingIndex = i;
        break;
      }
    }

    setState(() {
      if (existingIndex != -1) {
        final existing = _items[existingIndex];
        _items[existingIndex] = existing.copyWith(quantity: existing.quantity + 1);
        _expandedItems.add(existingIndex);
      } else {
        final newItem = PurchaseItem.create(
          productId: product.id,
          barcode: product.barcode,
          productName: product.name,
          mrp: product.mrp,
          quantity: 1,
          freeQuantity: 0,
          purchasePrice: product.costPrice,
          salesPrice: product.retailPrice,
          costPrice: product.costPrice,
          taxPercent: product.taxRate,
          last: product.costPrice,
          // Default new lines to the base stock unit — safest, unsurprising
          // default that matches today's behavior. The cashier can switch
          // to buying by the product's purchaseUnit via the selector below
          // when this product has one configured.
          isPurchaseUnitEntry: false,
          purchaseUnitFactor: product.unitsPerPurchaseUnit,
        );
        _originalMrp[newItem.id] = product.mrp;
        _itemProducts[newItem.id] = product;
        _items.add(newItem);
        _expandedItems.add(_items.length - 1);
      }
      _productSearchController.clear();
      _searchResults = [];
    });
    _recalculate();
  }

  void _removeItem(int index) {
    setState(() {
      _originalMrp.remove(_items[index].id);
      _itemProducts.remove(_items[index].id);
      _items.removeAt(index);
      _expandedItems.remove(index);
    });
    _recalculate();
  }

  void _updateItem(int index, PurchaseItem newItem) {
    setState(() => _items[index] = newItem);
    _recalculate();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _searchDebounce = Timer(const Duration(milliseconds: 300), () async {
      final results = await ref.read(productNotifierProvider.notifier).search(value.trim());
      if (!mounted) return;
      setState(() {
        _searchResults = results;
        _searching = false;
      });
    });
  }

  void _recalculate() {
    double stockTotal = 0;
    double totalQty = 0;

    for (final item in _items) {
      final effectiveQty = item.isRepack ? item.packCount.toDouble() : item.quantity.toDouble();
      stockTotal += item.purchasePrice * effectiveQty;
      totalQty += effectiveQty;
    }

    final billTotal = double.tryParse(_billTotalController.text) ?? 0;
    final diff = billTotal - stockTotal;
    _differenceController.text = diff.toStringAsFixed(2);
    _totalController.text = stockTotal.toStringAsFixed(2);

    final accountPercent = double.tryParse(_accountPercentController.text) ?? 0;
    final account = (stockTotal * accountPercent) / 100;
    _accountController.text = account.toStringAsFixed(2);

    final taxRate = double.tryParse(_taxRateController.text) ?? 0;
    final tax = (stockTotal - account) * (taxRate / 100);
    _taxController.text = tax.toStringAsFixed(2);

    final netAmount = stockTotal - account + tax;
    _netAmountController.text = netAmount.toStringAsFixed(2);
    _totalQtyController.text = formatQty(totalQty);

    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    if (_selectedSupplier == null && widget.existingPurchase == null) {
      _goToStepWithError(0, 'Please select a supplier');
      return;
    }
    if (_items.isEmpty) {
      _goToStepWithError(1, 'Add at least one product');
      return;
    }

    final purchase = Purchase.create(
      storeId: 'store_default',
      supplierId: _selectedSupplier?.id ?? widget.existingPurchase?.supplierId,
      grnNo: _grnController.text.trim(),
      purchaseDate: _dateController.text.isNotEmpty
          ? DateTime.parse(_dateController.text).millisecondsSinceEpoch ~/ 1000
          : DateTime.now().millisecondsSinceEpoch ~/ 1000,
      location: _locationController.text.trim(),
      supplierName: _selectedSupplier?.name ?? widget.existingPurchase?.supplierName,
      supplierMerchant: _merchantController.text.trim(),
      supplierAddress: _addressController.text.trim(),
      total: double.tryParse(_totalController.text) ?? 0,
      billTotal: double.tryParse(_billTotalController.text) ?? 0,
      difference: double.tryParse(_differenceController.text) ?? 0,
      accountPercent: double.tryParse(_accountPercentController.text) ?? 0,
      account: double.tryParse(_accountController.text) ?? 0,
      taxRate: double.tryParse(_taxRateController.text) ?? 0,
      taxPercent: double.tryParse(_taxPercentController.text) ?? 0,
      tax: double.tryParse(_taxController.text) ?? 0,
      chess: _chessController.text.trim().isNotEmpty ? _chessController.text.trim() : null,
      netAmount: double.tryParse(_netAmountController.text) ?? 0,
      transportStatus: _transportStatusController.text.trim().isNotEmpty ? _transportStatusController.text.trim() : null,
      transport: _transportController.text.trim().isNotEmpty ? _transportController.text.trim() : null,
      labourStatus: _labourStatusController.text.trim().isNotEmpty ? _labourStatusController.text.trim() : null,
      labourCharges: double.tryParse(_labourChargesController.text) ?? 0,
      transportCharge: double.tryParse(_transportChargeController.text) ?? 0,
      totalQty: double.tryParse(_totalQtyController.text) ?? 0,
      remarks: _remarksController.text.trim().isNotEmpty ? _remarksController.text.trim() : null,
      received: _received,
      cForm: _cFormController.text.trim().isNotEmpty ? _cFormController.text.trim() : null,
      dueStatus: _dueStatusController.text.trim().isNotEmpty ? _dueStatusController.text.trim() : null,
      closeStatus: _closeStatusController.text.trim().isNotEmpty ? _closeStatusController.text.trim() : null,
      dueDate: _dueDateController.text.isNotEmpty
          ? DateTime.parse(_dueDateController.text).millisecondsSinceEpoch ~/ 1000
          : 0,
      status: _status,
    );

    final repo = PurchaseRepository();
    try {
      if (widget.existingPurchase == null) {
        await repo.insertWithItems(purchase, _items);
      } else {
        await repo.updateWithItems(purchase, _items);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Purchase saved'), backgroundColor: Colors.green),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _goToStepWithError(int step, String message) {
    setState(() => _step = step);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  // ----- UI -----

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppScaffold(
      title: widget.existingPurchase == null ? 'New Purchase' : 'Edit Purchase',
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            _buildStepTabs(theme),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: switch (_step) {
                  0 => _buildDetailsStep(),
                  1 => _buildItemsStep(),
                  _ => _buildTotalsStep(),
                },
              ),
            ),
            _buildBottomBar(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildStepTabs(ThemeData theme) {
    const labels = ['Details', 'Items', 'Totals'];
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: List.generate(labels.length, (i) {
          final selected = _step == i;
          return Expanded(
            child: InkWell(
              onTap: () => setState(() => _step = i),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: selected ? theme.colorScheme.primary : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                child: Text(
                  '${i + 1}  ${labels[i]}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    color: selected ? theme.colorScheme.primary : theme.hintColor,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildBottomBar(ThemeData theme) {
    final netAmount = double.tryParse(_netAmountController.text) ?? 0;
    final totalQty = _totalQtyController.text;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$totalQty units · ${_items.length} item${_items.length == 1 ? '' : 's'}',
                    style: TextStyle(fontSize: 12, color: theme.hintColor),
                  ),
                  Text(
                    '₹${netAmount.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            ElevatedButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save, size: 18),
              label: const Text('Save purchase'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Step 1: Details ---

  Widget _buildDetailsStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionCard(
          title: 'Purchase info',
          children: [
            _statusChips(),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _grnController,
                    decoration: const InputDecoration(labelText: 'Purchase / GRN no *'),
                    validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _dateController,
                    decoration: const InputDecoration(labelText: 'Purchase date'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _locationController,
              decoration: const InputDecoration(labelText: 'Warehouse / location'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _sectionCard(
          title: 'Supplier',
          children: [
            Consumer(
              builder: (context, ref, child) {
                final suppliersAsync = ref.watch(supplierNotifierProvider);
                return suppliersAsync.when(
                  data: (suppliers) => DropdownButtonFormField<Supplier>(
                    initialValue: _selectedSupplier,
                    decoration: const InputDecoration(labelText: 'Supplier *'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Select supplier')),
                      ...suppliers.map((s) => DropdownMenuItem(value: s, child: Text(s.name))),
                    ],
                    onChanged: (val) {
                      setState(() {
                        _selectedSupplier = val;
                        if (val != null) {
                          _merchantController.text = val.phone ?? '';
                          _addressController.text = val.address ?? '';
                        }
                      });
                    },
                    validator: (v) => v == null && widget.existingPurchase == null ? 'Select a supplier' : null,
                  ),
                  loading: () => const LinearProgressIndicator(),
                  error: (err, stack) => Text('Error: $err'),
                );
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _merchantController,
              decoration: const InputDecoration(labelText: 'Contact / merchant'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _addressController,
              decoration: const InputDecoration(labelText: 'Address'),
              maxLines: 2,
            ),
          ],
        ),
        const SizedBox(height: 16),
        _sectionCard(
          title: 'Charges & delivery',
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _transportStatusController,
                    decoration: const InputDecoration(labelText: 'Transport status'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _transportChargeController,
                    decoration: const InputDecoration(labelText: 'Transport charge'),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _transportController,
              decoration: const InputDecoration(labelText: 'Transport / courier'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _labourStatusController,
                    decoration: const InputDecoration(labelText: 'Labour status'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _labourChargesController,
                    decoration: const InputDecoration(labelText: 'Labour charges'),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Checkbox(value: _received, onChanged: (v) => setState(() => _received = v ?? false)),
                      const Text('Received'),
                    ],
                  ),
                ),
                Expanded(
                  child: TextFormField(
                    controller: _dueDateController,
                    decoration: const InputDecoration(labelText: 'Due date'),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        _sectionCard(
          title: 'Other',
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _cFormController,
                    decoration: const InputDecoration(labelText: 'C Form'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _chessController,
                    decoration: const InputDecoration(labelText: 'Document ref'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _dueStatusController,
                    decoration: const InputDecoration(labelText: 'Due status'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _closeStatusController,
                    decoration: const InputDecoration(labelText: 'Close status'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _remarksController,
              decoration: const InputDecoration(labelText: 'Remarks'),
              maxLines: 2,
            ),
          ],
        ),
      ],
    );
  }

  Widget _statusChips() {
    return Wrap(
      spacing: 8,
      children: _kStatuses.map((s) {
        final selected = _status == s;
        return ChoiceChip(
          label: Text(s[0].toUpperCase() + s.substring(1)),
          selected: selected,
          onSelected: (_) => setState(() => _status = s),
        );
      }).toList(),
    );
  }

  // --- Step 2: Items ---

  Widget _buildItemsStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildProductSearch(),
        const SizedBox(height: 12),
        if (_items.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.inventory_2_outlined, size: 40, color: Theme.of(context).hintColor),
                    const SizedBox(height: 8),
                    Text('No items yet — search above to add one', style: TextStyle(color: Theme.of(context).hintColor)),
                  ],
                ),
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) => _buildItemCard(index),
          ),
      ],
    );
  }

  Widget _buildProductSearch() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _productSearchController,
          focusNode: _searchFocus,
          decoration: InputDecoration(
            hintText: 'Scan barcode or search product',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _searching
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : null,
            border: const OutlineInputBorder(),
          ),
          onChanged: _onSearchChanged,
        ),
        if (_searchResults.isNotEmpty)
          Card(
            margin: const EdgeInsets.only(top: 4),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _searchResults.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final product = _searchResults[i];
                  return ListTile(
                    dense: true,
                    title: Text(product.name),
                    subtitle: Text('Barcode: ${product.barcode} · ₹${product.retailPrice}'),
                    onTap: () => _addProduct(product),
                  );
                },
              ),
            ),
          )
        else if (!_searching && _productSearchController.text.trim().isNotEmpty)
          Card(
            margin: const EdgeInsets.only(top: 4),
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.add_circle_outline, color: Colors.green),
              title: Text('Add "${_productSearchController.text.trim()}" as a new product'),
              subtitle: const Text('Not in your product list yet — create it without leaving this screen'),
              onTap: () => _showQuickAddProductDialog(_productSearchController.text.trim()),
            ),
          ),
      ],
    );
  }

  /// Lets the cashier create a brand-new product right from Purchase Entry
  /// instead of having to stop, go to Products, add it there, then come
  /// back and search again. Cost/selling price and MRP for THIS purchase
  /// are still filled in on the item row afterwards — this dialog only
  /// covers what's needed to create the product master record.
  Future<void> _showQuickAddProductDialog(String initialQuery) async {
    final looksLikeBarcode = RegExp(r'^\d{4,}$').hasMatch(initialQuery);
    final nameController = TextEditingController(text: looksLikeBarcode ? '' : initialQuery);
    final barcodeController = TextEditingController(text: looksLikeBarcode ? initialQuery : '');
    final mrpController = TextEditingController();
    final taxController = TextEditingController(text: '5');
    final unitController = TextEditingController(text: 'Pcs');
    String? categoryId = _categories.isNotEmpty ? _categories.first.id : null;
    final formKey = GlobalKey<FormState>();

    final product = await showDialog<Product>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('New Product'),
          content: SizedBox(
            width: 420,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: nameController,
                      autofocus: !looksLikeBarcode,
                      decoration: const InputDecoration(labelText: 'Product Name *', border: OutlineInputBorder()),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: barcodeController,
                      autofocus: looksLikeBarcode,
                      decoration: const InputDecoration(labelText: 'Barcode (leave blank to auto-generate)', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    if (_categories.isNotEmpty)
                      DropdownButtonFormField<String>(
                        initialValue: categoryId,
                        decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
                        items: _categories
                            .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
                            .toList(),
                        onChanged: (v) => setDialogState(() => categoryId = v),
                      ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: unitController,
                            decoration: const InputDecoration(labelText: 'Unit', border: OutlineInputBorder()),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: taxController,
                            decoration: const InputDecoration(labelText: 'Tax %', border: OutlineInputBorder()),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: mrpController,
                      decoration: const InputDecoration(
                        labelText: 'MRP (optional)',
                        helperText: 'Cost/selling price are set on the item row after adding',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                if (!formKey.currentState!.validate()) return;
                final barcode = barcodeController.text.trim().isEmpty
                    ? 'PLU${DateTime.now().millisecondsSinceEpoch}'
                    : barcodeController.text.trim();
                final newProduct = Product.create(
                  barcode: barcode,
                  name: nameController.text.trim(),
                  categoryId: categoryId,
                  unit: unitController.text.trim().isEmpty ? 'Pcs' : unitController.text.trim(),
                  taxRate: double.tryParse(taxController.text.trim()) ?? 0,
                  mrp: double.tryParse(mrpController.text.trim()) ?? 0,
                );
                Navigator.pop(dialogContext, newProduct);
              },
              child: const Text('Add Product'),
            ),
          ],
        ),
      ),
    );

    if (product == null) return;

    try {
      await ref.read(productNotifierProvider.notifier).addProduct(product);
      if (!mounted) return;
      _addProduct(product);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${product.name} added to your product list'), backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create product: $e'), backgroundColor: Colors.red),
      );
    }
  }

  /// Mirrors `PurchaseRepository._stockQtyForItem` — purely for the UI
  /// preview hint shown while entering a line, so the cashier can see the
  /// conversion before saving. The actual stock write happens in the
  /// repository against the persisted item fields; this never itself
  /// writes anything.
  double _stockQtyPreview(PurchaseItem item) {
    if (item.isRepack) return item.packCount.toDouble();
    final rawQty = item.quantity + item.freeQuantity;
    final factor = item.isPurchaseUnitEntry ? item.purchaseUnitFactor : 1.0;
    return rawQty * factor;
  }

  Widget _buildItemCard(int index) {
    final item = _items[index];
    final expanded = _expandedItems.contains(index);
    final effectiveQty = item.isRepack ? item.packCount.toDouble() : item.quantity.toDouble();
    final lineTotal = item.purchasePrice * effectiveQty;
    final originalMrp = _originalMrp[item.id];
    final mrpChanged = originalMrp != null && (item.mrp - originalMrp).abs() > 0.005;

    // Purchase-unit (Box/Case) buying — only offered when the product has
    // one configured. Distinct from `isRepack` above; see PurchaseItem's
    // isPurchaseUnitEntry/purchaseUnitFactor doc comments.
    final product = _itemProducts[item.id];
    final purchaseUnitEligible =
        product != null && product.purchaseUnit != null && product.purchaseUnit!.isNotEmpty && product.unitsPerPurchaseUnit > 1;
    final baseUnitLabel = product?.unit ?? 'unit';
    final qtyUnitLabel = (item.isPurchaseUnitEntry && product?.purchaseUnit != null) ? product!.purchaseUnit! : baseUnitLabel;
    // What actually lands in stock for this line — shown as a hint so the
    // cashier can see the conversion before saving, not just discover it
    // afterward on the stock report.
    final stockQtyPreview = _stockQtyPreview(item);

    return Card(
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() {
              expanded ? _expandedItems.remove(index) : _expandedItems.add(index);
            }),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                item.productName ?? item.productId,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (mrpChanged) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.amber.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'New MRP',
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.orange),
                                ),
                              ),
                            ],
                          ],
                        ),
                        Text(
                          item.isPurchaseUnitEntry
                              ? '${formatQty(item.quantity)} $qtyUnitLabel × ₹${item.purchasePrice.toStringAsFixed(2)} '
                                  '(= ${formatQty(stockQtyPreview)} $baseUnitLabel)'
                              : '${formatQty(item.quantity)} $qtyUnitLabel × ₹${item.purchasePrice.toStringAsFixed(2)}',
                          style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
                        ),
                      ],
                    ),
                  ),
                  Text('₹${lineTotal.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () => _removeItem(index),
                  ),
                  Icon(expanded ? Icons.expand_less : Icons.expand_more, color: Theme.of(context).hintColor),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                children: [
                  const Divider(),
                  if (purchaseUnitEligible) ...[
                    DropdownButtonFormField<bool>(
                      key: ValueKey('buyunit_${item.id}'),
                      initialValue: item.isPurchaseUnitEntry,
                      decoration: const InputDecoration(labelText: 'Buying in'),
                      items: [
                        DropdownMenuItem(value: false, child: Text('$baseUnitLabel (each)')),
                        DropdownMenuItem(
                          value: true,
                          child: Text('${product.purchaseUnit} (${formatQty(product.unitsPerPurchaseUnit)} $baseUnitLabel each)'),
                        ),
                      ],
                      onChanged: (val) => _updateItem(
                        index,
                        item.copyWith(
                          isPurchaseUnitEntry: val ?? false,
                          purchaseUnitFactor: product.unitsPerPurchaseUnit,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          key: ValueKey('qty_${item.id}'),
                          initialValue: formatQty(item.quantity),
                          decoration: InputDecoration(
                            labelText: 'Qty ($qtyUnitLabel)',
                            helperText: item.isPurchaseUnitEntry ? '= ${formatQty(stockQtyPreview)} $baseUnitLabel to stock' : null,
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onChanged: (v) {
                            final qty = double.tryParse(v) ?? 1;
                            // If a total amount for this qty was entered, keep
                            // the per-unit purchase price in sync as qty
                            // changes, so the cashier never has to redo the
                            // division by hand.
                            final recalculatedPrice =
                                (item.dozAmt > 0 && qty > 0) ? item.dozAmt / qty : item.purchasePrice;
                            _updateItem(index, item.copyWith(quantity: qty, purchasePrice: recalculatedPrice));
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          key: ValueKey('free_${item.id}'),
                          initialValue: item.freeQuantity.toString(),
                          decoration: const InputDecoration(labelText: 'Free'),
                          keyboardType: TextInputType.number,
                          onChanged: (v) => _updateItem(index, item.copyWith(freeQuantity: int.tryParse(v) ?? 0)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          key: ValueKey('dozamt_${item.id}'),
                          initialValue: item.dozAmt == 0 ? '' : item.dozAmt.toString(),
                          decoration: const InputDecoration(
                            labelText: 'Total Amount',
                            helperText: 'Total invoice amt for this qty',
                            helperMaxLines: 2,
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (v) {
                            final dozAmt = double.tryParse(v) ?? 0;
                            // Auto-fill Purchase price from the total the
                            // supplier billed for this box/dozen, instead of
                            // making the cashier divide it out manually.
                            final qty = item.quantity;
                            final calculatedPrice = (dozAmt > 0 && qty > 0) ? dozAmt / qty : item.purchasePrice;
                            _updateItem(index, item.copyWith(dozAmt: dozAmt, purchasePrice: calculatedPrice));
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          key: ValueKey('pp_${item.id}'),
                          initialValue: item.purchasePrice.toString(),
                          decoration: const InputDecoration(labelText: 'Purchase price'),
                          keyboardType: TextInputType.number,
                          onChanged: (v) => _updateItem(index, item.copyWith(purchasePrice: double.tryParse(v) ?? 0)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          key: ValueKey('mrp_${item.id}'),
                          initialValue: item.mrp.toString(),
                          decoration: const InputDecoration(labelText: 'MRP'),
                          keyboardType: TextInputType.number,
                          onChanged: (v) => _updateItem(index, item.copyWith(mrp: double.tryParse(v) ?? 0)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          key: ValueKey('sp_${item.id}'),
                          initialValue: item.salesPrice.toString(),
                          decoration: const InputDecoration(labelText: 'Sales price'),
                          keyboardType: TextInputType.number,
                          onChanged: (v) => _updateItem(index, item.copyWith(salesPrice: double.tryParse(v) ?? 0)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          key: ValueKey('tax_${item.id}'),
                          initialValue: item.taxPercent.toString(),
                          decoration: const InputDecoration(labelText: 'Tax %'),
                          keyboardType: TextInputType.number,
                          onChanged: (v) => _updateItem(index, item.copyWith(taxPercent: double.tryParse(v) ?? 0)),
                        ),
                      ),
                    ],
                  ),
                  if (mrpChanged)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, size: 14, color: Colors.orange),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Master MRP is ₹${originalMrp.toStringAsFixed(2)} — saving at ₹${item.mrp.toStringAsFixed(2)} '
                              'creates a separate priced item, so the cashier is prompted to pick the right one at billing.',
                              style: const TextStyle(fontSize: 11, color: Colors.orange),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          key: ValueKey('disc_${item.id}'),
                          initialValue: item.discount.toString(),
                          decoration: const InputDecoration(labelText: 'Discount'),
                          keyboardType: TextInputType.number,
                          onChanged: (v) => _updateItem(index, item.copyWith(discount: double.tryParse(v) ?? 0)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          key: ValueKey('batch_${item.id}'),
                          initialValue: item.batchNo ?? '',
                          decoration: const InputDecoration(labelText: 'Batch no'),
                          onChanged: (v) => _updateItem(index, item.copyWith(batchNo: v.isEmpty ? null : v)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          key: ValueKey('exp_${item.id}'),
                          initialValue: item.expiryDate != null
                              ? DateTime.fromMillisecondsSinceEpoch(item.expiryDate! * 1000).toLocal().toString().split(' ')[0]
                              : '',
                          decoration: const InputDecoration(labelText: 'Expiry date'),
                          onChanged: (v) {
                            try {
                              final date = DateTime.parse(v);
                              _updateItem(index, item.copyWith(expiryDate: date.millisecondsSinceEpoch ~/ 1000));
                            } catch (_) {}
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          key: ValueKey('pack_date_${item.id}'),
                          initialValue: item.packingDate != null
                              ? DateTime.fromMillisecondsSinceEpoch(item.packingDate! * 1000).toLocal().toString().split(' ')[0]
                              : '',
                          decoration: const InputDecoration(labelText: 'Packing date'),
                          onChanged: (v) {
                            try {
                              final date = DateTime.parse(v);
                              _updateItem(index, item.copyWith(packingDate: date.millisecondsSinceEpoch ~/ 1000));
                            } catch (_) {}
                          },
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: CheckboxListTile(
                          value: item.isRepack,
                          onChanged: (val) => _updateItem(index, item.copyWith(isRepack: val ?? false)),
                          title: const Text('Repack'),
                          controlAffinity: ListTileControlAffinity.leading,
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                  if (item.isRepack)
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            key: ValueKey('bulkq_${item.id}'),
                            initialValue: formatQty(item.bulkQuantity),
                            decoration: const InputDecoration(labelText: 'Bulk qty'),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            onChanged: (v) => _updateItem(index, item.copyWith(bulkQuantity: double.tryParse(v) ?? 0)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            key: ValueKey('packsize_${item.id}'),
                            initialValue: item.packSize.toString(),
                            decoration: const InputDecoration(labelText: 'Pack size'),
                            keyboardType: TextInputType.number,
                            onChanged: (v) {
                              final val = double.tryParse(v) ?? 0;
                              final updated = item.copyWith(packSize: val);
                              if (val > 0 && item.bulkQuantity > 0) {
                                final count = (item.bulkQuantity / val).round();
                                _updateItem(index, updated.copyWith(packCount: count, quantity: count.toDouble()));
                              } else {
                                _updateItem(index, updated);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            key: ValueKey('packunit_${item.id}'),
                            initialValue: item.packUnit ?? '',
                            decoration: const InputDecoration(labelText: 'Pack unit'),
                            onChanged: (v) => _updateItem(index, item.copyWith(packUnit: v.isEmpty ? null : v)),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // --- Step 3: Totals ---

  Widget _buildTotalsStep() {
    final diff = double.tryParse(_differenceController.text) ?? 0;
    final matches = diff == 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionCard(
          title: 'Bill reconciliation',
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _billTotalController,
                    decoration: const InputDecoration(labelText: 'Supplier invoice total'),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _totalController,
                    decoration: const InputDecoration(labelText: 'Calculated total'),
                    keyboardType: TextInputType.number,
                    readOnly: true,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: matches ? Colors.green.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: matches ? Colors.green : Colors.red),
              ),
              child: Row(
                children: [
                  Icon(matches ? Icons.check_circle : Icons.warning_amber, color: matches ? Colors.green : Colors.red, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    matches ? 'Totals match' : 'Difference of ₹${diff.abs().toStringAsFixed(2)}',
                    style: TextStyle(color: matches ? Colors.green : Colors.red, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _sectionCard(
          title: 'Deductions & tax',
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _accountPercentController,
                    decoration: const InputDecoration(labelText: 'Account %'),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _accountController,
                    decoration: const InputDecoration(labelText: 'Account amount'),
                    keyboardType: TextInputType.number,
                    readOnly: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _taxRateController,
                    decoration: const InputDecoration(labelText: 'Tax rate %'),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _taxController,
                    decoration: const InputDecoration(labelText: 'Tax amount'),
                    keyboardType: TextInputType.number,
                    readOnly: true,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Net amount', style: TextStyle(color: Theme.of(context).hintColor)),
                const SizedBox(height: 4),
                Text(
                  '₹${(double.tryParse(_netAmountController.text) ?? 0).toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // --- Shared ---

  Widget _sectionCard({required String title, required List<Widget> children}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}