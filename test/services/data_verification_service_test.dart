import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:supermart_pos/core/database/migrations/migration_v1.dart';
import 'package:supermart_pos/services/data_verification_service.dart';

/// Builds a throwaway in-memory database with the real schema (via
/// MigrationV1) so DataVerificationService's checks can run against
/// something that actually looks like production data.
Future<Database> _openTestDatabase() async {
  sqfliteFfiInit();
  return databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 1,
      onCreate: (db, version) => MigrationV1.up(db),
    ),
  );
}

Future<void> _insertProduct(
  Database db, {
  required String id,
  required String barcode,
  String name = 'Test Product',
  int stockQuantity = 10,
  int allowNegativeStock = 0,
  int isDeleted = 0,
}) {
  return db.insert('products', {
    'id': id,
    'barcode': barcode,
    'name': name,
    'stock_quantity': stockQuantity,
    'allow_negative_stock': allowNegativeStock,
    'is_deleted': isDeleted,
  });
}

void main() {
  group('DataVerificationService', () {
    late Database db;

    setUp(() async {
      db = await _openTestDatabase();
    });

    tearDown(() async {
      await db.close();
    });

    test('clean database produces zero issues', () async {
      await _insertProduct(db, id: 'p1', barcode: '111', name: 'Rice');
      await _insertProduct(db, id: 'p2', barcode: '222', name: 'Sugar');

      await db.insert('customers', {
        'id': 'c1',
        'phone': '9999999999',
        'name': 'Regular Customer',
        'outstanding_balance': 100,
        'credit_limit': 500,
        'is_deleted': 0,
      });

      await db.insert('sales', {
        'id': 's1',
        'invoice_no': 1,
        'net_amount': 100,
      });
      await db.insert('sale_items', {
        'id': 'si1',
        'sale_id': 's1',
        'product_id': 'p1',
        'quantity': 1,
        'unit_price': 100,
        'total_price': 100,
      });

      final issues = await DataVerificationService.runAllChecks(db: db);

      expect(issues, isEmpty);
    });

    test('duplicate barcode and negative stock without override are reported', () async {
      // Two active products sharing the same barcode.
      await _insertProduct(db, id: 'p1', barcode: 'dup-barcode', name: 'Product A');
      await _insertProduct(db, id: 'p2', barcode: 'dup-barcode', name: 'Product B');

      // Negative stock with no override allowed.
      await _insertProduct(
        db,
        id: 'p3',
        barcode: 'neg-stock',
        name: 'Product C',
        stockQuantity: -5,
        allowNegativeStock: 0,
      );

      final issues = await DataVerificationService.runAllChecks(db: db);

      final duplicateBarcodeIssue = issues.where(
        (i) => i.checkName == 'Duplicate Barcodes',
      );
      expect(duplicateBarcodeIssue, hasLength(1));
      expect(duplicateBarcodeIssue.first.severity, VerificationSeverity.warning);
      expect(duplicateBarcodeIssue.first.message, contains('dup-barcode'));

      final negativeStockIssue = issues.where(
        (i) => i.checkName == 'Negative Stock',
      );
      expect(negativeStockIssue, hasLength(1));
      expect(negativeStockIssue.first.severity, VerificationSeverity.error);
      expect(negativeStockIssue.first.message, contains('Product C'));
    });

    test('negative stock is ignored when allow_negative_stock is set', () async {
      await _insertProduct(
        db,
        id: 'p1',
        barcode: '333',
        name: 'Frozen Peas',
        stockQuantity: -3,
        allowNegativeStock: 1,
      );

      final issues = await DataVerificationService.runAllChecks(db: db);

      expect(issues.where((i) => i.checkName == 'Negative Stock'), isEmpty);
    });

    test('orphaned sale items are reported', () async {
      await db.insert('sales', {'id': 's1', 'invoice_no': 7, 'net_amount': 50});

      // Sale item pointing at a product id that doesn't exist.
      await db.insert('sale_items', {
        'id': 'si1',
        'sale_id': 's1',
        'product_id': 'missing-product',
        'quantity': 1,
        'unit_price': 50,
        'total_price': 50,
      });

      final issues = await DataVerificationService.runAllChecks(db: db);

      expect(issues.where((i) => i.checkName == 'Orphaned Sale Items'), hasLength(1));
    });

    test('duplicate invoice numbers check runs cleanly when sales are unique', () async {
      // `sales.invoice_no` is a UNIQUE column, so genuine duplicates can't
      // be created through a normal insert — this check exists purely as a
      // defensive net against DB corruption. Here we just confirm the check
      // runs without raising a false positive on well-formed data.
      await db.insert('sales', {'id': 's1', 'invoice_no': 7, 'net_amount': 50});
      await db.insert('sales', {'id': 's2', 'invoice_no': 8, 'net_amount': 75});

      final issues = await DataVerificationService.runAllChecks(db: db);

      expect(issues.where((i) => i.checkName == 'Duplicate Invoice Numbers'), isEmpty);
    });

    test('customers over their credit limit are reported', () async {
      await db.insert('customers', {
        'id': 'c1',
        'phone': '8888888888',
        'name': 'Over Limit Customer',
        'outstanding_balance': 1000,
        'credit_limit': 500,
        'is_deleted': 0,
      });

      final issues = await DataVerificationService.runAllChecks(db: db);

      final creditIssues = issues.where((i) => i.checkName == 'Credit Limit Exceeded');
      expect(creditIssues, hasLength(1));
      expect(creditIssues.first.severity, VerificationSeverity.warning);
      expect(creditIssues.first.message, contains('Over Limit Customer'));
    });
  });
}
