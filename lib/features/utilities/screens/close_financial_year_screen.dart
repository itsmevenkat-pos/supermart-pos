import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/financial_year.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../providers/auth_provider.dart';
import '../../../repositories/user_repository.dart';
import '../../../services/financial_year_close_service.dart';

/// Admin-only, irreversible: locks a financial year's books. There is no
/// "reopen" anywhere in this app once a year shows up in
/// `financial_year_closures`, so every affordance here is built around
/// making that permanence obvious before it happens — current status up
/// front, a past-closures audit trail, and a type-to-confirm dialog gating
/// the actual close.
class CloseFinancialYearScreen extends ConsumerStatefulWidget {
  const CloseFinancialYearScreen({super.key});

  @override
  ConsumerState<CloseFinancialYearScreen> createState() => _CloseFinancialYearScreenState();
}

class _CloseFinancialYearScreenState extends ConsumerState<CloseFinancialYearScreen> {
  final _service = FinancialYearCloseService();
  final _userRepo = UserRepository();

  late final String _currentFy = financialYearLabel(DateTime.now());

  bool _loading = true;
  bool _closing = false;
  bool _currentFyClosed = false;
  List<_ClosureRow> _closedYears = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rawRows = await _service.getClosedFinancialYears();
      final closedNow = await _service.isFinancialYearClosed(_currentFy);

      final rows = <_ClosureRow>[];
      for (final row in rawRows) {
        final userId = row['closed_by_user_id'] as String?;
        String closedBy = 'Unknown';
        if (userId != null) {
          final user = await _userRepo.getById(userId);
          closedBy = user?.name ?? 'Unknown';
        }
        rows.add(_ClosureRow(
          financialYear: row['financial_year'] as String,
          closedAt: DateTime.fromMillisecondsSinceEpoch((row['closed_at'] as int) * 1000),
          closedBy: closedBy,
          notes: row['notes'] as String?,
        ));
      }

      if (!mounted) return;
      setState(() {
        _closedYears = rows;
        _currentFyClosed = closedNow;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load closure history: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _confirmAndClose() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ConfirmCloseDialog(financialYear: _currentFy),
    );
    if (confirmed != true) return;
    if (!mounted) return;

    final userId = ref.read(authProvider).user?.id;
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No logged-in user found.'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _closing = true);
    try {
      await _service.closeFinancialYear(financialYear: _currentFy, userId: userId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Financial year $_currentFy has been closed.'), backgroundColor: Colors.green),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to close financial year: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _closing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Close Financial Year',
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildCurrentFyCard(),
                  const SizedBox(height: 24),
                  const Text(
                    'Previously Closed Financial Years',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  _buildClosedYearsList(),
                ],
              ),
            ),
    );
  }

  Widget _buildCurrentFyCard() {
    return Card(
      elevation: 0,
      color: Colors.red.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.red.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.event_busy, color: Colors.red.shade700),
                const SizedBox(width: 8),
                const Text('Current Financial Year', style: TextStyle(fontSize: 13, color: Colors.black54)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _currentFy,
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded, size: 18, color: Colors.amber.shade900),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Closing a financial year is a permanent, admin-only action and cannot be undone.',
                      style: TextStyle(fontSize: 12.5, color: Colors.amber.shade900),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_currentFyClosed)
              Row(
                children: [
                  Icon(Icons.lock, color: Colors.grey.shade700, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'This financial year is already closed.',
                    style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w600),
                  ),
                ],
              )
            else
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _closing ? null : _confirmAndClose,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: _closing
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.lock),
                  label: Text(_closing ? 'Closing...' : 'Close Financial Year'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildClosedYearsList() {
    if (_closedYears.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text('No financial years have been closed yet.', style: TextStyle(color: Colors.grey.shade600)),
      );
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _closedYears.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, index) {
          final row = _closedYears[index];
          return ListTile(
            leading: const Icon(Icons.lock_outline),
            title: Text(row.financialYear, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
              'Closed by ${row.closedBy} on ${DateFormat('dd MMM yyyy, hh:mm a').format(row.closedAt)}'
              '${row.notes != null && row.notes!.isNotEmpty ? '\n${row.notes}' : ''}',
            ),
            isThreeLine: row.notes != null && row.notes!.isNotEmpty,
          );
        },
      ),
    );
  }
}

class _ClosureRow {
  final String financialYear;
  final DateTime closedAt;
  final String closedBy;
  final String? notes;

  _ClosureRow({
    required this.financialYear,
    required this.closedAt,
    required this.closedBy,
    this.notes,
  });
}

/// Type-to-confirm dialog: the confirm button stays disabled until the
/// admin types the exact FY label back, a deliberate friction point for an
/// action with no undo.
class _ConfirmCloseDialog extends StatefulWidget {
  final String financialYear;

  const _ConfirmCloseDialog({required this.financialYear});

  @override
  State<_ConfirmCloseDialog> createState() => _ConfirmCloseDialogState();
}

class _ConfirmCloseDialogState extends State<_ConfirmCloseDialog> {
  final _controller = TextEditingController();
  bool _matches = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final matches = _controller.text == widget.financialYear;
      if (matches != _matches) setState(() => _matches = matches);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.red.shade700),
          const SizedBox(width: 8),
          const Expanded(child: Text('Close Financial Year?')),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This will permanently lock the ${widget.financialYear} financial year. '
            'This action cannot be undone.',
          ),
          const SizedBox(height: 16),
          Text(
            'Type "${widget.financialYear}" to confirm:',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText: widget.financialYear,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _matches ? () => Navigator.pop(context, true) : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red.shade700,
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.grey.shade300,
          ),
          child: const Text('Close Financial Year'),
        ),
      ],
    );
  }
}
