import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_scaffold.dart';
import '../../../services/data_verification_service.dart';

class VerifyDataScreen extends ConsumerStatefulWidget {
  const VerifyDataScreen({super.key});

  @override
  ConsumerState<VerifyDataScreen> createState() => _VerifyDataScreenState();
}

class _VerifyDataScreenState extends ConsumerState<VerifyDataScreen> {
  bool _isRunning = false;
  bool _isExporting = false;
  List<VerificationIssue>? _issues;

  Future<void> _runCheck() async {
    setState(() {
      _isRunning = true;
      _issues = null;
    });

    try {
      final issues = await DataVerificationService.runAllChecks();
      issues.sort((a, b) => _severityRank(b.severity).compareTo(_severityRank(a.severity)));

      if (!mounted) return;
      setState(() => _issues = issues);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Verification failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isRunning = false);
    }
  }

  int _severityRank(VerificationSeverity severity) {
    switch (severity) {
      case VerificationSeverity.error:
        return 2;
      case VerificationSeverity.warning:
        return 1;
      case VerificationSeverity.info:
        return 0;
    }
  }

  Future<void> _exportReport() async {
    final issues = _issues;
    if (issues == null) return;

    setState(() => _isExporting = true);
    try {
      final rows = <List<dynamic>>[
        ['severity', 'check', 'message'],
        for (final issue in issues)
          [issue.severity.name, issue.checkName, issue.message],
      ];

      final csvString = const ListToCsvConverter().convert(rows);
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'verify_report_$timestamp.csv';

      String? savedPath;
      try {
        savedPath = await FilePicker.platform.saveFile(
          dialogTitle: 'Save Verification Report',
          fileName: fileName,
          bytes: utf8.encode(csvString),
        );
      } catch (_) {
        savedPath = null;
      }

      if (savedPath == null) {
        // Fall back to picking a directory and writing the file ourselves —
        // some platforms/versions of file_picker's saveFile don't reliably
        // hand back a writable path.
        final dirPath = await FilePicker.platform.getDirectoryPath(
          dialogTitle: 'Choose a folder to save the report',
        );
        if (dirPath != null) {
          savedPath = '$dirPath${Platform.pathSeparator}$fileName';
          await File(savedPath).writeAsString(csvString);
        }
      } else if (!(await File(savedPath).exists())) {
        // saveFile returned a path but didn't write bytes on this platform.
        await File(savedPath).writeAsString(csvString);
      }

      if (!mounted) return;

      if (savedPath == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Export cancelled')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Report saved to $savedPath'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
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
      title: 'Verify My Data',
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isRunning) {
      return const Center(child: CircularProgressIndicator());
    }

    final issues = _issues;
    if (issues == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.fact_check, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text(
                'Run a check to look for data problems like duplicate\n'
                'barcodes, negative stock, or customers over their credit limit.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _runCheck,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Run Check'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (issues.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle, size: 64, color: Colors.green),
              const SizedBox(height: 16),
              const Text(
                'No issues found',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: _isRunning ? null : _runCheck,
                icon: const Icon(Icons.refresh),
                label: const Text('Run Check Again'),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${issues.length} issue${issues.length == 1 ? '' : 's'} found',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              TextButton.icon(
                onPressed: _isRunning ? null : _runCheck,
                icon: const Icon(Icons.refresh),
                label: const Text('Re-run'),
              ),
              const SizedBox(width: 8),
              _isExporting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : ElevatedButton.icon(
                      onPressed: _exportReport,
                      icon: const Icon(Icons.file_download),
                      label: const Text('Export Report'),
                    ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            itemCount: issues.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final issue = issues[index];
              return ListTile(
                leading: _severityIcon(issue.severity),
                title: Text(issue.checkName),
                subtitle: Text(issue.message),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _severityIcon(VerificationSeverity severity) {
    switch (severity) {
      case VerificationSeverity.error:
        return const Icon(Icons.error, color: Colors.red);
      case VerificationSeverity.warning:
        return const Icon(Icons.warning, color: Colors.orange);
      case VerificationSeverity.info:
        return const Icon(Icons.info, color: Colors.blue);
    }
  }
}
