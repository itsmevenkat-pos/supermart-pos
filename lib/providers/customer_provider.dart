import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../models/customer_model.dart';
import '../repositories/customer_repository.dart';

part 'customer_provider.g.dart';

@riverpod
class CustomerNotifier extends _$CustomerNotifier {
  final CustomerRepository _repo = CustomerRepository();

  @override
  Future<List<Customer>> build() async {
    return await _repo.getAll();
  }

  Future<void> addCustomer(Customer customer) async {
    await _repo.insert(customer);
    ref.invalidateSelf();
  }

  Future<void> updateCustomer(Customer customer) async {
    await _repo.update(customer);
    ref.invalidateSelf();
  }

  Future<List<Customer>> search(String query) async {
    state = const AsyncValue.loading();
    final results = await _repo.search(query);
    state = AsyncValue.data(results);
    return results;
  }

  Future<Customer?> getById(String id) async {
    return await _repo.getById(id);
  }
}
