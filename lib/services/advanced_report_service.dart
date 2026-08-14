import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../core/database/database_helper.dart';
import '../repositories/category_repository.dart';
import '../repositories/festival_repository.dart';
import '../repositories/product_repository.dart';

/// Backs the "All Reports" catalog (Transaction/Party/GST/Item-Stock/
/// Business/Tax reports) that mirrors a competitor POS's Reports menu.
///
/// Same access pattern as [ReportService]: no repository indirection for
/// the bulk of these — raw `db.query`/`db.rawQuery` against the sqflite
/// [Database] obtained via [DatabaseHelper]. [db] is an optional injection
/// seam for tests (mirrors `DataVerificationService.runAllChecks({Database?
/// db})`); production call sites never need to pass it.
///
/// Several report groups here are **deliberate approximations**, called out
/// on each method:
/// - GSTR1/2/3B/9 are not filing-ready statutory formats — this app has no
///   HSN-level GST return structure, so they're grouped by `products.tax_rate`
///   / `purchase_items.tax_percent` instead. The UI layer is responsible for
///   showing an "unofficial — verify before filing" disclaimer.
/// - Trial Balance / Balance Sheet are simplified summaries built from
///   ledger running balances and current stock value, not statutory-format
///   statements.
class AdvancedReportService {
  AdvancedReportService({Database? db}) : _db = db;

  final Database? _db;
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final ProductRepository _productRepo = ProductRepository();
  final CategoryRepository _categoryRepo = CategoryRepository();

  Future<Database> get _database async => _db ?? await _dbHelper.database;

  int _fromTime(DateTime? from) => from != null ? from.millisecondsSinceEpoch ~/ 1000 : 0;

  int _toTime(DateTime? to) =>
      to != null ? to.millisecondsSinceEpoch ~/ 1000 : DateTime.now().millisecondsSinceEpoch ~/ 1000;

  // ---------------------------------------------------------------------
  // Transactions
  // ---------------------------------------------------------------------

