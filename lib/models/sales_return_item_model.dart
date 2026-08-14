import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

class SalesReturnItem extends Equatable {
  final String id;
  final String? returnId;
  final String? saleItemId;
  final String productId;
  final double quantity;
  final double unitPrice;
  final double taxAmount;
  final double totalPrice;
  /// Cost price at time of the original sale (or, for an untied return, the
  /// product's current cost price) — mirrors `sale_items.cost_price` so a
  /// future COGS-reversal pass has something to subtract.
  final double costPrice;
  /// Whether this line was put back on the shelf. False for
  /// damaged/expired/otherwise non-resalable returns — recorded for the
  /// audit trail but does not touch stock_quantity or stock_ledger.
  final bool restocked;

  const SalesReturnItem({
    required this.id,
    this.returnId,
    this.saleItemId,
    required this.productId,
    this.quantity = 1,
    this.unitPrice = 0,
    this.taxAmount = 0,
    this.totalPrice = 0,
    this.costPrice = 0,
    this.restocked = true,
  });

  factory SalesReturnItem.create({
    String? saleItemId,
    required String productId,
    double quantity = 1,
    double unitPrice = 0,
    double taxAmount = 0,
    double totalPrice = 0,
    double costPrice = 0,
    bool restocked = true,
  }) {
    return SalesReturnItem(
      id: const Uuid().v4(),
      saleItemId: saleItemId,
      productId: productId,
      quantity: quantity,
      unitPrice: unitPrice,
      taxAmount: taxAmount,
      totalPrice: totalPrice,
      costPrice: costPrice,
      restocked: restocked,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'return_id': returnId,
        'sale_item_id': saleItemId,
        'product_id': productId,
        'quantity': quantity,
        'unit_price': unitPrice,
        'tax_amount': taxAmount,
        'total_price': totalPrice,
        'cost_price': costPrice,
        'restocked': restocked ? 1 : 0,
      };

  factory SalesReturnItem.fromJson(Map<String, dynamic> map) => SalesReturnItem(
        id: map['id'] as String,
        returnId: map['return_id'] as String?,
        saleItemId: map['sale_item_id'] as String?,
        productId: map['product_id'] as String,
        quantity: (map['quantity'] as num?)?.toDouble() ?? 1,
        unitPrice: (map['unit_price'] as num?)?.toDouble() ?? 0,
        taxAmount: (map['tax_amount'] as num?)?.toDouble() ?? 0,
        totalPrice: (map['total_price'] as num?)?.toDouble() ?? 0,
        costPrice: (map['cost_price'] as num?)?.toDouble() ?? 0,
        restocked: (map['restocked'] as int?) != 0,
      );

  @override
  List<Object?> get props => [id, productId, quantity, totalPrice, restocked];
}
