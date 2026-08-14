import 'package:sqflite/sqflite.dart';

import '../core/database/database_helper.dart';

/// How serious a [VerificationIssue] is. Used to sort and color results in
/// the Verify My Data screen (errors first, then warnings, then info).
enum VerificationSeverity { info, warning, error }

/// A single finding produced by one of [DataVerificationService]'s checks.
class VerificationIssue {
  final VerificationSeverity severity;
  final String checkName;
  final String message;
  final String? recordId;

  const VerificationIssue({
    required this.severity,
    required this.checkName,
    required this.message,
    this.recordId,
  });
}

/// Runs a battery of read-only sanity checks over the local database and
/// reports anything that looks wrong (duplicate barcodes, orphaned rows,
/// customers over their credit limit, etc). Never writes to the database.
class DataVerificationService {
  /// Runs every check, isolating failures so one bad query can't take down
  /// the rest. Returns an empty list when the database is clean.
  static Future<List<VerificationIssue>> runAllChecks({Database? db}) async {
    final database = db ?? await DatabaseHelper.instance.database;

    final issues = <VerificationIssue>[];

    await _runCheck(issues, 'Duplicate Barcodes', () => _checkDuplicateBarcodes(database));
    await _runCheck(issues, 'Negative Stock', () => _checkNegativeStock(database));
    await _runCheck(issues, 'Orphaned Sale Items', () => _checkOrphanedSaleItems(database));
    await _runCheck(issues, 'Credit Limit Exceeded', () => _checkCreditLimitExceeded(database));
    await _runCheck(issues, 'Duplicate Invoice Numbers', () => _checkDuplicateInvoiceNumbers(database));

    return issues;
  }

  /// Runs [check], appending whatever issues it finds to [issues]. If
  /// [check] itself throws, appends a single error-level issue describing
  /// the failure instead of letting the exception propagate.
  static Future<void> _runCheck(
    List<VerificationIssue> issues,
    String checkName,
    Future<List<VerificationIssue>> Function() check,
  ) async {
    try {
      issues.addAll(await check());
    } catch (e) {
      issues.add(VerificationIssue(
        severity: VerificationSeverity.error,
        checkName: checkName,
        message: 'Check failed to run: $e',
      ));
    }
  }

  static Future<List<VerificationIssue>> _checkDuplicateBarcodes(Database db) async {
    final rows = await db.rawQuery('''
      SELECT barcode, COUNT(*) c
      FROM products
      WHERE is_deleted = 0
      GROUP BY barcode
      HAVING c > 1
    ''');

    return rows.map((row) {
      final barcode = row['barcode'];
      final count = row['c'];
      return VerificationIssue(
        severity: VerificationSeverity.warning,
        checkName: 'Duplicate Barcodes',
        message: 'Barcode $barcode is used by $count products',
        recordId: barcode?.toString(),
      );
    }).toList();
  }

  static Future<List<VerificationIssue>> _checkNegativeStock(Database db) async {
    final rows = await db.rawQuery('''
      SELECT id, name, stock_quantity
      FROM products
      WHERE stock_quantity < 0 AND allow_negative_stock = 0 AND is_deleted = 0
    ''');

    return rows.map((row) {
      final name = row['name'];
      final stock = row['stock_quantity'];
      return VerificationIssue(
        severity: VerificationSeverity.error,
        checkName: 'Negative Stock',
        message: "Product '$name' has negative stock ($stock) but negative stock isn't allowed for it",
        recordId: row['id']?.toString(),
      );
    }).toList();
  }

  static Future<List<VerificationIssue>> _checkOrphanedSaleItems(Database db) async {
    final rows = await db.rawQuery('''
      SELECT si.id, si.sale_id
      FROM sale_items si
      LEFT JOIN products p ON p.id = si.product_id
      WHERE p.id IS NULL
    ''');

    return rows.map((row) {
      return VerificationIssue(
        severity: VerificationSeverity.error,
        checkName: 'Orphaned Sale Items',
        message: 'Sale item references a missing product',
        recordId: row['id']?.toString(),
      );
    }).toList();
  }

  static Future<List<VerificationIssue>> _checkCreditLimitExceeded(Database db) async {
    final rows = await db.rawQuery('''
      SELECT id, name, outstanding_balance, credit_limit
      FROM customers
      WHERE outstanding_balance > credit_limit AND credit_limit > 0 AND is_deleted = 0
    ''');

    return rows.map((row) {
      final name = row['name'];
      final balance = row['outstanding_balance'];
      final limit = row['credit_limit'];
      return VerificationIssue(
        severity: VerificationSeverity.warning,
        checkName: 'Credit Limit Exceeded',
        message: "Customer '$name' owes ₹$balance which exceeds their ₹$limit credit limit",
        recordId: row['id']?.toString(),
      );
    }).toList();
  }

  static Future<List<VerificationIssue>> _checkDuplicateInvoiceNumbers(Database db) async {
    final rows = await db.rawQuery('''
      SELECT invoice_no, COUNT(*) c
      FROM sales
      GROUP BY invoice_no
      HAVING c > 1
    ''');

    return rows.map((row) {
      final invoiceNo = row['invoice_no'];
      return VerificationIssue(
        severity: VerificationSeverity.error,
        checkName: 'Duplicate Invoice Numbers',
        message: 'Invoice number $invoiceNo appears on multiple sales',
        recordId: invoiceNo?.toString(),
      );
    }).toList();
  }
}
