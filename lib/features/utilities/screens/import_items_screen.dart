import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_scaffold.dart';
import '../../../models/product_model.dart';
import '../../../repositories/category_repository.dart';
import '../../../repositories/product_repository.dart';

const _expectedColumns = [
  'Name',
  'Barcode',
  'Category',
  'Unit',
  'MRP',
  'Retail Price',
  'Wholesale Price',
  'Cost Price',
  'Tax Rate',
  'Stock Quantity',
  'Reorder Level',
];

const _sampleRows = [
  ['Aashirvaad Atta 5kg', '8901234567890', 'Grocery & Staples', 'Pcs', '285', '270', '255', '240', '5', '20', '5'],
  ['Amul Milk 500ml', '8901234567891', 'Dairy', 'Pcs', '30', '28', '26', '24', '0', '50', '10'],
];

class _ImportRow {
  _ImportRow({
    required this.name,
    required this.barcode,
    required this.categoryId,
    required this.unit,
    required this.mrp,
    required this.retailPrice,
    required this.wholesalePrice,
    required this.costPrice,
    required this.taxRate,
    required this.stockQuantity,
    required this.reorderLevel,
    this.error,
    this.warning,
  });

  final String name;
  final String barcode;
  final String? categoryId;
  final String unit;
  final double mrp;
  final double retailPrice;
  final double wholesalePrice;
  final double costPrice;
  final double taxRate;
  final double stockQuantity;
  final int reorderLevel;
  final String? error;
  final String? warning;

  bool get isOk => error == null;

  Product toProduct() {
    return Product.create(
      barcode: barcode,
      name: name,
      categoryId: categoryId,
      unit: unit,
      mrp: mrp,
      retailPrice: retailPrice,
      wholesalePrice: wholesalePrice,
      costPrice: costPrice,
      taxRate: taxRate,
      stockQuantity: stockQuantity,
      reorderLevel: reorderLevel,
    );
  }
}

class ImportItemsScreen extends ConsumerStatefulWidget {
  const ImportItemsScreen({super.key});

  @override
  ConsumerState<ImportItemsScreen> createState() => _ImportItemsScreenState();
}

class _ImportItemsScreenState extends ConsumerState<ImportItemsScreen> {
  bool _isBusy = false;
  String? _fileName;
  List<_ImportRow> _rows = [];

  int get _okCount => _rows.where((r) => r.isOk).length;
  int get _errorCount => _rows.length - _okCount;
  int get _warningCount => _rows.where((r) => r.isOk && r.warning != null).length;

