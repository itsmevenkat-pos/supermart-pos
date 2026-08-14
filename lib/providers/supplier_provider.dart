import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../models/supplier_model.dart';
import '../repositories/supplier_repository.dart';

part 'supplier_provider.g.dart';

@riverpod
class SupplierNotifier extends _$SupplierNotifier {
  final SupplierRepository _repo = SupplierRepository();

  @override
  Future<List<Supplier>> build() async {
    return await _repo.getAll();
  }

  Future<void> addSupplier(Supplier supplier) async {
    await _repo.insert(supplier);
    ref.invalidateSelf();
  }

  Future<void> updateSupplier(Supplier supplier) async {
    await _repo.update(supplier);
    ref.invalidateSelf();
  }

  Future<List<Supplier>> search(String query) async {
    state = const AsyncValue.loading();
    final results = await _repo.search(query);
    state = AsyncValue.data(results);
    return results;
  }

  Future<Supplier?> getById(String id) async {
    return await _repo.getById(id);
  }
}
