import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/financial_year.dart';
import '../../../services/financial_statement_service.dart';

final financialAmountFormat = NumberFormat('#,##0.00');

/// Formats an amount for a statement, blanking a zero so a column of figures
/// reads as figures rather than as a wall of "0.00".
String statementAmount(double value) => value == 0 ? '' : financialAmountFormat.format(value);

/// Shared chrome for the three financial statements — the financial-year
/// selector, load/error/empty handling, and CSV export.
///
/// Factored out because Trial Balance, P&L and Balance Sheet differ only in
/// what they put in the middle; triplicating the year picker and the export
/// dialog across three screens is how the three slowly stop behaving the
/// same way.
class FinancialStatementShell<T> extends StatefulWidget {
  const FinancialStatementShell({
    super.key,
    required this.title,
    required this.load,
    required this.builder,
    required this.csvRows,
    required this.csvFilePrefix,
  });

  final String title;

  /// Builds the statement for the selected financial year.
  final Future<T> Function(String financialYear) load;

  /// Renders the loaded statement.
  final Widget Function(BuildContext context, T statement) builder;

  /// The statement as rows of a CSV, header row included.
  final List<List<dynamic>> Function(T statement) csvRows;

  final String csvFilePrefix;

  @override
  State<FinancialStatementShell<T>> createState() => _FinancialStatementShellState<T>();
}

class _FinancialStatementShellState<T> extends State<FinancialStatementShell<T>> {
  final _service = FinancialStatementService();

  late String _financialYear = financialYearLabel(DateTime.now());
  List<String> _availableYears = const [];
  T? _statement;
  Object? _error;
  bool _isLoading = true;
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _loadYears();
    _reload();
  }

  Future<void> _loadYears() async {
    try {
      final years = await _service.getFinancialYearsWithEntries();
      if (!mounted) return;
      // The current year is always offered even with no entries yet —
      // otherwise a shop that hasn't billed today has an empty dropdown.
      setState(() {
        _availableYears = {financialYearLabel(DateTime.now()), ...years}.toList()
          ..sort((a, b) => b.compareTo(a));
      });
    } catch (_) {
      // A failed year list is not worth blocking the report over; the
      // selector just falls back to the current year.
    }
  }

  Future<void> _reload() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final statement = await widget.load(_financialYear);
      if (!mounted) return;
      setState(() {
        _statement = statement;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _isLoading = false;
      });
    }
  }

  Future<void> _export() async {
    final statement = _statement;
    if (statement == null) return;
    setState(() => _isExporting = true);
    try {
      final csvString = const ListToCsvConverter().convert(widget.csvRows(statement));
      final fileName = '${widget.csvFilePrefix}_${_financialYear.replaceAll('-', '')}_'
          '${DateTime.now().millisecondsSinceEpoch}.csv';

      String? savedPath;
      try {
        savedPath = await FilePicker.platform.saveFile(
          dialogTitle: 'Save ${widget.title}',
          fileName: fileName,
          bytes: utf8.encode(csvString),
        );
      } catch (_) {
        savedPath = await FilePicker.platform.saveFile(
          dialogTitle: 'Save ${widget.title}',
          fileName: fileName,
        );
        if (savedPath != null) {
          await File(savedPath).writeAsString(csvString);
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        savedPath == null
            ? const SnackBar(content: Text('Export cancelled'))
            : SnackBar(
                content: Text('Exported to $savedPath'),
                backgroundColor: Colors.green,
              ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Text('Financial Year:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(width: 12),
              DropdownButton<String>(
                value: _availableYears.contains(_financialYear) ? _financialYear : null,
                hint: Text(_financialYear),
                items: [
                  for (final year in _availableYears) DropdownMenuItem(value: year, child: Text(year)),
                ],
                onChanged: (year) {
                  if (year == null || year == _financialYear) return;
                  setState(() => _financialYear = year);
                  _reload();
                },
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _isLoading ? null : _reload,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _isExporting || _statement == null ? null : _export,
                icon: _isExporting
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.download),
                label: const Text('Export CSV'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(child: _content()),
      ],
    );
  }

  Widget _content() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Could not load this statement:\n$_error', textAlign: TextAlign.center),
        ),
      );
    }
    final statement = _statement;
    if (statement == null) return const SizedBox.shrink();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: widget.builder(context, statement),
    );
  }
}

/// The green/red "this statement balances" banner the three statements share.
///
/// These reports are diagnostics as much as summaries: a ledger that does not
/// balance is exactly the thing a shopkeeper needs told plainly, so the state
/// is stated either way rather than only when something is wrong.
class BalanceBanner extends StatelessWidget {
  const BalanceBanner({
    super.key,
    required this.isBalanced,
    required this.balancedLabel,
    required this.unbalancedLabel,
  });

  final bool isBalanced;
  final String balancedLabel;
  final String unbalancedLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isBalanced ? Colors.green.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1),
        border: Border.all(color: isBalanced ? Colors.green : Colors.red),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Icon(isBalanced ? Icons.check_circle : Icons.error, color: isBalanced ? Colors.green : Colors.red),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              isBalanced ? balancedLabel : unbalancedLabel,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isBalanced ? Colors.green.shade900 : Colors.red.shade900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A titled block of a statement — used for the P&L's sections and the
/// Balance Sheet's asset/liability/equity groups.
class StatementSection extends StatelessWidget {
  const StatementSection({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const Divider(),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// One `label ..... amount` line of a statement.
class StatementLine extends StatelessWidget {
  const StatementLine({
    super.key,
    required this.label,
    required this.amount,
    this.isTotal = false,
    this.indent = false,
  });

  final String label;
  final double amount;
  final bool isTotal;
  final bool indent;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontWeight: isTotal ? FontWeight.bold : FontWeight.normal);
    return Padding(
      padding: EdgeInsets.only(left: indent ? 16 : 0, top: 4, bottom: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(financialAmountFormat.format(amount), style: style),
        ],
      ),
    );
  }
}
