import '../core/database/database_helper.dart';
import '../models/supplier_model.dart';

class SupplierRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<List<Supplier>> getAll() async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'suppliers',
      where: 'is_deleted = 0',
      orderBy: 'name ASC',
    );
    return result.map((e) => Supplier.fromJson(e)).toList();
  }

  Future<Supplier?> getById(String id) async {
    final db = await _dbHelper.database;
    final result = await db.query('suppliers', where: 'id = ?', whereArgs: [id]);
    if (result.isEmpty) return null;
    return Supplier.fromJson(result.first);
  }

  Future<Supplier?> getByName(String name) async {
    final db = await _dbHelper.database;
    final result = await db.query('suppliers', where: 'name = ?', whereArgs: [name]);
    if (result.isEmpty) return null;
    return Supplier.fromJson(result.first);
  }

  Future<void> insert(Supplier supplier) async {
    final db = await _dbHelper.database;
    await db.insert('suppliers', supplier.toJson());
    await _dbHelper.queueSync('suppliers', supplier.id, 'INSERT', supplier.toJson());
  }

  Future<void> update(Supplier supplier) async {
    final db = await _dbHelper.database;
    await db.update('suppliers', supplier.toJson(), where: 'id = ?', whereArgs: [supplier.id]);
    await _dbHelper.queueSync('suppliers', supplier.id, 'UPDATE', supplier.toJson());
  }

  /// Inserts many suppliers in a single transaction — used by the
  /// Import Parties screen.
  Future<void> bulkInsert(List<Supplier> suppliers) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      for (final supplier in suppliers) {
        await txn.insert('suppliers', supplier.toJson());
        await _dbHelper.queueSync('suppliers', supplier.id, 'INSERT', supplier.toJson(), executor: txn);
      }
    });
  }

  Future<List<Supplier>> search(String query) async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'suppliers',
      where: '(name LIKE ? OR phone LIKE ?) AND is_deleted = 0',
      whereArgs: ['%$query%', '%$query%'],
      limit: 20,
    );
    return result.map((e) => Supplier.fromJson(e)).toList();
  }
}