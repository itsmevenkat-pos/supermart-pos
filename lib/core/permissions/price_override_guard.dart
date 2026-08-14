import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/auth_service.dart';
import '../database/database_helper.dart';

/// Gate for price-changing actions (discounts, manual price overrides).
///
/// Admins and managers pass straight through — they already have the
/// authority. A cashier is prompted for a manager/admin's credentials,
/// which are verified WITHOUT switching the app's active login session
/// (so the cashier stays logged in as themselves throughout). A successful
/// approval is written to the audit log so there's a record of who
/// authorized what.
Future<bool> requirePriceOverrideAuth(
  BuildContext context,
  WidgetRef ref, {
  required String actionLabel,
}) async {
  final currentUser = ref.read(authProvider).user;
  if (currentUser == null) return false;

  if (currentUser.role == UserRole.admin || currentUser.role == UserRole.manager) {
    return true;
  }

  final usernameController = TextEditingController();
  final passwordController = TextEditingController();

  final approved = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => _ApprovalDialog(
      actionLabel: actionLabel,
      usernameController: usernameController,
      passwordController: passwordController,
      currentUser: currentUser,
    ),
  );

  usernameController.dispose();
  passwordController.dispose();
  return approved ?? false;
}

/// Same manager/admin approval flow as [requirePriceOverrideAuth], but
/// returns the approving [User] instead of a bare bool — for callers (like
/// Returns/Refunds) that need to record *who* approved, not just that
/// someone did. Admins/managers acting on their own return `currentUser`
/// straight through, same as [requirePriceOverrideAuth]'s early pass.
Future<User?> requireApprovalWithApprover(
  BuildContext context,
  WidgetRef ref, {
  required String actionLabel,
}) async {
  final currentUser = ref.read(authProvider).user;
  if (currentUser == null) return null;

  if (currentUser.role == UserRole.admin || currentUser.role == UserRole.manager) {
    return currentUser;
  }

  final usernameController = TextEditingController();
  final passwordController = TextEditingController();

  final approver = await showDialog<User>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => _ApprovalDialog(
      actionLabel: actionLabel,
      usernameController: usernameController,
      passwordController: passwordController,
      currentUser: currentUser,
      returnApprover: true,
    ),
  );

  usernameController.dispose();
  passwordController.dispose();
  return approver;
}

class _ApprovalDialog extends StatefulWidget {
  final String actionLabel;
  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final User currentUser;
  /// When true, pops the approving [User] (for [requireApprovalWithApprover]);
  /// when false (default), pops a plain `true` (for [requirePriceOverrideAuth]).
  final bool returnApprover;

  const _ApprovalDialog({
    required this.actionLabel,
    required this.usernameController,
    required this.passwordController,
    required this.currentUser,
    this.returnApprover = false,
  });

  @override
  State<_ApprovalDialog> createState() => _ApprovalDialogState();
}

class _ApprovalDialogState extends State<_ApprovalDialog> {
  String? _error;
  bool _checking = false;

  Future<void> _approve() async {
    setState(() {
      _checking = true;
      _error = null;
    });

    final approver = await AuthService().login(
      widget.usernameController.text,
      widget.passwordController.text,
    );

    if (!mounted) return;

    if (approver == null) {
      setState(() {
        _checking = false;
        _error = 'Invalid username or password';
      });
      return;
    }

    if (approver.role != UserRole.admin && approver.role != UserRole.manager) {
      setState(() {
        _checking = false;
        _error = '${approver.name} is not authorized to approve this';
      });
      return;
    }

    await DatabaseHelper.instance.logAudit(
      userId: approver.id,
      actionType: 'PRICE_OVERRIDE_APPROVED',
      tableName: 'billing',
      recordId: widget.currentUser.id,
      newValue: '${widget.actionLabel} — approved by ${approver.name} for cashier ${widget.currentUser.name}',
    );

    if (!mounted) return;
    if (widget.returnApprover) {
      Navigator.pop<User>(context, approver);
    } else {
      Navigator.pop<bool>(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Manager Approval Required'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${widget.actionLabel} needs a manager or admin to approve.'),
          const SizedBox(height: 12),
          TextField(
            controller: widget.usernameController,
            decoration: const InputDecoration(labelText: 'Manager/Admin Username', border: OutlineInputBorder()),
            enabled: !_checking,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: widget.passwordController,
            decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
            obscureText: true,
            enabled: !_checking,
            onSubmitted: (_) => _approve(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _checking
              ? null
              : () => widget.returnApprover ? Navigator.pop<User>(context, null) : Navigator.pop<bool>(context, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _checking ? null : _approve,
          child: _checking
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Approve'),
        ),
      ],
    );
  }
}