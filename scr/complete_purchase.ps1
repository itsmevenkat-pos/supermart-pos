# complete_purchase.ps1 – Complete Purchase Module
$base = "lib"

$files = @{

    # ---------- PURCHASE MODEL (Enhanced) ----------
    "models/purchase_model.dart" = @'
import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

class Purchase extends Equatable {
  final String id;
  final String? storeId;
  final String? supplierId;
  final String grnNo;
  final int purchaseDate;
  final String? location;
  final String? supplierName;
  final String? supplierMerchant;
  final String? supplierAddress;
  final double total;
  final double billTotal;
  final double difference;
  final double accountPercent;
  final double account;
  final double taxRate;
  final double taxPercent;
  final double tax;
  final String? chess;
  final double netAmount;
  final String? transportStatus;
  final String? transport;
  final String? labourStatus;
  final double labourCharges;
  final double transportCharge;
  final int totalQty;
  final String? remarks;
  final bool received;
  final String? cForm;
  final String? dueStatus;
  final String? closeStatus;
  final int dueDate;
  final String status;
  final int synced;
  final int createdAt;
  final int? updatedAt;

  const Purchase({
    required this.id,
    this.storeId,
    this.supplierId,
    this.grnNo = '',
    this.purchaseDate = 0,
    this.location,
    this.supplierName,
    this.supplierMerchant,
    this.supplierAddress,
    this.total = 0,
    this.billTotal = 0,
    this.difference = 0,
    this.accountPercent = 0,
    this.account = 0,
    this.taxRate = 0,
    this.taxPercent = 0,
    this.tax = 0,
    this.chess,
    this.netAmount = 0,
    this.transportStatus,
    this.transport,
    this.labourStatus,
    this.labourCharges = 0,
    this.transportCharge = 0,
    this.totalQty = 0,
    this.remarks,
    this.received = false,
    this.cForm,
    this.dueStatus,
    this.closeStatus,
    this.dueDate = 0,
    this.status = 'received',
    this.synced = 0,
    this.createdAt = 0,
    this.updatedAt,
  });

  factory Purchase.create({
    String? storeId,
    String? supplierId,
    String grnNo = '',
    int purchaseDate = 0,
    String? location,
    String? supplierName,
    String? supplierMerchant,
    String? supplierAddress,
    double total = 0,
    double billTotal = 0,
    double difference = 0,
    double accountPercent = 0,
    double account = 0,
    double taxRate = 0,
    double taxPercent = 0,
    double tax = 0,
    String? chess,
    double netAmount = 0,
    String? transportStatus,
    String? transport,
    String? labourStatus,
    double labourCharges = 0,
    double transportCharge = 0,
    int totalQty = 0,
    String? remarks,
    bool received = false,
    String? cForm,
    String? dueStatus,
    String? closeStatus,
    int dueDate = 0,
    String status = 'received',
  }) {
    return Purchase(
      id: const Uuid().v4(),
      storeId: storeId,
      supplierId: supplierId,
      grnNo: grnNo.isNotEmpty ? grnNo : 'GRN-${DateTime.now().millisecondsSinceEpoch}',
      purchaseDate: purchaseDate,
      location: location,
      supplierName: supplierName,
      supplierMerchant: supplierMerchant,
      supplierAddress: supplierAddress,
      total: total,
      billTotal: billTotal,
      difference: difference,
      accountPercent: accountPercent,
      account: account,
      taxRate: taxRate,
      taxPercent: taxPercent,
      tax: tax,
      chess: chess,
      netAmount: netAmount,
      transportStatus: transportStatus,
      transport: transport,
      labourStatus: labourStatus,
      labourCharges: labourCharges,
      transportCharge: transportCharge,
      totalQty: totalQty,
      remarks: remarks,
      received: received,
      cForm: cForm,
      dueStatus: dueStatus,
      closeStatus: closeStatus,
      dueDate: dueDate,
      status: status,
    );
  }

  Purchase copyWith({
    String? grnNo,
    int? purchaseDate,
    String? location,
    String? supplierName,
    String? supplierMerchant,
    String? supplierAddress,
    double? total,
    double? billTotal,
    double? difference,
    double? accountPercent,
    double? account,
    double? taxRate,
    double? taxPercent,
    double? tax,
    String? chess,
    double? netAmount,
    String? transportStatus,
    String? transport,
    String? labourStatus,
    double? labourCharges,
    double? transportCharge,
    int? totalQty,
    String? remarks,
    bool? received,
    String? cForm,
    String? dueStatus,
    String? closeStatus,
    int? dueDate,
    String? status,
  }) {
    return Purchase(
      id: id,
      storeId: storeId,
      supplierId: supplierId,
      grnNo: grnNo ?? this.grnNo,
      purchaseDate: purchaseDate ?? this.purchaseDate,
      location: location ?? this.location,
      supplierName: supplierName ?? this.supplierName,
      supplierMerchant: supplierMerchant ?? this.supplierMerchant,
      supplierAddress: supplierAddress ?? this.supplierAddress,
      total: total ?? this.total,
      billTotal: billTotal ?? this.billTotal,
      difference: difference ?? this.difference,
      accountPercent: accountPercent ?? this.accountPercent,
      account: account ?? this.account,
      taxRate: taxRate ?? this.taxRate,
      taxPercent: taxPercent ?? this.taxPercent,
      tax: tax ?? this.tax,
      chess: chess ?? this.chess,
      netAmount: netAmount ?? this.netAmount,
      transportStatus: transportStatus ?? this.transportStatus,
      transport: transport ?? this.transport,
      labourStatus: labourStatus ?? this.labourStatus,
      labourCharges: labourCharges ?? this.labourCharges,
      transportCharge: transportCharge ?? this.transportCharge,
      totalQty: totalQty ?? this.totalQty,
      remarks: remarks ?? this.remarks,
      received: received ?? this.received,
      cForm: cForm ?? this.cForm,
      dueStatus: dueStatus ?? this.dueStatus,
      closeStatus: closeStatus ?? this.closeStatus,
      dueDate: dueDate ?? this.dueDate,
      status: status ?? this.status,
      updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'store_id': storeId,
        'supplier_id': supplierId,
        'grn_no': grnNo,
        'purchase_date': purchaseDate,
        'location': location,
        'supplier_name': supplierName,
        'supplier_merchant': supplierMerchant,
        'supplier_address': supplierAddress,
        'total': total,
        'bill_total': billTotal,
        'difference': difference,
        'account_percent': accountPercent,
        'account': account,
        'tax_rate': taxRate,
        'tax_percent': taxPercent,
        'tax': tax,
        'chess': chess,
        'net_amount': netAmount,
        'transport_status': transportStatus,
        'transport': transport,
        'labour_status': labourStatus,
        'labour_charges': labourCharges,
        'transport_charge': transportCharge,
        'total_qty': totalQty,
        'remarks': remarks,
        'received': received ? 1 : 0,
        'c_form': cForm,
        'due_status': dueStatus,
        'close_status': closeStatus,
        'due_date': dueDate,
        'status': status,
        'synced': synced,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory Purchase.fromJson(Map<String, dynamic> map) => Purchase(
        id: map['id'] as String,
        storeId: map['store_id'] as String?,
        supplierId: map['supplier_id'] as String?,
        grnNo: map['grn_no'] as String? ?? '',
        purchaseDate: map['purchase_date'] as int? ?? 0,
        location: map['location'] as String?,
        supplierName: map['supplier_name'] as String?,
        supplierMerchant: map['supplier_merchant'] as String?,
        supplierAddress: map['supplier_address'] as String?,
        total: (map['total'] as num?)?.toDouble() ?? 0,
        billTotal: (map['bill_total'] as num?)?.toDouble() ?? 0,
        difference: (map['difference'] as num?)?.toDouble() ?? 0,
        accountPercent: (map['account_percent'] as num?)?.toDouble() ?? 0,
        account: (map['account'] as num?)?.toDouble() ?? 0,
        taxRate: (map['tax_rate'] as num?)?.toDouble() ?? 0,
        taxPercent: (map['tax_percent'] as num?)?.toDouble() ?? 0,
        tax: (map['tax'] as num?)?.toDouble() ?? 0,
        chess: map['chess'] as String?,
        netAmount: (map['net_amount'] as num?)?.toDouble() ?? 0,
        transportStatus: map['transport_status'] as String?,
        transport: map['transport'] as String?,
        labourStatus: map['labour_status'] as String?,
        labourCharges: (map['labour_charges'] as num?)?.toDouble() ?? 0,
        transportCharge: (map['transport_charge'] as num?)?.toDouble() ?? 0,
        totalQty: map['total_qty'] as int? ?? 0,
        remarks: map['remarks'] as String?,
        received: (map['received'] as int?) == 1,
        cForm: map['c_form'] as String?,
        dueStatus: map['due_status'] as String?,
        closeStatus: map['close_status'] as String?,
        dueDate: map['due_date'] as int? ?? 0,
        status: map['status'] as String? ?? 'received',
        synced: map['synced'] as int? ?? 0,
        createdAt: map['created_at'] as int? ?? 0,
        updatedAt: map['updated_at'] as int?,
      );

  @override
  List<Object?> get props => [id, grnNo, supplierId, netAmount, status];
}
'@

    # ---------- PURCHASE ITEM MODEL (Enhanced) ----------
    "models/purchase_item_model.dart" = @'
import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

class PurchaseItem extends Equatable {
  final String id;
  final String? purchaseId;
  final String productId;
  final String? barcode;
  final String? productName;
  final double mrp;
  final int quantity;
  final double dozAmt;
  final double purchasePrice;
  final double discount;
  final double taxPercent;
  final double netRate;
  final double costPrice;
  final double profit;
  final double margin;
  final double last;
  final double lastMargin;
  final double salesPrice;
  final double total;
  final bool isRepack;
  final double bulkQuantity;
  final String? bulkUnit;
  final double packSize;
  final String? packUnit;
  final int packCount;
  final String? batchNo;
  final int? expiryDate;
  final int freeQuantity;
  final double taxAmount;
  final double discountAmount;

  const PurchaseItem({
    required this.id,
    this.purchaseId,
    required this.productId,
    this.barcode,
    this.productName,
    this.mrp = 0,
    this.quantity = 1,
    this.dozAmt = 0,
    this.purchasePrice = 0,
    this.discount = 0,
    this.taxPercent = 0,
    this.netRate = 0,
    this.costPrice = 0,
    this.profit = 0,
    this.margin = 0,
    this.last = 0,
    this.lastMargin = 0,
    this.salesPrice = 0,
    this.total = 0,
    this.isRepack = false,
    this.bulkQuantity = 0,
    this.bulkUnit,
    this.packSize = 0,
    this.packUnit,
    this.packCount = 0,
    this.batchNo,
    this.expiryDate,
    this.freeQuantity = 0,
    this.taxAmount = 0,
    this.discountAmount = 0,
  });

  factory PurchaseItem.create({
    required String productId,
    String? barcode,
    String? productName,
    double mrp = 0,
    int quantity = 1,
    double dozAmt = 0,
    double purchasePrice = 0,
    double discount = 0,
    double taxPercent = 0,
    double netRate = 0,
    double costPrice = 0,
    double profit = 0,
    double margin = 0,
    double last = 0,
    double lastMargin = 0,
    double salesPrice = 0,
    double total = 0,
    bool isRepack = false,
    double bulkQuantity = 0,
    String? bulkUnit,
    double packSize = 0,
    String? packUnit,
    int packCount = 0,
    String? batchNo,
    int? expiryDate,
    int freeQuantity = 0,
    double taxAmount = 0,
    double discountAmount = 0,
  }) {
    return PurchaseItem(
      id: const Uuid().v4(),
      productId: productId,
      barcode: barcode,
      productName: productName,
      mrp: mrp,
      quantity: quantity,
      dozAmt: dozAmt,
      purchasePrice: purchasePrice,
      discount: discount,
      taxPercent: taxPercent,
      netRate: netRate,
      costPrice: costPrice,
      profit: profit,
      margin: margin,
      last: last,
      lastMargin: lastMargin,
      salesPrice: salesPrice,
      total: total,
      isRepack: isRepack,
      bulkQuantity: bulkQuantity,
      bulkUnit: bulkUnit,
      packSize: packSize,
      packUnit: packUnit,
      packCount: packCount,
      batchNo: batchNo,
      expiryDate: expiryDate,
      freeQuantity: freeQuantity,
      taxAmount: taxAmount,
      discountAmount: discountAmount,
    );
  }

  PurchaseItem copyWith({
    int? quantity,
    double? purchasePrice,
    double? discount,
    double? taxPercent,
    double? netRate,
    double? costPrice,
    double? salesPrice,
    double? total,
    double? mrp,
    double? dozAmt,
    double? profit,
    double? margin,
    double? last,
    double? lastMargin,
    bool? isRepack,
    double? bulkQuantity,
    String? bulkUnit,
    double? packSize,
    String? packUnit,
    int? packCount,
    String? batchNo,
    int? expiryDate,
  }) {
    return PurchaseItem(
      id: id,
      purchaseId: purchaseId,
      productId: productId,
      barcode: barcode,
      productName: productName,
      mrp: mrp ?? this.mrp,
      quantity: quantity ?? this.quantity,
      dozAmt: dozAmt ?? this.dozAmt,
      purchasePrice: purchasePrice ?? this.purchasePrice,
      discount: discount ?? this.discount,
      taxPercent: taxPercent ?? this.taxPercent,
      netRate: netRate ?? this.netRate,
      costPrice: costPrice ?? this.costPrice,
      profit: profit ?? this.profit,
      margin: margin ?? this.margin,
      last: last ?? this.last,
      lastMargin: lastMargin ?? this.lastMargin,
      salesPrice: salesPrice ?? this.salesPrice,
      total: total ?? this.total,
      isRepack: isRepack ?? this.isRepack,
      bulkQuantity: bulkQuantity ?? this.bulkQuantity,
      bulkUnit: bulkUnit ?? this.bulkUnit,
      packSize: packSize ?? this.packSize,
      packUnit: packUnit ?? this.packUnit,
      packCount: packCount ?? this.packCount,
      batchNo: batchNo ?? this.batchNo,
      expiryDate: expiryDate ?? this.expiryDate,
      freeQuantity: freeQuantity,
      taxAmount: taxAmount,
      discountAmount: discountAmount,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'purchase_id': purchaseId,
        'product_id': productId,
        'barcode': barcode,
        'product_name': productName,
        'mrp': mrp,
        'quantity': quantity,
        'doz_amt': dozAmt,
        'purchase_price': purchasePrice,
        'discount': discount,
        'tax_percent': taxPercent,
        'net_rate': netRate,
        'cost_price': costPrice,
        'profit': profit,
        'margin': margin,
        'last': last,
        'last_margin': lastMargin,
        'sales_price': salesPrice,
        'total': total,
        'is_repack': isRepack ? 1 : 0,
        'bulk_quantity': bulkQuantity,
        'bulk_unit': bulkUnit,
        'pack_size': packSize,
        'pack_unit': packUnit,
        'pack_count': packCount,
        'batch_no': batchNo,
        'expiry_date': expiryDate,
        'free_quantity': freeQuantity,
        'tax_amount': taxAmount,
        'discount_amount': discountAmount,
      };

  factory PurchaseItem.fromJson(Map<String, dynamic> map) => PurchaseItem(
        id: map['id'] as String,
        purchaseId: map['purchase_id'] as String?,
        productId: map['product_id'] as String,
        barcode: map['barcode'] as String?,
        productName: map['product_name'] as String?,
        mrp: (map['mrp'] as num?)?.toDouble() ?? 0,
        quantity: map['quantity'] as int? ?? 1,
        dozAmt: (map['doz_amt'] as num?)?.toDouble() ?? 0,
        purchasePrice: (map['purchase_price'] as num?)?.toDouble() ?? 0,
        discount: (map['discount'] as num?)?.toDouble() ?? 0,
        taxPercent: (map['tax_percent'] as num?)?.toDouble() ?? 0,
        netRate: (map['net_rate'] as num?)?.toDouble() ?? 0,
        costPrice: (map['cost_price'] as num?)?.toDouble() ?? 0,
        profit: (map['profit'] as num?)?.toDouble() ?? 0,
        margin: (map['margin'] as num?)?.toDouble() ?? 0,
        last: (map['last'] as num?)?.toDouble() ?? 0,
        lastMargin: (map['last_margin'] as num?)?.toDouble() ?? 0,
        salesPrice: (map['sales_price'] as num?)?.toDouble() ?? 0,
        total: (map['total'] as num?)?.toDouble() ?? 0,
        isRepack: (map['is_repack'] as int?) == 1,
        bulkQuantity: (map['bulk_quantity'] as num?)?.toDouble() ?? 0,
        bulkUnit: map['bulk_unit'] as String?,
        packSize: (map['pack_size'] as num?)?.toDouble() ?? 0,
        packUnit: map['pack_unit'] as String?,
        packCount: map['pack_count'] as int? ?? 0,
        batchNo: map['batch_no'] as String?,
        expiryDate: map['expiry_date'] as int?,
        freeQuantity: map['free_quantity'] as int? ?? 0,
        taxAmount: (map['tax_amount'] as num?)?.toDouble() ?? 0,
        discountAmount: (map['discount_amount'] as num?)?.toDouble() ?? 0,
      );

  @override
  List<Object?> get props => [id, productId, quantity, purchasePrice, total];
}
'@

    # ---------- PURCHASE REPOSITORY (Complete) ----------
    "repositories/purchase_repository.dart" = @'
import '../core/database/database_helper.dart';
import '../models/purchase_model.dart';
import '../models/purchase_item_model.dart';
import '../models/stock_ledger_model.dart';
import '../models/supplier_ledger_model.dart';
import 'stock_ledger_repository.dart';
import 'supplier_ledger_repository.dart';

class PurchaseRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final StockLedgerRepository _ledgerRepo = StockLedgerRepository();
  final SupplierLedgerRepository _supplierLedgerRepo = SupplierLedgerRepository();

  Future<void> insertWithItems(Purchase purchase, List<PurchaseItem> items) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      // 1. Insert purchase header
      await txn.insert('purchases', purchase.toJson());

      // 2. Insert purchase items and update products
      for (final item in items) {
        await txn.insert('purchase_items', item.toJson());

        // Determine stock quantity to add
        int stockQtyToAdd;
        double costPriceToSet;

        if (item.isRepack) {
          stockQtyToAdd = item.packCount;
          costPriceToSet = item.purchasePrice;
        } else {
          stockQtyToAdd = item.quantity + item.freeQuantity;
          costPriceToSet = item.purchasePrice;
        }

        // Update product stock, cost price, selling price, MRP
        await txn.rawUpdate('''
          UPDATE products 
          SET stock_quantity = stock_quantity + ?,
              cost_price = ?,
              selling_price = ?,
              mrp = ?,
              updated_at = ?
          WHERE id = ?
        ''', [
          stockQtyToAdd,
          costPriceToSet,
          item.salesPrice,
          item.mrp,
          DateTime.now().millisecondsSinceEpoch ~/ 1000,
          item.productId,
        ]);

        // Insert stock ledger
        final ledger = StockLedger.create(
          productId: item.productId,
          storeId: purchase.storeId!,
          referenceType: 'purchase',
          referenceId: purchase.id,
          quantityChange: stockQtyToAdd,
          batchNo: item.batchNo,
          expiryDate: item.expiryDate,
          costPrice: costPriceToSet,
          sellingPrice: item.salesPrice,
        );
        await _ledgerRepo.insert(ledger);
      }

      // 3. Update supplier ledger
      final currentBalance = await _supplierLedgerRepo.getBalance(purchase.supplierId!);
      final newBalance = currentBalance + purchase.netAmount;
      final supplierLedger = SupplierLedger.create(
        supplierId: purchase.supplierId!,
        referenceType: 'purchase',
        referenceId: purchase.id,
        amount: purchase.netAmount,
        balance: newBalance,
      );
      await _supplierLedgerRepo.insert(supplierLedger);

      // 4. Queue sync
      await _dbHelper.queueSync('purchases', purchase.id, 'INSERT', purchase.toJson());
    });
  }

  Future<void> updateWithItems(Purchase purchase, List<PurchaseItem> items) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      // Get old items to reverse stock
      final oldItemsResult = await txn.query('purchase_items', where: 'purchase_id = ?', whereArgs: [purchase.id]);
      final oldItems = oldItemsResult.map((e) => PurchaseItem.fromJson(e)).toList();

      // Reverse old stock
      for (final oldItem in oldItems) {
        int stockQtyToRemove;
        if (oldItem.isRepack) {
          stockQtyToRemove = oldItem.packCount;
        } else {
          stockQtyToRemove = oldItem.quantity + oldItem.freeQuantity;
        }
        await txn.rawUpdate('''
          UPDATE products 
          SET stock_quantity = stock_quantity - ?
          WHERE id = ?
        ''', [stockQtyToRemove, oldItem.productId]);
      }

      // Delete old items
      await txn.delete('purchase_items', where: 'purchase_id = ?', whereArgs: [purchase.id]);

      // Update purchase header
      await txn.update('purchases', purchase.toJson(), where: 'id = ?', whereArgs: [purchase.id]);

      // Insert new items and update stock
      for (final item in items) {
        await txn.insert('purchase_items', item.toJson());

        int stockQtyToAdd;
        double costPriceToSet;
        if (item.isRepack) {
          stockQtyToAdd = item.packCount;
          costPriceToSet = item.purchasePrice;
        } else {
          stockQtyToAdd = item.quantity + item.freeQuantity;
          costPriceToSet = item.purchasePrice;
        }

        await txn.rawUpdate('''
          UPDATE products 
          SET stock_quantity = stock_quantity + ?,
              cost_price = ?,
              selling_price = ?,
              mrp = ?,
              updated_at = ?
          WHERE id = ?
        ''', [
          stockQtyToAdd,
          costPriceToSet,
          item.salesPrice,
          item.mrp,
          DateTime.now().millisecondsSinceEpoch ~/ 1000,
          item.productId,
        ]);

        final ledger = StockLedger.create(
          productId: item.productId,
          storeId: purchase.storeId!,
          referenceType: 'purchase',
          referenceId: purchase.id,
          quantityChange: stockQtyToAdd,
          batchNo: item.batchNo,
          expiryDate: item.expiryDate,
          costPrice: costPriceToSet,
          sellingPrice: item.salesPrice,
        );
        await _ledgerRepo.insert(ledger);
      }

      // Update supplier ledger (remove old, add new)
      await txn.delete('supplier_ledger', where: 'reference_id = ? AND reference_type = "purchase"', whereArgs: [purchase.id]);
      final currentBalance = await _supplierLedgerRepo.getBalance(purchase.supplierId!);
      final newBalance = currentBalance + purchase.netAmount;
      final supplierLedger = SupplierLedger.create(
        supplierId: purchase.supplierId!,
        referenceType: 'purchase',
        referenceId: purchase.id,
        amount: purchase.netAmount,
        balance: newBalance,
      );
      await _supplierLedgerRepo.insert(supplierLedger);

      await _dbHelper.queueSync('purchases', purchase.id, 'UPDATE', purchase.toJson());
    });
  }

  Future<List<Purchase>> getAll({int limit = 100}) async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'purchases',
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return result.map((e) => Purchase.fromJson(e)).toList();
  }

  Future<Purchase?> getByGrn(String grnNo) async {
    final db = await _dbHelper.database;
    final result = await db.query('purchases', where: 'grn_no = ?', whereArgs: [grnNo]);
    if (result.isEmpty) return null;
    return Purchase.fromJson(result.first);
  }

  Future<Purchase?> getById(String id) async {
    final db = await _dbHelper.database;
    final result = await db.query('purchases', where: 'id = ?', whereArgs: [id]);
    if (result.isEmpty) return null;
    return Purchase.fromJson(result.first);
  }

  Future<List<PurchaseItem>> getItemsByPurchase(String purchaseId) async {
    final db = await _dbHelper.database;
    final result = await db.query('purchase_items', where: 'purchase_id = ?', whereArgs: [purchaseId]);
    return result.map((e) => PurchaseItem.fromJson(e)).toList();
  }

  Future<void> delete(String id) async {
    final db = await _dbHelper.database;
    await db.delete('purchases', where: 'id = ?', whereArgs: [id]);
  }
}
'@

    # ---------- PURCHASE PROVIDER ----------
    "providers/purchase_provider.dart" = @'
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../models/purchase_model.dart';
import '../models/purchase_item_model.dart';
import '../repositories/purchase_repository.dart';

