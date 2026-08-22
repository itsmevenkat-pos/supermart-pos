import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:supermart_pos/core/database/database_helper.dart';
import 'package:supermart_pos/repositories/cash_movement_repository.dart';
import 'package:supermart_pos/services/approval_service.dart';
import 'package:supermart_pos/services/cash_management_service.dart';
import 'package:supermart_pos/services/counter_service.dart';
import 'package:supermart_pos/services/gl_service.dart';

/// P2-C3 — manual cash management.
///
/// Project 1 found `CashMovementSource.manualAdjustment` defined with no
/// writer: real money left tills for reasons the system could not express, and
/// every one of those surfaced as an unexplained shortage. These cover the
/// vocabulary that closes that, and the controls on it.
///
/// Accounting decision AD-5 governs what reaches the GL: a drop and a transfer
/// move cash from one place to another and, with one Cash account in the chart
/// of accounts, have no GL consequence at all. Only a categorised payout posts.
class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this._path);
  final String _path;

  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late CashManagementService cash;
  late CashMovementRepository book;
  late String cashAccountId;

  int userCounter = 0;
  Future<String> newUser(String role) async {
    final db = await DatabaseHelper.instance.database;
    final id = '$role-${userCounter++}';
    await db.insert('users', {
      'id': id,
      'username': 'user_$id',
      'password_hash': 'x',
      'role': role,
      'name': 'User $id',
      'must_change_password': 0,
      'is_active': 1,
      'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    });
    return id;
  }

  Future<double> netDebit(String accountId) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.rawQuery(
      'SELECT COALESCE(SUM(debit) - SUM(credit), 0) AS net FROM gl_entries WHERE account_id = ?',
      [accountId],
    );
    return (rows.first['net'] as num).toDouble();
  }

  Future<Map<String, Object?>> movement(String id) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query('cash_movements', where: 'id = ?', whereArgs: [id]);
    expect(rows, hasLength(1));
    return rows.first;
  }

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('cash_management_test');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
    await DatabaseHelper.instance.database;
    cash = CashManagementService();
    book = CashMovementRepository();
    cashAccountId = (await GLService().requireAccountByCode(GLService.cashAccountCode)).id;
  });

  tearDownAll(() async {
    await DatabaseHelper.instance.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('the v35 columns exist and carry what a manual movement needs', () {
    test('cash_movements has counterparty, approver and reason', () async {
      final db = await DatabaseHelper.instance.database;
      final columns = (await db.rawQuery('PRAGMA table_info(cash_movements)'))
          .map((row) => row['name'] as String)
          .toSet();
      expect(columns, containsAll(['counterparty', 'approved_by_user_id', 'reason']));
      // The v34 columns are untouched — this was an additive migration.
      expect(
        columns,
        containsAll(['id', 'session_id', 'direction', 'amount', 'source_type', 'source_id', 'user_id', 'note']),
      );
    });

    test('a sale-driven movement leaves the manual columns null', () async {
      final cashier = await newUser('cashier');
      final session = await CounterService().openShift(userId: cashier, openingCash: 1000);
      final db = await DatabaseHelper.instance.database;

      final id = await book.recordIn(
        amount: 100,
        sourceType: CashMovementSource.sale,
        sourceId: 'some-sale',
        sessionId: session.id,
        userId: cashier,
        executor: db,
      );

      final row = await movement(id!);
      expect(row['counterparty'], isNull);
      expect(row['approved_by_user_id'], isNull);
      expect(row['reason'], isNull);
    });
  });

  group('P2-C3 — cash in', () {
    test('increases what the shift must account for, with a reason and an audit row', () async {
      final cashier = await newUser('cashier');
      final session = await CounterService().openShift(userId: cashier, openingCash: 2000);

      final id = await cash.cashIn(
        amount: 300,
        reason: 'Petty cash returned unspent',
        userId: cashier,
        sessionId: session.id,
      );

      expect(await book.getSessionNet(session.id), 300);

      final row = await movement(id);
      expect(row['direction'], 'in');
      expect(row['source_type'], CashMovementSource.cashIn);
      expect(row['reason'], 'Petty cash returned unspent');
      expect(row['user_id'], cashier);
      expect(row['session_id'], session.id);

      final db = await DatabaseHelper.instance.database;
      final audit = await db.query(
        'audit_log',
        where: 'action_type = ? AND record_id = ?',
        whereArgs: [CashManagementService.auditAction, id],
      );
      expect(audit, hasLength(1));
      expect(audit.first['user_id'], cashier);
    });

    test('posts nothing to the GL — the cash was already in the Cash account', () async {
      final cashier = await newUser('cashier');
      final session = await CounterService().openShift(userId: cashier, openingCash: 1000);
      final before = await netDebit(cashAccountId);

      await cash.cashIn(amount: 250, reason: 'Float correction', userId: cashier, sessionId: session.id);

      expect(await netDebit(cashAccountId), closeTo(before, 0.01));
    });

    test('a movement with no reason is refused', () async {
      final cashier = await newUser('cashier');
      await expectLater(
        cash.cashIn(amount: 100, reason: '   ', userId: cashier),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('P2-C3 — cash out', () {
    test('below the discretion limit a cashier may pay out alone', () async {
      final cashier = await newUser('cashier');
      final session = await CounterService().openShift(userId: cashier, openingCash: 2000);

      final id = await cash.cashOut(
        amount: 200,
        reason: 'Delivery driver fuel',
        userId: cashier,
        sessionId: session.id,
        counterparty: 'Delivery driver',
      );

      expect(await book.getSessionNet(session.id), -200);
      final row = await movement(id);
      expect(row['direction'], 'out');
      expect(row['counterparty'], 'Delivery driver');
      expect(row['approved_by_user_id'], isNull);
    });

    test('above the limit without an approver is refused, and leaves the drawer alone', () async {
      final cashier = await newUser('cashier');
      final session = await CounterService().openShift(userId: cashier, openingCash: 5000);

      await expectLater(
        cash.cashOut(amount: 2000, reason: 'Supplier paid in notes', userId: cashier, sessionId: session.id),
        throwsA(isA<ApprovalRequired>()),
      );

      expect(await book.getSessionNet(session.id), 0);
      final db = await DatabaseHelper.instance.database;
      expect(
        await db.query('cash_movements', where: 'session_id = ?', whereArgs: [session.id]),
        isEmpty,
      );
    });

    test('above the limit with a manager succeeds and records the approver', () async {
      final cashier = await newUser('cashier');
      final manager = await newUser('manager');
      final session = await CounterService().openShift(userId: cashier, openingCash: 5000);

      final id = await cash.cashOut(
        amount: 2000,
        reason: 'Supplier paid in notes',
        userId: cashier,
        sessionId: session.id,
        approvedByUserId: manager,
      );

      expect(await book.getSessionNet(session.id), -2000);
      final row = await movement(id);
      expect(row['approved_by_user_id'], manager);
      expect(row['user_id'], cashier, reason: 'the collector and the approver are different people');
    });

    test('a cashier cannot approve their own payout', () async {
      final cashier = await newUser('cashier');
      final session = await CounterService().openShift(userId: cashier, openingCash: 5000);

      await expectLater(
        cash.cashOut(
          amount: 2000,
          reason: 'Self-approved',
          userId: cashier,
          sessionId: session.id,
          approvedByUserId: cashier,
        ),
        throwsA(isA<UnauthorizedApprover>()),
      );
      expect(await book.getSessionNet(session.id), 0);
    });

    test('booked to an expense account it posts Dr expense / Cr Cash', () async {
      final cashier = await newUser('cashier');
      final session = await CounterService().openShift(userId: cashier, openingCash: 2000);
      final utilities = await GLService().requireAccountByCode('5300');

      final cashBefore = await netDebit(cashAccountId);
      final utilitiesBefore = await netDebit(utilities.id);

      final id = await cash.cashOut(
        amount: 400,
        reason: 'Electricity bill paid in cash',
        userId: cashier,
        sessionId: session.id,
        expenseAccountCode: '5300',
      );

      expect(await netDebit(cashAccountId), closeTo(cashBefore - 400, 0.01));
      expect(await netDebit(utilities.id), closeTo(utilitiesBefore + 400, 0.01));
      expect(await book.getSessionNet(session.id), -400);

      // GL Cash and the cash book moved by the same amount — the invariant
      // this project exists to protect.
      final db = await DatabaseHelper.instance.database;
      final glRows = await db.query(
        'gl_entries',
        where: 'reference_type = ? AND reference_id = ?',
        whereArgs: [CashManagementService.glReferenceType, id],
      );
      expect(glRows, hasLength(2));
    });

    test('a non-expense account is refused rather than posted to', () async {
      final cashier = await newUser('cashier');
      final session = await CounterService().openShift(userId: cashier, openingCash: 2000);

      await expectLater(
        cash.cashOut(
          amount: 100,
          reason: 'Miscategorised',
          userId: cashier,
          sessionId: session.id,
          expenseAccountCode: GLService.salesRevenueAccountCode, // revenue, not expense
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(await book.getSessionNet(session.id), 0);
    });
  });

  group('P2-C3 — cash drop', () {
    test('reduces the shift, names the destination, and posts nothing to the GL', () async {
      final cashier = await newUser('cashier');
      final manager = await newUser('manager');
      final session = await CounterService().openShift(userId: cashier, openingCash: 2000);
      final glBefore = await netDebit(cashAccountId);

      final id = await cash.cashDrop(
        amount: 5000,
        userId: cashier,
        destination: 'Main safe',
        sessionId: session.id,
        approvedByUserId: manager,
      );

      expect(await book.getSessionNet(session.id), -5000);
      final row = await movement(id);
      expect(row['source_type'], CashMovementSource.cashDrop);
      expect(row['counterparty'], 'Main safe');
      expect(row['approved_by_user_id'], manager);

      // AD-5: the money is still cash, just in a different place. Inventing a
      // "Cash in Safe" account to make this look like accounting was the
      // alternative, and was ruled out.
      expect(await netDebit(cashAccountId), closeTo(glBefore, 0.01));
    });

    test('a shift that has already closed cannot have cash dropped from it', () async {
      final cashier = await newUser('cashier');
      final manager = await newUser('manager');
      final session = await CounterService().openShift(userId: cashier, openingCash: 2000);
      await CounterService().closeShift(sessionId: session.id, closingCash: 2000, denominations: null);

      await expectLater(
        cash.cashDrop(
          amount: 100,
          userId: cashier,
          destination: 'Main safe',
          sessionId: session.id,
          approvedByUserId: manager,
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('P2-C3 — cash transfer', () {
    test('moves cash between two shifts atomically, each leg naming the other', () async {
      final cashierA = await newUser('cashier');
      final cashierB = await newUser('cashier');
      final manager = await newUser('manager');
      final sessionA = await CounterService().openShift(userId: cashierA, openingCash: 3000);
      final sessionB = await CounterService().openShift(userId: cashierB, openingCash: 500);
      final glBefore = await netDebit(cashAccountId);

      final (outId, inId) = await cash.cashTransfer(
        amount: 1000,
        userId: cashierA,
        fromSessionId: sessionA.id,
        toSessionId: sessionB.id,
        reason: 'Counter 2 ran out of change',
        approvedByUserId: manager,
      );

      expect(await book.getSessionNet(sessionA.id), -1000);
      expect(await book.getSessionNet(sessionB.id), 1000);

      final out = await movement(outId);
      final into = await movement(inId);
      expect(out['counterparty'], sessionB.id);
      expect(into['counterparty'], sessionA.id);
      // The receiving leg points back at the leg that sent it, so a transfer
      // can be matched to its pair rather than inferred from timing.
      expect(into['source_id'], outId);

      // No GL effect: the cash never left the business.
      expect(await netDebit(cashAccountId), closeTo(glBefore, 0.01));
    });

    test('a transfer into a closed shift moves nothing at all', () async {
      final cashierA = await newUser('cashier');
      final cashierB = await newUser('cashier');
      final manager = await newUser('manager');
      final sessionA = await CounterService().openShift(userId: cashierA, openingCash: 3000);
      final sessionB = await CounterService().openShift(userId: cashierB, openingCash: 500);
      await CounterService().closeShift(sessionId: sessionB.id, closingCash: 500, denominations: null);

      await expectLater(
        cash.cashTransfer(
          amount: 1000,
          userId: cashierA,
          fromSessionId: sessionA.id,
          toSessionId: sessionB.id,
          approvedByUserId: manager,
        ),
        throwsA(isA<StateError>()),
      );

      // Critically, the sending leg did not survive the failure of the
      // receiving one — that would have destroyed ₹1,000.
      expect(await book.getSessionNet(sessionA.id), 0);
    });

    test('a transfer to the same shift is refused', () async {
      final cashier = await newUser('cashier');
      final session = await CounterService().openShift(userId: cashier, openingCash: 1000);
      await expectLater(
        cash.cashTransfer(
          amount: 100,
          userId: cashier,
          fromSessionId: session.id,
          toSessionId: session.id,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('P2-C3 — manual adjustment', () {
    test('always needs a manager, however small', () async {
      final cashier = await newUser('cashier');
      final session = await CounterService().openShift(userId: cashier, openingCash: 2000);

      // ₹10 is far below the discretion limit — this is refused on principle,
      // not on amount. An unrestricted "make it balance" operation would undo
      // the whole reconciliation control.
      await expectLater(
        () => cash.manualAdjustment(
          amount: 10,
          direction: 'out',
          reason: 'Till reads short',
          userId: cashier,
          approvedByUserId: '',
          sessionId: session.id,
        ),
        throwsA(isA<UnauthorizedApprover>()),
      );
      expect(await book.getSessionNet(session.id), 0);
    });

    test('a cashier cannot approve their own adjustment', () async {
      final cashier = await newUser('cashier');
      final session = await CounterService().openShift(userId: cashier, openingCash: 2000);

      await expectLater(
        cash.manualAdjustment(
          amount: 500,
          direction: 'out',
          reason: 'Making it balance',
          userId: cashier,
          approvedByUserId: cashier,
          sessionId: session.id,
        ),
        throwsA(isA<UnauthorizedApprover>()),
      );
      expect(await book.getSessionNet(session.id), 0);
    });

    test('with a manager it records, with the reason and both people named', () async {
      final cashier = await newUser('cashier');
      final manager = await newUser('manager');
      final session = await CounterService().openShift(userId: cashier, openingCash: 2000);

      final id = await cash.manualAdjustment(
        amount: 50,
        direction: 'out',
        reason: 'Counted short after recount; written off',
        userId: cashier,
        approvedByUserId: manager,
        sessionId: session.id,
      );

      expect(await book.getSessionNet(session.id), -50);
      final row = await movement(id);
      expect(row['source_type'], CashMovementSource.manualAdjustment);
      expect(row['user_id'], cashier);
      expect(row['approved_by_user_id'], manager);
      expect(row['reason'], 'Counted short after recount; written off');

      final db = await DatabaseHelper.instance.database;
      final audit = await db.query(
        'audit_log',
        where: 'action_type = ? AND record_id = ?',
        whereArgs: [CashManagementService.auditAction, id],
      );
      final recorded = jsonDecode(audit.first['new_value'] as String) as Map<String, dynamic>;
      expect(recorded['approvedByUserId'], manager);
      expect(recorded['reason'], 'Counted short after recount; written off');
    });

    test('an adjustment with no reason is refused', () async {
      final cashier = await newUser('cashier');
      final manager = await newUser('manager');
      await expectLater(
        cash.manualAdjustment(
          amount: 50,
          direction: 'out',
          reason: '  ',
          userId: cashier,
          approvedByUserId: manager,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('P2-C3 — reconciliation with the shift', () {
    test('a shift with drops, payouts and top-ups still closes to the cash book', () async {
      final cashier = await newUser('cashier');
      final manager = await newUser('manager');
      final session = await CounterService().openShift(userId: cashier, openingCash: 2000);

      await cash.cashIn(amount: 300, reason: 'Petty cash back', userId: cashier, sessionId: session.id);
      await cash.cashOut(amount: 200, reason: 'Driver fuel', userId: cashier, sessionId: session.id);
      await cash.cashDrop(
        amount: 1000,
        userId: cashier,
        destination: 'Main safe',
        sessionId: session.id,
        approvedByUserId: manager,
      );

      // 2,000 + 300 − 200 − 1,000 = 1,100.
      final expected = 2000 + await book.getSessionNet(session.id);
      final closed = await CounterService().closeShift(
        sessionId: session.id,
        closingCash: 1100,
        denominations: null,
      );

      expect(expected, 1100);
      expect(closed.expectedCash, 1100);
      expect(closed.difference, 0);

      // And the manual movements are retrievable as their own view.
      final manual = await cash.manualMovementsForSession(session.id);
      expect(manual, hasLength(3));
      expect(
        manual.map((m) => m['source_type']),
        containsAll([CashMovementSource.cashIn, CashMovementSource.cashOut, CashMovementSource.cashDrop]),
      );
    });
  });
}
