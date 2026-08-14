import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

class SaleItem extends Equatable {
  final String id;
  final String? saleId;
  final String productId;
  final double quantity;
  final double unitPrice;
  final double taxAmount;
  final double discountAmount;
  final double totalPrice;
  final String? lineDiscountReason;
  /// Product cost price at the moment of sale — snapshotted here (rather than
  /// read live off `products.cost_price`) so profit reports stay accurate
  /// even after the product's cost price later changes.
  final double costPrice;

  const SaleItem({
    required this.id,
    this.saleId,
    required this.productId,
    this.quantity = 1,
    this.unitPrice = 0,
    this.taxAmount = 0,
    this.discountAmount = 0,
    this.totalPrice = 0,
    this.lineDiscountReason,
    this.costPrice = 0,
  });

  factory SaleItem.create({
    required String productId,
    double quantity = 1,
    double unitPrice = 0,
    double taxAmount = 0,
    double discountAmount = 0,
    double totalPrice = 0,
    String? lineDiscountReason,
    double costPrice = 0,
  }) {
    return SaleItem(
      id: const Uuid().v4(),
      productId: productId,
      quantity: quantity,
      unitPrice: unitPrice,
      taxAmount: taxAmount,
      discountAmount: discountAmount,
      totalPrice: totalPrice,
      lineDiscountReason: lineDiscountReason,
      costPrice: costPrice,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'sale_id': saleId,
        'product_id': productId,
        'quantity': quantity,
        'unit_price': unitPrice,
        'tax_amount': taxAmount,
        'discount_amount': discountAmount,
        'total_price': totalPrice,
        'line_discount_reason': lineDiscountReason,
        'cost_price': costPrice,
      };

  factory SaleItem.fromJson(Map<String, dynamic> map) => SaleItem(
        id: map['id'] as String,
        saleId: map['sale_id'] as String?,
        productId: map['product_id'] as String,
        quantity: (map['quantity'] as num?)?.toDouble() ?? 1,
        unitPrice: (map['unit_price'] as num?)?.toDouble() ?? 0,
        taxAmount: (map['tax_amount'] as num?)?.toDouble() ?? 0,
        discountAmount: (map['discount_amount'] as num?)?.toDouble() ?? 0,
        totalPrice: (map['total_price'] as num?)?.toDouble() ?? 0,
        lineDiscountReason: map['line_discount_reason'] as String?,
        costPrice: (map['cost_price'] as num?)?.toDouble() ?? 0,
      );

  @override
  List<Object?> get props => [id, productId, quantity, totalPrice];
}