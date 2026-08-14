import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

import '../core/utils/financial_year.dart';

/// One line of the double-entry journal — always exactly one side, never both.
///
/// A "transaction" in accounting terms is several of these rows sharing a
/// `referenceType`/`referenceId`; the balancing check across them lives in
/// `GLService.postCompoundEntry`, not here. What this class guarantees is the
/// narrower per-row invariant: exactly one of [debit]/[credit] is positive and
/// the other is exactly zero. A row with both sides filled, or with neither,
/// or with a negative amount, is not a journal line — it is corrupt data that
/// would silently unbalance every report built on top of it, so it throws at
/// construction rather than reaching the database.
///
/// The table is append-only: corrections go through `GLService.reverseEntry`,
/// which writes a new opposite-side row pointing back via
/// [reversalOfEntryId], leaving the original untouched as an audit trail.
class GLEntry extends Equatable {
  final String id;

  /// Seconds since epoch, matching the rest of this schema.
  final int entryDate;

  /// What produced this line — 'Sale', 'Purchase', 'Manual', 'Return', ...
  final String referenceType;

  /// The id of the originating sale/purchase/return, when there is one.
  final String? referenceId;

  final String description;
  final String accountId;
  final double debit;
  final double credit;

  /// Short label like "25-26", from [financialYearLabel].
  final String financialYear;

  final String? createdBy;
  final int createdAt;

  /// Set only on a reversal row: the id of the entry this one corrects.
  final String? reversalOfEntryId;

  GLEntry({
    required this.id,
    required this.entryDate,
    required this.referenceType,
    this.referenceId,
    required this.description,
    required this.accountId,
    this.debit = 0,
    this.credit = 0,
    required this.financialYear,
    this.createdBy,
    this.createdAt = 0,
    this.reversalOfEntryId,
  }) {
    if (debit < 0 || credit < 0) {
      throw ArgumentError('GL entry amounts cannot be negative (debit: $debit, credit: $credit). '
          'Post the opposite side instead of a negative amount.');
    }
    if (debit > 0 && credit > 0) {
      throw ArgumentError('A GL entry is one-sided: it cannot have both a debit ($debit) '
          'and a credit ($credit). Post two entries instead.');
    }
    if (debit == 0 && credit == 0) {
      throw ArgumentError('A GL entry needs a non-zero amount on exactly one side.');
    }
  }

  /// Builds a journal line, deriving the financial year from [entryDate] so a
  /// caller can never file an entry under the wrong year by hand.
  factory GLEntry.post({
    required DateTime entryDate,
    required String accountId,
    required double amount,
    required bool isDebit,
    required String description,
    required String referenceType,
    String? referenceId,
    String? createdBy,
    String? reversalOfEntryId,
  }) {
    return GLEntry(
      id: const Uuid().v4(),
      entryDate: entryDate.millisecondsSinceEpoch ~/ 1000,
      referenceType: referenceType,
      referenceId: referenceId,
      description: description,
      accountId: accountId,
      debit: isDebit ? amount : 0,
      credit: isDebit ? 0 : amount,
      financialYear: financialYearLabel(entryDate),
      createdBy: createdBy,
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      reversalOfEntryId: reversalOfEntryId,
    );
  }

  bool get isDebit => debit > 0;

  /// The amount on whichever side this line uses.
  double get amount => isDebit ? debit : credit;

  DateTime get entryDateTime => DateTime.fromMillisecondsSinceEpoch(entryDate * 1000);

  Map<String, dynamic> toJson() => {
        'id': id,
        'entry_date': entryDate,
        'reference_type': referenceType,
        'reference_id': referenceId,
        'description': description,
        'account_id': accountId,
        'debit': debit,
        'credit': credit,
        'financial_year': financialYear,
        'created_by': createdBy,
        'created_at': createdAt,
        'reversal_of_entry_id': reversalOfEntryId,
      };

  factory GLEntry.fromJson(Map<String, dynamic> map) => GLEntry(
        id: map['id'] as String,
        entryDate: map['entry_date'] as int,
        referenceType: map['reference_type'] as String,
        referenceId: map['reference_id'] as String?,
        description: map['description'] as String,
        accountId: map['account_id'] as String,
        debit: (map['debit'] as num?)?.toDouble() ?? 0,
        credit: (map['credit'] as num?)?.toDouble() ?? 0,
        financialYear: map['financial_year'] as String,
        createdBy: map['created_by'] as String?,
        createdAt: map['created_at'] as int? ?? 0,
        reversalOfEntryId: map['reversal_of_entry_id'] as String?,
      );

  @override
  List<Object?> get props => [
        id,
        entryDate,
        referenceType,
        referenceId,
        description,
        accountId,
        debit,
        credit,
        financialYear,
        createdBy,
        createdAt,
        reversalOfEntryId,
      ];
}
