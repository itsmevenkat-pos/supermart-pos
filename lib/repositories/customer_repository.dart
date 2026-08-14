import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../core/database/database_helper.dart';
import '../models/customer_model.dart';
import '../models/customer_ledger_model.dart';

/// Injected via constructor so tests can pass a fake/in-memory [DatabaseHelper]
/// instead of the real singleton. Existing call sites that used
/// `CustomerRepository()` still compile unchanged because [dbHelper] defaults
/// to the app-wide singleton.
class CustomerRepository {
  CustomerRepository({DatabaseHelper? dbHelper})
      : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _dbHelper;

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

  Future<void> insert(Customer customer) async {
    final db = await _dbHelper.database;
    await db.insert('customers', customer.toJson());
    await _dbHelper.queueSync('customers', customer.id, 'INSERT', customer.toJson());
  }

  Future<void> update(Customer customer) async {
    final db = await _dbHelper.database;
    await db.update('customers', customer.toJson(), where: 'id = ?', whereArgs: [customer.id]);
    await _dbHelper.queueSync('customers', customer.id, 'UPDATE', customer.toJson());
  }

  /// Inserts many customers in a single transaction — used by the
  /// Import Parties screen.
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
  Future<void> receivePayment({
    required String customerId,
    required double amount,
    required String method,
    String? note,
  }) async {
    if (amount <= 0) {
      throw ArgumentError('Payment amount must be greater than zero');
    }
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      final result = await txn.query('customers', where: 'id = ?', whereArgs: [customerId]);
      if (result.isEmpty) {
        throw Exception('Customer not found: $customerId');
      }
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
            referenceId: const Uuid().v4(),
            amount: -paymentPortion,
            balance: runningBalance,
            note: note ?? 'Payment received (${method.toUpperCase()})',
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
            referenceId: const Uuid().v4(),
            amount: -advancePortion,
            balance: runningBalance,
            note: note ?? 'Advance received (${method.toUpperCase()})',
          ).toJson(),
        );
      }

      await _dbHelper.queueSync(
        'customers',
        customerId,
        'UPDATE',
        {'id': customerId, 'outstanding_balance': newBalance},
        executor: txn,
      );
    });
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