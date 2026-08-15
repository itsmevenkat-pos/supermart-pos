class AppConstants {
  static const String appName = 'SuperMart POS Enterprise';
  static const String dbName = 'super_mart_pos.db';
  static const int dbVersion = 32; // ✅ updated from 31 to 32 (Collections & commission: collection_activities, commission_rules, commission_ledger)
  static const int sessionTimeoutSeconds = 300;
  static const double bonusPointsThreshold = 300.0;
  static const double bonusPointValue = 0.50;
}