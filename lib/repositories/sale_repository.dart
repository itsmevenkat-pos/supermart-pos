import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../core/database/database_helper.dart';
import '../models/sale_model.dart';
import '../models/sale_item_model.dart';
import '../models/stock_ledger_model.dart';
import '../models/customer_model.dart';
import '../models/customer_ledger_model.dart';
import '../models/product_model.dart';
import '../core/utils/financial_year.dart';
import '../core/utils/loyalty_utils.dart';
import 'product_kit_repository.dart';
import 'stock_group_repository.dart';
import '../services/gl_service.dart';

class SaleRepository {
  SaleRepository({
    DatabaseHelper? dbHelper,
    ProductKitRepository? kitRepo,
    StockGroupRepository? stockGroupRepo,
    GLService? glService,
  })  : _dbHelper = dbHelper ?? DatabaseHelper.instance,
        _kitRepo = kitRepo ?? ProductKitRepository(),
        _stockGroupRepo = stockGroupRepo ?? StockGroupRepository(),
        _glService = glService ?? GLService();

  final DatabaseHelper _dbHelper;
  final ProductKitRepository _kitRepo;
  final StockGroupRepository _stockGroupRepo;
  final GLService _glService;

  /// Pass [txn] to run inside an already-open transaction (e.g. from
  /// [ExchangeRepository], which composes a new sale with a return
  /// atomically) instead of opening a new one — default behavior (omitting
  /// [txn]) is unchanged for existing callers.
  Future<Sale> insertSaleWithItems({
    required Sale sale,
    required List<SaleItem> items,
    required String storeId,
    String? customerId,
    Transaction? txn,
  }) async {
    if (txn != null) {
      return _insertSaleBody(txn, sale, items, storeId, customerId);
    }
    final db = await _dbHelper.database;
    late Sale savedSale;
    await db.transaction((t) async {
      savedSale = await _insertSaleBody(t, sale, items, storeId, customerId);
    });
    return savedSale;
  }

