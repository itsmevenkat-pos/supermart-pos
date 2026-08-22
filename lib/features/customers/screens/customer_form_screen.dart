import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../core/permissions/price_override_guard.dart';
import '../../../models/customer_model.dart';
import '../../../providers/customer_provider.dart';

class CustomerFormScreen extends ConsumerStatefulWidget {
  final Customer? customer;
  final Function(Customer)? onSaved;

  const CustomerFormScreen({super.key, this.customer, this.onSaved});

  @override
  ConsumerState<CustomerFormScreen> createState() => _CustomerFormScreenState();
}

class _CustomerFormScreenState extends ConsumerState<CustomerFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late final TextEditingController _addressController;
  late final TextEditingController _localityController;
  late final TextEditingController _creditLimitController;
  DateTime? _dateOfBirth;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.customer?.name ?? '');
    _phoneController = TextEditingController(text: widget.customer?.phone ?? '');
    _emailController = TextEditingController(text: widget.customer?.email ?? '');
    _addressController = TextEditingController(text: widget.customer?.address ?? '');
    _localityController = TextEditingController(text: widget.customer?.locality ?? '');
    _creditLimitController = TextEditingController(text: widget.customer?.creditLimit.toString() ?? '0');
    _dateOfBirth = widget.customer?.dateOfBirth != null
        ? DateTime.fromMillisecondsSinceEpoch(widget.customer!.dateOfBirth! * 1000)
        : null;
  }

  Future<void> _pickDateOfBirth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime(1990, 1, 1),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _dateOfBirth = picked);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _localityController.dispose();
    _creditLimitController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    // A credit limit is how much the shop is willing to be owed, so raising
    // one is a manager's call — otherwise a cashier could write themselves a
    // limit and immediately sell on credit against it. Creating or editing a
    // customer is left open, because adding a walk-in at the till is ordinary
    // cashier work; only the limit itself is gated, and only when it goes up.
    final previousLimit = widget.customer?.creditLimit ?? 0;
    final requestedLimit = double.tryParse(_creditLimitController.text) ?? 0;
    var effectiveLimit = requestedLimit;
    String? approvedByUserId;
    if (requestedLimit > previousLimit) {
      final approver = await requireApprovalWithApprover(
        context,
        ref,
        actionLabel: 'Credit limit for ${_nameController.text.trim()} '
            '→ ₹${requestedLimit.toStringAsFixed(2)}',
      );
      approvedByUserId = approver?.id;
      if (approver == null) {
        // Refused or cancelled: keep the old limit rather than abandoning the
        // rest of the edit, so a cashier's legitimate changes aren't lost.
        effectiveLimit = previousLimit;
        if (mounted) {
          _creditLimitController.text = previousLimit.toStringAsFixed(2);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Credit limit unchanged — manager approval required')),
          );
        }
      }
    }

    final customer = Customer(
      id: widget.customer?.id ?? const Uuid().v4(),
      storeId: 'store_default',
      phone: _phoneController.text.trim(),
      name: _nameController.text.trim(),
      email: _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
      address: _addressController.text.trim().isEmpty ? null : _addressController.text.trim(),
      locality: _localityController.text.trim().isEmpty ? null : _localityController.text.trim(),
      creditLimit: effectiveLimit,
      loyaltyPoints: widget.customer?.loyaltyPoints ?? 0,
      totalSpent: widget.customer?.totalSpent ?? 0,
      outstandingBalance: widget.customer?.outstandingBalance ?? 0,
      rating: widget.customer?.rating ?? CustomerRating.regular,
      ratingManualOverride: widget.customer?.ratingManualOverride,
      dateOfBirth: _dateOfBirth != null ? _dateOfBirth!.millisecondsSinceEpoch ~/ 1000 : null,
      isDeleted: false,
      createdAt: widget.customer?.createdAt ?? DateTime.now().millisecondsSinceEpoch,
      updatedAt: widget.customer?.updatedAt,
    );

    // The approver goes with the save. The repository, not this screen, is
    // what decides whether one was required — this only supplies the one it
    // authenticated, so a refused approval simply arrives as null and the
    // unchanged limit above passes the repository's check anyway.
    final notifier = ref.read(customerNotifierProvider.notifier);
    if (widget.customer == null) {
      await notifier.addCustomer(customer, approvedByUserId: approvedByUserId);
    } else {
      await notifier.updateCustomer(customer, approvedByUserId: approvedByUserId);
    }

    if (widget.onSaved != null) {
      widget.onSaved!(customer);
    }

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.customer == null ? 'New Customer' : 'Edit Customer'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Full Name *'),
                  validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _phoneController,
                  decoration: const InputDecoration(labelText: 'Phone Number *'),
                  keyboardType: TextInputType.phone,
                  validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(labelText: 'Email (optional)'),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _addressController,
                  decoration: const InputDecoration(labelText: 'Address (optional)'),
                  maxLines: 2,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _localityController,
                  decoration: const InputDecoration(labelText: 'Locality (optional)'),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _creditLimitController,
                  decoration: const InputDecoration(labelText: 'Credit Limit (₹)'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.cake_outlined),
                  title: Text(_dateOfBirth == null
                      ? 'Date of Birth (optional)'
                      : 'Birthday: ${_dateOfBirth!.day}/${_dateOfBirth!.month}/${_dateOfBirth!.year}'),
                  subtitle: const Text('Used for birthday-wish campaigns'),
                  trailing: _dateOfBirth != null
                      ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () => setState(() => _dateOfBirth = null))
                      : null,
                  onTap: _pickDateOfBirth,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 40,
                  child: ElevatedButton(
                    onPressed: _save,
                    child: Text(widget.customer == null ? 'CREATE CUSTOMER' : 'UPDATE CUSTOMER'),
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
