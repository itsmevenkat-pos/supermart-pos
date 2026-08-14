import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/database/database_helper.dart';

/// Multi-store sync against Supabase. See SUPABASE_SYNC_DESIGN.md at the
/// project root for the full design and the reasoning behind the choices
/// below — this is the client implementation of that design.
///
/// SETUP REQUIRED before this works: create a Supabase project, run the
/// mirrored schema described in SUPABASE_SYNC_DESIGN.md, and paste the
/// project URL and anon key into [supabaseUrl]/[supabaseAnonKey]. Until
/// then, [isConfigured] is false and every method throws immediately
/// rather than silently doing nothing.
class SupabaseSyncService {
  static const String supabaseUrl = 'YOUR_SUPABASE_PROJECT_URL';
  static const String supabaseAnonKey = 'YOUR_SUPABASE_ANON_KEY';

  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  SupabaseClient? _client;

  bool get isConfigured => !supabaseUrl.startsWith('YOUR_') && !supabaseAnonKey.startsWith('YOUR_');

  SupabaseClient _requireClient() {
    if (!isConfigured) {
      throw Exception(
        'Supabase sync is not set up yet — add your project URL/anon key in '
        'supabase_sync_service.dart (see SUPABASE_SYNC_DESIGN.md for setup steps).',
      );
    }
    return _client ??= SupabaseClient(supabaseUrl, supabaseAnonKey);
  }

  /// PUSH: drains the local `sync_queue` outbox that every repository
  /// already writes to on insert/update/delete (see
  /// `DatabaseHelper.queueSync` and its call sites). Deliberately
  /// table-agnostic — it replays `payload_json` as an upsert (or issues a
  /// delete) without needing to know each table's columns, so it doesn't
  /// need updating every time a table gains a column elsewhere in the app.
  Future<SyncPushResult> pushPending({int batchSize = 100}) async {
    final client = _requireClient();
    final db = await _dbHelper.database;
    final rows = await db.query(
      'sync_queue',
      where: 'retry_count < 5',
      orderBy: 'created_at ASC',
      limit: batchSize,
    );

    var pushed = 0;
    var failed = 0;
    for (final row in rows) {
      final id = row['id'] as String;
      final tableName = row['table_name'] as String;
      final operation = row['operation'] as String;
      final payload = jsonDecode(row['payload_json'] as String) as Map<String, dynamic>;

      try {
        if (operation == 'DELETE') {
          await client.from(tableName).delete().eq('id', payload['id']);
        } else {
          // INSERT and UPDATE both upsert. For append-only tables (sales,
          // sale_items, purchases, purchase_items, stock_ledger,
          // customer_ledger, supplier_ledger, payments) this is
          // conflict-free by construction: ids are client-generated UUIDs
          // and a row is written exactly once by the store that created
          // it. For mutable/shared tables (products, customers, suppliers)
          // this is Last-Write-Wins by wall-clock push order — see
          // SUPABASE_SYNC_DESIGN.md for why that's an acceptable tradeoff
          // at this scale.
          await client.from(tableName).upsert(payload);
        }
        await db.delete('sync_queue', where: 'id = ?', whereArgs: [id]);
        pushed++;
      } catch (_) {
        await db.rawUpdate('UPDATE sync_queue SET retry_count = retry_count + 1 WHERE id = ?', [id]);
        failed++;
      }
    }
    return SyncPushResult(pushed: pushed, failed: failed);
  }

