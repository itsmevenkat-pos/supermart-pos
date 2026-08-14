import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:supermart_pos/core/database/migrations/migration_v1.dart';
import 'package:supermart_pos/core/database/migrations/migration_v17.dart';
import 'package:supermart_pos/services/advanced_report_service.dart';

/// Builds a throwaway in-memory database with the real baseline schema (via
/// MigrationV1, which already includes `products.hsn_code`), plus MigrationV17
/// (adds `product_batches`, needed by [getExpiryAlerts] tests) layered on
/// top, so AdvancedReportService's aggregation queries run against something
/// that actually looks like production data. Mirrors the pattern in
/// `test/services/data_verification_service_test.dart`.
Future<Database> _openTestDatabase() async {
  sqfliteFfiInit();
  return databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 1,
      onCreate: (db, version) async {
        await MigrationV1.up(db);
        await MigrationV17.up(db);
      },
    ),
  );
}

const _now = 1700000000;

Future<void> _insertCustomer(
  Database db, {
  required String id,
  String name = 'Test Customer',
  String rating = 'regular',
}) {
  return db.insert('customers', {
    'id': id,
    'phone': '9$id'.padRight(10, '0').substring(0, 10),
    'name': name,
    'rating': rating,
  });
}

Future<void> _insertProduct(
  Database db, {
  required String id,
  String name = 'Test Product',
  double taxRate = 0,
}) {
  return db.insert('products', {
    'id': id,
    'barcode': id,
    'name': name,
    'tax_rate': taxRate,
  });
}

Future<void> _insertSale(
  Database db, {
  required String id,
  String? customerId,
  String? userId,
  required int invoiceNo,
  String? invoiceDisplayNo,
  required double netAmount,
  double taxTotal = 0,
  bool isCreditSale = false,
  String status = 'completed',
  String? paymentMethods,
  int createdAt = _now,
}) {
  return db.insert('sales', {
    'id': id,
    'customer_id': customerId,
    'user_id': userId,
    'invoice_no': invoiceNo,
    'invoice_display_no': invoiceDisplayNo,
    'net_amount': netAmount,
    'tax_total': taxTotal,
    'is_credit_sale': isCreditSale ? 1 : 0,
    'status': status,
    'payment_methods': paymentMethods,
    'created_at': createdAt,
  });
}

Future<void> _insertUser(
  Database db, {
  required String id,
  String? username,
  String name = 'Test User',
}) {
  return db.insert('users', {
    'id': id,
    'username': username ?? id,
    'password_hash': 'x',
    'name': name,
  });
}

Future<void> _insertSaleItem(
  Database db, {
  required String id,
  required String saleId,
  required String productId,
  double quantity = 1,
  double totalPrice = 0,
  double taxAmount = 0,
  double costPrice = 0,
}) {
  return db.insert('sale_items', {
    'id': id,
    'sale_id': saleId,
    'product_id': productId,
    'quantity': quantity,
    'total_price': totalPrice,
    'tax_amount': taxAmount,
    'cost_price': costPrice,
  });
}

Future<void> _insertPurchase(
  Database db, {
  required String id,
  required String grnNo,
  double netAmount = 0,
  int createdAt = _now,
}) {
  return db.insert('purchases', {
    'id': id,
    'grn_no': grnNo,
    'net_amount': netAmount,
    'created_at': createdAt,
  });
}

Future<void> _insertPurchaseItem(
  Database db, {
  required String id,
  required String purchaseId,
  required String productId,
  double taxPercent = 0,
  double total = 0,
  double taxAmount = 0,
}) {
  return db.insert('purchase_items', {
    'id': id,
    'purchase_id': purchaseId,
    'product_id': productId,
    'tax_percent': taxPercent,
    'total': total,
    'tax_amount': taxAmount,
  });
}

