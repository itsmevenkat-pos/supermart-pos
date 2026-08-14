import '../core/database/database_helper.dart';
import '../models/festival_model.dart';

class FestivalRepository {
  FestivalRepository({DatabaseHelper? dbHelper}) : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _dbHelper;

  Future<List<Festival>> getAll() async {
    final db = await _dbHelper.database;
    final result = await db.query('festival_calendar', orderBy: 'month ASC, day ASC');
    return result.map((e) => Festival.fromJson(e)).toList();
  }

  Future<void> insert(Festival festival) async {
    final db = await _dbHelper.database;
    await db.insert('festival_calendar', festival.toJson());
  }

  Future<void> update(Festival festival) async {
    final db = await _dbHelper.database;
    await db.update('festival_calendar', festival.toJson(), where: 'id = ?', whereArgs: [festival.id]);
  }

  Future<void> delete(String id) async {
    final db = await _dbHelper.database;
    await db.delete('festival_calendar', where: 'id = ?', whereArgs: [id]);
  }

  /// The nearest upcoming active festival from [from] (today, normally),
  /// or null if none are active. Wraps to next year for a month/day that's
  /// already passed this year, so this always returns the *next*
  /// occurrence, never a date in the past.
  Future<({Festival festival, DateTime date, int daysUntil})?> nextUpcoming(DateTime from) async {
    final festivals = (await getAll()).where((f) => f.isActive).toList();
    if (festivals.isEmpty) return null;

    final today = DateTime(from.year, from.month, from.day);
    ({Festival festival, DateTime date, int daysUntil})? nearest;

    for (final festival in festivals) {
      final date = _occurrenceOnOrAfter(festival, today);
      final daysUntil = date.difference(today).inDays;
      if (nearest == null || daysUntil < nearest.daysUntil) {
        nearest = (festival: festival, date: date, daysUntil: daysUntil);
      }
    }
    return nearest;
  }

  DateTime _occurrenceOnOrAfter(Festival festival, DateTime today) {
    final thisYear = _clampedDate(today.year, festival.month, festival.day);
    if (!thisYear.isBefore(today)) return thisYear;
    return _clampedDate(today.year + 1, festival.month, festival.day);
  }

  // Clamps day-of-month (e.g. Feb 30 from a mis-edited entry) into that
  // month's actual last day instead of DateTime silently rolling over into
  // the next month.
  DateTime _clampedDate(int year, int month, int day) {
    final lastDayOfMonth = DateTime(year, month + 1, 0).day;
    return DateTime(year, month, day > lastDayOfMonth ? lastDayOfMonth : day);
  }
}
