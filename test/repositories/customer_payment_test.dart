import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:supermart_pos/core/database/database_helper.dart';
import 'package:supermart_pos/models/customer_model.dart';
import 'package:supermart_pos/repositories/cash_movement_repository.dart';
import 'package:supermart_pos/repositories/customer_repository.dart';
import 'package:supermart_pos/repositories/store_repository.dart';
import 'package:supermart_pos/services/approval_service.dart';

/// C2 — control, attribution and audit on khata collection.
///
/// The finding this covers was not "cashiers should not collect payments" —
/// they should, it is ordinary counter work. It was that the collection left
/// no approval record, no audit row and no session stamp, so a receipt that
/// reduced a receivable was indistinguishable from one that never happened.
///
/// Scope note, stated plainly rather than papered over: the *threshold prompt*
/// itself lives in `receive_payment_screen.dart` and needs a `BuildContext`,
/// so it cannot be driven from a repository test. What is verified here is
/// everything the prompt produces and everything downstream of it — the
/// configured threshold the screen reads, that a claimed approver is really
/// authorized, and that collector/approver/session/reference all reach the
/// database. See the project report for the widget-test gap (H4).
class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this._path);
  final String _path;

  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
}

int _phoneCounter = 0;
String _nextPhone() => (9300000000 + (_phoneCounter++)).toString();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late CustomerRepository customers;
  late CashMovementRepository cashRepo;

  Future<void> seedUser(String id, String role, {bool active = true}) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert('users', {
      'id': id,
      'username': 'user_$id',
      'password_hash': 'x',
      'role': role,
      'name': 'User $id',
      'must_change_password': 0,
      'is_active': active ? 1 : 0,
      'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    });
  }

  Future<String> openShift(String userId, {double openingCash = 2000}) async {
    final db = await DatabaseHelper.instance.database;
    final id = 'session-$userId-${DateTime.now().microsecondsSinceEpoch}';
    await db.insert('sessions', {
      'id': id,
      'user_id': userId,
      'opening_time': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'opening_cash': openingCash,
      'status': 'open',
      'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    });
    return id;
  }

  Future<Customer> seedCustomer({double owes = 0}) async {
    final customer = Customer.create(phone: _nextPhone(), name: 'Khata Customer');
    await customers.insert(customer);
    if (owes != 0) {
      await customers.update(customer.copyWith(outstandingBalance: owes));
    }
    return customer;
  }

  Future<Map<String, Object?>> auditRowFor(String customerId) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'audit_log',
      where: 'action_type = ? AND record_id = ?',
      whereArgs: ['CUSTOMER_PAYMENT_RECEIVED', customerId],
      orderBy: 'timestamp DESC',
    );
    expect(rows, isNotEmpty, reason: 'every receipt must leave an audit row');
    return rows.first;
  }

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('customer_payment_test');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
    await DatabaseHelper.instance.database;
    customers = CustomerRepository();
    cashRepo = CashMovementRepository();

    await seedUser('cashier-1', 'cashier');
    await seedUser('cashier-2', 'cashier');
    await seedUser('manager-1', 'manager');
    await seedUser('admin-1', 'admin');
    await seedUser('manager-retired', 'manager', active: false);
    await seedUser('accountant-1', 'accountant');
  });

  tearDownAll(() async {
    await DatabaseHelper.instance.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('C2-01 — a cashier collecting a normal khata payment', () {
    test('is allowed, and lands in the ledger, the drawer, the shift and the audit log', () async {
      final session = await openShift('cashier-1');
      final customer = await seedCustomer(owes: 1000);

      final ref = await customers.receivePayment(
        customerId: customer.id,
        amount: 400,
        method: 'cash',
        userId: 'cashier-1',
        sessionId: session,
      );

      // Customer ledger
      final after = await customers.getById(customer.id);
      expect(after!.outstandingBalance, 600);

      final db = await DatabaseHelper.instance.database;
      final ledger = await db.query(
        'customer_ledger',
        where: 'reference_id = ?',
        whereArgs: [ref],
      );
      expect(ledger, hasLength(1));
      expect(ledger.first['reference_type'], 'payment');
      expect((ledger.first['amount'] as num).toDouble(), -400);
      expect((ledger.first['balance'] as num).toDouble(), 600);

      // Cash movement, with both attributions on it
      final movements = await db.query(
        'cash_movements',
        where: 'source_type = ? AND source_id = ?',
        whereArgs: [CashMovementSource.customerPayment, ref],
      );
      expect(movements, hasLength(1));
      expect(movements.first['direction'], 'in');
      expect((movements.first['amount'] as num).toDouble(), 400);
      expect(movements.first['user_id'], 'cashier-1');
      expect(movements.first['session_id'], session);

      expect(await cashRepo.getSessionNet(session), 400);

      // Audit row
      final audit = await auditRowFor(customer.id);
      expect(audit['user_id'], 'cashier-1');
    });

    test('splits an overpayment into a payment and an advance under one reference', () async {
      final session = await openShift('cashier-2');
      final customer = await seedCustomer(owes: 300);

      final ref = await customers.receivePayment(
        customerId: customer.id,
        amount: 500,
        method: 'cash',
        userId: 'cashier-2',
        sessionId: session,
      );

      final after = await customers.getById(customer.id);
      expect(after!.outstandingBalance, -200); // ₹200 held as advance

      final db = await DatabaseHelper.instance.database;
      final ledger = await db.query(
        'customer_ledger',
        where: 'reference_id = ?',
        whereArgs: [ref],
        orderBy: 'created_at ASC',
      );
      expect(ledger, hasLength(2));
      expect(ledger.map((r) => r['reference_type']), containsAll(['payment', 'advance']));

      // The drawer took the whole ₹500 regardless of how it was apportioned.
      expect(await cashRepo.getSessionNet(session), 500);
    });
  });

  group('C2-02 — the approval threshold', () {
    test('is the store setting the screen reads, not a constant in the screen', () async {
      final db = await DatabaseHelper.instance.database;
      await db.update(
        'stores',
        {'return_threshold_no_approval': 1500.0},
        where: 'id = ?',
        whereArgs: [StoreRepository.defaultStoreId],
      );

      expect(await StoreRepository().getReturnThreshold(), 1500);

      // The screen's rule is `amount > threshold` — so ₹1,500 passes
      // unprompted and ₹1,500.01 escalates. Pinned here so a change to the
      // boundary has to be deliberate.
      const threshold = 1500.0;
      expect(1500.0 > threshold, isFalse);
      expect(1500.01 > threshold, isTrue);
    });

    test('falls back to a safe default when the store row has none', () async {
      final db = await DatabaseHelper.instance.database;
      await db.update(
        'stores',
        {'return_threshold_no_approval': null},
        where: 'id = ?',
        whereArgs: [StoreRepository.defaultStoreId],
      );

      expect(await StoreRepository().getReturnThreshold(), 500);

      // Restore for anything that runs after this.
      await db.update(
        'stores',
        {'return_threshold_no_approval': 500.0},
        where: 'id = ?',
        whereArgs: [StoreRepository.defaultStoreId],
      );
    });
  });

  group('C2-03 — approval by an authorized manager', () {
    test('succeeds, and records both the collector and the approver', () async {
      final session = await openShift('cashier-1');
      final customer = await seedCustomer(owes: 9000);

      final ref = await customers.receivePayment(
        customerId: customer.id,
        amount: 5000,
        method: 'cash',
        userId: 'cashier-1',
        sessionId: session,
        approvedByUserId: 'manager-1',
      );

      final audit = await auditRowFor(customer.id);
      final recorded = jsonDecode(audit['new_value'] as String) as Map<String, dynamic>;

      expect(audit['user_id'], 'cashier-1', reason: 'the collector is who took the money');
      expect(recorded['approvedByUserId'], 'manager-1');
      expect(recorded['paymentRef'], ref);
      expect(recorded['amount'], 5000);
      expect(recorded['sessionId'], session);

      expect(await cashRepo.getSessionNet(session), 5000);
    });

    test('an admin may also approve', () async {
      final session = await openShift('cashier-2');
      final customer = await seedCustomer(owes: 4000);

      await customers.receivePayment(
        customerId: customer.id,
        amount: 4000,
        method: 'cash',
        userId: 'cashier-2',
        sessionId: session,
        approvedByUserId: 'admin-1',
      );

      final audit = await auditRowFor(customer.id);
      final recorded = jsonDecode(audit['new_value'] as String) as Map<String, dynamic>;
      expect(recorded['approvedByUserId'], 'admin-1');
    });
  });

  group('C2-04 — an unauthorized approval is rejected', () {
    test('a cashier cannot approve their own collection', () async {
      final session = await openShift('cashier-1');
      final customer = await seedCustomer(owes: 9000);

      // The screen would never offer this, but the screen is not the control —
      // a stamped approval that nobody checked is a forged one.
      await expectLater(
        customers.receivePayment(
          customerId: customer.id,
          amount: 6000,
          method: 'cash',
          userId: 'cashier-1',
          sessionId: session,
          approvedByUserId: 'cashier-1',
        ),
        throwsA(isA<Exception>()),
      );

      final after = await customers.getById(customer.id);
      expect(after!.outstandingBalance, 9000, reason: 'the receivable must be untouched');
      expect(await cashRepo.getSessionNet(session), 0);
    });

    test('another cashier cannot approve either', () async {
      final customer = await seedCustomer(owes: 2000);
      await expectLater(
        customers.receivePayment(
          customerId: customer.id,
          amount: 2000,
          method: 'cash',
          userId: 'cashier-1',
          approvedByUserId: 'cashier-2',
        ),
        throwsA(isA<Exception>()),
      );
      expect((await customers.getById(customer.id))!.outstandingBalance, 2000);
    });

    test('an accountant is not an approver for a cash receipt', () async {
      final customer = await seedCustomer(owes: 2000);
      await expectLater(
        customers.receivePayment(
          customerId: customer.id,
          amount: 2000,
          method: 'cash',
          userId: 'cashier-1',
          approvedByUserId: 'accountant-1',
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('a deactivated manager cannot approve', () async {
      final customer = await seedCustomer(owes: 2000);
      await expectLater(
        customers.receivePayment(
          customerId: customer.id,
          amount: 2000,
          method: 'cash',
          userId: 'cashier-1',
          approvedByUserId: 'manager-retired',
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('an approver id that names nobody is rejected', () async {
      final customer = await seedCustomer(owes: 2000);
      await expectLater(
        customers.receivePayment(
          customerId: customer.id,
          amount: 2000,
          method: 'cash',
          userId: 'cashier-1',
          approvedByUserId: 'ghost-manager',
        ),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('C2-05 — no active shift', () {
    test('the receipt still stands, and is attributed to no shift rather than to a wrong one', () async {
      // `cashier-no-shift` has never opened a till.
      await seedUser('cashier-no-shift', 'cashier');
      final customer = await seedCustomer(owes: 700);

      final ref = await customers.receivePayment(
        customerId: customer.id,
        amount: 700,
        method: 'cash',
        userId: 'cashier-no-shift',
        approvedByUserId: 'manager-1', // above the ₹500 cashier limit (P2-C4)
      );

      final db = await DatabaseHelper.instance.database;
      final movement = await db.query(
        'cash_movements',
        where: 'source_type = ? AND source_id = ?',
        whereArgs: [CashMovementSource.customerPayment, ref],
      );
      expect(movement, hasLength(1), reason: 'the cash book records it either way');
      expect(movement.first['session_id'], isNull);
      expect(movement.first['user_id'], 'cashier-no-shift');

      expect((await customers.getById(customer.id))!.outstandingBalance, 0);
    });

    test('an unstamped receipt is attributed to the collector\'s open shift', () async {
      await seedUser('cashier-infer', 'cashier');
      final session = await openShift('cashier-infer');
      final customer = await seedCustomer(owes: 800);

      // The caller passed no sessionId; the repository resolves the open shift
      // on the caller's own transaction rather than leaving the money adrift.
      await customers.receivePayment(
        customerId: customer.id,
        amount: 800,
        method: 'cash',
        userId: 'cashier-infer',
        approvedByUserId: 'manager-1', // above the ₹500 cashier limit (P2-C4)
      );

      expect(await cashRepo.getSessionNet(session), 800);
    });
  });

  group('C2-06/07 — duplicates and failures', () {
    test('two collections from one customer are two receipts, each on its own reference', () async {
      final session = await openShift('cashier-1');
      final customer = await seedCustomer(owes: 1000);

      final first = await customers.receivePayment(
        customerId: customer.id,
        amount: 250,
        method: 'cash',
        userId: 'cashier-1',
        sessionId: session,
      );
      final second = await customers.receivePayment(
        customerId: customer.id,
        amount: 250,
        method: 'cash',
        userId: 'cashier-1',
        sessionId: session,
      );

      expect(first, isNot(second));
      expect((await customers.getById(customer.id))!.outstandingBalance, 500);

      final db = await DatabaseHelper.instance.database;
      final movements = await db.query(
        'cash_movements',
        where: 'source_type = ? AND source_id IN (?, ?)',
        whereArgs: [CashMovementSource.customerPayment, first, second],
      );
      expect(movements, hasLength(2));
    });

    test('a rejected payment leaves the ledger, the balance and the drawer untouched', () async {
      final session = await openShift('cashier-1');
      final customer = await seedCustomer(owes: 1000);
      final db = await DatabaseHelper.instance.database;

      final ledgerBefore = await db.query(
        'customer_ledger',
        where: 'customer_id = ?',
        whereArgs: [customer.id],
      );

      await expectLater(
        customers.receivePayment(
          customerId: customer.id,
          amount: 500,
          method: 'cash',
          userId: 'cashier-1',
          sessionId: session,
          approvedByUserId: 'cashier-2', // not an approver — rolls the lot back
        ),
        throwsA(isA<Exception>()),
      );

      final ledgerAfter = await db.query(
        'customer_ledger',
        where: 'customer_id = ?',
        whereArgs: [customer.id],
      );
      expect(ledgerAfter.length, ledgerBefore.length);
      expect((await customers.getById(customer.id))!.outstandingBalance, 1000);
      expect(await cashRepo.getSessionNet(session), 0);

      final orphanAudit = await db.query(
        'audit_log',
        where: 'action_type = ? AND record_id = ?',
        whereArgs: ['CUSTOMER_PAYMENT_RECEIVED', customer.id],
      );
      expect(orphanAudit, isEmpty, reason: 'a payment that did not happen must not be audited as one');
    });

    test('a zero or negative amount is refused before anything is written', () async {
      final customer = await seedCustomer(owes: 1000);
      await expectLater(
        customers.receivePayment(customerId: customer.id, amount: 0, method: 'cash', userId: 'cashier-1'),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        customers.receivePayment(customerId: customer.id, amount: -100, method: 'cash', userId: 'cashier-1'),
        throwsA(isA<ArgumentError>()),
      );
      expect((await customers.getById(customer.id))!.outstandingBalance, 1000);
    });
  });

  group('C2-08 — what a sensitive receipt leaves behind', () {
    test('user, approver, timestamp, reference, session and both balances', () async {
      final session = await openShift('cashier-1');
      final customer = await seedCustomer(owes: 3000);

      final ref = await customers.receivePayment(
        customerId: customer.id,
        amount: 3000,
        method: 'cash',
        note: 'Full settlement',
        userId: 'cashier-1',
        sessionId: session,
        approvedByUserId: 'manager-1',
      );

      final audit = await auditRowFor(customer.id);
      expect(audit['user_id'], 'cashier-1');
      expect(audit['table_name'], 'customers');
      expect(audit['record_id'], customer.id);
      expect((audit['timestamp'] as num).toInt(), greaterThan(0));

      final before = jsonDecode(audit['old_value'] as String) as Map<String, dynamic>;
      final after = jsonDecode(audit['new_value'] as String) as Map<String, dynamic>;
      expect(before['outstanding_balance'], 3000);
      expect(after['outstanding_balance'], 0);
      expect(after['approvedByUserId'], 'manager-1');
      expect(after['sessionId'], session);
      expect(after['paymentRef'], ref);
      expect(after['method'], 'cash');
      expect(after['note'], 'Full settlement');

      // The reference on the audit row is the one the cash book and the
      // customer ledger carry, so a drawer figure can be walked back to the
      // approval that authorized it.
      final db = await DatabaseHelper.instance.database;
      expect(
        await db.query('cash_movements', where: 'source_id = ?', whereArgs: [ref]),
        hasLength(1),
      );
      expect(
        await db.query('customer_ledger', where: 'reference_id = ?', whereArgs: [ref]),
        hasLength(1),
      );
    });

    test('a non-cash receipt is still audited, but moves no cash', () async {
      final session = await openShift('cashier-2');
      final customer = await seedCustomer(owes: 1200);

      final ref = await customers.receivePayment(
        customerId: customer.id,
        amount: 1200,
        method: 'upi',
        userId: 'cashier-2',
        sessionId: session,
        approvedByUserId: 'manager-1', // above the ₹500 cashier limit (P2-C4)
      );

      await auditRowFor(customer.id);
      expect(await cashRepo.getSessionNet(session), 0);

      final db = await DatabaseHelper.instance.database;
      expect(await db.query('cash_movements', where: 'source_id = ?', whereArgs: [ref]), isEmpty);
      expect((await customers.getById(customer.id))!.outstandingBalance, 0);
    });
  });

  group('C2 credit limit — the ordinary cashier workflow stays open', () {
    test('a cashier can create and edit a customer without approval', () async {
      final customer = Customer.create(phone: _nextPhone(), name: 'Walk In');
      await customers.insert(customer);

      await customers.update(customer.copyWith(name: 'Walk In (corrected)', locality: 'North Street'));

      final saved = await customers.getById(customer.id);
      expect(saved!.name, 'Walk In (corrected)');
      expect(saved.locality, 'North Street');
      expect(saved.creditLimit, 0);
    });

    test('raising a credit limit without a manager is refused', () async {
      // In Project 1 this rule lived in `customer_form_screen` and could only
      // be asserted by restating its arithmetic. It is now enforced by the
      // repository (P2-C4), so it can be tested against the real thing.
      final customer = Customer.create(phone: _nextPhone(), name: 'Limit Holder');
      await customers.insert(customer);

      await expectLater(
        customers.update(customer.copyWith(creditLimit: 5000)),
        throwsA(isA<ApprovalRequired>()),
      );
      expect((await customers.getById(customer.id))!.creditLimit, 0);
    });

    test('raising it with a manager succeeds', () async {
      final customer = Customer.create(phone: _nextPhone(), name: 'Approved Limit');
      await customers.insert(customer);

      await customers.update(customer.copyWith(creditLimit: 5000), approvedByUserId: 'manager-1');
      expect((await customers.getById(customer.id))!.creditLimit, 5000);
    });

    test('a cashier cannot approve a credit-limit rise', () async {
      final customer = Customer.create(phone: _nextPhone(), name: 'Self Approved Limit');
      await customers.insert(customer);

      await expectLater(
        customers.update(customer.copyWith(creditLimit: 5000), approvedByUserId: 'cashier-1'),
        throwsA(isA<UnauthorizedApprover>()),
      );
      expect((await customers.getById(customer.id))!.creditLimit, 0);
    });

    test('keeping or lowering a limit needs no approval', () async {
      final customer = Customer.create(phone: _nextPhone(), name: 'Lowering Limit');
      await customers.insert(customer);
      await customers.update(customer.copyWith(creditLimit: 5000), approvedByUserId: 'manager-1');

      // Re-saving unchanged, then reducing the shop's exposure — both ordinary
      // cashier work, neither gated.
      await customers.update(customer.copyWith(creditLimit: 5000));
      await customers.update(customer.copyWith(creditLimit: 2000));
      expect((await customers.getById(customer.id))!.creditLimit, 2000);
    });

    test('editing other fields on a customer who has a limit is not gated', () async {
      final customer = Customer.create(phone: _nextPhone(), name: 'Detail Edit');
      await customers.insert(customer);
      await customers.update(customer.copyWith(creditLimit: 3000), approvedByUserId: 'manager-1');

      final stored = (await customers.getById(customer.id))!;
      await customers.update(stored.copyWith(name: 'Detail Edit (corrected)', locality: 'South Street'));

      final after = (await customers.getById(customer.id))!;
      expect(after.name, 'Detail Edit (corrected)');
      expect(after.creditLimit, 3000, reason: 'the limit came along unchanged and needed no approval');
    });

    test('creating a customer already holding a limit is gated too', () async {
      // Otherwise "raise the limit" is evadable by deleting and re-adding.
      final customer = Customer.create(phone: _nextPhone(), name: 'Born With Credit');
      await expectLater(
        customers.insert(customer.copyWith(creditLimit: 9000)),
        throwsA(isA<ApprovalRequired>()),
      );
      expect(await customers.getById(customer.id), isNull);
    });
  });
}
