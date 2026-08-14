import 'package:flutter/material.dart';
import '../../../models/product_model.dart';
import '../../../repositories/product_repository.dart';

/// Search-and-select dialog for picking an existing product — shared by the
/// "link as a variant of" (parent product) and "add kit component" flows on
/// the product form, since both are the same interaction.
class ProductPickerDialog extends StatefulWidget {
  /// A product that can't pick itself (e.g. as its own parent/component).
  final String? excludeProductId;
  /// Excludes kit products from the results — a kit can't contain another
  /// kit as a component, to avoid recursive kits.
  final bool excludeKits;

  const ProductPickerDialog({super.key, this.excludeProductId, this.excludeKits = false});

  @override
  State<ProductPickerDialog> createState() => _ProductPickerDialogState();
}

class _ProductPickerDialogState extends State<ProductPickerDialog> {
  final _searchController = TextEditingController();
  List<Product> _results = [];
  bool _loading = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _results = []);
      return;
    }
    setState(() => _loading = true);
    var found = await ProductRepository().search(query.trim());
    found = found.where((p) => p.id != widget.excludeProductId).toList();
    if (widget.excludeKits) {
      found = found.where((p) => !p.isKit).toList();
    }
    if (mounted) setState(() {
      _results = found;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SizedBox(
        width: 420,
        height: 480,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Select Product', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search by name or barcode',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: _search,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _results.isEmpty
                      ? Center(
                          child: Text(
                            _searchController.text.trim().isEmpty ? 'Start typing to search' : 'No products found',
                            style: const TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _results.length,
                          itemBuilder: (_, index) {
                            final product = _results[index];
                            return ListTile(
                              leading: const Icon(Icons.inventory_2_outlined),
                              title: Text(product.displayName ?? product.name),
                              subtitle: Text('Barcode: ${product.barcode}  •  ₹${product.retailPrice.toStringAsFixed(2)}'),
                              onTap: () => Navigator.pop(context, product),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
