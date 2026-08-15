import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

import 'chart_of_account_model.dart';

/// The cached debit/credit totals for one account in one financial year.
///
/// Derived data — every row here can be rebuilt from `gl_entries` by
/// `GLRepository.recalculateBalance`, which is the only writer. Nothing else
/// should update this table; a balance edited by hand is a balance that no
/// longer means anything.
///
/// Keyed by year rather than being one running total forever, because this app
/// closes financial years (`FinancialYearCloseService`) and each year's books
/// stand on their own.
class GLBalance extends Equatable {
  final String id;
  final String accountId;
  final String financialYear;
  final double totalDebit;
  final double totalCredit;

  /// The account's balance in its own natural direction — see [signedBalance].
  /// Stored rather than recomputed on read so reports can sum a single column.
  final double balance;

  final int lastUpdated;

  const GLBalance({
    required this.id,
    required this.accountId,
    required this.financialYear,
    this.totalDebit = 0,
    this.totalCredit = 0,
    this.balance = 0,
    this.lastUpdated = 0,
  });

  /// Computes the balance from the two totals in [type]'s natural direction,
  /// so callers never have to get the sign convention right themselves.
  factory GLBalance.create({
    required String accountId,
    required String financialYear,
    required AccountType type,
    required double totalDebit,
    required double totalCredit,
  }) {
    return GLBalance(
      id: const Uuid().v4(),
      accountId: accountId,
      financialYear: financialYear,
      totalDebit: totalDebit,
      totalCredit: totalCredit,
      balance: signedBalance(totalDebit, totalCredit, type),
      lastUpdated: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
  }

  /// Whether [type] normally carries a debit balance — delegates to the one
  /// definition in `chart_of_account_model.dart` rather than restating the
  /// rule here.
  static bool normalBalanceNature(AccountType type) => isNormallyDebit(type);

  /// The raw difference, always debit-minus-credit regardless of account type.
  /// Trial Balance columns are built from this; [balance] is for display.
  double get rawDifference => totalDebit - totalCredit;

  Map<String, dynamic> toJson() => {
        'id': id,
        'account_id': accountId,
        'financial_year': financialYear,
        'total_debit': totalDebit,
        'total_credit': totalCredit,
        'balance': balance,
        'last_updated': lastUpdated,
      };

  factory GLBalance.fromJson(Map<String, dynamic> map) => GLBalance(
        id: map['id'] as String,
        accountId: map['account_id'] as String,
        financialYear: map['financial_year'] as String,
        totalDebit: (map['total_debit'] as num?)?.toDouble() ?? 0,
        totalCredit: (map['total_credit'] as num?)?.toDouble() ?? 0,
        balance: (map['balance'] as num?)?.toDouble() ?? 0,
        lastUpdated: map['last_updated'] as int? ?? 0,
      );

  @override
  List<Object?> get props => [id, accountId, financialYear, totalDebit, totalCredit, balance, lastUpdated];
}
