# add_providers.ps1 – Creates all missing providers and repositories
$base = "lib"

$missingFiles = @{

    # ========================== REPOSITORIES ==========================
    "repositories/category_repository.dart" = @'
import '../core/database/database_helper.dart';
import '../models/category_model.dart';

class CategoryRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<List<Category>> getAll() async {
    final db = await _dbHelper.database;
    final result = await db.query('categories', orderBy: 'name ASC');
    return result.map((e) => Category.fromJson(e)).toList();
  }

  Future<Category?> getById(String id) async {
    final db = await _dbHelper.database;
    final result = await db.query('categories', where: 'id = ?', whereArgs: [id]);
    if (result.isEmpty) return null;
    return Category.fromJson(result.first);
  }

  Future<void> insert(Category category) async {
    final db = await _dbHelper.database;
    await db.insert('categories', category.toJson());
  }

  Future<void> update(Category category) async {
    final db = await _dbHelper.database;
    await db.update('categories', category.toJson(), where: 'id = ?', whereArgs: [category.id]);
  }
}
'@

    "repositories/sale_repository.dart" = @'
import '../core/database/database_helper.dart';
import '../models/sale_model.dart';
import '../models/sale_item_model.dart';

class SaleRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<void> insertWithItems(Sale sale, List<SaleItem> items) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      await txn.insert('sales', sale.toJson());
      for (final item in items) {
        await txn.insert('sale_items', item.toJson());
      }
    });
    await _dbHelper.queueSync('sales', sale.id, 'INSERT', sale.toJson());
  }

  Future<Sale?> getById(String id) async {
    final db = await _dbHelper.database;
    final result = await db.query('sales', where: 'id = ?', whereArgs: [id]);
    if (result.isEmpty) return null;
    return Sale.fromJson(result.first);
  }

  Future<List<Sale>> getRecent({int limit = 50}) async {
    final db = await _dbHelper.database;
    final result = await db.query('sales', orderBy: 'created_at DESC', limit: limit);
    return result.map((e) => Sale.fromJson(e)).toList();
  }

  Future<double> getCashTotalBySession(String sessionId) async {
    final db = await _dbHelper.database;
    final result = await db.rawQuery('''
      SELECT COALESCE(SUM(net_amount), 0) as total 
      FROM sales 
      WHERE session_id = ? AND status = 'completed'
    ''', [sessionId]);
    return (result.first['total'] as num?)?.toDouble() ?? 0;
  }

  Future<double> getTodayTotal() async {
    final db = await _dbHelper.database;
    final dayStart = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 86400;
    final result = await db.rawQuery('''
      SELECT COALESCE(SUM(net_amount), 0) as total 
      FROM sales 
      WHERE created_at > ? AND status = 'completed'
    ''', [dayStart]);
    return (result.first['total'] as num?)?.toDouble() ?? 0;
  }
}
'@

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

  Future<void> insertWithItems(Purchase purchase, List<PurchaseItem> items) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      await txn.insert('purchases', purchase.toJson());
      for (final item in items) {
        await txn.insert('purchase_items', item.toJson());
        // Update product stock
        await txn.rawUpdate('''
          UPDATE products 
          SET stock_quantity = stock_quantity + ?,
              cost_price = ?,
              updated_at = ?
          WHERE id = ?
        ''', [
          item.quantity + item.freeQuantity,
          item.costPrice,
          DateTime.now().millisecondsSinceEpoch ~/ 1000,
          item.productId,
        ]);
      }
    });
  }

  Future<List<Purchase>> getAll({int limit = 100}) async {
    final db = await _dbHelper.database;
    final result = await db.query('purchases', orderBy: 'created_at DESC', limit: limit);
    return result.map((e) => Purchase.fromJson(e)).toList();
  }

  Future<Purchase?> getById(String id) async {
    final db = await _dbHelper.database;
    final result = await db.query('purchases', where: 'id = ?', whereArgs: [id]);
    if (result.isEmpty) return null;
    return Purchase.fromJson(result.first);
  }

  Future<List<PurchaseItem>> getItemsByPurchase(String purchaseId) async {
    final db = await _dbHelper.database;
    final result = await db.query('purchase_items', where: 'purchase_id = ?', whereArgs: [purchaseId]);
    return result.map((e) => PurchaseItem.fromJson(e)).toList();
  }
}
'@

    "repositories/stock_ledger_repository.dart" = @'
import '../core/database/database_helper.dart';
import '../models/stock_ledger_model.dart';

class StockLedgerRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<void> insert(StockLedger ledger) async {
    final db = await _dbHelper.database;
    await db.insert('stock_ledger', ledger.toJson());
  }

  Future<List<StockLedger>> getByProduct(String productId, {int limit = 50}) async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'stock_ledger',
      where: 'product_id = ?',
      whereArgs: [productId],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return result.map((e) => StockLedger.fromJson(e)).toList();
  }
}
'@

    "repositories/supplier_ledger_repository.dart" = @'
import '../core/database/database_helper.dart';
import '../models/supplier_ledger_model.dart';

class SupplierLedgerRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<void> insert(SupplierLedger ledger) async {
    final db = await _dbHelper.database;
    await db.insert('supplier_ledger', ledger.toJson());
  }

  Future<double> getBalance(String supplierId) async {
    final db = await _dbHelper.database;
    final result = await db.rawQuery(
      'SELECT balance FROM supplier_ledger WHERE supplier_id = ? ORDER BY created_at DESC LIMIT 1',
      [supplierId],
    );
    if (result.isEmpty) return 0.0;
    return (result.first['balance'] as num?)?.toDouble() ?? 0.0;
  }
}
'@

    # ========================== SERVICES ==========================
    "services/billing_service.dart" = @'
import 'package:uuid/uuid.dart';
import '../models/product_model.dart';
import '../models/customer_model.dart';
import '../models/sale_model.dart';
import '../models/sale_item_model.dart';
import '../models/stock_ledger_model.dart';
import '../repositories/product_repository.dart';
import '../repositories/customer_repository.dart';
import '../repositories/sale_repository.dart';
import '../repositories/stock_ledger_repository.dart';

class CartItem {
  final String productId;
  final int quantity;
  final Product product;

  CartItem({required this.productId, required this.quantity, required this.product});
}

class BillingService {
  final ProductRepository _productRepo = ProductRepository();
  final CustomerRepository _customerRepo = CustomerRepository();
  final SaleRepository _saleRepo = SaleRepository();
  final StockLedgerRepository _ledgerRepo = StockLedgerRepository();

  Future<Sale> completeSale({
    required String storeId,
    required String? customerId,
    required String? sessionId,
    required String? userId,
    required List<CartItem> cartItems,
    required Map<String, double> payments,
    required double discountTotal,
    String? discountReason,
    double? partialPaymentAmount,
    double? creditUsed,
    String? deliveryAddress,
    bool isDelivery = false,
    double deliveryCharge = 0,
  }) async {
    double subtotal = 0;
    double totalTax = 0;
    final saleItems = <SaleItem>[];

    for (final item in cartItems) {
      final product = await _productRepo.getById(item.productId);
      if (product == null) throw Exception('Product not found: ${item.productId}');
      if (product.stockQuantity < item.quantity && !product.isDeleted) {
        // Check if category allows negative stock
        // For now, allow all products to go negative
      }

      final taxAmount = (product.retailPrice * item.quantity * product.taxRate) / 100;
      final lineTotal = (product.retailPrice * item.quantity) + taxAmount;

      subtotal += product.retailPrice * item.quantity;
      totalTax += taxAmount;

      saleItems.add(SaleItem(
        id: const Uuid().v4(),
        productId: product.id,
        quantity: item.quantity,
        unitPrice: product.retailPrice,
        taxAmount: taxAmount,
        discountAmount: 0,
        totalPrice: lineTotal,
      ));
    }

    final grandTotal = subtotal + totalTax + deliveryCharge - discountTotal;
    final sale = Sale.create(
      storeId: storeId,
      customerId: customerId,
      sessionId: sessionId,
      userId: userId,
      subtotal: subtotal,
      taxTotal: totalTax,
      discountTotal: discountTotal,
      discountReason: discountReason,
      netAmount: grandTotal,
      paymentMethods: payments,
      partialPaymentAmount: partialPaymentAmount,
      creditUsed: creditUsed,
      deliveryAddress: deliveryAddress,
      isDelivery: isDelivery,
      deliveryCharge: deliveryCharge,
      isCreditSale: creditUsed != null && creditUsed > 0,
    );

    await _saleRepo.insertWithItems(sale, saleItems);

    // Update stock
    for (final item in saleItems) {
      await _productRepo.updateStock(item.productId, -item.quantity);
      final ledger = StockLedger.create(
        productId: item.productId,
        storeId: storeId,
        referenceType: 'sale',
        referenceId: sale.id,
        quantityChange: -item.quantity,
        costPrice: 0,
        sellingPrice: item.unitPrice,
      );
      await _ledgerRepo.insert(ledger);
    }

    // Update customer points and balance
    if (customerId != null) {
      final customer = await _customerRepo.getById(customerId);
      if (customer != null) {
        final pointsEarned = (grandTotal / 100).floor();
        var updated = customer.copyWith(
          loyaltyPoints: customer.loyaltyPoints + pointsEarned,
          totalSpent: customer.totalSpent + grandTotal,
        );
        if (creditUsed != null && creditUsed > 0) {
          updated = updated.copyWith(
            outstandingBalance: customer.outstandingBalance - creditUsed,
          );
        }
        await _customerRepo.update(updated);
      }
    }

    return sale;
  }
}
'@

    # ========================== PROVIDERS ==========================
    "providers/product_provider.dart" = @'
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../models/product_model.dart';
import '../repositories/product_repository.dart';

