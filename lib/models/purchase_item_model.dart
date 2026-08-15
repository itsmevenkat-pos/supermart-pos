import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

class PurchaseItem extends Equatable {
  final String id;
  final String? purchaseId;
  final String productId;
  final String? barcode;
  final String? productName;
  final double mrp;
  final double quantity;
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
  /// When this batch was packed/manufactured — distinct from [expiryDate]
  /// and from the purchase's own `createdAt` (when it was RECEIVED into
  /// this shop, not when the manufacturer packed it). Printed on barcode
  /// labels alongside Expiry Date.
  final int? packingDate;
  final int freeQuantity;
  final double taxAmount;
  final double discountAmount;
  /// Whether [quantity] (and [freeQuantity]) on this line were entered in
  /// the product's `purchaseUnit` (e.g. "Box") rather than its base stock
  /// unit (e.g. "Pcs") — distinct from [isRepack], which is about splitting
  /// one bulk-purchased unit into several retail units. This is simply "the
  /// number typed is boxes, not pieces." Defaults to false so every
  /// pre-existing row (and every product without a purchaseUnit configured)
  /// behaves exactly as before.
  final bool isPurchaseUnitEntry;
  /// Snapshot of the product's `unitsPerPurchaseUnit` at the moment this
  /// line was added — NOT a live lookup — so that editing or deleting this
  /// purchase later reverses stock by the exact same factor that was used
  /// to add it, even if the product's conversion factor is changed
  /// afterward. Ignored unless [isPurchaseUnitEntry] is true. Defaults to 1
  /// (a no-op multiplier) for backward compatibility.
  final double purchaseUnitFactor;

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
    this.packingDate,
    this.freeQuantity = 0,
    this.taxAmount = 0,
    this.discountAmount = 0,
    this.isPurchaseUnitEntry = false,
    this.purchaseUnitFactor = 1,
  });

  factory PurchaseItem.create({
    required String productId,
    String? barcode,
    String? productName,
    double mrp = 0,
    double quantity = 1,
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
    int? packingDate,
    int freeQuantity = 0,
    double taxAmount = 0,
    double discountAmount = 0,
    bool isPurchaseUnitEntry = false,
    double purchaseUnitFactor = 1,
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
      packingDate: packingDate,
      freeQuantity: freeQuantity,
      taxAmount: taxAmount,
      discountAmount: discountAmount,
      isPurchaseUnitEntry: isPurchaseUnitEntry,
      purchaseUnitFactor: purchaseUnitFactor,
    );
  }

  PurchaseItem copyWith({
    String? barcode,
    double? quantity,
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
    int? packingDate,
    int? freeQuantity,
    double? taxAmount,
    double? discountAmount,
    bool? isPurchaseUnitEntry,
    double? purchaseUnitFactor,
  }) {
    return PurchaseItem(
      id: id,
      purchaseId: purchaseId,
      productId: productId,
      barcode: barcode ?? this.barcode,
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
      packingDate: packingDate ?? this.packingDate,
      freeQuantity: freeQuantity ?? this.freeQuantity,
      taxAmount: taxAmount ?? this.taxAmount,
      discountAmount: discountAmount ?? this.discountAmount,
      isPurchaseUnitEntry: isPurchaseUnitEntry ?? this.isPurchaseUnitEntry,
      purchaseUnitFactor: purchaseUnitFactor ?? this.purchaseUnitFactor,
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
        'packing_date': packingDate,
        'free_quantity': freeQuantity,
        'tax_amount': taxAmount,
        'discount_amount': discountAmount,
        'is_purchase_unit_entry': isPurchaseUnitEntry ? 1 : 0,
        'purchase_unit_factor': purchaseUnitFactor,
      };

  factory PurchaseItem.fromJson(Map<String, dynamic> map) => PurchaseItem(
        id: map['id'] as String,
        purchaseId: map['purchase_id'] as String?,
        productId: map['product_id'] as String,
        barcode: map['barcode'] as String?,
        productName: map['product_name'] as String?,
        mrp: (map['mrp'] as num?)?.toDouble() ?? 0,
        quantity: (map['quantity'] as num?)?.toDouble() ?? 1,
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
        packingDate: map['packing_date'] as int?,
        freeQuantity: map['free_quantity'] as int? ?? 0,
        taxAmount: (map['tax_amount'] as num?)?.toDouble() ?? 0,
        discountAmount: (map['discount_amount'] as num?)?.toDouble() ?? 0,
        isPurchaseUnitEntry: (map['is_purchase_unit_entry'] as int?) == 1,
        purchaseUnitFactor: (map['purchase_unit_factor'] as num?)?.toDouble() ?? 1,
      );

  @override
  List<Object?> get props => [id, productId, quantity, purchasePrice, total];
}