part 'purchase_provider.g.dart';

@riverpod
class PurchaseNotifier extends _$PurchaseNotifier {
  final PurchaseRepository _repo = PurchaseRepository();

  @override
  Future<List<Purchase>> build() async {
    return await _repo.getAll();
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
  }

  Future<Purchase?> getById(String id) async {
    return await _repo.getById(id);
  }

  Future<List<PurchaseItem>> getItems(String purchaseId) async {
    return await _repo.getItemsByPurchase(purchaseId);
  }

  Future<void> createPurchase(Purchase purchase, List<PurchaseItem> items) async {
    await _repo.insertWithItems(purchase, items);
    ref.invalidateSelf();
  }

  Future<void> updatePurchase(Purchase purchase, List<PurchaseItem> items) async {
    await _repo.updateWithItems(purchase, items);
    ref.invalidateSelf();
  }

  Future<void> deletePurchase(String id) async {
    await _repo.delete(id);
    ref.invalidateSelf();
  }

  Future<Purchase?> getByGrn(String grnNo) async {
    return await _repo.getByGrn(grnNo);
  }
}
'@

    # ---------- PURCHASE LIST SCREEN ----------
    "features/purchases/screens/purchase_list_screen.dart" = @'
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../providers/purchase_provider.dart';
import '../../../models/purchase_model.dart';
import 'purchase_form_screen.dart';

