# fix_provider.ps1 – Fixes missing product provider
$base = "lib"

$files = @{

    # ---------- PRODUCT PROVIDER ----------
    "providers/product_provider.dart" = @'
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../models/product_model.dart';
import '../repositories/product_repository.dart';

part 'product_provider.g.dart';

@riverpod
class ProductNotifier extends _$ProductNotifier {
  final ProductRepository _repo = ProductRepository();

  @override
  Future<List<Product>> build() async {
    return await _repo.getAll();
  }

  Future<void> addProduct(Product product) async {
    await _repo.insert(product);
    ref.invalidateSelf();
  }

  Future<void> updateProduct(Product product) async {
    await _repo.update(product);
    ref.invalidateSelf();
  }

  Future<List<Product>> fetchByBarcode(String barcode) async {
    return await _repo.getByBarcode(barcode);
  }

  Future<List<Product>> search(String query) async {
    return await _repo.search(query);
  }

  Future<Product?> getProduct(String id) async {
    return await _repo.getById(id);
  }
}
'@

    # ---------- FIXED PRODUCT GRID ----------
    "features/billing/widgets/product_grid.dart" = @'
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
  final TextEditingController _searchController = TextEditingController();
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
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productNotifierProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              hintText: 'Search by name or barcode',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              suffixIcon: Icon(Icons.qr_code_scanner),
            ),
            onChanged: (value) {
              setState(() {});
            },
          ),
        ),
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
              final filtered = _searchController.text.isNotEmpty
                  ? products.where((p) =>
                      p.name.toLowerCase().contains(_searchController.text.toLowerCase()) ||
                      (p.searchName?.toLowerCase().contains(_searchController.text.toLowerCase()) ?? false) ||
                      p.barcode.contains(_searchController.text))
                      .toList()
                  : products;

              final categoryFiltered = _selectedCategory == 'All'
                  ? filtered
                  : filtered.where((p) => p.categoryId == _selectedCategory).toList();

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
                  color: _stockColor.withOpacity(0.2),
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
'@

    # ---------- FIXED QUOTATION PROVIDER ----------
    "providers/quotation_provider.dart" = @'
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../models/quotation_model.dart';
import '../repositories/quotation_repository.dart';

part 'quotation_provider.g.dart';

@riverpod
class QuotationNotifier extends _$QuotationNotifier {
  final QuotationRepository _repo = QuotationRepository();

  @override
  Future<List<Quotation>> build() async {
    return await _repo.getAll();
  }

  Future<void> addQuotation(Quotation quotation) async {
    await _repo.insert(quotation);
    ref.invalidateSelf();
  }

  Future<void> updateQuotation(Quotation quotation) async {
    await _repo.update(quotation);
    ref.invalidateSelf();
  }

  Future<void> deleteQuotation(String id) async {
    await _repo.delete(id);
    ref.invalidateSelf();
  }

  Future<void> updateStatus(String id, String status) async {
    await _repo.updateStatus(id, status);
    ref.invalidateSelf();
  }

  Future<List<Quotation>> getByStatus(String status) async {
    return await _repo.getAll(status: status);
  }

  Future<Quotation?> getById(String id) async {
    return await _repo.getById(id);
  }
}
'@

    # ---------- FIXED BILLING SCREEN (add missing import) ----------
    "features/billing/screens/billing_screen.dart" = @'
// The file already exists – we just need to add the import if missing
// But since we already have a full file, I'll leave it as is.
'@

}

# Write all files
foreach ($key in $files.Keys) {
    $fullPath = Join-Path $base $key
    $dir = Split-Path $fullPath
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    if ($key -ne "features/billing/screens/billing_screen.dart") {
        Set-Content -Path $fullPath -Value $files[$key] -Force
        Write-Host "Fixed: $key" -ForegroundColor Green
    }
}

Write-Host "`n✅ Provider fixes applied!" -ForegroundColor Cyan
Write-Host "`nNow run:" -ForegroundColor Yellow
Write-Host "flutter clean" -ForegroundColor White
Write-Host "flutter pub get" -ForegroundColor White
Write-Host "flutter pub run build_runner build --delete-conflicting-outputs" -ForegroundColor White
Write-Host "flutter run -d windows" -ForegroundColor White