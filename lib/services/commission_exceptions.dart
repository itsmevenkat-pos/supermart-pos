/// Failures specific to commission calculation and settlement, mirroring
/// `gl_exceptions.dart`'s shape.
class CommissionException implements Exception {
  CommissionException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// No `salesmen` row with the given id.
class SalesmanNotFound extends CommissionException {
  SalesmanNotFound(super.message);
}

/// No active commission rule covers the whole requested period, so there is
/// no rate to apply. Refused rather than defaulting to zero — a silent ₹0
/// commission looks like a salesman who sold nothing.
class NoCommissionRule extends CommissionException {
  NoCommissionRule(super.message);
}

/// More than one active rule overlaps the requested period, so the shop's own
/// records disagree about what it promised to pay.
///
/// Deliberately an error rather than a "pick the newest" heuristic: the two
/// rules exist because someone changed the agreement mid-period, and the
/// honest answer is to settle the two stretches separately, which the message
/// says.
class AmbiguousCommissionRule extends CommissionException {
  AmbiguousCommissionRule(super.message);
}

/// The rule itself is unusable — a tiered rule with no bands, a negative
/// rate, bands that are not in ascending order, or more than one open-ended
/// top band.
class InvalidCommissionRule extends CommissionException {
  InvalidCommissionRule(super.message);
}

/// The requested period is not a period — `to` is before `from`.
class InvalidCommissionPeriod extends CommissionException {
  InvalidCommissionPeriod(super.message);
}

/// A settlement already exists for this salesman and period. Mirrors the
/// `UNIQUE(salesman_id, period_from, period_to)` constraint so the caller
/// gets a readable message instead of a raw SQLite error.
class CommissionSettlementExists extends CommissionException {
  CommissionSettlementExists(super.message);
}

/// No `commission_ledger` row with the given id.
class CommissionSettlementNotFound extends CommissionException {
  CommissionSettlementNotFound(super.message);
}

/// The settlement cannot move to the state asked for — settling one already
/// settled, or deleting one that has been paid out.
class InvalidSettlementState extends CommissionException {
  InvalidSettlementState(super.message);
}
