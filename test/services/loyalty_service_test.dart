import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:supermart_pos/core/database/database_helper.dart';
import 'package:supermart_pos/models/customer_model.dart';
import 'package:supermart_pos/models/loyalty_point_event_model.dart';
import 'package:supermart_pos/repositories/loyalty_event_repository.dart';
import 'package:supermart_pos/repositories/store_repository.dart';
import 'package:supermart_pos/services/loyalty_exceptions.dart';
import 'package:supermart_pos/services/loyalty_service.dart';

class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this._path);
  final String _path;

  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late LoyaltyService service;
  late LoyaltyEventRepository events;
  late StoreRepository stores;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('loyalty_service_test');
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
    service = LoyaltyService();
    events = LoyaltyEventRepository();
    stores = StoreRepository();
    final db = await DatabaseHelper.instance.database;
    await db.delete('bonus_points');
    await db.delete('audit_log');
    await db.delete('customers');
    await db.delete('users');
    // Back to the shipped defaults; individual tests opt into expiry.
    await stores.updateLoyaltyExpiryDays(0);
    await stores.updateLoyaltyValuePerPoint(0.5);
  });

  /// `audit_log.user_id` has a real FK to `users`, and `adjustPoints` writes an
  /// audit row inside its transaction — so the acting user has to exist.
  Future<String> makeUser(String id) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert('users', {
      'id': id,
      'username': id,
      'password_hash': 'x',
      'role': 'manager',
      'name': 'Manager $id',
    });
    return id;
  }

  var phoneSeq = 0;
  Future<Customer> makeCustomer({int points = 0, String name = 'Test Customer'}) async {
    phoneSeq++;
    final customer = Customer.create(phone: '80000000$phoneSeq', name: name);
    final db = await DatabaseHelper.instance.database;
    await db.insert('customers', customer.toJson()..['loyalty_points'] = points);
    return customer;
  }

  Future<int> balanceOf(String customerId) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query('customers', columns: ['loyalty_points'], where: 'id = ?', whereArgs: [customerId]);
    return (rows.first['loyalty_points'] as num).toInt();
  }

  Future<LoyaltyPointEvent> addEvent(
    String customerId, {
    int earned = 0,
    int redeemed = 0,
    LoyaltyEventType type = LoyaltyEventType.sale,
    required DateTime date,
    DateTime? expiresAt,
  }) {
    return events.insertEvent(LoyaltyPointEvent.create(
      customerId: customerId,
      pointsEarned: earned,
      pointsRedeemed: redeemed,
      eventType: type,
      date: date,
      expiresAt: expiresAt,
    ));
  }

  group('expiryDateFor', () {
    test('returns null when the store has expiry switched off — the default', () async {
      expect(await service.expiryDateFor(DateTime(2025, 1, 1)), isNull);
    });

    test('adds the configured window to the earn date', () async {
      await stores.updateLoyaltyExpiryDays(365);

      expect(await service.expiryDateFor(DateTime(2025, 1, 1)), DateTime(2026, 1, 1));
    });

    test('treats a negative setting as off rather than expiring points in the past', () async {
      await stores.updateLoyaltyExpiryDays(-30);

      expect(await service.expiryDateFor(DateTime(2025, 1, 1)), isNull);
    });
  });

  group('expireOldPointsForCustomer', () {
    test('expires the unspent remainder of a lapsed lot and logs it', () async {
      final customer = await makeCustomer(points: 70);
      await addEvent(customer.id, earned: 100, date: DateTime(2025, 1, 1), expiresAt: DateTime(2025, 3, 1));
      await addEvent(customer.id, redeemed: 30, date: DateTime(2025, 2, 1));

      final result = await service.expireOldPointsForCustomer(customer.id, asOf: DateTime(2025, 3, 2));

      expect(result.pointsExpired, 70);
      expect(result.customersAffected, 1);
      expect(await balanceOf(customer.id), 0);

      final logged = (await events.getEventsForCustomer(customer.id))
          .where((e) => e.eventType == LoyaltyEventType.expire)
          .single;
      expect(logged.pointsRedeemed, 70);
      expect(logged.saleId, isNull);
    });

    test('expires nothing when the lapsed lot was already spent', () async {
      final customer = await makeCustomer(points: 0);
      await addEvent(customer.id, earned: 100, date: DateTime(2025, 1, 1), expiresAt: DateTime(2025, 3, 1));
      await addEvent(customer.id, redeemed: 100, date: DateTime(2025, 2, 1));

      final result = await service.expireOldPointsForCustomer(customer.id, asOf: DateTime(2025, 3, 2));

      expect(result.pointsExpired, 0);
      expect(result.customersAffected, 0);
      expect(await balanceOf(customer.id), 0);
    });

    test('leaves a lot alone before its date', () async {
      final customer = await makeCustomer(points: 100);
      await addEvent(customer.id, earned: 100, date: DateTime(2025, 1, 1), expiresAt: DateTime(2025, 6, 1));

      final result = await service.expireOldPointsForCustomer(customer.id, asOf: DateTime(2025, 3, 1));

      expect(result.pointsExpired, 0);
      expect(await balanceOf(customer.id), 100);
    });

    test('never expires points earned with no expiry date', () async {
      final customer = await makeCustomer(points: 100);
      await addEvent(customer.id, earned: 100, date: DateTime(2020, 1, 1));

      final result = await service.expireOldPointsForCustomer(customer.id, asOf: DateTime(2030, 1, 1));

      expect(result.pointsExpired, 0);
      expect(await balanceOf(customer.id), 100);
    });

    test('consumes lots oldest-first, so spending protects the oldest lot', () async {
      // 100 earned Jan (lapses Mar), 50 earned Feb (lapses Apr), 120 spent
      // mid-Feb. FIFO puts all 100 of the Jan lot against that spend, so when
      // March passes the Jan lot has nothing left to lose.
      final customer = await makeCustomer(points: 30);
      await addEvent(customer.id, earned: 100, date: DateTime(2025, 1, 1), expiresAt: DateTime(2025, 3, 1));
      await addEvent(customer.id, earned: 50, date: DateTime(2025, 2, 1), expiresAt: DateTime(2025, 4, 1));
      await addEvent(customer.id, redeemed: 120, date: DateTime(2025, 2, 15));

      final march = await service.expireOldPointsForCustomer(customer.id, asOf: DateTime(2025, 3, 2));

      expect(march.pointsExpired, 0);
      expect(await balanceOf(customer.id), 30);

      // April: the Feb lot's surviving 30 finally lapses.
      final april = await service.expireOldPointsForCustomer(customer.id, asOf: DateTime(2025, 4, 2));

      expect(april.pointsExpired, 30);
      expect(await balanceOf(customer.id), 0);
    });

    test('is idempotent — a second sweep takes nothing more', () async {
      final customer = await makeCustomer(points: 70);
      await addEvent(customer.id, earned: 100, date: DateTime(2025, 1, 1), expiresAt: DateTime(2025, 3, 1));
      await addEvent(customer.id, redeemed: 30, date: DateTime(2025, 2, 1));

      final first = await service.expireOldPointsForCustomer(customer.id, asOf: DateTime(2025, 3, 2));
      final second = await service.expireOldPointsForCustomer(customer.id, asOf: DateTime(2025, 3, 3));
      final third = await service.expireOldPointsForCustomer(customer.id, asOf: DateTime(2026, 1, 1));

      expect(first.pointsExpired, 70);
      expect(second.pointsExpired, 0);
      expect(third.pointsExpired, 0);
      expect(await balanceOf(customer.id), 0);
      expect(
        (await events.getEventsForCustomer(customer.id)).where((e) => e.eventType == LoyaltyEventType.expire),
        hasLength(1),
      );
    });

    test('writes the write-off back onto the lot so its remainder shrinks', () async {
      final customer = await makeCustomer(points: 100);
      final lot = await addEvent(
        customer.id,
        earned: 100,
        date: DateTime(2025, 1, 1),
        expiresAt: DateTime(2025, 3, 1),
      );

      await service.expireOldPointsForCustomer(customer.id, asOf: DateTime(2025, 3, 2));

      final reread = (await events.getEventsForCustomer(customer.id)).firstWhere((e) => e.id == lot.id);
      expect(reread.expiredPoints, 100);
      expect(reread.unexpiredEarned, 0);
    });

    test('never drives the running balance negative when the log and balance disagree', () async {
      // The lots claim 100 unspent; the customer's actual balance says 40 —
      // the sort of drift a hand-edited row or a pre-event-log sale leaves.
      final customer = await makeCustomer(points: 40);
      await addEvent(customer.id, earned: 100, date: DateTime(2025, 1, 1), expiresAt: DateTime(2025, 3, 1));

      final result = await service.expireOldPointsForCustomer(customer.id, asOf: DateTime(2025, 3, 2));

      expect(result.pointsExpired, 40);
      expect(await balanceOf(customer.id), 0);
    });

    test('does nothing for a customer with no events at all', () async {
      final customer = await makeCustomer(points: 25);

      final result = await service.expireOldPointsForCustomer(customer.id, asOf: DateTime(2030, 1, 1));

      expect(result.pointsExpired, 0);
      expect(await balanceOf(customer.id), 25);
    });

    test('throws for an unknown customer rather than silently succeeding', () async {
      expect(
        () => service.expireOldPointsForCustomer('no-such-customer'),
        throwsA(isA<LoyaltyCustomerNotFound>()),
      );
    });
  });

  group('expireOldPoints (store-wide sweep)', () {
    test('only touches customers with a due lot, and reports both counts', () async {
      final loses = await makeCustomer(points: 50, name: 'Loses');
      final spent = await makeCustomer(points: 0, name: 'Spent');
      final safe = await makeCustomer(points: 80, name: 'Safe');

      await addEvent(loses.id, earned: 50, date: DateTime(2025, 1, 1), expiresAt: DateTime(2025, 3, 1));
      await addEvent(spent.id, earned: 40, date: DateTime(2025, 1, 1), expiresAt: DateTime(2025, 3, 1));
      await addEvent(spent.id, redeemed: 40, date: DateTime(2025, 2, 1));
      await addEvent(safe.id, earned: 80, date: DateTime(2025, 1, 1), expiresAt: DateTime(2026, 3, 1));

      final result = await service.expireOldPoints(asOf: DateTime(2025, 3, 2));

      // Both lapsed-lot holders are candidates; only one actually loses points.
      expect(result.customersProcessed, 2);
      expect(result.customersAffected, 1);
      expect(result.pointsExpired, 50);
      expect(result.events, hasLength(1));
      expect(await balanceOf(loses.id), 0);
      expect(await balanceOf(safe.id), 80);
    });

    test('reports an empty result on a store with nothing to expire', () async {
      await makeCustomer(points: 10);

      final result = await service.expireOldPoints(asOf: DateTime(2025, 3, 2));

      expect(result.isEmpty, isTrue);
      expect(result.customersProcessed, 0);
    });
  });

  group('adjustPoints', () {
    test('grants points, updates the balance and logs an adjust event', () async {
      final customer = await makeCustomer(points: 10);
      await makeUser('user-1');

      final event = await service.adjustPoints(
        customerId: customer.id,
        points: 25,
        note: 'Goodwill for a damaged item',
        userId: 'user-1',
      );

      expect(await balanceOf(customer.id), 35);
      expect(event.eventType, LoyaltyEventType.adjust);
      expect(event.pointsEarned, 25);
      expect(event.pointsRedeemed, 0);
      expect(event.note, 'Goodwill for a damaged item');
      expect(event.createdByUserId, 'user-1');
    });

    test('deducts points', () async {
      final customer = await makeCustomer(points: 40);
      await makeUser('user-1');

      final event = await service.adjustPoints(
        customerId: customer.id,
        points: -15,
        note: 'Correcting a mis-keyed bill',
        userId: 'user-1',
      );

      expect(await balanceOf(customer.id), 25);
      expect(event.pointsEarned, 0);
      expect(event.pointsRedeemed, 15);
    });

    test('refuses to deduct more than the customer holds', () async {
      final customer = await makeCustomer(points: 5);

      await expectLater(
        service.adjustPoints(customerId: customer.id, points: -10, note: 'Too much', userId: 'u'),
        throwsA(isA<InsufficientLoyaltyPoints>()),
      );
      expect(await balanceOf(customer.id), 5);
    });

    test('refuses a zero adjustment', () async {
      final customer = await makeCustomer(points: 5);

      expect(
        () => service.adjustPoints(customerId: customer.id, points: 0, note: 'Nothing', userId: 'u'),
        throwsA(isA<InvalidLoyaltyAdjustment>()),
      );
    });

    test('refuses an adjustment with no reason', () async {
      final customer = await makeCustomer(points: 5);

      expect(
        () => service.adjustPoints(customerId: customer.id, points: 5, note: '   ', userId: 'u'),
        throwsA(isA<InvalidLoyaltyAdjustment>()),
      );
    });

    test('throws for an unknown customer and writes nothing', () async {
      await expectLater(
        service.adjustPoints(customerId: 'nobody', points: 5, note: 'x', userId: 'u'),
        throwsA(isA<LoyaltyCustomerNotFound>()),
      );

      final db = await DatabaseHelper.instance.database;
      expect(await db.query('bonus_points'), isEmpty);
    });

    test('stamps granted points with the store expiry window', () async {
      await stores.updateLoyaltyExpiryDays(90);
      final customer = await makeCustomer(points: 0);
      await makeUser('u');

      final event = await service.adjustPoints(
        customerId: customer.id,
        points: 10,
        note: 'Grant',
        userId: 'u',
        at: DateTime(2025, 1, 1),
      );

      expect(event.expiresAtDateTime, DateTime(2025, 4, 1));
    });

    test('does not put an expiry date on a deduction', () async {
      await stores.updateLoyaltyExpiryDays(90);
      final customer = await makeCustomer(points: 50);
      await makeUser('u');

      final event = await service.adjustPoints(
        customerId: customer.id,
        points: -10,
        note: 'Deduct',
        userId: 'u',
      );

      expect(event.expiresAt, isNull);
    });

    test('records the adjustment in the audit log', () async {
      final customer = await makeCustomer(points: 0);
      await makeUser('user-7');

      await service.adjustPoints(customerId: customer.id, points: 7, note: 'Why', userId: 'user-7');

      final db = await DatabaseHelper.instance.database;
      final rows = await db.query('audit_log', where: 'action_type = ?', whereArgs: ['LOYALTY_POINTS_ADJUSTED']);
      expect(rows, hasLength(1));
      expect(rows.first['user_id'], 'user-7');
      expect(rows.first['new_value'], contains('"points":7'));
    });

    test('granted points then take part in expiry like any other lot', () async {
      await stores.updateLoyaltyExpiryDays(30);
      final customer = await makeCustomer(points: 0);
      await makeUser('u');
      await service.adjustPoints(
        customerId: customer.id,
        points: 20,
        note: 'Grant',
        userId: 'u',
        at: DateTime(2025, 1, 1),
      );

      final result = await service.expireOldPointsForCustomer(customer.id, asOf: DateTime(2025, 3, 1));

      expect(result.pointsExpired, 20);
      expect(await balanceOf(customer.id), 0);
    });
  });

  group('getCustomerSummary', () {
    test('reports balance, value, tier and lifetime totals', () async {
      await stores.updateLoyaltyValuePerPoint(2);
      final customer = await makeCustomer(points: 45);
      await addEvent(customer.id, earned: 100, date: DateTime(2025, 1, 1));
      await addEvent(customer.id, redeemed: 40, date: DateTime(2025, 2, 1));
      await addEvent(customer.id, redeemed: 15, date: DateTime(2025, 2, 5), type: LoyaltyEventType.expire);

      final summary = await service.getCustomerSummary(customer.id);

      expect(summary.pointsBalance, 45);
      expect(summary.valuePerPoint, 2);
      expect(summary.pointsValue, 90);
      expect(summary.tier, CustomerRating.regular);
      expect(summary.lifetimeEarned, 100);
      expect(summary.lifetimeRedeemed, 40);
      expect(summary.lifetimeExpired, 15);
      expect(summary.recentEvents, hasLength(3));
    });

    test('caps "expiring soon" at what the customer actually holds', () async {
      // The lot says 100 are due; the customer has already spent down to 20.
      // Warning them about 100 would be a lie.
      final customer = await makeCustomer(points: 20);
      await addEvent(
        customer.id,
        earned: 100,
        date: DateTime(2025, 1, 1),
        expiresAt: DateTime.now().add(const Duration(days: 5)),
      );

      final summary = await service.getCustomerSummary(customer.id);

      expect(summary.pointsExpiringSoon, 20);
    });

    test('ignores lots expiring beyond the warning window', () async {
      final customer = await makeCustomer(points: 100);
      await addEvent(
        customer.id,
        earned: 100,
        date: DateTime(2025, 1, 1),
        expiresAt: DateTime.now().add(const Duration(days: 400)),
      );

      final summary = await service.getCustomerSummary(customer.id);

      expect(summary.pointsExpiringSoon, 0);
      expect(summary.nextExpiryDate, isNotNull);
    });

    test('nextExpiryDate is the earliest surviving lot', () async {
      final customer = await makeCustomer(points: 30);
      await addEvent(customer.id, earned: 10, date: DateTime(2025, 1, 1), expiresAt: DateTime(2026, 5, 1));
      await addEvent(customer.id, earned: 20, date: DateTime(2025, 2, 1), expiresAt: DateTime(2026, 2, 1));

      final summary = await service.getCustomerSummary(customer.id);

      expect(summary.nextExpiryDate, DateTime(2026, 2, 1));
    });

    test('nextExpiryDate is null when nothing has an expiry', () async {
      final customer = await makeCustomer(points: 30);
      await addEvent(customer.id, earned: 30, date: DateTime(2025, 1, 1));

      expect((await service.getCustomerSummary(customer.id)).nextExpiryDate, isNull);
    });

    test('honours recentLimit without distorting lifetime totals', () async {
      final customer = await makeCustomer(points: 5);
      for (var i = 1; i <= 6; i++) {
        await addEvent(customer.id, earned: 1, date: DateTime(2025, 1, i));
      }

      final summary = await service.getCustomerSummary(customer.id, recentLimit: 2);

      expect(summary.recentEvents, hasLength(2));
      expect(summary.lifetimeEarned, 6);
    });

    test('throws for an unknown customer', () async {
      expect(() => service.getCustomerSummary('nobody'), throwsA(isA<LoyaltyCustomerNotFound>()));
    });
  });

  group('getStoreSummary', () {
    test('totals outstanding points and prices them as a liability', () async {
      await stores.updateLoyaltyValuePerPoint(0.5);
      await makeCustomer(points: 200, name: 'A');
      await makeCustomer(points: 100, name: 'B');
      await makeCustomer(points: 0, name: 'C');

      final summary = await service.getStoreSummary();

      expect(summary.outstandingPoints, 300);
      expect(summary.customersWithPoints, 2);
      expect(summary.outstandingValue, 150);
      expect(summary.expiryEnabled, isFalse);
    });

    test('splits period activity into earned, redeemed and expired', () async {
      final customer = await makeCustomer(points: 10, name: 'A');
      await addEvent(customer.id, earned: 50, date: DateTime(2025, 5, 5));
      await addEvent(customer.id, redeemed: 20, date: DateTime(2025, 5, 6));
      await addEvent(customer.id, redeemed: 20, date: DateTime(2025, 5, 7), type: LoyaltyEventType.expire);
      await addEvent(customer.id, earned: 999, date: DateTime(2025, 9, 1));

      final summary = await service.getStoreSummary(
        from: DateTime(2025, 5, 1),
        to: DateTime(2025, 5, 31),
      );

      expect(summary.pointsEarnedInPeriod, 50);
      expect(summary.pointsRedeemedInPeriod, 20);
      expect(summary.pointsExpiredInPeriod, 20);
    });

    test('reports the expiry setting so the UI can say whether it is on', () async {
      await stores.updateLoyaltyExpiryDays(180);

      final summary = await service.getStoreSummary();

      expect(summary.expiryDays, 180);
      expect(summary.expiryEnabled, isTrue);
    });
  });

  group('recomputeBalanceFromEvents', () {
    test('rebuilds the balance from the log without writing anything', () async {
      final customer = await makeCustomer(points: 999);
      await addEvent(customer.id, earned: 100, date: DateTime(2025, 1, 1));
      await addEvent(customer.id, redeemed: 30, date: DateTime(2025, 2, 1));
      await addEvent(customer.id, redeemed: 20, date: DateTime(2025, 3, 1), type: LoyaltyEventType.expire);

      expect(await service.recomputeBalanceFromEvents(customer.id), 50);
      // Deliberately does not repair the drift — see the method's doc comment.
      expect(await balanceOf(customer.id), 999);
    });

    test('is zero for a customer with no events', () async {
      final customer = await makeCustomer(points: 12);
      expect(await service.recomputeBalanceFromEvents(customer.id), 0);
    });
  });

  group('tierForSpend', () {
    test('maps spend onto this store\'s four-tier ladder', () async {
      expect(await service.tierForSpend(0), CustomerRating.regular);
      expect(await service.tierForSpend(2000), CustomerRating.bronze);
      expect(await service.tierForSpend(10000), CustomerRating.silver);
      expect(await service.tierForSpend(25000), CustomerRating.gold);
    });
  });
}
