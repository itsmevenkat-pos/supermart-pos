import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../repositories/store_repository.dart';
import '../../../services/backup_service.dart';
import '../../../services/google_drive_backup_service.dart';
import '../../../services/onedrive_backup_service.dart';
import '../../../services/supabase_sync_service.dart';
import '../../../services/ollama_service.dart';
import '../../../services/thermal_print_service.dart';
import '../../../services/windows_printer.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late Future<String> _invoicePrefixFuture;
  late Future<double> _returnThresholdFuture;
  late Future<double> _maxDiscountPercentFuture;
  late Future<double> _loyaltyValueFuture;
  late Future<double> _bonusThresholdFuture;
  late Future<Map<String, double>> _tierThresholdsFuture;
  late Future<({String prefix, String valueType})> _weighingConfigFuture;
  late Future<({String type, String? target, int? port, int charsPerLine})> _printerConfigFuture;
  late Future<({bool enabled, String baseUrl, String model})> _ollamaConfigFuture;

  @override
  void initState() {
    super.initState();
    _invoicePrefixFuture = StoreRepository().getInvoicePrefix();
    _returnThresholdFuture = StoreRepository().getReturnThreshold();
    _maxDiscountPercentFuture = StoreRepository().getMaxDiscountPercent();
    _loyaltyValueFuture = StoreRepository().getLoyaltyValuePerPoint();
    _bonusThresholdFuture = StoreRepository().getBonusPointsThreshold();
    _tierThresholdsFuture = StoreRepository().getTierThresholds();
    _weighingConfigFuture = StoreRepository().getWeighingBarcodeConfig();
    _printerConfigFuture = StoreRepository().getPrinterConfig();
    _ollamaConfigFuture = StoreRepository().getOllamaConfig();
  }

  Future<void> _editInvoicePrefix(String current) async {
    final controller = TextEditingController(text: current);
    final newPrefix = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Invoice Prefix'),
        content: TextField(
          controller: controller,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            hintText: 'e.g. SM',
            helperText: 'Used in bill numbers, e.g. SM/25-26/00001',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newPrefix == null || newPrefix.isEmpty || newPrefix == current) return;
    await StoreRepository().updateInvoicePrefix(newPrefix);
    setState(() => _invoicePrefixFuture = StoreRepository().getInvoicePrefix());
  }

  Future<void> _editReturnThreshold(double current) async {
    final controller = TextEditingController(text: current.toStringAsFixed(0));
    final newValue = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Return Approval Threshold'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            hintText: 'e.g. 500',
            helperText: 'Returns at or under this amount post without manager approval. '
                'Returns with no originating sale always need approval, regardless of amount.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newValue == null || newValue.isEmpty) return;
    final parsed = double.tryParse(newValue);
    if (parsed == null || parsed < 0) return;
    await StoreRepository().updateReturnThreshold(parsed);
    setState(() => _returnThresholdFuture = StoreRepository().getReturnThreshold());
  }

  Future<void> _editMaxDiscountPercent(double current) async {
    final controller = TextEditingController(text: current.toStringAsFixed(0));
    final newValue = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Max Discount Without Approval'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            hintText: 'e.g. 10',
            helperText: 'Cashiers can apply a discount up to this percent of the bill subtotal on their own. '
                'A larger discount still needs manager/admin approval.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newValue == null || newValue.isEmpty) return;
    final parsed = double.tryParse(newValue);
    if (parsed == null || parsed < 0) return;
    await StoreRepository().updateMaxDiscountPercent(parsed);
    setState(() => _maxDiscountPercentFuture = StoreRepository().getMaxDiscountPercent());
  }

  Future<void> _editLoyaltyValue(double current) async {
    final controller = TextEditingController(text: current.toStringAsFixed(2));
    final newValue = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Loyalty Point Value'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            hintText: 'e.g. 0.50',
            helperText: '₹ value of one point when a customer redeems it at checkout.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newValue == null || newValue.isEmpty) return;
    final parsed = double.tryParse(newValue);
    if (parsed == null || parsed < 0) return;
    await StoreRepository().updateLoyaltyValuePerPoint(parsed);
    setState(() => _loyaltyValueFuture = StoreRepository().getLoyaltyValuePerPoint());
  }

  Future<void> _editBonusThreshold(double current) async {
    final controller = TextEditingController(text: current.toStringAsFixed(0));
    final newValue = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Points Earn Rate'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            hintText: 'e.g. 300',
            helperText: '₹ a customer must spend on a bill to earn 1 loyalty point '
                '(before their membership tier multiplier). This is the earn side — '
                '"Loyalty Point Value" below is what a point is worth when redeemed.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newValue == null || newValue.isEmpty) return;
    final parsed = double.tryParse(newValue);
    if (parsed == null || parsed <= 0) return;
    await StoreRepository().updateBonusPointsThreshold(parsed);
    setState(() => _bonusThresholdFuture = StoreRepository().getBonusPointsThreshold());
  }

  Future<void> _editTierThresholds(Map<String, double> current) async {
    final bronzeController = TextEditingController(text: current['bronze']!.toStringAsFixed(0));
    final silverController = TextEditingController(text: current['silver']!.toStringAsFixed(0));
    final goldController = TextEditingController(text: current['gold']!.toStringAsFixed(0));
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Membership Tier Thresholds'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Minimum lifetime spend to reach each tier. Higher tiers earn loyalty points faster '
              '(Bronze 1.2x, Silver 1.5x, Gold 2x).',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: bronzeController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Bronze (₹)'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: silverController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Silver (₹)'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: goldController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Gold (₹)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    if (saved != true) return;
    final bronze = double.tryParse(bronzeController.text) ?? current['bronze']!;
    final silver = double.tryParse(silverController.text) ?? current['silver']!;
    final gold = double.tryParse(goldController.text) ?? current['gold']!;
    await StoreRepository().updateTierThresholds(bronze: bronze, silver: silver, gold: gold);
    setState(() => _tierThresholdsFuture = StoreRepository().getTierThresholds());
  }

  Future<void> _editWeighingConfig(({String prefix, String valueType}) current) async {
    final prefixController = TextEditingController(text: current.prefix);
    var valueType = current.valueType;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Weighing Scale Barcodes'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'For products sold by weight, priced by the shop\'s weighing scale rather than typed '
                'in manually. Leave the prefix blank to leave this off — scanning a normal product '
                'barcode is unaffected either way.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: prefixController,
                keyboardType: TextInputType.number,
                maxLength: 2,
                decoration: const InputDecoration(
                  labelText: 'Barcode Prefix',
                  hintText: 'e.g. 21',
                  helperText: 'The first 2 digits your scale prints — check its manual/settings',
                ),
              ),
              DropdownButtonFormField<String>(
                initialValue: valueType,
                decoration: const InputDecoration(labelText: 'Embedded Value'),
                items: const [
                  DropdownMenuItem(value: 'weight_grams', child: Text('Weight (grams)')),
                  DropdownMenuItem(value: 'price_paise', child: Text('Total price (paise)')),
                ],
                onChanged: (value) => setDialogState(() => valueType = value ?? 'weight_grams'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (saved != true) return;
    await StoreRepository().updateWeighingBarcodeConfig(
      prefix: prefixController.text.trim(),
      valueType: valueType,
    );
    setState(() => _weighingConfigFuture = StoreRepository().getWeighingBarcodeConfig());
  }

  Future<void> _editPrinterConfig(({String type, String? target, int? port, int charsPerLine}) current) async {
    var type = current.type;
    final targetController = TextEditingController(text: current.target ?? '');
    final portController = TextEditingController(text: current.port?.toString() ?? '9100');
    var charsPerLine = current.charsPerLine;
    final installedPrinters = WindowsPrinter.listPrinterNames();

    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Thermal Printer'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Real ESC/POS receipt printing, bypassing the PDF/print-dialog fallback. '
                  'Untested against real hardware — verify a test print looks right on your '
                  'printer before relying on it.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: 'Connection'),
                  items: const [
                    DropdownMenuItem(value: 'none', child: Text('None (use PDF/print dialog)')),
                    DropdownMenuItem(value: 'network', child: Text('Network (WiFi/Ethernet)')),
                    DropdownMenuItem(value: 'windows', child: Text('USB (Windows printer)')),
                  ],
                  onChanged: (value) => setDialogState(() => type = value ?? 'none'),
                ),
                if (type == 'network') ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: targetController,
                    decoration: const InputDecoration(labelText: 'Printer IP Address', hintText: 'e.g. 192.168.1.50'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: portController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Port', hintText: '9100 (standard raw print port)'),
                  ),
                ],
                if (type == 'windows') ...[
                  const SizedBox(height: 8),
                  if (installedPrinters.isEmpty)
                    TextField(
                      controller: targetController,
                      decoration: const InputDecoration(
                        labelText: 'Printer Name',
                        helperText: 'No installed printers detected — type the exact name from Windows Settings',
                      ),
                    )
                  else
                    DropdownButtonFormField<String>(
                      initialValue: installedPrinters.contains(targetController.text) ? targetController.text : null,
                      decoration: const InputDecoration(labelText: 'Printer'),
                      items: installedPrinters.map((name) => DropdownMenuItem(value: name, child: Text(name))).toList(),
                      onChanged: (value) => targetController.text = value ?? '',
                    ),
                ],
                if (type != 'none') ...[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    initialValue: charsPerLine,
                    decoration: const InputDecoration(labelText: 'Paper Width'),
                    items: const [
                      DropdownMenuItem(value: 32, child: Text('58mm (32 characters)')),
                      DropdownMenuItem(value: 48, child: Text('80mm (48 characters)')),
                    ],
                    onChanged: (value) => setDialogState(() => charsPerLine = value ?? 32),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            if (type != 'none')
              TextButton(
                onPressed: () async {
                  final bytes = ThermalPrintService.buildEscPosReceipt(
                    storeName: 'SUPERMART POS',
                    invoiceLabel: 'TEST',
                    date: DateTime.now(),
                    customerName: 'Test Print',
                    items: const [
                      {'name': 'Test Item', 'qty': 1, 'price': 0.0},
                    ],
                    subtotal: 0,
                    total: 0,
                    footerMessage: 'Test print OK',
                    charsPerLine: charsPerLine,
                  );
                  final ok = await ThermalPrintService.printEscPos(
                    printerType: type,
                    printerTarget: targetController.text.trim(),
                    printerPort: int.tryParse(portController.text.trim()),
                    receiptBytes: bytes,
                  );
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(ok ? 'Test print sent' : 'Test print failed — check connection details'),
                      backgroundColor: ok ? Colors.green : Colors.red,
                    ),
                  );
                },
                child: const Text('Test Print'),
              ),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (saved != true) return;
    await StoreRepository().updatePrinterConfig(
      type: type,
      target: targetController.text.trim().isEmpty ? null : targetController.text.trim(),
      port: int.tryParse(portController.text.trim()),
      charsPerLine: charsPerLine,
    );
    setState(() => _printerConfigFuture = StoreRepository().getPrinterConfig());
  }

  Future<void> _editOllamaConfig(({bool enabled, String baseUrl, String model}) current) async {
    var enabled = current.enabled;
    final baseUrlController = TextEditingController(text: current.baseUrl);
    final modelController = TextEditingController(text: current.model);
    String? testResult;

    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('AI Analysis (Ollama)'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Optional local AI summary on the AI Analysis report. Runs entirely on this '
                  'PC via Ollama (ollama.com) — nothing is sent anywhere else. The reports work '
                  'fine without this; it just adds a plain-English blurb on top.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Enable AI summary'),
                  value: enabled,
                  onChanged: (value) => setDialogState(() {
                    enabled = value;
                    testResult = null;
                  }),
                ),
                if (enabled) ...[
                  TextField(
                    controller: baseUrlController,
                    decoration: const InputDecoration(
                      labelText: 'Ollama Server URL',
                      hintText: 'http://localhost:11434',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: modelController,
                    decoration: const InputDecoration(
                      labelText: 'Model',
                      hintText: 'e.g. llama3.2',
                    ),
                  ),
                  if (testResult != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      testResult!,
                      style: TextStyle(
                        color: testResult == 'Connected' ? Colors.green : Colors.red,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            if (enabled)
              TextButton(
                onPressed: () async {
                  final reachable = await OllamaService().isReachable(baseUrlController.text.trim());
                  setDialogState(() => testResult = reachable ? 'Connected' : 'Could not connect');
                },
                child: const Text('Test Connection'),
              ),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (saved != true) return;
    await StoreRepository().updateOllamaConfig(
      enabled: enabled,
      baseUrl: baseUrlController.text.trim().isEmpty ? 'http://localhost:11434' : baseUrlController.text.trim(),
      model: modelController.text.trim().isEmpty ? 'llama3.2' : modelController.text.trim(),
    );
    setState(() => _ollamaConfigFuture = StoreRepository().getOllamaConfig());
  }

  Future<void> _backupToLocalFolder() async {
    final destinationDir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choose a backup destination (local folder or USB drive)',
    );
    if (destinationDir == null || !mounted) return;

    try {
      final path = await BackupService().backupToLocalFolder(destinationDir);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Backup saved to $path'), backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Backup failed: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _restoreFromFile() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Choose a SuperMart POS backup file',
      type: FileType.custom,
      allowedExtensions: ['db', 'bak'],
    );
    final path = result?.files.single.path;
    if (path == null || !mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Restore Database?'),
        content: const Text(
          'This replaces ALL current data (products, sales, customers, everything) with '
          "what's in the backup file. A safety copy of today's data is made first, but "
          'anything entered after the backup was taken will be lost.\n\n'
          'The app must be closed and reopened afterward. Continue?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await BackupService().restoreBackup(path);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text('Restore Complete'),
          content: const Text('Close the app now and reopen it to load the restored data.'),
          actions: [
            ElevatedButton(
              onPressed: () => exit(0),
              child: const Text('Exit App'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Restore failed: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _syncNow() async {
    final service = SupabaseSyncService();
    if (!service.isConfigured) {
      showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Multi-Store Sync Not Set Up'),
          content: const Text(
            'Sync is designed and ready in the code, but needs a Supabase project connected '
            'before it can run — see SUPABASE_SYNC_DESIGN.md for setup steps. This is a one-time '
            'developer setup, not something to fix from inside the app.',
          ),
          actions: [
            ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
          ],
        ),
      );
      return;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Expanded(child: Text('Syncing…')),
          ],
        ),
      ),
    );
    try {
      final pushResult = await service.pushPending();
      final pullResult = await service.pullMasterData();
      if (!mounted) return;
      Navigator.pop(context);
      final updated = pullResult.updatedPerTable.values.fold<int>(0, (a, b) => a + b);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Sync complete: pushed ${pushResult.pushed}${pushResult.failed > 0 ? ' (${pushResult.failed} failed)' : ''}, '
            'pulled $updated update${updated == 1 ? '' : 's'}.',
          ),
          backgroundColor: Colors.green,
        ),
      );
      setState(() {}); // refresh the status tile
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sync failed: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _backupToCloud({
    required Future<String> Function() run,
    required bool isConfigured,
    required String serviceName,
  }) async {
    if (!isConfigured) {
      showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('$serviceName Not Set Up'),
          content: Text(
            "$serviceName backup needs a one-time developer setup (an OAuth app registration) "
            "before it can sign you in. It's not configured on this install yet — this is not "
            'something you need to fix from inside the app.',
          ),
          actions: [
            ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
          ],
        ),
      );
      return;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Expanded(child: Text('Waiting for sign-in in your browser…')),
          ],
        ),
      ),
    );

    try {
      final result = await run();
      if (!mounted) return;
      Navigator.pop(context); // close progress dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result), backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // close progress dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$serviceName backup failed: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Settings',
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.storefront),
            title: const Text('Business Profile'),
            subtitle: const Text('Name, GSTIN, contact details, logo & signature'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/business-profile'),
          ),
          const Divider(),
          FutureBuilder<String>(
            future: _invoicePrefixFuture,
            builder: (context, snapshot) {
              final prefix = snapshot.data ?? '...';
              return ListTile(
                leading: const Icon(Icons.receipt_long),
                title: const Text('Invoice Prefix'),
                subtitle: Text('$prefix  →  e.g. $prefix/25-26/00001'),
                trailing: const Icon(Icons.edit, size: 20),
                onTap: snapshot.hasData ? () => _editInvoicePrefix(snapshot.data!) : null,
              );
            },
          ),
          const Divider(),
          FutureBuilder<double>(
            future: _returnThresholdFuture,
            builder: (context, snapshot) {
              final threshold = snapshot.data;
              return ListTile(
                leading: const Icon(Icons.assignment_return),
                title: const Text('Return Approval Threshold'),
                subtitle: Text(threshold == null ? 'Loading…' : '₹${threshold.toStringAsFixed(0)}'),
                trailing: const Icon(Icons.edit, size: 20),
                onTap: threshold != null ? () => _editReturnThreshold(threshold) : null,
              );
            },
          ),
          const Divider(),
          FutureBuilder<double>(
            future: _maxDiscountPercentFuture,
            builder: (context, snapshot) {
              final percent = snapshot.data;
              return ListTile(
                leading: const Icon(Icons.percent),
                title: const Text('Max Discount Without Approval'),
                subtitle: Text(percent == null ? 'Loading…' : '${percent.toStringAsFixed(0)}% of bill subtotal'),
                trailing: const Icon(Icons.edit, size: 20),
                onTap: percent != null ? () => _editMaxDiscountPercent(percent) : null,
              );
            },
          ),
          const Divider(),
          FutureBuilder<double>(
            future: _bonusThresholdFuture,
            builder: (context, snapshot) {
              final threshold = snapshot.data;
              return ListTile(
                leading: const Icon(Icons.card_giftcard),
                title: const Text('Points Earn Rate'),
                subtitle: Text(
                  threshold == null
                      ? 'Loading…'
                      : '₹${threshold.toStringAsFixed(0)} spent = 1 point earned (before tier multiplier)',
                ),
                trailing: const Icon(Icons.edit, size: 20),
                onTap: threshold != null ? () => _editBonusThreshold(threshold) : null,
              );
            },
          ),
          const Divider(),
          FutureBuilder<double>(
            future: _loyaltyValueFuture,
            builder: (context, snapshot) {
              final value = snapshot.data;
              return ListTile(
                leading: const Icon(Icons.redeem),
                title: const Text('Loyalty Point Value'),
                subtitle: Text(value == null ? 'Loading…' : '₹${value.toStringAsFixed(2)} per point when redeemed'),
                trailing: const Icon(Icons.edit, size: 20),
                onTap: value != null ? () => _editLoyaltyValue(value) : null,
              );
            },
          ),
          const Divider(),
          FutureBuilder<Map<String, double>>(
            future: _tierThresholdsFuture,
            builder: (context, snapshot) {
              final tiers = snapshot.data;
              return ListTile(
                leading: const Icon(Icons.military_tech_outlined),
                title: const Text('Membership Tier Thresholds'),
                subtitle: Text(
                  tiers == null
                      ? 'Loading…'
                      : 'Bronze ₹${tiers['bronze']!.toStringAsFixed(0)} · '
                          'Silver ₹${tiers['silver']!.toStringAsFixed(0)} · '
                          'Gold ₹${tiers['gold']!.toStringAsFixed(0)}',
                ),
                trailing: const Icon(Icons.edit, size: 20),
                onTap: tiers != null ? () => _editTierThresholds(tiers) : null,
              );
            },
          ),
          const Divider(),
          FutureBuilder<({String prefix, String valueType})>(
            future: _weighingConfigFuture,
            builder: (context, snapshot) {
              final config = snapshot.data;
              final subtitle = config == null
                  ? 'Loading…'
                  : config.prefix.isEmpty
                      ? 'Off — scanning a weighing-scale barcode looks it up as a normal barcode'
                      : 'Prefix "${config.prefix}", embedded ${config.valueType == 'price_paise' ? 'price' : 'weight'}';
              return ListTile(
                leading: const Icon(Icons.scale),
                title: const Text('Weighing Scale Barcodes'),
                subtitle: Text(subtitle),
                trailing: const Icon(Icons.edit, size: 20),
                onTap: config != null ? () => _editWeighingConfig(config) : null,
              );
            },
          ),
          const Divider(),
          FutureBuilder<({String type, String? target, int? port, int charsPerLine})>(
            future: _printerConfigFuture,
            builder: (context, snapshot) {
              final config = snapshot.data;
              final subtitle = config == null
                  ? 'Loading…'
                  : config.type == 'none'
                      ? 'Off — receipts print via PDF/OS print dialog'
                      : config.type == 'network'
                          ? 'Network — ${config.target ?? '(not set)'}:${config.port ?? 9100}'
                          : 'USB — ${config.target ?? '(not set)'}';
              return ListTile(
                leading: const Icon(Icons.receipt),
                title: const Text('Thermal Printer'),
                subtitle: Text(subtitle),
                trailing: const Icon(Icons.edit, size: 20),
                onTap: config != null ? () => _editPrinterConfig(config) : null,
              );
            },
          ),
          const Divider(),
          FutureBuilder<({bool enabled, String baseUrl, String model})>(
            future: _ollamaConfigFuture,
            builder: (context, snapshot) {
              final config = snapshot.data;
              final subtitle = config == null
                  ? 'Loading…'
                  : config.enabled
                      ? 'On — ${config.model} at ${config.baseUrl}'
                      : 'Off — AI Analysis shows data-only reports';
              return ListTile(
                leading: const Icon(Icons.smart_toy_outlined),
                title: const Text('AI Analysis (Ollama)'),
                subtitle: Text(subtitle),
                trailing: const Icon(Icons.edit, size: 20),
                onTap: config != null ? () => _editOllamaConfig(config) : null,
              );
            },
          ),
          const Divider(),
          const ListTile(
            leading: Icon(Icons.currency_rupee),
            title: Text('Currency'),
            subtitle: Text('INR (₹)'),
          ),
          const Divider(),
          const ListTile(
            leading: Icon(Icons.warning),
            title: Text('MRP Warning Multiplier'),
            subtitle: Text(
              '2x — for reference only right now, not yet enforced anywhere in the app. '
              'Intended to flag a selling price set at more than 2x an item\'s MRP as a likely pricing mistake.',
            ),
            isThreeLine: true,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.backup),
            title: const Text('Backup Database'),
            subtitle: const Text('Save a copy to a local folder or USB drive'),
            onTap: _backupToLocalFolder,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.restore),
            title: const Text('Restore Database'),
            subtitle: const Text('Replace current data from a backup file'),
            onTap: _restoreFromFile,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.cloud_upload),
            title: const Text('Backup to Google Drive'),
            subtitle: const Text('Sign in and upload a copy off-site'),
            onTap: () => _backupToCloud(
              run: () => GoogleDriveBackupService().backupToGoogleDrive(),
              isConfigured: GoogleDriveBackupService().isConfigured,
              serviceName: 'Google Drive',
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.cloud_upload),
            title: const Text('Backup to OneDrive'),
            subtitle: const Text('Sign in and upload a copy off-site'),
            onTap: () => _backupToCloud(
              run: () => OneDriveBackupService().backupToOneDrive(),
              isConfigured: OneDriveBackupService().isConfigured,
              serviceName: 'OneDrive',
            ),
          ),
          const Divider(),
          FutureBuilder<SyncStatus>(
            future: SupabaseSyncService().getStatus(),
            builder: (context, snapshot) {
              final status = snapshot.data;
              final subtitle = status == null
                  ? 'Loading…'
                  : !status.isConfigured
                      ? 'Not set up yet — see SUPABASE_SYNC_DESIGN.md'
                      : '${status.pendingCount} pending'
                          '${status.failedCount > 0 ? ', ${status.failedCount} failed' : ''}'
                          ' · last synced: ${status.lastPulledAt?.toString().split('.').first ?? 'never'}';
              return ListTile(
                leading: const Icon(Icons.sync),
                title: const Text('Multi-Store Sync'),
                subtitle: Text(subtitle),
                trailing: TextButton(onPressed: _syncNow, child: const Text('Sync Now')),
              );
            },
          ),
        ],
      ),
    );
  }
}
