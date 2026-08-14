import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../models/customer_model.dart';
import '../../../models/supplier_ledger_model.dart';
import '../../../models/supplier_model.dart';
import '../../../repositories/customer_ledger_repository.dart';
import '../../../repositories/customer_repository.dart';
import '../../../repositories/supplier_repository.dart';

final _dateFormat = DateFormat('dd MMM yyyy, hh:mm a');

enum _PartyType { customer, supplier }

/// One normalized ledger row, built from either a [CustomerLedger] or a
/// [SupplierLedger] entry, so the table/CSV-export code below doesn't need
/// to branch on party type — [SupplierLedgerRepository] doesn't expose a
/// `getEntries` method like its customer counterpart, so supplier entries
/// are read directly via a `supplier_ledger` table query instead (mirroring
/// what [CustomerLedgerRepository.getEntries] already does internally).
class _LedgerRow {
  final int createdAt;
  final String referenceType;
  final double amount;
  final double balance;
  final String? note;

  const _LedgerRow({
    required this.createdAt,
    required this.referenceType,
    required this.amount,
    required this.balance,
    this.note,
  });
}

class PartyStatementScreen extends ConsumerStatefulWidget {
  const PartyStatementScreen({super.key});

  @override
  ConsumerState<PartyStatementScreen> createState() => _PartyStatementScreenState();
}

class _PartyStatementScreenState extends ConsumerState<PartyStatementScreen> {
  final _searchController = TextEditingController();

  _PartyType _partyType = _PartyType.customer;
  List<Customer> _customerResults = [];
  List<Supplier> _supplierResults = [];
  bool _isSearching = false;

  Customer? _selectedCustomer;
  Supplier? _selectedSupplier;
  List<_LedgerRow> _ledgerRows = [];
  bool _isLoadingLedger = false;
  bool _isExporting = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _resetSearch() {
    _searchController.clear();
    _customerResults = [];
    _supplierResults = [];
  }

