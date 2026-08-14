import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../services/report_service.dart';

part 'report_provider.g.dart';

@riverpod
class SalesReport extends _$SalesReport {
  final ReportService _service = ReportService();

  @override
  Future<Map<String, dynamic>> build() async {
    return await _service.getSalesReport();
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
  }
}

@riverpod
class PurchaseReport extends _$PurchaseReport {
  final ReportService _service = ReportService();

  @override
  Future<Map<String, dynamic>> build() async {
    return await _service.getPurchaseReport();
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
  }
}

@riverpod
class StockReport extends _$StockReport {
  final ReportService _service = ReportService();

  @override
  Future<List<Map<String, dynamic>>> build() async {
    return await _service.getStockReport();
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
  }
}

@riverpod
class GstReport extends _$GstReport {
  final ReportService _service = ReportService();

  @override
  Future<Map<String, dynamic>> build() async {
    return await _service.getGstReport();
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
  }
}

@riverpod
class ProfitLossReport extends _$ProfitLossReport {
  final ReportService _service = ReportService();

  @override
  Future<Map<String, dynamic>> build() async {
    return await _service.getProfitLoss();
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
  }
}

/// Plain (non-codegen) provider, unlike the others above — a payment-mode
/// day summary is meaningfully scoped to "today" by definition, so this
/// defaults its own from/to instead of taking none like the all-time
/// reports above.
final paymentModeSummaryProvider = FutureProvider.autoDispose<Map<String, double>>((ref) async {
  final now = DateTime.now();
  final startOfToday = DateTime(now.year, now.month, now.day);
  return ReportService().getPaymentModeSummary(from: startOfToday, to: now);
});
