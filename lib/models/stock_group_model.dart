import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

/// A pooled/shared stock group — e.g. several ₹10 chip flavors that should
/// draw from one common stock count instead of separate per-flavor counts,
/// so one flavor selling out doesn't look like a stockout while siblings
/// still have plenty on the shelf. See StockGroupRepository for how
/// membership keeps every member's own `products.stock_quantity` mirrored
/// to the same pooled number.
class StockGroup extends Equatable {
  final String id;
  final String name;
  final int createdAt;

  const StockGroup({
    required this.id,
    required this.name,
    this.createdAt = 0,
  });

  factory StockGroup.create({required String name}) {
    return StockGroup(id: const Uuid().v4(), name: name);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'created_at': createdAt,
      };

  factory StockGroup.fromJson(Map<String, dynamic> map) => StockGroup(
        id: map['id'] as String,
        name: map['name'] as String,
        createdAt: map['created_at'] as int? ?? 0,
      );

  @override
  List<Object?> get props => [id, name];
}
