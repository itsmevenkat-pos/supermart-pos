import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/database/database_helper.dart';
import '../models/salesman_model.dart';

/// Aggregated performance figures for a salesman — sale count and total net
/// sales amount, joined from the `sales` table. Read-only; not persisted.
class SalesmanPerformance {
  final Salesman salesman;
  final int saleCount;
  final double totalAmount;

  const SalesmanPerformance({
    required this.salesman,
    required this.saleCount,
    required this.totalAmount,
  });
}

/// Injected via constructor so tests can pass a fake/in-memory [DatabaseHelper]
/// instead of the real singleton. Existing call sites that used
/// `SalesmanRepository()` still compile unchanged because [dbHelper] defaults
/// to the app-wide singleton.
class SalesmanRepository {
  SalesmanRepository({DatabaseHelper? dbHelper})
      : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _dbHelper;

  Future<List<Salesman>> getAll({bool activeOnly = false}) async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'salesmen',
      where: activeOnly ? 'is_active = 1' : null,
      orderBy: 'name ASC',
    );
    return result.map((e) => Salesman.fromJson(e)).toList();
  }

  Future<Salesman?> getById(String id) async {
    final db = await _dbHelper.database;
    final result = await db.query('salesmen', where: 'id = ?', whereArgs: [id]);
    if (result.isEmpty) return null;
    return Salesman.fromJson(result.first);
  }

  Future<void> insert(Salesman salesman) async {
    final db = await _dbHelper.database;
    await db.insert('salesmen', salesman.toJson());
    await _dbHelper.queueSync('salesmen', salesman.id, 'INSERT', salesman.toJson());
  }

  Future<void> update(Salesman salesman) async {
    final db = await _dbHelper.database;
    await db.update('salesmen', salesman.toJson(), where: 'id = ?', whereArgs: [salesman.id]);
    await _dbHelper.queueSync('salesmen', salesman.id, 'UPDATE', salesman.toJson());
  }

  Future<void> setActive(String id, bool active) async {
    final db = await _dbHelper.database;
    await db.update(
      'salesmen',
      {'is_active': active ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
    await _dbHelper.queueSync('salesmen', id, 'UPDATE', {'id': id, 'is_active': active ? 1 : 0});
  }

  /// Sale count and total net-amount per active salesman, sorted by total
  /// descending — used by the Track Your Salesmen screen.
  Future<List<SalesmanPerformance>> getPerformance() async {
    final db = await _dbHelper.database;
    final rows = await db.rawQuery('''
      SELECT s.id, s.name, s.phone, s.is_active, s.created_at, s.store_id,
             COUNT(sa.id) as sale_count,
             COALESCE(SUM(sa.net_amount), 0) as total_amount
      FROM salesmen s
      LEFT JOIN sales sa ON sa.salesman_id = s.id
      WHERE s.is_active = 1
      GROUP BY s.id
      ORDER BY total_amount DESC
    ''');

    return rows.map((row) {
      final salesman = Salesman.fromJson(row);
      return SalesmanPerformance(
        salesman: salesman,
        saleCount: (row['sale_count'] as num?)?.toInt() ?? 0,
        totalAmount: (row['total_amount'] as num?)?.toDouble() ?? 0,
      );
    }).toList();
  }
}

/// Riverpod provider — override this in tests with a fake DatabaseHelper-backed
/// repository, e.g.:
///   ProviderScope(overrides: [
///     salesmanRepositoryProvider.overrideWithValue(SalesmanRepository(dbHelper: fakeDb)),
///   ])
final salesmanRepositoryProvider = Provider<SalesmanRepository>((ref) => SalesmanRepository());
