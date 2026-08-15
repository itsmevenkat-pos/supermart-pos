import 'package:flutter/material.dart';

import '../../../core/widgets/app_scaffold.dart';
import '../../../models/chart_of_account_model.dart';
import '../../../services/financial_statement_service.dart';
import '../widgets/financial_statement_shell.dart';

/// What the shop owns against what it owes and what the owners have in it.
class BalanceSheetScreen extends StatelessWidget {
  const BalanceSheetScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final service = FinancialStatementService();

    return AppScaffold(
      title: 'Balance Sheet',
      body: FinancialStatementShell<BalanceSheet>(
        title: 'Balance Sheet',
        csvFilePrefix: 'balance_sheet',
        load: (year) => service.generateBalanceSheet(financialYear: year),
        csvRows: (bs) => [
          ['Section', 'Code', 'Account', 'Amount'],
          ..._sectionCsv(bs.currentAssets),
          ..._sectionCsv(bs.fixedAssets),
          ['', '', 'TOTAL ASSETS', bs.totalAssets],
          ..._sectionCsv(bs.currentLiabilities),
          ..._sectionCsv(bs.longTermLiabilities),
          ['', '', 'TOTAL LIABILITIES', bs.totalLiabilities],
          ..._sectionCsv(bs.equity),
          ['Equity', '', 'Current Year Profit', bs.netProfit],
          ['', '', 'TOTAL EQUITY', bs.totalEquity],
        ],
        builder: (context, bs) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _section(bs.currentAssets),
              _section(bs.fixedAssets),
              StatementSection(
                title: 'Total Assets',
                children: [StatementLine(label: 'TOTAL ASSETS', amount: bs.totalAssets, isTotal: true)],
              ),
              _section(bs.currentLiabilities),
              _section(bs.longTermLiabilities),
              StatementSection(
                title: 'Equity',
                children: [
                  for (final row in bs.equity.lines.where((r) => !r.isZero))
                    StatementLine(
                      label: '${row.account.code}  ${row.account.name}',
                      amount: signedBalance(row.debit, row.credit, row.account.type),
                      indent: true,
                    ),
                  // Shown, never posted — this year's profit only becomes a
                  // real Retained Earnings entry when the year is closed.
                  StatementLine(
                    label: 'Current Year Profit (not yet posted)',
                    amount: bs.netProfit,
                    indent: true,
                  ),
                  const Divider(),
                  StatementLine(label: 'Total Equity', amount: bs.totalEquity, isTotal: true),
                ],
              ),
              StatementSection(
                title: 'Liabilities + Equity',
                children: [
                  StatementLine(label: 'Total Liabilities', amount: bs.totalLiabilities),
                  StatementLine(label: 'Total Equity', amount: bs.totalEquity),
                  const Divider(),
                  StatementLine(
                    label: 'TOTAL LIABILITIES + EQUITY',
                    amount: bs.totalLiabilities + bs.totalEquity,
                    isTotal: true,
                  ),
                ],
              ),
              BalanceBanner(
                isBalanced: bs.isBalanced,
                balancedLabel: 'Balanced — assets equal liabilities plus equity.',
                unbalancedLabel: 'NOT balanced — assets differ from liabilities plus equity by '
                    '${financialAmountFormat.format((bs.totalAssets - (bs.totalLiabilities + bs.totalEquity)).abs())}. '
                    'The ledger has a one-sided entry.',
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _section(BalanceSheetSection section) {
    final lines = section.lines.where((r) => !r.isZero).toList();
    return StatementSection(
      title: section.label,
      children: [
        for (final row in lines)
          StatementLine(
            label: '${row.account.code}  ${row.account.name}',
            amount: signedBalance(row.debit, row.credit, row.account.type),
            indent: true,
          ),
        if (lines.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Text('Nothing posted.')),
        const Divider(),
        StatementLine(label: 'Total ${section.label}', amount: section.total, isTotal: true),
      ],
    );
  }

  static List<List<dynamic>> _sectionCsv(BalanceSheetSection section) => [
        for (final row in section.lines.where((r) => !r.isZero))
          [
            section.label,
            row.account.code,
            row.account.name,
            signedBalance(row.debit, row.credit, row.account.type),
          ],
        ['', '', 'Total ${section.label}', section.total],
      ];
}
