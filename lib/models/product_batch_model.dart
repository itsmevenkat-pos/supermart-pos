import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

/// A read-only batch history record — one row per purchase line that
/// brought stock in for a product, capturing the MRP/cost/selling price
/// and expiry that batch carried. Written automatically by
/// `PurchaseRepository`; shows "quantity received," not a live "quantity
/// remaining" (that needs sale-side batch attribution, which doesn't exist
/// — see the Product & Item Master plan for why this stops short of FEFO).
class ProductBatch extends Equatable {
  final String id;
  final String productId;
  final String? purchaseId;
  final String? batchNo;
  final double? mrp;
  final double? costPrice;
  final double? sellingPrice;
  final int? expiryDate;
  final double quantityReceived;
  final int createdAt;

  const ProductBatch({
    required this.id,
    required this.productId,
    this.purchaseId,
    this.batchNo,
    this.mrp,
    this.costPrice,
    this.sellingPrice,
    this.expiryDate,
    required this.quantityReceived,
    this.createdAt = 0,
  });

  factory ProductBatch.create({
    required String productId,
    String? purchaseId,
    String? batchNo,
    double? mrp,
    double? costPrice,
    double? sellingPrice,
    int? expiryDate,
    required double quantityReceived,
  }) {
    return ProductBatch(
      id: const Uuid().v4(),
      productId: productId,
      purchaseId: purchaseId,
      batchNo: batchNo,
      mrp: mrp,
      costPrice: costPrice,
      sellingPrice: sellingPrice,
      expiryDate: expiryDate,
      quantityReceived: quantityReceived,
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'product_id': productId,
        'purchase_id': purchaseId,
        'batch_no': batchNo,
        'mrp': mrp,
        'cost_price': costPrice,
        'selling_price': sellingPrice,
        'expiry_date': expiryDate,
        'quantity_received': quantityReceived,
        'created_at': createdAt,
      };

  factory ProductBatch.fromJson(Map<String, dynamic> map) => ProductBatch(
        id: map['id'] as String,
        productId: map['product_id'] as String,
        purchaseId: map['purchase_id'] as String?,
        batchNo: map['batch_no'] as String?,
        mrp: (map['mrp'] as num?)?.toDouble(),
        costPrice: (map['cost_price'] as num?)?.toDouble(),
        sellingPrice: (map['selling_price'] as num?)?.toDouble(),
        expiryDate: map['expiry_date'] as int?,
        quantityReceived: (map['quantity_received'] as num?)?.toDouble() ?? 0,
        createdAt: map['created_at'] as int? ?? 0,
      );

  @override
  List<Object?> get props => [id, productId, batchNo, quantityReceived];
}