class PurchaseListScreen extends ConsumerStatefulWidget {
  const PurchaseListScreen({super.key});

  @override
  ConsumerState<PurchaseListScreen> createState() => _PurchaseListScreenState();
}

class _PurchaseListScreenState extends ConsumerState<PurchaseListScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final purchasesAsync = ref.watch(purchaseNotifierProvider);

    return AppScaffold(
      title: 'Purchases',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () => ref.read(purchaseNotifierProvider.notifier).refresh(),
        ),
      ],
      floatingActionButton: FloatingActionButton(
        onPressed: () => _navigateToForm(),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Search by GRN or supplier',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                setState(() {});
              },
            ),
          ),
          Expanded(
            child: purchasesAsync.when(
              data: (purchases) {
                final filtered = _searchController.text.isEmpty
                    ? purchases
                    : purchases.where((p) =>
                        p.grnNo.contains(_searchController.text) ||
                        (p.supplierName ?? '').contains(_searchController.text)).toList();
                if (filtered.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.receipt_long, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text('No purchases found'),
                        SizedBox(height: 8),
                        Text('Tap + to record a new purchase'),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (_, index) {
                    final p = filtered[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: ListTile(
                        leading: const Icon(Icons.receipt),
                        title: Text('GRN: ${p.grnNo}'),
                        subtitle: Text(
                          'Supplier: ${p.supplierName ?? "N/A"} | ₹${p.netAmount.toStringAsFixed(2)} | Qty: ${p.totalQty}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: p.received ? Colors.green : Colors.orange,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                p.received ? 'Received' : 'Pending',
                                style: const TextStyle(fontSize: 10, color: Colors.white),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit, size: 20),
                              onPressed: () => _navigateToForm(p),
                            ),
                          ],
                        ),
                        onTap: () => _navigateToForm(p),
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => Center(child: Text('Error: $err')),
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToForm([Purchase? purchase]) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PurchaseFormScreen(existingPurchase: purchase),
      ),
    ).then((_) => ref.read(purchaseNotifierProvider.notifier).refresh());
  }
}
'@

    # ---------- PURCHASE FORM SCREEN (Complete) ----------
    "features/purchases/screens/purchase_form_screen.dart" = @'
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../models/purchase_model.dart';
import '../../../models/purchase_item_model.dart';
import '../../../models/product_model.dart';
import '../../../models/supplier_model.dart';
import '../../../providers/purchase_provider.dart';
import '../../../providers/product_provider.dart';
import '../../../providers/supplier_provider.dart';
import '../../../repositories/purchase_repository.dart';
import '../../../services/gst_service.dart';