  /// PULL: brings down master-data changes — product catalog/pricing,
  /// customers, suppliers — from Supabase (e.g. pushed centrally by HQ, or
  /// created at another store). Last-Write-Wins by `updated_at`: a remote
  /// row only overwrites the local one if it's actually newer.
  ///
  /// `stock_quantity` is deliberately excluded from the products pull —
  /// stock is store-local and derived from this store's own stock_ledger;
  /// applying a remote value here would silently overwrite real local
  /// stock with whatever another store happens to have on hand. Categories
  /// aren't pulled: that table has no `updated_at` column to diff
  /// against today (rarely changes; add a timestamp column first if
  /// central category sync becomes a real need).
  Future<SyncPullResult> pullMasterData() async {
    final client = _requireClient();
    final updated = <String, int>{
      'products': await _pullTable(client, tableName: 'products', excludeColumnsOnUpdate: const ['stock_quantity']),
      'customers': await _pullTable(client, tableName: 'customers'),
      'suppliers': await _pullTable(client, tableName: 'suppliers'),
    };
    return SyncPullResult(updated);
  }

  Future<int> _pullTable(
    SupabaseClient client, {
    required String tableName,
    List<String> excludeColumnsOnUpdate = const [],
  }) async {
    final db = await _dbHelper.database;
    final stateRows = await db.query('sync_state', where: 'table_name = ?', whereArgs: [tableName]);
    final lastPulledAt = stateRows.isNotEmpty ? stateRows.first['last_pulled_at'] as int : 0;

    final remoteRows = await client.from(tableName).select().gt('updated_at', lastPulledAt).order('updated_at');

    var applied = 0;
    var maxUpdatedAt = lastPulledAt;
    for (final remote in (remoteRows as List).cast<Map<String, dynamic>>()) {
      final id = remote['id'] as String;
      final remoteUpdatedAt = (remote['updated_at'] as num?)?.toInt() ?? 0;
      if (remoteUpdatedAt > maxUpdatedAt) maxUpdatedAt = remoteUpdatedAt;

      final localRows = await db.query(tableName, where: 'id = ?', whereArgs: [id]);
      final localUpdatedAt = localRows.isNotEmpty ? (localRows.first['updated_at'] as num?)?.toInt() ?? 0 : -1;
      if (remoteUpdatedAt <= localUpdatedAt) continue;

      final data = Map<String, dynamic>.from(remote);
      if (localRows.isNotEmpty) {
        for (final col in excludeColumnsOnUpdate) {
          data.remove(col);
        }
        await db.update(tableName, data, where: 'id = ?', whereArgs: [id]);
      } else {
        await db.insert(tableName, data);
      }
      applied++;
    }

    await db.insert(
      'sync_state',
      {'table_name': tableName, 'last_pulled_at': maxUpdatedAt},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return applied;
  }

  Future<SyncStatus> getStatus() async {
    final db = await _dbHelper.database;
    final pendingResult = await db.rawQuery('SELECT COUNT(*) as count FROM sync_queue WHERE retry_count < 5');
    final failedResult = await db.rawQuery('SELECT COUNT(*) as count FROM sync_queue WHERE retry_count >= 5');
    final stateRows = await db.query('sync_state', orderBy: 'last_pulled_at DESC', limit: 1);
    final lastPulledAt = stateRows.isNotEmpty ? stateRows.first['last_pulled_at'] as int : null;

    return SyncStatus(
      isConfigured: isConfigured,
      pendingCount: (pendingResult.first['count'] as int?) ?? 0,
      failedCount: (failedResult.first['count'] as int?) ?? 0,
      lastPulledAt: lastPulledAt != null && lastPulledAt > 0
          ? DateTime.fromMillisecondsSinceEpoch(lastPulledAt * 1000)
          : null,
    );
  }
}

class SyncPushResult {
  final int pushed;
  final int failed;
  const SyncPushResult({required this.pushed, required this.failed});
}

class SyncPullResult {
  final Map<String, int> updatedPerTable;
  const SyncPullResult(this.updatedPerTable);
}

class SyncStatus {
  final bool isConfigured;
  final int pendingCount;
  final int failedCount;
  final DateTime? lastPulledAt;
  const SyncStatus({
    required this.isConfigured,
    required this.pendingCount,
    required this.failedCount,
    this.lastPulledAt,
  });
}