  /// Chronological list of sales + purchases in the range, each row tagged
  /// `type: 'sale'|'purchase'`.
  Future<List<Map<String, dynamic>>> getDayBook({DateTime? from, DateTime? to}) async {
    final db = await _database;
    final fromTime = _fromTime(from);
    final toTime = _toTime(to);

    final rows = await db.rawQuery('''
      SELECT 'sale' AS type, s.created_at AS date,
        COALESCE(s.invoice_display_no, CAST(s.invoice_no AS TEXT)) AS reference,
        COALESCE(c.name, 'Walk-in') AS party,
        s.net_amount AS amount
      FROM sales s
      LEFT JOIN customers c ON c.id = s.customer_id
      WHERE s.created_at >= ? AND s.created_at <= ? AND s.status = 'completed'
      UNION ALL
      SELECT 'purchase' AS type, p.created_at AS date,
        p.grn_no AS reference,
        COALESCE(sup.name, p.supplier_name, 'Unknown') AS party,
        p.net_amount AS amount
      FROM purchases p
      LEFT JOIN suppliers sup ON sup.id = p.supplier_id
      WHERE p.created_at >= ? AND p.created_at <= ?
      ORDER BY date ASC
    ''', [fromTime, toTime, fromTime, toTime]);

    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  /// Same union as [getDayBook] but with a running balance column
  /// (cumulative net_amount — sales positive, purchases negative — in
  /// chronological order).
  Future<List<Map<String, dynamic>>> getAllTransactions({DateTime? from, DateTime? to}) async {
    final rows = await getDayBook(from: from, to: to);
    double runningBalance = 0;
    final result = <Map<String, dynamic>>[];
    for (final row in rows) {
      final amount = (row['amount'] as num?)?.toDouble() ?? 0;
      runningBalance += row['type'] == 'purchase' ? -amount : amount;
      result.add({...row, 'runningBalance': runningBalance});
    }
    return result;
  }

  // ---------------------------------------------------------------------
  // Profit
  // ---------------------------------------------------------------------

  /// One row per completed sale: invoice no, date, customer name (or
  /// "Walk-in"), net sale amount (ex-tax), COGS, and profit.
  Future<List<Map<String, dynamic>>> getBillWiseProfit({DateTime? from, DateTime? to}) async {
    final db = await _database;
    final rows = await db.rawQuery('''
      SELECT s.id AS saleId,
        COALESCE(s.invoice_display_no, CAST(s.invoice_no AS TEXT)) AS invoiceNo,
        s.created_at AS date,
        COALESCE(c.name, 'Walk-in') AS customerName,
        (s.net_amount - s.tax_total) AS netSaleAmount,
        COALESCE(SUM(si.cost_price * si.quantity), 0) AS cogs
      FROM sales s
      LEFT JOIN customers c ON c.id = s.customer_id
      LEFT JOIN sale_items si ON si.sale_id = s.id
      WHERE s.created_at >= ? AND s.created_at <= ? AND s.status = 'completed'
      GROUP BY s.id
      ORDER BY s.created_at ASC
    ''', [_fromTime(from), _toTime(to)]);

    return rows.map((r) {
      final netSaleAmount = (r['netSaleAmount'] as num?)?.toDouble() ?? 0;
      final cogs = (r['cogs'] as num?)?.toDouble() ?? 0;
      return {
        ...Map<String, dynamic>.from(r),
        'profit': netSaleAmount - cogs,
      };
    }).toList();
  }

  /// Per cashier (`sales.user_id`): bill count, total net sales, and a
  /// cash/upi/card/credit breakdown. The breakdown is aggregated in Dart
  /// from each sale's `payment_methods` JSON column — same parsing approach
  /// as [getBankStatement] — since SQLite can't sum JSON object fields
  /// directly. Sales whose `user_id` has no matching (or no) `users` row
  /// are grouped together under 'Unknown' (LEFT JOIN).
  Future<List<Map<String, dynamic>>> getUserWiseSales({DateTime? from, DateTime? to}) async {
    final db = await _database;
    final fromTime = _fromTime(from);
    final toTime = _toTime(to);

    final rows = await db.rawQuery('''
      SELECT s.user_id AS userId, COALESCE(u.name, 'Unknown') AS userName,
        COUNT(*) AS billCount,
        COALESCE(SUM(s.net_amount), 0) AS totalSales
      FROM sales s
      LEFT JOIN users u ON u.id = s.user_id
      WHERE s.created_at >= ? AND s.created_at <= ? AND s.status = 'completed'
      GROUP BY s.user_id
    ''', [fromTime, toTime]);

    final saleRows = await db.query(
      'sales',
      columns: ['user_id', 'payment_methods'],
      where: 'created_at >= ? AND created_at <= ? AND status = ?',
      whereArgs: [fromTime, toTime, 'completed'],
    );

    final breakdownByUser = <Object?, Map<String, double>>{};
    for (final row in saleRows) {
      final raw = row['payment_methods'] as String?;
      if (raw == null || raw.isEmpty) continue;
      try {
        final methods = Map<String, dynamic>.from(jsonDecode(raw));
        final totals = breakdownByUser.putIfAbsent(
          row['user_id'],
          () => {'cash': 0, 'upi': 0, 'card': 0, 'credit': 0},
        );
        for (final entry in methods.entries) {
          if (!totals.containsKey(entry.key)) continue;
          totals[entry.key] = totals[entry.key]! + ((entry.value as num?)?.toDouble() ?? 0);
        }
      } catch (_) {
        // Malformed/legacy row — skip rather than crash the report.
      }
    }

    return rows.map((r) {
      final breakdown = breakdownByUser[r['userId']] ?? const {'cash': 0.0, 'upi': 0.0, 'card': 0.0, 'credit': 0.0};
      return {
        'userName': r['userName'],
        'billCount': r['billCount'],
        'totalSales': r['totalSales'],
        'cash': breakdown['cash'],
        'upi': breakdown['upi'],
        'card': breakdown['card'],
        'credit': breakdown['credit'],
      };
    }).toList();
  }

  /// Simplified trial balance: Cash Sales / Credit Sales (from sales
  /// totals), Accounts Receivable / Accounts Payable (latest ledger running
  /// balances summed across all customers/suppliers), and Stock Value
  /// (current cost_price * stock_quantity). This is NOT a statutory-format
  /// trial balance — the UI must show a "simplified" disclaimer.
  Future<List<Map<String, dynamic>>> getTrialBalance({DateTime? from, DateTime? to}) async {
    final db = await _database;
    final fromTime = _fromTime(from);
    final toTime = _toTime(to);

    final salesRows = await db.rawQuery('''
      SELECT
        COALESCE(SUM(CASE WHEN is_credit_sale = 0 THEN net_amount ELSE 0 END), 0) AS cashSales,
        COALESCE(SUM(CASE WHEN is_credit_sale = 1 THEN net_amount ELSE 0 END), 0) AS creditSales
      FROM sales
      WHERE created_at >= ? AND created_at <= ? AND status = 'completed'
    ''', [fromTime, toTime]);
    final cashSales = (salesRows.first['cashSales'] as num?)?.toDouble() ?? 0;
    final creditSales = (salesRows.first['creditSales'] as num?)?.toDouble() ?? 0;

    final receivables = await _totalReceivables(db);
    final payables = await _totalPayables(db);
    final stockValue = await _totalStockValue(db);

    return [
      {'account': 'Cash Sales', 'debit': 0.0, 'credit': cashSales},
      {'account': 'Credit Sales', 'debit': 0.0, 'credit': creditSales},
      {'account': 'Accounts Receivable', 'debit': receivables, 'credit': 0.0},
      {'account': 'Accounts Payable', 'debit': 0.0, 'credit': payables},
      {'account': 'Stock Value', 'debit': stockValue, 'credit': 0.0},
    ];
  }

  /// Simplified balance sheet: Assets = current stock value + total
  /// receivables; Liabilities = total payables. Not a statutory-format
  /// statement — the UI must show a "simplified" disclaimer.
  Future<List<Map<String, dynamic>>> getBalanceSheet({DateTime? from, DateTime? to}) async {
    final db = await _database;
    final stockValue = await _totalStockValue(db);
    final receivables = await _totalReceivables(db);
    final payables = await _totalPayables(db);

    return [
      {'category': 'Assets', 'item': 'Stock', 'amount': stockValue},
      {'category': 'Assets', 'item': 'Receivables', 'amount': receivables},
      {'category': 'Liabilities', 'item': 'Payables', 'amount': payables},
    ];
  }

  Future<double> _totalReceivables(Database db) async {
    final customerIds = await db.rawQuery(
      "SELECT id FROM customers WHERE is_deleted = 0",
    );
    double total = 0;
    for (final row in customerIds) {
      final result = await db.rawQuery(
        'SELECT balance FROM customer_ledger WHERE customer_id = ? ORDER BY created_at DESC LIMIT 1',
        [row['id']],
      );
      if (result.isNotEmpty) {
        total += (result.first['balance'] as num?)?.toDouble() ?? 0;
      }
    }
    return total;
  }

  Future<double> _totalPayables(Database db) async {
    final supplierIds = await db.rawQuery(
      "SELECT id FROM suppliers WHERE is_deleted = 0",
    );
    double total = 0;
    for (final row in supplierIds) {
      final result = await db.rawQuery(
        'SELECT balance FROM supplier_ledger WHERE supplier_id = ? ORDER BY created_at DESC LIMIT 1',
        [row['id']],
      );
      if (result.isNotEmpty) {
        total += (result.first['balance'] as num?)?.toDouble() ?? 0;
      }
    }
    return total;
  }

  Future<double> _totalStockValue(Database db) async {
    final result = await db.rawQuery('''
      SELECT COALESCE(SUM(cost_price * stock_quantity), 0) AS stockValue
      FROM products
      WHERE is_deleted = 0
    ''');
    return (result.first['stockValue'] as num?)?.toDouble() ?? 0;
  }

  // ---------------------------------------------------------------------
  // Party
  // ---------------------------------------------------------------------

  /// Per customer: total sales (ex-tax), total COGS, profit.
  Future<List<Map<String, dynamic>>> getPartyWiseProfitLoss({DateTime? from, DateTime? to}) async {
    final db = await _database;
    final fromTime = _fromTime(from);
    final toTime = _toTime(to);

    // Two separate aggregations (not one joined query) — joining sale_items
    // in to compute COGS while also summing sale-level net_amount in the
    // same GROUP BY would multiply-count net_amount once per line item.
    final salesRows = await db.rawQuery('''
      SELECT s.customer_id AS customerId, COALESCE(c.name, 'Walk-in') AS name,
        COALESCE(SUM(s.net_amount - s.tax_total), 0) AS totalSales
      FROM sales s
      LEFT JOIN customers c ON c.id = s.customer_id
      WHERE s.created_at >= ? AND s.created_at <= ? AND s.status = 'completed'
      GROUP BY s.customer_id
    ''', [fromTime, toTime]);

    final cogsRows = await db.rawQuery('''
      SELECT s.customer_id AS customerId,
        COALESCE(SUM(si.cost_price * si.quantity), 0) AS cogs
      FROM sales s
      JOIN sale_items si ON si.sale_id = s.id
      WHERE s.created_at >= ? AND s.created_at <= ? AND s.status = 'completed'
      GROUP BY s.customer_id
    ''', [fromTime, toTime]);

    final cogsByCustomer = <Object?, double>{
      for (final r in cogsRows) r['customerId']: (r['cogs'] as num?)?.toDouble() ?? 0,
    };

    return salesRows.map((r) {
      final totalSales = (r['totalSales'] as num?)?.toDouble() ?? 0;
      final cogs = cogsByCustomer[r['customerId']] ?? 0;
      return {
        'customerId': r['customerId'],
        'name': r['name'],
        'totalSales': totalSales,
        'totalCogs': cogs,
        'profit': totalSales - cogs,
      };
    }).toList();
  }

  /// Combined directory of all customers and suppliers: name, type
  /// ('customer'|'supplier'), phone, balance. Ignores [from]/[to] — this is
  /// a directory, not a transaction-range report.
  Future<List<Map<String, dynamic>>> getAllParties({DateTime? from, DateTime? to}) async {
    final db = await _database;

    final customers = await db.rawQuery('''
      SELECT name, phone, outstanding_balance AS balance
      FROM customers
      WHERE is_deleted = 0
    ''');

    final suppliers = await db.rawQuery('''
      SELECT s.name, s.phone,
        COALESCE(
          (SELECT balance FROM supplier_ledger sl WHERE sl.supplier_id = s.id ORDER BY sl.created_at DESC LIMIT 1),
          s.opening_balance
        ) AS balance
      FROM suppliers s
      WHERE s.is_deleted = 0
    ''');

    return [
      for (final c in customers)
        {'name': c['name'], 'type': 'customer', 'phone': c['phone'], 'balance': c['balance']},
      for (final s in suppliers)
        {'name': s['name'], 'type': 'supplier', 'phone': s['phone'], 'balance': s['balance']},
    ];
  }

  /// Per (customer, product) pair from completed sales: customer name,
  /// product name, quantity, amount.
  Future<List<Map<String, dynamic>>> getPartyReportByItem({DateTime? from, DateTime? to}) async {
    final db = await _database;
    final rows = await db.rawQuery('''
      SELECT COALESCE(c.name, 'Walk-in') AS customerName, pr.name AS productName,
        SUM(si.quantity) AS quantity, SUM(si.total_price) AS amount
      FROM sale_items si
      JOIN sales s ON s.id = si.sale_id
      JOIN products pr ON pr.id = si.product_id
      LEFT JOIN customers c ON c.id = s.customer_id
      WHERE s.created_at >= ? AND s.created_at <= ? AND s.status = 'completed'
      GROUP BY s.customer_id, si.product_id
      ORDER BY customerName ASC, productName ASC
    ''', [_fromTime(from), _toTime(to)]);
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  /// Per customer: total sales; per supplier: total purchases. One list
  /// with a `partyType` column ('customer'|'supplier').
  Future<List<Map<String, dynamic>>> getSalePurchaseByParty({DateTime? from, DateTime? to}) async {
    final db = await _database;
    final fromTime = _fromTime(from);
    final toTime = _toTime(to);

    final rows = await db.rawQuery('''
      SELECT 'customer' AS partyType, COALESCE(c.name, 'Walk-in') AS party,
        SUM(s.net_amount) AS amount
      FROM sales s
      LEFT JOIN customers c ON c.id = s.customer_id
      WHERE s.created_at >= ? AND s.created_at <= ? AND s.status = 'completed'
      GROUP BY s.customer_id
      UNION ALL
      SELECT 'supplier' AS partyType, COALESCE(sup.name, p.supplier_name, 'Unknown') AS party,
        SUM(p.net_amount) AS amount
      FROM purchases p
      LEFT JOIN suppliers sup ON sup.id = p.supplier_id
      WHERE p.created_at >= ? AND p.created_at <= ?
      GROUP BY p.supplier_id
    ''', [fromTime, toTime, fromTime, toTime]);

    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  /// Sales grouped by `customer.rating` (gold/silver/bronze/regular).
  /// Suppliers have no grouping field in this app, so all supplier
  /// purchases are returned as a single 'Ungrouped' row.
  Future<List<Map<String, dynamic>>> getSalePurchaseByPartyGroup({DateTime? from, DateTime? to}) async {
    final db = await _database;
    final fromTime = _fromTime(from);
    final toTime = _toTime(to);

    final salesRows = await db.rawQuery('''
      SELECT COALESCE(c.rating, 'regular') AS groupName, SUM(s.net_amount) AS amount
      FROM sales s
      LEFT JOIN customers c ON c.id = s.customer_id
      WHERE s.created_at >= ? AND s.created_at <= ? AND s.status = 'completed'
      GROUP BY groupName
    ''', [fromTime, toTime]);

    final purchaseRows = await db.rawQuery('''
      SELECT COALESCE(SUM(net_amount), 0) AS amount
      FROM purchases
      WHERE created_at >= ? AND created_at <= ?
    ''', [fromTime, toTime]);

    return [
      for (final r in salesRows)
        {'partyType': 'customer', 'groupName': r['groupName'], 'amount': r['amount']},
      {
        'partyType': 'supplier',
        'groupName': 'Ungrouped',
        'amount': (purchaseRows.first['amount'] as num?)?.toDouble() ?? 0,
      },
    ];
  }

  // ---------------------------------------------------------------------
  // GST — deliberate approximations. This app has no HSN-level GST return
  // structure, so GSTR1/2/3B/9 are grouped by tax rate instead of the real
  // statutory item/HSN breakdown. The UI must show an "unofficial — verify
  // before filing" disclaimer on all four.
  // ---------------------------------------------------------------------

  /// Outward supplies (sales) grouped by tax rate: rate, taxable value, tax
  /// amount, invoice count.
  Future<List<Map<String, dynamic>>> getGstr1({DateTime? from, DateTime? to}) async {
    final db = await _database;
    final rows = await db.rawQuery('''
      SELECT pr.tax_rate AS rate,
        COALESCE(SUM(si.total_price - si.tax_amount), 0) AS taxableValue,
        COALESCE(SUM(si.tax_amount), 0) AS taxAmount,
        COUNT(DISTINCT s.id) AS invoiceCount
      FROM sale_items si
      JOIN sales s ON s.id = si.sale_id
      JOIN products pr ON pr.id = si.product_id
      WHERE s.created_at >= ? AND s.created_at <= ? AND s.status = 'completed'
      GROUP BY pr.tax_rate
      ORDER BY pr.tax_rate ASC
    ''', [_fromTime(from), _toTime(to)]);
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  /// Inward supplies (purchases) grouped by `purchase_items.tax_percent`:
  /// rate, taxable value, tax amount, invoice count.
  Future<List<Map<String, dynamic>>> getGstr2({DateTime? from, DateTime? to}) async {
    final db = await _database;
    final rows = await db.rawQuery('''
      SELECT pi.tax_percent AS rate,
        COALESCE(SUM(pi.total - pi.tax_amount), 0) AS taxableValue,
        COALESCE(SUM(pi.tax_amount), 0) AS taxAmount,
        COUNT(DISTINCT p.id) AS invoiceCount
      FROM purchase_items pi
      JOIN purchases p ON p.id = pi.purchase_id
      WHERE p.created_at >= ? AND p.created_at <= ?
      GROUP BY pi.tax_percent
      ORDER BY pi.tax_percent ASC
    ''', [_fromTime(from), _toTime(to)]);
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  /// Single summary combining [getGstr1] (output tax liability) and
  /// [getGstr2] (input tax credit): net tax payable = output tax - input
  /// tax credit. Returned as a one-element list to keep a uniform return
  /// type across the service.
  Future<List<Map<String, dynamic>>> getGstr3b({DateTime? from, DateTime? to}) async {
    final gstr1 = await getGstr1(from: from, to: to);
    final gstr2 = await getGstr2(from: from, to: to);

    final outputTax = gstr1.fold<double>(0, (sum, r) => sum + ((r['taxAmount'] as num?)?.toDouble() ?? 0));
    final inputTaxCredit = gstr2.fold<double>(0, (sum, r) => sum + ((r['taxAmount'] as num?)?.toDouble() ?? 0));

    return [
      {
        'outputTax': outputTax,
        'inputTaxCredit': inputTaxCredit,
        'netTaxPayable': outputTax - inputTaxCredit,
      },
    ];
  }

  /// Annual version of [getGstr3b] — sums across the whole financial year
  /// (1 Apr – 31 Mar) containing [to] (or now if [to] is null), ignoring
  /// [from]. Same tax-rate-grouped approximation as GSTR1/2/3B.
  Future<List<Map<String, dynamic>>> getGstr9({DateTime? from, DateTime? to}) async {
    final anchor = to ?? DateTime.now();
    final startYear = anchor.month >= 4 ? anchor.year : anchor.year - 1;
    final fyStart = DateTime(startYear, 4, 1);
    final fyEnd = DateTime(startYear + 1, 3, 31, 23, 59, 59);
    return getGstr3b(from: fyStart, to: fyEnd);
  }

  /// Sales grouped by `products.hsn_code` — code (or 'Not set' if null),
  /// quantity, taxable value, tax amount.
  Future<List<Map<String, dynamic>>> getSaleSummaryByHsn({DateTime? from, DateTime? to}) async {
    final db = await _database;
    final rows = await db.rawQuery('''
      SELECT COALESCE(pr.hsn_code, 'Not set') AS code,
        SUM(si.quantity) AS quantity,
        COALESCE(SUM(si.total_price - si.tax_amount), 0) AS taxableValue,
        COALESCE(SUM(si.tax_amount), 0) AS taxAmount
      FROM sale_items si
      JOIN sales s ON s.id = si.sale_id
      JOIN products pr ON pr.id = si.product_id
      WHERE s.created_at >= ? AND s.created_at <= ? AND s.status = 'completed'
      GROUP BY code
      ORDER BY code ASC
    ''', [_fromTime(from), _toTime(to)]);
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  /// SAC (services) codes generally don't apply to a goods retailer — this
  /// app has no separate SAC field, so it reuses the HSN grouping as a
  /// stand-in. Same shape as [getSaleSummaryByHsn].
  Future<List<Map<String, dynamic>>> getSacReport({DateTime? from, DateTime? to}) {
    return getSaleSummaryByHsn(from: from, to: to);
  }

  // ---------------------------------------------------------------------
  // Item / Stock
  // ---------------------------------------------------------------------

  /// Variant of [getPartyReportByItem] re-ordered/relabeled product-first:
  /// product name, then customer name, quantity, amount.
  Future<List<Map<String, dynamic>>> getItemReportByParty({DateTime? from, DateTime? to}) async {
    final db = await _database;
    final rows = await db.rawQuery('''
      SELECT pr.name AS productName, COALESCE(c.name, 'Walk-in') AS customerName,
        SUM(si.quantity) AS quantity, SUM(si.total_price) AS amount
      FROM sale_items si
      JOIN sales s ON s.id = si.sale_id
      JOIN products pr ON pr.id = si.product_id
      LEFT JOIN customers c ON c.id = s.customer_id
      WHERE s.created_at >= ? AND s.created_at <= ? AND s.status = 'completed'
      GROUP BY si.product_id, s.customer_id
      ORDER BY productName ASC, customerName ASC
    ''', [_fromTime(from), _toTime(to)]);
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  /// Per product: quantity sold, revenue (ex-tax), COGS, profit.
  Future<List<Map<String, dynamic>>> getItemWiseProfitLoss({DateTime? from, DateTime? to}) async {
    final db = await _database;
    final rows = await db.rawQuery('''
      SELECT si.product_id AS productId, pr.name AS name,
        SUM(si.quantity) AS quantity,
        COALESCE(SUM(si.total_price - si.tax_amount), 0) AS revenue,
        COALESCE(SUM(si.cost_price * si.quantity), 0) AS cogs
      FROM sale_items si
      JOIN sales s ON s.id = si.sale_id
      JOIN products pr ON pr.id = si.product_id
      WHERE s.created_at >= ? AND s.created_at <= ? AND s.status = 'completed'
      GROUP BY si.product_id
      ORDER BY name ASC
    ''', [_fromTime(from), _toTime(to)]);

    return rows.map((r) {
      final revenue = (r['revenue'] as num?)?.toDouble() ?? 0;
      final cogs = (r['cogs'] as num?)?.toDouble() ?? 0;
      return {...Map<String, dynamic>.from(r), 'profit': revenue - cogs};
    }).toList();
  }

  /// Same as [getItemWiseProfitLoss] but grouped by `products.category_id`.
  Future<List<Map<String, dynamic>>> getItemCategoryWiseProfitLoss({DateTime? from, DateTime? to}) async {
    final db = await _database;
    final rows = await db.rawQuery('''
      SELECT pr.category_id AS categoryId, COALESCE(cat.name, 'Uncategorized') AS category,
        SUM(si.quantity) AS quantity,
        COALESCE(SUM(si.total_price - si.tax_amount), 0) AS revenue,
        COALESCE(SUM(si.cost_price * si.quantity), 0) AS cogs
      FROM sale_items si
      JOIN sales s ON s.id = si.sale_id
      JOIN products pr ON pr.id = si.product_id
      LEFT JOIN categories cat ON cat.id = pr.category_id
      WHERE s.created_at >= ? AND s.created_at <= ? AND s.status = 'completed'
      GROUP BY pr.category_id
      ORDER BY category ASC
    ''', [_fromTime(from), _toTime(to)]);

    return rows.map((r) {
      final revenue = (r['revenue'] as num?)?.toDouble() ?? 0;
      final cogs = (r['cogs'] as num?)?.toDouble() ?? 0;
      return {...Map<String, dynamic>.from(r), 'profit': revenue - cogs};
    }).toList();
  }

  /// Batch-level near-expiry/expired alert list from `product_batches`
  /// (joined to `products` for the name), soonest/most-overdue expiry
  /// first. Includes every batch with a non-null `expiry_date` at or before
  /// `now + [daysAhead]` days, tagged `status: 'Expired'` (already past) or
  /// `'Expiring Soon'` (within the window).
  ///
  /// **Deliberate approximation**: `product_batches.quantity_received` is
  /// the quantity originally purchased into that batch — this schema has no
  /// per-batch remaining-stock/FIFO consumption tracking, so there is no way
  /// to know how much of *that specific batch* is still unsold. Do not read
  /// `quantityReceived` as current remaining stock. `currentProductStock` is
  /// a deliberately separate figure — the product's current *total* stock
  /// across all batches (`products.stock_quantity`) — included only so the
  /// UI can show it for context alongside the batch row, not as a per-batch
  /// number. The UI should label it clearly (e.g. "Current Total Stock") to
  /// avoid implying otherwise. Use this report to flag which batches/expiry
  /// dates need physical shelf verification, not as an authoritative
  /// remaining-quantity source.
  Future<List<Map<String, dynamic>>> getExpiryAlerts({int daysAhead = 30}) async {
    final db = await _database;
    final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final cutoff = nowSeconds + daysAhead * 86400;

    final rows = await db.rawQuery('''
      SELECT pr.name AS productName,
        pb.batch_no AS batchNo,
        pb.expiry_date AS expiryDate,
        pb.quantity_received AS quantityReceived,
        pr.stock_quantity AS currentProductStock,
        CASE WHEN pb.expiry_date < ? THEN 'Expired' ELSE 'Expiring Soon' END AS status
      FROM product_batches pb
      JOIN products pr ON pr.id = pb.product_id
      WHERE pb.expiry_date IS NOT NULL AND pb.expiry_date <= ?
      ORDER BY pb.expiry_date ASC
    ''', [nowSeconds, cutoff]);

    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  /// Thin wrapper over [ProductRepository.getLowStock].
  Future<List<Map<String, dynamic>>> getLowStockSummary() async {
    final lowStock = await _productRepo.getLowStock();
    final categories = await _categoryRepo.getAll();
    final categoryNames = {for (final c in categories) c.id: c.name};

    return lowStock
        .map((p) => {
              'name': p.name,
              'barcode': p.barcode,
              'stockQuantity': p.stockQuantity,
              'reorderLevel': p.reorderLevel,
              'category': categoryNames[p.categoryId] ?? 'Uncategorized',
            })
        .toList();
  }

  /// Full `stock_ledger` rows in range joined to product name: date,
  /// product name, reference type, quantity change, batch/expiry context.
  Future<List<Map<String, dynamic>>> getStockDetail({DateTime? from, DateTime? to}) async {
    final db = await _database;
    final rows = await db.rawQuery('''
      SELECT sl.created_at AS date, pr.name AS productName,
        sl.reference_type AS referenceType, sl.quantity_change AS quantityChange,
        sl.batch_no AS batchNo, sl.expiry_date AS expiryDate
      FROM stock_ledger sl
      JOIN products pr ON pr.id = sl.product_id
      WHERE sl.created_at >= ? AND sl.created_at <= ?
      ORDER BY sl.created_at ASC
    ''', [_fromTime(from), _toTime(to)]);
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  /// Sales and purchases totals grouped by category, one list with a
  /// `type` column ('sale'|'purchase').
  Future<List<Map<String, dynamic>>> getSalePurchaseByItemCategory({DateTime? from, DateTime? to}) async {
    final db = await _database;
    final fromTime = _fromTime(from);
    final toTime = _toTime(to);

    final rows = await db.rawQuery('''
      SELECT 'sale' AS type, COALESCE(cat.name, 'Uncategorized') AS category,
        SUM(si.total_price) AS amount
      FROM sale_items si
      JOIN sales s ON s.id = si.sale_id
      JOIN products pr ON pr.id = si.product_id
      LEFT JOIN categories cat ON cat.id = pr.category_id
      WHERE s.created_at >= ? AND s.created_at <= ? AND s.status = 'completed'
      GROUP BY pr.category_id
      UNION ALL
      SELECT 'purchase' AS type, COALESCE(cat.name, 'Uncategorized') AS category,
        SUM(pi.total) AS amount
      FROM purchase_items pi
      JOIN purchases p ON p.id = pi.purchase_id
      JOIN products pr ON pr.id = pi.product_id
      LEFT JOIN categories cat ON cat.id = pr.category_id
      WHERE p.created_at >= ? AND p.created_at <= ?
      GROUP BY pr.category_id
    ''', [fromTime, toTime, fromTime, toTime]);

    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  /// Current stock value (cost_price * stock_quantity) grouped by category.
  Future<List<Map<String, dynamic>>> getStockSummaryByItemCategory() async {
    final db = await _database;
    final rows = await db.rawQuery('''
      SELECT COALESCE(cat.name, 'Uncategorized') AS category,
        COALESCE(SUM(pr.cost_price * pr.stock_quantity), 0) AS stockValue
      FROM products pr
      LEFT JOIN categories cat ON cat.id = pr.category_id
      WHERE pr.is_deleted = 0
      GROUP BY pr.category_id
      ORDER BY category ASC
    ''');
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  /// Per product: total discount given across sale_items in range, and
  /// count of times discounted.
  Future<List<Map<String, dynamic>>> getItemWiseDiscount({DateTime? from, DateTime? to}) async {
    final db = await _database;
    final rows = await db.rawQuery('''
      SELECT pr.name AS name,
        COALESCE(SUM(si.discount_amount), 0) AS totalDiscount,
        SUM(CASE WHEN si.discount_amount > 0 THEN 1 ELSE 0 END) AS discountCount
      FROM sale_items si
      JOIN sales s ON s.id = si.sale_id
      JOIN products pr ON pr.id = si.product_id
      WHERE s.created_at >= ? AND s.created_at <= ? AND s.status = 'completed'
      GROUP BY si.product_id
      ORDER BY totalDiscount DESC
    ''', [_fromTime(from), _toTime(to)]);
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  // ---------------------------------------------------------------------
  // Business / Tax
  // ---------------------------------------------------------------------

  /// Sales rows where `payment_methods` records a non-cash method (card/
  /// upi/etc, parsed the same way as `SaleRepository.getCashTotalBySession`)
  /// plus purchases with a non-zero `account` portion, listed chronologically
  /// with method and amount. Derived from recorded payment methods, not a
  /// reconciled bank feed — this app has no bank-transaction import.
  Future<List<Map<String, dynamic>>> getBankStatement({DateTime? from, DateTime? to}) async {
    final db = await _database;
    final fromTime = _fromTime(from);
    final toTime = _toTime(to);

    final result = <Map<String, dynamic>>[];

    final saleRows = await db.query(
      'sales',
      columns: ['created_at', 'payment_methods', 'customer_id', 'invoice_display_no', 'invoice_no'],
      where: 'created_at >= ? AND created_at <= ? AND status = ?',
      whereArgs: [fromTime, toTime, 'completed'],
    );
    for (final row in saleRows) {
      final raw = row['payment_methods'] as String?;
      if (raw == null || raw.isEmpty) continue;
      try {
        final methods = Map<String, dynamic>.from(jsonDecode(raw));
        for (final entry in methods.entries) {
          if (entry.key == 'cash') continue;
          final amount = (entry.value as num?)?.toDouble() ?? 0;
          if (amount <= 0) continue;
          result.add({
            'type': 'sale',
            'date': row['created_at'],
            'method': entry.key,
            'amount': amount,
            'reference': row['invoice_display_no'] ?? row['invoice_no']?.toString(),
          });
        }
      } catch (_) {
        // Malformed/legacy row — skip rather than crash the report.
      }
    }

    final purchaseRows = await db.query(
      'purchases',
      columns: ['created_at', 'account', 'grn_no'],
      where: 'created_at >= ? AND created_at <= ? AND account > 0',
      whereArgs: [fromTime, toTime],
    );
    for (final row in purchaseRows) {
      result.add({
        'type': 'purchase',
        'date': row['created_at'],
        'method': 'account',
        'amount': (row['account'] as num?)?.toDouble() ?? 0,
        'reference': row['grn_no'],
      });
    }

    result.sort((a, b) => (a['date'] as int).compareTo(b['date'] as int));
    return result;
  }

  /// Total discounts given per day in the range.
  Future<List<Map<String, dynamic>>> getDiscountReport({DateTime? from, DateTime? to}) async {
    final db = await _database;
    final rows = await db.rawQuery('''
      SELECT date(s.created_at, 'unixepoch') AS day,
        COALESCE(SUM(si.discount_amount), 0) AS totalDiscount
      FROM sale_items si
      JOIN sales s ON s.id = si.sale_id
      WHERE s.created_at >= ? AND s.created_at <= ? AND s.status = 'completed'
      GROUP BY day
      ORDER BY day ASC
    ''', [_fromTime(from), _toTime(to)]);
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  /// Matches the reference screenshot shape: rows like
  /// {taxName: 'SGST@2.5%'/'CGST@2.5%', taxPercent, taxableSaleAmount, taxIn,
  /// taxablePurchaseAmount, taxOut}. Each product's `tax_rate` /
  /// `purchase_items.tax_percent` is split evenly into SGST + CGST halves —
  /// an intra-state-transaction assumption; inter-state (IGST) is not
  /// distinguished in this app's data model.
  Future<List<Map<String, dynamic>>> getGstRateReport({DateTime? from, DateTime? to}) async {
    final db = await _database;
    final fromTime = _fromTime(from);
    final toTime = _toTime(to);

    final saleRows = await db.rawQuery('''
      SELECT pr.tax_rate AS rate,
        COALESCE(SUM(si.total_price - si.tax_amount), 0) AS taxableSale,
        COALESCE(SUM(si.tax_amount), 0) AS taxIn
      FROM sale_items si
      JOIN sales s ON s.id = si.sale_id
      JOIN products pr ON pr.id = si.product_id
      WHERE s.created_at >= ? AND s.created_at <= ? AND s.status = 'completed'
      GROUP BY pr.tax_rate
    ''', [fromTime, toTime]);

    final purchaseRows = await db.rawQuery('''
      SELECT pi.tax_percent AS rate,
        COALESCE(SUM(pi.total - pi.tax_amount), 0) AS taxablePurchase,
        COALESCE(SUM(pi.tax_amount), 0) AS taxOut
      FROM purchase_items pi
      JOIN purchases p ON p.id = pi.purchase_id
      WHERE p.created_at >= ? AND p.created_at <= ?
      GROUP BY pi.tax_percent
    ''', [fromTime, toTime]);

    final saleByRate = <double, Map<String, double>>{
      for (final r in saleRows)
        (r['rate'] as num).toDouble(): {
          'taxableSale': (r['taxableSale'] as num?)?.toDouble() ?? 0,
          'taxIn': (r['taxIn'] as num?)?.toDouble() ?? 0,
        },
    };
    final purchaseByRate = <double, Map<String, double>>{
      for (final r in purchaseRows)
        (r['rate'] as num).toDouble(): {
          'taxablePurchase': (r['taxablePurchase'] as num?)?.toDouble() ?? 0,
          'taxOut': (r['taxOut'] as num?)?.toDouble() ?? 0,
        },
    };

    final allRates = {...saleByRate.keys, ...purchaseByRate.keys}.toList()..sort();

    final result = <Map<String, dynamic>>[];
    for (final rate in allRates) {
      final taxableSale = saleByRate[rate]?['taxableSale'] ?? 0;
      final taxIn = saleByRate[rate]?['taxIn'] ?? 0;
      final taxablePurchase = purchaseByRate[rate]?['taxablePurchase'] ?? 0;
      final taxOut = purchaseByRate[rate]?['taxOut'] ?? 0;
      final halfRate = rate / 2;

      for (final label in ['SGST', 'CGST']) {
        result.add({
          'taxName': '$label@$halfRate%',
          'taxPercent': halfRate,
          'taxableSaleAmount': taxableSale,
          'taxIn': taxIn / 2,
          'taxablePurchaseAmount': taxablePurchase,
          'taxOut': taxOut / 2,
        });
      }
    }
    return result;
  }

  // ---------------------------------------------------------------------
  // Sales: Returns/Cancellations/Exchanges/Top Sellers
  // ---------------------------------------------------------------------

  /// One row per return in the range: date, invoice reference (or 'Untied'
  /// if the return has no linked sale), customer name (or 'Walk-in'),
  /// reason, refund method/amount, item count, and how many of those items
  /// were restocked.
  Future<List<Map<String, dynamic>>> getSalesReturnReport({DateTime? from, DateTime? to}) async {
    final db = await _database;
    final rows = await db.rawQuery('''
      SELECT sr.id AS returnId,
        sr.created_at AS date,
        CASE
          WHEN sr.sale_id IS NULL THEN 'Untied'
          ELSE COALESCE(s.invoice_display_no, CAST(s.invoice_no AS TEXT))
        END AS invoiceRef,
        COALESCE(c.name, 'Walk-in') AS customerName,
        sr.reason AS reason,
        sr.refund_method AS refundMethod,
        sr.refund_amount AS refundAmount,
        COALESCE(items.itemCount, 0) AS itemCount,
        COALESCE(items.restockedCount, 0) AS restockedCount
      FROM sales_returns sr
      LEFT JOIN sales s ON s.id = sr.sale_id
      LEFT JOIN customers c ON c.id = sr.customer_id
      LEFT JOIN (
        SELECT return_id,
          COUNT(*) AS itemCount,
          SUM(CASE WHEN restocked = 1 THEN 1 ELSE 0 END) AS restockedCount
        FROM sales_return_items
        GROUP BY return_id
      ) items ON items.return_id = sr.id
      WHERE sr.created_at >= ? AND sr.created_at <= ?
      ORDER BY sr.created_at ASC
    ''', [_fromTime(from), _toTime(to)]);
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  /// One row per cancellation in the range: date, invoice reference,
  /// customer name (or 'Walk-in'), reason, refund method/amount.
  Future<List<Map<String, dynamic>>> getSalesCancelReport({DateTime? from, DateTime? to}) async {
    final db = await _database;
    final rows = await db.rawQuery('''
      SELECT sc.id AS cancellationId,
        sc.created_at AS date,
        COALESCE(s.invoice_display_no, CAST(s.invoice_no AS TEXT)) AS invoiceRef,
        COALESCE(c.name, 'Walk-in') AS customerName,
        sc.reason AS reason,
        sc.refund_method AS refundMethod,
        sc.refund_amount AS refundAmount
      FROM sale_cancellations sc
      LEFT JOIN sales s ON s.id = sc.sale_id
      LEFT JOIN customers c ON c.id = sc.customer_id
      WHERE sc.created_at >= ? AND sc.created_at <= ?
      ORDER BY sc.created_at ASC
    ''', [_fromTime(from), _toTime(to)]);
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  /// One row per exchange in the range: date, original invoice reference
  /// (via the linked return's sale, or 'Untied' if that return had none),
  /// new invoice reference, customer name (or 'Walk-in'), price difference,
  /// settlement method.
  Future<List<Map<String, dynamic>>> getExchangeReport({DateTime? from, DateTime? to}) async {
    final db = await _database;
    final rows = await db.rawQuery('''
      SELECT ex.id AS exchangeId,
        ex.created_at AS date,
        CASE
          WHEN sr.sale_id IS NULL THEN 'Untied'
          ELSE COALESCE(origSale.invoice_display_no, CAST(origSale.invoice_no AS TEXT))
        END AS originalInvoiceRef,
        COALESCE(newSale.invoice_display_no, CAST(newSale.invoice_no AS TEXT)) AS newInvoiceRef,
        COALESCE(c.name, 'Walk-in') AS customerName,
        ex.price_difference AS priceDifference,
        ex.settlement_method AS settlementMethod
      FROM exchanges ex
      LEFT JOIN sales_returns sr ON sr.id = ex.return_id
      LEFT JOIN sales origSale ON origSale.id = sr.sale_id
      LEFT JOIN sales newSale ON newSale.id = ex.new_sale_id
      LEFT JOIN customers c ON c.id = ex.customer_id
      WHERE ex.created_at >= ? AND ex.created_at <= ?
      ORDER BY ex.created_at ASC
    ''', [_fromTime(from), _toTime(to)]);
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  /// Products ranked by quantity sold (descending) in the range: name,
  /// barcode, quantity, revenue (ex-tax). Limited to [limit] rows.
  Future<List<Map<String, dynamic>>> getTopSellingProducts({
    DateTime? from,
    DateTime? to,
    int limit = 50,
  }) async {
    final db = await _database;
    final rows = await db.rawQuery('''
      SELECT pr.name AS name,
        pr.barcode AS barcode,
        COALESCE(SUM(si.quantity), 0) AS quantity,
        COALESCE(SUM(si.total_price - si.tax_amount), 0) AS revenue
      FROM sale_items si
      JOIN sales s ON s.id = si.sale_id
      JOIN products pr ON pr.id = si.product_id
      WHERE s.created_at >= ? AND s.created_at <= ? AND s.status = 'completed'
      GROUP BY si.product_id
      ORDER BY quantity DESC
      LIMIT ?
    ''', [_fromTime(from), _toTime(to), limit]);
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  // ---------------------------------------------------------------------
  // AI Analysis: Customer visits, slow movers, festival stock suggestions
  // ---------------------------------------------------------------------

  /// Every customer with their last completed-sale date (null if they've
  /// never bought anything) and days since — sorted most-overdue-for-a-
  /// return-visit first, with never-purchased customers surfacing at the
  /// very top (SQLite sorts NULL before any value in ASC order).
  Future<List<Map<String, dynamic>>> getCustomerLastVisit() async {
    final db = await _database;
    final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final rows = await db.rawQuery('''
      SELECT c.id AS customerId, c.name AS name, c.phone AS phone, c.total_spent AS totalSpent,
        MAX(CASE WHEN s.status = 'completed' THEN s.created_at END) AS lastVisit
      FROM customers c
      LEFT JOIN sales s ON s.customer_id = c.id
      GROUP BY c.id
      ORDER BY lastVisit ASC
    ''');
    return rows.map((r) {
      final lastVisit = r['lastVisit'] as int?;
      return {
        ...Map<String, dynamic>.from(r),
        'daysSinceVisit': lastVisit == null ? null : (nowSeconds - lastVisit) ~/ 86400,
      };
    }).toList();
  }

  /// The single product a customer has bought the most of (by total
  /// quantity across all their completed sales), or null if they've never
  /// bought anything. Used on the customer history screen's "Favorite
  /// Product" stat.
  Future<Map<String, dynamic>?> getCustomerFavoriteProduct(String customerId) async {
    final db = await _database;
    final rows = await db.rawQuery('''
      SELECT pr.id AS productId, pr.name AS name,
        SUM(si.quantity) AS totalQuantity, COUNT(DISTINCT s.id) AS timesPurchased
      FROM sale_items si
      JOIN sales s ON s.id = si.sale_id
      JOIN products pr ON pr.id = si.product_id
      WHERE s.customer_id = ? AND s.status = 'completed'
      GROUP BY si.product_id
      ORDER BY totalQuantity DESC
      LIMIT 1
    ''', [customerId]);
    return rows.isEmpty ? null : Map<String, dynamic>.from(rows.first);
  }

  /// Products still in stock that have sold little or nothing in the last
  /// [days] days — candidates for a clearance push or to stop reordering.
  /// `soldQuantity` is scoped to [days]; `lastSaleAt` looks back across all
  /// time (null means it has never sold at all, not just recently).
  Future<List<Map<String, dynamic>>> getSlowMovingStock({int days = 60, int limit = 100}) async {
    final db = await _database;
    final windowStart = DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch ~/ 1000;
    final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final rows = await db.rawQuery('''
      SELECT pr.id AS productId, pr.name AS name, pr.barcode AS barcode,
        pr.stock_quantity AS stockQuantity, pr.retail_price AS retailPrice,
        (pr.stock_quantity * pr.cost_price) AS stockValue,
        COALESCE(recent.soldQty, 0) AS soldQuantity,
        last.lastSaleAt AS lastSaleAt
      FROM products pr
      LEFT JOIN (
        SELECT si.product_id, SUM(si.quantity) AS soldQty
        FROM sale_items si JOIN sales s ON s.id = si.sale_id
        WHERE s.created_at >= ? AND s.status = 'completed'
        GROUP BY si.product_id
      ) recent ON recent.product_id = pr.id
      LEFT JOIN (
        SELECT si.product_id, MAX(s.created_at) AS lastSaleAt
        FROM sale_items si JOIN sales s ON s.id = si.sale_id
        WHERE s.status = 'completed'
        GROUP BY si.product_id
      ) last ON last.product_id = pr.id
      WHERE pr.is_deleted = 0 AND pr.is_active = 1 AND pr.stock_quantity > 0
      ORDER BY soldQuantity ASC, stockValue DESC
      LIMIT ?
    ''', [windowStart, limit]);
    return rows.map((r) {
      final lastSaleAt = r['lastSaleAt'] as int?;
      return {
        ...Map<String, dynamic>.from(r),
        'daysSinceLastSale': lastSaleAt == null ? null : (nowSeconds - lastSaleAt) ~/ 86400,
      };
    }).toList();
  }

  /// Finds the nearest upcoming active festival (see FestivalRepository)
  /// and looks at what sold well in the same ±14-day calendar window last
  /// year, so a manager can restock ahead of it. Returns
  /// `hasFestival: false` if no festival is configured/active, and
  /// `hasHistoricalData: false` if nothing sold in that window last year
  /// (e.g. a new store, or data that predates the app's use) — both are
  /// normal, non-error states the UI should show a plain message for.
  Future<Map<String, dynamic>> getFestivalStockSuggestions({int windowDays = 14, int limit = 15}) async {
    final upcoming = await FestivalRepository().nextUpcoming(DateTime.now());
    if (upcoming == null) {
      return {'hasFestival': false};
    }

    final lastYearCenter = DateTime(upcoming.date.year - 1, upcoming.date.month, upcoming.date.day);
    final windowStart =
        lastYearCenter.subtract(Duration(days: windowDays)).millisecondsSinceEpoch ~/ 1000;
    final windowEnd = lastYearCenter.add(Duration(days: windowDays)).millisecondsSinceEpoch ~/ 1000;

    final db = await _database;
    final rows = await db.rawQuery('''
      SELECT pr.id AS productId, pr.name AS name, pr.barcode AS barcode,
        SUM(si.quantity) AS quantitySoldLastYear,
        SUM(si.total_price) AS revenueLastYear,
        pr.stock_quantity AS currentStock
      FROM sale_items si
      JOIN sales s ON s.id = si.sale_id
      JOIN products pr ON pr.id = si.product_id
      WHERE s.created_at >= ? AND s.created_at <= ? AND s.status = 'completed'
      GROUP BY si.product_id
      ORDER BY quantitySoldLastYear DESC
      LIMIT ?
    ''', [windowStart, windowEnd, limit]);

    return {
      'hasFestival': true,
      'festivalName': upcoming.festival.name,
      'festivalNotes': upcoming.festival.notes,
      'festivalDate': upcoming.date.millisecondsSinceEpoch ~/ 1000,
      'daysUntil': upcoming.daysUntil,
      'hasHistoricalData': rows.isNotEmpty,
      'suggestions': rows.map((r) {
        final quantitySoldLastYear = (r['quantitySoldLastYear'] as num?)?.toDouble() ?? 0;
        final currentStock = (r['currentStock'] as num?)?.toDouble() ?? 0;
        return {
          ...Map<String, dynamic>.from(r),
          // Rough heuristic, not a demand forecast: if what's on the shelf
          // now wouldn't have covered last year's festival-window volume,
          // flag it as worth restocking before the same festival this year.
          'needsRestock': currentStock < quantitySoldLastYear,
        };
      }).toList(),
    };
  }
}