class PurchaseFormScreen extends ConsumerStatefulWidget {
  final Purchase? existingPurchase;

  const PurchaseFormScreen({super.key, this.existingPurchase});

  @override
  ConsumerState<PurchaseFormScreen> createState() => _PurchaseFormScreenState();
}

class _PurchaseFormScreenState extends ConsumerState<PurchaseFormScreen> {
  final _formKey = GlobalKey<FormState>();

  // Header fields
  late final TextEditingController _grnController;
  late final TextEditingController _dateController;
  late final TextEditingController _locationController;

  // Supplier fields
  Supplier? _selectedSupplier;
  late final TextEditingController _supplierNameController;
  late final TextEditingController _merchantController;
  late final TextEditingController _addressController;

  // Financial fields
  late final TextEditingController _totalController;
  late final TextEditingController _billTotalController;
  late final TextEditingController _differenceController;
  late final TextEditingController _accountPercentController;
  late final TextEditingController _accountController;
  late final TextEditingController _taxRateController;
  late final TextEditingController _taxPercentController;
  late final TextEditingController _taxController;
  late final TextEditingController _chessController;
  late final TextEditingController _netAmountController;

  // Logistics
  late final TextEditingController _transportStatusController;
  late final TextEditingController _transportController;
  late final TextEditingController _labourStatusController;
  late final TextEditingController _labourChargesController;
  late final TextEditingController _transportChargeController;

