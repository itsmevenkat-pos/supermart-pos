import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_scaffold.dart';
import '../../../models/sale_item_model.dart';
import '../../../repositories/customer_repository.dart';
import '../../../repositories/product_repository.dart';
import '../../../repositories/sale_repository.dart';
import '../../../services/tally_xml_service.dart';

enum _TallyExportKind { stockItems, ledgers, salesVouchers }

/// Lets a manager/accountant export Stock Items, Ledgers, or Sales Vouchers
/// (for a chosen date range) to a Tally-importable XML file.
class ExportTallyScreen extends ConsumerStatefulWidget {
  const ExportTallyScreen({super.key});

  @override
  ConsumerState<ExportTallyScreen> createState() => _ExportTallyScreenState();
}

class _ExportTallyScreenState extends ConsumerState<ExportTallyScreen> {
  bool _isExporting = false;
  _TallyExportKind _kind = _TallyExportKind.stockItems;
  late DateTime _startDate;
  late DateTime _endDate;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, 1);
    _endDate = DateTime(now.year, now.month, now.day);
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
    }
  }

  Future<void> _export() async {
    setState(() => _isExporting = true);
    try {
      String xmlString;
      int recordCount;

      switch (_kind) {
        case _TallyExportKind.stockItems:
          final products = await ref.read(productRepositoryProvider).getAll(activeOnly: false);
          xmlString = TallyXmlService.buildStockItemEnvelope(products);
          recordCount = products.length;
          break;
        case _TallyExportKind.ledgers:
          final customers = await ref.read(customerRepositoryProvider).getAll(includeDeleted: false);
          xmlString = TallyXmlService.buildLedgerEnvelope(customers);
          recordCount = customers.length;
          break;
        case _TallyExportKind.salesVouchers:
          final saleRepository = ref.read(saleRepositoryProvider);
          // End-of-day boundary so the range includes the whole last day,
          // matching what the date-range picker visually implies.
          final rangeEnd = DateTime(_endDate.year, _endDate.month, _endDate.day, 23, 59, 59);
          final sales = await saleRepository.getByDateRange(_startDate, rangeEnd);
          final itemsBySaleId = <String, List<SaleItem>>{};
          for (final sale in sales) {
            itemsBySaleId[sale.id] = await saleRepository.getItemsBySale(sale.id);
          }
          xmlString = TallyXmlService.buildSalesVoucherEnvelope(sales, itemsBySaleId);
          recordCount = sales.length;
          break;
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'tally_export_$timestamp.xml';

      String? savedPath;
      try {
        savedPath = await FilePicker.platform.saveFile(
          dialogTitle: 'Save Tally Export',
          fileName: fileName,
          bytes: utf8.encode(xmlString),
        );
      } catch (_) {
        savedPath = await FilePicker.platform.saveFile(
          dialogTitle: 'Save Tally Export',
          fileName: fileName,
        );
        if (savedPath != null) {
          await File(savedPath).writeAsString(xmlString);
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
            content: Text('Exported $recordCount record(s) to $savedPath'),
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

  String _formatDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Exports To Tally',
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('What to export', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            RadioListTile<_TallyExportKind>(
              value: _TallyExportKind.stockItems,
              groupValue: _kind,
              title: const Text('Stock Items (Masters)'),
              onChanged: (val) => setState(() => _kind = val ?? _kind),
            ),
            RadioListTile<_TallyExportKind>(
              value: _TallyExportKind.ledgers,
              groupValue: _kind,
              title: const Text('Parties (Ledgers)'),
              onChanged: (val) => setState(() => _kind = val ?? _kind),
            ),
            RadioListTile<_TallyExportKind>(
              value: _TallyExportKind.salesVouchers,
              groupValue: _kind,
              title: const Text('Sales Vouchers'),
              onChanged: (val) => setState(() => _kind = val ?? _kind),
            ),
            const SizedBox(height: 16),
            if (_kind == _TallyExportKind.salesVouchers) ...[
              Text('Date range', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.date_range),
                title: Text('${_formatDate(_startDate)}  to  ${_formatDate(_endDate)}'),
                trailing: TextButton(
                  onPressed: _pickDateRange,
                  child: const Text('Change'),
                ),
              ),
              const SizedBox(height: 16),
            ],
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: _isExporting
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton.icon(
                      onPressed: _export,
                      icon: const Icon(Icons.file_upload),
                      label: const Text('Export'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
