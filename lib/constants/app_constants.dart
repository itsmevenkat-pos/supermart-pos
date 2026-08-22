class AppConstants {
  static const String appName = 'SuperMart POS Enterprise';
  static const String dbName = 'super_mart_pos.db';
  static const int dbVersion = 35; // v35: manual cash management columns on cash_movements (counterparty, approver, reason)

  // Removed: sessionTimeoutSeconds (idle lock was never implemented),
  // bonusPointsThreshold and bonusPointValue (both superseded by the
  // per-store loyalty settings in StoreRepository). Constants nothing reads
  // imply behaviour the app doesn't have.
}