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

  /// [approvedByUserId] is passed straight through to the repository, which
  /// owns the credit-limit rule — the screen supplies the approver it
  /// authenticated, and the repository decides whether one was needed.
  Future<void> addCustomer(Customer customer, {String? approvedByUserId}) async {
    await _repo.insert(customer, approvedByUserId: approvedByUserId);
    ref.invalidateSelf();
  }

  Future<void> updateCustomer(Customer customer, {String? approvedByUserId}) async {
    await _repo.update(customer, approvedByUserId: approvedByUserId);
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
