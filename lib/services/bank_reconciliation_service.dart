import 'package:csv/csv.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/database/database_helper.dart';
import '../models/bank_account_model.dart';
import '../models/bank_statement_model.dart';
import '../models/bank_transaction_model.dart';
import '../models/gl_entry_model.dart';
import '../repositories/bank_reconciliation_repository.dart';
import '../repositories/gl_repository.dart';
import 'bank_reconciliation_exceptions.dart';

/// One parsed CSV row, before it becomes a `BankTransaction`. Kept separate so
/// a caller can parse and preview a file without writing anything.
class ParsedStatementLine extends Equatable {
  const ParsedStatementLine({
    required this.date,
    required this.amount,
    this.reference,
    this.description,
  });

  final DateTime date;

  /// Signed, same convention as `BankTransaction.amount`.
  final double amount;

  final String? reference;
  final String? description;

  @override
  List<Object?> get props => [date, amount, reference, description];
}

/// A proposed pairing of one statement line with one GL entry.
///
/// A suggestion is **not** a match. Only [isExact] suggestions — same calendar
/// day, amount equal to the paisa — are safe to confirm without a human
/// looking, and that is exactly the line `autoMatch` draws.
class MatchSuggestion extends Equatable {
  const MatchSuggestion({
    required this.transaction,
    required this.entry,
    required this.dayDifference,
    required this.amountDifference,
  });

  final BankTransaction transaction;
  final GLEntry entry;

  /// Whole days between the statement line and the ledger entry, absolute.
  final int dayDifference;

  /// Absolute rupee gap between the two amounts.
  final double amountDifference;

  /// Same day, same amount to the paisa. See the class doc.
  bool get isExact => dayDifference == 0 && amountDifference <= BankReconciliationService.amountTolerance;

  @override
  List<Object?> get props => [transaction, entry, dayDifference, amountDifference];
}

/// The state of one account's reconciliation over a period. Computed on demand
/// from the ledger and the imported lines — deliberately not stored, see
/// `MigrationV29`'s doc for why there is no results table.
class ReconciliationSummary extends Equatable {
  const ReconciliationSummary({
    required this.bankAccountId,
    required this.glBalance,
    required this.statementBalance,
    required this.matchedCount,
    required this.unmatchedCount,
    required this.ignoredCount,
    required this.unmatchedTotal,
  });

  final String bankAccountId;

  /// Signed balance of the linked `chart_of_accounts` row, per Phase 1's
  /// `signedBalance` — for a bank asset account, debits minus credits.
  final double glBalance;

  /// What the bank says: the account's opening balance plus every imported line
  /// in range. Built from the account's own opening figure rather than a
  /// statement's `ending_balance` so a period spanning several statements — or
  /// none — still has a well-defined answer.
  final double statementBalance;

  final int matchedCount;

  /// Lines still awaiting a decision. Ignored lines are deliberately excluded:
  /// somebody already decided about those.
  final int unmatchedCount;

  final int ignoredCount;

  /// Signed sum of the still-outstanding lines — the amount the variance would
  /// move by if every one of them were matched.
  final double unmatchedTotal;

  /// Positive when the bank shows more than the ledger does.
  double get variance => statementBalance - glBalance;

  /// Balanced *and* nothing left hanging. A zero variance with unmatched lines
  /// still open is a coincidence, not a reconciliation, so both conditions are
  /// required here.
  bool get isReconciled =>
      variance.abs() <= BankReconciliationService.amountTolerance && unmatchedCount == 0;

  @override
  List<Object?> get props => [
        bankAccountId,
        glBalance,
        statementBalance,
        matchedCount,
        unmatchedCount,
        ignoredCount,
        unmatchedTotal,
      ];
}