  Future<Sale> _insertSaleBody(
    Transaction txn,
    Sale sale,
    List<SaleItem> items,
    String storeId,
    String? customerId,
  ) async {
    late Sale savedSale;
    {
      // Assign the real sequential invoice number inside the transaction
      // so two sales can never race for the same number. (Sale.create's
      // own invoiceNo is just a placeholder until this replaces it.)
      final result = await txn.rawQuery('SELECT MAX(invoice_no) as maxNo FROM sales');
      final maxNo = result.first['maxNo'] as int?;
      final nextInvoiceNo = (maxNo ?? 1000) + 1;

      // Formatted display number (e.g. SM/25-26/00001): store prefix +
      // financial year + a sequence that resets each financial year. This
      // is a label derived alongside invoice_no, not a replacement for it —
      // invoice_no stays the gapless integer sequence used for uniqueness.
      final fy = financialYearLabel(DateTime.now());
      final storeRows = await txn.query('stores', where: 'id = ?', whereArgs: [storeId], limit: 1);
      final prefix = storeRows.isNotEmpty ? (storeRows.first['invoice_prefix'] as String? ?? 'SM') : 'SM';

      final counterRows = await txn.query('invoice_counters', where: 'financial_year = ?', whereArgs: [fy]);
      final int fySeq;
      if (counterRows.isEmpty) {
        fySeq = 1;
        await txn.insert('invoice_counters', {'financial_year': fy, 'next_seq': 2});
      } else {
        fySeq = counterRows.first['next_seq'] as int;
        await txn.update(
          'invoice_counters',
          {'next_seq': fySeq + 1},
          where: 'financial_year = ?',
          whereArgs: [fy],
        );
      }
      final invoiceDisplayNo = '$prefix/$fy/${fySeq.toString().padLeft(5, '0')}';

      savedSale = sale.copyWith(invoiceNo: nextInvoiceNo, invoiceDisplayNo: invoiceDisplayNo);

      // 1. Insert sale header
      await txn.insert('sales', savedSale.toJson());

      // 2. Insert sale items and update product stock
      for (final item in items) {
        // `SaleItem.create()` has no `saleId` param (items are built before
        // the sale's real id/invoice number is finalized above), so it's
        // never set on the object itself — stamp it into the row here.
        // Without this, `sale_items.sale_id` is silently NULL and every
        // by-sale lookup (`getItemsBySale`, Returns, Cancel, Exchange,
        // several reports) finds nothing for a real sale.
        final itemJson = item.toJson()..['sale_id'] = savedSale.id;
        await txn.insert('sale_items', itemJson);

        final productRows = await txn.query('products', where: 'id = ?', whereArgs: [item.productId], limit: 1);
        final product = productRows.isNotEmpty ? Product.fromJson(productRows.first) : null;

        if (product != null && product.isService) {
          // Non-inventory line (carry bag, delivery charge, ...) — nothing
          // to check or deduct, and no ledger entry since no stock moved.
        } else if (product != null && product.isKit) {
          // A kit's own stock_quantity is unused — deduct each component
          // instead, with the same atomic check-and-decrement guard used
          // below for a normal line, just run once per component.
          final components = await _kitRepo.getComponents(product.id, executor: txn);
          for (final component in components) {
            final requiredQty = component.quantity * item.quantity;
            final affected = await txn.rawUpdate(
              '''
              UPDATE products
              SET stock_quantity = stock_quantity - ?, updated_at = ?
              WHERE id = ? AND (stock_quantity >= ? OR allow_negative_stock = 1)
              ''',
              [
                requiredQty,
                DateTime.now().millisecondsSinceEpoch ~/ 1000,
                component.componentProductId,
                requiredQty,
              ],
            );
            if (affected == 0) {
              throw Exception(
                'Not enough stock of a kit component for "${product.displayName ?? product.name}" — it may have '
                'just sold out. Please re-check the cart.',
              );
            }
            await _stockGroupRepo.propagateDelta(component.componentProductId, -requiredQty, executor: txn);
            final componentLedger = StockLedger.create(
              productId: component.componentProductId,
              storeId: storeId,
              referenceType: 'sale_kit_component',
              referenceId: sale.id,
              quantityChange: -requiredQty,
              batchNo: null,
              expiryDate: null,
              costPrice: 0,
              sellingPrice: 0,
            );
            await txn.insert('stock_ledger', componentLedger.toJson());
          }
        } else {
          // Atomic check-and-decrement: the WHERE clause re-verifies stock
          // (or the per-product override) at the moment of the actual write,
          // not just when it was added to the cart earlier. If two sales
          // race for the last units, only one can win this UPDATE — the
          // other gets 0 rows affected and the whole sale rolls back instead
          // of silently pushing stock negative when that wasn't allowed.
          // (This checks the product-level override; the category-level
          // allowNegativeStock flag is still enforced at add-to-cart time in
          // the UI, just not duplicated here to keep this a single-table
          // UPDATE without a JOIN.)
          final affected = await txn.rawUpdate(
            '''
            UPDATE products
            SET stock_quantity = stock_quantity - ?, updated_at = ?
            WHERE id = ? AND (stock_quantity >= ? OR allow_negative_stock = 1)
            ''',
            [item.quantity, DateTime.now().millisecondsSinceEpoch ~/ 1000, item.productId, item.quantity],
          );
          if (affected == 0) {
            throw Exception(
              'Not enough stock for one of the items in this sale — it may have just sold out. Please re-check the cart.',
            );
          }
          await _stockGroupRepo.propagateDelta(item.productId, -item.quantity, executor: txn);

          // Insert stock ledger entry
          final ledger = StockLedger.create(
            productId: item.productId,
            storeId: storeId,
            referenceType: 'sale',
            referenceId: sale.id,
            quantityChange: -item.quantity,
            batchNo: null,
            expiryDate: null,
            costPrice: 0,
            sellingPrice: item.unitPrice,
          );
          await txn.insert('stock_ledger', ledger.toJson());
        }
      }

      // 3. Update customer loyalty points and outstanding balance
      if (customerId != null) {
        final customerResult = await txn.query(
          'customers',
          where: 'id = ?',
          whereArgs: [customerId],
        );
        if (customerResult.isNotEmpty) {
          final customer = Customer.fromJson(customerResult.first);

          if (sale.loyaltyPointsRedeemed > customer.loyaltyPoints) {
            throw Exception(
              'Cannot redeem ${sale.loyaltyPointsRedeemed} points — this customer only has ${customer.loyaltyPoints}.',
            );
          }

          // Tier thresholds live on `stores`, already fetched into
          // `storeRows` above for the invoice prefix — no second query.
          final storeRow = storeRows.isNotEmpty ? storeRows.first : <String, Object?>{};
          final bronzeMin = (storeRow['tier_bronze_min_spent'] as num?)?.toDouble() ?? 2000;
          final silverMin = (storeRow['tier_silver_min_spent'] as num?)?.toDouble() ?? 10000;
          final goldMin = (storeRow['tier_gold_min_spent'] as num?)?.toDouble() ?? 25000;

          // 1 point per bonusPointsThreshold spent — a real per-store
          // setting (`stores.bonus_points_threshold`, see StoreRepository)
          // rather than a hardcoded constant — multiplied by the customer's
          // *current* tier (before this sale's spend can bump them up), so
          // a sale that itself crosses a tier boundary still earns at the
          // old rate.
          final bonusPointsThreshold = (storeRow['bonus_points_threshold'] as num?)?.toDouble() ?? 300;
          final multiplier = pointMultiplierForRating(customer.effectiveRating);
          final pointsEarned = ((sale.netAmount / bonusPointsThreshold) * multiplier).floor();
          final pointsRedeemed = sale.loyaltyPointsRedeemed;
          final newTotalSpent = customer.totalSpent + sale.netAmount;
          final newRating = computeTier(
            totalSpent: newTotalSpent,
            bronzeMin: bronzeMin,
            silverMin: silverMin,
            goldMin: goldMin,
          );
          double newOutstanding = customer.outstandingBalance;

          if (sale.creditUsed != null && sale.creditUsed! > 0) {
            // A credit sale is money the customer now OWES more of — this
            // was previously subtracting, which meant buying on credit
            // silently reduced what they owed. Fixed to add.
            newOutstanding = customer.outstandingBalance + sale.creditUsed!;
          }

          if (sale.partialPaymentAmount != null && sale.partialPaymentAmount! > 0) {
            newOutstanding += sale.partialPaymentAmount!;
          }

          await txn.rawUpdate(
            '''
            UPDATE customers
            SET loyalty_points = loyalty_points + ? - ?,
                total_spent = total_spent + ?,
                outstanding_balance = ?,
                rating = ?,
                updated_at = ?
            WHERE id = ?
            ''',
            [
              pointsEarned,
              pointsRedeemed,
              sale.netAmount,
              newOutstanding,
              newRating.name,
              DateTime.now().millisecondsSinceEpoch ~/ 1000,
              customerId,
            ],
          );

          // First real writer `bonus_points` has ever had — the table
          // existed since the original schema but nothing wrote to it; the
          // running total on `customers.loyalty_points` was the only record.
          if (pointsEarned != 0 || pointsRedeemed != 0) {
            await txn.insert('bonus_points', {
              'id': const Uuid().v4(),
              'customer_id': customerId,
              'sale_id': sale.id,
              'points_earned': pointsEarned,
              'points_redeemed': pointsRedeemed,
              'date': DateTime.now().millisecondsSinceEpoch ~/ 1000,
            });
          }

          // Record the change on the customer's ledger too, not just the
          // running total field, so it shows up in their transaction
          // history (see CustomerLedgerRepository).
          final delta = newOutstanding - customer.outstandingBalance;
          if (delta != 0) {
            final ledgerEntry = CustomerLedger.create(
              customerId: customerId,
              referenceType: 'sale',
              referenceId: sale.id,
              amount: delta,
              balance: newOutstanding,
            );
            await txn.insert('customer_ledger', ledgerEntry.toJson());
          }
        }
      }

      // 4. General Ledger: debit Cash for what was taken at the till and
      // Accounts Receivable for whatever the customer still owes, credit
      // Sales Revenue for the bill. Posted with `txn`, so the ledger commits
      // or rolls back with the sale itself — a sale whose GL post fails (a
      // closed financial year, a missing chart of accounts) fails as a sale
      // rather than committing and leaving the books silently short. That
      // is the "side-effect inside the caller's transaction" pattern already
      // used above for stock, loyalty and sync.
      //
      // This sits in the repository rather than in BillingService because
      // this is where the sale actually becomes final, and it is the only
      // place every sale passes through — an exchange composes its
      // replacement sale by calling in here with its own `txn`, and would
      // never reach a post made in BillingService.processSale.
      //
      // `partialPaymentAmount` and `creditUsed` are the two ways this app
      // grows a customer's outstanding balance (see the customer update
      // above); their sum is exactly the receivable side of the sale.
      final receivable = (savedSale.creditUsed ?? 0) + (savedSale.partialPaymentAmount ?? 0);
      // `Sale.create` always stamps createdAt; the fallback only guards a
      // hand-built Sale left at the default 0, which would otherwise file the
      // entry under financial year 69-70.
      final saleDate = savedSale.createdAt > 0
          ? DateTime.fromMillisecondsSinceEpoch(savedSale.createdAt * 1000)
          : DateTime.now();
      await _glService.postSaleEntries(
        saleId: savedSale.id,
        saleDate: saleDate,
        netAmount: savedSale.netAmount,
        receivableAmount: receivable,
        description: 'Sale ${savedSale.invoiceDisplayNo ?? savedSale.invoiceNo}',
        createdBy: savedSale.userId,
        executor: txn,
      );

      // Fixed: pass `txn` so this write is part of the same atomic
      // transaction instead of racing it on a separate connection reference.
      await _dbHelper.queueSync('sales', savedSale.id, 'INSERT', savedSale.toJson(), executor: txn);
    }

    return savedSale;
  }

