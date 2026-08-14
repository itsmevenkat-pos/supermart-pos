class AppConstants {
  static const String appName = 'SuperMart POS Enterprise';
  static const String dbName = 'super_mart_pos.db';
  static const int dbVersion = 27; // ✅ updated from 26 to 27 (purchase_items purchase-unit conversion columns)
  static const int sessionTimeoutSeconds = 300;
  static const double bonusPointsThreshold = 300.0;
  static const double bonusPointValue = 0.50;
}