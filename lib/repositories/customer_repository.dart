import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../core/database/database_helper.dart';
import '../models/customer_model.dart';
import '../models/customer_ledger_model.dart';
import 'cash_movement_repository.dart';
import '../services/approval_service.dart';
import '../services/gl_service.dart';

/// Injected via constructor so tests can pass a fake/in-memory [DatabaseHelper]
/// instead of the real singleton. Existing call sites that used
/// `CustomerRepository()` still compile unchanged because [dbHelper] defaults
/// to the app-wide singleton.
class CustomerRepository {
  CustomerRepository({
    DatabaseHelper? dbHelper,
    CashMovementRepository? cashMovements,
    GLService? glService,
    ApprovalService? approvals,
  })  : _dbHelper = dbHelper ?? DatabaseHelper.instance,
        _cashMovements = cashMovements ?? CashMovementRepository(),
        _glService = glService ?? GLService(),
        _approvals = approvals ?? ApprovalService();

  final DatabaseHelper _dbHelper;
  final CashMovementRepository _cashMovements;
  final GLService _glService;
  final ApprovalService _approvals;

  Future<List<Customer>> getAll({bool includeDeleted = false}) async {
    final db = await _dbHelper.database;
    // Fixed: sqflite's `query()` takes a bare table name as its first
    // argument — the WHERE clause must go through `where`/`whereArgs`,
    // not be concatenated into the table name string.
    final result = await db.query(
      'customers',
      where: includeDeleted ? null : 'is_deleted = 0',
      orderBy: 'name ASC',
    );
    return result.map((e) => Customer.fromJson(e)).toList();
  }

