import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/counter_service.dart';

/// Opens a cashier shift/session. Sales made after this now carry a real
/// session_id (see BillingService/billing_screen.dart), which is what
/// makes shift closing and cash reconciliation possible at all.
class CounterOpenScreen extends ConsumerStatefulWidget {
  const CounterOpenScreen({super.key});

  @override
  ConsumerState<CounterOpenScreen> createState() => _CounterOpenScreenState();
}

class _CounterOpenScreenState extends ConsumerState<CounterOpenScreen> {
  final _openingCashController = TextEditingController(text: '0');
  final _notesController = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _openingCashController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _openShift() async {
    final user = ref.read(authProvider).user;
    if (user == null) {
      setState(() => _error = 'No user logged in');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await CounterService().openShift(
        userId: user.id,
        openingCash: double.tryParse(_openingCashController.text.trim()) ?? 0,
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Shift opened'), backgroundColor: Colors.green),
      );
      Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _saving = false;
        // CounterService throws a plain message like "You already have an
        // open shift." — strip the "Exception: " prefix for display.
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Open Shift',
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.point_of_sale, size: 48, color: Colors.green),
                const SizedBox(height: 12),
                const Text(
                  'Start your shift by counting the cash in the drawer.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _openingCashController,
                  decoration: const InputDecoration(
                    labelText: 'Opening Cash (₹)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.currency_rupee),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  autofocus: true,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _notesController,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _saving ? null : _openShift,
                  icon: _saving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.lock_open),
                  label: const Text('Open Shift'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}