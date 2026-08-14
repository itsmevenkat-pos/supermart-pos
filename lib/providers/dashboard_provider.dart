import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_model.dart';
import '../models/sale_model.dart';
import '../repositories/customer_repository.dart';
import '../repositories/product_repository.dart';
import '../repositories/sale_repository.dart';
import '../services/report_service.dart';
import '../services/sales_summary_service.dart';
import 'auth_provider.dart';

/// Everything the dashboard's home screen needs, in one shot.
///
/// For a cashier only [todaySales]/[todayBillCount] are populated (their own
/// sales only) — the rest stay null so the UI knows to render the simplified
/// cashier home instead of the full manager/admin KPI dashboard.
class DashboardData {
  final double todaySales;
  final int todayBillCount;
  final double? todayProfit;
  final int? lowStockCount;
  final double? pendingDues;
  final List<Map<String, dynamic>>? last7Days;
  final List<Sale>? recentSales;

  const DashboardData({
    required this.todaySales,
    required this.todayBillCount,
    this.todayProfit,
    this.lowStockCount,
    this.pendingDues,
    this.last7Days,
    this.recentSales,
  });

  bool get isFullDashboard => last7Days != null;
}

final dashboardDataProvider = FutureProvider.autoDispose<DashboardData>((ref) async {
  final user = ref.watch(authProvider).user;
  if (user == null) {
    return const DashboardData(todaySales: 0, todayBillCount: 0);
  }

  final salesSummaryService = SalesSummaryService();
  final isManager = user.role == UserRole.manager || user.role == UserRole.admin;

  if (!isManager) {
    // Cashier home: just their own shift so far.
    final summary = await salesSummaryService.getTodaySummary(userId: user.id);
    return DashboardData(
      todaySales: (summary['totalSales'] as num?)?.toDouble() ?? 0,
      todayBillCount: (summary['totalCount'] as int?) ?? 0,
    );
  }

  // Manager/admin home: full KPI set.
  final reportService = ReportService();
  final productRepo = ProductRepository();
  final customerRepo = CustomerRepository();
  final saleRepo = SaleRepository();

  final today = DateTime.now();
  final startOfToday = DateTime(today.year, today.month, today.day);

  final summary = await salesSummaryService.getTodaySummary();
  final profitLoss = await reportService.getProfitLoss(from: startOfToday);
  final lowStockItems = await productRepo.getLowStock();
  final customers = await customerRepo.getAll();
  final trend = await reportService.getDailySalesTrend(days: 7);
  final recentSales = await saleRepo.getRecent(limit: 5);

  final lowStockCount = lowStockItems.length;
  final pendingDues = customers.fold<double>(
    0,
    (sum, c) => sum + c.outstandingBalance,
  );

  return DashboardData(
    todaySales: (summary['totalSales'] as num?)?.toDouble() ?? 0,
    todayBillCount: (summary['totalCount'] as int?) ?? 0,
    todayProfit: (profitLoss['grossProfit'] as num?)?.toDouble() ?? 0,
    lowStockCount: lowStockCount,
    pendingDues: pendingDues,
    last7Days: trend,
    recentSales: recentSales,
  );
});
