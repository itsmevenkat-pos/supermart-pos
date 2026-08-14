import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../models/coupon_model.dart';
import '../../../repositories/coupon_repository.dart';

class CouponFormScreen extends ConsumerStatefulWidget {
  final Coupon? coupon;

  const CouponFormScreen({super.key, this.coupon});

  @override
  ConsumerState<CouponFormScreen> createState() => _CouponFormScreenState();
}

class _CouponFormScreenState extends ConsumerState<CouponFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _codeController;
  late final TextEditingController _valueController;
  late final TextEditingController _minBillController;
  late final TextEditingController _maxUsesController;

  late CouponType _type;
  late bool _isActive;
  DateTime? _startDate;
  DateTime? _endDate;

  bool _isSaving = false;

  bool get _isEditing => widget.coupon != null;

  @override
  void initState() {
    super.initState();
    final c = widget.coupon;
    _codeController = TextEditingController(text: c?.code ?? '');
    _valueController = TextEditingController(text: c?.value.toStringAsFixed(2) ?? '');
    _minBillController = TextEditingController(text: c != null && c.minBillAmount > 0 ? c.minBillAmount.toStringAsFixed(2) : '');
    _maxUsesController = TextEditingController(text: c?.maxUses?.toString() ?? '');
    _type = c?.type ?? CouponType.percentage;
    _isActive = c?.isActive ?? true;
    _startDate = c?.startDate != null ? DateTime.fromMillisecondsSinceEpoch(c!.startDate! * 1000) : null;
    _endDate = c?.endDate != null ? DateTime.fromMillisecondsSinceEpoch(c!.endDate! * 1000) : null;
  }

  @override
  void dispose() {
    _codeController.dispose();
    _valueController.dispose();
    _minBillController.dispose();
    _maxUsesController.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = (isStart ? _startDate : _endDate) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
      } else {
        _endDate = picked;
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      final code = _codeController.text.trim().toUpperCase();
      final value = double.tryParse(_valueController.text.trim()) ?? 0;
      final minBill = double.tryParse(_minBillController.text.trim()) ?? 0;
      final maxUses = int.tryParse(_maxUsesController.text.trim());
      final startEpoch = _startDate != null ? _startDate!.millisecondsSinceEpoch ~/ 1000 : null;
      final endEpoch = _endDate != null ? _endDate!.millisecondsSinceEpoch ~/ 1000 : null;

      final repo = ref.read(couponRepositoryProvider);

      // A duplicate code (other than this same coupon, when editing) would
      // otherwise fail silently against the table's UNIQUE constraint —
      // checked here so the cashier-facing error is legible instead of a
      // raw SQLite exception.
      final existing = await repo.getByCode(code);
      if (existing != null && existing.id != widget.coupon?.id) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('A coupon with code "$code" already exists'), backgroundColor: Colors.red),
        );
        setState(() => _isSaving = false);
        return;
      }

      if (_isEditing) {
        final updated = widget.coupon!.copyWith(
          code: code,
          type: _type,
          value: value,
          minBillAmount: minBill,
          maxUses: maxUses,
          clearMaxUses: maxUses == null,
          startDate: startEpoch,
          clearStartDate: startEpoch == null,
          endDate: endEpoch,
          clearEndDate: endEpoch == null,
          isActive: _isActive,
        );
        await repo.update(updated);
      } else {
        final coupon = Coupon.create(
          code: code,
          type: _type,
          value: value,
          minBillAmount: minBill,
          maxUses: maxUses,
          startDate: startEpoch,
          endDate: endEpoch,
        );
        await repo.insert(coupon);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isEditing ? 'Coupon updated' : 'Coupon created'), backgroundColor: Colors.green),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving coupon: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: _isEditing ? 'Edit Coupon' : 'New Coupon',
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
                  controller: _codeController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Coupon Code *',
                    hintText: 'e.g. WELCOME10',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => (value == null || value.trim().isEmpty) ? 'Coupon code is required' : null,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<CouponType>(
                  initialValue: _type,
                  decoration: const InputDecoration(labelText: 'Type *', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: CouponType.percentage, child: Text('Percentage off')),
                    DropdownMenuItem(value: CouponType.fixed, child: Text('Flat ₹ off')),
                  ],
                  onChanged: (value) => setState(() => _type = value ?? CouponType.percentage),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _valueController,
                  decoration: InputDecoration(
                    labelText: _type == CouponType.percentage ? 'Discount %' : 'Discount Amount (₹)',
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: (value) {
                    final n = double.tryParse(value?.trim() ?? '');
                    if (n == null || n <= 0) return 'Enter a value greater than 0';
                    if (_type == CouponType.percentage && n > 100) return 'Percentage can\'t exceed 100';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _minBillController,
                  decoration: const InputDecoration(
                    labelText: 'Minimum Bill Amount (optional)',
                    helperText: 'Leave blank for no minimum',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _maxUsesController,
                  decoration: const InputDecoration(
                    labelText: 'Usage Limit (optional)',
                    helperText: 'Leave blank for unlimited uses. Set to 1 for a single-use code.',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                const Text('Active Dates (optional — leave blank for always-on)', style: TextStyle(fontWeight: FontWeight.bold)),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _pickDate(isStart: true),
                        child: Text(_startDate == null ? 'Start date' : _startDate!.toString().split(' ')[0]),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (_startDate != null)
                      IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() => _startDate = null)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _pickDate(isStart: false),
                        child: Text(_endDate == null ? 'End date' : _endDate!.toString().split(' ')[0]),
                      ),
                    ),
                    if (_endDate != null)
                      IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() => _endDate = null)),
                  ],
                ),
                if (_isEditing) ...[
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Active'),
                    subtitle: const Text('Inactive coupons are rejected at checkout'),
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
                  label: Text(_isEditing ? 'Update Coupon' : 'Save Coupon'),
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
