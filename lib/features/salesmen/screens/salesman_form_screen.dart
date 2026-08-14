import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../models/salesman_model.dart';
import '../../../repositories/salesman_repository.dart';

class SalesmanFormScreen extends ConsumerStatefulWidget {
  final Salesman? salesman;

  const SalesmanFormScreen({super.key, this.salesman});

  @override
  ConsumerState<SalesmanFormScreen> createState() => _SalesmanFormScreenState();
}

class _SalesmanFormScreenState extends ConsumerState<SalesmanFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late bool _isActive;

  bool _isSaving = false;

  bool get _isEditing => widget.salesman != null;

  @override
  void initState() {
    super.initState();
    final s = widget.salesman;
    _nameController = TextEditingController(text: s?.name ?? '');
    _phoneController = TextEditingController(text: s?.phone ?? '');
    _isActive = s?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      final name = _nameController.text.trim();
      final phone = _phoneController.text.trim();

      final repo = ref.read(salesmanRepositoryProvider);

      if (_isEditing) {
        final updated = widget.salesman!.copyWith(
          name: name,
          phone: phone.isEmpty ? null : phone,
          isActive: _isActive,
        );
        await repo.update(updated);
      } else {
        final salesman = Salesman.create(
          name: name,
          phone: phone.isEmpty ? null : phone,
        );
        await repo.insert(salesman);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isEditing ? 'Salesman updated' : 'Salesman added'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving salesman: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: _isEditing ? 'Edit Salesman' : 'New Salesman',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Salesman Name *',
                    border: OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.words,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Salesman name is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneController,
                  decoration: const InputDecoration(
                    labelText: 'Phone',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.phone),
                  ),
                  keyboardType: TextInputType.phone,
                ),
                if (_isEditing) ...[
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Active'),
                    subtitle: const Text('Inactive salesmen are hidden from billing and performance lists'),
                    value: _isActive,
                    onChanged: (value) => setState(() => _isActive = value),
                  ),
                ],
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _isSaving ? null : _save,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.save),
                  label: Text(_isEditing ? 'Update Salesman' : 'Save Salesman'),
                  style: ElevatedButton.styleFrom(
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