/// Imports bank statements and reconciles them against the General Ledger.
///
/// The two rules that shape everything here:
///
/// 1. **Amount tolerance is ±0.01, not a percentage.** The original design
///    draft proposed ±5%; a reconciliation tool that accepts a 5%-off amount as
///    "matched" hides exactly the errors it exists to find. Dates get ±2 days
///    of slack (banks post late), amounts get one paisa of floating-point
///    slack and nothing more.
///
/// 2. **Auto-matching suggests; humans confirm.** [suggestMatches] never
///    writes. [autoMatch] writes only for same-day exact-amount hits, where
///    there is no judgement left to exercise. Everything looser goes to a
///    person via [matchTransaction].
class BankReconciliationService {
  BankReconciliationService({
    BankReconciliationRepository? repository,
    GLRepository? glRepository,
    DatabaseHelper? dbHelper,
  })  : _repository = repository ?? BankReconciliationRepository(),
        _glRepository = glRepository ?? GLRepository(),
        _dbHelper = dbHelper ?? DatabaseHelper.instance;

  final BankReconciliationRepository _repository;
  final GLRepository _glRepository;
  final DatabaseHelper _dbHelper;

  /// One paisa. Also the epsilon for comparing two computed balances, since
  /// both sides are doubles summed over many rows.
  static const double amountTolerance = 0.01;

  /// How late a bank may post a transaction and still be considered the same
  /// event as the ledger entry.
  static const int dateToleranceDays = 2;

  static const List<String> _expectedHeader = ['date', 'reference', 'description', 'amount'];

  // --------------------------------------------------------------- CSV parse

