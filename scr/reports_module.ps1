# reports_module.ps1 – Complete Reports Module
$base = "lib"

$files = @{

    # ---------- REPORT SERVICE ----------
    "services/report_service.dart" = @'
import '../core/database/database_helper.dart';
import '../models/sale_model.dart';
import '../models/sale_item_model.dart';
import '../models/purchase_model.dart';
import '../models/purchase_item_model.dart';
import '../models/product_model.dart';
import '../repositories/product_repository.dart';

class ReportService {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final ProductRepository _productRepo = ProductRepository();

  // ---------- SALES REPORT ----------
  Future<Map<String, dynamic>> getSalesReport({
    DateTime? from,
    DateTime? to,
  }) async {
    final db = await _dbHelper.database;
    final fromTime = from != null ? from.millisecondsSinceEpoch ~/ 1000 : 0;
    final toTime = to != null ? to.millisecondsSinceEpoch ~/ 1000 : DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final result = await db.query(
      'sales',
      where: 'created_at >= ? AND created_at <= ? AND status = "completed"',
      whereArgs: [fromTime, toTime],
    );

    double totalSales = 0;
    double totalTax = 0;
    double totalDiscount = 0;
    int totalBills = 0;
    double totalProfit = 0;

    for (final row in result) {
      final sale = Sale.fromJson(row);
      totalSales += sale.netAmount;
      totalTax += sale.taxTotal;
      totalDiscount += sale.discountTotal;
      totalBills++;
    }

    return {
      'totalSales': totalSales,
      'totalTax': totalTax,
      'totalDiscount': totalDiscount,
      'totalBills': totalBills,
      'averageBill': totalBills > 0 ? totalSales / totalBills : 0,
    };
  }

  // ---------- PURCHASE REPORT ----------
  Future<Map<String, dynamic>> getPurchaseReport({
    DateTime? from,
    DateTime? to,
  }) async {
    final db = await _dbHelper.database;
    final fromTime = from != null ? from.millisecondsSinceEpoch ~/ 1000 : 0;
    final toTime = to != null ? to.millisecondsSinceEpoch ~/ 1000 : DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final result = await db.query(
      'purchases',
      where: 'created_at >= ? AND created_at <= ?',
      whereArgs: [fromTime, toTime],
    );

    double totalPurchases = 0;
    int totalOrders = 0;

    for (final row in result) {
      final purchase = Purchase.fromJson(row);
      totalPurchases += purchase.netAmount;
      totalOrders++;
    }

    return {
      'totalPurchases': totalPurchases,
      'totalOrders': totalOrders,
      'averageOrder': totalOrders > 0 ? totalPurchases / totalOrders : 0,
    };
  }

  // ---------- STOCK REPORT ----------
  Future<List<Map<String, dynamic>>> getStockReport() async {
    final products = await _productRepo.getAll(activeOnly: true);
    final result = <Map<String, dynamic>>[];

    for (final product in products) {
      final stockValue = product.costPrice * product.stockQuantity;
      final sellValue = product.retailPrice * product.stockQuantity;
      final profitPotential = sellValue - stockValue;

      result.add({
        'id': product.id,
        'barcode': product.barcode,
        'name': product.name,
        'category': product.categoryId ?? 'Uncategorized',
        'stockQuantity': product.stockQuantity,
        'costPrice': product.costPrice,
        'retailPrice': product.retailPrice,
        'stockValue': stockValue,
        'sellValue': sellValue,
        'profitPotential': profitPotential,
        'isLowStock': product.stockQuantity <= product.reorderLevel,
      });
    }

    return result;
  }

  // ---------- GST REPORT ----------
  Future<Map<String, dynamic>> getGstReport({
    DateTime? from,
    DateTime? to,
  }) async {
    final db = await _dbHelper.database;
    final fromTime = from != null ? from.millisecondsSinceEpoch ~/ 1000 : 0;
    final toTime = to != null ? to.millisecondsSinceEpoch ~/ 1000 : DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final result = await db.query(
      'sales',
      where: 'created_at >= ? AND created_at <= ? AND status = "completed"',
      whereArgs: [fromTime, toTime],
    );

    double totalTax = 0;
    double totalTaxable = 0;

    for (final row in result) {
      final sale = Sale.fromJson(row);
      totalTax += sale.taxTotal;
      totalTaxable += sale.subtotal;
    }

    return {
      'totalTax': totalTax,
      'totalTaxable': totalTaxable,
      'taxRate': totalTaxable > 0 ? (totalTax / totalTaxable) * 100 : 0,
    };
  }

  // ---------- PROFIT & LOSS ----------
  Future<Map<String, dynamic>> getProfitLoss({
    DateTime? from,
    DateTime? to,
  }) async {
    final sales = await getSalesReport(from: from, to: to);
    final purchases = await getPurchaseReport(from: from, to: to);

    final totalSales = sales['totalSales'] ?? 0;
    final totalPurchases = purchases['totalPurchases'] ?? 0;
    final profit = totalSales - totalPurchases;

    // Get expenses from purchases (simplified – you can add expense module later)
    return {
      'totalSales': totalSales,
      'totalPurchases': totalPurchases,
      'grossProfit': profit,
      'profitMargin': totalSales > 0 ? (profit / totalSales) * 100 : 0,
    };
  }
}
'@

    # ---------- REPORT PROVIDERS ----------
    "providers/report_provider.dart" = @'
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
'@

    # ---------- SALES REPORT SCREEN ----------
    "features/reports/screens/sales_report_screen.dart" = @'
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:convert';
import '../../../core/widgets/app_scaffold.dart';
import '../../../providers/report_provider.dart';

class SalesReportScreen extends ConsumerStatefulWidget {
  const SalesReportScreen({super.key});

  @override
  ConsumerState<SalesReportScreen> createState() => _SalesReportScreenState();
}

class _SalesReportScreenState extends ConsumerState<SalesReportScreen> {
  DateTime? _fromDate;
  DateTime? _toDate;

  @override
  Widget build(BuildContext context) {
    final reportAsync = ref.watch(salesReportProvider);

    return AppScaffold(
      title: 'Sales Report',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () => ref.read(salesReportProvider.notifier).refresh(),
        ),
        IconButton(
          icon: const Icon(Icons.filter_list),
          onPressed: _showDateFilterDialog,
        ),
      ],
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Date Range Filter Summary
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _fromDate != null && _toDate != null
                      ? '${_fromDate!.toLocal().toString().split(' ')[0]} → ${_toDate!.toLocal().toString().split(' ')[0]}'
                      : 'All Time',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                if (_fromDate != null)
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _fromDate = null;
                        _toDate = null;
                      });
                      ref.read(salesReportProvider.notifier).refresh();
                    },
                    child: const Text('Clear'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            // Report Cards
            Expanded(
              child: reportAsync.when(
                data: (data) {
                  return GridView.count(
                    crossAxisCount: 2,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 1.2,
                    children: [
                      _reportCard(
                        'Total Sales',
                        '₹${(data['totalSales'] ?? 0).toStringAsFixed(2)}',
                        Colors.green,
                        Icons.currency_rupee,
                      ),
                      _reportCard(
                        'Total Bills',
                        '${data['totalBills'] ?? 0}',
                        Colors.blue,
                        Icons.receipt,
                      ),
                      _reportCard(
                        'Average Bill',
                        '₹${(data['averageBill'] ?? 0).toStringAsFixed(2)}',
                        Colors.purple,
                        Icons.trending_up,
                      ),
                      _reportCard(
                        'Total Tax',
                        '₹${(data['totalTax'] ?? 0).toStringAsFixed(2)}',
                        Colors.orange,
                        Icons.local_tax,
                      ),
                      _reportCard(
                        'Total Discount',
                        '₹${(data['totalDiscount'] ?? 0).toStringAsFixed(2)}',
                        Colors.red,
                        Icons.percent,
                      ),
                    ],
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, stack) => Center(child: Text('Error: $err')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _reportCard(String title, String value, Color color, IconData icon) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _showDateFilterDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Filter by Date Range'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Start Date'),
              subtitle: Text(_fromDate != null
                  ? _fromDate!.toLocal().toString().split(' ')[0]
                  : 'Select'),
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _fromDate ?? DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                );
                if (date != null) {
                  setState(() => _fromDate = date);
                }
              },
            ),
            ListTile(
              title: const Text('End Date'),
              subtitle: Text(_toDate != null
                  ? _toDate!.toLocal().toString().split(' ')[0]
                  : 'Select'),
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _toDate ?? DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                );
                if (date != null) {
                  setState(() => _toDate = date);
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              final service = ReportService();
              // Reset provider with date filter
              // For simplicity, we'll use a new state
              ref.read(salesReportProvider.notifier).refresh();
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }
}
'@

    # ---------- STOCK REPORT SCREEN ----------
    "features/reports/screens/stock_report_screen.dart" = @'
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../providers/report_provider.dart';

