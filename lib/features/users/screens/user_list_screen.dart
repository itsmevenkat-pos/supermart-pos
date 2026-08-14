import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../models/user_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/user_provider.dart';
import '../../../repositories/user_repository.dart';
import 'user_form_screen.dart';

class UserListScreen extends ConsumerWidget {
  const UserListScreen({super.key});

  Color _roleColor(UserRole role) {
    switch (role) {
      case UserRole.admin:
        return Colors.red.shade700;
      case UserRole.manager:
        return Colors.blue.shade700;
      case UserRole.accountant:
        return Colors.teal.shade700;
      case UserRole.cashier:
        return Colors.grey.shade700;
    }
  }

  String _roleLabel(UserRole role) {
    switch (role) {
      case UserRole.admin:
        return 'Admin';
      case UserRole.manager:
        return 'Manager';
      case UserRole.accountant:
        return 'Accountant';
      case UserRole.cashier:
        return 'Cashier';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersAsync = ref.watch(userListProvider);
    final currentUser = ref.watch(authProvider).user;

    return AppScaffold(
      title: 'Users',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () => ref.invalidate(userListProvider),
        ),
      ],
      floatingActionButton: FloatingActionButton(
        onPressed: () => _navigateToForm(context, ref),
        child: const Icon(Icons.add),
      ),
      body: usersAsync.when(
        data: (users) {
          if (users.isEmpty) {
            return const Center(child: Text('No users yet'));
          }
          return ListView.builder(
            itemCount: users.length,
            itemBuilder: (_, index) {
              final u = users[index];
              final isSelf = u.id == currentUser?.id;
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: _roleColor(u.role).withValues(alpha: 0.15),
                  child: Text(
                    u.name.isNotEmpty ? u.name[0].toUpperCase() : '?',
                    style: TextStyle(color: _roleColor(u.role), fontWeight: FontWeight.bold),
                  ),
                ),
                title: Text(u.name),
                subtitle: Text('@${u.username}${isSelf ? ' (You)' : ''}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _roleColor(u.role).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _roleLabel(u.role),
                        style: TextStyle(color: _roleColor(u.role), fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Switch(
                      value: u.isActive,
                      onChanged: isSelf
                          ? null // can't deactivate your own account
                          : (value) => _toggleActive(context, ref, u, value),
                    ),
                  ],
                ),
                onTap: () => _navigateToForm(context, ref, u),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
      ),
    );
  }

  Future<void> _toggleActive(BuildContext context, WidgetRef ref, User user, bool active) async {
    if (!active) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Deactivate User'),
          content: Text('${user.name} will no longer be able to log in. Continue?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Deactivate'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    await UserRepository().update(user.copyWith(isActive: active));
    ref.invalidate(userListProvider);
  }

  void _navigateToForm(BuildContext context, WidgetRef ref, [User? user]) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => UserFormScreen(user: user)),
    ).then((_) => ref.invalidate(userListProvider));
  }
}
