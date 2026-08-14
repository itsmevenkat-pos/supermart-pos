import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

class StockLedger extends Equatable {
  final String id;
  final String productId;
  final String storeId;
  final String referenceType;
  final String referenceId;
  final double quantityChange;
  final String? batchNo;
  final int? expiryDate;
  final double costPrice;
  final double sellingPrice;
  final int createdAt;

  const StockLedger({
    required this.id,
    required this.productId,
    required this.storeId,
    required this.referenceType,
    required this.referenceId,
    required this.quantityChange,
    this.batchNo,
    this.expiryDate,
    required this.costPrice,
    required this.sellingPrice,
    this.createdAt = 0,
  });

  factory StockLedger.create({
    required String productId,
    required String storeId,
    required String referenceType,
    required String referenceId,
    required double quantityChange,
    String? batchNo,
    int? expiryDate,
    required double costPrice,
    required double sellingPrice,
  }) {
    return StockLedger(
      id: const Uuid().v4(),
      productId: productId,
      storeId: storeId,
      referenceType: referenceType,
      referenceId: referenceId,
      quantityChange: quantityChange,
      batchNo: batchNo,
      expiryDate: expiryDate,
      costPrice: costPrice,
      sellingPrice: sellingPrice,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'product_id': productId,
    'store_id': storeId,
    'reference_type': referenceType,
    'reference_id': referenceId,
    'quantity_change': quantityChange,
    'batch_no': batchNo,
    'expiry_date': expiryDate,
    'cost_price': costPrice,
    'selling_price': sellingPrice,
    'created_at': createdAt,
  };

  factory StockLedger.fromJson(Map<String, dynamic> map) => StockLedger(
    id: map['id'] as String,
    productId: map['product_id'] as String,
    storeId: map['store_id'] as String,
    referenceType: map['reference_type'] as String,
    referenceId: map['reference_id'] as String,
    quantityChange: (map['quantity_change'] as num).toDouble(),
    batchNo: map['batch_no'] as String?,
    expiryDate: map['expiry_date'] as int?,
    costPrice: (map['cost_price'] as num).toDouble(),
    sellingPrice: (map['selling_price'] as num).toDouble(),
    createdAt: map['created_at'] as int? ?? 0,
  );

  @override
  List<Object?> get props => [id, productId, referenceType, quantityChange];
}