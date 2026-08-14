import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_scaffold.dart';
import '../../../models/customer_model.dart';
import '../../../models/supplier_model.dart';
import '../../../repositories/customer_repository.dart';
import '../../../repositories/supplier_repository.dart';

enum _PartyType { customer, supplier }

/// One parsed CSV row, holding either a ready-to-insert [Customer]/[Supplier]
/// (when [isOk] is true) or a human-readable reason it was skipped.
class _ImportRow {
  final List<dynamic> raw;
  final String status;
  final bool isOk;
  final Customer? customer;
  final Supplier? supplier;

  const _ImportRow({
    required this.raw,
    required this.status,
    required this.isOk,
    this.customer,
    this.supplier,
  });
}

class ImportPartiesScreen extends ConsumerStatefulWidget {
  const ImportPartiesScreen({super.key});

  @override
  ConsumerState<ImportPartiesScreen> createState() => _ImportPartiesScreenState();
}

class _ImportPartiesScreenState extends ConsumerState<ImportPartiesScreen> {
  _PartyType _selectedType = _PartyType.customer;
  List<_ImportRow> _rows = [];
  String? _fileName;
  bool _isBusy = false;

  int get _okCount => _rows.where((r) => r.isOk).length;

  String _cell(List<dynamic> row, int index) {
    if (index >= row.length) return '';
    final value = row[index];
    if (value == null) return '';
    return value.toString().trim();
  }

  void _resetPreview() {
    _rows = [];
    _fileName = null;
  }

  Future<void> _pickFile() async {
    setState(() {
      _isBusy = true;
      _resetPreview();
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );
      if (result == null || result.files.single.path == null) {
        return;
      }

      final path = result.files.single.path!;
      final csvString = await File(path).readAsString(encoding: utf8);
      final rows = const CsvToListConverter().convert(csvString, eol: '\n');
      if (rows.isEmpty) {
        throw Exception('CSV file is empty');
      }

      final dataRows = rows.skip(1).toList(); // skip header row
      final parsed = _selectedType == _PartyType.customer
          ? _parseCustomerRows(dataRows)
          : _parseSupplierRows(dataRows);

      setState(() {
        _fileName = result.files.single.name;
        _rows = parsed;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error reading file: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  List<_ImportRow> _parseCustomerRows(List<List<dynamic>> dataRows) {
    final parsed = <_ImportRow>[];
    for (final row in dataRows) {
      if (row.every((c) => c == null || c.toString().trim().isEmpty)) {
        continue; // skip fully blank lines
      }
      final name = _cell(row, 0);
      final phone = _cell(row, 1);
      final email = _cell(row, 2);
      final address = _cell(row, 3);
      final locality = _cell(row, 4);
      final creditLimit = double.tryParse(_cell(row, 5)) ?? 0;

      String status;
      bool ok;
      if (name.isEmpty) {
        status = 'Missing name';
        ok = false;
      } else if (phone.isEmpty) {
        status = 'Missing phone';
        ok = false;
      } else {
        status = 'OK';
        ok = true;
      }

      parsed.add(_ImportRow(
        raw: row,
        status: status,
        isOk: ok,
        customer: ok
            ? Customer.create(
                storeId: 'store_default',
                phone: phone,
                name: name,
                email: email.isEmpty ? null : email,
                address: address.isEmpty ? null : address,
                locality: locality.isEmpty ? null : locality,
                creditLimit: creditLimit,
              )
            : null,
      ));
    }
    return parsed;
  }

  List<_ImportRow> _parseSupplierRows(List<List<dynamic>> dataRows) {
    final parsed = <_ImportRow>[];
    for (final row in dataRows) {
      if (row.every((c) => c == null || c.toString().trim().isEmpty)) {
        continue; // skip fully blank lines
      }
      final name = _cell(row, 0);
      final phone = _cell(row, 1);
      final email = _cell(row, 2);
      final address = _cell(row, 3);
      final openingBalance = double.tryParse(_cell(row, 4)) ?? 0;

      String status;
      bool ok;
      if (name.isEmpty) {
        status = 'Missing name';
        ok = false;
      } else {
        status = 'OK';
        ok = true;
      }

      parsed.add(_ImportRow(
        raw: row,
        status: status,
        isOk: ok,
        supplier: ok
            ? Supplier.create(
                storeId: 'store_default',
                name: name,
                phone: phone.isEmpty ? null : phone,
                email: email.isEmpty ? null : email,
                address: address.isEmpty ? null : address,
                openingBalance: openingBalance,
              )
            : null,
      ));
    }
    return parsed;
  }

  Future<void> _import() async {
    final okRows = _rows.where((r) => r.isOk).toList();
    if (okRows.isEmpty) return;

    setState(() => _isBusy = true);
    try {
      if (_selectedType == _PartyType.customer) {
        final customers = okRows.map((r) => r.customer!).toList();
        await ref.read(customerRepositoryProvider).bulkInsert(customers);
      } else {
        final suppliers = okRows.map((r) => r.supplier!).toList();
        await SupplierRepository().bulkInsert(suppliers);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Imported ${okRows.length} ${_selectedType == _PartyType.customer ? 'customer(s)' : 'supplier(s)'} successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Import Parties',
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<_PartyType>(
              segments: const [
                ButtonSegment(
                  value: _PartyType.customer,
                  label: Text('Customers'),
                  icon: Icon(Icons.people),
                ),
                ButtonSegment(
                  value: _PartyType.supplier,
                  label: Text('Suppliers'),
                  icon: Icon(Icons.business),
                ),
              ],
              selected: {_selectedType},
              onSelectionChanged: _isBusy
                  ? null
                  : (selection) {
                      setState(() {
                        _selectedType = selection.first;
                        _resetPreview();
                      });
                    },
            ),
            const SizedBox(height: 12),
            Text(
              _selectedType == _PartyType.customer
                  ? 'Expected columns: name, phone, email, address, locality, credit_limit'
                  : 'Expected columns: name, phone, email, address, opening_balance',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _isBusy ? null : _pickFile,
              icon: const Icon(Icons.upload_file),
              label: const Text('Choose CSV File'),
            ),
            if (_fileName != null) ...[
              const SizedBox(height: 8),
              Text('File: $_fileName', style: Theme.of(context).textTheme.bodyMedium),
            ],
            const SizedBox(height: 16),
            if (_isBusy) const Center(child: CircularProgressIndicator()),
            if (!_isBusy && _rows.isNotEmpty) ...[
              Text(
                '$_okCount of ${_rows.length} row(s) ready to import',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Expanded(child: _buildPreviewTable()),
              const SizedBox(height: 16),
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: (_isBusy || _okCount == 0) ? null : _import,
                  child: Text('Import ($_okCount)'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewTable() {
    final columns = _selectedType == _PartyType.customer
        ? const ['Name', 'Phone', 'Email', 'Address', 'Locality', 'Credit Limit', 'Status']
        : const ['Name', 'Phone', 'Email', 'Address', 'Opening Balance', 'Status'];
    final fieldCount = columns.length - 1;

    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: columns.map((c) => DataColumn(label: Text(c))).toList(),
          rows: _rows.map((row) {
            final cells = <DataCell>[
              for (var i = 0; i < fieldCount; i++) DataCell(Text(_cell(row.raw, i))),
              DataCell(
                Text(
                  row.status,
                  style: TextStyle(
                    color: row.isOk ? Colors.green : Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ];
            return DataRow(cells: cells);
          }).toList(),
        ),
      ),
    );
  }
}
