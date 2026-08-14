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
