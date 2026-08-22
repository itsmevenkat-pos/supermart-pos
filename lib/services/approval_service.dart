import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../core/database/database_helper.dart';

/// Failures raised when a financial action is not properly authorised.
///
/// Distinct types rather than bare `Exception('...')` for the same reason the
/// GL uses them: the caller has to be able to tell "a manager needs to approve
/// this" (show the approval dialog) apart from "the person you named may not
/// approve" (refuse and say why). [code] is the stable identifier; [message]
/// is what a cashier reads.
class ApprovalException implements Exception {
  const ApprovalException(this.message, this.code);

  final String message;
  final String code;

  @override
  String toString() => 'ApprovalException($code): $message';
}

/// The amount is above the threshold a cashier may act on alone and no
/// approver was supplied at all.
class ApprovalRequired extends ApprovalException {
  const ApprovalRequired(String message) : super(message, 'APPROVAL_REQUIRED');
}

/// An approver was supplied but may not authorise this — wrong role, a
/// deactivated account, or an id that names nobody.
class UnauthorizedApprover extends ApprovalException {
  const UnauthorizedApprover(String message) : super(message, 'UNAUTHORIZED_APPROVER');
}

/// The one place that decides whether a financial action is authorised.
///
/// **Why this is a service and not a dialog.** Until now the threshold rule
/// lived in the screens: `receive_payment_screen` read the store's threshold,
/// compared it, and showed an approval dialog above it. That made the control
/// a property of one code path rather than of the operation — anything calling
/// the repository directly (a future screen, a bulk tool, a sync handler, a
/// test) simply did not have it. The UI still owns the *experience* of asking
/// for approval; this owns the *rule*, and the repositories call it inside
/// their own transaction so a refusal rolls the whole operation back.
///
/// Checks run on the caller's [DatabaseExecutor], never on a second
/// connection — querying through `DatabaseHelper.database` from inside an open
/// transaction deadlocks against it in sqflite.
class ApprovalService {
  ApprovalService({DatabaseHelper? dbHelper}) : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _dbHelper;

  /// Roles that may authorise a financial action on someone else's behalf.
  static const Set<String> approverRoles = {'admin', 'manager'};

  /// The amount a cashier may move without a manager, read from store
  /// settings.
  ///
  /// This is `stores.return_threshold_no_approval` — the same figure returns
  /// and receive-payment already use. Reusing it is deliberate: it is the
  /// shop's one "how much may a cashier move unsupervised" number, and giving
  /// cash management a second, separately-configured threshold would mean a
  /// shop could tighten refunds while silently leaving till payouts wide open.
  /// If the two ever need to diverge, that is a store-settings change and a
  /// migration, not a hardcoded constant here.
  Future<double> cashierDiscretionLimit({DatabaseExecutor? executor}) async {
    final db = executor ?? await _dbHelper.database;
    final rows = await db.query(
      'stores',
      columns: ['return_threshold_no_approval'],
      where: 'id = ?',
      whereArgs: ['store_default'],
      limit: 1,
    );
    if (rows.isEmpty) return 500;
    return (rows.first['return_threshold_no_approval'] as num?)?.toDouble() ?? 500;
  }

  /// Verifies that [approvedByUserId] names someone who may authorise things.
  ///
  /// Never trusts the id it is given: a supplied approver is a claim, and a
  /// claim that is written into an audit row without being checked is a forged
  /// approval that is then believed for ever.
  Future<void> requireValidApprover(
    String approvedByUserId, {
    required DatabaseExecutor executor,
  }) async {
    final rows = await executor.query(
      'users',
      columns: ['role', 'is_active'],
      where: 'id = ?',
      whereArgs: [approvedByUserId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw UnauthorizedApprover('No user with id $approvedByUserId — approval refused.');
    }
    final role = rows.first['role'] as String?;
    if (role == null || !approverRoles.contains(role)) {
      throw UnauthorizedApprover(
        'That user is a ${role ?? 'user'} and cannot approve this — a manager or admin is needed.',
      );
    }
    if (((rows.first['is_active'] as num?)?.toInt() ?? 0) != 1) {
      throw const UnauthorizedApprover('That approver\'s account is deactivated — approval refused.');
    }
  }

  /// The full rule for an amount-gated action: below the limit a cashier acts
  /// alone; at or above it a valid approver is required.
  ///
  /// The boundary is `amount > limit`, matching what the screens have always
  /// done — an amount exactly equal to the threshold does *not* need approval.
  /// An approver supplied below the threshold is still validated rather than
  /// waved through, so a bad id cannot be smuggled into the audit trail on a
  /// small transaction.
  Future<void> authorise({
    required double amount,
    required String actionLabel,
    String? approvedByUserId,
    required DatabaseExecutor executor,
  }) async {
    final limit = await cashierDiscretionLimit(executor: executor);
    if (amount > limit) {
      if (approvedByUserId == null) {
        throw ApprovalRequired(
          '$actionLabel of ₹${amount.toStringAsFixed(2)} is above the ₹${limit.toStringAsFixed(2)} '
          'limit a cashier may act on alone — a manager or admin must approve it.',
        );
      }
      await requireValidApprover(approvedByUserId, executor: executor);
      return;
    }
    if (approvedByUserId != null) {
      await requireValidApprover(approvedByUserId, executor: executor);
    }
  }

  /// Actions that always need a manager regardless of amount — currently the
  /// manual cash adjustment, which is the one operation that can make a till
  /// balance by assertion rather than by counting.
  Future<void> authoriseAlways({
    required String actionLabel,
    String? approvedByUserId,
    required DatabaseExecutor executor,
  }) async {
    if (approvedByUserId == null) {
      throw ApprovalRequired('$actionLabel always needs a manager or admin to approve it.');
    }
    await requireValidApprover(approvedByUserId, executor: executor);
  }
}

final approvalServiceProvider = Provider<ApprovalService>((ref) => ApprovalService());
