class AppConstants {
  static const String appName = 'SuperMart POS Enterprise';
  static const String dbName = 'super_mart_pos.db';
  static const int dbVersion = 30; // ✅ updated from 29 to 30 (Loyalty point event log + expiry: bonus_points columns, stores.loyalty_points_expiry_days)
  static const int sessionTimeoutSeconds = 300;
  static const double bonusPointsThreshold = 300.0;
  static const double bonusPointValue = 0.50;
}