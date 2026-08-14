import '../core/database/database_helper.dart';
import '../models/sale_model.dart';
import '../models/sale_item_model.dart';

class SyncService {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<void> queueSale(Sale sale, List<SaleItem> items) async {
    final payload = {
      'sale': sale.toJson(),
      'items': items.map((e) => e.toJson()).toList(),
    };
    await _dbHelper.queueSync('sales', sale.id, 'INSERT', payload);
  }

  Future<int> getPendingCount() async {
    final db = await _dbHelper.database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM sync_queue WHERE retry_count < 5');
    return result.first['count'] as int? ?? 0;
  }
}
