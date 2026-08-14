import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../models/store_model.dart';
import '../../../repositories/store_repository.dart';

const _businessTypes = [
  'Retail',
  'Wholesale',
  'Distributor',
  'Manufacturer',
  'Service',
  'Other',
];

const _businessCategories = [
  'FMCG Products',
  'Grocery & Staples',
  'Electronics',
  'Clothing & Apparel',
  'Pharmacy',
  'Restaurant & Food',
  'Hardware & Tools',
  'Other',
];

const _indianStates = [
  'Andhra Pradesh', 'Arunachal Pradesh', 'Assam', 'Bihar', 'Chhattisgarh',
  'Goa', 'Gujarat', 'Haryana', 'Himachal Pradesh', 'Jharkhand', 'Karnataka',
  'Kerala', 'Madhya Pradesh', 'Maharashtra', 'Manipur', 'Meghalaya',
  'Mizoram', 'Nagaland', 'Odisha', 'Punjab', 'Rajasthan', 'Sikkim',
  'Tamil Nadu', 'Telangana', 'Tripura', 'Uttar Pradesh', 'Uttarakhand',
  'West Bengal', 'Delhi', 'Jammu and Kashmir', 'Ladakh', 'Puducherry',
];

class BusinessProfileScreen extends ConsumerStatefulWidget {
  const BusinessProfileScreen({super.key});

  @override
  ConsumerState<BusinessProfileScreen> createState() => _BusinessProfileScreenState();
}

