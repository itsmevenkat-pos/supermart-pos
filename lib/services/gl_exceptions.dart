/// Failures the General Ledger raises on its own terms.
///
/// These are distinct types rather than bare `Exception('...')` (the usual
/// style elsewhere in this app) for one reason: a caller inside a sale
/// transaction has to be able to tell "this period is closed, refuse the sale"
/// apart from "the database is unavailable", and a string message is not
/// something you can branch on safely. [code] is the stable, greppable
/// identifier; [message] is what a cashier reads.
class GLException implements Exception {
  const GLException(this.message, this.code);

  final String message;
  final String code;

  @override
  String toString() => 'GLException($code): $message';
}

/// The referenced account does not exist, or exists but is deactivated.
class AccountNotFound extends GLException {
  const AccountNotFound(String message) : super(message, 'ACCOUNT_NOT_FOUND');
}

/// A compound entry's debits and credits do not agree. Thrown *before*
/// anything is written — an unbalanced entry never reaches the journal.
class UnbalancedEntry extends GLException {
  const UnbalancedEntry(String message) : super(message, 'UNBALANCED_ENTRY');
}

/// The financial year the entry falls into has been closed via
/// `FinancialYearCloseService`. Closing is one-way, so this is permanent for
/// that year — the correction belongs in the current year instead.
class ClosedPeriod extends GLException {
  const ClosedPeriod(String message) : super(message, 'CLOSED_PERIOD');
}

/// A GL entry was asked for by id and isn't there — currently only from
/// `GLService.reverseEntry`.
class EntryNotFound extends GLException {
  const EntryNotFound(String message) : super(message, 'ENTRY_NOT_FOUND');
}
