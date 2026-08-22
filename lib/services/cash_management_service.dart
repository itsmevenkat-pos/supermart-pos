import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../core/database/database_helper.dart';
import '../repositories/cash_movement_repository.dart';
import 'approval_service.dart';
import '../models/chart_of_account_model.dart';
import 'gl_service.dart';

/// Non-sale cash movements: money entering or leaving a till for a reason the
/// sales path cannot express.
///
/// **Why this exists.** Project 1 built the cash book and closed the
/// reconciliation hole, then found that `CashMovementSource.manualAdjustment`
/// had no writer at all: a shop that paid a delivery driver ₹200 out of the
/// till, or dropped ₹5,000 to the safe mid-shift, had no way to say so. The
/// shift simply read short, and a control that produces unexplained shortages
/// every day stops being believed.
///
/// **What posts to the GL, and what deliberately does not** (accounting
/// decision AD-5, taken with the business):
/// - A **drop** to the safe and a **transfer** between counters move cash from
///   one place to another. With a single `Cash` account in the chart of
///   accounts they have *no* GL consequence — inventing a "Cash in Safe"
///   account to make them look like accounting would be an arbitrary posting.
///   They move the cash book and the shift, and nothing else.
/// - **Cash in** with no named counterpart (a float correction, petty cash
///   coming back) likewise touches only the cash book.
/// - **Cash out as an expense** does post: `Dr <the expense account the
///   operator chose> / Cr Cash`. The operator picks the account; this refuses
///   the movement rather than defaulting to one, because guessing which
///   expense a ₹200 payout belongs to is exactly the arbitrary classification
///   the accounting review ruled out.
/// - **Manual adjustment** (a till reading short or over) does not post. That
///   needs a `Cash Short/Over` account and a policy on who may write a
///   shortage off; both are open decisions, deliberately not invented here.
///
/// Every operation is one transaction covering the cash movement and its audit
/// row, so an unauthorised or failed movement leaves nothing behind.
class CashManagementService {
  CashManagementService({
    DatabaseHelper? dbHelper,
    CashMovementRepository? cashMovements,
    ApprovalService? approvals,
    GLService? glService,
  })  : _dbHelper = dbHelper ?? DatabaseHelper.instance,
        _cashMovements = cashMovements ?? CashMovementRepository(),
        _approvals = approvals ?? ApprovalService(),
        _glService = glService ?? GLService();

  final DatabaseHelper _dbHelper;
  final CashMovementRepository _cashMovements;
  final ApprovalService _approvals;
  final GLService _glService;

  static const String auditAction = 'CASH_MOVEMENT_RECORDED';
  static const String glReferenceType = 'CashMovement';

  /// Money into the till from outside a sale — a float top-up, petty cash
  /// coming back, a miscellaneous receipt.
  ///
  /// Cash arriving is not the leak risk cash leaving is, so this is not
  /// amount-gated; it is still attributed and audited like everything else.
  Future<String> cashIn({
    required double amount,
    required String reason,
    required String userId,
    String? sessionId,
    String? counterparty,
    String? approvedByUserId,
  }) =>
      _record(
        direction: 'in',
        sourceType: CashMovementSource.cashIn,
        amount: amount,
        reason: reason,
        userId: userId,
        sessionId: sessionId,
        counterparty: counterparty,
        approvedByUserId: approvedByUserId,
        requireApproval: false,
      );

  /// Money out of the till — petty cash, an expense, a supplier paid in notes.
  ///
  /// Pass [expenseAccountCode] to book it as an expense (`Dr expense / Cr
  /// Cash`). Leave it null and only the cash book moves, which is right for a
  /// payout that will be classified later or that is settled elsewhere.
  /// Above the cashier discretion limit a manager must approve.
  Future<String> cashOut({
    required double amount,
    required String reason,
    required String userId,
    String? sessionId,
    String? counterparty,
    String? approvedByUserId,
    String? expenseAccountCode,
  }) =>
      _record(
        direction: 'out',
        sourceType: CashMovementSource.cashOut,
        amount: amount,
        reason: reason,
        userId: userId,
        sessionId: sessionId,
        counterparty: counterparty,
        approvedByUserId: approvedByUserId,
        requireApproval: true,
        expenseAccountCode: expenseAccountCode,
      );

