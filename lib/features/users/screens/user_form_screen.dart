import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/security/password_hasher.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../models/user_model.dart';
import '../../../repositories/user_repository.dart';

class UserFormScreen extends StatefulWidget {
  final User? user;

  const UserFormScreen({super.key, this.user});

  @override
  State<UserFormScreen> createState() => _UserFormScreenState();
}

class _UserFormScreenState extends State<UserFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _repo = UserRepository();

  late final TextEditingController _nameController;
  late final TextEditingController _usernameController;

  late UserRole _role;
  bool _isSaving = false;

  bool get _isEditing => widget.user != null;

  @override
  void initState() {
    super.initState();
    final u = widget.user;
    _nameController = TextEditingController(text: u?.name ?? '');
    _usernameController = TextEditingController(text: u?.username ?? '');
    _role = u?.role ?? UserRole.cashier;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  /// Random 8-character temp password. Charset excludes visually-ambiguous
  /// characters (0/O, 1/l/I) since this gets read off a screen and typed
  /// back in by whoever it's handed to.
  String _generateTempPassword() {
    const chars = 'ABCDEFGHJKMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789';
    final rand = Random.secure();
    return List.generate(8, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      if (_isEditing) {
        final updated = widget.user!.copyWith(
          name: _nameController.text.trim(),
          username: _usernameController.text.trim(),
          role: _role,
        );
        await _repo.update(updated);
        if (mounted) Navigator.pop(context);
      } else {
        final existing = await _repo.getByUsername(_usernameController.text.trim());
        if (existing != null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('That username is already taken'), backgroundColor: Colors.red),
            );
          }
          setState(() => _isSaving = false);
          return;
        }

        final tempPassword = _generateTempPassword();
        final newUser = User.create(
          username: _usernameController.text.trim(),
          passwordHash: PasswordHasher.hash(tempPassword),
          role: _role,
          name: _nameController.text.trim(),
          // Always true for a system-generated password — the user picks
          // their own real one the first time they log in.
          mustChangePassword: true,
        );
        await _repo.insert(newUser);
        if (mounted) await _showCredentialsDialog(newUser.username, tempPassword);
        if (mounted) Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save user: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _resetPassword() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Reset Password – ${widget.user!.name}'),
        content: const Text(
          'This generates a new temporary password. The user will need to set their own password the next time they log in. Continue?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Generate'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final tempPassword = _generateTempPassword();
    await _repo.update(widget.user!.copyWith(
      passwordHash: PasswordHasher.hash(tempPassword),
      mustChangePassword: true,
    ));
    if (mounted) await _showCredentialsDialog(widget.user!.username, tempPassword);
  }

  /// Shows the temp password once, with a one-tap copy so the admin can
  /// hand it to the user without retyping it — the standard pattern in
  /// POS/back-office admin panels.
  Future<void> _showCredentialsDialog(String username, String tempPassword) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Temporary Password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Share these with the user. This password is shown only once.'),
            const SizedBox(height: 16),
            Text('Username: $username', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    tempPassword,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, letterSpacing: 1.2, fontFamily: 'monospace'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 20),
                    tooltip: 'Copy password',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: tempPassword));
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(content: Text('Password copied'), duration: Duration(seconds: 1)),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: 'Username: $username\nPassword: $tempPassword'));
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(content: Text('Username and password copied'), duration: Duration(seconds: 1)),
                );
              },
              icon: const Icon(Icons.copy_all, size: 18),
              label: const Text('Copy both'),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: _isEditing ? 'Edit User' : 'New User',
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Full Name', border: OutlineInputBorder()),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _usernameController,
              decoration: const InputDecoration(labelText: 'Username', border: OutlineInputBorder()),
              autocorrect: false,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Username is required';
                if (v.trim().contains(' ')) return 'Username cannot contain spaces';
                return null;
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<UserRole>(
              initialValue: _role,
              decoration: const InputDecoration(labelText: 'Role', border: OutlineInputBorder()),
              items: UserRole.values.map((r) {
                return DropdownMenuItem(value: r, child: Text(r.name[0].toUpperCase() + r.name.substring(1)));
              }).toList(),
              onChanged: (val) => setState(() => _role = val!),
            ),
            const SizedBox(height: 16),
            if (!_isEditing)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.blue.shade100),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 18, color: Colors.blue.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'A temporary password will be generated automatically and shown once you create the user.',
                        style: TextStyle(fontSize: 13, color: Colors.blue.shade900),
                      ),
                    ),
                  ],
                ),
              )
            else
              OutlinedButton.icon(
                onPressed: _resetPassword,
                icon: const Icon(Icons.lock_reset),
                label: const Text('Reset Password'),
              ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isSaving ? null : _save,
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              child: _isSaving
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(_isEditing ? 'Save Changes' : 'Create User'),
            ),
          ],
        ),
      ),
    );
  }
}