import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

enum AccountType { asset, liability, equity, revenue, expense }

/// Whether [type] increases on the debit side. Assets and expenses do; the
/// other three increase on the credit side.
///
/// This is the single definition of debit/credit nature in the codebase —
/// `GLBalance.normalBalanceNature`, `GLService.getRunningBalance` and
/// `FinancialStatementService` all route through here or through
/// [signedBalance]. Do not re-derive it anywhere else: two copies that drift
/// apart would show a Trial Balance that balances next to a Balance Sheet
/// that does not, with nothing obviously wrong in either.
bool isNormallyDebit(AccountType type) => type == AccountType.asset || type == AccountType.expense;

/// The balance of an account in its own natural direction, so a "positive"
/// number always means what an accountant expects: cash on hand for an asset,
/// money owed for a liability, income earned for a revenue account.
double signedBalance(double totalDebit, double totalCredit, AccountType type) =>
    isNormallyDebit(type) ? totalDebit - totalCredit : totalCredit - totalDebit;

/// One account in the chart of accounts.
///
/// `isSystem` accounts are the ones seeded by MigrationV28 and referenced by
/// code from the sale/purchase posting paths — the UI must offer deactivate
/// rather than delete for those, since deleting one would orphan posted
/// `gl_entries` rows that point at it.
class ChartOfAccount extends Equatable {
  final String id;
  final String code;
  final String name;
  final AccountType type;
  final String? subType;
  final String? parentId;
  final bool isActive;
  final String? description;
  final double openingBalance;
  final int createdAt;
  final int? updatedAt;
  final bool isSystem;

  const ChartOfAccount({
    required this.id,
    required this.code,
    required this.name,
    required this.type,
    this.subType,
    this.parentId,
    this.isActive = true,
    this.description,
    this.openingBalance = 0,
    this.createdAt = 0,
    this.updatedAt,
    this.isSystem = false,
  });

  factory ChartOfAccount.create({
    required String code,
    required String name,
    required AccountType type,
    String? subType,
    String? parentId,
    String? description,
    double openingBalance = 0,
    bool isSystem = false,
  }) {
    return ChartOfAccount(
      id: const Uuid().v4(),
      code: code,
      name: name,
      type: type,
      subType: subType,
      parentId: parentId,
      description: description,
      openingBalance: openingBalance,
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      isSystem: isSystem,
    );
  }

  /// See [isNormallyDebit] — this account's own natural direction.
  bool get isDebitNature => isNormallyDebit(type);

  Map<String, dynamic> toJson() => {
        'id': id,
        'code': code,
        'name': name,
        'account_type': type.name,
        'sub_type': subType,
        'parent_id': parentId,
        'is_active': isActive ? 1 : 0,
        'description': description,
        'opening_balance': openingBalance,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'is_system': isSystem ? 1 : 0,
      };

  factory ChartOfAccount.fromJson(Map<String, dynamic> map) => ChartOfAccount(
        id: map['id'] as String,
        code: map['code'] as String,
        name: map['name'] as String,
        type: AccountType.values.byName(map['account_type'] as String),
        subType: map['sub_type'] as String?,
        parentId: map['parent_id'] as String?,
        isActive: (map['is_active'] as int? ?? 1) == 1,
        description: map['description'] as String?,
        openingBalance: (map['opening_balance'] as num?)?.toDouble() ?? 0,
        createdAt: map['created_at'] as int? ?? 0,
        updatedAt: map['updated_at'] as int?,
        isSystem: (map['is_system'] as int? ?? 0) == 1,
      );

  @override
  List<Object?> get props => [
        id,
        code,
        name,
        type,
        subType,
        parentId,
        isActive,
        description,
        openingBalance,
        createdAt,
        updatedAt,
        isSystem,
      ];
}
