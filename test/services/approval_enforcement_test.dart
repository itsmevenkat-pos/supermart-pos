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

/// P2-C4 — the approval threshold is a property of the operation, not of the
/// screen that happens to invoke it.
///
/// Project 1 moved approver *validation* into the repository but left the
/// threshold decision in `receive_payment_screen`: the screen read the store
/// setting, compared it, and showed a dialog. Anything that did not go through
/// that screen — a future screen, a bulk tool, a sync handler, a test, this
/// file — could take a receipt of any size with no approver at all. That is
/// what these cover.
///
/// The rule is deliberately exercised through `CustomerRepository.receivePayment`
/// rather than only against `ApprovalService` in isolation, because "the
/// service is authoritative" is a claim about the *call path*, and a unit test
/// of the guard alone would not have caught the original defect.
class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this._path);
  final String _path;

  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
}

int _phoneCounter = 0;
String _nextPhone() => (9700000000 + (_phoneCounter++)).toString();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late CustomerRepository customers;
  late ApprovalService approvals;

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

  Future<Customer> seedCustomer({double owes = 0}) async {
    final customer = Customer.create(phone: _nextPhone(), name: 'Approval Customer');
    await customers.insert(customer);
    if (owes != 0) {
      await customers.update(customer.copyWith(outstandingBalance: owes));
    }
    return customer;
  }

  /// Asserts nothing at all was written for [customer] — the whole point of
  /// running the guard inside the transaction.
  Future<void> expectNothingRecorded(Customer customer, double originalBalance) async {
    final db = await DatabaseHelper.instance.database;
    expect((await customers.getById(customer.id))!.outstandingBalance, originalBalance);
    expect(
      await db.query('customer_ledger', where: 'customer_id = ?', whereArgs: [customer.id]),
      isEmpty,
    );
    expect(
      await db.query(
        'audit_log',
        where: 'action_type = ? AND record_id = ?',
        whereArgs: ['CUSTOMER_PAYMENT_RECEIVED', customer.id],
      ),
      isEmpty,
    );
  }

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('approval_enforcement_test');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
    await DatabaseHelper.instance.database;
    customers = CustomerRepository();
    approvals = ApprovalService();

    await seedUser('appr-cashier', 'cashier');
    await seedUser('appr-cashier-2', 'cashier');
    await seedUser('appr-manager', 'manager');
    await seedUser('appr-admin', 'admin');
    await seedUser('appr-accountant', 'accountant');
    await seedUser('appr-manager-inactive', 'manager', active: false);
  });

  tearDownAll(() async {
    await DatabaseHelper.instance.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('P2-C4 — the threshold', () {
    test('is read from store settings, not hardcoded', () async {
      expect(await approvals.cashierDiscretionLimit(), await StoreRepository().getReturnThreshold());
      expect(await approvals.cashierDiscretionLimit(), 500);
    });

    test('below the threshold: a cashier acts alone', () async {
      final customer = await seedCustomer(owes: 1000);
      await customers.receivePayment(
        customerId: customer.id,
        amount: 499,
        method: 'cash',
        userId: 'appr-cashier',
      );
      expect((await customers.getById(customer.id))!.outstandingBalance, 501);
    });

    test('exactly at the threshold: still no approval needed', () async {
      final customer = await seedCustomer(owes: 1000);
      // The boundary is `amount > limit`, matching what the screen always did.
      await customers.receivePayment(
        customerId: customer.id,
        amount: 500,
        method: 'cash',
        userId: 'appr-cashier',
      );
      expect((await customers.getById(customer.id))!.outstandingBalance, 500);
    });

    test('a rupee above the threshold: refused without an approver', () async {
      final customer = await seedCustomer(owes: 1000);
      await expectLater(
        customers.receivePayment(
          customerId: customer.id,
          amount: 500.01,
          method: 'cash',
          userId: 'appr-cashier',
        ),
        throwsA(isA<ApprovalRequired>()),
      );
      await expectNothingRecorded(customer, 1000);
    });

    test('a changed store threshold changes the rule immediately', () async {
      final db = await DatabaseHelper.instance.database;
      await db.update(
        'stores',
        {'return_threshold_no_approval': 2000.0},
        where: 'id = ?',
        whereArgs: [StoreRepository.defaultStoreId],
      );
      addTearDown(() async {
        await db.update(
          'stores',
          {'return_threshold_no_approval': 500.0},
          where: 'id = ?',
          whereArgs: [StoreRepository.defaultStoreId],
        );
      });

      // ₹1,500 would have needed a manager a moment ago and now does not.
      final customer = await seedCustomer(owes: 3000);
      await customers.receivePayment(
        customerId: customer.id,
        amount: 1500,
        method: 'cash',
        userId: 'appr-cashier',
      );
      expect((await customers.getById(customer.id))!.outstandingBalance, 1500);
    });
  });

  group('P2-C4 — who may approve', () {
    test('a manager may', () async {
      final customer = await seedCustomer(owes: 5000);
      await customers.receivePayment(
        customerId: customer.id,
        amount: 3000,
        method: 'cash',
        userId: 'appr-cashier',
        approvedByUserId: 'appr-manager',
      );
      expect((await customers.getById(customer.id))!.outstandingBalance, 2000);
    });

    test('an admin may', () async {
      final customer = await seedCustomer(owes: 5000);
      await customers.receivePayment(
        customerId: customer.id,
        amount: 3000,
        method: 'cash',
        userId: 'appr-cashier',
        approvedByUserId: 'appr-admin',
      );
      expect((await customers.getById(customer.id))!.outstandingBalance, 2000);
    });

    test('a cashier may not approve their own receipt', () async {
      final customer = await seedCustomer(owes: 5000);
      await expectLater(
        customers.receivePayment(
          customerId: customer.id,
          amount: 3000,
          method: 'cash',
          userId: 'appr-cashier',
          approvedByUserId: 'appr-cashier',
        ),
        throwsA(isA<UnauthorizedApprover>()),
      );
      await expectNothingRecorded(customer, 5000);
    });

    test('another cashier may not either', () async {
      final customer = await seedCustomer(owes: 5000);
      await expectLater(
        customers.receivePayment(
          customerId: customer.id,
          amount: 3000,
          method: 'cash',
          userId: 'appr-cashier',
          approvedByUserId: 'appr-cashier-2',
        ),
        throwsA(isA<UnauthorizedApprover>()),
      );
      await expectNothingRecorded(customer, 5000);
    });

    test('an accountant may not', () async {
      final customer = await seedCustomer(owes: 5000);
      await expectLater(
        customers.receivePayment(
          customerId: customer.id,
          amount: 3000,
          method: 'cash',
          userId: 'appr-cashier',
          approvedByUserId: 'appr-accountant',
        ),
        throwsA(isA<UnauthorizedApprover>()),
      );
    });

    test('a deactivated manager may not', () async {
      final customer = await seedCustomer(owes: 5000);
      await expectLater(
        customers.receivePayment(
          customerId: customer.id,
          amount: 3000,
          method: 'cash',
          userId: 'appr-cashier',
          approvedByUserId: 'appr-manager-inactive',
        ),
        throwsA(isA<UnauthorizedApprover>()),
      );
    });

    test('an id that names nobody may not', () async {
      final customer = await seedCustomer(owes: 5000);
      await expectLater(
        customers.receivePayment(
          customerId: customer.id,
          amount: 3000,
          method: 'cash',
          userId: 'appr-cashier',
          approvedByUserId: 'no-such-person',
        ),
        throwsA(isA<UnauthorizedApprover>()),
      );
      await expectNothingRecorded(customer, 5000);
    });

    test('a forged approver is rejected even below the threshold', () async {
      // Nothing needed approving, but a bad id must not be smuggled into the
      // audit trail on the back of a small transaction.
      final customer = await seedCustomer(owes: 1000);
      await expectLater(
        customers.receivePayment(
          customerId: customer.id,
          amount: 100,
          method: 'cash',
          userId: 'appr-cashier',
          approvedByUserId: 'no-such-person',
        ),
        throwsA(isA<UnauthorizedApprover>()),
      );
      await expectNothingRecorded(customer, 1000);
    });
  });

  group('P2-C4 — the UI cannot be the only gate', () {
    test('calling the repository directly, exactly as a non-screen caller would, is still gated', () async {
      final customer = await seedCustomer(owes: 50000);

      // This is the bypass Project 1 left open and named as a remaining risk:
      // "a non-screen caller can still take a ₹50,000 receipt with no approver
      // at all". It is now refused by the service, not by the dialog.
      await expectLater(
        customers.receivePayment(
          customerId: customer.id,
          amount: 50000,
          method: 'cash',
          userId: 'appr-cashier',
        ),
        throwsA(isA<ApprovalRequired>()),
      );
      await expectNothingRecorded(customer, 50000);
    });

    test('a split receipt is gated on its total, not on its largest leg', () async {
      final customer = await seedCustomer(owes: 2000);

      // Neither leg exceeds ₹500 on its own; together they are ₹800, which
      // does. Gating per-leg would be a trivially exploitable loophole.
      await expectLater(
        customers.receivePayment(
          customerId: customer.id,
          amount: 800,
          methodAmounts: const {'cash': 400, 'upi': 400},
          userId: 'appr-cashier',
        ),
        throwsA(isA<ApprovalRequired>()),
      );
      await expectNothingRecorded(customer, 2000);
    });

    test('the same split receipt goes through once a manager approves it', () async {
      final customer = await seedCustomer(owes: 2000);
      await customers.receivePayment(
        customerId: customer.id,
        amount: 800,
        methodAmounts: const {'cash': 400, 'upi': 400},
        userId: 'appr-cashier',
        approvedByUserId: 'appr-manager',
      );
      expect((await customers.getById(customer.id))!.outstandingBalance, 1200);
    });
  });

  group('P2-C4 — rollback on refusal', () {
    test('a refused receipt leaves no ledger row, no cash movement, no audit row', () async {
      final db = await DatabaseHelper.instance.database;
      final sessionId = 'session-appr-${DateTime.now().microsecondsSinceEpoch}';
      await db.insert('sessions', {
        'id': sessionId,
        'user_id': 'appr-cashier',
        'opening_time': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'opening_cash': 2000,
        'status': 'open',
        'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      });

      final customer = await seedCustomer(owes: 9000);
      await expectLater(
        customers.receivePayment(
          customerId: customer.id,
          amount: 4000,
          method: 'cash',
          userId: 'appr-cashier',
          sessionId: sessionId,
        ),
        throwsA(isA<ApprovalRequired>()),
      );

      await expectNothingRecorded(customer, 9000);
      expect(await CashMovementRepository().getSessionNet(sessionId), 0);
      expect(
        await db.query(
          'gl_entries',
          where: 'reference_type = ?',
          whereArgs: ['CustomerPayment'],
        ).then((rows) => rows.where((r) => r['description'].toString().contains(customer.id))),
        isEmpty,
      );
    });
  });

  group('P2-C4 — the guard itself', () {
    test('reports the limit and the amount in a message a cashier can act on', () async {
      final db = await DatabaseHelper.instance.database;
      try {
        await approvals.authorise(
          amount: 5000,
          actionLabel: 'Customer payment',
          executor: db,
        );
        fail('should have thrown');
      } on ApprovalRequired catch (e) {
        expect(e.code, 'APPROVAL_REQUIRED');
        expect(e.message, contains('5000.00'));
        expect(e.message, contains('500.00'));
      }
    });

    test('distinguishes "needs approval" from "that approver is not allowed"', () async {
      final db = await DatabaseHelper.instance.database;
      // Two different failures that a screen must respond to differently: one
      // opens the approval dialog, the other says the credentials were wrong.
      await expectLater(
        approvals.authorise(amount: 5000, actionLabel: 'X', executor: db),
        throwsA(isA<ApprovalRequired>()),
      );
      await expectLater(
        approvals.authorise(
          amount: 5000,
          actionLabel: 'X',
          approvedByUserId: 'appr-cashier',
          executor: db,
        ),
        throwsA(isA<UnauthorizedApprover>()),
      );
    });
  });
}
