import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/product_provider.dart';
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
              final categoryFiltered = _selectedCategory == 'All'
                  ? products
                  : products.where((p) => p.categoryId == _selectedCategory).toList();

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
                  color: _stockColor.withValues(alpha: 0.2),
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