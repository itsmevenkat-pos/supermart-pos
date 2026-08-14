import 'package:flutter/material.dart';

import '../../../core/widgets/app_scaffold.dart';
import '../../../services/financial_statement_service.dart';
import '../widgets/financial_statement_shell.dart';

/// Every active account's balance in a debit and a credit column, with the
/// two totals that must agree.
class TrialBalanceScreen extends StatelessWidget {
  const TrialBalanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final service = FinancialStatementService();

    return AppScaffold(
      title: 'Trial Balance',
      body: FinancialStatementShell<TrialBalance>(
        title: 'Trial Balance',
        csvFilePrefix: 'trial_balance',
        load: service.generateTrialBalance,
        csvRows: (tb) => [
          ['Code', 'Account', 'Type', 'Debit', 'Credit'],
          for (final row in tb.nonZeroRows)
            [row.account.code, row.account.name, row.account.type.name, row.debit, row.credit],
          ['', 'TOTAL', '', tb.totalDebits, tb.totalCredits],
        ],
        builder: (context, tb) {
          final rows = tb.nonZeroRows;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No ledger entries for this financial year yet.', textAlign: TextAlign.center),
                )
              else
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Code')),
                      DataColumn(label: Text('Account')),
                      DataColumn(label: Text('Debit'), numeric: true),
                      DataColumn(label: Text('Credit'), numeric: true),
                    ],
                    rows: [
                      for (final row in rows)
                        DataRow(cells: [
                          DataCell(Text(row.account.code)),
                          DataCell(Text(row.account.name)),
                          DataCell(Text(statementAmount(row.debit))),
                          DataCell(Text(statementAmount(row.credit))),
                        ]),
                      DataRow(
                        cells: [
                          const DataCell(Text('')),
                          const DataCell(Text('TOTAL', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataCell(Text(
                            financialAmountFormat.format(tb.totalDebits),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          )),
                          DataCell(Text(
                            financialAmountFormat.format(tb.totalCredits),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          )),
                        ],
                      ),
                    ],
                  ),
                ),
              BalanceBanner(
                isBalanced: tb.isBalanced,
                balancedLabel: 'Balanced — total debits equal total credits.',
                unbalancedLabel: 'NOT balanced — debits and credits differ by '
                    '${financialAmountFormat.format((tb.totalDebits - tb.totalCredits).abs())}. '
                    'The ledger has a one-sided entry.',
              ),
            ],
          );
        },
      ),
    );
  }
}