  /// Preview of what the next invoice number will be — for display only
  /// (e.g. the status bar). The number actually committed is decided
  /// transactionally inside [insertSaleWithItems], so this preview could in
  /// theory be stale if another sale completes in between, but for a
  /// single-cashier desktop app that's not a practical concern.
  Future<int> previewNextInvoiceNo() async {
    final db = await _dbHelper.database;
    final result = await db.rawQuery('SELECT MAX(invoice_no) as maxNo FROM sales');
    final maxNo = result.first['maxNo'] as int?;
    return (maxNo ?? 1000) + 1;
  }

  Future<List<Sale>> getRecent({int limit = 50}) async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'sales',
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return result.map((e) => Sale.fromJson(e)).toList();
  }

  /// Purchase history for a customer's detail screen, most recent first.
  Future<List<Sale>> getByCustomer(String customerId, {int limit = 100}) async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'sales',
      where: 'customer_id = ?',
      whereArgs: [customerId],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return result.map((e) => Sale.fromJson(e)).toList();
  }

  /// Sales within [start, end] (inclusive), oldest first — used by the
  /// Exports To Tally screen to scope a voucher export to a date range.
  Future<List<Sale>> getByDateRange(DateTime start, DateTime end) async {
    final db = await _dbHelper.database;
    final startSec = start.millisecondsSinceEpoch ~/ 1000;
    final endSec = end.millisecondsSinceEpoch ~/ 1000;
    final result = await db.query(
      'sales',
      where: 'created_at >= ? AND created_at <= ?',
      whereArgs: [startSec, endSec],
      orderBy: 'created_at ASC',
    );
    return result.map((e) => Sale.fromJson(e)).toList();
  }

  Future<Sale?> getById(String id) async {
    final db = await _dbHelper.database;
    final result = await db.query('sales', where: 'id = ?', whereArgs: [id]);
    if (result.isEmpty) return null;
    return Sale.fromJson(result.first);
  }

  Future<List<SaleItem>> getItemsBySale(String saleId) async {
    final db = await _dbHelper.database;
    final result = await db.query('sale_items', where: 'sale_id = ?', whereArgs: [saleId]);
    return result.map((e) => SaleItem.fromJson(e)).toList();
  }

  Future<double> getCashTotalBySession(String sessionId) async {
    final db = await _dbHelper.database;
    // Was summing the whole sale's net_amount regardless of how it was
    // paid — a ₹1,000 bill paid ₹400 cash + ₹600 UPI counted as ₹1,000
    // cash, which threw off shift-closing reconciliation. Now sums only
    // the actual cash portion recorded in each sale's payment_methods.
    final result = await db.query(
      'sales',
      columns: ['payment_methods'],
      where: 'session_id = ? AND status = ?',
      whereArgs: [sessionId, 'completed'],
    );
    double cashTotal = 0;
    for (final row in result) {
      final raw = row['payment_methods'] as String?;
      if (raw == null || raw.isEmpty) continue;
      try {
        final methods = Map<String, dynamic>.from(jsonDecode(raw));
        cashTotal += (methods['cash'] as num?)?.toDouble() ?? 0;
      } catch (_) {
        // Malformed/legacy row — skip rather than crash shift closing.
      }
    }
    return cashTotal;
  }
}

final saleRepositoryProvider = Provider<SaleRepository>((ref) {
  return SaleRepository();
});