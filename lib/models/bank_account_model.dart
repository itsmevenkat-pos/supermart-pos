import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

/// A real-world bank account whose statements get reconciled against the
/// General Ledger.
///
/// [glAccountId] is the link that makes reconciliation meaningful: it names the
/// `chart_of_accounts` row (typically `1010` Bank) whose `gl_entries` this
/// account's statement lines are compared against. Without it there is nothing
/// to reconcile *to*, so `BankReconciliationService` refuses to reconcile an
/// account that has none rather than silently reporting a zero-variance match.
class BankAccount extends Equatable {
  final String id;
  final String accountNumber;
  final String accountHolder;
  final String bankName;

  /// Balance the account carried before any imported statement — the starting
  /// point a statement-side running balance is built on.
  final double openingBalance;

  /// `chart_of_accounts.id` this account reconciles against. Nullable because
  /// the column is, but see the class doc: reconciliation requires it.
  final String? glAccountId;

  /// Seconds since epoch of the last date reconciled through, or null if the
  /// account has never been reconciled. Everything on or before this date is
  /// settled; everything after is still open.
  final int? reconciledUpTo;

  final bool isActive;
  final int createdAt;

  const BankAccount({
    required this.id,
    required this.accountNumber,
    required this.accountHolder,
    required this.bankName,
    this.openingBalance = 0,
    this.glAccountId,
    this.reconciledUpTo,
    this.isActive = true,
    this.createdAt = 0,
  });

  factory BankAccount.create({
    required String accountNumber,
    required String accountHolder,
    required String bankName,
    double openingBalance = 0,
    String? glAccountId,
  }) {
    return BankAccount(
      id: const Uuid().v4(),
      accountNumber: accountNumber,
      accountHolder: accountHolder,
      bankName: bankName,
      openingBalance: openingBalance,
      glAccountId: glAccountId,
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
  }

  DateTime? get reconciledUpToDate =>
      reconciledUpTo == null ? null : DateTime.fromMillisecondsSinceEpoch(reconciledUpTo! * 1000);

  /// Last four digits, for display — a full account number has no business
  /// being rendered on a list screen a customer might be standing in front of.
  String get maskedNumber {
    final digits = accountNumber.trim();
    if (digits.length <= 4) return digits;
    return '••••${digits.substring(digits.length - 4)}';
  }

  BankAccount copyWith({
    String? accountNumber,
    String? accountHolder,
    String? bankName,
    double? openingBalance,
    String? glAccountId,
    int? reconciledUpTo,
    bool? isActive,
  }) {
    return BankAccount(
      id: id,
      accountNumber: accountNumber ?? this.accountNumber,
      accountHolder: accountHolder ?? this.accountHolder,
      bankName: bankName ?? this.bankName,
      openingBalance: openingBalance ?? this.openingBalance,
      glAccountId: glAccountId ?? this.glAccountId,
      reconciledUpTo: reconciledUpTo ?? this.reconciledUpTo,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'account_number': accountNumber,
        'account_holder': accountHolder,
        'bank_name': bankName,
        'opening_balance': openingBalance,
        'gl_account_id': glAccountId,
        'reconciled_up_to': reconciledUpTo,
        'is_active': isActive ? 1 : 0,
        'created_at': createdAt,
      };

  factory BankAccount.fromJson(Map<String, dynamic> map) => BankAccount(
        id: map['id'] as String,
        accountNumber: map['account_number'] as String,
        accountHolder: map['account_holder'] as String,
        bankName: map['bank_name'] as String,
        openingBalance: (map['opening_balance'] as num?)?.toDouble() ?? 0,
        glAccountId: map['gl_account_id'] as String?,
        reconciledUpTo: map['reconciled_up_to'] as int?,
        isActive: (map['is_active'] as int? ?? 1) == 1,
        createdAt: map['created_at'] as int? ?? 0,
      );

  @override
  List<Object?> get props => [
        id,
        accountNumber,
        accountHolder,
        bankName,
        openingBalance,
        glAccountId,
        reconciledUpTo,
        isActive,
        createdAt,
      ];
}