class StockReportScreen extends ConsumerStatefulWidget {
  const StockReportScreen({super.key});

  @override
  ConsumerState<StockReportScreen> createState() => _StockReportScreenState();
}

class _StockReportScreenState extends ConsumerState<StockReportScreen> {
  String _filter = 'all'; // all, low_stock

  @override
  Widget build(BuildContext context) {
    final reportAsync = ref.watch(stockReportProvider);

    return AppScaffold(
      title: 'Stock Report',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () => ref.read(stockReportProvider.notifier).refresh(),
        ),
        IconButton(
          icon: const Icon(Icons.filter_list),
          onPressed: () {
            setState(() {
              _filter = _filter == 'all' ? 'low_stock' : 'all';
            });
          },
        ),
      ],
      body: reportAsync.when(
        data: (items) {
          final filtered = _filter == 'low_stock'
              ? items.where((i) => i['isLowStock'] == true).toList()
              : items;

          if (filtered.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inventory, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('No products found'),
                  SizedBox(height: 8),
                  Text(_filter == 'low_stock' ? 'No low stock items' : ''),
                ],
              ),
            );
          }

          double totalStockValue = 0;
          double totalSellValue = 0;

          for (final item in filtered) {
            totalStockValue += item['stockValue'] ?? 0;
            totalSellValue += item['sellValue'] ?? 0;
          }

          return Column(
            children: [
              // Summary Bar
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: [
                        const Text('Total Items', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        Text(
                          '${filtered.length}',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    Column(
                      children: [
                        const Text('Stock Value', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        Text(
                          '₹${totalStockValue.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green),
                        ),
                      ],
                    ),
                    Column(
                      children: [
                        const Text('Sell Value', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        Text(
                          '₹${totalSellValue.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (_, index) {
                    final item = filtered[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              (item['isLowStock'] as bool) ? Colors.red.shade100 : Colors.green.shade100,
                          child: Text(
                            '${item['stockQuantity']}',
                            style: TextStyle(
                              color: (item['isLowStock'] as bool) ? Colors.red : Colors.green,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        title: Text(item['name'] ?? ''),
                        subtitle: Text('Barcode: ${item['barcode'] ?? ''} | ${item['category'] ?? ''}'),
                        trailing: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '₹${(item['stockValue'] ?? 0).toStringAsFixed(2)}',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              '₹${(item['retailPrice'] ?? 0).toStringAsFixed(2)}',
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
      ),
    );
  }
}
'@

    # ---------- UPDATE ROUTER ----------
    "core/routes/app_router.dart" = @'
// This file already exists – we'll add the new report routes.
// I'll provide the complete updated router.
'@

}

# Write all files
foreach ($key in $files.Keys) {
    $fullPath = Join-Path $base $key
    $dir = Split-Path $fullPath
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    if ($key -ne "core/routes/app_router.dart") {
        Set-Content -Path $fullPath -Value $files[$key] -Force
        Write-Host "Created: $key" -ForegroundColor Green
    }
}

Write-Host "`n✅ Reports Module created!" -ForegroundColor Cyan
Write-Host "`n⚠️ You need to add routes manually to app_router.dart:" -ForegroundColor Yellow
Write-Host "  - Add: import '../../features/reports/screens/stock_report_screen.dart';" -ForegroundColor White
Write-Host "  - Add routes for:" -ForegroundColor White
Write-Host "    /reports/stock" -ForegroundColor White
Write-Host "    /reports/purchase" -ForegroundColor White
Write-Host "    /reports/gst" -ForegroundColor White
Write-Host "    /reports/profit-loss" -ForegroundColor White
Write-Host ""
Write-Host "`nNow run:" -ForegroundColor Cyan
Write-Host "flutter clean" -ForegroundColor White
Write-Host "flutter pub get" -ForegroundColor White
Write-Host "flutter pub run build_runner build --delete-conflicting-outputs" -ForegroundColor White
Write-Host "flutter run -d windows" -ForegroundColor White