import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

/// One line of "what a kit/bundle product is made of" — e.g. a "Gift
/// Hamper" kit made of 2x Chocolate Box + 1x Greeting Card. Consumed by
/// `SaleRepository` at sale time to deduct component stock instead of the
/// kit's own (unused) `stock_quantity`.
class ProductKitComponent extends Equatable {
  final String id;
  final String kitProductId;
  final String componentProductId;
  final double quantity;

  const ProductKitComponent({
    required this.id,
    required this.kitProductId,
    required this.componentProductId,
    this.quantity = 1,
  });

  factory ProductKitComponent.create({
    required String kitProductId,
    required String componentProductId,
    double quantity = 1,
  }) {
    return ProductKitComponent(
      id: const Uuid().v4(),
      kitProductId: kitProductId,
      componentProductId: componentProductId,
      quantity: quantity,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'kit_product_id': kitProductId,
        'component_product_id': componentProductId,
        'quantity': quantity,
      };

  factory ProductKitComponent.fromJson(Map<String, dynamic> map) => ProductKitComponent(
        id: map['id'] as String,
        kitProductId: map['kit_product_id'] as String,
        componentProductId: map['component_product_id'] as String,
        quantity: (map['quantity'] as num?)?.toDouble() ?? 1,
      );

  @override
  List<Object?> get props => [id, kitProductId, componentProductId, quantity];
}
