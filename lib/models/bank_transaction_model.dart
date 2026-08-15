import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

/// Where one imported statement line stands relative to the ledger.
///
/// `unmatched` is the default and the only state the importer ever writes.
/// `matched` means a human confirmed the line against a specific GL entry (or
/// an exact date+amount hit was auto-confirmed — see
/// `BankReconciliationService.autoMatch`). `ignored` is for lines that will
/// never have a ledger counterpart and should stop counting as outstanding —
/// bank charges the shop books elsewhere, an interest credit, a test deposit.
enum BankMatchStatus { unmatched, matched, ignored }

/// A single line of an imported bank statement.
///
/// [amount] is **signed**: positive is money into the account, negative is
/// money out. This mirrors how banks export CSV and, more usefully, collapses
/// the debit/credit case split into one comparison when matching against
/// `gl_entries` — a positive statement amount corresponds to a *debit* on the
/// bank asset account, a negative one to a credit. `signedGlAmount` on the
/// matching code does that translation in exactly one place.
///
/// [matchedGlEntryId] is only ever set together with
/// [BankMatchStatus.matched]; the repository enforces that pairing so a line
/// can't claim to be matched while pointing at nothing.
class BankTransaction extends Equatable {
  final String id;
  final String bankStatementId;

  /// Seconds since epoch — the date the bank posted this line.
  final int transactionDate;

  /// The bank's own reference: cheque number, UTR, UPI ref. Optional because
  /// plenty of statement rows genuinely have none.
  final String? reference;

  final String? description;

  /// Signed: positive = money in, negative = money out. See the class doc.
  final double amount;

  final String? matchedGlEntryId;
  final BankMatchStatus matchStatus;

  const BankTransaction({
    required this.id,
    required this.bankStatementId,
    required this.transactionDate,
    this.reference,
    this.description,
    required this.amount,
    this.matchedGlEntryId,
    this.matchStatus = BankMatchStatus.unmatched,
  });

  factory BankTransaction.create({
    required String bankStatementId,
    required DateTime transactionDate,
    required double amount,
    String? reference,
    String? description,
  }) {
    return BankTransaction(
      id: const Uuid().v4(),
      bankStatementId: bankStatementId,
      transactionDate: transactionDate.millisecondsSinceEpoch ~/ 1000,
      reference: reference,
      description: description,
      amount: amount,
    );
  }

  DateTime get transactionDateTime => DateTime.fromMillisecondsSinceEpoch(transactionDate * 1000);

  /// True when money came into the account. On the linked GL asset account
  /// this line's counterpart is a **debit**.
  bool get isCredit => amount > 0;

  bool get isMatched => matchStatus == BankMatchStatus.matched;

  /// Still awaiting a decision — neither matched nor deliberately ignored.
  /// This is what "outstanding" means in the reconciliation summary.
  bool get isOutstanding => matchStatus == BankMatchStatus.unmatched;

  BankTransaction copyWith({
    String? reference,
    String? description,
    double? amount,
    String? matchedGlEntryId,
    BankMatchStatus? matchStatus,
    bool clearMatchedGlEntry = false,
  }) {
    return BankTransaction(
      id: id,
      bankStatementId: bankStatementId,
      transactionDate: transactionDate,
      reference: reference ?? this.reference,
      description: description ?? this.description,
      amount: amount ?? this.amount,
      matchedGlEntryId: clearMatchedGlEntry ? null : (matchedGlEntryId ?? this.matchedGlEntryId),
      matchStatus: matchStatus ?? this.matchStatus,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'bank_statement_id': bankStatementId,
        'transaction_date': transactionDate,
        'reference': reference,
        'description': description,
        'amount': amount,
        'matched_gl_entry_id': matchedGlEntryId,
        'match_status': matchStatus.name,
      };

  factory BankTransaction.fromJson(Map<String, dynamic> map) => BankTransaction(
        id: map['id'] as String,
        bankStatementId: map['bank_statement_id'] as String,
        transactionDate: map['transaction_date'] as int,
        reference: map['reference'] as String?,
        description: map['description'] as String?,
        amount: (map['amount'] as num).toDouble(),
        matchedGlEntryId: map['matched_gl_entry_id'] as String?,
        matchStatus: BankMatchStatus.values.byName(map['match_status'] as String? ?? 'unmatched'),
      );

  @override
  List<Object?> get props => [
        id,
        bankStatementId,
        transactionDate,
        reference,
        description,
        amount,
        matchedGlEntryId,
        matchStatus,
      ];
}
