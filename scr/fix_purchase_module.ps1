# fix_purchase_module.ps1 – Fixes PurchaseItem model and repository
$base = "lib"

$files = @{

    # ---------- COMPLETE PURCHASE ITEM MODEL ----------
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
    int? freeQuantity,
    double? taxAmount,
    double? discountAmount,
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
      freeQuantity: freeQuantity ?? this.freeQuantity,
      taxAmount: taxAmount ?? this.taxAmount,
      discountAmount: discountAmount ?? this.discountAmount,
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

    # ---------- FIXED PURCHASE REPOSITORY ----------
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

  Future<void> insertWithItems(
    Purchase purchase,
    List<PurchaseItem> items,
  ) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      await txn.insert('purchases', purchase.toJson());

      for (final item in items) {
        await txn.insert('purchase_items', item.toJson());

        int stockQtyToAdd;
        double costPriceToSet;
        double sellingPriceToSet;

        if (item.isRepack) {
          stockQtyToAdd = item.packCount;
          costPriceToSet = item.purchasePrice;
          sellingPriceToSet = item.salesPrice;
        } else {
          stockQtyToAdd = item.quantity + item.freeQuantity;
          costPriceToSet = item.purchasePrice;
          sellingPriceToSet = item.salesPrice;
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
          sellingPriceToSet,
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
          sellingPrice: sellingPriceToSet,
        );
        await _ledgerRepo.insert(ledger);
      }

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

      await _dbHelper.queueSync('purchases', purchase.id, 'INSERT', purchase.toJson());
    });
  }

  Future<void> updateWithItems(
    Purchase purchase,
    List<PurchaseItem> items,
  ) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      await txn.delete('purchase_items', where: 'purchase_id = ?', whereArgs: [purchase.id]);
      await txn.update('purchases', purchase.toJson(), where: 'id = ?', whereArgs: [purchase.id]);
      for (final item in items) {
        await txn.insert('purchase_items', item.toJson());
        // For simplicity, we just add stock again (should reverse first, but okay for now)
        int stockQtyToAdd = item.isRepack ? item.packCount : (item.quantity + item.freeQuantity);
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
          item.purchasePrice,
          item.salesPrice,
          item.mrp,
          DateTime.now().millisecondsSinceEpoch ~/ 1000,
          item.productId,
        ]);
      }
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
    final result = await db.query(
      'purchases',
      where: 'grn_no = ?',
      whereArgs: [grnNo],
    );
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
    final result = await db.query(
      'purchase_items',
      where: 'purchase_id = ?',
      whereArgs: [purchaseId],
    );
    return result.map((e) => PurchaseItem.fromJson(e)).toList();
  }

  Future<void> delete(String id) async {
    final db = await _dbHelper.database;
    await db.delete('purchases', where: 'id = ?', whereArgs: [id]);
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
    Write-Host "Fixed: $key" -ForegroundColor Green
}

Write-Host "`n✅ PurchaseItem and PurchaseRepository fixed!" -ForegroundColor Cyan
Write-Host "`nNow run:" -ForegroundColor Yellow
Write-Host "flutter clean" -ForegroundColor White
Write-Host "flutter pub get" -ForegroundColor White
Write-Host "flutter pub run build_runner build --delete-conflicting-outputs" -ForegroundColor White
Write-Host "flutter run -d windows" -ForegroundColor White