import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

/// A single line on a [Quotation] — added alongside header totals so a
/// quotation can actually be reloaded into the cart later ("Convert to
/// Bill"), not just displayed as a lump-sum figure.
class QuotationItem extends Equatable {
  final String id;
  final String? quotationId;
  final String productId;
  final double quantity;
  final double unitPrice;
  final double totalPrice;

  const QuotationItem({
    required this.id,
    this.quotationId,
    required this.productId,
    this.quantity = 1,
    this.unitPrice = 0,
    this.totalPrice = 0,
  });

  factory QuotationItem.create({
    String? quotationId,
    required String productId,
    double quantity = 1,
    double unitPrice = 0,
    double totalPrice = 0,
  }) {
    return QuotationItem(
      id: const Uuid().v4(),
      quotationId: quotationId,
      productId: productId,
      quantity: quantity,
      unitPrice: unitPrice,
      totalPrice: totalPrice,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'quotation_id': quotationId,
        'product_id': productId,
        'quantity': quantity,
        'unit_price': unitPrice,
        'total_price': totalPrice,
      };

  factory QuotationItem.fromJson(Map<String, dynamic> map) => QuotationItem(
        id: map['id'] as String,
        quotationId: map['quotation_id'] as String?,
        productId: map['product_id'] as String,
        quantity: (map['quantity'] as num?)?.toDouble() ?? 1,
        unitPrice: (map['unit_price'] as num?)?.toDouble() ?? 0,
        totalPrice: (map['total_price'] as num?)?.toDouble() ?? 0,
      );

  @override
  List<Object?> get props => [id, quotationId, productId, quantity, totalPrice];
}
