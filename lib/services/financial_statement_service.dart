import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../core/database/database_helper.dart';
import '../models/chart_of_account_model.dart';
import '../repositories/gl_repository.dart';

/// One account's line on a Trial Balance, already split into the two columns.
class TrialBalanceRow {
  const TrialBalanceRow({
    required this.account,
    required this.debit,
    required this.credit,
  });

  final ChartOfAccount account;
  final double debit;
  final double credit;

  bool get isZero => debit == 0 && credit == 0;
}

class TrialBalance {
  const TrialBalance({
    required this.financialYear,
    required this.rows,
    required this.totalDebits,
    required this.totalCredits,
  });

  final String financialYear;
  final List<TrialBalanceRow> rows;
  final double totalDebits;
  final double totalCredits;

  /// Rows that actually moved — what a reader normally wants to look at.
  List<TrialBalanceRow> get nonZeroRows => rows.where((r) => !r.isZero).toList();

  bool get isBalanced => (totalDebits - totalCredits).abs() < FinancialStatementService.tolerance;
}

/// A Profit & Loss statement for one financial year.
class PLStatement {
  const PLStatement({
    required this.financialYear,
    required this.revenue,
    required this.cogs,
    required this.otherExpenses,
    required this.revenueLines,
    required this.expenseLines,
  });

  final String financialYear;
  final double revenue;
  final double cogs;
  final double otherExpenses;

  /// Per-account detail, so the screen can show the breakdown rather than
  /// three opaque totals.
  final List<TrialBalanceRow> revenueLines;
  final List<TrialBalanceRow> expenseLines;

  double get grossProfit => revenue - cogs;
  double get totalExpenses => cogs + otherExpenses;
  double get netProfit => revenue - cogs - otherExpenses;
}

/// One side's worth of a Balance Sheet section, split by `sub_type`.
class BalanceSheetSection {
  const BalanceSheetSection({required this.label, required this.lines});

  final String label;
  final List<TrialBalanceRow> lines;

  /// Totalled in each account's own natural direction (see [signedBalance]),
  /// so an asset section totals what the shop has and a liability section what
  /// it owes — both as positive numbers, the way a reader expects to see them.
  double get total => lines.fold(0, (sum, r) => sum + signedBalance(r.debit, r.credit, r.account.type));
}

class BalanceSheet {
  const BalanceSheet({
    required this.financialYear,
    required this.asOf,
    required this.currentAssets,
    required this.fixedAssets,
    required this.currentLiabilities,
    required this.longTermLiabilities,
    required this.equity,
    required this.netProfit,
  });

  final String financialYear;
  final DateTime? asOf;

  final BalanceSheetSection currentAssets;
  final BalanceSheetSection fixedAssets;
  final BalanceSheetSection currentLiabilities;
  final BalanceSheetSection longTermLiabilities;
  final BalanceSheetSection equity;

  /// This year's profit, shown inside Equity as un-appropriated Retained
  /// Earnings. Deliberately *not* posted as a GL entry — that only happens
  /// when the year is closed. Until then it exists on this report only.
  final double netProfit;

  double get totalAssets => currentAssets.total + fixedAssets.total;
  double get totalLiabilities => currentLiabilities.total + longTermLiabilities.total;

  /// Posted equity plus the year's profit — the profit belongs to the owners
  /// even before it is formally appropriated, and leaving it out is exactly
  /// what would make this statement fail to balance.
  double get totalEquity => equity.total + netProfit;

  bool get isBalanced =>
      (totalAssets - (totalLiabilities + totalEquity)).abs() < FinancialStatementService.tolerance;
}

/// Trial Balance, Profit & Loss and Balance Sheet, computed from the General
/// Ledger.
///
/// **Strictly read-only.** Every figure comes from `gl_entries`; nothing here
/// writes, and nothing here reads the `gl_balances` cache either. Summing the
/// journal directly costs one indexed query and means a report can never show
/// a stale number — and it is what makes the optional `asOf` cut-off on the
/// Balance Sheet possible at all, since the cache only knows whole years.
///
/// All three share [_accountTotals], so there is one piece of SQL behind them
/// and no way for the Trial Balance and the Balance Sheet to disagree about
/// what an account's balance is.
class FinancialStatementService {
  FinancialStatementService({DatabaseHelper? dbHelper, GLRepository? glRepository})
      : _dbHelper = dbHelper ?? DatabaseHelper.instance,
        _glRepository = glRepository ?? GLRepository();

