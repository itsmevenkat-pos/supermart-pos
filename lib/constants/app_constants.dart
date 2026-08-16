class AppConstants {
  static const String appName = 'SuperMart POS Enterprise';
  static const String dbName = 'super_mart_pos.db';
  static const int dbVersion = 34; // ✅ updated from 33 to 34 (Cash movements: single source of truth for shift-close expected cash)

  // Removed: sessionTimeoutSeconds (idle lock was never implemented),
  // bonusPointsThreshold and bonusPointValue (both superseded by the
  // per-store loyalty settings in StoreRepository). Constants nothing reads
  // imply behaviour the app doesn't have.
}