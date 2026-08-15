/// Failures specific to loyalty point administration, mirroring
/// `gl_exceptions.dart` and `bank_reconciliation_exceptions.dart` so callers
/// can catch a loyalty problem distinctly.
class LoyaltyException implements Exception {
  LoyaltyException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// No `customers` row with the given id.
class LoyaltyCustomerNotFound extends LoyaltyException {
  LoyaltyCustomerNotFound(super.message);
}

/// A manual adjustment would drive the customer's balance below zero.
///
/// Refused rather than clamped: a manager deducting more points than a
/// customer has is working from a wrong number, and silently deducting only
/// part of it leaves both the ledger and the manager's belief wrong.
class InsufficientLoyaltyPoints extends LoyaltyException {
  InsufficientLoyaltyPoints(super.message);
}

/// An adjustment of zero points, or one with no explanation. Every manual
/// movement has to say who and why — that is the entire point of logging it.
class InvalidLoyaltyAdjustment extends LoyaltyException {
  InvalidLoyaltyAdjustment(super.message);
}
