import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/permissions/price_override_guard.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../models/customer_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/customer_provider.dart';
import '../../../repositories/customer_repository.dart';
import '../../../services/approval_service.dart';
import '../../../services/counter_service.dart';

/// Lets a cashier/manager record a payment against a customer's khata/credit
/// balance — or, if the amount is more than they owe (or they owe nothing),
/// an advance held for future purchases. Previously a "Coming Soon"
/// placeholder — there was no way to reduce a customer's outstanding_balance
/// anywhere in the app once a credit sale had added to it, and no way to
/// record an advance at all.
class ReceivePaymentScreen extends ConsumerStatefulWidget {
  const ReceivePaymentScreen({super.key});

  @override
  ConsumerState<ReceivePaymentScreen> createState() => _ReceivePaymentScreenState();
}

class _ReceivePaymentScreenState extends ConsumerState<ReceivePaymentScreen> {
  final _searchController = TextEditingController();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  Customer? _selectedCustomer;
  String _method = 'cash';
  bool _submitting = false;

  @override
  void dispose() {
    _searchController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _pickCustomer(Customer customer) {
    setState(() {
      _selectedCustomer = customer;
      _amountController.clear();
      _noteController.clear();
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedCustomer = null;
      _searchController.clear();
    });
    ref.invalidate(customerNotifierProvider);
  }

  Future<void> _submit() async {
    final customer = _selectedCustomer;
    if (customer == null || !_formKey.currentState!.validate()) return;

    final amount = double.parse(_amountController.text);
    final advancePortion = (amount - customer.outstandingBalance.clamp(0.0, double.infinity)).clamp(0.0, amount);

    final currentUser = ref.read(authProvider).user;
    if (currentUser == null) return;

    // Receiving a payment reduces a receivable, which is the same class of
    // action as a refund — so it is gated the same way returns are, on the
    // same configurable threshold, rather than being open to anyone who can
    // reach the screen. Without this a cashier could clear a customer's khata
    // and pocket the cash, with nothing to reconcile against.
    // The same limit the repository will enforce, read from the same place —
    // this decides whether to *show* the approval dialog, not whether the
    // payment is allowed. `receivePayment` re-checks and refuses regardless,
    // so a caller that skips this screen is bound by the rule too.
    final threshold = await ApprovalService().cashierDiscretionLimit();
    String? approvedByUserId;
    if (amount > threshold) {
      if (!mounted) return;
      final approver = await requireApprovalWithApprover(
        context,
        ref,
        actionLabel: 'Payment of ₹${amount.toStringAsFixed(2)} from ${customer.name}',
      );
      if (approver == null) return;
      approvedByUserId = approver.id;
    }

    setState(() => _submitting = true);
    try {
      // The open shift, so a cash receipt lands in the drawer this cashier
      // will have to reconcile at close (see MigrationV34).
      final session = await CounterService().getActiveSession(currentUser.id);

      await CustomerRepository().receivePayment(
        customerId: customer.id,
        amount: amount,
        method: _method,
        note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
        userId: currentUser.id,
        sessionId: session?.id,
        approvedByUserId: approvedByUserId,
      );
      if (!mounted) return;
      final message = advancePortion > 0
          ? advancePortion == amount
              ? '₹${amount.toStringAsFixed(2)} recorded as an advance for ${customer.name}'
              : '₹${amount.toStringAsFixed(2)} received from ${customer.name} '
                  '(₹${advancePortion.toStringAsFixed(2)} held as advance)'
          : '₹${amount.toStringAsFixed(2)} received from ${customer.name}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.green),
      );
      _clearSelection();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not record payment: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Receive Payment',
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _selectedCustomer == null ? _buildCustomerSearch() : _buildPaymentForm(_selectedCustomer!),
      ),
    );
  }

  Widget _buildCustomerSearch() {
    final customersAsync = ref.watch(customerNotifierProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _searchController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Search customer by name or phone',
            prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(),
          ),
          onChanged: (value) {
            if (value.trim().isNotEmpty) {
              ref.read(customerNotifierProvider.notifier).search(value.trim());
            } else {
              ref.invalidate(customerNotifierProvider);
            }
          },
        ),
        const SizedBox(height: 12),
        Expanded(
          child: customersAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Center(child: Text('Error: $err')),
            data: (customers) {
              // Default view surfaces anyone with a nonzero balance —
              // either a due to collect or an existing advance — since
              // this screen is also where a new advance gets recorded for
              // a customer who doesn't owe anything yet.
              final withBalance = customers.where((c) => c.outstandingBalance != 0).toList();
              final list = _searchController.text.trim().isEmpty ? withBalance : customers;
              if (list.isEmpty) {
                return Center(
                  child: Text(
                    _searchController.text.trim().isEmpty
                        ? 'No customers have a due or advance balance — search by name/phone to record a new advance'
                        : 'No matching customers',
                  ),
                );
              }
              return ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, index) {
                  final c = list[index];
                  return ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person)),
                    title: Text(c.name),
                    subtitle: Text(c.phone),
                    trailing: c.outstandingBalance > 0
                        ? Text(
                            '₹${c.outstandingBalance.toStringAsFixed(2)} due',
                            style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
                          )
                        : c.outstandingBalance < 0
                            ? Text(
                                '₹${(-c.outstandingBalance).toStringAsFixed(2)} advance',
                                style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
                              )
                            : const Text('No due', style: TextStyle(color: Colors.grey)),
                    onTap: () => _pickCustomer(c),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentForm(Customer customer) {
    final currentDue = customer.outstandingBalance.clamp(0.0, double.infinity);
    final currentAdvance = -customer.outstandingBalance.clamp(-double.infinity, 0.0);
    final enteredAmount = double.tryParse(_amountController.text) ?? 0;
    final paymentPortion = enteredAmount.clamp(0.0, currentDue);
    final advancePortion = (enteredAmount - currentDue).clamp(0.0, enteredAmount);

    return Form(
      key: _formKey,
      child: ListView(
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.person, size: 32),
              title: Text(customer.name, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(customer.phone),
              trailing: TextButton(onPressed: _clearSelection, child: const Text('Change')),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            color: (currentAdvance > 0 ? Colors.blue : Colors.orange).withValues(alpha: 0.1),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(currentAdvance > 0 ? 'Current Advance' : 'Current Due'),
                  Text(
                    '₹${(currentAdvance > 0 ? currentAdvance : currentDue).toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: currentAdvance > 0 ? Colors.blue : Colors.orange,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _amountController,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Amount Received',
              prefixText: '₹ ',
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              final amount = double.tryParse(value ?? '');
              if (amount == null || amount <= 0) return 'Enter a valid amount';
              return null;
            },
            onChanged: (_) => setState(() {}),
          ),
          if (advancePortion > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  border: Border.all(color: Colors.blue),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  paymentPortion > 0
                      ? '₹${paymentPortion.toStringAsFixed(2)} clears the current due; the remaining '
                          '₹${advancePortion.toStringAsFixed(2)} will be held as an advance for future purchases.'
                      : '₹${advancePortion.toStringAsFixed(2)} will be held as an advance for future purchases '
                          '— this customer has no current due.',
                  style: const TextStyle(color: Colors.blue, fontSize: 12),
                ),
              ),
            ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _method,
            decoration: const InputDecoration(labelText: 'Payment Method', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'cash', child: Text('Cash')),
              DropdownMenuItem(value: 'upi', child: Text('UPI')),
              DropdownMenuItem(value: 'card', child: Text('Card')),
            ],
            onChanged: (value) => setState(() => _method = value ?? 'cash'),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _noteController,
            decoration: const InputDecoration(
              labelText: 'Note (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check),
              label: Text(_submitting ? 'Recording...' : 'Record Payment'),
            ),
          ),
        ],
      ),
    );
  }
}
