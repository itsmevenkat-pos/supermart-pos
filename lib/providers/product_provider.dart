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
    ref.invalidateSelf(); // ✅ Forces rebuild of the provider
  }

  Future<void> updateProduct(Product product) async {
    await _repo.update(product);
    ref.invalidateSelf();
  }

  /// Flips a product active/inactive without touching any other field —
  /// the quick toggle on the product list, as an alternative to opening the
  /// full edit form just to hide a discontinued/duplicate item from billing.
  Future<void> setActive(Product product, bool isActive) async {
    await _repo.update(product.copyWith(isActive: isActive));
    ref.invalidateSelf();
  }

  Future<List<Product>> fetchByBarcode(String barcode, {bool activeOnly = false}) async {
    return await _repo.getByBarcode(barcode, activeOnly: activeOnly);
  }

  /// Read-only search — does NOT touch `state`. This used to overwrite the
  /// shared product-list state with search results, which meant every
  /// keystroke in the billing search box silently replaced what the
  /// product grid was showing (since ProductGrid watches this same
  /// provider for its full list). Callers that want the results just use
  /// the return value directly, same as fetchByBarcode already did.
  Future<List<Product>> search(String query, {bool activeOnly = false}) async {
    return await _repo.search(query, activeOnly: activeOnly);
  }

  Future<Product?> getProduct(String id) async {
    return await _repo.getById(id);
  }
}