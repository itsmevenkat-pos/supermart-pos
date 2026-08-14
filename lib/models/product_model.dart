import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

class Product extends Equatable {
  final String id;
  final String? storeId;
  final String barcode;
  final String name;
  final String? searchName;
  final String? displayName;
  final String? categoryId;
  final String unit;
  final double mrp;
  final double retailPrice;
  final double wholesalePrice;
  final double costPrice;
  final double taxRate;
  final double stockQuantity;
  final int reorderLevel;
  final bool allowNegativeStock;
  final bool bonusEligible;
  final bool isActive;
  final bool isDeleted;
  final String? hsnCode;
  /// Second name in the local/regional script (Tamil, Hindi, ...), stored
  /// independently of [name] — printed on the bill and searchable
  /// separately once billing/printing consume it.
  final String? localName;
  /// The unit stock is received in when it differs from [unit] (the
  /// selling unit) — e.g. purchase in "Box", sell in "Pcs". Null means no
  /// conversion is defined; [unit] is used for both.
  final String? purchaseUnit;
  /// How many [unit]s make up one [purchaseUnit] (e.g. 12 Pcs per Box).
  final double unitsPerPurchaseUnit;
  /// Sold by weight (loose produce, meat, etc.) — decimal quantities are
  /// already supported system-wide; this just flags the item as such.
  final bool isWeighted;
  /// Optional ceiling that complements [reorderLevel] (the existing "low
  /// stock" / minimum trigger) — an overstocking warning threshold.
  final double? maxStockLevel;
  /// Links this product as a variant under another product (e.g. 500ml
  /// under a "Cooking Oil" parent) for grouped display/reporting. Distinct
  /// from the existing same-barcode-different-MRP mechanism.
  final String? parentProductId;
  /// A kit/bundle/combo — its own [stockQuantity] is unused; selling it
  /// deducts stock from its `product_kit_components` instead.
  final bool isKit;
  /// A non-inventory/service line (carry bag, delivery charge, ...) — never
  /// stock-checked or stock-tracked.
  final bool isService;
  /// Local file path to an item image shown on the product list/POS.
  final String? imagePath;
  /// Pooled/shared stock group (e.g. several ₹10 chip flavors sharing one
  /// stock count) — null means this product tracks its own stock normally.
  /// See StockGroupRepository for how membership keeps every member's
  /// stockQuantity mirrored to the same pooled number. Distinct from
  /// [parentProductId], which is a display/reporting grouping, not a
  /// stock-sharing one.
  final String? stockGroupId;
  final int createdAt;
  final int? updatedAt;

  const Product({
    required this.id,
    this.storeId,
    required this.barcode,
    required this.name,
    this.searchName,
    this.displayName,
    this.categoryId,
    this.unit = 'Pcs',
    this.mrp = 0,
    this.retailPrice = 0,
    this.wholesalePrice = 0,
    this.costPrice = 0,
    this.taxRate = 0,
    this.stockQuantity = 0.0,
    this.reorderLevel = 5,
    this.allowNegativeStock = false,
    this.bonusEligible = true,
    this.isActive = true,
    this.isDeleted = false,
    this.hsnCode,
    this.localName,
    this.purchaseUnit,
    this.unitsPerPurchaseUnit = 1,
    this.isWeighted = false,
    this.maxStockLevel,
    this.parentProductId,
    this.isKit = false,
    this.isService = false,
    this.imagePath,
    this.stockGroupId,
    this.createdAt = 0,
    this.updatedAt,
  });

  factory Product.create({
    String? storeId,
    required String barcode,
    required String name,
    String? searchName,
    String? displayName,
    String? categoryId,
    String unit = 'Pcs',
    double mrp = 0,
    double retailPrice = 0,
    double wholesalePrice = 0,
    double costPrice = 0,
    double taxRate = 0,
    double stockQuantity = 0.0,
    int reorderLevel = 5,
    bool allowNegativeStock = false,
    bool bonusEligible = true,
    String? hsnCode,
    String? localName,
    String? purchaseUnit,
    double unitsPerPurchaseUnit = 1,
    bool isWeighted = false,
    double? maxStockLevel,
    String? parentProductId,
    bool isKit = false,
    bool isService = false,
    String? imagePath,
  }) {
    return Product(
      id: const Uuid().v4(),
      storeId: storeId,
      barcode: barcode,
      name: name,
      searchName: searchName ?? name,
      displayName: displayName ?? name,
      categoryId: categoryId,
      unit: unit,
      mrp: mrp,
      retailPrice: retailPrice,
      wholesalePrice: wholesalePrice,
      costPrice: costPrice,
      taxRate: taxRate,
      stockQuantity: stockQuantity,
      reorderLevel: reorderLevel,
      allowNegativeStock: allowNegativeStock,
      bonusEligible: bonusEligible,
      hsnCode: hsnCode,
      localName: localName,
      purchaseUnit: purchaseUnit,
      unitsPerPurchaseUnit: unitsPerPurchaseUnit,
      isWeighted: isWeighted,
      maxStockLevel: maxStockLevel,
      parentProductId: parentProductId,
      isKit: isKit,
      isService: isService,
      imagePath: imagePath,
    );
  }

