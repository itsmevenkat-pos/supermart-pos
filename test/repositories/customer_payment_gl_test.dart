import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:supermart_pos/core/database/database_helper.dart';
import 'package:supermart_pos/core/utils/financial_year.dart';
import 'package:supermart_pos/models/customer_model.dart';
import 'package:supermart_pos/models/product_model.dart';
import 'package:supermart_pos/models/sale_model.dart';
import 'package:supermart_pos/models/sale_item_model.dart';
import 'package:supermart_pos/repositories/cash_movement_repository.dart';
import 'package:supermart_pos/repositories/customer_repository.dart';
import 'package:supermart_pos/repositories/product_repository.dart';
import 'package:supermart_pos/repositories/sale_repository.dart';
import 'package:supermart_pos/services/financial_year_close_service.dart';
import 'package:supermart_pos/services/gl_service.dart';

/// P2-C1 — a khata collection is a GL event.
///
/// Before this, `receivePayment` wrote the customer ledger, the cash book and
/// an audit row, and posted nothing to the GL at all. Accounts Receivable was
/// therefore reduced only by cancellations and credit-adjusted returns, never
/// by an actual collection, so GL AR drifted upward against the customer
/// ledger without limit and never came back.
///
/// Accounting decisions in force here:
/// - **AD-1** — cash settles to Cash 1000, everything else to Bank 1010.
/// - **AD-3** — advances stay in Accounts Receivable, which may go
///   net-negative. The invariant that buys is asserted at the bottom of this
///   file: the sum of every customer's outstanding balance equals the GL
///   Accounts Receivable balance, always.
class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this._path);
  final String _path;

  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
}

