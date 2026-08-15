import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:supermart_pos/constants/app_constants.dart';
import 'package:supermart_pos/core/database/database_helper.dart';
import 'package:supermart_pos/core/database/migrations/migration_v28.dart';

/// Points path_provider at a throwaway temp directory so
/// `DatabaseHelper.instance.database` (which resolves its file path via
/// `getApplicationDocumentsDirectory()`) can open a real sqflite (ffi)
/// database under `flutter_test`, instead of hitting a real app-data
/// directory or a missing platform channel.
class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this._path);
  final String _path;

  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
}

/// Column name -> declared type for [table], straight from SQLite's own
/// catalogue — so the two migration paths are compared on what SQLite
/// actually built, not on the DDL text we think we ran.
Future<Map<String, String>> _columns(DatabaseExecutor db, String table) async {
  final rows = await db.rawQuery('PRAGMA table_info($table)');
  return {
    for (final row in rows) row['name'] as String: (row['type'] as String).toUpperCase(),
  };
}

Future<Set<String>> _indexes(DatabaseExecutor db, String table) async {
  final rows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = ? AND name LIKE 'idx_%'",
    [table],
  );
  return rows.map((row) => row['name'] as String).toSet();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  /// The database built by `onCreate` (MigrationV1) — i.e. what a brand new
  /// install gets.
  late Database freshDb;

  /// A database with only the v28 GL migration applied — i.e. what an
  /// existing v27 install gets from `onUpgrade`.
  late Database upgradedDb;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('gl_schema_test');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
    freshDb = await DatabaseHelper.instance.database;

    sqfliteFfiInit();
    upgradedDb = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
      ),
    );
    await MigrationV28.up(upgradedDb);
  });

  tearDownAll(() async {
    await upgradedDb.close();
    await DatabaseHelper.instance.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('GL schema — fresh database (onCreate)', () {
    // Asserts a floor, not an exact number. The GL schema landed at v28, so
    // anything below that means the migration was lost; anything above is a
    // later migration doing its job and is none of this test's business. The
    // original `== 28` made every subsequent migration fail a GL test, which
    // says nothing about the GL schema — v29 (bank reconciliation) is what
    // tripped it.
    test('dbVersion is at least the GL version and the created database reports it', () async {
      expect(AppConstants.dbVersion, greaterThanOrEqualTo(28));
      expect(await freshDb.getVersion(), AppConstants.dbVersion);
    });

    test('all three GL tables exist', () async {
      final rows = await freshDb.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN "
        "('chart_of_accounts', 'gl_entries', 'gl_balances')",
      );
      expect(
        rows.map((row) => row['name']).toSet(),
        {'chart_of_accounts', 'gl_entries', 'gl_balances'},
      );
    });

    test('chart_of_accounts has every required column', () async {
      expect(
        (await _columns(freshDb, 'chart_of_accounts')).keys.toSet(),
        {
          'id', 'code', 'name', 'account_type', 'sub_type', 'parent_id',
          'is_active', 'description', 'opening_balance', 'created_at',
          'updated_at', 'is_system',
        },
      );
    });

    test('gl_entries has every required column, including reversal_of_entry_id', () async {
      expect(
        (await _columns(freshDb, 'gl_entries')).keys.toSet(),
        {
          'id', 'entry_date', 'reference_type', 'reference_id', 'description',
          'account_id', 'debit', 'credit', 'financial_year', 'created_by',
          'created_at', 'reversal_of_entry_id',
        },
      );
    });

    test('gl_balances has every required column', () async {
      expect(
        (await _columns(freshDb, 'gl_balances')).keys.toSet(),
        {
          'id', 'account_id', 'financial_year', 'total_debit', 'total_credit',
          'balance', 'last_updated',
        },
      );
    });

    test('all five GL indexes exist', () async {
      expect(await _indexes(freshDb, 'gl_entries'), {
        'idx_gl_entries_account',
        'idx_gl_entries_date',
        'idx_gl_entries_reference',
      });
      expect(await _indexes(freshDb, 'chart_of_accounts'), {
        'idx_chart_of_accounts_code',
        'idx_chart_of_accounts_parent',
      });
    });

    test('the default chart of accounts is seeded, all as system accounts', () async {
      final rows = await freshDb.query('chart_of_accounts', orderBy: 'code ASC');

      expect(rows.length, MigrationV28.defaultAccounts.length);
      expect(
        rows.map((row) => row['code']).toList(),
        ['1000', '1010', '1100', '1200', '1500', '2000', '2010', '2100', '2200',
         '3000', '3100', '4000', '4100', '4900', '5000', '5100', '5200', '5300',
         '5400', '5500'],
      );
      expect(rows.every((row) => row['is_system'] == 1), isTrue);
      expect(rows.every((row) => row['is_active'] == 1), isTrue);
      expect(rows.every((row) => (row['created_at'] as int) > 0), isTrue);
    });

    test('every seeded account carries a sub_type and a known account_type', () async {
      final rows = await freshDb.query('chart_of_accounts');

      expect(rows.every((row) => (row['sub_type'] as String?)?.isNotEmpty ?? false), isTrue);
      expect(
        rows.map((row) => row['account_type']).toSet(),
        {'asset', 'liability', 'equity', 'revenue', 'expense'},
      );
    });

    test('a duplicate account code is rejected', () async {
      expect(
        () => freshDb.insert('chart_of_accounts', {
          'id': 'coa_duplicate_probe',
          'code': '1000', // already seeded as Cash
          'name': 'Second Cash',
          'account_type': 'asset',
          'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        }),
        throwsA(isA<DatabaseException>()),
      );

      // The rejected insert left nothing behind.
      final probe = await freshDb.query(
        'chart_of_accounts',
        where: 'id = ?',
        whereArgs: ['coa_duplicate_probe'],
      );
      expect(probe, isEmpty);
    });

    test('gl_balances allows one row per account per financial year, not two', () async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      // Same account, two different years — fine.
      await freshDb.insert('gl_balances', {
        'id': 'bal_probe_25_26',
        'account_id': 'coa_1000',
        'financial_year': '25-26',
        'last_updated': now,
      });
      await freshDb.insert('gl_balances', {
        'id': 'bal_probe_26_27',
        'account_id': 'coa_1000',
        'financial_year': '26-27',
        'last_updated': now,
      });

      // Same account, same year again — rejected by UNIQUE(account_id, financial_year).
      expect(
        () => freshDb.insert('gl_balances', {
          'id': 'bal_probe_duplicate',
          'account_id': 'coa_1000',
          'financial_year': '25-26',
          'last_updated': now,
        }),
        throwsA(isA<DatabaseException>()),
      );

      await freshDb.delete('gl_balances', where: "id LIKE 'bal_probe_%'");
    });

    test('a gl_entries row pointing at a non-existent account is rejected', () async {
      // The app switches `PRAGMA foreign_keys = ON` on every connection, so
      // the FK on account_id is really enforced, not just documentation.
      expect(
        () => freshDb.insert('gl_entries', {
          'id': 'gle_probe_orphan',
          'entry_date': DateTime.now().millisecondsSinceEpoch ~/ 1000,
          'reference_type': 'Manual',
          'description': 'orphan probe',
          'account_id': 'coa_does_not_exist',
          'debit': 10.0,
          'credit': 0.0,
          'financial_year': '25-26',
          'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        }),
        throwsA(isA<DatabaseException>()),
      );
    });
  });

  group('GL schema — upgraded database (onUpgrade v27 -> v28)', () {
    test('produces the same tables and columns as a fresh database', () async {
      for (final table in ['chart_of_accounts', 'gl_entries', 'gl_balances']) {
        expect(
          await _columns(upgradedDb, table),
          await _columns(freshDb, table),
          reason: '$table differs between the onCreate and onUpgrade paths',
        );
      }
    });

    test('produces the same GL indexes as a fresh database', () async {
      for (final table in ['chart_of_accounts', 'gl_entries']) {
        expect(await _indexes(upgradedDb, table), await _indexes(freshDb, table));
      }
    });

    test('seeds the identical default chart of accounts', () async {
      Future<List<Object?>> codesAndTypes(DatabaseExecutor db) async {
        final rows = await db.query('chart_of_accounts', orderBy: 'code ASC');
        return rows.map((row) => '${row['code']}|${row['name']}|${row['account_type']}|${row['sub_type']}').toList();
      }

      expect(await codesAndTypes(upgradedDb), await codesAndTypes(freshDb));
    });

    test('re-running the migration does not duplicate accounts', () async {
      final before = await upgradedDb.query('chart_of_accounts');

      await MigrationV28.up(upgradedDb);

      final after = await upgradedDb.query('chart_of_accounts');
      expect(after.length, before.length);
      expect(after.length, MigrationV28.defaultAccounts.length);
    });

    test('re-seeding leaves a user-renamed account untouched', () async {
      await upgradedDb.update(
        'chart_of_accounts',
        {'name': 'Petty Cash (renamed by user)'},
        where: 'code = ?',
        whereArgs: ['1000'],
      );

      await MigrationV28.seedDefaultAccounts(upgradedDb);

      final rows = await upgradedDb.query('chart_of_accounts', where: 'code = ?', whereArgs: ['1000']);
      expect(rows.single['name'], 'Petty Cash (renamed by user)');
    });
  });
}