  /// Parses `Date,Reference,Description,Amount`.
  ///
  /// A header row is required and validated: silently treating a mislabelled
  /// column as an amount is how a reconciliation ends up confidently wrong.
  /// Blank lines are skipped; anything else that fails to parse throws
  /// [StatementParseException] with the row number, so nothing is imported
  /// half-right.
  List<ParsedStatementLine> parseStatementCsv(String csv) {
    final rows = const CsvToListConverter(eol: '\n', shouldParseNumbers: false).convert(csv.replaceAll('\r\n', '\n'));
    if (rows.isEmpty) {
      throw StatementParseException('The file is empty.');
    }

    final header = rows.first.map((c) => c.toString().trim().toLowerCase()).toList();
    if (header.length < 4 || !_headerMatches(header)) {
      throw StatementParseException(
        'Expected a "Date,Reference,Description,Amount" header row, found: ${rows.first.join(',')}',
        rowNumber: 1,
      );
    }

    final lines = <ParsedStatementLine>[];
    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      final rowNumber = i + 1;
      if (row.every((c) => c.toString().trim().isEmpty)) continue;
      if (row.length < 4) {
        throw StatementParseException('Expected 4 columns, found ${row.length}.', rowNumber: rowNumber);
      }

      final date = _parseDate(row[0].toString().trim(), rowNumber);
      final amount = _parseAmount(row[3].toString().trim(), rowNumber);
      final reference = row[1].toString().trim();
      final description = row[2].toString().trim();

      lines.add(ParsedStatementLine(
        date: date,
        amount: amount,
        reference: reference.isEmpty ? null : reference,
        description: description.isEmpty ? null : description,
      ));
    }
    return lines;
  }

  bool _headerMatches(List<String> header) {
    for (var i = 0; i < _expectedHeader.length; i++) {
      if (header[i] != _expectedHeader[i]) return false;
    }
    return true;
  }

  /// Accepts `yyyy-MM-dd`, `dd/MM/yyyy` and `dd-MM-yyyy`.
  ///
  /// Day-first is the Indian convention this app is built for, so an ambiguous
  /// `03/04/2025` is read as 3 April, not 4 March. The unambiguous ISO form is
  /// recognised by its four-digit first component, so both can coexist without
  /// a format flag the user would have to get right.
  DateTime _parseDate(String raw, int rowNumber) {
    if (raw.isEmpty) {
      throw StatementParseException('Missing date.', rowNumber: rowNumber);
    }
    final parts = raw.split(RegExp(r'[/\-.]'));
    if (parts.length != 3) {
      throw StatementParseException(
        'Unrecognised date "$raw" — use yyyy-MM-dd, dd/MM/yyyy or dd-MM-yyyy.',
        rowNumber: rowNumber,
      );
    }
    final numbers = parts.map(int.tryParse).toList();
    if (numbers.any((n) => n == null)) {
      throw StatementParseException('Unrecognised date "$raw".', rowNumber: rowNumber);
    }

    final int year, month, day;
    if (parts[0].length == 4) {
      year = numbers[0]!;
      month = numbers[1]!;
      day = numbers[2]!;
    } else {
      day = numbers[0]!;
      month = numbers[1]!;
      year = numbers[2]! < 100 ? 2000 + numbers[2]! : numbers[2]!;
    }

    if (month < 1 || month > 12 || day < 1 || day > 31) {
      throw StatementParseException('Date "$raw" is out of range.', rowNumber: rowNumber);
    }
    final parsed = DateTime(year, month, day);
    // DateTime rolls 31 February forward instead of rejecting it, so check the
    // components survived the round trip.
    if (parsed.year != year || parsed.month != month || parsed.day != day) {
      throw StatementParseException('Date "$raw" is not a real date.', rowNumber: rowNumber);
    }
    return parsed;
  }

  /// Accepts `1234.56`, `-1,234.56`, `(1234.56)` (accounting negative) and a
  /// leading `₹`/`Rs.` — all forms real bank exports use.
  double _parseAmount(String raw, int rowNumber) {
    if (raw.isEmpty) {
      throw StatementParseException('Missing amount.', rowNumber: rowNumber);
    }
    var cleaned = raw.replaceAll(RegExp(r'[₹,\s]'), '').replaceAll(RegExp(r'^Rs\.?', caseSensitive: false), '');
    var negative = false;
    if (cleaned.startsWith('(') && cleaned.endsWith(')')) {
      negative = true;
      cleaned = cleaned.substring(1, cleaned.length - 1);
    }
    final value = double.tryParse(cleaned);
    if (value == null) {
      throw StatementParseException('Amount "$raw" is not a number.', rowNumber: rowNumber);
    }
    if (value == 0) {
      throw StatementParseException('Amount "$raw" is zero — a statement line must move money.', rowNumber: rowNumber);
    }
    return negative ? -value.abs() : value;
  }

  // ------------------------------------------------------------------ import

  /// Parses [csv] and writes the statement and all of its lines in one
  /// transaction — a partially imported statement would produce a variance that
  /// looks like a real accounting discrepancy.
  ///
  /// [endingBalance] defaults to `beginningBalance + sum(lines)`, but pass the
  /// bank's own stated figure when the statement has one: the mismatch between
  /// the two is itself a finding, and deriving it throws that signal away.
  Future<BankStatement> importStatement({
    required String bankAccountId,
    required DateTime statementDate,
    required double beginningBalance,
    required String csv,
    double? endingBalance,
  }) async {
    final account = await _repository.getAccount(bankAccountId);
    if (account == null) {
      throw BankAccountNotFound('No bank account with id $bankAccountId.');
    }

    final lines = parseStatementCsv(csv);
    if (lines.isEmpty) {
      throw StatementParseException('The file has a valid header but no transaction rows.');
    }

    final movement = lines.fold<double>(0, (sum, line) => sum + line.amount);
    final statement = BankStatement.create(
      bankAccountId: bankAccountId,
      statementDate: statementDate,
      beginningBalance: beginningBalance,
      endingBalance: endingBalance ?? beginningBalance + movement,
    );

    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      await _repository.createStatement(statement, executor: txn);
      await _repository.insertTransactions(
        lines
            .map((line) => BankTransaction.create(
                  bankStatementId: statement.id,
                  transactionDate: line.date,
                  amount: line.amount,
                  reference: line.reference,
                  description: line.description,
                ))
            .toList(),
        executor: txn,
      );
    });
    return statement;
  }

  // ---------------------------------------------------------------- matching

  /// Proposes pairings for the still-unmatched lines of [bankAccountId],
  /// **without writing anything**.
  ///
  /// Candidates are the linked GL account's entries in the same date window,
  /// minus any entry already claimed by another matched line. Each statement
  /// line takes its best candidate — closest amount, then closest date — and
  /// that entry is then off the table for the rest of the pass, so two lines
  /// can never be suggested against the same ledger entry.
  Future<List<MatchSuggestion>> suggestMatches(
    String bankAccountId, {
    DateTime? from,
    DateTime? to,
  }) async {
    final account = await _requireLinkedAccount(bankAccountId);

    final unmatched = await _repository.getTransactionsForAccount(
      bankAccountId,
      from: from,
      to: to,
      status: BankMatchStatus.unmatched,
    );
    if (unmatched.isEmpty) return const [];

    // Widen the ledger window by the date tolerance at both ends, otherwise a
    // bank line on the first day of the period could never match an entry
    // posted two days earlier.
    const slack = Duration(days: dateToleranceDays);
    final earliest = unmatched.first.transactionDateTime;
    final latest = unmatched.last.transactionDateTime;

    final claimed = await _repository.getMatchedGlEntryIds(bankAccountId);
    final candidates = (await _glRepository.getEntriesByAccount(
      account.glAccountId!,
      from: earliest.subtract(slack),
      to: latest.add(slack),
    ))
        .where((entry) => !claimed.contains(entry.id))
        .toList();

    final taken = <String>{};
    final suggestions = <MatchSuggestion>[];
    for (final transaction in unmatched) {
      MatchSuggestion? best;
      for (final entry in candidates) {
        if (taken.contains(entry.id)) continue;

        final dayDifference = _wholeDaysBetween(transaction.transactionDateTime, entry.entryDateTime);
        if (dayDifference > dateToleranceDays) continue;

        final amountDifference = (_signedGlAmount(entry) - transaction.amount).abs();
        if (amountDifference > amountTolerance) continue;

        final suggestion = MatchSuggestion(
          transaction: transaction,
          entry: entry,
          dayDifference: dayDifference,
          amountDifference: amountDifference,
        );
        if (best == null || _isBetter(suggestion, best)) {
          best = suggestion;
        }
      }
      if (best != null) {
        taken.add(best.entry.id);
        suggestions.add(best);
      }
    }
    return suggestions;
  }

  /// Confirms only the unambiguous suggestions — same day, same amount — and
  /// returns how many were written. Everything else stays `unmatched` for a
  /// person to decide on, which is the point of the suggest/confirm split.
  Future<int> autoMatch(String bankAccountId, {DateTime? from, DateTime? to}) async {
    final suggestions = await suggestMatches(bankAccountId, from: from, to: to);
    final exact = suggestions.where((s) => s.isExact).toList();
    if (exact.isEmpty) return 0;

    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      for (final suggestion in exact) {
        await _repository.markMatched(suggestion.transaction.id, suggestion.entry.id, executor: txn);
      }
    });
    return exact.length;
  }

  /// Confirms one pairing by hand. Both sides are checked to exist first — a
  /// match pointing at a deleted entry is worse than no match at all.
  Future<void> matchTransaction(String transactionId, String glEntryId) async {
    final transaction = await _repository.getTransaction(transactionId);
    if (transaction == null) {
      throw BankStatementNotFound('No bank transaction with id $transactionId.');
    }
    final entry = await _glRepository.getEntry(glEntryId);
    if (entry == null) {
      throw BankReconciliationException('No GL entry with id $glEntryId.');
    }
    await _repository.markMatched(transactionId, glEntryId);
  }

  Future<void> unmatchTransaction(String transactionId) => _repository.markUnmatched(transactionId);

  /// Marks a line as having no ledger counterpart, ever — bank charges booked
  /// elsewhere, interest credits, test deposits. It stops counting as
  /// outstanding but still counts toward the statement balance, so the variance
  /// it causes stays visible instead of being quietly written off.
  Future<void> ignoreTransaction(String transactionId) => _repository.markIgnored(transactionId);

  // ---------------------------------------------------------- reconciliation

  /// Computes the current reconciliation state of [bankAccountId] over an
  /// optional date window.
  ///
  /// The GL side is the linked account's signed balance from `gl_entries`
  /// (Phase 1's `signedBalance` convention: debits minus credits for an asset).
  /// It is summed from the journal in the same window rather than read from the
  /// `gl_balances` cache, because the cache is per-financial-year and a
  /// reconciliation period is usually a month.
  Future<ReconciliationSummary> reconcile(
    String bankAccountId, {
    DateTime? from,
    DateTime? to,
  }) async {
    final account = await _requireLinkedAccount(bankAccountId);

    final transactions = await _repository.getTransactionsForAccount(bankAccountId, from: from, to: to);
    final entries = await _glRepository.getEntriesByAccount(account.glAccountId!, from: from, to: to);

    final glMovement = entries.fold<double>(0, (sum, entry) => sum + _signedGlAmount(entry));
    final statementMovement = transactions.fold<double>(0, (sum, t) => sum + t.amount);

    final unmatched = transactions.where((t) => t.isOutstanding).toList();

    return ReconciliationSummary(
      bankAccountId: bankAccountId,
      glBalance: account.openingBalance + glMovement,
      statementBalance: account.openingBalance + statementMovement,
      matchedCount: transactions.where((t) => t.isMatched).length,
      unmatchedCount: unmatched.length,
      ignoredCount: transactions.where((t) => t.matchStatus == BankMatchStatus.ignored).length,
      unmatchedTotal: unmatched.fold<double>(0, (sum, t) => sum + t.amount),
    );
  }

  /// Closes the period: moves `reconciled_up_to` to [through].
  ///
  /// Refuses unless the period actually reconciles, unless [force] is set. A
  /// watermark that can be moved over an unbalanced period is a watermark that
  /// means nothing — but a manager who has looked at the variance and accepted
  /// it needs a way through, so the override exists and is explicit.
  Future<ReconciliationSummary> markReconciled(
    String bankAccountId, {
    required DateTime through,
    DateTime? from,
    bool force = false,
  }) async {
    final summary = await reconcile(bankAccountId, from: from, to: through);
    if (!summary.isReconciled && !force) {
      throw BankReconciliationException(
        'Period does not reconcile: variance ${summary.variance.toStringAsFixed(2)}, '
        '${summary.unmatchedCount} unmatched line(s). Resolve them or pass force: true to accept.',
      );
    }
    await _repository.setReconciledUpTo(bankAccountId, through);
    return summary;
  }

  // ----------------------------------------------------------------- helpers

  Future<BankAccount> _requireLinkedAccount(String bankAccountId) async {
    final account = await _repository.getAccount(bankAccountId);
    if (account == null) {
      throw BankAccountNotFound('No bank account with id $bankAccountId.');
    }
    if (account.glAccountId == null || account.glAccountId!.isEmpty) {
      throw BankAccountNotLinked(
        'Bank account ${account.accountNumber} is not linked to a chart-of-accounts row, '
        'so there is no ledger balance to reconcile it against.',
      );
    }
    return account;
  }

  /// Translates a ledger line into the statement's sign convention: money into
  /// the bank asset account is a debit, and a statement shows it as positive.
  /// This is the *only* place that conversion happens.
  double _signedGlAmount(GLEntry entry) => entry.debit - entry.credit;

  /// Calendar days apart, ignoring time of day — a bank line stamped midnight
  /// and a sale posted at 6pm the same day are zero days apart, not one.
  int _wholeDaysBetween(DateTime a, DateTime b) {
    final dayA = DateTime(a.year, a.month, a.day);
    final dayB = DateTime(b.year, b.month, b.day);
    return dayA.difference(dayB).inDays.abs();
  }

  /// Closer amount wins; ties break on the closer date.
  bool _isBetter(MatchSuggestion candidate, MatchSuggestion incumbent) {
    final amountGap = candidate.amountDifference - incumbent.amountDifference;
    if (amountGap.abs() > 1e-9) return amountGap < 0;
    return candidate.dayDifference < incumbent.dayDifference;
  }
}

final bankReconciliationServiceProvider = Provider<BankReconciliationService>((ref) {
  return BankReconciliationService();
});