Future<void> _insertBatch(
  Database db, {
  required String id,
  required String productId,
  String? batchNo,
  int? expiryDate,
  double quantityReceived = 1,
}) {
  return db.insert('product_batches', {
    'id': id,
    'product_id': productId,
    'batch_no': batchNo,
    'expiry_date': expiryDate,
    'quantity_received': quantityReceived,
  });
}

void main() {
  group('AdvancedReportService', () {
    late Database db;
    late AdvancedReportService service;

    setUp(() async {
      db = await _openTestDatabase();
      service = AdvancedReportService(db: db);
    });

    tearDown(() async {
      await db.close();
    });

    test('getBillWiseProfit computes ex-tax net sale amount and COGS-based profit', () async {
      await _insertCustomer(db, id: 'c1', name: 'Alice');
      await _insertProduct(db, id: 'p1');
      await _insertSale(
        db,
        id: 's1',
        customerId: 'c1',
        invoiceNo: 1,
        invoiceDisplayNo: 'SM/25-26/00001',
        netAmount: 118,
        taxTotal: 18,
      );
      // net sale amount (ex-tax) = 118 - 18 = 100; cogs = 30 * 2 = 60.
      await _insertSaleItem(
        db,
        id: 'si1',
        saleId: 's1',
        productId: 'p1',
        quantity: 2,
        totalPrice: 118,
        taxAmount: 18,
        costPrice: 30,
      );

      final rows = await service.getBillWiseProfit();

      expect(rows, hasLength(1));
      expect(rows.first['invoiceNo'], 'SM/25-26/00001');
      expect(rows.first['customerName'], 'Alice');
      expect(rows.first['netSaleAmount'], 100);
      expect(rows.first['cogs'], 60);
      expect(rows.first['profit'], 40);
    });

    test('getGstRateReport splits each tax rate evenly across SGST and CGST', () async {
      await _insertProduct(db, id: 'p1', name: 'Five Percent Item', taxRate: 5);
      await _insertProduct(db, id: 'p2', name: 'Twelve Percent Item', taxRate: 12);
      await _insertSale(db, id: 's1', invoiceNo: 1, netAmount: 217, taxTotal: 17);
      // p1: taxable 100, tax 5. p2: taxable 100, tax 12.
      await _insertSaleItem(db, id: 'si1', saleId: 's1', productId: 'p1', totalPrice: 105, taxAmount: 5);
      await _insertSaleItem(db, id: 'si2', saleId: 's1', productId: 'p2', totalPrice: 112, taxAmount: 12);

      final rows = await service.getGstRateReport();

      final fivePercentRows = rows.where((r) => r['taxPercent'] == 2.5).toList();
      expect(fivePercentRows, hasLength(2)); // SGST@2.5% + CGST@2.5%
      expect(fivePercentRows.map((r) => r['taxName']), containsAll(['SGST@2.5%', 'CGST@2.5%']));
      for (final row in fivePercentRows) {
        expect(row['taxableSaleAmount'], 100);
        expect(row['taxIn'], 2.5); // 5 / 2
      }

      final twelvePercentRows = rows.where((r) => r['taxPercent'] == 6.0).toList();
      expect(twelvePercentRows, hasLength(2)); // SGST@6.0% + CGST@6.0%
      for (final row in twelvePercentRows) {
        expect(row['taxableSaleAmount'], 100);
        expect(row['taxIn'], 6); // 12 / 2
      }
    });

    test('getPartyWiseProfitLoss aggregates ex-tax sales and COGS per customer', () async {
      await _insertCustomer(db, id: 'c1', name: 'Alice');
      await _insertCustomer(db, id: 'c2', name: 'Bob');
      await _insertProduct(db, id: 'p1');

      // Alice: two sales, ex-tax 100 + 50 = 150; cogs 40 + 20 = 60; profit 90.
      await _insertSale(db, id: 's1', customerId: 'c1', invoiceNo: 1, netAmount: 118, taxTotal: 18);
      await _insertSaleItem(db, id: 'si1', saleId: 's1', productId: 'p1', quantity: 2, costPrice: 20);
      await _insertSale(db, id: 's2', customerId: 'c1', invoiceNo: 2, netAmount: 59, taxTotal: 9);
      await _insertSaleItem(db, id: 'si2', saleId: 's2', productId: 'p1', quantity: 2, costPrice: 10);

      // Bob: one sale, ex-tax 100; cogs 30; profit 70.
      await _insertSale(db, id: 's3', customerId: 'c2', invoiceNo: 3, netAmount: 118, taxTotal: 18);
      await _insertSaleItem(db, id: 'si3', saleId: 's3', productId: 'p1', quantity: 1, costPrice: 30);

      final rows = await service.getPartyWiseProfitLoss();

      final alice = rows.firstWhere((r) => r['name'] == 'Alice');
      expect(alice['totalSales'], 150);
      expect(alice['totalCogs'], 60);
      expect(alice['profit'], 90);

      final bob = rows.firstWhere((r) => r['name'] == 'Bob');
      expect(bob['totalSales'], 100);
      expect(bob['totalCogs'], 30);
      expect(bob['profit'], 70);
    });

    test('getGstr3b nets output tax against input tax credit', () async {
      await _insertProduct(db, id: 'p1');
      await _insertSale(db, id: 's1', invoiceNo: 1, netAmount: 118, taxTotal: 18);
      // Output tax (sales side) = 18.
      await _insertSaleItem(db, id: 'si1', saleId: 's1', productId: 'p1', totalPrice: 118, taxAmount: 18);

      await _insertPurchase(db, id: 'pu1', grnNo: 'GRN-1', netAmount: 106);
      // Input tax credit (purchase side) = 6.
      await _insertPurchaseItem(db, id: 'pi1', purchaseId: 'pu1', productId: 'p1', taxPercent: 6, total: 106, taxAmount: 6);

      final rows = await service.getGstr3b();

      expect(rows, hasLength(1));
      expect(rows.first['outputTax'], 18);
      expect(rows.first['inputTaxCredit'], 6);
      expect(rows.first['netTaxPayable'], 12);
    });

    test('getSalePurchaseByPartyGroup groups sales by customer rating and ungroups purchases', () async {
      await _insertCustomer(db, id: 'c1', name: 'Gold Customer', rating: 'gold');
      await _insertCustomer(db, id: 'c2', name: 'Silver Customer', rating: 'silver');
      await _insertProduct(db, id: 'p1');

      await _insertSale(db, id: 's1', customerId: 'c1', invoiceNo: 1, netAmount: 100);
      await _insertSale(db, id: 's2', customerId: 'c2', invoiceNo: 2, netAmount: 50);

      await _insertPurchase(db, id: 'pu1', grnNo: 'GRN-1', netAmount: 75);

      final rows = await service.getSalePurchaseByPartyGroup();

      final goldRow = rows.firstWhere((r) => r['groupName'] == 'gold');
      expect(goldRow['partyType'], 'customer');
      expect(goldRow['amount'], 100);

      final silverRow = rows.firstWhere((r) => r['groupName'] == 'silver');
      expect(silverRow['amount'], 50);

      final ungroupedRow = rows.firstWhere((r) => r['groupName'] == 'Ungrouped');
      expect(ungroupedRow['partyType'], 'supplier');
      expect(ungroupedRow['amount'], 75);
    });

    test('getUserWiseSales aggregates bill count, totals, and payment breakdown per cashier', () async {
      await _insertUser(db, id: 'u1', name: 'Alice');
      await _insertUser(db, id: 'u2', name: 'Bob');

      // Alice: two sales — one cash+upi, one all card.
      await _insertSale(
        db,
        id: 's1',
        userId: 'u1',
        invoiceNo: 1,
        netAmount: 150,
        paymentMethods: '{"cash": 100, "upi": 50}',
      );
      await _insertSale(
        db,
        id: 's2',
        userId: 'u1',
        invoiceNo: 2,
        netAmount: 200,
        paymentMethods: '{"card": 200}',
      );

      // Bob: one sale, split between credit and cash.
      await _insertSale(
        db,
        id: 's3',
        userId: 'u2',
        invoiceNo: 3,
        netAmount: 80,
        paymentMethods: '{"cash": 30, "credit": 50}',
      );

      // A sale with no user_id (e.g. legacy data) should be grouped as 'Unknown'.
      await _insertSale(
        db,
        id: 's4',
        invoiceNo: 4,
        netAmount: 40,
        paymentMethods: '{"cash": 40}',
      );

      // A non-completed sale must be excluded entirely.
      await _insertSale(
        db,
        id: 's5',
        userId: 'u1',
        invoiceNo: 5,
        netAmount: 999,
        status: 'cancelled',
        paymentMethods: '{"cash": 999}',
      );

      final rows = await service.getUserWiseSales();

      expect(rows, hasLength(3));

      final alice = rows.firstWhere((r) => r['userName'] == 'Alice');
      expect(alice['billCount'], 2);
      expect(alice['totalSales'], 350);
      expect(alice['cash'], 100);
      expect(alice['upi'], 50);
      expect(alice['card'], 200);
      expect(alice['credit'], 0);

      final bob = rows.firstWhere((r) => r['userName'] == 'Bob');
      expect(bob['billCount'], 1);
      expect(bob['totalSales'], 80);
      expect(bob['cash'], 30);
      expect(bob['credit'], 50);
      expect(bob['upi'], 0);
      expect(bob['card'], 0);

      final unknown = rows.firstWhere((r) => r['userName'] == 'Unknown');
      expect(unknown['billCount'], 1);
      expect(unknown['totalSales'], 40);
      expect(unknown['cash'], 40);
    });

    test('getExpiryAlerts returns only batches within the window, tagged Expired vs Expiring Soon', () async {
      final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final expiredSeconds = nowSeconds - (2 * 86400); // 2 days ago
      final soonSeconds = nowSeconds + (5 * 86400); // 5 days from now, within default 30-day window
      final farSeconds = nowSeconds + (200 * 86400); // well outside the window

      await _insertProduct(db, id: 'p1', name: 'Milk Packet');
      await db.update('products', {'stock_quantity': 40}, where: 'id = ?', whereArgs: ['p1']);

      await _insertBatch(db, id: 'b1', productId: 'p1', batchNo: 'BATCH-EXPIRED', expiryDate: expiredSeconds, quantityReceived: 10);
      await _insertBatch(db, id: 'b2', productId: 'p1', batchNo: 'BATCH-SOON', expiryDate: soonSeconds, quantityReceived: 20);
      await _insertBatch(db, id: 'b3', productId: 'p1', batchNo: 'BATCH-FAR', expiryDate: farSeconds, quantityReceived: 30);

      final rows = await service.getExpiryAlerts(daysAhead: 30);

      // BATCH-FAR is outside the 30-day window and must be excluded.
      expect(rows, hasLength(2));
      expect(rows.map((r) => r['batchNo']).toList(), ['BATCH-EXPIRED', 'BATCH-SOON']); // soonest first

      final expiredRow = rows.firstWhere((r) => r['batchNo'] == 'BATCH-EXPIRED');
      expect(expiredRow['status'], 'Expired');
      expect(expiredRow['productName'], 'Milk Packet');
      expect(expiredRow['quantityReceived'], 10);
      expect(expiredRow['currentProductStock'], 40);

      final soonRow = rows.firstWhere((r) => r['batchNo'] == 'BATCH-SOON');
      expect(soonRow['status'], 'Expiring Soon');
      expect(soonRow['quantityReceived'], 20);
      expect(soonRow['currentProductStock'], 40);
    });
  });
}
