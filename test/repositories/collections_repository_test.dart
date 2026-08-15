import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:supermart_pos/core/database/database_helper.dart';
import 'package:supermart_pos/models/collection_activity_model.dart';
import 'package:supermart_pos/models/customer_ledger_model.dart';
import 'package:supermart_pos/models/customer_model.dart';
import 'package:supermart_pos/repositories/collections_repository.dart';

/// Same temp-directory path_provider shim the other DB-backed tests use, so
/// `DatabaseHelper.instance.database` can open a real sqflite database under
/// `flutter_test`.
class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this._path);
  final String _path;

  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late CollectionsRepository repository;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('collections_repo_test');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
    await DatabaseHelper.instance.database;
  });

  tearDownAll(() async {
    await DatabaseHelper.instance.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  setUp(() async {
    repository = CollectionsRepository();
    final db = await DatabaseHelper.instance.database;
    await db.delete('collection_activities');
    await db.delete('customer_ledger');
    await db.delete('customers');
  });

  int secs(DateTime d) => d.millisecondsSinceEpoch ~/ 1000;

  Future<Customer> makeCustomer({String name = 'Ravi', String phone = '9876543210'}) async {
    final customer = Customer.create(phone: phone, name: name);
    final db = await DatabaseHelper.instance.database;
    await db.insert('customers', customer.toJson());
    return customer;
  }

  Future<CustomerLedger> addLedger(
    String customerId, {
    required double amount,
    required DateTime at,
    String referenceType = 'sale',
    double balance = 0,
  }) async {
    final entry = CustomerLedger(
      id: 'led_${at.millisecondsSinceEpoch}_${amount.toStringAsFixed(2)}',
      customerId: customerId,
      referenceType: referenceType,
      referenceId: 'ref_1',
      amount: amount,
      balance: balance,
      createdAt: secs(at),
    );
    final db = await DatabaseHelper.instance.database;
    await db.insert('customer_ledger', entry.toJson());
    return entry;
  }

  group('ledger reads', () {
    test('returns a customer\'s entries oldest first', () async {
      final customer = await makeCustomer();
      final now = DateTime.now();
      await addLedger(customer.id, amount: 100, at: now.subtract(const Duration(days: 5)));
      await addLedger(customer.id, amount: 200, at: now.subtract(const Duration(days: 20)));

      final entries = await repository.getLedgerEntries(customerId: customer.id);

      expect(entries, hasLength(2));
      expect(entries.first.amount, 200); // the older one
      expect(entries.last.amount, 100);
    });

    test('asOf excludes entries dated after it', () async {
      final customer = await makeCustomer();
      final now = DateTime.now();
      await addLedger(customer.id, amount: 100, at: now.subtract(const Duration(days: 30)));
      await addLedger(customer.id, amount: 500, at: now.subtract(const Duration(days: 1)));

      final entries = await repository.getLedgerEntries(
        customerId: customer.id,
        asOf: now.subtract(const Duration(days: 10)),
      );

      expect(entries, hasLength(1));
      expect(entries.single.amount, 100);
    });

    test('without a customer filter, entries are grouped by customer', () async {
      final a = await makeCustomer(name: 'A', phone: '1111111111');
      final b = await makeCustomer(name: 'B', phone: '2222222222');
      final now = DateTime.now();
      await addLedger(a.id, amount: 10, at: now.subtract(const Duration(days: 2)));
      await addLedger(b.id, amount: 20, at: now.subtract(const Duration(days: 3)));

      final entries = await repository.getLedgerEntries();

      expect(entries, hasLength(2));
      // Grouped by customer_id, so all of one customer's rows are contiguous.
      expect(entries.map((e) => e.customerId).toSet(), {a.id, b.id});
    });

    test('getCustomersByIds returns an empty map for an empty request', () async {
      expect(await repository.getCustomersByIds([]), isEmpty);
    });

    test('getCustomersByIds keys results by id and ignores unknown ids', () async {
      final customer = await makeCustomer(name: 'Meena');

      final found = await repository.getCustomersByIds([customer.id, 'does-not-exist']);

      expect(found, hasLength(1));
      expect(found[customer.id]!.name, 'Meena');
    });
  });

  group('activities', () {
    test('insert then read back a logged activity', () async {
      final customer = await makeCustomer();
      final activity = CollectionActivity.logged(
        customerId: customer.id,
        activityType: CollectionActivityType.call,
        notes: 'Promised to pay Friday',
        amountCollected: 0,
      );

      await repository.insertActivity(activity);
      final loaded = await repository.getActivityById(activity.id);

      expect(loaded, isNotNull);
      expect(loaded!.activityType, CollectionActivityType.call);
      expect(loaded.status, CollectionActivityStatus.completed);
      expect(loaded.notes, 'Promised to pay Friday');
      expect(loaded.amountCollected, 0);
      expect(loaded.completedDate, isNotNull);
    });

    test('a null amountCollected round-trips as null, not zero', () async {
      final customer = await makeCustomer();
      final activity = CollectionActivity.logged(
        customerId: customer.id,
        activityType: CollectionActivityType.visit,
      );

      await repository.insertActivity(activity);

      expect((await repository.getActivityById(activity.id))!.amountCollected, isNull);
    });

    test('getActivityById returns null for an unknown id', () async {
      expect(await repository.getActivityById('nope'), isNull);
    });

    test('update replaces the stored row', () async {
      final customer = await makeCustomer();
      final activity = CollectionActivity.scheduled(
        customerId: customer.id,
        activityType: CollectionActivityType.call,
        scheduledDate: DateTime.now().add(const Duration(days: 2)),
      );
      await repository.insertActivity(activity);

      await repository.updateActivity(CollectionActivity(
        id: activity.id,
        customerId: activity.customerId,
        activityType: activity.activityType,
        scheduledDate: activity.scheduledDate,
        completedDate: secs(DateTime.now()),
        status: CollectionActivityStatus.completed,
        notes: 'Done',
        amountCollected: 250,
        createdAt: activity.createdAt,
      ));

      final loaded = await repository.getActivityById(activity.id);
      expect(loaded!.status, CollectionActivityStatus.completed);
      expect(loaded.amountCollected, 250);
      expect(loaded.notes, 'Done');
    });

    test('per-customer history is newest first', () async {
      final customer = await makeCustomer();
      final now = DateTime.now();
      final older = CollectionActivity.logged(
        customerId: customer.id,
        activityType: CollectionActivityType.call,
        completedDate: now.subtract(const Duration(days: 10)),
      );
      final newer = CollectionActivity.logged(
        customerId: customer.id,
        activityType: CollectionActivityType.visit,
        completedDate: now.subtract(const Duration(days: 1)),
      );
      await repository.insertActivity(older);
      await repository.insertActivity(newer);

      final history = await repository.getActivitiesForCustomer(customer.id);

      expect(history.map((a) => a.activityType).toList(),
          [CollectionActivityType.visit, CollectionActivityType.call]);
    });

    test('history is scoped to the customer asked for', () async {
      final a = await makeCustomer(name: 'A', phone: '1111111111');
      final b = await makeCustomer(name: 'B', phone: '2222222222');
      await repository.insertActivity(CollectionActivity.logged(
        customerId: a.id,
        activityType: CollectionActivityType.call,
      ));
      await repository.insertActivity(CollectionActivity.logged(
        customerId: b.id,
        activityType: CollectionActivityType.email,
      ));

      expect(await repository.getActivitiesForCustomer(a.id), hasLength(1));
    });

    test('pending list excludes completed rows and logged-only rows', () async {
      final customer = await makeCustomer();
      // Completed — not pending.
      await repository.insertActivity(CollectionActivity.logged(
        customerId: customer.id,
        activityType: CollectionActivityType.call,
      ));
      // Pending, but with no scheduled date it is not a reminder.
      await repository.insertActivity(CollectionActivity(
        id: 'no-date',
        customerId: customer.id,
        activityType: CollectionActivityType.call,
      ));
      final scheduled = CollectionActivity.scheduled(
        customerId: customer.id,
        activityType: CollectionActivityType.whatsapp,
        scheduledDate: DateTime.now().add(const Duration(days: 3)),
      );
      await repository.insertActivity(scheduled);

      final pending = await repository.getPendingActivities();

      expect(pending, hasLength(1));
      expect(pending.single.id, scheduled.id);
    });

    test('dueBy filters the worklist to what has come due, soonest first', () async {
      final customer = await makeCustomer();
      final now = DateTime.now();
      final soon = CollectionActivity.scheduled(
        customerId: customer.id,
        activityType: CollectionActivityType.call,
        scheduledDate: now.add(const Duration(days: 1)),
      );
      final later = CollectionActivity.scheduled(
        customerId: customer.id,
        activityType: CollectionActivityType.visit,
        scheduledDate: now.add(const Duration(days: 30)),
      );
      await repository.insertActivity(later);
      await repository.insertActivity(soon);

      final due = await repository.getPendingActivities(dueBy: now.add(const Duration(days: 7)));

      expect(due, hasLength(1));
      expect(due.single.id, soon.id);

      final all = await repository.getPendingActivities();
      expect(all.map((a) => a.id).toList(), [soon.id, later.id]);
    });

    test('delete removes the row', () async {
      final customer = await makeCustomer();
      final activity = CollectionActivity.scheduled(
        customerId: customer.id,
        activityType: CollectionActivityType.call,
        scheduledDate: DateTime.now().add(const Duration(days: 1)),
      );
      await repository.insertActivity(activity);

      await repository.deleteActivity(activity.id);

      expect(await repository.getActivityById(activity.id), isNull);
    });
  });
}
