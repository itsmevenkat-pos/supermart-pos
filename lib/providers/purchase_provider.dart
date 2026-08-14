import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../models/purchase_model.dart';
import '../models/purchase_item_model.dart';
import '../repositories/purchase_repository.dart';

part 'purchase_provider.g.dart';

@riverpod
class PurchaseNotifier extends _$PurchaseNotifier {
  final PurchaseRepository _repo = PurchaseRepository();

  @override
  Future<List<Purchase>> build() async {
    return await _repo.getAll();
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
  }

  Future<Purchase?> getById(String id) async {
    return await _repo.getById(id);
  }

  Future<List<PurchaseItem>> getItems(String purchaseId) async {
    return await _repo.getItemsByPurchase(purchaseId);
  }

  Future<void> createPurchase(Purchase purchase, List<PurchaseItem> items) async {
    await _repo.insertWithItems(purchase, items);
    ref.invalidateSelf();
  }

  Future<void> updatePurchase(Purchase purchase, List<PurchaseItem> items) async {
    await _repo.updateWithItems(purchase, items);
    ref.invalidateSelf();
  }

  Future<void> deletePurchase(String id) async {
    await _repo.delete(id);
    ref.invalidateSelf();
  }

  Future<Purchase?> getByGrn(String grnNo) async {
    return await _repo.getByGrn(grnNo);
  }
}
