class AppConstants {
  static const String appName = 'SuperMart POS Enterprise';
  static const String dbName = 'super_mart_pos.db';
  static const int dbVersion = 34; // ✅ updated from 33 to 34 (Cash movements: single source of truth for shift-close expected cash)
  static const int sessionTimeoutSeconds = 300;
  static const double bonusPointsThreshold = 300.0;
  static const double bonusPointValue = 0.50;
}