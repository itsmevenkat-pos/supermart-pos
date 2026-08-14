import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/sales_return_model.dart';
import '../models/sales_return_item_model.dart';
import '../repositories/sales_return_repository.dart';

/// Recent returns for the returns list screen — plain FutureProvider (not
/// riverpod codegen) to match repository-provider-only features like
/// `saleRepositoryProvider`, avoiding a build_runner step for this feature.
final recentReturnsProvider = FutureProvider<List<SalesReturn>>((ref) async {
  final repo = ref.watch(salesReturnRepositoryProvider);
  return repo.getRecent();
});

final returnItemsProvider = FutureProvider.family<List<SalesReturnItem>, String>((ref, returnId) async {
  final repo = ref.watch(salesReturnRepositoryProvider);
  return repo.getItemsByReturn(returnId);
});

class SalesReturnNotifier {
  SalesReturnNotifier(this._ref);

  final Ref _ref;

  Future<SalesReturn> createReturn({
    required SalesReturn header,
    required List<SalesReturnItem> items,
  }) async {
    final repo = _ref.read(salesReturnRepositoryProvider);
    final saved = await repo.insertReturn(header: header, items: items);
    _ref.invalidate(recentReturnsProvider);
    return saved;
  }
}

final salesReturnNotifierProvider = Provider<SalesReturnNotifier>((ref) {
  return SalesReturnNotifier(ref);
});
