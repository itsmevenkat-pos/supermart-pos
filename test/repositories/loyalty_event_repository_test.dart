import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:supermart_pos/core/database/database_helper.dart';
import 'package:supermart_pos/models/customer_model.dart';
import 'package:supermart_pos/models/loyalty_point_event_model.dart';
import 'package:supermart_pos/repositories/loyalty_event_repository.dart';

class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this._path);
  final String _path;

  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late LoyaltyEventRepository repository;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('loyalty_event_repo_test');
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
    repository = LoyaltyEventRepository();
    final db = await DatabaseHelper.instance.database;
    await db.delete('bonus_points');
    await db.delete('sales');
    await db.delete('customers');
  });

  var invoiceSeq = 0;

  /// `bonus_points.sale_id` has a real FK to `sales`, so an event that names a
  /// sale needs that sale to exist. Only the NOT NULL columns are set — nothing
  /// here reads the rest.
  Future<String> makeSale(String id) async {
    invoiceSeq++;
    final db = await DatabaseHelper.instance.database;
    await db.insert('sales', {
      'id': id,
      'invoice_no': invoiceSeq,
      'net_amount': 0,
      'created_at': DateTime(2025).millisecondsSinceEpoch ~/ 1000,
    });
    return id;
  }

  var phoneSeq = 0;
  Future<Customer> makeCustomer({int points = 0, String name = 'Test Customer'}) async {
    phoneSeq++;
    final customer = Customer.create(phone: '90000000$phoneSeq', name: name);
    final db = await DatabaseHelper.instance.database;
    await db.insert('customers', customer.toJson()..['loyalty_points'] = points);
    return customer;
  }

  Future<LoyaltyPointEvent> addEvent(
    String customerId, {
    int earned = 0,
    int redeemed = 0,
    LoyaltyEventType type = LoyaltyEventType.sale,
    DateTime? date,
    DateTime? expiresAt,
  }) {
    return repository.insertEvent(LoyaltyPointEvent.create(
      customerId: customerId,
      pointsEarned: earned,
      pointsRedeemed: redeemed,
      eventType: type,
      date: date,
      expiresAt: expiresAt,
    ));
  }

  group('insertEvent / getEventsForCustomer', () {
    test('round-trips every column through sqflite', () async {
      final customer = await makeCustomer();
      await makeSale('sale-1');
      final written = await repository.insertEvent(LoyaltyPointEvent.create(
        customerId: customer.id,
        saleId: 'sale-1',
        pointsEarned: 12,
        pointsRedeemed: 3,
        eventType: LoyaltyEventType.sale,
        date: DateTime(2025, 4, 2),
        expiresAt: DateTime(2026, 4, 2),
        note: 'a note',
        createdByUserId: 'user-1',
      ));

      final read = (await repository.getEventsForCustomer(customer.id)).single;

      expect(read, written);
      expect(read.saleId, 'sale-1');
      expect(read.pointsEarned, 12);
      expect(read.pointsRedeemed, 3);
      expect(read.eventType, LoyaltyEventType.sale);
      expect(read.expiresAtDateTime, DateTime(2026, 4, 2));
      expect(read.note, 'a note');
      expect(read.createdByUserId, 'user-1');
    });

    test('returns newest first', () async {
      final customer = await makeCustomer();
      await addEvent(customer.id, earned: 1, date: DateTime(2025, 1, 1));
      await addEvent(customer.id, earned: 2, date: DateTime(2025, 3, 1));
      await addEvent(customer.id, earned: 3, date: DateTime(2025, 2, 1));

      final events = await repository.getEventsForCustomer(customer.id);

      expect(events.map((e) => e.pointsEarned), [2, 3, 1]);
    });

    test('filters by date range inclusively', () async {
      final customer = await makeCustomer();
      await addEvent(customer.id, earned: 1, date: DateTime(2025, 1, 1));
      await addEvent(customer.id, earned: 2, date: DateTime(2025, 2, 1));
      await addEvent(customer.id, earned: 3, date: DateTime(2025, 3, 1));

      final events = await repository.getEventsForCustomer(
        customer.id,
        from: DateTime(2025, 2, 1),
        to: DateTime(2025, 3, 1),
      );

      expect(events.map((e) => e.pointsEarned), [3, 2]);
    });

    test('honours the limit', () async {
      final customer = await makeCustomer();
      for (var i = 0; i < 5; i++) {
        await addEvent(customer.id, earned: 1, date: DateTime(2025, 1, i + 1));
      }

      expect(await repository.getEventsForCustomer(customer.id, limit: 2), hasLength(2));
    });

    test('does not leak another customer\'s events', () async {
      final a = await makeCustomer(name: 'A');
      final b = await makeCustomer(name: 'B');
      await addEvent(a.id, earned: 5);
      await addEvent(b.id, earned: 7);

      final events = await repository.getEventsForCustomer(a.id);

      expect(events.single.pointsEarned, 5);
    });
  });

  group('getEventsInRange', () {
    test('spans customers and filters by type', () async {
      final a = await makeCustomer(name: 'A');
      final b = await makeCustomer(name: 'B');
      await addEvent(a.id, earned: 5, date: DateTime(2025, 5, 10));
      await addEvent(b.id, redeemed: 2, date: DateTime(2025, 5, 11), type: LoyaltyEventType.adjust);
      await addEvent(b.id, earned: 9, date: DateTime(2025, 7, 1));

      final all = await repository.getEventsInRange(
        from: DateTime(2025, 5, 1),
        to: DateTime(2025, 5, 31),
      );
      final adjustments = await repository.getEventsInRange(
        from: DateTime(2025, 5, 1),
        to: DateTime(2025, 5, 31),
        eventType: LoyaltyEventType.adjust,
      );

      expect(all, hasLength(2));
      expect(adjustments.single.pointsRedeemed, 2);
    });
  });

  group('getEventForSale', () {
    test('finds the sale event and ignores the cancellation on the same sale', () async {
      final customer = await makeCustomer();
      await makeSale('sale-9');
      await repository.insertEvent(LoyaltyPointEvent.create(
        customerId: customer.id,
        saleId: 'sale-9',
        pointsEarned: 20,
        date: DateTime(2025, 1, 1),
      ));
      await repository.insertEvent(LoyaltyPointEvent.create(
        customerId: customer.id,
        saleId: 'sale-9',
        pointsRedeemed: 20,
        eventType: LoyaltyEventType.cancellation,
        date: DateTime(2025, 1, 2),
      ));

      final event = await repository.getEventForSale('sale-9');

      expect(event!.pointsEarned, 20);
      expect(event.eventType, LoyaltyEventType.sale);
    });

    test('returns null when the sale earned nothing', () async {
      expect(await repository.getEventForSale('no-such-sale'), isNull);
    });
  });

  group('getEarnLotsForCustomer', () {
    test('returns only rows that earned, oldest first', () async {
      final customer = await makeCustomer();
      await addEvent(customer.id, earned: 10, date: DateTime(2025, 3, 1));
      await addEvent(customer.id, redeemed: 4, date: DateTime(2025, 3, 2));
      await addEvent(customer.id, earned: 6, date: DateTime(2025, 1, 1));

      final lots = await repository.getEarnLotsForCustomer(customer.id);

      expect(lots.map((e) => e.pointsEarned), [6, 10]);
    });
  });

  group('getRedeemedTotalExcludingExpiry', () {
    test('sums spending but skips expiry write-offs', () async {
      final customer = await makeCustomer();
      await addEvent(customer.id, redeemed: 5);
      await addEvent(customer.id, redeemed: 3, type: LoyaltyEventType.adjust);
      await addEvent(customer.id, redeemed: 100, type: LoyaltyEventType.expire);

      expect(await repository.getRedeemedTotalExcludingExpiry(customer.id), 8);
    });

    test('is zero for a customer with no events', () async {
      final customer = await makeCustomer();
      expect(await repository.getRedeemedTotalExcludingExpiry(customer.id), 0);
    });
  });

  group('getCustomerIdsWithDueLots', () {
    test('lists customers with a lapsed, not-fully-written-off lot', () async {
      final due = await makeCustomer(name: 'Due');
      final future = await makeCustomer(name: 'Future');
      final never = await makeCustomer(name: 'Never');
      await addEvent(due.id, earned: 10, date: DateTime(2025, 1, 1), expiresAt: DateTime(2025, 6, 1));
      await addEvent(future.id, earned: 10, date: DateTime(2025, 1, 1), expiresAt: DateTime(2026, 6, 1));
      await addEvent(never.id, earned: 10, date: DateTime(2025, 1, 1));

      final ids = await repository.getCustomerIdsWithDueLots(DateTime(2025, 7, 1));

      expect(ids, [due.id]);
    });

    test('excludes a lot already fully written off', () async {
      final customer = await makeCustomer();
      final lot = await addEvent(
        customer.id,
        earned: 10,
        date: DateTime(2025, 1, 1),
        expiresAt: DateTime(2025, 6, 1),
      );
      await repository.addExpiredPoints(lot.id, 10);

      expect(await repository.getCustomerIdsWithDueLots(DateTime(2025, 7, 1)), isEmpty);
    });
  });

  group('addExpiredPoints', () {
    test('accumulates rather than overwriting, so two sweeps compose', () async {
      final customer = await makeCustomer();
      final lot = await addEvent(customer.id, earned: 10, expiresAt: DateTime(2025, 6, 1));

      await repository.addExpiredPoints(lot.id, 4);
      await repository.addExpiredPoints(lot.id, 3);

      final read = (await repository.getEventsForCustomer(customer.id)).single;
      expect(read.expiredPoints, 7);
      expect(read.unexpiredEarned, 3);
    });

    test('ignores a non-positive amount instead of corrupting the lot', () async {
      final customer = await makeCustomer();
      final lot = await addEvent(customer.id, earned: 10);

      await repository.addExpiredPoints(lot.id, 0);
      await repository.addExpiredPoints(lot.id, -5);

      expect((await repository.getEventsForCustomer(customer.id)).single.expiredPoints, 0);
    });
  });

  group('store-wide aggregates', () {
    test('outstanding points and customer count read the running balance', () async {
      await makeCustomer(points: 120, name: 'A');
      await makeCustomer(points: 30, name: 'B');
      await makeCustomer(points: 0, name: 'C');

      expect(await repository.getTotalOutstandingPoints(), 150);
      expect(await repository.getCustomerCountWithPoints(), 2);
    });

    test('are zero on an empty database rather than null', () async {
      expect(await repository.getTotalOutstandingPoints(), 0);
      expect(await repository.getCustomerCountWithPoints(), 0);
    });
  });

  group('getPointsExpiringBefore', () {
    test('sums the unexpired remainder of lots due before the cutoff', () async {
      final customer = await makeCustomer();
      final lot = await addEvent(customer.id, earned: 10, expiresAt: DateTime(2025, 6, 1));
      await repository.addExpiredPoints(lot.id, 4);
      await addEvent(customer.id, earned: 7, expiresAt: DateTime(2025, 7, 1));
      await addEvent(customer.id, earned: 99, expiresAt: DateTime(2030, 1, 1));
      await addEvent(customer.id, earned: 50);

      expect(await repository.getPointsExpiringBefore(DateTime(2025, 8, 1)), 13);
    });

    test('scopes to one customer when asked', () async {
      final a = await makeCustomer(name: 'A');
      final b = await makeCustomer(name: 'B');
      await addEvent(a.id, earned: 10, expiresAt: DateTime(2025, 6, 1));
      await addEvent(b.id, earned: 40, expiresAt: DateTime(2025, 6, 1));

      expect(await repository.getPointsExpiringBefore(DateTime(2025, 8, 1), customerId: a.id), 10);
    });
  });
}
