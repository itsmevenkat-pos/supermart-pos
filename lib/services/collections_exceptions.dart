/// Failures specific to collections, mirroring `gl_exceptions.dart`'s shape so
/// callers can catch a collections problem distinctly from a ledger one.
class CollectionsException implements Exception {
  CollectionsException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// No `collection_activities` row with the given id.
class CollectionActivityNotFound extends CollectionsException {
  CollectionActivityNotFound(super.message);
}

/// No `customers` row with the given id. Raised before writing an activity
/// rather than letting the foreign key fail, so the caller gets a sentence
/// instead of a constraint violation.
class CollectionCustomerNotFound extends CollectionsException {
  CollectionCustomerNotFound(super.message);
}

/// The activity cannot move to the state asked for — completing something
/// already completed, or rescheduling a follow-up that is finished.
class InvalidCollectionActivityState extends CollectionsException {
  InvalidCollectionActivityState(super.message);
}

/// A follow-up was scheduled for a date already past. Refused rather than
/// accepted, because a reminder that is born overdue is indistinguishable in
/// the worklist from one the shop genuinely missed.
class InvalidFollowUpDate extends CollectionsException {
  InvalidFollowUpDate(super.message);
}

/// The customer has no phone number, so a WhatsApp reminder cannot be
/// addressed. Distinct from a send failure — nothing was attempted.
class NoContactNumber extends CollectionsException {
  NoContactNumber(super.message);
}