  Product copyWith({
    String? barcode,
    String? name,
    String? searchName,
    String? displayName,
    String? categoryId,
    String? unit,
    double? mrp,
    double? retailPrice,
    double? wholesalePrice,
    double? costPrice,
    double? taxRate,
    double? stockQuantity,
    int? reorderLevel,
    bool? allowNegativeStock,
    bool? bonusEligible,
    bool? isActive,
    bool? isDeleted,
    String? hsnCode,
    String? localName,
    String? purchaseUnit,
    double? unitsPerPurchaseUnit,
    bool? isWeighted,
    double? maxStockLevel,
    String? parentProductId,
    bool? isKit,
    bool? isService,
    String? imagePath,
    String? stockGroupId,
    bool clearStockGroupId = false,
  }) {
    return Product(
      id: id,
      storeId: storeId,
      barcode: barcode ?? this.barcode,
      name: name ?? this.name,
      searchName: searchName ?? this.searchName,
      displayName: displayName ?? this.displayName,
      categoryId: categoryId ?? this.categoryId,
      unit: unit ?? this.unit,
      mrp: mrp ?? this.mrp,
      retailPrice: retailPrice ?? this.retailPrice,
      wholesalePrice: wholesalePrice ?? this.wholesalePrice,
      costPrice: costPrice ?? this.costPrice,
      taxRate: taxRate ?? this.taxRate,
      stockQuantity: stockQuantity ?? this.stockQuantity,
      reorderLevel: reorderLevel ?? this.reorderLevel,
      allowNegativeStock: allowNegativeStock ?? this.allowNegativeStock,
      bonusEligible: bonusEligible ?? this.bonusEligible,
      isActive: isActive ?? this.isActive,
      isDeleted: isDeleted ?? this.isDeleted,
      hsnCode: hsnCode ?? this.hsnCode,
      localName: localName ?? this.localName,
      purchaseUnit: purchaseUnit ?? this.purchaseUnit,
      unitsPerPurchaseUnit: unitsPerPurchaseUnit ?? this.unitsPerPurchaseUnit,
      isWeighted: isWeighted ?? this.isWeighted,
      maxStockLevel: maxStockLevel ?? this.maxStockLevel,
      stockGroupId: clearStockGroupId ? null : (stockGroupId ?? this.stockGroupId),
      parentProductId: parentProductId ?? this.parentProductId,
      isKit: isKit ?? this.isKit,
      isService: isService ?? this.isService,
      imagePath: imagePath ?? this.imagePath,
      createdAt: createdAt,
      updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'store_id': storeId,
        'barcode': barcode,
        'name': name,
        'search_name': searchName,
        'display_name': displayName,
        'category_id': categoryId,
        'unit': unit,
        'mrp': mrp,
        'retail_price': retailPrice,
        'wholesale_price': wholesalePrice,
        'cost_price': costPrice,
        'tax_rate': taxRate,
        'stock_quantity': stockQuantity,
        'reorder_level': reorderLevel,
        'allow_negative_stock': allowNegativeStock ? 1 : 0,
        'bonus_eligible': bonusEligible ? 1 : 0,
        'is_active': isActive ? 1 : 0,
        'is_deleted': isDeleted ? 1 : 0,
        'hsn_code': hsnCode,
        'local_name': localName,
        'purchase_unit': purchaseUnit,
        'units_per_purchase_unit': unitsPerPurchaseUnit,
        'is_weighted': isWeighted ? 1 : 0,
        'max_stock_level': maxStockLevel,
        'parent_product_id': parentProductId,
        'is_kit': isKit ? 1 : 0,
        'is_service': isService ? 1 : 0,
        'image_path': imagePath,
        'stock_group_id': stockGroupId,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory Product.fromJson(Map<String, dynamic> map) => Product(
        id: map['id'] as String,
        storeId: map['store_id'] as String?,
        barcode: map['barcode'] as String,
        name: map['name'] as String,
        searchName: map['search_name'] as String?,
        displayName: map['display_name'] as String?,
        categoryId: map['category_id'] as String?,
        unit: map['unit'] as String? ?? 'Pcs',
        mrp: (map['mrp'] as num?)?.toDouble() ?? 0,
        retailPrice: (map['retail_price'] as num?)?.toDouble() ?? 0,
        wholesalePrice: (map['wholesale_price'] as num?)?.toDouble() ?? 0,
        costPrice: (map['cost_price'] as num?)?.toDouble() ?? 0,
        taxRate: (map['tax_rate'] as num?)?.toDouble() ?? 0,
        stockQuantity: (map['stock_quantity'] as num?)?.toDouble() ?? 0,
        reorderLevel: map['reorder_level'] as int? ?? 5,
        allowNegativeStock: (map['allow_negative_stock'] as int?) == 1,
        bonusEligible: (map['bonus_eligible'] as int?) == 1,
        isActive: (map['is_active'] as int?) == 1,
        isDeleted: (map['is_deleted'] as int?) == 1,
        hsnCode: map['hsn_code'] as String?,
        localName: map['local_name'] as String?,
        purchaseUnit: map['purchase_unit'] as String?,
        unitsPerPurchaseUnit: (map['units_per_purchase_unit'] as num?)?.toDouble() ?? 1,
        isWeighted: (map['is_weighted'] as int?) == 1,
        maxStockLevel: (map['max_stock_level'] as num?)?.toDouble(),
        parentProductId: map['parent_product_id'] as String?,
        isKit: (map['is_kit'] as int?) == 1,
        isService: (map['is_service'] as int?) == 1,
        imagePath: map['image_path'] as String?,
        stockGroupId: map['stock_group_id'] as String?,
        createdAt: map['created_at'] as int? ?? 0,
        updatedAt: map['updated_at'] as int?,
      );

  double get availableStock => stockQuantity;
  bool get isLowStock => stockQuantity <= reorderLevel;
  bool get isOverstocked => maxStockLevel != null && stockQuantity > maxStockLevel!;
  double get marginPercent => retailPrice > 0 ? ((retailPrice - costPrice) / retailPrice) * 100 : 0;

  @override
  List<Object?> get props => [id, barcode, name, stockQuantity];
}