  Future<void> _downloadSample() async {
    setState(() => _isBusy = true);
    try {
      final csvString = const ListToCsvConverter().convert([_expectedColumns, ..._sampleRows]);
      String? savedPath;
      try {
        savedPath = await FilePicker.platform.saveFile(
          dialogTitle: 'Save Sample Import CSV',
          fileName: 'import_items_sample.csv',
          bytes: utf8.encode(csvString),
        );
      } catch (_) {
        savedPath = await FilePicker.platform.saveFile(
          dialogTitle: 'Save Sample Import CSV',
          fileName: 'import_items_sample.csv',
        );
        if (savedPath != null) {
          await File(savedPath).writeAsString(csvString);
        }
      }
      if (!mounted) return;
      if (savedPath != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sample saved to $savedPath'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving sample: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _pickFile() async {
    setState(() => _isBusy = true);
    try {
      final categories = await CategoryRepository().getAll();
      final categoryNameToId = {for (final c in categories) c.name.trim().toLowerCase(): c.id};

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) {
        return;
      }

      final pickedFile = result.files.single;
      String csvString;
      if (pickedFile.bytes != null) {
        csvString = utf8.decode(pickedFile.bytes!);
      } else if (pickedFile.path != null) {
        csvString = await File(pickedFile.path!).readAsString();
      } else {
        throw Exception('Could not read the selected file');
      }

      final normalized = csvString.replaceAll('\r\n', '\n');
      final table = const CsvToListConverter().convert(normalized, eol: '\n');

      final rows = <_ImportRow>[];
      for (var i = 0; i < table.length; i++) {
        if (i == 0) continue; // header row
        final row = table[i];
        if (row.isEmpty || (row.length == 1 && row.first.toString().trim().isEmpty)) {
          continue; // blank line
        }
        rows.add(_parseRow(row, categoryNameToId));
      }

      setState(() {
        _fileName = pickedFile.name;
        _rows = rows;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error reading file: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  _ImportRow _parseRow(List<dynamic> row, Map<String, String> categoryNameToId) {
    if (row.length < 2) {
      return _ImportRow(
        name: '',
        barcode: '',
        categoryId: null,
        unit: 'Pcs',
        mrp: 0,
        retailPrice: 0,
        wholesalePrice: 0,
        costPrice: 0,
        taxRate: 0,
        stockQuantity: 0,
        reorderLevel: 5,
        error: 'Not enough columns',
      );
    }

    String col(int index) => index < row.length ? row[index].toString().trim() : '';

    final name = col(0);
    final barcode = col(1);
    final categoryText = col(2);
    final unitRaw = col(3);
    final unit = unitRaw.isEmpty ? 'Pcs' : unitRaw;
    final mrp = double.tryParse(col(4)) ?? 0;
    final retailPrice = double.tryParse(col(5)) ?? 0;
    final wholesalePrice = double.tryParse(col(6)) ?? 0;
    final costPrice = double.tryParse(col(7)) ?? 0;
    final taxRate = double.tryParse(col(8)) ?? 0;
    final stockQuantity = double.tryParse(col(9)) ?? 0;
    final reorderLevel = int.tryParse(col(10)) ?? 5;

    // Matched by name, not the internal category id — a file exported from
    // another tool has no way to know this app's internal ids. An unmatched
    // name doesn't block the row; it just imports as Uncategorized with a
    // warning, since guessing a wrong category would be worse than none.
    String? categoryId;
    String? warning;
    if (categoryText.isNotEmpty) {
      categoryId = categoryNameToId[categoryText.toLowerCase()];
      if (categoryId == null) {
        warning = 'Category "$categoryText" not found — will import as Uncategorized';
      }
    }

    String? error;
    if (name.isEmpty) {
      error = 'Missing name';
    } else if (barcode.isEmpty) {
      error = 'Missing barcode';
    }

    return _ImportRow(
      name: name,
      barcode: barcode,
      categoryId: categoryId,
      unit: unit,
      mrp: mrp,
      retailPrice: retailPrice,
      wholesalePrice: wholesalePrice,
      costPrice: costPrice,
      taxRate: taxRate,
      stockQuantity: stockQuantity,
      reorderLevel: reorderLevel,
      error: error,
      warning: warning,
    );
  }

  Future<void> _import() async {
    final okRows = _rows.where((r) => r.isOk).toList();
    if (okRows.isEmpty) return;

    setState(() => _isBusy = true);
    try {
      final products = okRows.map((r) => r.toProduct()).toList();
      await ref.read(productRepositoryProvider).bulkInsert(products);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Imported ${products.length} items'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Import Items',
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Expected CSV columns, in order:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text(_expectedColumns.join(' · '), style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 6),
                  const Text(
                    'Exporting from another tool: get your products into a spreadsheet with these '
                    'columns in this order (rename/reorder its headers to match), then save as CSV. '
                    'Category must match an existing category name here exactly — unmatched ones '
                    'still import, just as Uncategorized.',
                    style: TextStyle(fontSize: 12, color: Colors.black87),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isBusy ? null : _downloadSample,
                    icon: const Icon(Icons.download),
                    label: const Text('Download Sample CSV'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isBusy ? null : _pickFile,
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Choose CSV File'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_fileName != null)
              Text(
                '$_fileName — $_okCount OK'
                '${_warningCount > 0 ? ' ($_warningCount with warnings)' : ''}'
                ', $_errorCount error(s)',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            const SizedBox(height: 12),
            if (_rows.isNotEmpty)
              Expanded(
                child: SingleChildScrollView(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Name')),
                        DataColumn(label: Text('Barcode')),
                        DataColumn(label: Text('MRP')),
                        DataColumn(label: Text('Status')),
                      ],
                      rows: _rows
                          .map(
                            (r) => DataRow(
                              cells: [
                                DataCell(Text(r.name)),
                                DataCell(Text(r.barcode)),
                                DataCell(Text(r.mrp.toString())),
                                DataCell(
                                  Text(
                                    !r.isOk ? r.error! : (r.warning ?? 'OK'),
                                    style: TextStyle(
                                      color: !r.isOk
                                          ? Colors.red
                                          : r.warning != null
                                              ? Colors.orange.shade800
                                              : Colors.green,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: _isBusy
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton(
                      onPressed: _okCount > 0 ? _import : null,
                      child: Text('Import ($_okCount)'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