  void _clearSelection() {
    setState(() {
      _selectedCustomer = null;
      _selectedSupplier = null;
      _ledgerRows = [];
      _resetSearch();
    });
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _customerResults = [];
        _supplierResults = [];
      });
      return;
    }
    setState(() => _isSearching = true);
    try {
      if (_partyType == _PartyType.customer) {
        final results = await ref.read(customerRepositoryProvider).search(query);
        if (mounted) setState(() => _customerResults = results);
      } else {
        final results = await SupplierRepository().search(query);
        if (mounted) setState(() => _supplierResults = results);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Search error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _selectCustomer(Customer customer) async {
    setState(() {
      _selectedCustomer = customer;
      _selectedSupplier = null;
      _isLoadingLedger = true;
      _ledgerRows = [];
    });
    try {
      final entries = await ref.read(customerLedgerRepositoryProvider).getEntries(customer.id);
      if (!mounted) return;
      setState(() {
        _ledgerRows = entries
            .map((e) => _LedgerRow(
                  createdAt: e.createdAt,
                  referenceType: e.referenceType,
                  amount: e.amount,
                  balance: e.balance,
                  note: e.note,
                ))
            .toList();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading ledger: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingLedger = false);
    }
  }

  Future<void> _selectSupplier(Supplier supplier) async {
    setState(() {
      _selectedSupplier = supplier;
      _selectedCustomer = null;
      _isLoadingLedger = true;
      _ledgerRows = [];
    });
    try {
      final db = await DatabaseHelper.instance.database;
      final rows = await db.query(
        'supplier_ledger',
        where: 'supplier_id = ?',
        whereArgs: [supplier.id],
        orderBy: 'created_at ASC',
      );
      final entries = rows.map((e) => SupplierLedger.fromJson(e)).toList();
      if (!mounted) return;
      setState(() {
        _ledgerRows = entries
            .map((e) => _LedgerRow(
                  createdAt: e.createdAt,
                  referenceType: e.referenceType,
                  amount: e.amount,
                  balance: e.balance,
                ))
            .toList();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading ledger: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingLedger = false);
    }
  }

  Future<void> _export() async {
    if (_ledgerRows.isEmpty) return;
    setState(() => _isExporting = true);
    try {
      final rows = <List<dynamic>>[
        ['Date', 'Reference Type', 'Amount', 'Balance', 'Note'],
        for (final r in _ledgerRows)
          [
            _dateFormat.format(DateTime.fromMillisecondsSinceEpoch(r.createdAt * 1000)),
            r.referenceType,
            r.amount,
            r.balance,
            r.note ?? '',
          ],
      ];

      final csvString = const ListToCsvConverter().convert(rows);
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'party_statement_$timestamp.csv';

      String? savedPath;
      try {
        savedPath = await FilePicker.platform.saveFile(
          dialogTitle: 'Save Party Statement',
          fileName: fileName,
          bytes: utf8.encode(csvString),
        );
      } catch (_) {
        savedPath = await FilePicker.platform.saveFile(
          dialogTitle: 'Save Party Statement',
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
            content: Text('Exported ${_ledgerRows.length} entries to $savedPath'),
            backgroundColor: Colors.green,
          ),
        );
      }
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
    final hasSelection = _selectedCustomer != null || _selectedSupplier != null;

    return AppScaffold(
      title: 'Party Statement',
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<_PartyType>(
              segments: const [
                ButtonSegment(
                  value: _PartyType.customer,
                  label: Text('Customer'),
                  icon: Icon(Icons.people),
                ),
                ButtonSegment(
                  value: _PartyType.supplier,
                  label: Text('Supplier'),
                  icon: Icon(Icons.business),
                ),
              ],
              selected: {_partyType},
              onSelectionChanged: hasSelection
                  ? null
                  : (selection) {
                      setState(() {
                        _partyType = selection.first;
                        _resetSearch();
                      });
                    },
            ),
            const SizedBox(height: 16),
            if (!hasSelection) ...[
              TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  labelText: 'Search by name / phone',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: _search,
              ),
              const SizedBox(height: 8),
              if (_isSearching) const LinearProgressIndicator(),
              Expanded(child: _buildSearchResults()),
            ] else ...[
              _buildPartyHeader(),
              const SizedBox(height: 12),
              Expanded(child: _buildLedgerTable()),
              const SizedBox(height: 16),
              SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: (_isExporting || _isLoadingLedger || _ledgerRows.isEmpty) ? null : _export,
                  icon: _isExporting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download),
                  label: const Text('Export CSV'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    final query = _searchController.text.trim();
    if (_partyType == _PartyType.customer) {
      if (query.isEmpty) {
        return const Center(child: Text('Search for a customer to view their statement'));
      }
      if (!_isSearching && _customerResults.isEmpty) {
        return const Center(child: Text('No matching customers'));
      }
      return ListView.separated(
        itemCount: _customerResults.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, index) {
          final customer = _customerResults[index];
          return ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person)),
            title: Text(customer.name),
            subtitle: Text(customer.phone),
            trailing: Text('₹${customer.outstandingBalance.toStringAsFixed(2)}'),
            onTap: () => _selectCustomer(customer),
          );
        },
      );
    } else {
      if (query.isEmpty) {
        return const Center(child: Text('Search for a supplier to view their statement'));
      }
      if (!_isSearching && _supplierResults.isEmpty) {
        return const Center(child: Text('No matching suppliers'));
      }
      return ListView.separated(
        itemCount: _supplierResults.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, index) {
          final supplier = _supplierResults[index];
          return ListTile(
            leading: const CircleAvatar(child: Icon(Icons.business)),
            title: Text(supplier.name),
            subtitle: Text(supplier.phone ?? 'No phone'),
            onTap: () => _selectSupplier(supplier),
          );
        },
      );
    }
  }

  Widget _buildPartyHeader() {
    final isCustomer = _selectedCustomer != null;
    final name = isCustomer ? _selectedCustomer!.name : _selectedSupplier!.name;
    final phone = isCustomer ? _selectedCustomer!.phone : (_selectedSupplier!.phone ?? 'No phone');
    final balance = _ledgerRows.isNotEmpty ? _ledgerRows.last.balance : 0.0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.phone, size: 16, color: Colors.grey),
                    const SizedBox(width: 6),
                    Text(phone),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text('Current Balance', style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 2),
              Text(
                '₹${balance.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: balance > 0 ? Colors.red : Colors.green,
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Change party',
            onPressed: _clearSelection,
          ),
        ],
      ),
    );
  }

  Widget _buildLedgerTable() {
    if (_isLoadingLedger) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_ledgerRows.isEmpty) {
      return const Center(child: Text('No transactions yet'));
    }
    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Date')),
            DataColumn(label: Text('Type')),
            DataColumn(label: Text('Amount'), numeric: true),
            DataColumn(label: Text('Balance'), numeric: true),
            DataColumn(label: Text('Note')),
          ],
          rows: _ledgerRows
              .map(
                (r) => DataRow(cells: [
                  DataCell(Text(_dateFormat.format(DateTime.fromMillisecondsSinceEpoch(r.createdAt * 1000)))),
                  DataCell(Text(r.referenceType)),
                  DataCell(Text(r.amount.toStringAsFixed(2))),
                  DataCell(Text(r.balance.toStringAsFixed(2))),
                  DataCell(Text(r.note ?? '')),
                ]),
              )
              .toList(),
        ),
      ),
    );
  }
}