  final DatabaseHelper _dbHelper;
  final GLRepository _glRepository;

  /// Rounding tolerance for "does this balance?" — same reasoning as
  /// `GLService.balanceTolerance`: paise-level drift is arithmetic, anything
  /// larger is a real problem.
  static const double tolerance = 0.01;

  /// The account code COGS is tracked under. `sub_type` is 'cogs'.
  static const String cogsAccountCode = '5000';

  // Sub-types seeded by MigrationV28, which the Balance Sheet splits on.
  static const String currentAssetSubType = 'current_asset';
  static const String fixedAssetSubType = 'fixed_asset';
  static const String currentLiabilitySubType = 'current_liability';
  static const String longTermLiabilitySubType = 'long_term_liability';

  /// Debit and credit totals per account for [financialYear], optionally only
  /// counting entries dated on or before [asOf].
  ///
  /// The one query all three statements are built on.
  Future<Map<String, ({double debit, double credit})>> _accountTotals(
    String financialYear, {
    DateTime? asOf,
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await _dbHelper.database;
    final args = <Object?>[financialYear];
    var where = 'financial_year = ?';
    if (asOf != null) {
      where += ' AND entry_date <= ?';
      args.add(asOf.millisecondsSinceEpoch ~/ 1000);
    }
    final rows = await db.rawQuery(
      'SELECT account_id, COALESCE(SUM(debit), 0) AS d, COALESCE(SUM(credit), 0) AS c '
      'FROM gl_entries WHERE $where GROUP BY account_id',
      args,
    );
    return {
      for (final row in rows)
        row['account_id'] as String: (
          debit: (row['d'] as num).toDouble(),
          credit: (row['c'] as num).toDouble(),
        ),
    };
  }

  /// Splits an account's activity into the Trial Balance's two columns.
  ///
  /// The rule is simply "debit balance goes in the debit column" — which is
  /// the same thing as the task's phrasing (normally-debit and positive, or
  /// normally-credit and negative), just stated without the double negative.
  /// Because every posted entry balances, summing these two columns over all
  /// accounts is guaranteed to produce equal totals.
  TrialBalanceRow _row(ChartOfAccount account, ({double debit, double credit})? totals) {
    final raw = (totals?.debit ?? 0) - (totals?.credit ?? 0);
    return TrialBalanceRow(
      account: account,
      debit: raw > 0 ? raw : 0,
      credit: raw < 0 ? -raw : 0,
    );
  }

  // ------------------------------------------------------------ trial balance

  /// Every active account, its balance split into debit and credit columns.
  Future<TrialBalance> generateTrialBalance(
    String financialYear, {
    DateTime? asOf,
    DatabaseExecutor? executor,
  }) async {
    final accounts = await _glRepository.getAllAccounts(isActive: true, executor: executor);
    final totals = await _accountTotals(financialYear, asOf: asOf, executor: executor);

    final rows = accounts.map((account) => _row(account, totals[account.id])).toList();

    return TrialBalance(
      financialYear: financialYear,
      rows: rows,
      totalDebits: rows.fold(0, (sum, r) => sum + r.debit),
      totalCredits: rows.fold(0, (sum, r) => sum + r.credit),
    );
  }

  // --------------------------------------------------------------------- P&L

  /// Revenue less cost of goods sold less other expenses, for [financialYear].
  ///
  /// COGS is broken out from the other expenses by account code
  /// [cogsAccountCode], per Task 1.4.
  ///
  /// **Known limitation, deliberate:** nothing currently *posts* to account
  /// 5000 — Task 1.3's sale integration was specified as cash/receivable
  /// against revenue only, with no matching inventory-to-COGS movement. So
  /// COGS reads zero here and gross profit equals revenue until a COGS
  /// posting exists. That is a missing posting, not a missing calculation,
  /// and the fix belongs on the posting side.
  ///
  /// It would be easy to paper over by computing COGS from
  /// `sale_items.cost_price` the way `ReportService` already does — and that
  /// is exactly what is avoided here. Two independent COGS figures that can
  /// drift apart is a worse problem than one that is visibly zero, and this
  /// statement is meant to report the ledger, not to work around it.
  Future<PLStatement> generatePLStatement({
    required String financialYear,
    DateTime? asOf,
    DatabaseExecutor? executor,
  }) async {
    final accounts = await _glRepository.getAllAccounts(isActive: true, executor: executor);
    final totals = await _accountTotals(financialYear, asOf: asOf, executor: executor);

    final revenueLines = <TrialBalanceRow>[];
    final expenseLines = <TrialBalanceRow>[];
    var revenue = 0.0;
    var cogs = 0.0;
    var otherExpenses = 0.0;

    for (final account in accounts) {
      final row = _row(account, totals[account.id]);
      // Each account's contribution in its own natural direction: revenue
      // earned, expense incurred.
      final amount = signedBalance(
        totals[account.id]?.debit ?? 0,
        totals[account.id]?.credit ?? 0,
        account.type,
      );

      switch (account.type) {
        case AccountType.revenue:
          revenueLines.add(row);
          revenue += amount;
        case AccountType.expense:
          expenseLines.add(row);
          if (account.code == cogsAccountCode) {
            cogs += amount;
          } else {
            otherExpenses += amount;
          }
        case AccountType.asset:
        case AccountType.liability:
        case AccountType.equity:
          break;
      }
    }

    return PLStatement(
      financialYear: financialYear,
      revenue: revenue,
      cogs: cogs,
      otherExpenses: otherExpenses,
      revenueLines: revenueLines,
      expenseLines: expenseLines,
    );
  }

  // ----------------------------------------------------------- balance sheet

  /// Assets against liabilities and equity, as at [asOf] (or the whole
  /// financial year when omitted).
  ///
  /// Balances by construction rather than by luck: every posted entry has
  /// equal debits and credits, so across all accounts the debit-minus-credit
  /// total is zero, which rearranges to exactly
  /// `Assets = Liabilities + Equity + (Revenue - Expenses)`. [netProfit] is
  /// that last bracket — which is why it is included in equity here and why
  /// leaving it out would make the statement fail to balance.
  Future<BalanceSheet> generateBalanceSheet({
    required String financialYear,
    DateTime? asOf,
    DatabaseExecutor? executor,
  }) async {
    final accounts = await _glRepository.getAllAccounts(isActive: true, executor: executor);
    final totals = await _accountTotals(financialYear, asOf: asOf, executor: executor);

    final currentAssets = <TrialBalanceRow>[];
    final fixedAssets = <TrialBalanceRow>[];
    final currentLiabilities = <TrialBalanceRow>[];
    final longTermLiabilities = <TrialBalanceRow>[];
    final equity = <TrialBalanceRow>[];
    var revenue = 0.0;
    var expenses = 0.0;

    for (final account in accounts) {
      final row = _row(account, totals[account.id]);
      final amount = signedBalance(
        totals[account.id]?.debit ?? 0,
        totals[account.id]?.credit ?? 0,
        account.type,
      );

      switch (account.type) {
        case AccountType.asset:
          // An unrecognised sub_type is treated as current rather than
          // dropped — a misfiled asset on the wrong line is a labelling
          // problem, an omitted one silently unbalances the statement.
          (account.subType == fixedAssetSubType ? fixedAssets : currentAssets).add(row);
        case AccountType.liability:
          (account.subType == longTermLiabilitySubType ? longTermLiabilities : currentLiabilities).add(row);
        case AccountType.equity:
          equity.add(row);
        case AccountType.revenue:
          revenue += amount;
        case AccountType.expense:
          expenses += amount;
      }
    }

    return BalanceSheet(
      financialYear: financialYear,
      asOf: asOf,
      currentAssets: BalanceSheetSection(label: 'Current Assets', lines: currentAssets),
      fixedAssets: BalanceSheetSection(label: 'Fixed Assets', lines: fixedAssets),
      currentLiabilities: BalanceSheetSection(label: 'Current Liabilities', lines: currentLiabilities),
      longTermLiabilities: BalanceSheetSection(label: 'Long-term Liabilities', lines: longTermLiabilities),
      equity: BalanceSheetSection(label: 'Equity', lines: equity),
      netProfit: revenue - expenses,
    );
  }

  // -------------------------------------------------------------- year list

  /// Financial years that actually have ledger activity, newest first — for
  /// the year selector on the report screens.
  Future<List<String>> getFinancialYearsWithEntries({DatabaseExecutor? executor}) async {
    final db = executor ?? await _dbHelper.database;
    final rows = await db.rawQuery(
      'SELECT DISTINCT financial_year FROM gl_entries ORDER BY financial_year DESC',
    );
    return rows.map((row) => row['financial_year'] as String).toList();
  }
}

final financialStatementServiceProvider = Provider<FinancialStatementService>((ref) {
  return FinancialStatementService();
});
