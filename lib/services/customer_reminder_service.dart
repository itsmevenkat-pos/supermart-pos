import '../core/database/database_helper.dart';

/// One customer's purchase-recency snapshot, for the Service Reminders
/// screen — who hasn't come back in a while and what they usually buy, so
/// staff know who to follow up with and what to mention.
class CustomerReminderInfo {
  final String customerId;
  final String name;
  final String phone;
  final DateTime lastPurchaseDate;
  final int daysSinceLastPurchase;
  final int orderCount;
  final List<String> topProducts;

  CustomerReminderInfo({
    required this.customerId,
    required this.name,
    required this.phone,
    required this.lastPurchaseDate,
    required this.daysSinceLastPurchase,
    required this.orderCount,
    required this.topProducts,
  });
}

class CustomerReminderService {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  /// Every customer with at least one completed sale, their last purchase
  /// date, and their top 3 most-bought products by quantity — sorted with
  /// the longest-lapsed customers first.
  Future<List<CustomerReminderInfo>> getCustomerReminders() async {
    final db = await _dbHelper.database;

    final lastPurchaseRows = await db.rawQuery('''
      SELECT c.id AS customerId, c.name AS name, c.phone AS phone,
             MAX(s.created_at) AS lastPurchase, COUNT(s.id) AS orderCount
      FROM customers c
      INNER JOIN sales s ON s.customer_id = c.id AND s.status = 'completed'
      WHERE c.is_deleted = 0
      GROUP BY c.id
    ''');

    // Grouped by customer then sorted by quantity within that group (rather
    // than a window function, for compatibility with older bundled SQLite
    // builds) so the top-N-per-customer pick below is a simple scan.
    final productRows = await db.rawQuery('''
      SELECT s.customer_id AS customerId, p.name AS productName, SUM(si.quantity) AS totalQty
      FROM sale_items si
      INNER JOIN sales s ON s.id = si.sale_id AND s.status = 'completed'
      INNER JOIN products p ON p.id = si.product_id
      WHERE s.customer_id IS NOT NULL
      GROUP BY s.customer_id, si.product_id
      ORDER BY s.customer_id, totalQty DESC
    ''');

    const topProductsPerCustomer = 3;
    final topProductsByCustomer = <String, List<String>>{};
    for (final row in productRows) {
      final customerId = row['customerId'] as String;
      final list = topProductsByCustomer.putIfAbsent(customerId, () => []);
      if (list.length < topProductsPerCustomer) {
        list.add(row['productName'] as String);
      }
    }

    final now = DateTime.now();
    final result = lastPurchaseRows.map((row) {
      final customerId = row['customerId'] as String;
      final lastPurchase = DateTime.fromMillisecondsSinceEpoch((row['lastPurchase'] as int) * 1000);
      return CustomerReminderInfo(
        customerId: customerId,
        name: row['name'] as String,
        phone: row['phone'] as String,
        lastPurchaseDate: lastPurchase,
        daysSinceLastPurchase: now.difference(lastPurchase).inDays,
        orderCount: row['orderCount'] as int,
        topProducts: topProductsByCustomer[customerId] ?? const [],
      );
    }).toList();

    result.sort((a, b) => b.daysSinceLastPurchase.compareTo(a.daysSinceLastPurchase));
    return result;
  }
}
