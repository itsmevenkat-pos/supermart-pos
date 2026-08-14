import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../core/widgets/app_scaffold.dart';
import '../widgets/date_filter_widget.dart';

/// Describes one column of a [GenericReportScreen] table: which key to pull
/// out of each row map, what header label to show, and how to format the
/// raw value for display/export.
class ReportColumn {
  final String key;
  final String label;
  final String Function(dynamic value)? formatter;

  const ReportColumn({required this.key, required this.label, this.formatter});

  String format(dynamic value) {
    if (value == null) return '';
    if (formatter != null) return formatter!(value);
    return value.toString();
  }
}

/// A reusable, data-shape-agnostic report screen: given a fetch callback
/// that returns `List<Map<String, dynamic>>` rows for an optional date
/// range, and a set of [ReportColumn]s describing how to render them, this
/// renders a scrollable table with date filtering, refresh, and CSV export
/// — so individual report screens don't need to be written by hand.
class GenericReportScreen extends StatefulWidget {
  final String title;
  final Future<List<Map<String, dynamic>>> Function(DateTime? from, DateTime? to) fetch;
  final List<ReportColumn> columns;
  final String? disclaimerText;

  const GenericReportScreen({
    super.key,
    required this.title,
    required this.fetch,
    required this.columns,
    this.disclaimerText,
  });

  @override
  State<GenericReportScreen> createState() => _GenericReportScreenState();
}

class _GenericReportScreenState extends State<GenericReportScreen> {
  DateTime? _fromDate;
  DateTime? _toDate;
  bool _isLoading = false;
  bool _isExporting = false;
  List<Map<String, dynamic>> _rows = [];

  @override
  void initState() {
    super.initState();
    _loadReport();
  }

  Future<void> _loadReport() async {
    setState(() => _isLoading = true);
    try {
      final rows = await widget.fetch(_fromDate, _toDate);
      if (!mounted) return;
      setState(() => _rows = rows);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading report: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _export() async {
    if (_rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No data to export')),
      );
      return;
    }

    setState(() => _isExporting = true);
    try {
      final csvRows = <List<dynamic>>[
        [for (final column in widget.columns) column.label],
        for (final row in _rows)
          [for (final column in widget.columns) column.format(row[column.key])],
      ];

      final csvString = const ListToCsvConverter().convert(csvRows);
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final safeTitle = widget.title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
      final fileName = '${safeTitle}_$timestamp.csv';

      String? savedPath;
      try {
        savedPath = await FilePicker.platform.saveFile(
          dialogTitle: 'Save ${widget.title} Export',
          fileName: fileName,
          bytes: utf8.encode(csvString),
        );
      } catch (_) {
        savedPath = await FilePicker.platform.saveFile(
          dialogTitle: 'Save ${widget.title} Export',
          fileName: fileName,
        );
        if (savedPath != null) {
          await File(savedPath).writeAsString(csvString);
        }
      }

      if (!mounted) return;

      if (savedPath == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Export cancelled')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Exported ${_rows.length} rows to $savedPath'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error exporting report: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: widget.title,
      actions: [
        DateFilterWidget(
          fromDate: _fromDate,
          toDate: _toDate,
          onFilterApplied: (from, to) {
            setState(() {
              _fromDate = from;
              _toDate = to;
            });
            _loadReport();
          },
          onFilterCleared: () {
            setState(() {
              _fromDate = null;
              _toDate = null;
            });
            _loadReport();
          },
        ),
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Refresh',
          onPressed: _isLoading ? null : _loadReport,
        ),
        IconButton(
          icon: _isExporting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.download),
          tooltip: 'Export CSV',
          onPressed: _isExporting ? null : _export,
        ),
      ],
      body: Column(
        children: [
          if (widget.disclaimerText != null) _DisclaimerBanner(text: widget.disclaimerText!),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_rows.isEmpty) {
      return const Center(
        child: Text(
          'No data for this period',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          columns: [
            for (final column in widget.columns) DataColumn(label: Text(column.label)),
          ],
          rows: [
            for (final row in _rows)
              DataRow(
                cells: [
                  for (final column in widget.columns) DataCell(Text(column.format(row[column.key]))),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _DisclaimerBanner extends StatelessWidget {
  final String text;

  const _DisclaimerBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Colors.amber.shade100,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.orange.shade900,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
