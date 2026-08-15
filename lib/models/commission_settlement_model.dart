import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

/// Whether a calculated commission has actually been paid out.
///
/// `calculated` is a payable the shop has worked out and owes; `settled` means
/// it has been handed over. There is deliberately no `cancelled` — a
/// settlement raised in error is deleted (only while `calculated`), because a
/// cancelled row that still sits in the ledger invites being counted twice.
enum CommissionSettlementStatus { calculated, settled }

/// One salesman's commission for one closed period.
///
/// Maps to the **`commission_ledger`** table — the table keeps the name from
/// the task file's DDL, the class is named for what a row actually is. There
/// is no double-entry involved despite the "ledger" name; this is a payable
/// worked out from sales, not a GL account. Commission is **not** posted to
/// the general ledger — see the architecture doc, the chart of accounts has
/// no commission-expense or accrued-commission account and adding one is an
/// accounting decision for a human.
///
/// `UNIQUE(salesman_id, period_from, period_to)` in the schema is what makes
/// re-running a month safe: the second attempt hits the constraint instead of
/// creating a duplicate payable.
class CommissionSettlement extends Equatable {
  final String id;
  final String salesmanId;

  /// Seconds since epoch, inclusive.
  final int periodFrom;

  /// Seconds since epoch, inclusive.
  final int periodTo;

  /// Sum of `sales.net_amount` for this salesman in the period, excluding
  /// cancelled sales. See `CommissionService.grossSalesFor`.
  final double grossSales;

  final double commissionAmount;
  final CommissionSettlementStatus status;

  /// Seconds since epoch; set when [status] becomes `settled`.
  final int? settledDate;

  /// Free text — a payslip number, a voucher reference, whatever the shop
  /// uses. This app has no payroll module to link to, and this field is the
  /// whole of the "salary integration" Task 2.4 allows.
  final String? salaryReference;

  final int createdAt;

  const CommissionSettlement({
    required this.id,
    required this.salesmanId,
    required this.periodFrom,
    required this.periodTo,
    required this.grossSales,
    required this.commissionAmount,
    this.status = CommissionSettlementStatus.calculated,
    this.settledDate,
    this.salaryReference,
    this.createdAt = 0,
  });

  factory CommissionSettlement.create({
    required String salesmanId,
    required DateTime periodFrom,
    required DateTime periodTo,
    required double grossSales,
    required double commissionAmount,
  }) {
    return CommissionSettlement(
      id: const Uuid().v4(),
      salesmanId: salesmanId,
      periodFrom: periodFrom.millisecondsSinceEpoch ~/ 1000,
      periodTo: periodTo.millisecondsSinceEpoch ~/ 1000,
      grossSales: grossSales,
      commissionAmount: commissionAmount,
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
  }

  bool get isSettled => status == CommissionSettlementStatus.settled;

  Map<String, dynamic> toJson() => {
        'id': id,
        'salesman_id': salesmanId,
        'period_from': periodFrom,
        'period_to': periodTo,
        'gross_sales': grossSales,
        'commission_amount': commissionAmount,
        'status': status.name,
        'settled_date': settledDate,
        'salary_reference': salaryReference,
        'created_at': createdAt,
      };

  factory CommissionSettlement.fromJson(Map<String, dynamic> map) => CommissionSettlement(
        id: map['id'] as String,
        salesmanId: map['salesman_id'] as String,
        periodFrom: map['period_from'] as int,
        periodTo: map['period_to'] as int,
        grossSales: (map['gross_sales'] as num?)?.toDouble() ?? 0,
        commissionAmount: (map['commission_amount'] as num?)?.toDouble() ?? 0,
        status: CommissionSettlementStatus.values.firstWhere(
          (s) => s.name == map['status'],
          orElse: () => CommissionSettlementStatus.calculated,
        ),
        settledDate: map['settled_date'] as int?,
        salaryReference: map['salary_reference'] as String?,
        createdAt: map['created_at'] as int? ?? 0,
      );

  @override
  List<Object?> get props =>
      [id, salesmanId, periodFrom, periodTo, grossSales, commissionAmount, status, settledDate];
}
