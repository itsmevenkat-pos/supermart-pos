/// Failures specific to bank reconciliation, mirroring `gl_exceptions.dart`'s
/// shape so callers can catch a bank problem distinctly from a ledger one.
class BankReconciliationException implements Exception {
  BankReconciliationException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// No `bank_accounts` row with the given id.
class BankAccountNotFound extends BankReconciliationException {
  BankAccountNotFound(super.message);
}

/// The bank account has no `gl_account_id`, so there is nothing to reconcile
/// against. Reported rather than silently treated as a zero-variance match.
class BankAccountNotLinked extends BankReconciliationException {
  BankAccountNotLinked(super.message);
}

/// No `bank_statements` or `bank_transactions` row with the given id.
class BankStatementNotFound extends BankReconciliationException {
  BankStatementNotFound(super.message);
}

/// The CSV could not be read — wrong header, unparseable date, non-numeric
/// amount. Carries [rowNumber] (1-based, counting the header) so the UI can
/// point at the offending line instead of saying "import failed".
class StatementParseException extends BankReconciliationException {
  StatementParseException(super.message, {this.rowNumber});

  final int? rowNumber;

  @override
  String toString() =>
      rowNumber == null ? 'StatementParseException: $message' : 'StatementParseException (row $rowNumber): $message';
}