  /// Cash moved from the till to the safe. Reduces what the shift must account
  /// for; no GL effect (AD-5).
  Future<String> cashDrop({
    required double amount,
    required String userId,
    required String destination,
    String? reason,
    String? sessionId,
    String? approvedByUserId,
  }) =>
      _record(
        direction: 'out',
        sourceType: CashMovementSource.cashDrop,
        amount: amount,
        reason: reason ?? 'Cash drop to $destination',
        userId: userId,
        sessionId: sessionId,
        counterparty: destination,
        approvedByUserId: approvedByUserId,
        requireApproval: true,
      );

  /// Cash moved between two open shifts. Writes both legs in one transaction,
  /// so the money is never in neither place nor in both — each leg names the
  /// other session as its counterparty, which is what lets a transfer be
  /// matched to its pair afterwards.
  ///
  /// Returns the two movement ids, out first.
  Future<(String, String)> cashTransfer({
    required double amount,
    required String userId,
    required String fromSessionId,
    required String toSessionId,
    String? reason,
    String? approvedByUserId,
  }) async {
    if (amount <= 0) {
      throw ArgumentError('A transfer must be greater than zero');
    }
    if (fromSessionId == toSessionId) {
      throw ArgumentError('A transfer needs two different sessions');
    }

    final db = await _dbHelper.database;
    late String outId;
    late String inId;

    await db.transaction((txn) async {
      await _approvals.authorise(
        amount: amount,
        actionLabel: 'Cash transfer',
        approvedByUserId: approvedByUserId,
        executor: txn,
      );
      await _requireOpenSession(fromSessionId, txn);
      await _requireOpenSession(toSessionId, txn);

      final note = reason ?? 'Cash transfer between counters';

      outId = (await _cashMovements.recordOut(
        amount: amount,
        sourceType: CashMovementSource.cashTransferOut,
        sessionId: fromSessionId,
        userId: userId,
        note: note,
        counterparty: toSessionId,
        approvedByUserId: approvedByUserId,
        reason: note,
        executor: txn,
      ))!;

      inId = (await _cashMovements.recordIn(
        amount: amount,
        sourceType: CashMovementSource.cashTransferIn,
        sourceId: outId, // ties the receiving leg to the leg that sent it
        sessionId: toSessionId,
        userId: userId,
        note: note,
        counterparty: fromSessionId,
        approvedByUserId: approvedByUserId,
        reason: note,
        executor: txn,
      ))!;

      await _dbHelper.logAudit(
        userId: userId,
        actionType: auditAction,
        tableName: 'cash_movements',
        recordId: outId,
        newValue: jsonEncode({
          'type': CashMovementSource.cashTransferOut,
          'amount': amount,
          'fromSessionId': fromSessionId,
          'toSessionId': toSessionId,
          'pairedMovementId': inId,
          'reason': note,
          'approvedByUserId': approvedByUserId,
        }),
        executor: txn,
      );
    });

    return (outId, inId);
  }

  /// A deliberate correction to what the till is expected to hold.
  ///
  /// **Always requires a manager**, whatever the amount, and always requires a
  /// reason. This is the one operation that can make a drawer balance by
  /// assertion rather than by counting, so it is never available to a cashier
  /// acting alone — an unrestricted "make it balance" button would undo the
  /// entire control Project 1 built.
  /// `async` so its argument checks surface as a rejected Future like every
  /// other failure here, rather than throwing synchronously at the call site
  /// and forcing callers to guard the invocation as well as the await.
  Future<String> manualAdjustment({
    required double amount,
    required String direction,
    required String reason,
    required String userId,
    required String approvedByUserId,
    String? sessionId,
  }) async {
    if (direction != 'in' && direction != 'out') {
      throw ArgumentError("Direction must be 'in' or 'out'");
    }
    if (reason.trim().isEmpty) {
      throw ArgumentError('A manual adjustment must say why');
    }
    return _record(
      direction: direction,
      sourceType: CashMovementSource.manualAdjustment,
      amount: amount,
      reason: reason,
      userId: userId,
      sessionId: sessionId,
      approvedByUserId: approvedByUserId,
      requireApproval: true,
      alwaysRequireApproval: true,
    );
  }

