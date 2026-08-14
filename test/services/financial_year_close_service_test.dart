import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:supermart_pos/core/database/database_helper.dart';
import 'package:supermart_pos/services/financial_year_close_service.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late FinancialYearCloseService service;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('fy_close_test');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);

    // `financial_year_closures.closed_by_user_id` has an FK to `users(id)`
    // and the app enables `PRAGMA foreign_keys = ON` on every connection, so
    // the test user referenced below must actually exist.
    final db = await DatabaseHelper.instance.database;
    await db.insert('users', {
      'id': 'test-user-1',
      'username': 'test_admin',
      'password_hash': 'x',
      'role': 'admin',
      'name': 'Test Admin',
      'must_change_password': 0,
      'is_active': 1,
      'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    });
  });

  tearDownAll(() async {
    await DatabaseHelper.instance.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  setUp(() {
    service = FinancialYearCloseService();
  });

  group('FinancialYearCloseService', () {
    test('closing a fresh financial year succeeds and is reflected in isFinancialYearClosed', () async {
      const fy = '19-20';

      expect(await service.isFinancialYearClosed(fy), isFalse);

      await service.closeFinancialYear(financialYear: fy, userId: 'test-user-1');

      expect(await service.isFinancialYearClosed(fy), isTrue);

      final closed = await service.getClosedFinancialYears();
      expect(closed.any((row) => row['financial_year'] == fy), isTrue);
    });

    test('closing the same financial year twice throws on the second attempt', () async {
      const fy = '20-21';

      await service.closeFinancialYear(financialYear: fy, userId: 'test-user-1');

      expect(
        () => service.closeFinancialYear(financialYear: fy, userId: 'test-user-1'),
        throwsA(isA<Exception>()),
      );

      // Still only one row for this financial year — the failed second
      // attempt did not leave a partial/duplicate write behind.
      final closed = await service.getClosedFinancialYears();
      expect(closed.where((row) => row['financial_year'] == fy).length, 1);
    });
  });
}
