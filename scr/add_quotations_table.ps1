# add_quotations_table.ps1 – Adds quotations table via migration
$base = "lib"

$files = @{

    # ---------- UPDATE DATABASE HELPER ----------
    "core/database/database_helper.dart" = @'
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import 'package:uuid/uuid.dart';
import 'migrations/migration_v1.dart';
import '../../constants/app_constants.dart';

class DatabaseHelper {
  DatabaseHelper._privateConstructor();
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, AppConstants.dbName);

    return await openDatabase(
      path,
      version: AppConstants.dbVersion,
      onCreate: (db, version) async {
        await MigrationV1.up(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // Migrations from version 2 to 3 (add quotations)
        if (oldVersion < 2) {
          // If old version is 1, apply all upgrades up to 2
          // but we already have version 2 from earlier migration
          // So we only need to handle from 2 to 3
        }
        if (oldVersion < 3) {
          // Add quotations table
          await db.execute('''
            CREATE TABLE quotations (
              id TEXT PRIMARY KEY,
              store_id TEXT REFERENCES stores(id) ON DELETE CASCADE,
              customer_id TEXT REFERENCES customers(id) ON DELETE SET NULL,
              customer_name TEXT NOT NULL,
              customer_phone TEXT,
              customer_email TEXT,
              quote_no TEXT NOT NULL,
              subtotal REAL NOT NULL DEFAULT 0,
              tax_total REAL NOT NULL DEFAULT 0,
              discount_total REAL NOT NULL DEFAULT 0,
              discount_reason TEXT,
              net_amount REAL NOT NULL DEFAULT 0,
              notes TEXT,
              expiry_date INTEGER,
              status TEXT DEFAULT 'pending',
              created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
              updated_at INTEGER
            )
          ''');
          await db.execute('CREATE INDEX idx_quotations_customer ON quotations(customer_id)');
          await db.execute('CREATE INDEX idx_quotations_status ON quotations(status)');
          // Set version to 3
          await db.setVersion(3);
        }
      },
    );
  }

  Future<void> queueSync(
    String table,
    String recordId,
    String operation,
    Map<String, dynamic> payload,
  ) async {
    final db = await database;
    await db.insert('sync_queue', {
      'id': const Uuid().v4(),
      'table_name': table,
      'record_id': recordId,
      'operation': operation,
      'payload_json': jsonEncode(payload),
      'retry_count': 0,
      'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    });
  }

  Future<void> logAudit({
    required String userId,
    required String actionType,
    required String tableName,
    required String recordId,
    String? oldValue,
    String? newValue,
  }) async {
    final db = await database;
    await db.insert('audit_log', {
      'id': const Uuid().v4(),
      'user_id': userId,
      'action_type': actionType,
      'table_name': tableName,
      'record_id': recordId,
      'old_value': oldValue,
      'new_value': newValue,
      'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    });
  }
}
'@

    # ---------- UPDATE VERSION IN CONSTANTS ----------
    "constants/app_constants.dart" = @'
class AppConstants {
  static const String appName = 'SuperMart POS Enterprise';
  static const String dbName = 'super_mart_pos.db';
  static const int dbVersion = 3; // ✅ updated from 2 to 3
  static const int sessionTimeoutSeconds = 300;
  static const double bonusPointsThreshold = 300.0;
  static const double bonusPointValue = 0.50;
}
'@

}

# Write files
foreach ($key in $files.Keys) {
    $fullPath = Join-Path $base $key
    $dir = Split-Path $fullPath
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    Set-Content -Path $fullPath -Value $files[$key] -Force
    Write-Host "Updated: $key" -ForegroundColor Green
}

Write-Host "`n✅ Quotations table added!" -ForegroundColor Cyan
Write-Host "`nNow run:" -ForegroundColor Yellow
Write-Host "flutter clean" -ForegroundColor White
Write-Host "flutter pub get" -ForegroundColor White
Write-Host "flutter pub run build_runner build --delete-conflicting-outputs" -ForegroundColor White
Write-Host "flutter run -d windows" -ForegroundColor White