class _BusinessProfileScreenState extends ConsumerState<BusinessProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _repo = StoreRepository();

  late Future<Store> _storeFuture;

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _gstinController = TextEditingController();
  final _emailController = TextEditingController();
  final _addressController = TextEditingController();
  final _pincodeController = TextEditingController();

  String? _businessType;
  String? _businessCategory;
  String? _state;
  String? _logoPath;
  String? _signaturePath;

  bool _isSaving = false;
  Store? _loadedStore;

  @override
  void initState() {
    super.initState();
    _storeFuture = _repo.getStore().then((store) {
      _loadedStore = store;
      _nameController.text = store.name;
      _phoneController.text = store.phone ?? '';
      _gstinController.text = store.gstin ?? '';
      _emailController.text = store.email ?? '';
      _addressController.text = store.address ?? '';
      _pincodeController.text = store.pincode ?? '';
      _businessType = store.businessType;
      _businessCategory = store.businessCategory;
      _state = store.state;
      _logoPath = store.logoPath;
      _signaturePath = store.signaturePath;
      return store;
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _gstinController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _pincodeController.dispose();
    super.dispose();
  }

  Future<void> _pickImage({required bool isLogo}) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      dialogTitle: isLogo ? 'Select business logo' : 'Select signature',
    );
    final path = result?.files.single.path;
    if (path == null) return;
    setState(() {
      if (isLogo) {
        _logoPath = path;
      } else {
        _signaturePath = path;
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_loadedStore == null) return;

    setState(() => _isSaving = true);
    try {
      final updated = _loadedStore!.copyWith(
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        gstin: _gstinController.text.trim(),
        email: _emailController.text.trim(),
        businessType: _businessType,
        businessCategory: _businessCategory,
        address: _addressController.text.trim(),
        state: _state,
        pincode: _pincodeController.text.trim(),
        logoPath: _logoPath,
        signaturePath: _signaturePath,
      );
      await _repo.updateStore(updated);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Business profile updated'), backgroundColor: Colors.green),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving profile: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Business Profile',
      body: FutureBuilder<Store>(
        future: _storeFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLogoPicker(),
                    const SizedBox(height: 32),
                    Wrap(
                      spacing: 48,
                      runSpacing: 24,
                      children: [
                        SizedBox(width: 380, child: _buildBusinessDetails()),
                        SizedBox(width: 380, child: _buildMoreDetails()),
                      ],
                    ),
                    const SizedBox(height: 32),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: _isSaving ? null : _save,
                          icon: _isSaving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.save),
                          label: const Text('Save Changes'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                          ),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton(
                          onPressed: _isSaving ? null : () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLogoPicker() {
    return GestureDetector(
      onTap: () => _pickImage(isLogo: true),
      child: Stack(
        children: [
          CircleAvatar(
            radius: 60,
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            backgroundImage: _logoPath != null ? FileImage(File(_logoPath!)) : null,
            child: _logoPath == null
                ? const Text('Add\nLogo', textAlign: TextAlign.center)
                : null,
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: CircleAvatar(
              radius: 16,
              backgroundColor: Colors.white,
              child: Icon(Icons.edit, size: 16, color: Theme.of(context).colorScheme.primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBusinessDetails() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Business Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        TextFormField(
          controller: _nameController,
          decoration: const InputDecoration(labelText: 'Business Name *', border: OutlineInputBorder()),
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Business name is required' : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _phoneController,
          decoration: const InputDecoration(labelText: 'Phone Number', border: OutlineInputBorder()),
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _gstinController,
          decoration: const InputDecoration(
            labelText: 'GSTIN',
            border: OutlineInputBorder(),
            hintText: 'Enter GSTIN',
          ),
          textCapitalization: TextCapitalization.characters,
          validator: (v) {
            if (v == null || v.trim().isEmpty) return null;
            final ok = RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$')
                .hasMatch(v.trim().toUpperCase());
            return ok ? null : 'Enter a valid 15-character GSTIN';
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _emailController,
          decoration: const InputDecoration(labelText: 'Email ID', border: OutlineInputBorder()),
          keyboardType: TextInputType.emailAddress,
          validator: (v) {
            if (v == null || v.trim().isEmpty) return null;
            final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim());
            return ok ? null : 'Enter a valid email';
          },
        ),
      ],
    );
  }

  Widget _buildMoreDetails() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('More Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          decoration: const InputDecoration(labelText: 'Business Type', border: OutlineInputBorder()),
          initialValue: _businessType,
          items: _businessTypes
              .map((t) => DropdownMenuItem(value: t, child: Text(t)))
              .toList(),
          onChanged: (v) => setState(() => _businessType = v),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          decoration: const InputDecoration(labelText: 'Business Category', border: OutlineInputBorder()),
          initialValue: _businessCategory,
          items: _businessCategories
              .map((c) => DropdownMenuItem(value: c, child: Text(c)))
              .toList(),
          onChanged: (v) => setState(() => _businessCategory = v),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          decoration: const InputDecoration(labelText: 'State', border: OutlineInputBorder()),
          initialValue: _state,
          items: _indianStates
              .map((s) => DropdownMenuItem(value: s, child: Text(s)))
              .toList(),
          onChanged: (v) => setState(() => _state = v),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _pincodeController,
          decoration: const InputDecoration(labelText: 'Pincode', border: OutlineInputBorder()),
          keyboardType: TextInputType.number,
          validator: (v) {
            if (v == null || v.trim().isEmpty) return null;
            return RegExp(r'^\d{6}$').hasMatch(v.trim()) ? null : 'Enter a valid 6-digit pincode';
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _addressController,
          decoration: const InputDecoration(labelText: 'Business Address', border: OutlineInputBorder()),
          maxLines: 3,
        ),
        const SizedBox(height: 12),
        _buildSignaturePicker(),
      ],
    );
  }

  Widget _buildSignaturePicker() {
    return GestureDetector(
      onTap: () => _pickImage(isLogo: false),
      child: Container(
        height: 100,
        width: double.infinity,
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outline),
          borderRadius: BorderRadius.circular(8),
        ),
        child: _signaturePath != null
            ? Image.file(File(_signaturePath!), fit: BoxFit.contain)
            : const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cloud_upload_outlined),
                    SizedBox(height: 4),
                    Text('Upload Signature'),
                  ],
                ),
              ),
      ),
    );
  }
}
