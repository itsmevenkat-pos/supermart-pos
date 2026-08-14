import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../models/category_model.dart';
import '../../../models/product_model.dart';
import '../../../models/promotion_model.dart';
import '../../../repositories/category_repository.dart';
import '../../../repositories/product_repository.dart';
import '../../../repositories/promotion_repository.dart';

enum _Scope { product, category }

class PromotionFormScreen extends ConsumerStatefulWidget {
  final Promotion? promotion;

  const PromotionFormScreen({super.key, this.promotion});

  @override
  ConsumerState<PromotionFormScreen> createState() => _PromotionFormScreenState();
}

class _PromotionFormScreenState extends ConsumerState<PromotionFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _minQuantityController;
  late final TextEditingController _discountValueController;
  late final TextEditingController _productSearchController;
  late final TextEditingController _freeProductSearchController;

  late PromotionType _type;
  late _Scope _scope;
  late bool _isActive;
  DateTime? _startDate;
  DateTime? _endDate;

  List<Category> _categories = [];
  String? _selectedCategoryId;

  Product? _selectedProduct;
  List<Product> _productResults = [];

  Product? _selectedFreeProduct;
  List<Product> _freeProductResults = [];

  bool _isSaving = false;

  bool get _isEditing => widget.promotion != null;

  @override
  void initState() {
    super.initState();
    final p = widget.promotion;
    _nameController = TextEditingController(text: p?.name ?? '');
    _minQuantityController = TextEditingController(text: (p?.minQuantity ?? 1).toString());
    _discountValueController = TextEditingController(text: p?.discountValue?.toStringAsFixed(2) ?? '');
    _productSearchController = TextEditingController();
    _freeProductSearchController = TextEditingController();
    _type = p?.type ?? PromotionType.percentage;
    _scope = p?.categoryId != null ? _Scope.category : _Scope.product;
    _selectedCategoryId = p?.categoryId;
    _isActive = p?.isActive ?? true;
    _startDate = p?.startDate != null ? DateTime.fromMillisecondsSinceEpoch(p!.startDate! * 1000) : null;
    _endDate = p?.endDate != null ? DateTime.fromMillisecondsSinceEpoch(p!.endDate! * 1000) : null;

    CategoryRepository().getAll().then((cats) {
      if (mounted) setState(() => _categories = cats);
    });

    if (p?.productId != null) {
      ProductRepository().getById(p!.productId!).then((product) {
        if (mounted && product != null) {
          setState(() {
            _selectedProduct = product;
            _productSearchController.text = product.displayName ?? product.name;
          });
        }
      });
    }
    if (p?.freeProductId != null) {
      ProductRepository().getById(p!.freeProductId!).then((product) {
        if (mounted && product != null) {
          setState(() {
            _selectedFreeProduct = product;
            _freeProductSearchController.text = product.displayName ?? product.name;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _minQuantityController.dispose();
    _discountValueController.dispose();
    _productSearchController.dispose();
    _freeProductSearchController.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = (isStart ? _startDate : _endDate) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
      } else {
        _endDate = picked;
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_scope == _Scope.product && _selectedProduct == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick a product for this promotion'), backgroundColor: Colors.red),
      );
      return;
    }
    if (_scope == _Scope.category && _selectedCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick a category for this promotion'), backgroundColor: Colors.red),
      );
      return;
    }
    if (_type == PromotionType.free_item && _selectedFreeProduct == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick which product is given free'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final name = _nameController.text.trim();
      final minQuantity = int.tryParse(_minQuantityController.text.trim()) ?? 1;
      final discountValue = double.tryParse(_discountValueController.text.trim());
      final startEpoch = _startDate != null ? _startDate!.millisecondsSinceEpoch ~/ 1000 : null;
      final endEpoch = _endDate != null ? _endDate!.millisecondsSinceEpoch ~/ 1000 : null;

      final repo = ref.read(promotionRepositoryProvider);

      if (_isEditing) {
        final updated = widget.promotion!.copyWith(
          name: name,
          type: _type,
          productId: _scope == _Scope.product ? _selectedProduct!.id : null,
          categoryId: _scope == _Scope.category ? _selectedCategoryId : null,
          minQuantity: minQuantity,
          discountValue: discountValue,
          freeProductId: _type == PromotionType.free_item ? _selectedFreeProduct!.id : null,
          startDate: startEpoch,
          endDate: endEpoch,
          isActive: _isActive,
        );
        await repo.update(updated);
      } else {
        final promo = Promotion.create(
          name: name,
          type: _type,
          productId: _scope == _Scope.product ? _selectedProduct!.id : null,
          categoryId: _scope == _Scope.category ? _selectedCategoryId : null,
          minQuantity: minQuantity,
          discountValue: discountValue,
          freeProductId: _type == PromotionType.free_item ? _selectedFreeProduct!.id : null,
          startDate: startEpoch,
          endDate: endEpoch,
        );
        await repo.insert(promo);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isEditing ? 'Promotion updated' : 'Promotion created'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving promotion: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _searchProduct(String query, {required bool isFree}) async {
    if (query.trim().isEmpty) {
      setState(() {
        if (isFree) {
          _freeProductResults = [];
        } else {
          _productResults = [];
        }
      });
      return;
    }
    final results = await ProductRepository().search(query.trim());
    if (!mounted) return;
    setState(() {
      if (isFree) {
        _freeProductResults = results;
      } else {
        _productResults = results;
      }
    });
  }

  Widget _buildProductPicker({
    required String label,
    required TextEditingController controller,
    required List<Product> results,
    required Product? selected,
    required bool isFree,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: controller,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.search),
            suffixIcon: selected != null ? const Icon(Icons.check_circle, color: Colors.green) : null,
          ),
          onChanged: (value) {
            setState(() {
              if (isFree) {
                _selectedFreeProduct = null;
              } else {
                _selectedProduct = null;
              }
            });
            _searchProduct(value, isFree: isFree);
          },
        ),
        if (results.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxHeight: 180),
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300)),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: results.length,
              itemBuilder: (_, index) {
                final product = results[index];
                return ListTile(
                  dense: true,
                  title: Text(product.displayName ?? product.name),
                  subtitle: Text('${product.barcode} · ₹${product.retailPrice.toStringAsFixed(2)}'),
                  onTap: () {
                    setState(() {
                      if (isFree) {
                        _selectedFreeProduct = product;
                        _freeProductResults = [];
                      } else {
                        _selectedProduct = product;
                        _productResults = [];
                      }
                      controller.text = product.displayName ?? product.name;
                    });
                  },
                );
              },
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: _isEditing ? 'Edit Promotion' : 'New Promotion',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Promotion Name *',
                    hintText: 'e.g. Diwali Snacks Offer',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) =>
                      (value == null || value.trim().isEmpty) ? 'Promotion name is required' : null,
                ),
                const SizedBox(height: 16),
                const Text('Applies to', style: TextStyle(fontWeight: FontWeight.bold)),
                RadioGroup<_Scope>(
                  groupValue: _scope,
                  onChanged: (value) => setState(() => _scope = value ?? _Scope.product),
                  child: Row(
                    children: [
                      Expanded(
                        child: RadioListTile<_Scope>(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('One product'),
                          value: _Scope.product,
                        ),
                      ),
                      Expanded(
                        child: RadioListTile<_Scope>(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('A category'),
                          value: _Scope.category,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_scope == _Scope.product)
                  _buildProductPicker(
                    label: 'Product *',
                    controller: _productSearchController,
                    results: _productResults,
                    selected: _selectedProduct,
                    isFree: false,
                  )
                else
                  DropdownButtonFormField<String>(
                    initialValue: _selectedCategoryId,
                    decoration: const InputDecoration(labelText: 'Category *', border: OutlineInputBorder()),
                    items: _categories
                        .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
                        .toList(),
                    onChanged: (value) => setState(() => _selectedCategoryId = value),
                  ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _minQuantityController,
                  decoration: const InputDecoration(
                    labelText: 'Minimum Quantity *',
                    helperText: 'Total qty of the scoped product/category needed in the cart to trigger this',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    final n = int.tryParse(value?.trim() ?? '');
                    if (n == null || n < 1) return 'Enter a whole number, at least 1';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<PromotionType>(
                  initialValue: _type,
                  decoration: const InputDecoration(labelText: 'Reward Type *', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: PromotionType.percentage, child: Text('Percentage off')),
                    DropdownMenuItem(value: PromotionType.fixed, child: Text('Flat ₹ off')),
                    DropdownMenuItem(value: PromotionType.free_item, child: Text('Free item')),
                  ],
                  onChanged: (value) => setState(() => _type = value ?? PromotionType.percentage),
                ),
                const SizedBox(height: 16),
                if (_type == PromotionType.free_item)
                  _buildProductPicker(
                    label: 'Free Product *',
                    controller: _freeProductSearchController,
                    results: _freeProductResults,
                    selected: _selectedFreeProduct,
                    isFree: true,
                  )
                else
                  TextFormField(
                    controller: _discountValueController,
                    decoration: InputDecoration(
                      labelText: _type == PromotionType.percentage ? 'Discount %' : 'Discount Amount (₹)',
                      border: const OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    validator: (value) {
                      final n = double.tryParse(value?.trim() ?? '');
                      if (n == null || n <= 0) return 'Enter a value greater than 0';
                      if (_type == PromotionType.percentage && n > 100) return 'Percentage can\'t exceed 100';
                      return null;
                    },
                  ),
                const SizedBox(height: 16),
                const Text('Active Dates (optional — leave blank for always-on)', style: TextStyle(fontWeight: FontWeight.bold)),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _pickDate(isStart: true),
                        child: Text(_startDate == null ? 'Start date' : _startDate!.toString().split(' ')[0]),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (_startDate != null)
                      IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() => _startDate = null)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _pickDate(isStart: false),
                        child: Text(_endDate == null ? 'End date' : _endDate!.toString().split(' ')[0]),
                      ),
                    ),
                    if (_endDate != null)
                      IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() => _endDate = null)),
                  ],
                ),
                if (_isEditing) ...[
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Active'),
                    subtitle: const Text('Inactive promotions never auto-apply at billing'),
                    value: _isActive,
                    onChanged: (value) => setState(() => _isActive = value),
                  ),
                ],
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _isSaving ? null : _save,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.save),
                  label: Text(_isEditing ? 'Update Promotion' : 'Save Promotion'),
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
