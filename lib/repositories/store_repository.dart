import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/database/database_helper.dart';
import '../models/store_model.dart';

/// The store row is currently a single hardcoded 'store_default' record
/// seeded at install time (see MigrationV1) — there's no multi-store UI yet,
/// so this repository only deals with that one row.
class StoreRepository {
  StoreRepository({DatabaseHelper? dbHelper}) : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _dbHelper;

  static const String defaultStoreId = 'store_default';

  Future<Store> getStore() async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'stores',
      where: 'id = ?',
      whereArgs: [defaultStoreId],
      limit: 1,
    );
    if (result.isEmpty) {
      return const Store(id: defaultStoreId, name: 'Main Store');
    }
    return Store.fromJson(result.first);
  }

  Future<void> updateStore(Store store) async {
    final db = await _dbHelper.database;
    final data = store.toJson()..remove('id');
    await db.update(
      'stores',
      data,
      where: 'id = ?',
      whereArgs: [defaultStoreId],
    );
  }

  Future<String> getInvoicePrefix() async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'stores',
      columns: ['invoice_prefix'],
      where: 'id = ?',
      whereArgs: [defaultStoreId],
      limit: 1,
    );
    if (result.isEmpty) return 'SM';
    return (result.first['invoice_prefix'] as String?) ?? 'SM';
  }

  Future<void> updateInvoicePrefix(String prefix) async {
    final db = await _dbHelper.database;
    await db.update(
      'stores',
      {'invoice_prefix': prefix},
      where: 'id = ?',
      whereArgs: [defaultStoreId],
    );
  }

  Future<double> getReturnThreshold() async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'stores',
      columns: ['return_threshold_no_approval'],
      where: 'id = ?',
      whereArgs: [defaultStoreId],
      limit: 1,
    );
    if (result.isEmpty) return 500;
    return (result.first['return_threshold_no_approval'] as num?)?.toDouble() ?? 500;
  }

  Future<void> updateReturnThreshold(double threshold) async {
    final db = await _dbHelper.database;
    await db.update(
      'stores',
      {'return_threshold_no_approval': threshold},
      where: 'id = ?',
      whereArgs: [defaultStoreId],
    );
  }

  /// A cashier can apply a discount up to this percentage of the bill
  /// subtotal without manager approval; above it, `requirePriceOverrideAuth`
  /// still gates the discount, same as before this existed.
  Future<double> getMaxDiscountPercent() async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'stores',
      columns: ['max_discount_percent_no_approval'],
      where: 'id = ?',
      whereArgs: [defaultStoreId],
      limit: 1,
    );
    if (result.isEmpty) return 10;
    return (result.first['max_discount_percent_no_approval'] as num?)?.toDouble() ?? 10;
  }

  Future<void> updateMaxDiscountPercent(double percent) async {
    final db = await _dbHelper.database;
    await db.update(
      'stores',
      {'max_discount_percent_no_approval': percent},
      where: 'id = ?',
      whereArgs: [defaultStoreId],
    );
  }

  /// ₹ value of one redeemed loyalty point at checkout. See
  /// [getBonusPointsThreshold] for the separate earn-rate setting.
  Future<double> getLoyaltyValuePerPoint() async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'stores',
      columns: ['loyalty_value_per_point'],
      where: 'id = ?',
      whereArgs: [defaultStoreId],
      limit: 1,
    );
    if (result.isEmpty) return 0.5;
    return (result.first['loyalty_value_per_point'] as num?)?.toDouble() ?? 0.5;
  }

  Future<void> updateLoyaltyValuePerPoint(double value) async {
    final db = await _dbHelper.database;
    await db.update(
      'stores',
      {'loyalty_value_per_point': value},
      where: 'id = ?',
      whereArgs: [defaultStoreId],
    );
  }

  /// ₹ spent to earn 1 loyalty point (before the customer's tier
  /// multiplier — see `pointMultiplierForRating` in `loyalty_utils.dart`).
  /// Used to be a hardcoded `AppConstants.bonusPointsThreshold` with no way
  /// to change it; now a real per-store setting like [getLoyaltyValuePerPoint].
  Future<double> getBonusPointsThreshold() async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'stores',
      columns: ['bonus_points_threshold'],
      where: 'id = ?',
      whereArgs: [defaultStoreId],
      limit: 1,
    );
    if (result.isEmpty) return 300;
    return (result.first['bonus_points_threshold'] as num?)?.toDouble() ?? 300;
  }

  Future<void> updateBonusPointsThreshold(double value) async {
    final db = await _dbHelper.database;
    await db.update(
      'stores',
      {'bonus_points_threshold': value},
      where: 'id = ?',
      whereArgs: [defaultStoreId],
    );
  }

  /// How many days a loyalty point stays spendable after it is earned.
  ///
  /// **0 means points never expire**, which is the default and what every
  /// installation did before this setting existed — turning expiry on has to
  /// be a deliberate act by a manager, not something an upgrade does to a
  /// customer's balance behind their back.
  ///
  /// The value is read once when points are *earned* and frozen onto that
  /// event's `expires_at` (see `MigrationV30`), so changing it here affects
  /// future earnings only and cannot retroactively lapse points a customer has
  /// already been told they have.
  Future<int> getLoyaltyExpiryDays() async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'stores',
      columns: ['loyalty_points_expiry_days'],
      where: 'id = ?',
      whereArgs: [defaultStoreId],
      limit: 1,
    );
    if (result.isEmpty) return 0;
    return (result.first['loyalty_points_expiry_days'] as num?)?.toInt() ?? 0;
  }

  Future<void> updateLoyaltyExpiryDays(int days) async {
    final db = await _dbHelper.database;
    await db.update(
      'stores',
      {'loyalty_points_expiry_days': days < 0 ? 0 : days},
      where: 'id = ?',
      whereArgs: [defaultStoreId],
    );
  }

  /// Minimum lifetime spend to reach each membership tier — see
  /// `computeTier` in `loyalty_utils.dart` for how these are applied.
  Future<Map<String, double>> getTierThresholds() async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'stores',
      columns: ['tier_bronze_min_spent', 'tier_silver_min_spent', 'tier_gold_min_spent'],
      where: 'id = ?',
      whereArgs: [defaultStoreId],
      limit: 1,
    );
    if (result.isEmpty) {
      return {'bronze': 2000, 'silver': 10000, 'gold': 25000};
    }
    final row = result.first;
    return {
      'bronze': (row['tier_bronze_min_spent'] as num?)?.toDouble() ?? 2000,
      'silver': (row['tier_silver_min_spent'] as num?)?.toDouble() ?? 10000,
      'gold': (row['tier_gold_min_spent'] as num?)?.toDouble() ?? 25000,
    };
  }

  Future<void> updateTierThresholds({
    required double bronze,
    required double silver,
    required double gold,
  }) async {
    final db = await _dbHelper.database;
    await db.update(
      'stores',
      {
        'tier_bronze_min_spent': bronze,
        'tier_silver_min_spent': silver,
        'tier_gold_min_spent': gold,
      },
      where: 'id = ?',
      whereArgs: [defaultStoreId],
    );
  }

  /// Weighing-scale barcode prefix (e.g. "21") + whether the embedded value
  /// is a weight (grams) or a total price (paise). Empty prefix = feature
  /// disabled — see decodeWeighingBarcode in weighing_barcode.dart.
  Future<({String prefix, String valueType})> getWeighingBarcodeConfig() async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'stores',
      columns: ['weighing_barcode_prefix', 'weighing_barcode_value_type'],
      where: 'id = ?',
      whereArgs: [defaultStoreId],
      limit: 1,
    );
    if (result.isEmpty) return (prefix: '', valueType: 'weight_grams');
    return (
      prefix: (result.first['weighing_barcode_prefix'] as String?) ?? '',
      valueType: (result.first['weighing_barcode_value_type'] as String?) ?? 'weight_grams',
    );
  }

  Future<void> updateWeighingBarcodeConfig({required String prefix, required String valueType}) async {
    final db = await _dbHelper.database;
    await db.update(
      'stores',
      {'weighing_barcode_prefix': prefix, 'weighing_barcode_value_type': valueType},
      where: 'id = ?',
      whereArgs: [defaultStoreId],
    );
  }

  /// Thermal printer config. [type] is `'none'` (default — PDF/OS print
  /// dialog fallback), `'network'` ([target] is an IP address, [port]
  /// defaults to 9100), or `'windows'` ([target] is the exact Windows
  /// printer name). See ThermalPrintService.printEscPos.
  Future<({String type, String? target, int? port, int charsPerLine})> getPrinterConfig() async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'stores',
      columns: ['printer_type', 'printer_target', 'printer_port', 'printer_chars_per_line'],
      where: 'id = ?',
      whereArgs: [defaultStoreId],
      limit: 1,
    );
    if (result.isEmpty) return (type: 'none', target: null, port: null, charsPerLine: 32);
    final row = result.first;
    return (
      type: (row['printer_type'] as String?) ?? 'none',
      target: row['printer_target'] as String?,
      port: row['printer_port'] as int?,
      charsPerLine: (row['printer_chars_per_line'] as int?) ?? 32,
    );
  }

  Future<void> updatePrinterConfig({
    required String type,
    String? target,
    int? port,
    required int charsPerLine,
  }) async {
    final db = await _dbHelper.database;
    await db.update(
      'stores',
      {
        'printer_type': type,
        'printer_target': target,
        'printer_port': port,
        'printer_chars_per_line': charsPerLine,
      },
      where: 'id = ?',
      whereArgs: [defaultStoreId],
    );
  }

  /// Local Ollama config for the AI Analysis report's narrative summary.
  /// Disabled by default — see OllamaService for how [baseUrl]/[model] are
  /// used, and why a failed call there never throws.
  Future<({bool enabled, String baseUrl, String model})> getOllamaConfig() async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'stores',
      columns: ['ollama_enabled', 'ollama_base_url', 'ollama_model'],
      where: 'id = ?',
      whereArgs: [defaultStoreId],
      limit: 1,
    );
    if (result.isEmpty) {
      return (enabled: false, baseUrl: 'http://localhost:11434', model: 'llama3.2');
    }
    final row = result.first;
    return (
      enabled: (row['ollama_enabled'] as int? ?? 0) == 1,
      baseUrl: (row['ollama_base_url'] as String?) ?? 'http://localhost:11434',
      model: (row['ollama_model'] as String?) ?? 'llama3.2',
    );
  }

  Future<void> updateOllamaConfig({
    required bool enabled,
    required String baseUrl,
    required String model,
  }) async {
    final db = await _dbHelper.database;
    await db.update(
      'stores',
      {
        'ollama_enabled': enabled ? 1 : 0,
        'ollama_base_url': baseUrl,
        'ollama_model': model,
      },
      where: 'id = ?',
      whereArgs: [defaultStoreId],
    );
  }

  /// Razorpay credentials for this store (Phase 2, Task 2.3).
  ///
  /// Stored here rather than in a checked-in constants file, following the
  /// same pattern as the Ollama and printer configuration above — the task
  /// file rules out hardcoded keys in the repo, and this is where this app
  /// already keeps per-installation configuration.
  ///
  /// Disabled with empty keys by default, so a fresh install or an upgrade
  /// never offers a payment method the shop has not set up. See
  /// `docs/PAYMENT_GATEWAY_ARCHITECTURE.md` for the honest limits of holding
  /// a gateway key secret in a local SQLite file.
  Future<({bool enabled, String keyId, String keySecret})> getRazorpayConfig() async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'stores',
      columns: ['razorpay_enabled', 'razorpay_key_id', 'razorpay_key_secret'],
      where: 'id = ?',
      whereArgs: [defaultStoreId],
      limit: 1,
    );
    if (result.isEmpty) {
      return (enabled: false, keyId: '', keySecret: '');
    }
    final row = result.first;
    return (
      enabled: (row['razorpay_enabled'] as int? ?? 0) == 1,
      keyId: (row['razorpay_key_id'] as String?) ?? '',
      keySecret: (row['razorpay_key_secret'] as String?) ?? '',
    );
  }

  Future<void> updateRazorpayConfig({
    required bool enabled,
    required String keyId,
    required String keySecret,
  }) async {
    final db = await _dbHelper.database;
    await db.update(
      'stores',
      {
        'razorpay_enabled': enabled ? 1 : 0,
        'razorpay_key_id': keyId.trim(),
        'razorpay_key_secret': keySecret.trim(),
      },
      where: 'id = ?',
      whereArgs: [defaultStoreId],
    );
  }
}

final storeRepositoryProvider = Provider<StoreRepository>((ref) {
  return StoreRepository();
});
