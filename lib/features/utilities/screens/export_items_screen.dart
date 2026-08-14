import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_scaffold.dart';
import '../../../repositories/product_repository.dart';

class ExportItemsScreen extends ConsumerStatefulWidget {
  const ExportItemsScreen({super.key});

  @override
  ConsumerState<ExportItemsScreen> createState() => _ExportItemsScreenState();
}

class _ExportItemsScreenState extends ConsumerState<ExportItemsScreen> {
  bool _isExporting = false;

  Future<void> _export() async {
    setState(() => _isExporting = true);
    try {
      final products = await ref.read(productRepositoryProvider).getAll(activeOnly: false);

      final rows = <List<dynamic>>[
        [
          'name',
          'barcode',
          'category_id',
          'unit',
          'mrp',
          'retail_price',
          'wholesale_price',
          'cost_price',
          'tax_rate',
          'stock_quantity',
          'reorder_level',
        ],
        for (final product in products)
          [
            product.name,
            product.barcode,
            product.categoryId ?? '',
            product.unit,
            product.mrp,
            product.retailPrice,
            product.wholesalePrice,
            product.costPrice,
            product.taxRate,
            product.stockQuantity,
            product.reorderLevel,
          ],
      ];

      final csvString = const ListToCsvConverter().convert(rows);
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'items_export_$timestamp.csv';

      String? savedPath;
      try {
        savedPath = await FilePicker.platform.saveFile(
          dialogTitle: 'Save Items Export',
          fileName: fileName,
          bytes: utf8.encode(csvString),
        );
      } catch (_) {
        savedPath = await FilePicker.platform.saveFile(
          dialogTitle: 'Save Items Export',
          fileName: fileName,
        );
        if (savedPath != null) {
          await File(savedPath).writeAsString(csvString);
        }
      }

      if (!mounted) return;

      if (savedPath == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Export cancelled'),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Exported ${products.length} items to $savedPath'),
            backgroundColor: Colors.green,
          ),
        );
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
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Export Items',
      body: Center(
        child: _isExporting
            ? const CircularProgressIndicator()
            : ElevatedButton.icon(
                onPressed: _export,
                icon: const Icon(Icons.download),
                label: const Text('Export to CSV'),
              ),
      ),
    );
  }
}
