import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../providers/product_provider.dart';
import '../../../repositories/product_repository.dart';
import '../../../models/product_model.dart';
import '../../../core/utils/quantity_utils.dart';
import 'product_form_screen.dart';

class ProductListScreen extends ConsumerStatefulWidget {
  const ProductListScreen({super.key});

  @override
  ConsumerState<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends ConsumerState<ProductListScreen> {
  final TextEditingController _searchController = TextEditingController();
  // Own local copy of search results — previously this screen relied on
  // ProductNotifier.search() overwriting the shared provider state, which
  // was the same bug that let billing search silently replace what the
  // billing screen's product grid showed. Now search results live here
  // instead, and productNotifierProvider stays the untouched full list.
  List<Product>? _searchResults;
  // Off by default: the normal list (productNotifierProvider) only shows
  // active items, matching what's sellable. Switching this on fetches
  // active+inactive directly from the repo so deactivated items can be
  // found again and re-activated — there'd otherwise be no way to see them.
  bool _showInactive = false;
  List<Product>? _allIncludingInactive;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadIncludingInactive() async {
    final products = await ProductRepository().getAll(activeOnly: false);
    if (mounted) setState(() => _allIncludingInactive = products);
  }

  Future<void> _toggleShowInactive() async {
    final next = !_showInactive;
    setState(() => _showInactive = next);
    if (next) await _loadIncludingInactive();
  }

  Future<void> _toggleActive(Product product) async {
    await ref.read(productNotifierProvider.notifier).setActive(product, !product.isActive);
    if (_showInactive) await _loadIncludingInactive();
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productNotifierProvider);

    return AppScaffold(
      title: 'Products',
      actions: [
        IconButton(
          icon: Icon(_showInactive ? Icons.visibility : Icons.visibility_off),
          tooltip: _showInactive ? 'Showing inactive items — tap to hide' : 'Show inactive items',
          onPressed: _toggleShowInactive,
        ),
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () {
            ref.invalidate(productNotifierProvider);
            if (_showInactive) _loadIncludingInactive();
          },
        ),
      ],
      floatingActionButton: FloatingActionButton(
        onPressed: () => _navigateToForm(),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Search by name or barcode',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) async {
                if (value.isNotEmpty) {
                  final results = await ref.read(productNotifierProvider.notifier).search(value);
                  if (mounted) setState(() => _searchResults = results);
                } else {
                  setState(() => _searchResults = null);
                }
              },
            ),
          ),
          if (_showInactive)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Showing active and inactive items',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            ),
          Expanded(
            child: _searchResults != null
                ? _buildList(_searchResults!)
                : _showInactive
                    ? (_allIncludingInactive == null
                        ? const Center(child: CircularProgressIndicator())
                        : _buildList(_allIncludingInactive!))
                    : productsAsync.when(
                        data: (products) => _buildList(products),
                        loading: () => const Center(child: CircularProgressIndicator()),
                        error: (err, stack) => Center(
                          child: Text(
                            'Error: $err',
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(List<Product> products) {
    if (products.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('No products found'),
            SizedBox(height: 8),
            Text('Tap + to add your first product'),
          ],
        ),
      );
    }
    return ListView.builder(
      itemCount: products.length,
      itemBuilder: (context, index) {
        final product = products[index];
        return Opacity(
          opacity: product.isActive ? 1.0 : 0.55,
          child: Card(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: ListTile(
              leading: product.imagePath != null
                  ? CircleAvatar(backgroundImage: FileImage(File(product.imagePath!)))
                  : CircleAvatar(
                      backgroundColor: product.stockQuantity > 0
                          ? Colors.green.shade100
                          : Colors.red.shade100,
                      child: Text(
                        formatQty(product.stockQuantity),
                        style: TextStyle(
                          color: product.stockQuantity > 0
                              ? Colors.green.shade800
                              : Colors.red.shade800,
                        ),
                      ),
                    ),
              title: Text(product.name),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Barcode: ${product.barcode} | MRP: ₹${product.mrp.toStringAsFixed(2)}'
                    '${product.isActive ? '' : '  •  INACTIVE'}',
                    style: product.isActive ? null : const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  if (product.isKit || product.isService || product.parentProductId != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Wrap(
                        spacing: 6,
                        children: [
                          if (product.isKit) _badge('Kit', Colors.purple),
                          if (product.isService) _badge('Service', Colors.blue),
                          if (product.parentProductId != null) _badge('Variant', Colors.teal),
                        ],
                      ),
                    ),
                ],
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '₹${product.retailPrice.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(
                      product.isActive ? Icons.toggle_on : Icons.toggle_off,
                      size: 28,
                      color: product.isActive ? Colors.green : Colors.grey,
                    ),
                    tooltip: product.isActive ? 'Mark inactive' : 'Mark active',
                    onPressed: () => _toggleActive(product),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit, size: 20),
                    onPressed: () => _navigateToForm(product),
                  ),
                ],
              ),
              onTap: () => _navigateToForm(product),
            ),
          ),
        );
      },
    );
  }

  Widget _badge(String label, MaterialColor color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.shade200),
      ),
      child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color.shade700)),
    );
  }

  void _navigateToForm([Product? product]) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProductFormScreen(initialProduct: product),
      ),
    ).then((result) {
      // If the form returned true (saved successfully), refresh the list.
      if (result == true) {
        ref.invalidate(productNotifierProvider);
      }
    });
  }
}