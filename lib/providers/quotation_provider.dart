import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../models/quotation_model.dart';
import '../models/quotation_item_model.dart';
import '../repositories/quotation_repository.dart';

part 'quotation_provider.g.dart';

@riverpod
class QuotationNotifier extends _$QuotationNotifier {
  final QuotationRepository _repo = QuotationRepository();

  @override
  Future<List<Quotation>> build() async {
    return await _repo.getAll();
  }

  Future<void> addQuotation(Quotation quotation, {List<QuotationItem> items = const []}) async {
    await _repo.insert(quotation);
    if (items.isNotEmpty) {
      await _repo.insertItems(quotation.id, items);
    }
    ref.invalidateSelf();
  }

  Future<List<QuotationItem>> getItems(String quotationId) async {
    return await _repo.getItems(quotationId);
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
