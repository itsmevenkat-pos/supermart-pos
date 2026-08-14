import '../core/database/database_helper.dart';
import '../models/sale_model.dart';
import '../models/purchase_model.dart';
import '../repositories/product_repository.dart';
import '../repositories/category_repository.dart';

class ReportService {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final ProductRepository _productRepo = ProductRepository();
  final CategoryRepository _categoryRepo = CategoryRepository();

  /// Refund amount, refunded tax, refunded ex-tax taxable value, and
  /// refunded COGS for returns *processed* within the period — keyed off
  /// `sales_returns.created_at`, not the original sale's date, so a return
  /// nets against the period it actually affects the till/stock in, rather
  /// than retroactively rewriting a prior period's already-reported numbers.
  /// Used to net returns out of sales/tax/COGS below instead of reporting
  /// gross figures that no longer match what's actually owed to the
  /// business (see FEATURE_STATUS.md — Returns/Refunds).
  Future<Map<String, double>> _getReturnsTotals({DateTime? from, DateTime? to}) async {
    final db = await _dbHelper.database;
    final fromTime = from != null ? from.millisecondsSinceEpoch ~/ 1000 : 0;
    final toTime = to != null ? to.millisecondsSinceEpoch ~/ 1000 : DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final refundResult = await db.rawQuery('''
      SELECT COALESCE(SUM(refund_amount), 0) AS totalRefund
      FROM sales_returns
      WHERE created_at >= ? AND created_at <= ?
    ''', [fromTime, toTime]);

    // COGS is reversed for every returned line regardless of the restock
    // toggle: the original sale's revenue is being refunded either way, so
    // it should no longer count as "sold" for margin purposes. Whether the
    // goods physically went back on the shelf only affects stock_quantity,
    // handled separately by SalesReturnRepository at the time of the return.
    final itemsResult = await db.rawQuery('''
      SELECT
        COALESCE(SUM(sri.tax_amount), 0) AS totalTax,
        COALESCE(SUM(sri.total_price - sri.tax_amount), 0) AS totalTaxable,
        COALESCE(SUM(sri.cost_price * sri.quantity), 0) AS totalCogs
      FROM sales_return_items sri
      INNER JOIN sales_returns sr ON sr.id = sri.return_id
      WHERE sr.created_at >= ? AND sr.created_at <= ?
    ''', [fromTime, toTime]);

    return {
      'totalRefund': (refundResult.first['totalRefund'] as num?)?.toDouble() ?? 0,
      'totalTax': (itemsResult.first['totalTax'] as num?)?.toDouble() ?? 0,
      'totalTaxable': (itemsResult.first['totalTaxable'] as num?)?.toDouble() ?? 0,
      'totalCogs': (itemsResult.first['totalCogs'] as num?)?.toDouble() ?? 0,
    };
  }

  Future<Map<String, dynamic>> getSalesReport({
    DateTime? from,
    DateTime? to,
  }) async {
    final db = await _dbHelper.database;
    final fromTime = from != null ? from.millisecondsSinceEpoch ~/ 1000 : 0;
    final toTime = to != null ? to.millisecondsSinceEpoch ~/ 1000 : DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final result = await db.query(
      'sales',
      where: 'created_at >= ? AND created_at <= ? AND status = ?',
      whereArgs: [fromTime, toTime, 'completed'],
    );

    double grossSales = 0;
    double grossTax = 0;
    double totalDiscount = 0;
    int totalBills = 0;

    for (final row in result) {
      final sale = Sale.fromJson(row);
      grossSales += sale.netAmount;
      grossTax += sale.taxTotal;
      totalDiscount += sale.discountTotal;
      totalBills++;
    }

    final returns = await _getReturnsTotals(from: from, to: to);
    final totalReturns = returns['totalRefund']!;
    final totalSales = grossSales - totalReturns;
    final totalTax = (grossTax - returns['totalTax']!).clamp(0, double.infinity).toDouble();

    return {
      // Net of returns processed in this period — was gross before, which
      // over-reported actual sales once a return existed.
      'totalSales': totalSales,
      'grossSales': grossSales,
      'totalReturns': totalReturns,
      'totalTax': totalTax,
      'totalDiscount': totalDiscount,
      'totalBills': totalBills,
      'averageBill': totalBills > 0 ? totalSales / totalBills : 0,
    };
  }

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

