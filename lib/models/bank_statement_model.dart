import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

/// One imported bank statement — the header for a batch of `bank_transactions`.
///
/// [beginningBalance] and [endingBalance] are taken from the statement itself,
/// not computed from the imported lines. That is deliberate: the whole point of
/// reconciliation is to compare an *independently asserted* bank figure against
/// what the ledger thinks. Deriving the ending balance from the lines we just
/// parsed would make the check circular, and a statement whose lines don't add
/// up to its own stated ending balance is itself a finding worth surfacing (see
/// [lineSumMatches] on the reconciliation summary).
class BankStatement extends Equatable {
  final String id;
  final String bankAccountId;

  /// Seconds since epoch — the statement's closing date.
  final int statementDate;

  final double beginningBalance;
  final double endingBalance;

  /// Seconds since epoch of when this statement was imported into the app.
  final int importDate;

  const BankStatement({
    required this.id,
    required this.bankAccountId,
    required this.statementDate,
    required this.beginningBalance,
    required this.endingBalance,
    this.importDate = 0,
  });

  factory BankStatement.create({
    required String bankAccountId,
    required DateTime statementDate,
    required double beginningBalance,
    required double endingBalance,
  }) {
    return BankStatement(
      id: const Uuid().v4(),
      bankAccountId: bankAccountId,
      statementDate: statementDate.millisecondsSinceEpoch ~/ 1000,
      beginningBalance: beginningBalance,
      endingBalance: endingBalance,
      importDate: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
  }

  DateTime get statementDateTime => DateTime.fromMillisecondsSinceEpoch(statementDate * 1000);

  DateTime get importDateTime => DateTime.fromMillisecondsSinceEpoch(importDate * 1000);

  /// Net movement the bank says happened over the statement period.
  double get netMovement => endingBalance - beginningBalance;

  Map<String, dynamic> toJson() => {
        'id': id,
        'bank_account_id': bankAccountId,
        'statement_date': statementDate,
        'beginning_balance': beginningBalance,
        'ending_balance': endingBalance,
        'import_date': importDate,
      };

  factory BankStatement.fromJson(Map<String, dynamic> map) => BankStatement(
        id: map['id'] as String,
        bankAccountId: map['bank_account_id'] as String,
        statementDate: map['statement_date'] as int,
        beginningBalance: (map['beginning_balance'] as num?)?.toDouble() ?? 0,
        endingBalance: (map['ending_balance'] as num?)?.toDouble() ?? 0,
        importDate: map['import_date'] as int? ?? 0,
      );

  @override
  List<Object?> get props => [
        id,
        bankAccountId,
        statementDate,
        beginningBalance,
        endingBalance,
        importDate,
      ];
}
