import 'package:flutter/material.dart';

import '../../../core/widgets/app_scaffold.dart';
import '../../../services/financial_statement_service.dart';
import '../widgets/financial_statement_shell.dart';

/// Revenue less cost of goods sold less other expenses, for one financial
/// year.
class PLStatementScreen extends StatelessWidget {
  const PLStatementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final service = FinancialStatementService();

    return AppScaffold(
      title: 'Profit & Loss',
      body: FinancialStatementShell<PLStatement>(
        title: 'Profit & Loss',
        csvFilePrefix: 'profit_and_loss',
        load: (year) => service.generatePLStatement(financialYear: year),
        csvRows: (pl) => [
          ['Section', 'Code', 'Account', 'Amount'],
          for (final row in pl.revenueLines.where((r) => !r.isZero))
            ['Revenue', row.account.code, row.account.name, row.credit - row.debit],
          ['', '', 'Total Revenue', pl.revenue],
          ['', '', 'Cost of Goods Sold', pl.cogs],
          ['', '', 'Gross Profit', pl.grossProfit],
          for (final row in pl.expenseLines.where((r) => !r.isZero && r.account.code != '5000'))
            ['Expense', row.account.code, row.account.name, row.debit - row.credit],
          ['', '', 'Total Other Expenses', pl.otherExpenses],
          ['', '', 'Net Profit', pl.netProfit],
        ],
        builder: (context, pl) {
          final revenueLines = pl.revenueLines.where((r) => !r.isZero).toList();
          final otherExpenseLines =
              pl.expenseLines.where((r) => !r.isZero && r.account.code != '5000').toList();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              StatementSection(
                title: 'Revenue',
                children: [
                  for (final row in revenueLines)
                    StatementLine(
                      label: '${row.account.code}  ${row.account.name}',
                      amount: row.credit - row.debit,
                      indent: true,
                    ),
                  if (revenueLines.isEmpty)
                    const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Text('No revenue posted.')),
                  const Divider(),
                  StatementLine(label: 'Total Revenue', amount: pl.revenue, isTotal: true),
                ],
              ),
              StatementSection(
                title: 'Cost of Goods Sold',
                children: [
                  StatementLine(label: 'Cost of Goods Sold (5000)', amount: pl.cogs, indent: true),
                  const Divider(),
                  StatementLine(label: 'Gross Profit', amount: pl.grossProfit, isTotal: true),
                ],
              ),
              StatementSection(
                title: 'Operating & Other Expenses',
                children: [
                  for (final row in otherExpenseLines)
                    StatementLine(
                      label: '${row.account.code}  ${row.account.name}',
                      amount: row.debit - row.credit,
                      indent: true,
                    ),
                  if (otherExpenseLines.isEmpty)
                    const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Text('No expenses posted.')),
                  const Divider(),
                  StatementLine(label: 'Total Other Expenses', amount: pl.otherExpenses, isTotal: true),
                ],
              ),
              Card(
                color: pl.netProfit >= 0 ? Colors.green.withValues(alpha: 0.08) : Colors.red.withValues(alpha: 0.08),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Text(
                        pl.netProfit >= 0 ? 'Net Profit' : 'Net Loss',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                      const Spacer(),
                      Text(
                        financialAmountFormat.format(pl.netProfit.abs()),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: pl.netProfit >= 0 ? Colors.green.shade900 : Colors.red.shade900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