  // Other
  late final TextEditingController _totalQtyController;
  late final TextEditingController _remarksController;
  bool _received = false;
  late final TextEditingController _cFormController;
  late final TextEditingController _dueStatusController;
  late final TextEditingController _closeStatusController;
  late final TextEditingController _dueDateController;

  // Items
  List<PurchaseItem> _items = [];
  final TextEditingController _productSearchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  // GST Service
  final GstService _gstService = GstService();

  @override
  void initState() {
    super.initState();

    final p = widget.existingPurchase;

    _grnController = TextEditingController(text: p?.grnNo ?? '');
    _dateController = TextEditingController(
      text: p != null
          ? DateTime.fromMillisecondsSinceEpoch(p.purchaseDate * 1000)
              .toLocal()
              .toString()
              .split(' ')[0]
          : DateTime.now().toLocal().toString().split(' ')[0],
    );
    _locationController = TextEditingController(text: p?.location ?? '');

    _supplierNameController = TextEditingController(text: p?.supplierName ?? '');
    _merchantController = TextEditingController(text: p?.supplierMerchant ?? '');
    _addressController = TextEditingController(text: p?.supplierAddress ?? '');

    _totalController = TextEditingController(text: p?.total.toString() ?? '0');
    _billTotalController = TextEditingController(text: p?.billTotal.toString() ?? '0');
    _differenceController = TextEditingController(text: p?.difference.toString() ?? '0');
    _accountPercentController = TextEditingController(text: p?.accountPercent.toString() ?? '0');
    _accountController = TextEditingController(text: p?.account.toString() ?? '0');
    _taxRateController = TextEditingController(text: p?.taxRate.toString() ?? '0');
    _taxPercentController = TextEditingController(text: p?.taxPercent.toString() ?? '0');
    _taxController = TextEditingController(text: p?.tax.toString() ?? '0');
    _chessController = TextEditingController(text: p?.chess ?? '');
    _netAmountController = TextEditingController(text: p?.netAmount.toString() ?? '0');

    _transportStatusController = TextEditingController(text: p?.transportStatus ?? '');
    _transportController = TextEditingController(text: p?.transport ?? '');
    _labourStatusController = TextEditingController(text: p?.labourStatus ?? '');
    _labourChargesController = TextEditingController(text: p?.labourCharges.toString() ?? '0');
    _transportChargeController = TextEditingController(text: p?.transportCharge.toString() ?? '0');

    _totalQtyController = TextEditingController(text: p?.totalQty.toString() ?? '0');
    _remarksController = TextEditingController(text: p?.remarks ?? '');
    _received = p?.received ?? false;
    _cFormController = TextEditingController(text: p?.cForm ?? '');
    _dueStatusController = TextEditingController(text: p?.dueStatus ?? '');
    _closeStatusController = TextEditingController(text: p?.closeStatus ?? '');
    _dueDateController = TextEditingController(
      text: p != null && p.dueDate > 0
          ? DateTime.fromMillisecondsSinceEpoch(p.dueDate * 1000)
              .toLocal()
              .toString()
              .split(' ')[0]
          : '',
    );

    if (p != null) {
      _loadItems(p.id);
    }

    _billTotalController.addListener(_recalculate);
    _totalController.addListener(_recalculate);
    _accountPercentController.addListener(_recalculate);
    _taxRateController.addListener(_recalculate);
  }

