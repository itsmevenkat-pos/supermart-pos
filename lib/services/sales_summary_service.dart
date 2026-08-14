import '../core/database/database_helper.dart';
import '../models/sale_model.dart';

class SalesSummaryService {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<Map<String, dynamic>> getSummary({DateTime? from, DateTime? to, String? userId}) async {
    final db = await _dbHelper.database;
    final fromTime = from != null ? from.millisecondsSinceEpoch ~/ 1000 : 0;
    final toTime = to != null ? to.millisecondsSinceEpoch ~/ 1000 : DateTime.now().millisecondsSinceEpoch ~/ 1000;

    // Get all sales in date range
    final result = await db.query(
      'sales',
      where: userId != null
          ? 'created_at >= ? AND created_at <= ? AND status = ? AND user_id = ?'
          : 'created_at >= ? AND created_at <= ? AND status = ?',
      whereArgs: userId != null
          ? [fromTime, toTime, 'completed', userId]
          : [fromTime, toTime, 'completed'],
    );

    double totalCash = 0;
    double totalUpi = 0;
    double totalCard = 0;
    double totalCredit = 0;
    double totalPartial = 0;
    double totalAmount = 0;
    int totalCount = 0;

    for (final row in result) {
      final sale = Sale.fromJson(row);
      totalAmount += sale.netAmount;
      totalCount++;

      final methods = sale.paymentMethods ?? {};
      for (final entry in methods.entries) {
        if (entry.value <= 0) continue;
        final method = entry.key.toLowerCase();
        final amount = entry.value;

        if (method == 'cash') {
          totalCash += amount;
        } else if (method == 'upi') {
          totalUpi += amount;
        } else if (method == 'card') {
          totalCard += amount;
        } else if (method == 'credit') {
          totalCredit += amount;
        }

        // Check if partial payment (multiple methods)
        if (methods.length > 1) {
          totalPartial += amount;
        }
      }
    }

    return {
      'totalSales': totalAmount,
      'totalCount': totalCount,
      'cash': totalCash,
      'upi': totalUpi,
      'card': totalCard,
      'credit': totalCredit,
      'partial': totalPartial,
    };
  }

  Future<Map<String, dynamic>> getTodaySummary({String? userId}) async {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);
    return await getSummary(from: start, userId: userId);
  }
}
