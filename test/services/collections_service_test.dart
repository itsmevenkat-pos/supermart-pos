import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:supermart_pos/core/database/database_helper.dart';
import 'package:supermart_pos/models/collection_activity_model.dart';
import 'package:supermart_pos/models/customer_ledger_model.dart';
import 'package:supermart_pos/models/customer_model.dart';
import 'package:supermart_pos/repositories/collections_repository.dart';
import 'package:supermart_pos/services/collections_exceptions.dart';
import 'package:supermart_pos/services/collections_service.dart';

class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this._path);
  final String _path;

  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late CollectionsService service;

  /// Every age-sensitive test is computed against this fixed instant rather
  /// than `DateTime.now()`, so a test that says "exactly 30 days old" means
  /// it — and cannot flake when a run straddles midnight.
  final asOf = DateTime(2026, 6, 15, 12);

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('collections_service_test');
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
    service = CollectionsService(repository: CollectionsRepository());
    final db = await DatabaseHelper.instance.database;
    await db.delete('collection_activities');
    await db.delete('customer_ledger');
    await db.delete('customers');
  });

  int secs(DateTime d) => d.millisecondsSinceEpoch ~/ 1000;

  Future<Customer> makeCustomer({
    String name = 'Ravi',
    String phone = '9876543210',
  }) async {
    final customer = Customer.create(phone: phone, name: name);
    final db = await DatabaseHelper.instance.database;
    await db.insert('customers', customer.toJson());
    return customer;
  }

  var ledgerSeq = 0;

  /// Adds a ledger row [daysAgo] days before [asOf]. Positive [amount] is a
  /// charge, negative is a payment — the sign convention `CustomerLedger`
  /// documents.
  Future<void> addLedger(
    String customerId, {
    required double amount,
    required int daysAgo,
    String referenceType = 'sale',
  }) async {
    final at = asOf.subtract(Duration(days: daysAgo));
    final entry = CustomerLedger(
      id: 'led_${ledgerSeq++}',
      customerId: customerId,
      referenceType: referenceType,
      referenceId: 'ref_$ledgerSeq',
      amount: amount,
      balance: 0,
      createdAt: secs(at),
    );
    final db = await DatabaseHelper.instance.database;
    await db.insert('customer_ledger', entry.toJson());
  }

  group('aging bucket boundaries', () {
    // The documented rule: lower-inclusive, upper-exclusive. A charge exactly
    // 30 days old is in the 30-60 bucket, not 0-30. Task 2.4 asks for this
    // call to be made explicitly and tested, so each edge is pinned here.
    Future<AgingBucket> bucketAt(int daysAgo) async {
      final db = await DatabaseHelper.instance.database;
      await db.delete('customer_ledger');
      await db.delete('customers');
      final customer = await makeCustomer();
      await addLedger(customer.id, amount: 1000, daysAgo: daysAgo);
      final aging = await service.getCustomerAging(customer.id, asOf: asOf);
      return aging!.openCharges.single.bucket;
    }

    test('0 days old is current', () async {
      expect(await bucketAt(0), AgingBucket.current);
    });

    test('29 days old is still current', () async {
      expect(await bucketAt(29), AgingBucket.current);
    });

    test('exactly 30 days old falls in the 30-60 bucket', () async {
      expect(await bucketAt(30), AgingBucket.days30);
    });

    test('59 days old is still the 30-60 bucket', () async {
      expect(await bucketAt(59), AgingBucket.days30);
    });

    test('exactly 60 days old falls in the 60-90 bucket', () async {
      expect(await bucketAt(60), AgingBucket.days60);
    });

    test('89 days old is still the 60-90 bucket', () async {
      expect(await bucketAt(89), AgingBucket.days60);
    });

    test('exactly 90 days old falls in the 90+ bucket', () async {
      expect(await bucketAt(90), AgingBucket.days90Plus);
    });

    test('bucket labels match the boundaries they describe', () {
      expect(AgingBucket.current.label, '0-30 days');
      expect(AgingBucket.days30.label, '30-60 days');
      expect(AgingBucket.days60.label, '60-90 days');
      expect(AgingBucket.days90Plus.label, '90+ days');
    });
  });

  group('FIFO application', () {
    test('a payment clears the oldest charge first', () async {
      final customer = await makeCustomer();
      await addLedger(customer.id, amount: 500, daysAgo: 100); // oldest
      await addLedger(customer.id, amount: 300, daysAgo: 10);
      await addLedger(customer.id, amount: -500, daysAgo: 1, referenceType: 'payment');

      final aging = (await service.getCustomerAging(customer.id, asOf: asOf))!;

      // The 100-day-old debt is gone; only the recent one survives.
      expect(aging.openCharges, hasLength(1));
      expect(aging.openCharges.single.outstanding, 300);
      expect(aging.openCharges.single.ageInDays, 10);
      expect(aging.totalOutstanding, 300);
      expect(aging.amountIn(AgingBucket.days90Plus), 0);
      expect(aging.amountIn(AgingBucket.current), 300);
    });

    test('a partial payment leaves the remainder of the oldest charge aged as before', () async {
      final customer = await makeCustomer();
      await addLedger(customer.id, amount: 1000, daysAgo: 95);
      await addLedger(customer.id, amount: -400, daysAgo: 2, referenceType: 'payment');

      final aging = (await service.getCustomerAging(customer.id, asOf: asOf))!;

      expect(aging.openCharges.single.outstanding, 600);
      expect(aging.openCharges.single.originalAmount, 1000);
      // Paying part of an old debt does not make the rest of it recent.
      expect(aging.openCharges.single.ageInDays, 95);
      expect(aging.amountIn(AgingBucket.days90Plus), 600);
    });

    test('a payment spills from the oldest charge onto the next', () async {
      final customer = await makeCustomer();
      await addLedger(customer.id, amount: 200, daysAgo: 100);
      await addLedger(customer.id, amount: 500, daysAgo: 40);
      await addLedger(customer.id, amount: -400, daysAgo: 1, referenceType: 'payment');

      final aging = (await service.getCustomerAging(customer.id, asOf: asOf))!;

      // 400 clears the 200 outright and takes 200 off the 500.
      expect(aging.openCharges, hasLength(1));
      expect(aging.openCharges.single.outstanding, 300);
      expect(aging.amountIn(AgingBucket.days30), 300);
      expect(aging.amountIn(AgingBucket.days90Plus), 0);
    });

    test('an advance paid before a sale is absorbed by it', () async {
      final customer = await makeCustomer();
      await addLedger(customer.id, amount: -1000, daysAgo: 50, referenceType: 'advance');
      await addLedger(customer.id, amount: 700, daysAgo: 20);

      // The sale is fully covered by the advance, so nothing is outstanding.
      expect(await service.getCustomerAging(customer.id, asOf: asOf), isNull);
    });

    test('a sale larger than the advance leaves only the uncovered part', () async {
      final customer = await makeCustomer();
      await addLedger(customer.id, amount: -300, daysAgo: 50, referenceType: 'advance');
      await addLedger(customer.id, amount: 1000, daysAgo: 35);

      final aging = (await service.getCustomerAging(customer.id, asOf: asOf))!;

      expect(aging.totalOutstanding, 700);
      expect(aging.amountIn(AgingBucket.days30), 700);
    });

    test('overpayment leaves an advance and nothing outstanding', () async {
      final customer = await makeCustomer();
      await addLedger(customer.id, amount: 500, daysAgo: 40);
      await addLedger(customer.id, amount: -800, daysAgo: 2, referenceType: 'payment');

      // Nothing outstanding, so the customer is not a collections case at all.
      expect(await service.getCustomerAging(customer.id, asOf: asOf), isNull);

      final report = await service.generateAgingReport(asOf: asOf);
      expect(report.rows, isEmpty);
    });

    test('returns and cancellations reduce the balance like payments', () async {
      final customer = await makeCustomer();
      await addLedger(customer.id, amount: 1000, daysAgo: 70);
      await addLedger(customer.id, amount: -250, daysAgo: 60, referenceType: 'sales_return');
      await addLedger(customer.id, amount: -250, daysAgo: 55, referenceType: 'sale_cancellation');

      final aging = (await service.getCustomerAging(customer.id, asOf: asOf))!;

      expect(aging.totalOutstanding, 500);
    });

    test('the aged total matches the ledger sum', () async {
      final customer = await makeCustomer();
      await addLedger(customer.id, amount: 1200.50, daysAgo: 120);
      await addLedger(customer.id, amount: 340.25, daysAgo: 65);
      await addLedger(customer.id, amount: -500, daysAgo: 30, referenceType: 'payment');
      await addLedger(customer.id, amount: 99.75, daysAgo: 3);

      final aging = (await service.getCustomerAging(customer.id, asOf: asOf))!;

      // 1200.50 + 340.25 - 500 + 99.75
      expect(aging.totalOutstanding, closeTo(1140.50, 0.001));
      // And the buckets account for all of it.
      final bucketSum = AgingBucket.values.fold<double>(0, (s, b) => s + aging.amountIn(b));
      expect(bucketSum, closeTo(1140.50, 0.001));
    });

    test('floating-point dust does not survive as a phantom open charge', () async {
      final customer = await makeCustomer();
      await addLedger(customer.id, amount: 0.1, daysAgo: 40);
      await addLedger(customer.id, amount: 0.2, daysAgo: 39);
      await addLedger(customer.id, amount: -0.3, daysAgo: 1, referenceType: 'payment');

      // 0.1 + 0.2 - 0.3 is not exactly 0 in binary floating point.
      expect(await service.getCustomerAging(customer.id, asOf: asOf), isNull);
    });
  });

  group('aging report', () {
    test('excludes customers who owe nothing', () async {
      final owing = await makeCustomer(name: 'Owes', phone: '1111111111');
      final settled = await makeCustomer(name: 'Settled', phone: '2222222222');
      await addLedger(owing.id, amount: 400, daysAgo: 45);
      await addLedger(settled.id, amount: 400, daysAgo: 45);
      await addLedger(settled.id, amount: -400, daysAgo: 4, referenceType: 'payment');

      final report = await service.generateAgingReport(asOf: asOf);

      expect(report.rows, hasLength(1));
      expect(report.rows.single.customer.name, 'Owes');
    });

    test('is sorted with the oldest debt first', () async {
      final recent = await makeCustomer(name: 'Recent', phone: '1111111111');
      final ancient = await makeCustomer(name: 'Ancient', phone: '2222222222');
      final middling = await makeCustomer(name: 'Middling', phone: '3333333333');
      await addLedger(recent.id, amount: 5000, daysAgo: 5);
      await addLedger(ancient.id, amount: 100, daysAgo: 200);
      await addLedger(middling.id, amount: 900, daysAgo: 45);

      final report = await service.generateAgingReport(asOf: asOf);

      expect(report.rows.map((r) => r.customer.name).toList(),
          ['Ancient', 'Middling', 'Recent']);
    });

    test('totals per bucket and overall', () async {
      final a = await makeCustomer(name: 'A', phone: '1111111111');
      final b = await makeCustomer(name: 'B', phone: '2222222222');
      await addLedger(a.id, amount: 100, daysAgo: 5); // current
      await addLedger(a.id, amount: 200, daysAgo: 95); // 90+
      await addLedger(b.id, amount: 300, daysAgo: 65); // 60-90

      final report = await service.generateAgingReport(asOf: asOf);

      expect(report.totalIn(AgingBucket.current), 100);
      expect(report.totalIn(AgingBucket.days30), 0);
      expect(report.totalIn(AgingBucket.days60), 300);
      expect(report.totalIn(AgingBucket.days90Plus), 200);
      expect(report.grandTotal, 600);
      expect(report.customerCount, 2);
      expect(report.overdueCustomerCount, 2);
    });

    test('a customer with only current debt is not counted as overdue', () async {
      final customer = await makeCustomer();
      await addLedger(customer.id, amount: 750, daysAgo: 3);

      final report = await service.generateAgingReport(asOf: asOf);

      expect(report.customerCount, 1);
      expect(report.overdueCustomerCount, 0);
      expect(report.rows.single.isOverdue, isFalse);
    });

    test('asOf reproduces what the shop would have seen that day', () async {
      final customer = await makeCustomer();
      await addLedger(customer.id, amount: 1000, daysAgo: 60);
      await addLedger(customer.id, amount: -1000, daysAgo: 5, referenceType: 'payment');

      // Today: settled.
      expect((await service.generateAgingReport(asOf: asOf)).rows, isEmpty);

      // Ten days ago, before the payment: outstanding and 50 days old.
      final earlier = await service.generateAgingReport(
        asOf: asOf.subtract(const Duration(days: 10)),
      );
      expect(earlier.rows, hasLength(1));
      expect(earlier.rows.single.totalOutstanding, 1000);
      expect(earlier.rows.single.oldestChargeDays, 50);
    });

    test('an empty ledger produces an empty report', () async {
      final report = await service.generateAgingReport(asOf: asOf);
      expect(report.rows, isEmpty);
      expect(report.grandTotal, 0);
    });

    test('a soft-deleted customer still shows their receivable', () async {
      final customer = await makeCustomer(name: 'Vanishing');
      await addLedger(customer.id, amount: 620, daysAgo: 100);
      final db = await DatabaseHelper.instance.database;
      // How this app actually removes a customer — `is_deleted`, not a row
      // delete. The money is still owed, so it must not silently drop out of
      // the receivable just because someone tidied the customer list.
      await db.update('customers', {'is_deleted': 1}, where: 'id = ?', whereArgs: [customer.id]);

      final report = await service.generateAgingReport(asOf: asOf);

      expect(report.rows, hasLength(1));
      expect(report.grandTotal, 620);
      expect(report.rows.single.customer.name, 'Vanishing');
    });

    test('an orphaned ledger row does not crash the report', () async {
      // `customer_ledger.customer_id` is ON DELETE CASCADE and foreign keys
      // are on, so this cannot arise from a normal delete. It can arise from
      // a migration, which turns foreign keys off (see DatabaseHelper), or
      // from a sync that lands a ledger row for a customer this till has not
      // seen. The report keeps the money visible under a placeholder rather
      // than throwing on the missing name.
      final db = await DatabaseHelper.instance.database;
      await db.execute('PRAGMA foreign_keys = OFF');
      try {
        await addLedger('ghost-customer', amount: 620, daysAgo: 100);
      } finally {
        await db.execute('PRAGMA foreign_keys = ON');
      }

      final report = await service.generateAgingReport(asOf: asOf);

      expect(report.rows, hasLength(1));
      expect(report.grandTotal, 620);
      expect(report.rows.single.customer.name, contains('deleted customer'));
    });

    test('oldestChargeDays reports the oldest surviving charge', () async {
      final customer = await makeCustomer();
      await addLedger(customer.id, amount: 100, daysAgo: 150);
      await addLedger(customer.id, amount: 100, daysAgo: 20);

      final aging = (await service.getCustomerAging(customer.id, asOf: asOf))!;
      expect(aging.oldestChargeDays, 150);
    });

    test('getCustomerAging returns null for a customer with no ledger at all', () async {
      final customer = await makeCustomer();
      expect(await service.getCustomerAging(customer.id, asOf: asOf), isNull);
    });
  });

  group('activities', () {
    test('logActivity stores a completed touchpoint', () async {
      final customer = await makeCustomer();

      final activity = await service.logActivity(
        customerId: customer.id,
        activityType: CollectionActivityType.call,
        notes: 'Said cheque is posted',
        amountCollected: 0,
      );

      expect(activity.status, CollectionActivityStatus.completed);
      final history = await service.getActivitiesForCustomer(customer.id);
      expect(history.single.id, activity.id);
    });

    test('logActivity rejects an unknown customer before writing', () async {
      expect(
        () => service.logActivity(
          customerId: 'ghost',
          activityType: CollectionActivityType.call,
        ),
        throwsA(isA<CollectionCustomerNotFound>()),
      );
    });

    test('scheduleFollowUp stores a pending reminder', () async {
      final customer = await makeCustomer();

      final activity = await service.scheduleFollowUp(
        customerId: customer.id,
        activityType: CollectionActivityType.whatsapp,
        scheduledDate: asOf.add(const Duration(days: 7)),
        now: asOf,
      );

      expect(activity.isPending, isTrue);
      expect(activity.scheduledDate, secs(asOf.add(const Duration(days: 7))));
      expect(await service.getPendingFollowUps(), hasLength(1));
    });

    test('a follow-up cannot be scheduled in the past', () async {
      final customer = await makeCustomer();

      expect(
        () => service.scheduleFollowUp(
          customerId: customer.id,
          activityType: CollectionActivityType.call,
          scheduledDate: asOf.subtract(const Duration(days: 1)),
          now: asOf,
        ),
        throwsA(isA<InvalidFollowUpDate>()),
      );
    });

    test('isDue only counts pending reminders whose date has arrived', () async {
      final customer = await makeCustomer();
      final due = await service.scheduleFollowUp(
        customerId: customer.id,
        activityType: CollectionActivityType.call,
        scheduledDate: asOf.add(const Duration(days: 1)),
        now: asOf,
      );

      expect(due.isDue(asOf: asOf), isFalse);
      expect(due.isDue(asOf: asOf.add(const Duration(days: 2))), isTrue);

      // A logged activity has no scheduled date and is never "due".
      final logged = await service.logActivity(
        customerId: customer.id,
        activityType: CollectionActivityType.call,
      );
      expect(logged.isDue(asOf: asOf.add(const Duration(days: 365))), isFalse);
    });

    test('getDueFollowUps returns only what has come due', () async {
      final customer = await makeCustomer();
      await service.scheduleFollowUp(
        customerId: customer.id,
        activityType: CollectionActivityType.call,
        scheduledDate: asOf.add(const Duration(days: 2)),
        now: asOf,
      );
      await service.scheduleFollowUp(
        customerId: customer.id,
        activityType: CollectionActivityType.visit,
        scheduledDate: asOf.add(const Duration(days: 40)),
        now: asOf,
      );

      final due = await service.getDueFollowUps(dueBy: asOf.add(const Duration(days: 10)));

      expect(due, hasLength(1));
      expect(due.single.activityType, CollectionActivityType.call);
    });

    test('completing a follow-up records the outcome', () async {
      final customer = await makeCustomer();
      final scheduled = await service.scheduleFollowUp(
        customerId: customer.id,
        activityType: CollectionActivityType.call,
        scheduledDate: asOf.add(const Duration(days: 1)),
        now: asOf,
      );

      final completed = await service.completeActivity(
        scheduled.id,
        completedDate: asOf.add(const Duration(days: 1)),
        notes: 'Collected in full',
        amountCollected: 1500,
      );

      expect(completed.status, CollectionActivityStatus.completed);
      expect(completed.amountCollected, 1500);
      // It leaves the pending worklist.
      expect(await service.getPendingFollowUps(), isEmpty);
    });

    test('completing twice is refused', () async {
      final customer = await makeCustomer();
      final scheduled = await service.scheduleFollowUp(
        customerId: customer.id,
        activityType: CollectionActivityType.call,
        scheduledDate: asOf.add(const Duration(days: 1)),
        now: asOf,
      );
      await service.completeActivity(scheduled.id);

      expect(
        () => service.completeActivity(scheduled.id),
        throwsA(isA<InvalidCollectionActivityState>()),
      );
    });

    test('skipping keeps the row in the history but out of the worklist', () async {
      final customer = await makeCustomer();
      final scheduled = await service.scheduleFollowUp(
        customerId: customer.id,
        activityType: CollectionActivityType.call,
        scheduledDate: asOf.add(const Duration(days: 1)),
        now: asOf,
      );

      final skipped = await service.skipActivity(scheduled.id, notes: 'Paid before we called');

      expect(skipped.status, CollectionActivityStatus.skipped);
      expect(await service.getPendingFollowUps(), isEmpty);
      expect(await service.getActivitiesForCustomer(customer.id), hasLength(1));
    });

    test('a completed activity cannot be deleted', () async {
      final customer = await makeCustomer();
      final logged = await service.logActivity(
        customerId: customer.id,
        activityType: CollectionActivityType.call,
      );

      expect(
        () => service.deleteFollowUp(logged.id),
        throwsA(isA<InvalidCollectionActivityState>()),
      );
    });

    test('a pending follow-up can be deleted', () async {
      final customer = await makeCustomer();
      final scheduled = await service.scheduleFollowUp(
        customerId: customer.id,
        activityType: CollectionActivityType.call,
        scheduledDate: asOf.add(const Duration(days: 1)),
        now: asOf,
      );

      await service.deleteFollowUp(scheduled.id);

      expect(await service.getPendingFollowUps(), isEmpty);
    });

    test('acting on an unknown activity is refused', () async {
      expect(
        () => service.completeActivity('ghost'),
        throwsA(isA<CollectionActivityNotFound>()),
      );
    });
  });

  group('dues reminder', () {
    test('the message states the balance and the age of the oldest item', () async {
      final customer = await makeCustomer(name: 'Priya');
      await addLedger(customer.id, amount: 2500, daysAgo: 47);

      final aging = (await service.getCustomerAging(customer.id, asOf: asOf))!;
      final message = service.buildDuesReminderMessage(aging);

      expect(message, contains('Priya'));
      expect(message, contains('2500.00'));
      expect(message, contains('47 days'));
    });

    test('sending goes through the injected sender and logs the attempt', () async {
      final customer = await makeCustomer(name: 'Priya', phone: '9000000001');
      await addLedger(customer.id, amount: 800, daysAgo: 40);

      String? sentTo;
      String? sentMessage;
      final activity = await service.sendDuesReminder(
        customer.id,
        asOf: asOf,
        sender: ({required String phone, required String message}) async {
          sentTo = phone;
          sentMessage = message;
        },
      );

      expect(sentTo, '9000000001');
      expect(sentMessage, contains('800.00'));
      expect(activity.activityType, CollectionActivityType.whatsapp);
      expect(activity.status, CollectionActivityStatus.completed);
      expect(await service.getActivitiesForCustomer(customer.id), hasLength(1));
    });

    test('a customer with no phone number is refused before sending', () async {
      final customer = await makeCustomer(name: 'Anon', phone: '');
      await addLedger(customer.id, amount: 400, daysAgo: 40);

      var senderCalled = false;
      expect(
        () => service.sendDuesReminder(
          customer.id,
          asOf: asOf,
          sender: ({required String phone, required String message}) async {
            senderCalled = true;
          },
        ),
        throwsA(isA<NoContactNumber>()),
      );
      expect(senderCalled, isFalse);
    });

    test('a customer who owes nothing gets no reminder', () async {
      final customer = await makeCustomer();

      expect(
        () => service.sendDuesReminder(
          customer.id,
          asOf: asOf,
          sender: ({required String phone, required String message}) async {},
        ),
        throwsA(isA<InvalidCollectionActivityState>()),
      );
    });
  });
}