int _phoneCounter = 0;
String _nextPhone() => (9500000000 + (_phoneCounter++)).toString();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late CustomerRepository customers;
  late String cashAccountId;
  late String bankAccountId;
  late String receivableAccountId;

  Future<double> netDebitFor(String accountId, String referenceId) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(debit) - SUM(credit), 0) AS net FROM gl_entries
      WHERE account_id = ? AND reference_type = ? AND reference_id = ?
      ''',
      [accountId, GLService.customerPaymentReferenceType, referenceId],
    );
    return (rows.first['net'] as num).toDouble();
  }

  Future<double> accountNetDebit(String accountId) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.rawQuery(
      'SELECT COALESCE(SUM(debit) - SUM(credit), 0) AS net FROM gl_entries WHERE account_id = ?',
      [accountId],
    );
    return (rows.first['net'] as num).toDouble();
  }

  Future<Customer> seedCustomer({double owes = 0}) async {
    final customer = Customer.create(phone: _nextPhone(), name: 'GL Khata Customer');
    await customers.insert(customer);
    if (owes != 0) {
      await customers.update(customer.copyWith(outstandingBalance: owes));
    }
    return customer;
  }

  Future<String> openShift(String userId) async {
    final db = await DatabaseHelper.instance.database;
    final id = 'session-$userId-${DateTime.now().microsecondsSinceEpoch}';
    await db.insert('sessions', {
      'id': id,
      'user_id': userId,
      'opening_time': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'opening_cash': 2000,
      'status': 'open',
      'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    });
    return id;
  }

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('customer_payment_gl_test');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);

    final db = await DatabaseHelper.instance.database;
    await db.insert('users', {
      'id': 'gl-cashier',
      'username': 'gl_cashier',
      'password_hash': 'x',
      'role': 'cashier',
      'name': 'GL Cashier',
      'must_change_password': 0,
      'is_active': 1,
      'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    });
    // Collections above the ₹500 cashier discretion limit need a manager to
    // approve them (P2-C4), so the larger figures below carry one.
    await db.insert('users', {
      'id': 'gl-manager',
      'username': 'gl_manager',
      'password_hash': 'x',
      'role': 'manager',
      'name': 'GL Manager',
      'must_change_password': 0,
      'is_active': 1,
      'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    });

    customers = CustomerRepository();
    final gl = GLService();
    cashAccountId = (await gl.requireAccountByCode(GLService.cashAccountCode)).id;
    bankAccountId = (await gl.requireAccountByCode(GLService.bankAccountCode)).id;
    receivableAccountId = (await gl.requireAccountByCode(GLService.receivableAccountCode)).id;
  });

  tearDownAll(() async {
    await DatabaseHelper.instance.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('P2-C1 — collection posts to the GL', () {
    test('a partial cash collection debits Cash and credits Accounts Receivable', () async {
      final session = await openShift('gl-cashier');
      final customer = await seedCustomer(owes: 1000);

      final ref = await customers.receivePayment(
        customerId: customer.id,
        amount: 400,
        method: 'cash',
        userId: 'gl-cashier',
        sessionId: session,
      );

      expect((await customers.getById(customer.id))!.outstandingBalance, 600);
      expect(await netDebitFor(cashAccountId, ref), 400);
      expect(await netDebitFor(bankAccountId, ref), 0);
      expect(await netDebitFor(receivableAccountId, ref), -400);
      // Cash book and GL agree about the same notes.
      expect(await CashMovementRepository().getSessionNet(session), 400);
    });

    test('a full UPI collection debits Bank, not Cash', () async {
      final session = await openShift('gl-cashier');
      final customer = await seedCustomer(owes: 1000);

      final ref = await customers.receivePayment(
        customerId: customer.id,
        amount: 1000,
        method: 'upi',
        userId: 'gl-cashier',
        approvedByUserId: 'gl-manager', // above the ₹500 cashier limit (P2-C4)
        sessionId: session,
      );

      expect((await customers.getById(customer.id))!.outstandingBalance, 0);
      expect(await netDebitFor(cashAccountId, ref), 0);
      expect(await netDebitFor(bankAccountId, ref), 1000);
      expect(await netDebitFor(receivableAccountId, ref), -1000);
      expect(await CashMovementRepository().getSessionNet(session), 0);
    });

    test('a card collection debits Bank', () async {
      final customer = await seedCustomer(owes: 250);
      final ref = await customers.receivePayment(
        customerId: customer.id,
        amount: 250,
        method: 'card',
        userId: 'gl-cashier',
      );

      expect(await netDebitFor(bankAccountId, ref), 250);
      expect(await netDebitFor(receivableAccountId, ref), -250);
    });

    test('an overpayment posts the whole receipt, advance included', () async {
      final customer = await seedCustomer(owes: 500);

      final ref = await customers.receivePayment(
        customerId: customer.id,
        approvedByUserId: 'gl-manager', // above the ₹500 cashier limit (P2-C4)
        amount: 700,
        method: 'cash',
        userId: 'gl-cashier',
      );

      // AD-3: the ₹200 advance stays in Accounts Receivable, which simply goes
      // net-negative — so the GL and the customer ledger describe the same
      // ₹700 rather than diverging by the advance.
      expect((await customers.getById(customer.id))!.outstandingBalance, -200);
      expect(await netDebitFor(cashAccountId, ref), 700);
      expect(await netDebitFor(receivableAccountId, ref), -700);
    });

    test('an advance from a customer who owes nothing still posts', () async {
      final customer = await seedCustomer();

      final ref = await customers.receivePayment(
        customerId: customer.id,
        amount: 300,
        method: 'cash',
        userId: 'gl-cashier',
      );

      expect((await customers.getById(customer.id))!.outstandingBalance, -300);
      expect(await netDebitFor(cashAccountId, ref), 300);
      expect(await netDebitFor(receivableAccountId, ref), -300);
    });

    test('the GL entry is filed under the payment reference the ledger and cash book share', () async {
      final session = await openShift('gl-cashier');
      final customer = await seedCustomer(owes: 800);

      final ref = await customers.receivePayment(
        customerId: customer.id,
        approvedByUserId: 'gl-manager', // above the ₹500 cashier limit (P2-C4)
        amount: 800,
        method: 'cash',
        userId: 'gl-cashier',
        sessionId: session,
      );

      final db = await DatabaseHelper.instance.database;
      // One reference walks the whole chain: customer → ledger → cash → GL.
      expect(
        await db.query('customer_ledger', where: 'reference_id = ?', whereArgs: [ref]),
        hasLength(1),
      );
      expect(
        await db.query('cash_movements', where: 'source_id = ?', whereArgs: [ref]),
        hasLength(1),
      );
      final glRows = await db.query(
        'gl_entries',
        where: 'reference_type = ? AND reference_id = ?',
        whereArgs: [GLService.customerPaymentReferenceType, ref],
      );
      expect(glRows, hasLength(2)); // one debit, one credit
      expect(glRows.every((r) => r['created_by'] == 'gl-cashier'), isTrue);
    });
  });

  group('P2-C1 — split collection', () {
    test('₹400 cash + ₹600 UPI clears a ₹1,000 due across two accounts', () async {
      final session = await openShift('gl-cashier');
      final customer = await seedCustomer(owes: 1000);

      final ref = await customers.receivePayment(
        approvedByUserId: 'gl-manager', // above the ₹500 cashier limit (P2-C4)
        customerId: customer.id,
        amount: 1000,
        methodAmounts: const {'cash': 400, 'upi': 600},
        userId: 'gl-cashier',
        sessionId: session,
      );

      expect((await customers.getById(customer.id))!.outstandingBalance, 0);
      expect(await netDebitFor(cashAccountId, ref), 400);
      expect(await netDebitFor(bankAccountId, ref), 600);
      expect(await netDebitFor(receivableAccountId, ref), -1000);

      // Only the notes reach the drawer.
      expect(await CashMovementRepository().getSessionNet(session), 400);
    });

    test('a breakdown that does not add up to the amount is refused', () async {
      final customer = await seedCustomer(owes: 1000);

      await expectLater(
        customers.receivePayment(
          customerId: customer.id,
          amount: 1000,
          methodAmounts: const {'cash': 400, 'upi': 500}, // ₹900, not ₹1,000
          userId: 'gl-cashier',
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect((await customers.getById(customer.id))!.outstandingBalance, 1000);
    });

    test('giving neither a method nor a breakdown is refused', () async {
      final customer = await seedCustomer(owes: 100);
      await expectLater(
        customers.receivePayment(customerId: customer.id, amount: 100, userId: 'gl-cashier'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('P2-C1 — atomicity and duplicates', () {
    test('a GL failure rolls back the ledger, the balance, the drawer and the audit row', () async {
      final db = await DatabaseHelper.instance.database;
      final session = await openShift('gl-cashier');
      final customer = await seedCustomer(owes: 2000);

      final year = financialYearLabel(DateTime.now());
      await FinancialYearCloseService().closeFinancialYear(financialYear: year, userId: 'gl-cashier');
      addTearDown(() async {
        await db.delete('financial_year_closures', where: 'financial_year = ?', whereArgs: [year]);
      });

      await expectLater(
        customers.receivePayment(
          customerId: customer.id,
          amount: 500,
          method: 'cash',
          userId: 'gl-cashier',
          sessionId: session,
        ),
        throwsA(isA<Exception>()),
      );

      // The receipt never happened, in every table that would have recorded it.
      expect((await customers.getById(customer.id))!.outstandingBalance, 2000);
      expect(await CashMovementRepository().getSessionNet(session), 0);
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
    });

    test('two collections post two independent GL entries, neither duplicated', () async {
      final customer = await seedCustomer(owes: 1000);

      final first = await customers.receivePayment(
        customerId: customer.id,
        amount: 300,
        method: 'cash',
        userId: 'gl-cashier',
      );
      final second = await customers.receivePayment(
        customerId: customer.id,
        amount: 300,
        method: 'cash',
        userId: 'gl-cashier',
      );

      expect(first, isNot(second));
      expect(await netDebitFor(receivableAccountId, first), -300);
      expect(await netDebitFor(receivableAccountId, second), -300);
      expect((await customers.getById(customer.id))!.outstandingBalance, 400);
    });
  });

  group('P2-C1 — the reconciliation invariant', () {
    test('a receivable created by real credit sales moves the ledger and the GL identically', () async {
      final db = await DatabaseHelper.instance.database;

      Future<double> ledgerTotal() async => ((await db.rawQuery(
                'SELECT COALESCE(SUM(outstanding_balance), 0) AS total FROM customers WHERE is_deleted = 0',
              ))
                  .first['total'] as num)
          .toDouble();

      // Measured as a delta rather than an absolute, because other tests in
      // this file seed balances directly to set up their own scenarios. The
      // invariant being asserted is the one that matters operationally: any
      // sequence of real transactions moves both figures by the same amount.
      final ledgerBefore = await ledgerTotal();
      final glBefore = await accountNetDebit(receivableAccountId);

      /// A real credit sale, so the receivable exists in the GL as well as on
      /// the customer — seeding `outstanding_balance` by hand would prove
      /// nothing, since it is the posting path under test.
      Future<Customer> customerOwing(double amount) async {
        final customer = Customer.create(phone: _nextPhone(), name: 'Recon Customer');
        await customers.insert(customer);
        final product = Product.create(
          barcode: 'RECON-${DateTime.now().microsecondsSinceEpoch}',
          name: 'Recon Product',
          costPrice: 10,
          retailPrice: amount,
          stockQuantity: 50,
        );
        await ProductRepository().insert(product);
        await SaleRepository().insertSaleWithItems(
          sale: Sale.create(
            storeId: 'store_default',
            customerId: customer.id,
            userId: 'gl-cashier',
            netAmount: amount,
            creditUsed: amount,
            isCreditSale: true,
          ),
          items: [
            SaleItem.create(
                productId: product.id, quantity: 1, unitPrice: amount, totalPrice: amount, costPrice: 10),
          ],
          storeId: 'store_default',
          customerId: customer.id,
        );
        return customer;
      }

      final a = await customerOwing(1200);
      final b = await customerOwing(800);
      final c = await customerOwing(300);

      await customers.receivePayment(customerId: a.id, amount: 500, method: 'cash', userId: 'gl-cashier');
      await customers.receivePayment(
          customerId: b.id,
          amount: 800,
          method: 'upi',
          userId: 'gl-cashier',
          approvedByUserId: 'gl-manager');
      // Deliberately overpaid — ₹150 of this becomes an advance, and AD-3 says
      // that advance stays inside Accounts Receivable rather than moving to a
      // liability account. If it did move, this assertion would break.
      await customers.receivePayment(customerId: c.id, amount: 450, method: 'cash', userId: 'gl-cashier');

      final ledgerDelta = await ledgerTotal() - ledgerBefore;
      final glDelta = await accountNetDebit(receivableAccountId) - glBefore;

      expect(ledgerDelta, closeTo(glDelta, 0.01));
      // 2,300 sold on credit, 1,750 collected → 550 still owed, net of C's advance.
      expect(ledgerDelta, closeTo(550, 0.01));
    });
  });
}
