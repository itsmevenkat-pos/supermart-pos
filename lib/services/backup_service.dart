import 'dart:io';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../core/database/database_helper.dart';

/// Backup/restore for the local SQLite database. Local-folder/USB backup is
/// fully self-contained here; cloud-drive uploads (Google Drive, OneDrive)
/// reuse [createBackupFile] to produce the same staged file and just add
/// their own upload step on top.
class BackupService {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  String _backupFileName() {
    final now = DateTime.now();
    final ts = '${now.year}${_pad(now.month)}${_pad(now.day)}_'
        '${_pad(now.hour)}${_pad(now.minute)}${_pad(now.second)}';
    return 'supermart_backup_$ts.db';
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  /// Copies the live database into the system temp directory under a
  /// timestamped name. This is the shared first step for every backup
  /// destination (local folder, Google Drive, OneDrive) — each of those
  /// just does something different with the file this returns.
  Future<File> createBackupFile() async {
    final dbPath = await _dbHelper.getDatabasePath();
    final sourceFile = File(dbPath);
    if (!await sourceFile.exists()) {
      throw Exception('No database file found to back up.');
    }
    final tempDir = await getTemporaryDirectory();
    final backupPath = join(tempDir.path, _backupFileName());
    return sourceFile.copy(backupPath);
  }

  /// Copies a fresh backup into [destinationDir] — a local folder path or
  /// an attached USB/external drive's mount path. Returns the final path.
  Future<String> backupToLocalFolder(String destinationDir) async {
    final backupFile = await createBackupFile();
    final destinationPath = join(destinationDir, basename(backupFile.path));
    await backupFile.copy(destinationPath);
    return destinationPath;
  }

  /// Restores the database from [backupFilePath]. Validates the file looks
  /// like a real SuperMart POS database before touching anything, then
  /// saves a safety copy of the current live database (so a bad restore
  /// is itself recoverable) before swapping the backup file in.
  ///
  /// The app must be restarted after this returns — connections already
  /// opened elsewhere in the running process don't observe a file that was
  /// swapped out from under them.
  Future<void> restoreBackup(String backupFilePath) async {
    final backupFile = File(backupFilePath);
    if (!await backupFile.exists()) {
      throw Exception('Backup file not found: $backupFilePath');
    }
    await _validateDatabaseFile(backupFile);

    final dbPath = await _dbHelper.getDatabasePath();
    await _dbHelper.close();

    final liveFile = File(dbPath);
    if (await liveFile.exists()) {
      final safetyPath = '$dbPath.before_restore_${DateTime.now().millisecondsSinceEpoch}.bak';
      await liveFile.copy(safetyPath);
    }

    await backupFile.copy(dbPath);
  }

  /// Opens [file] read-only and checks for a `sales` table — enough to
  /// reject an unrelated file without depending on the exact current
  /// schema version (restoring an older backup is expected to work; the
  /// app's own migration path upgrades it on next launch).
  Future<void> _validateDatabaseFile(File file) async {
    sqfliteFfiInit();
    Database? db;
    try {
      db = await databaseFactoryFfi.openDatabase(
        file.path,
        options: OpenDatabaseOptions(readOnly: true),
      );
      final tables = await db.query(
        'sqlite_master',
        where: 'type = ? AND name = ?',
        whereArgs: ['table', 'sales'],
      );
      if (tables.isEmpty) {
        throw Exception('This file does not look like a valid SuperMart POS backup.');
      }
    } on Exception catch (e) {
      if (e.toString().contains('does not look like')) rethrow;
      throw Exception('Could not read this file as a database backup: $e');
    } finally {
      await db?.close();
    }
  }
}
