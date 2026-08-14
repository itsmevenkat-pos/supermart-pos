import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../models/sale_model.dart';
import '../services/billing_service.dart';

part 'sale_provider.g.dart';

@riverpod
class RecentSales extends _$RecentSales {
  final BillingService _service = BillingService();

  @override
  Future<List<Sale>> build() async {
    return await _service.getRecentSales(limit: 50);
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
  }
}