part 'product_provider.g.dart';

@riverpod
class ProductNotifier extends _$ProductNotifier {
  final ProductRepository _repo = ProductRepository();

  @override
  Future<List<Product>> build() async {
    return await _repo.getAll();
  }

  Future<void> addProduct(Product product) async {
    await _repo.insert(product);
    ref.invalidateSelf();
  }

  Future<void> updateProduct(Product product) async {
    await _repo.update(product);
    ref.invalidateSelf();
  }

  Future<List<Product>> fetchByBarcode(String barcode) async {
    return await _repo.getByBarcode(barcode);
  }

  Future<List<Product>> search(String query) async {
    return await _repo.search(query);
  }
}
'@

    "providers/customer_provider.dart" = @'
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../models/customer_model.dart';
import '../repositories/customer_repository.dart';

part 'customer_provider.g.dart';

@riverpod
class CustomerNotifier extends _$CustomerNotifier {
  final CustomerRepository _repo = CustomerRepository();

  @override
  Future<List<Customer>> build() async {
    return await _repo.getAll();
  }

  Future<void> addCustomer(Customer customer) async {
    await _repo.insert(customer);
    ref.invalidateSelf();
  }

  Future<void> updateCustomer(Customer customer) async {
    await _repo.update(customer);
    ref.invalidateSelf();
  }

  Future<List<Customer>> search(String query) async {
    return await _repo.search(query);
  }

  Future<Customer?> getById(String id) async {
    return await _repo.getById(id);
  }
}
'@

    "providers/supplier_provider.dart" = @'
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../models/supplier_model.dart';
import '../repositories/supplier_repository.dart';

part 'supplier_provider.g.dart';

@riverpod
class SupplierNotifier extends _$SupplierNotifier {
  final SupplierRepository _repo = SupplierRepository();

  @override
  Future<List<Supplier>> build() async {
    return await _repo.getAll();
  }

  Future<void> addSupplier(Supplier supplier) async {
    await _repo.insert(supplier);
    ref.invalidateSelf();
  }

  Future<void> updateSupplier(Supplier supplier) async {
    await _repo.update(supplier);
    ref.invalidateSelf();
  }

  Future<List<Supplier>> search(String query) async {
    return await _repo.search(query);
  }

  Future<Supplier?> getById(String id) async {
    return await _repo.getById(id);
  }
}
'@

    "providers/purchase_provider.dart" = @'
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../models/purchase_model.dart';
import '../models/purchase_item_model.dart';
import '../repositories/purchase_repository.dart';

part 'purchase_provider.g.dart';

@riverpod
class PurchaseNotifier extends _$PurchaseNotifier {
  final PurchaseRepository _repo = PurchaseRepository();

  @override
  Future<List<Purchase>> build() async {
    return await _repo.getAll();
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
  }

  Future<Purchase?> getById(String id) async {
    return await _repo.getById(id);
  }

  Future<List<PurchaseItem>> getItems(String purchaseId) async {
    return await _repo.getItemsByPurchase(purchaseId);
  }
}
'@

    # ========================== PROVIDER IMPORTS FIX ==========================
    # Add missing imports to billing_screen.dart – but we'll create a fixed version

}

# Write all files
foreach ($key in $missingFiles.Keys) {
    $fullPath = Join-Path $base $key
    $dir = Split-Path $fullPath
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    Set-Content -Path $fullPath -Value $missingFiles[$key] -Force
    Write-Host "Created: $key" -ForegroundColor Green
}

Write-Host "`n✅ All missing providers and repositories created!" -ForegroundColor Green