  /// Every manual movement in a shift, newest first — the cash book view a
  /// supervisor reads when a till does not balance.
  Future<List<Map<String, dynamic>>> manualMovementsForSession(String sessionId) async {
    final db = await _dbHelper.database;
    final placeholders = List.filled(CashMovementSource.manualSources.length, '?').join(', ');
    return db.rawQuery(
      '''
      SELECT * FROM cash_movements
      WHERE session_id = ? AND source_type IN ($placeholders)
      ORDER BY created_at DESC
      ''',
      [sessionId, ...CashMovementSource.manualSources],
    );
  }

  // ------------------------------------------------------------------ shared

  Future<String> _record({
    required String direction,
    required String sourceType,
    required double amount,
    required String reason,
    required String userId,
    required bool requireApproval,
    String? sessionId,
    String? counterparty,
    String? approvedByUserId,
    String? expenseAccountCode,
    bool alwaysRequireApproval = false,
  }) async {
    if (amount <= 0) {
      throw ArgumentError('A cash movement must be greater than zero');
    }
    if (reason.trim().isEmpty) {
      throw ArgumentError('A cash movement must say why');
    }

    final db = await _dbHelper.database;
    late String movementId;

    await db.transaction((txn) async {
      if (alwaysRequireApproval) {
        await _approvals.authoriseAlways(
          actionLabel: 'A manual cash adjustment',
          approvedByUserId: approvedByUserId,
          executor: txn,
        );
      } else if (requireApproval) {
        await _approvals.authorise(
          amount: amount,
          actionLabel: 'Cash movement',
          approvedByUserId: approvedByUserId,
          executor: txn,
        );
      } else if (approvedByUserId != null) {
        // Not gated by amount, but a supplied approver is still checked so a
        // bad id cannot be smuggled into the audit trail.
        await _approvals.requireValidApprover(approvedByUserId, executor: txn);
      }

      if (sessionId != null) {
        await _requireOpenSession(sessionId, txn);
      }

      movementId = (await _cashMovements.record(
        direction: direction,
        amount: amount,
        sourceType: sourceType,
        sessionId: sessionId,
        userId: userId,
        note: reason,
        counterparty: counterparty,
        approvedByUserId: approvedByUserId,
        reason: reason,
        executor: txn,
      ))!;

      // Only a categorised payout reaches the ledger — see the class comment
      // for why a drop, a transfer and an uncategorised payout do not.
      if (expenseAccountCode != null) {
        if (direction != 'out') {
          throw ArgumentError('Only cash going out can be booked to an expense account');
        }
        final expense = await _glService.requireAccountByCode(expenseAccountCode, executor: txn);
        if (expense.type != AccountType.expense) {
          throw ArgumentError(
            'Account ${expense.code} (${expense.name}) is a ${expense.type.name} account, not an expense account',
          );
        }
        final cash = await _glService.requireAccountByCode(GLService.cashAccountCode, executor: txn);
        await _glService.postCompoundEntry(
          entryDate: DateTime.now(),
          description: reason,
          referenceType: glReferenceType,
          referenceId: movementId,
          accounts: {expense.id: amount, cash.id: -amount},
          createdBy: userId,
          executor: txn,
        );
      }

      await _dbHelper.logAudit(
        userId: userId,
        actionType: auditAction,
        tableName: 'cash_movements',
        recordId: movementId,
        newValue: jsonEncode({
          'type': sourceType,
          'direction': direction,
          'amount': amount,
          'reason': reason,
          'counterparty': counterparty,
          'sessionId': sessionId,
          'approvedByUserId': approvedByUserId,
          'expenseAccountCode': expenseAccountCode,
        }),
        executor: txn,
      );
    });

    return movementId;
  }

  /// A movement can only be attributed to a shift that is actually open —
  /// otherwise it would change the expected cash of a till already counted and
  /// closed, silently rewriting a reconciliation somebody has signed off.
  Future<void> _requireOpenSession(String sessionId, DatabaseExecutor executor) async {
    final rows = await executor.query(
      'sessions',
      columns: ['status'],
      where: 'id = ?',
      whereArgs: [sessionId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw ArgumentError('No shift with id $sessionId');
    }
    if (rows.first['status'] != 'open') {
      throw StateError('Shift $sessionId is already closed — its cash cannot be changed');
    }
  }
}

final cashManagementServiceProvider =
    Provider<CashManagementService>((ref) => CashManagementService());
