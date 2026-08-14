import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_scaffold.dart';
import '../../../models/customer_model.dart';
import '../../../models/product_model.dart';
import '../../../repositories/customer_repository.dart';
import '../../../repositories/product_repository.dart';
import '../../../services/tally_xml_service.dart';

/// Lets a manager pick a Tally masters-export XML file, previews whatever
/// Stock Items / Ledgers it contains, and imports either or both into the
/// local product/customer tables.
class ImportTallyScreen extends ConsumerStatefulWidget {
  const ImportTallyScreen({super.key});

  @override
  ConsumerState<ImportTallyScreen> createState() => _ImportTallyScreenState();
}

class _ImportTallyScreenState extends ConsumerState<ImportTallyScreen> {
  bool _isBusy = false;
  String? _pickedFileName;
  List<Product> _stockItems = [];
  List<Customer> _ledgers = [];

  Future<void> _pickFile() async {
    setState(() => _isBusy = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xml'],
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.single;
      String? content;
      if (file.bytes != null) {
        content = utf8.decode(file.bytes!);
      } else if (file.path != null) {
        content = await File(file.path!).readAsString();
      }

      if (content == null) {
        throw Exception('Could not read the selected file');
      }

      final stockItems = TallyXmlService.parseStockItems(content);
      final ledgers = TallyXmlService.parseLedgers(content);

      setState(() {
        _pickedFileName = file.name;
        _stockItems = stockItems;
        _ledgers = ledgers;
      });

      if (!mounted) return;
      if (stockItems.isEmpty && ledgers.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No Stock Items or Ledgers found in this file')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Found ${stockItems.length} stock item(s) and ${ledgers.length} ledger(s)',
            ),
          ),
        );
      }
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

  Future<void> _importStockItems() async {
    setState(() => _isBusy = true);
    try {
      await ref.read(productRepositoryProvider).bulkInsert(_stockItems);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Imported ${_stockItems.length} item(s) successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        setState(() => _stockItems = []);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error importing items: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _importLedgers() async {
    setState(() => _isBusy = true);
    try {
      await ref.read(customerRepositoryProvider).bulkInsert(_ledgers);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Imported ${_ledgers.length} part(y/ies) successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        setState(() => _ledgers = []);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error importing parties: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Import From Tally',
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton.icon(
              onPressed: _isBusy ? null : _pickFile,
              icon: const Icon(Icons.file_open),
              label: const Text('Choose Tally XML File'),
            ),
            if (_pickedFileName != null) ...[
              const SizedBox(height: 8),
              Text('Selected: $_pickedFileName', style: Theme.of(context).textTheme.bodySmall),
            ],
            if (_isBusy) ...[
              const SizedBox(height: 16),
              const Center(child: CircularProgressIndicator()),
            ],
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                children: [
                  if (_stockItems.isNotEmpty) _buildStockItemsSection(),
                  if (_ledgers.isNotEmpty) _buildLedgersSection(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStockItemsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Stock Items Found: ${_stockItems.length}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 200,
              child: ListView.builder(
                itemCount: _stockItems.length,
                itemBuilder: (context, index) {
                  final product = _stockItems[index];
                  return ListTile(
                    dense: true,
                    title: Text(product.name),
                    subtitle: Text(
                      'Barcode: ${product.barcode} | Unit: ${product.unit} | '
                      'Qty: ${product.stockQuantity} | MRP: ${product.mrp}',
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _isBusy ? null : _importStockItems,
              child: const Text('Import These Items'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLedgersSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Ledgers Found: ${_ledgers.length}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 200,
              child: ListView.builder(
                itemCount: _ledgers.length,
                itemBuilder: (context, index) {
                  final customer = _ledgers[index];
                  return ListTile(
                    dense: true,
                    title: Text(customer.name),
                    subtitle: Text('Phone: ${customer.phone} | Credit Limit: ${customer.creditLimit}'),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _isBusy ? null : _importLedgers,
              child: const Text('Import These Parties'),
            ),
          ],
        ),
      ),
    );
  }
}