  @override
  void dispose() {
    _grnController.dispose();
    _dateController.dispose();
    _locationController.dispose();
    _supplierNameController.dispose();
    _merchantController.dispose();
    _addressController.dispose();
    _totalController.dispose();
    _billTotalController.dispose();
    _differenceController.dispose();
    _accountPercentController.dispose();
    _accountController.dispose();
    _taxRateController.dispose();
    _taxPercentController.dispose();
    _taxController.dispose();
    _chessController.dispose();
    _netAmountController.dispose();
    _transportStatusController.dispose();
    _transportController.dispose();
    _labourStatusController.dispose();
    _labourChargesController.dispose();
    _transportChargeController.dispose();
    _totalQtyController.dispose();
    _remarksController.dispose();
    _cFormController.dispose();
    _dueStatusController.dispose();
    _closeStatusController.dispose();
    _dueDateController.dispose();
    _productSearchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _loadItems(String purchaseId) async {
    final repo = PurchaseRepository();
    final items = await repo.getItemsByPurchase(purchaseId);
    setState(() {
      _items = items;
    });
    _recalculate();
  }

  void _addProduct(Product product) {
    final existing = _items.firstWhere(
      (i) => i.productId == product.id,
      orElse: () => null,
    );
    if (existing != null) {
      final index = _items.indexOf(existing);
      _items[index] = existing.copyWith(quantity: existing.quantity + 1);
      setState(() {});
      _recalculate();
      return;
    }

    _items.add(PurchaseItem.create(
      productId: product.id,
      barcode: product.barcode,
      productName: product.name,
      mrp: product.mrp,
      quantity: 1,
      purchasePrice: product.costPrice,
      salesPrice: product.sellingPrice,
      costPrice: product.costPrice,
      taxPercent: product.taxRate,
      last: product.costPrice,
    ));
    setState(() {});
    _recalculate();
  }

  void _removeItem(int index) {
    _items.removeAt(index);
    setState(() {});
    _recalculate();
  }

  void _updateItem(int index, PurchaseItem newItem) {
    _items[index] = newItem;
    setState(() {});
    _recalculate();
  }

  void _recalculate() {
    double stockTotal = 0;
    int totalQty = 0;

    for (final item in _items) {
      double effectiveQty = item.isRepack ? item.packCount.toDouble() : item.quantity.toDouble();
      final lineTotal = item.purchasePrice * effectiveQty;
      stockTotal += lineTotal;
      totalQty += effectiveQty.toInt();
    }

    final billTotal = double.tryParse(_billTotalController.text) ?? 0;
    final diff = billTotal - stockTotal;
    _differenceController.text = diff.toStringAsFixed(2);
    _totalController.text = stockTotal.toStringAsFixed(2);

    final accountPercent = double.tryParse(_accountPercentController.text) ?? 0;
    final account = (stockTotal * accountPercent) / 100;
    _accountController.text = account.toStringAsFixed(2);

    final taxRate = double.tryParse(_taxRateController.text) ?? 0;
    final tax = (stockTotal - account) * (taxRate / 100);
    _taxController.text = tax.toStringAsFixed(2);

    final netAmount = stockTotal - account + tax;
    _netAmountController.text = netAmount.toStringAsFixed(2);
    _totalQtyController.text = totalQty.toString();
  }

  Future<void> _save() async {
    if (_selectedSupplier == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a supplier'), backgroundColor: Colors.red),
      );
      return;
    }

    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one product'), backgroundColor: Colors.red),
      );
      return;
    }

    final purchase = Purchase.create(
      storeId: 'store_default',
      supplierId: _selectedSupplier!.id,
      grnNo: _grnController.text.trim(),
      purchaseDate: _dateController.text.isNotEmpty
          ? DateTime.parse(_dateController.text).millisecondsSinceEpoch ~/ 1000
          : DateTime.now().millisecondsSinceEpoch ~/ 1000,
      location: _locationController.text.trim(),
      supplierName: _selectedSupplier!.name,
      supplierMerchant: _merchantController.text.trim(),
      supplierAddress: _addressController.text.trim(),
      total: double.tryParse(_totalController.text) ?? 0,
      billTotal: double.tryParse(_billTotalController.text) ?? 0,
      difference: double.tryParse(_differenceController.text) ?? 0,
      accountPercent: double.tryParse(_accountPercentController.text) ?? 0,
      account: double.tryParse(_accountController.text) ?? 0,
      taxRate: double.tryParse(_taxRateController.text) ?? 0,
      taxPercent: double.tryParse(_taxPercentController.text) ?? 0,
      tax: double.tryParse(_taxController.text) ?? 0,
      chess: _chessController.text.trim().isNotEmpty ? _chessController.text.trim() : null,
      netAmount: double.tryParse(_netAmountController.text) ?? 0,
      transportStatus: _transportStatusController.text.trim().isNotEmpty ? _transportStatusController.text.trim() : null,
      transport: _transportController.text.trim().isNotEmpty ? _transportController.text.trim() : null,
      labourStatus: _labourStatusController.text.trim().isNotEmpty ? _labourStatusController.text.trim() : null,
      labourCharges: double.tryParse(_labourChargesController.text) ?? 0,
      transportCharge: double.tryParse(_transportChargeController.text) ?? 0,
      totalQty: int.tryParse(_totalQtyController.text) ?? 0,
      remarks: _remarksController.text.trim().isNotEmpty ? _remarksController.text.trim() : null,
      received: _received,
      cForm: _cFormController.text.trim().isNotEmpty ? _cFormController.text.trim() : null,
      dueStatus: _dueStatusController.text.trim().isNotEmpty ? _dueStatusController.text.trim() : null,
      closeStatus: _closeStatusController.text.trim().isNotEmpty ? _closeStatusController.text.trim() : null,
      dueDate: _dueDateController.text.isNotEmpty
          ? DateTime.parse(_dueDateController.text).millisecondsSinceEpoch ~/ 1000
          : 0,
      status: 'received',
    );

    final repo = PurchaseRepository();
    try {
      if (widget.existingPurchase == null) {
        await repo.insertWithItems(purchase, _items);
      } else {
        await repo.updateWithItems(purchase, _items);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Purchase saved successfully!'), backgroundColor: Colors.green),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showProductSelection(List<Product> products) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Select Product'),
        content: SizedBox(
          width: 400,
          height: 300,
          child: ListView.builder(
            itemCount: products.length,
            itemBuilder: (context, index) {
              final product = products[index];
              return ListTile(
                title: Text(product.name),
                subtitle: Text('Barcode: ${product.barcode} | ₹${product.retailPrice}'),
                onTap: () {
                  Navigator.pop(context);
                  _addProduct(product);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: widget.existingPurchase == null ? 'New Purchase' : 'Edit Purchase',
      actions: [
        IconButton(
          icon: const Icon(Icons.save),
          onPressed: _save,
        ),
      ],
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _buildHeaderSection(),
              const SizedBox(height: 16),
              _buildSupplierSection(),
              const SizedBox(height: 16),
              _buildFinancialSection(),
              const SizedBox(height: 16),
              _buildLogisticsSection(),
              const SizedBox(height: 16),
              _buildOtherDetailsSection(),
              const SizedBox(height: 16),
              _buildProductSearch(),
              const SizedBox(height: 8),
              _buildItemsGrid(),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save),
                  label: const Text('SAVE PURCHASE'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _grnController,
                decoration: const InputDecoration(labelText: 'GRN No *'),
                validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _dateController,
                decoration: const InputDecoration(labelText: 'Date (YYYY-MM-DD)'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _locationController,
                decoration: const InputDecoration(labelText: 'Location'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSupplierSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Consumer(
              builder: (context, ref, child) {
                final suppliersAsync = ref.watch(supplierNotifierProvider);
                return suppliersAsync.when(
                  data: (suppliers) {
                    return DropdownButtonFormField<Supplier>(
                      value: _selectedSupplier,
                      decoration: const InputDecoration(labelText: 'Supplier *'),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('Select Supplier')),
                        ...suppliers.map((s) {
                          return DropdownMenuItem(
                            value: s,
                            child: Text(s.name),
                          );
                        }),
                      ],
                      onChanged: (val) {
                        setState(() {
                          _selectedSupplier = val;
                          if (val != null) {
                            _supplierNameController.text = val.name;
                            _merchantController.text = val.phone ?? '';
                            _addressController.text = val.address ?? '';
                          }
                        });
                      },
                      validator: (v) => v == null ? 'Select a supplier' : null,
                    );
                  },
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (err, stack) => Text('Error: $err'),
                );
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _merchantController,
              decoration: const InputDecoration(labelText: 'Merchant'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _addressController,
              decoration: const InputDecoration(labelText: 'Address'),
              maxLines: 2,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFinancialSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _billTotalController,
                    decoration: const InputDecoration(labelText: 'Bill Total (Left)'),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _totalController,
                    decoration: const InputDecoration(labelText: 'Stock Total (Right)'),
                    keyboardType: TextInputType.number,
                    readOnly: true,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _differenceController,
                    decoration: const InputDecoration(labelText: 'Difference'),
                    readOnly: true,
                    style: TextStyle(color: double.tryParse(_differenceController.text) != 0 ? Colors.red : Colors.green),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _differenceController.text.isNotEmpty && double.tryParse(_differenceController.text) != 0
                          ? '⚠️ Mismatch'
                          : '✅ Matches',
                      style: TextStyle(
                        color: _differenceController.text.isNotEmpty && double.tryParse(_differenceController.text) != 0
                            ? Colors.red
                            : Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _accountPercentController,
                    decoration: const InputDecoration(labelText: 'Account %'),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _accountController,
                    decoration: const InputDecoration(labelText: 'Account'),
                    keyboardType: TextInputType.number,
                    readOnly: true,
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _taxRateController,
                    decoration: const InputDecoration(labelText: 'Tax Rate %'),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _taxPercentController,
                    decoration: const InputDecoration(labelText: 'Tax %'),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _taxController,
                    decoration: const InputDecoration(labelText: 'Tax'),
                    keyboardType: TextInputType.number,
                    readOnly: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _chessController,
                    decoration: const InputDecoration(labelText: 'Chess/Ref'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _netAmountController,
              decoration: const InputDecoration(
                labelText: 'Net Amount',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              readOnly: true,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogisticsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _transportStatusController,
                    decoration: const InputDecoration(labelText: 'Transport Status'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _transportController,
                    decoration: const InputDecoration(labelText: 'Transport'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _labourStatusController,
                    decoration: const InputDecoration(labelText: 'Labour Status'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _labourChargesController,
                    decoration: const InputDecoration(labelText: 'Labour Charges'),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _transportChargeController,
              decoration: const InputDecoration(labelText: 'Transport Charge'),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOtherDetailsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _totalQtyController,
                    decoration: const InputDecoration(labelText: 'Total Qty'),
                    keyboardType: TextInputType.number,
                    readOnly: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _remarksController,
                    decoration: const InputDecoration(labelText: 'Remarks'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Text('Received: '),
                      Checkbox(
                        value: _received,
                        onChanged: (val) => setState(() => _received = val ?? false),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _cFormController,
                    decoration: const InputDecoration(labelText: 'C Form'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _dueStatusController,
                    decoration: const InputDecoration(labelText: 'Due Status'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _closeStatusController,
                    decoration: const InputDecoration(labelText: 'Close Status'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _dueDateController,
              decoration: const InputDecoration(labelText: 'Due Date (YYYY-MM-DD)'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductSearch() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _productSearchController,
            focusNode: _searchFocus,
            decoration: const InputDecoration(
              hintText: 'Search product by name or barcode',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
            onSubmitted: (value) async {
              if (value.isNotEmpty) {
                final products = await ref
                    .read(productNotifierProvider.notifier)
                    .search(value);
                if (products.isNotEmpty) {
                  _showProductSelection(products);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('No product found'), backgroundColor: Colors.red),
                  );
                }
              }
            },
          ),
        ),
        IconButton(
          icon: const Icon(Icons.add),
          onPressed: () => _searchFocus.requestFocus(),
        ),
      ],
    );
  }

  Widget _buildItemsGrid() {
    if (_items.isEmpty) {
      return Card(
        child: const Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: Text('No items added yet')),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Items', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _items.length,
              itemBuilder: (context, index) {
                final item = _items[index];
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: Text(
                                item.productName ?? item.productId,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _removeItem(index),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                initialValue: item.barcode ?? '',
                                decoration: const InputDecoration(labelText: 'Barcode'),
                                onChanged: (v) => _updateItem(index, item.copyWith(barcode: v.isEmpty ? null : v)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextFormField(
                                initialValue: item.mrp.toString(),
                                decoration: const InputDecoration(labelText: 'MRP Rate'),
                                keyboardType: TextInputType.number,
                                onChanged: (v) => _updateItem(index, item.copyWith(mrp: double.tryParse(v) ?? 0)),
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                initialValue: item.quantity.toString(),
                                decoration: const InputDecoration(labelText: 'Qty'),
                                keyboardType: TextInputType.number,
                                onChanged: (v) => _updateItem(index, item.copyWith(quantity: int.tryParse(v) ?? 1)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextFormField(
                                initialValue: item.freeQuantity.toString(),
                                decoration: const InputDecoration(labelText: 'Free'),
                                keyboardType: TextInputType.number,
                                onChanged: (v) => _updateItem(index, item.copyWith(freeQuantity: int.tryParse(v) ?? 0)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextFormField(
                                initialValue: item.purchasePrice.toString(),
                                decoration: const InputDecoration(labelText: 'Purchase Price'),
                                keyboardType: TextInputType.number,
                                onChanged: (v) => _updateItem(index, item.copyWith(purchasePrice: double.tryParse(v) ?? 0)),
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                initialValue: item.discount.toString(),
                                decoration: const InputDecoration(labelText: 'Discount'),
                                keyboardType: TextInputType.number,
                                onChanged: (v) => _updateItem(index, item.copyWith(discount: double.tryParse(v) ?? 0)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextFormField(
                                initialValue: item.taxPercent.toString(),
                                decoration: const InputDecoration(labelText: 'Tax %'),
                                keyboardType: TextInputType.number,
                                onChanged: (v) => _updateItem(index, item.copyWith(taxPercent: double.tryParse(v) ?? 0)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextFormField(
                                initialValue: item.salesPrice.toString(),
                                decoration: const InputDecoration(labelText: 'Sales Price'),
                                keyboardType: TextInputType.number,
                                onChanged: (v) => _updateItem(index, item.copyWith(salesPrice: double.tryParse(v) ?? 0)),
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                initialValue: item.costPrice.toString(),
                                decoration: const InputDecoration(labelText: 'Cost Price'),
                                keyboardType: TextInputType.number,
                                onChanged: (v) => _updateItem(index, item.copyWith(costPrice: double.tryParse(v) ?? 0)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextFormField(
                                initialValue: item.batchNo ?? '',
                                decoration: const InputDecoration(labelText: 'Batch No'),
                                onChanged: (v) => _updateItem(index, item.copyWith(batchNo: v.isEmpty ? null : v)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextFormField(
                                initialValue: item.expiryDate != null
                                    ? DateTime.fromMillisecondsSinceEpoch(item.expiryDate! * 1000)
                                        .toLocal()
                                        .toString()
                                        .split(' ')[0]
                                    : '',
                                decoration: const InputDecoration(labelText: 'Expiry Date'),
                                onChanged: (v) {
                                  try {
                                    final date = DateTime.parse(v);
                                    _updateItem(index, item.copyWith(
                                      expiryDate: date.millisecondsSinceEpoch ~/ 1000,
                                    ));
                                  } catch (_) {}
                                },
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: CheckboxListTile(
                                value: item.isRepack,
                                onChanged: (val) => _updateItem(index, item.copyWith(isRepack: val ?? false)),
                                title: const Text('Repack'),
                                controlAffinity: ListTileControlAffinity.leading,
                                dense: true,
                              ),
                            ),
                            if (item.isRepack) ...[
                              Expanded(
                                child: TextFormField(
                                  initialValue: item.bulkQuantity.toString(),
                                  decoration: const InputDecoration(labelText: 'Bulk Qty'),
                                  keyboardType: TextInputType.number,
                                  onChanged: (v) => _updateItem(index, item.copyWith(bulkQuantity: double.tryParse(v) ?? 0)),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextFormField(
                                  initialValue: item.bulkUnit ?? '',
                                  decoration: const InputDecoration(labelText: 'Bulk Unit'),
                                  onChanged: (v) => _updateItem(index, item.copyWith(bulkUnit: v.isEmpty ? null : v)),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextFormField(
                                  initialValue: item.packSize.toString(),
                                  decoration: const InputDecoration(labelText: 'Pack Size'),
                                  keyboardType: TextInputType.number,
                                  onChanged: (v) {
                                    final val = double.tryParse(v) ?? 0;
                                    final updated = item.copyWith(packSize: val);
                                    if (val > 0 && item.bulkQuantity > 0) {
                                      final count = (item.bulkQuantity / val).round();
                                      _updateItem(index, updated.copyWith(packCount: count, quantity: count));
                                    } else {
                                      _updateItem(index, updated);
                                    }
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextFormField(
                                  initialValue: item.packUnit ?? '',
                                  decoration: const InputDecoration(labelText: 'Pack Unit'),
                                  onChanged: (v) => _updateItem(index, item.copyWith(packUnit: v.isEmpty ? null : v)),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
'@

}

# Write all files
foreach ($key in $files.Keys) {
    $fullPath = Join-Path $base $key
    $dir = Split-Path $fullPath
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    Set-Content -Path $fullPath -Value $files[$key] -Force
    Write-Host "Created: $key" -ForegroundColor Green
}

Write-Host "`n✅ Complete Purchase Module generated!" -ForegroundColor Cyan
Write-Host "`nNow run:" -ForegroundColor Yellow
Write-Host "flutter clean" -ForegroundColor White
Write-Host "flutter pub get" -ForegroundColor White
Write-Host "flutter pub run build_runner build --delete-conflicting-outputs" -ForegroundColor White
Write-Host "flutter run -d windows" -ForegroundColor White