  Future<Customer?> getByPhone(String phone) async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'customers',
      where: 'phone = ? AND is_deleted = 0',
      whereArgs: [phone],
    );
    if (result.isEmpty) return null;
    return Customer.fromJson(result.first);
  }

  Future<Customer?> getById(String id) async {
    final db = await _dbHelper.database;
    final result = await db.query('customers', where: 'id = ?', whereArgs: [id]);
    if (result.isEmpty) return null;
    return Customer.fromJson(result.first);
  }

  /// Creating a customer is ordinary cashier work and is not gated — except
  /// for the credit limit. Starting a new customer on a nonzero limit is an
  /// increase from zero, so it needs the same manager approval raising an
  /// existing limit does; otherwise "raise the limit" could be evaded by
  /// deleting and re-adding the customer.
  Future<void> insert(Customer customer, {String? approvedByUserId}) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      await _authoriseCreditLimit(
        customerName: customer.name,
        previousLimit: 0,
        requestedLimit: customer.creditLimit,
        approvedByUserId: approvedByUserId,
        executor: txn,
      );
      await txn.insert('customers', customer.toJson());
      await _dbHelper.queueSync('customers', customer.id, 'INSERT', customer.toJson(), executor: txn);
    });
  }

  /// Editing a customer's details is likewise open; only a credit-limit
  /// *increase* is gated, and it is compared against what is actually stored
  /// rather than against whatever the caller claims the old value was.
  Future<void> update(Customer customer, {String? approvedByUserId}) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      final existing = await txn.query(
        'customers',
        columns: ['credit_limit'],
        where: 'id = ?',
        whereArgs: [customer.id],
        limit: 1,
      );
      final previousLimit =
          existing.isEmpty ? 0.0 : (existing.first['credit_limit'] as num?)?.toDouble() ?? 0.0;

      await _authoriseCreditLimit(
        customerName: customer.name,
        previousLimit: previousLimit,
        requestedLimit: customer.creditLimit,
        approvedByUserId: approvedByUserId,
        executor: txn,
      );

      await txn.update('customers', customer.toJson(), where: 'id = ?', whereArgs: [customer.id]);
      await _dbHelper.queueSync('customers', customer.id, 'UPDATE', customer.toJson(), executor: txn);
    });
  }

  /// The credit-limit rule, in one place so [insert] and [update] cannot
  /// drift apart: raising what the shop is willing to be owed needs a manager,
  /// keeping or lowering it does not.
  ///
  /// This is not amount-gated. Any increase needs approval, which is exactly
  /// what `customer_form_screen` has always done — the rule has simply moved
  /// from that screen to here, so a caller that never opens the screen is
  /// bound by it too. Editing a name, phone or address reaches this with an
  /// unchanged limit and passes straight through.
  Future<void> _authoriseCreditLimit({
    required String customerName,
    required double previousLimit,
    required double requestedLimit,
    required String? approvedByUserId,
    required DatabaseExecutor executor,
  }) async {
    if (requestedLimit <= previousLimit) return;
    if (approvedByUserId == null) {
      throw ApprovalRequired(
        'Raising $customerName\'s credit limit to ₹${requestedLimit.toStringAsFixed(2)} '
        'needs a manager or admin to approve it.',
      );
    }
    await _approvals.requireValidApprover(approvedByUserId, executor: executor);
  }

  /// Inserts many customers in a single transaction — used by the Import
  /// Parties screen.
  ///
  /// Deliberately *not* credit-limit gated: the import screen sits behind a
  /// manager-only route (`/utilities/import-parties` in `_routeMinRole`), so
  /// the control is the route rather than a per-row approval, and prompting
  /// once per row of a thousand-row spreadsheet would make the feature
  /// unusable. Noted in the Project 2 report as a residual path.
  Future<void> bulkInsert(List<Customer> customers) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      for (final customer in customers) {
        await txn.insert('customers', customer.toJson());
        await _dbHelper.queueSync('customers', customer.id, 'INSERT', customer.toJson(), executor: txn);
      }
    });
  }

  Future<void> softDelete(String id) async {
    final db = await _dbHelper.database;
    await db.update('customers', {'is_deleted': 1}, where: 'id = ?', whereArgs: [id]);
  }

  /// Records a payment against a customer's credit/khata balance: reduces
  /// `outstanding_balance` and writes a matching negative-amount entry to
  /// `customer_ledger` in the same transaction, so the running balance and
  /// the transaction history can never drift apart.
  ///
  /// If [amount] is more than the customer currently owes, the excess isn't
  /// silently folded into the same "payment" row — it's split into a
  /// separate ledger entry with `referenceType: 'advance'`. A payment row
  /// should never represent more than what was actually due at the time;
  /// an advance is a distinct thing (money held for future purchases, a
  /// liability the business should be able to see and report on
  /// separately) and deserves its own label rather than reading as a
  /// confusing negative "due" amount. See CustomerLedger.referenceType and
  /// CustomerHistoryScreen's ledger tab, which render 'advance' entries
  /// distinctly from 'payment' ones.
  ///
  /// "Adjustment" of an existing advance against a later credit sale needs
  /// no separate mechanism — SaleRepository.insertSaleWithItems already
  /// adds `creditUsed` onto whatever `outstanding_balance` is, including a
  /// negative (advance) balance, so a customer with a ₹400 advance who buys
  /// ₹1000 on credit nets to ₹600 owed automatically.
  /// Records money received against a customer's outstanding balance.
  ///
  /// [userId] is required for anything that touches cash: a cash receipt both
  /// writes an audit row and lands in the drawer, and an unattributed
  /// reduction of a receivable is exactly the shape of a lapping fraud. It is
  /// optional only so existing non-cash callers keep compiling.
  ///
  /// [approvedByUserId], when given, is verified here rather than taken on
  /// trust: it must name an active manager or admin. The screen only ever
  /// passes an id `requireApprovalWithApprover` already authenticated, so this
  /// changes nothing about the normal flow — it stops any *other* caller from
  /// stamping an arbitrary id on a receipt and leaving an audit trail that
  /// says a manager signed off when none did. An approval record that can be
  /// forged is worse than no approval record, because it is believed.
  ///
  /// Returns the receipt reference tying together the ledger row, the cash
  /// movement, the GL entry and the audit row for this one payment.
  ///
  /// Give either [method] for a single-method receipt or [methodAmounts] for
  /// one settled several ways (₹400 notes + ₹600 UPI against the same ₹1,000
  /// due). Exactly one of the two is required, and a breakdown must add up to
  /// [amount] — a receipt whose legs disagree with its total is a data-entry
  /// error, not something to reconcile away silently.
  Future<String> receivePayment({
    required String customerId,
    required double amount,
    String? method,
    Map<String, double>? methodAmounts,
    String? note,
    String? userId,
    String? sessionId,
    String? approvedByUserId,
  }) async {
    if (amount <= 0) {
      throw ArgumentError('Payment amount must be greater than zero');
    }
    if ((method == null) == (methodAmounts == null)) {
      throw ArgumentError('Give exactly one of method or methodAmounts');
    }
    final methods = methodAmounts ?? {method!: amount};
    if (methods.isEmpty) {
      throw ArgumentError('A payment needs at least one method');
    }
    if (methods.values.any((v) => v <= 0)) {
      throw ArgumentError('Every payment leg must be greater than zero');
    }
    final legTotal = methods.values.fold<double>(0, (sum, v) => sum + v);
    if ((legTotal - amount).abs() > 0.01) {
      throw ArgumentError(
        'Payment legs total ${legTotal.toStringAsFixed(2)} but the payment is ${amount.toStringAsFixed(2)}',
      );
    }
    // How the receipt reads on a ledger row: the single method when there was
    // one, otherwise each leg named with its share.
    final methodLabel = methods.length == 1
        ? methods.keys.first.toUpperCase()
        : methods.entries.map((leg) => '${leg.key.toUpperCase()} ${leg.value.toStringAsFixed(2)}').join(' + ');

    // One id for this receipt, shared by every row it writes, so a cash
    // movement can be traced back to the exact payment that caused it. The
    // customer id was doing this job before, which meant a customer's tenth
    // collection was indistinguishable from their first.
    final paymentRef = const Uuid().v4();
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      final result = await txn.query('customers', where: 'id = ?', whereArgs: [customerId]);
      if (result.isEmpty) {
        throw Exception('Customer not found: $customerId');
      }

      // The threshold rule, enforced here rather than only in the screen that
      // shows the approval dialog. Project 1 validated *who* approved but not
      // *whether* approval was needed, so any caller that skipped the screen
      // could take a receipt of any size with no approver at all. Throws
      // ApprovalRequired / UnauthorizedApprover from inside the transaction,
      // so a refusal leaves nothing behind.
      await _approvals.authorise(
        amount: amount,
        actionLabel: 'Customer payment',
        approvedByUserId: approvedByUserId,
        executor: txn,
      );
      final customer = Customer.fromJson(result.first);
      final newBalance = customer.outstandingBalance - amount;

      await txn.update(
        'customers',
        {
          'outstanding_balance': newBalance,
          'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        },
        where: 'id = ?',
        whereArgs: [customerId],
      );

      // How much of this payment actually pays down an existing due, vs.
      // becomes an advance. `outstandingBalance` can itself already be
      // negative (an existing advance) — in that case the whole amount is
      // additional advance, there's no due left to apply a "payment" row to.
      final dueBeforePayment = customer.outstandingBalance.clamp(0.0, double.infinity);
      final paymentPortion = amount.clamp(0.0, dueBeforePayment);
      final advancePortion = amount - paymentPortion;

      var runningBalance = customer.outstandingBalance;
      if (paymentPortion > 0) {
        runningBalance -= paymentPortion;
        await txn.insert(
          'customer_ledger',
          CustomerLedger.create(
            customerId: customerId,
            referenceType: 'payment',
            referenceId: paymentRef,
            amount: -paymentPortion,
            balance: runningBalance,
            note: note ?? 'Payment received ($methodLabel)',
          ).toJson(),
        );
      }
      if (advancePortion > 0) {
        runningBalance -= advancePortion;
        await txn.insert(
          'customer_ledger',
          CustomerLedger.create(
            customerId: customerId,
            referenceType: 'advance',
            referenceId: paymentRef,
            amount: -advancePortion,
            balance: runningBalance,
            note: note ?? 'Advance received ($methodLabel)',
          ).toJson(),
        );
      }

      // Cash book: khata collected over the counter is real cash in the
      // drawer. Without this the shift reconciliation could not see it, and a
      // cashier could pocket exactly the amount collected and still close a
      // balanced till — the single largest hole this control had. Only the
      // cash leg of a split receipt reaches the drawer.
      final cashLeg = methods.entries
          .where((leg) => CashMovementRepository.isCashMethod(leg.key))
          .fold<double>(0, (sum, leg) => sum + leg.value);
      if (cashLeg > 0) {
        await _cashMovements.recordIn(
          amount: cashLeg,
          sourceType: CashMovementSource.customerPayment,
          sourceId: paymentRef,
          sessionId: sessionId,
          userId: userId,
          note: note ?? 'Khata payment received from ${customer.name}',
          executor: txn,
        );
      }

      // General Ledger: debit whatever now holds the money, credit Accounts
      // Receivable. Posted with `txn`, so a receipt whose ledger post fails —
      // a closed financial year, a missing chart of accounts — fails as a
      // receipt rather than committing and leaving the books saying the
      // customer still owes it. Before this, collections posted nothing at
      // all and GL receivable drifted upward against the customer ledger for
      // ever.
      await _glService.postCustomerPaymentEntries(
        paymentId: paymentRef,
        paymentDate: DateTime.now(),
        methodAmounts: methods,
        customerId: customerId,
        description: 'Payment from ${customer.name}',
        createdBy: userId,
        executor: txn,
      );

      // Reducing a receivable is a money movement and must leave a trace,
      // whoever did it and however it was paid.
      await _dbHelper.logAudit(
        userId: userId ?? 'unknown',
        actionType: 'CUSTOMER_PAYMENT_RECEIVED',
        tableName: 'customers',
        recordId: customerId,
        oldValue: jsonEncode({'outstanding_balance': customer.outstandingBalance}),
        newValue: jsonEncode({
          'paymentRef': paymentRef,
          'outstanding_balance': newBalance,
          'amount': amount,
          'method': method ?? 'split',
          'methodAmounts': methods,
          'note': note,
          'sessionId': sessionId,
          'approvedByUserId': approvedByUserId,
        }),
        executor: txn,
      );

      await _dbHelper.queueSync(
        'customers',
        customerId,
        'UPDATE',
        {'id': customerId, 'outstanding_balance': newBalance},
        executor: txn,
      );
    });
    return paymentRef;
  }

  Future<List<Customer>> search(String query) async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'customers',
      // Fixed: parenthesize the OR so `is_deleted = 0` applies to both
      // branches — previously a deleted customer could still match by name
      // because AND binds tighter than OR in SQL.
      where: '(name LIKE ? OR phone LIKE ?) AND is_deleted = 0',
      whereArgs: ['%$query%', '%$query%'],
      limit: 20,
    );
    return result.map((e) => Customer.fromJson(e)).toList();
  }
}

/// Riverpod provider — override this in tests with a fake DatabaseHelper-backed
/// repository, e.g.:
///   ProviderScope(overrides: [
///     customerRepositoryProvider.overrideWithValue(CustomerRepository(dbHelper: fakeDb)),
///   ])
final customerRepositoryProvider = Provider<CustomerRepository>((ref) {
  return CustomerRepository();
});