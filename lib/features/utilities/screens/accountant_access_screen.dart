import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/security/password_hasher.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../models/user_model.dart';
import '../../../repositories/user_repository.dart';

/// Admin-facing screen to create and manage accountant-role user accounts.
///
/// Accountants get read/export-only access (reports, sales history/summary,
/// customers, suppliers, item/Tally exports, verify-data) — the route
/// allowlist for that is already enforced in app_router.dart. This screen
/// just handles the CRUD side: it's a filtered, role-locked variant of
/// UserListScreen/UserFormScreen restricted to UserRole.accountant.
class AccountantAccessScreen extends StatefulWidget {
  const AccountantAccessScreen({super.key});

  @override
  State<AccountantAccessScreen> createState() => _AccountantAccessScreenState();
}

class _AccountantAccessScreenState extends State<AccountantAccessScreen> {
  final _repo = UserRepository();

  late Future<List<User>> _accountantsFuture;

  @override
  void initState() {
    super.initState();
    _accountantsFuture = _loadAccountants();
  }

  Future<List<User>> _loadAccountants() async {
    final all = await _repo.getAll();
    return all.where((u) => u.role == UserRole.accountant).toList();
  }

  void _refresh() {
    setState(() => _accountantsFuture = _loadAccountants());
  }

  /// Random 8-character temp password. Charset excludes visually-ambiguous
  /// characters (0/O, 1/l/I) since this gets read off a screen and typed
  /// back in by whoever it's handed to.
  String _generateTempPassword() {
    const chars = 'ABCDEFGHJKMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789';
    final rand = Random.secure();
    return List.generate(8, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  Future<void> _toggleActive(User user) async {
    try {
      await _repo.update(user.copyWith(isActive: !user.isActive));
      _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update account: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _addAccountant() async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    final usernameController = TextEditingController();
    bool isSaving = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Future<void> submit() async {
              if (!formKey.currentState!.validate()) return;

              setDialogState(() => isSaving = true);
              try {
                final username = usernameController.text.trim();
                final existing = await _repo.getByUsername(username);
                if (existing != null) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(content: Text('That username is already taken'), backgroundColor: Colors.red),
                    );
                  }
                  setDialogState(() => isSaving = false);
                  return;
                }

                final tempPassword = _generateTempPassword();
                final newUser = User.create(
                  username: username,
                  passwordHash: PasswordHasher.hash(tempPassword),
                  role: UserRole.accountant,
                  name: nameController.text.trim(),
                  // Always true for a system-generated password — the user
                  // picks their own real one the first time they log in.
                  mustChangePassword: true,
                );
                await _repo.insert(newUser);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                if (mounted) await _showCredentialsDialog(newUser.username, tempPassword);
                _refresh();
              } catch (e) {
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(content: Text('Failed to create accountant: $e'), backgroundColor: Colors.red),
                  );
                }
              } finally {
                setDialogState(() => isSaving = false);
              }
            }

            return AlertDialog(
              title: const Text('Add Accountant'),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: 'Full Name', border: OutlineInputBorder()),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: usernameController,
                      decoration: const InputDecoration(labelText: 'Username', border: OutlineInputBorder()),
                      autocorrect: false,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Username is required';
                        if (v.trim().contains(' ')) return 'Username cannot contain spaces';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
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
                              'A temporary password will be generated automatically and shown once you create the account.',
                              style: TextStyle(fontSize: 13, color: Colors.blue.shade900),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSaving ? null : submit,
                  child: isSaving
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Shows the temp password once, with a one-tap copy so the admin can
  /// hand it to the accountant without retyping it.
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
            const Text('Share these with the accountant. This password is shown only once.'),
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
      title: 'Accountant Access',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: _refresh,
        ),
      ],
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addAccountant,
        icon: const Icon(Icons.add),
        label: const Text('Add Accountant'),
      ),
      body: FutureBuilder<List<User>>(
        future: _accountantsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final accountants = snapshot.data ?? [];
          if (accountants.isEmpty) {
            return const Center(child: Text('No accountant accounts yet'));
          }
          return ListView.builder(
            itemCount: accountants.length,
            itemBuilder: (_, index) {
              final u = accountants[index];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.teal.withValues(alpha: 0.15),
                  child: Text(
                    u.name.isNotEmpty ? u.name[0].toUpperCase() : '?',
                    style: const TextStyle(color: Colors.teal, fontWeight: FontWeight.bold),
                  ),
                ),
                title: Text(u.name),
                subtitle: Text('@${u.username}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      u.isActive ? 'Active' : 'Inactive',
                      style: TextStyle(
                        color: u.isActive ? Colors.green.shade700 : Colors.grey.shade600,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    Switch(
                      value: u.isActive,
                      onChanged: (_) => _toggleActive(u),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