  Future<List<Map<String, dynamic>>> getStockReport() async {
    final products = await _productRepo.getAll(activeOnly: true);
    final categories = await _categoryRepo.getAll();
    final categoryNames = {for (final c in categories) c.id: c.name};
    final result = <Map<String, dynamic>>[];

    for (final product in products) {
      final stockValue = product.costPrice * product.stockQuantity;
      final sellValue = product.retailPrice * product.stockQuantity;
      final profitPotential = sellValue - stockValue;

      result.add({
        'id': product.id,
        'barcode': product.barcode,
        'name': product.name,
        'category': categoryNames[product.categoryId] ?? 'Uncategorized',
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

  /// Total sales for each of the last [days] days (oldest first, today last)
  /// — used for the dashboard's sales trend sparkline.
  Future<List<Map<String, dynamic>>> getDailySalesTrend({int days = 7}) async {
    final today = DateTime.now();
    final result = <Map<String, dynamic>>[];

    for (int i = days - 1; i >= 0; i--) {
      final day = DateTime(today.year, today.month, today.day).subtract(Duration(days: i));
      final dayEnd = day.add(const Duration(days: 1)).subtract(const Duration(seconds: 1));
      final report = await getSalesReport(from: day, to: dayEnd);
      result.add({
        'date': day,
        'totalSales': report['totalSales'] ?? 0,
      });
    }

    return result;
  }

  Future<Map<String, dynamic>> getGstReport({
    DateTime? from,
    DateTime? to,
  }) async {
    final db = await _dbHelper.database;
    final fromTime = from != null ? from.millisecondsSinceEpoch ~/ 1000 : 0;
    final toTime = to != null ? to.millisecondsSinceEpoch ~/ 1000 : DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final result = await db.query(
      'sales',
      where: 'created_at >= ? AND created_at <= ? AND status = ?',
      whereArgs: [fromTime, toTime, 'completed'],
    );

    double grossTax = 0;
    double grossTaxable = 0;

    for (final row in result) {
      final sale = Sale.fromJson(row);
      grossTax += sale.taxTotal;
      // Was using gross subtotal (pre-discount) as the taxable base, which
      // overstates taxable turnover whenever a discount was applied — GST
      // is only due on what the customer actually paid before tax, not the
      // sticker price.
      grossTaxable += (sale.subtotal - sale.discountTotal).clamp(0, double.infinity);
    }

    // A sales return functions as a credit note — it reduces output tax
    // liability, so returns processed in this period are netted out here
    // too, not just from the Sales tab.
    final returns = await _getReturnsTotals(from: from, to: to);
    final totalTax = (grossTax - returns['totalTax']!).clamp(0, double.infinity).toDouble();
    final totalTaxable = (grossTaxable - returns['totalTaxable']!).clamp(0, double.infinity).toDouble();

    return {
      'totalTax': totalTax,
      'totalTaxable': totalTaxable,
      'taxRate': totalTaxable > 0 ? (totalTax / totalTaxable) * 100 : 0,
    };
  }

  /// Total cost of goods actually sold in the period, from the cost price
  /// snapshotted onto each sale line at sale time (`sale_items.cost_price`)
  /// — not the live `products.cost_price`, so this stays correct even after
  /// a product's cost later changes, and not `purchases`, which measures
  /// buying activity rather than what was sold. Net of returns processed in
  /// this period — see [_getReturnsTotals].
  Future<double> getCostOfGoodsSold({DateTime? from, DateTime? to}) async {
    final db = await _dbHelper.database;
    final fromTime = from != null ? from.millisecondsSinceEpoch ~/ 1000 : 0;
    final toTime = to != null ? to.millisecondsSinceEpoch ~/ 1000 : DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final result = await db.rawQuery('''
      SELECT COALESCE(SUM(si.cost_price * si.quantity), 0) AS totalCogs
      FROM sale_items si
      INNER JOIN sales s ON s.id = si.sale_id
      WHERE s.created_at >= ? AND s.created_at <= ? AND s.status = ?
    ''', [fromTime, toTime, 'completed']);

    final grossCogs = (result.first['totalCogs'] as num?)?.toDouble() ?? 0;
    final returns = await _getReturnsTotals(from: from, to: to);
    return (grossCogs - returns['totalCogs']!).clamp(0, double.infinity).toDouble();
  }

  /// Payment-mode breakdown for the period — how much was actually
  /// collected by each method (cash/upi/card/credit/...), net of refunds
  /// issued back through that same method. A bill split across methods
  /// (e.g. part cash, part UPI) contributes to both. This is what a
  /// day-close needs and nothing else previously computed: getSalesReport
  /// only totals the bill amount, not how it was paid.
  Future<Map<String, double>> getPaymentModeSummary({DateTime? from, DateTime? to}) async {
    final db = await _dbHelper.database;
    final fromTime = from != null ? from.millisecondsSinceEpoch ~/ 1000 : 0;
    final toTime = to != null ? to.millisecondsSinceEpoch ~/ 1000 : DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final saleRows = await db.query(
      'sales',
      columns: ['payment_methods'],
      where: 'created_at >= ? AND created_at <= ? AND status = ?',
      whereArgs: [fromTime, toTime, 'completed'],
    );

    final totals = <String, double>{};
    for (final row in saleRows) {
      final sale = Sale.fromJson(row);
      final methods = sale.paymentMethods;
      if (methods == null) continue;
      for (final entry in methods.entries) {
        totals[entry.key] = (totals[entry.key] ?? 0) + entry.value;
      }
    }

    // A refund hands cash/UPI/etc. back out the door through whichever
    // method was used — net it out of that same method's total so this
    // reflects what's actually in the till/account, not gross sales.
    final refundRows = await db.query(
      'sales_returns',
      columns: ['refund_method', 'refund_amount'],
      where: 'created_at >= ? AND created_at <= ?',
      whereArgs: [fromTime, toTime],
    );
    for (final row in refundRows) {
      final method = (row['refund_method'] as String?)?.toLowerCase() ?? 'cash';
      final amount = (row['refund_amount'] as num?)?.toDouble() ?? 0;
      totals[method] = (totals[method] ?? 0) - amount;
    }

    return totals;
  }

  /// Real profit for the period: revenue excluding tax, minus what the sold
  /// goods actually cost (COGS) — not `totalSales - totalPurchases`, which
  /// conflates buying activity with selling activity and is meaningless over
  /// a single day (a day with sales but no purchases isn't 100% profit).
  Future<Map<String, dynamic>> getProfitLoss({
    DateTime? from,
    DateTime? to,
  }) async {
    final sales = await getSalesReport(from: from, to: to);
    final purchases = await getPurchaseReport(from: from, to: to);
    final totalCogs = await getCostOfGoodsSold(from: from, to: to);

    final totalSales = (sales['totalSales'] as num?)?.toDouble() ?? 0;
    final totalTax = (sales['totalTax'] as num?)?.toDouble() ?? 0;
    final totalPurchases = (purchases['totalPurchases'] as num?)?.toDouble() ?? 0;
    final revenueExTax = totalSales - totalTax;
    final profit = revenueExTax - totalCogs;

    return {
      'totalSales': totalSales,
      'totalReturns': (sales['totalReturns'] as num?)?.toDouble() ?? 0,
      'totalPurchases': totalPurchases,
      'totalCogs': totalCogs,
      'grossProfit': profit,
      'profitMargin': revenueExTax > 0 ? (profit / revenueExTax) * 100 : 0,
    };
  }
}