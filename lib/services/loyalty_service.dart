import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../core/database/database_helper.dart';
import '../core/utils/loyalty_utils.dart';
import '../models/customer_model.dart';
import '../models/loyalty_point_event_model.dart';
import '../repositories/loyalty_event_repository.dart';
import '../repositories/store_repository.dart';
import 'loyalty_exceptions.dart';

/// What one expiry sweep did. Returned rather than logged so the caller (a
/// Settings button today, possibly a scheduled job later) can show a real
/// result instead of "done".
class LoyaltyExpiryResult {
  const LoyaltyExpiryResult({
    required this.customersProcessed,
    required this.customersAffected,
    required this.pointsExpired,
    required this.events,
  });

  /// Customers that had at least one lot past its date — the candidate set.
  final int customersProcessed;

  /// Of those, how many actually lost points. The rest had already spent the
  /// lapsed lot, which is the common case and not a failure.
  final int customersAffected;

  final int pointsExpired;

  /// The `expire` rows written, one per affected customer.
  final List<LoyaltyPointEvent> events;

  bool get isEmpty => pointsExpired == 0;
}

/// One customer's loyalty standing — balance, tier and recent history in a
/// single round trip, for the customer history screen.
class CustomerLoyaltySummary {
  const CustomerLoyaltySummary({
    required this.customer,
    required this.pointsBalance,
    required this.valuePerPoint,
    required this.tier,
    required this.recentEvents,
    required this.lifetimeEarned,
    required this.lifetimeRedeemed,
    required this.lifetimeExpired,
    required this.pointsExpiringSoon,
    required this.nextExpiryDate,
  });

  final Customer customer;
  final int pointsBalance;
  final double valuePerPoint;

  /// [Customer.effectiveRating] — the manual override if one is set, otherwise
  /// the auto-computed tier. Repeated here so a caller does not have to know
  /// which of the two fields wins.
  final CustomerRating tier;

  final List<LoyaltyPointEvent> recentEvents;
  final int lifetimeEarned;
  final int lifetimeRedeemed;
  final int lifetimeExpired;

  /// Upper bound on points lapsing within the warning window — see
  /// `LoyaltyEventRepository.getPointsExpiringBefore` for why it is a bound
  /// and not an exact figure.
  final int pointsExpiringSoon;

  final DateTime? nextExpiryDate;

  double get pointsValue => pointsBalance * valuePerPoint;
}

/// Store-wide loyalty position. [outstandingValue] is a real liability the
/// shop owes its customers in future discounts.
class StoreLoyaltySummary {
  const StoreLoyaltySummary({
    required this.outstandingPoints,
    required this.valuePerPoint,
    required this.customersWithPoints,
    required this.pointsEarnedInPeriod,
    required this.pointsRedeemedInPeriod,
    required this.pointsExpiredInPeriod,
    required this.periodFrom,
    required this.periodTo,
    required this.expiryDays,
  });

  final int outstandingPoints;
  final double valuePerPoint;
  final int customersWithPoints;
  final int pointsEarnedInPeriod;
  final int pointsRedeemedInPeriod;
  final int pointsExpiredInPeriod;
  final DateTime periodFrom;
  final DateTime periodTo;

  /// 0 when expiry is switched off for this store.
  final int expiryDays;

  /// Points outstanding × redemption value. **Not posted to the General
  /// Ledger** — see the class doc on [LoyaltyService] for why that was left
  /// out of Task 2.2.
  double get outstandingValue => outstandingPoints * valuePerPoint;

  bool get expiryEnabled => expiryDays > 0;
}

/// Loyalty point administration: the event log, expiry, manual adjustments and
/// the reporting views over them.
///
/// **What this service is not.** Earning and redeeming points already happen
/// elsewhere and were not moved here: `SaleRepository` earns and redeems
/// inside the sale transaction, `loyalty_utils.dart` computes tiers and
/// multipliers, `StoreRepository` holds the rates. This service adds the parts
/// that were missing — reading the history back, expiring stale points and
/// correcting a balance by hand — and reuses those existing pieces rather than
/// recomputing them, so there is still exactly one place that decides how many
/// points a sale is worth.
///
/// **`customers.loyalty_points` stays authoritative.** The event log explains
/// the balance; it does not replace it. Every method here that moves points
/// updates both in the same transaction, and [recomputeBalanceFromEvents]
/// exists to check that they still agree.
///
/// **No GL posting.** Outstanding points are a genuine liability
/// ([StoreLoyaltySummary.outstandingValue]) and the Balance Sheet does not
/// show them. Booking that would mean a Phase 1 chart-of-accounts change and a
/// posting rule for every earn and redeem — a deliberate accounting decision,
/// not a detail to slip into a gap-closing task. The number is surfaced so a
/// human can decide; nothing writes it to the ledger.
class LoyaltyService {
  LoyaltyService({
    DatabaseHelper? dbHelper,
    LoyaltyEventRepository? eventRepository,
    StoreRepository? storeRepository,
  })  : _dbHelper = dbHelper ?? DatabaseHelper.instance,
        _events = eventRepository ?? LoyaltyEventRepository(),
        _stores = storeRepository ?? StoreRepository();

  final DatabaseHelper _dbHelper;
  final LoyaltyEventRepository _events;
  final StoreRepository _stores;

  /// How far ahead [CustomerLoyaltySummary.pointsExpiringSoon] looks.
  static const Duration expiryWarningWindow = Duration(days: 30);

  // ------------------------------------------------------------ earn support

  /// The `expires_at` to stamp on points earned at [earnedAt], or null when
  /// the store has expiry switched off.
  ///
  /// `SaleRepository` calls this when writing a sale's earn event. Kept here
  /// rather than inlined at the call site so the "0 days means never" rule
  /// lives in one place.
  Future<DateTime?> expiryDateFor(DateTime earnedAt) async {
    final days = await _stores.getLoyaltyExpiryDays();
    if (days <= 0) return null;
    return earnedAt.add(Duration(days: days));
  }

  // ---------------------------------------------------------------- expiry

  /// Expires lapsed points for every customer that has any, as of [asOf]
  /// (defaults to now).
  ///
  /// Safe to run repeatedly — see [expireOldPointsForCustomer] for how
  /// re-runs are made idempotent. There is no background scheduler in this
  /// app (checked: `main.dart` starts no periodic timer and there is no
  /// workmanager/cron dependency), so this is on-demand only; a manager runs
  /// it from the loyalty summary screen.
  Future<LoyaltyExpiryResult> expireOldPoints({DateTime? asOf}) async {
    final at = asOf ?? DateTime.now();
    final candidates = await _events.getCustomerIdsWithDueLots(at);

    var affected = 0;
    var total = 0;
    final written = <LoyaltyPointEvent>[];

    for (final customerId in candidates) {
      final result = await expireOldPointsForCustomer(customerId, asOf: at);
      if (result.pointsExpired > 0) {
        affected++;
        total += result.pointsExpired;
        written.addAll(result.events);
      }
    }

    return LoyaltyExpiryResult(
      customersProcessed: candidates.length,
      customersAffected: affected,
      pointsExpired: total,
      events: written,
    );
  }

  /// Expires one customer's lapsed points.
  ///
  /// **The FIFO rule.** Redemptions consume the oldest earn lot first. A lot
  /// only expires the part of it that redemptions never reached, so a customer
  /// who spent everything loses nothing when an old lot's date passes.
  ///
  /// **Why it is re-runnable.** What a sweep takes is written back onto each
  /// lot as `expired_points`, shrinking that lot's capacity, and the `expire`
  /// row it writes is excluded from the consumption total (see
  /// `LoyaltyEventRepository.getRedeemedTotalExcludingExpiry`). A second sweep
  /// therefore sees smaller lots and the same spending, and finds nothing left
  /// to take.
  Future<LoyaltyExpiryResult> expireOldPointsForCustomer(
    String customerId, {
    DateTime? asOf,
  }) async {
    final at = asOf ?? DateTime.now();
    final db = await _dbHelper.database;

    LoyaltyPointEvent? written;
    var expired = 0;

    await db.transaction((txn) async {
      final customer = await _requireCustomer(customerId, txn);

      final lots = await _events.getEarnLotsForCustomer(customerId, executor: txn);
      if (lots.isEmpty) return;

      // Points already spent, oldest-lot-first. Expiry write-offs are not
      // spending and are already reflected in each lot's `expired_points`.
      var unallocatedSpend = await _events.getRedeemedTotalExcludingExpiry(customerId, executor: txn);

      final writeOffs = <String, int>{};
      for (final lot in lots) {
        var remaining = lot.unexpiredEarned;
        if (remaining <= 0) continue;

        if (unallocatedSpend > 0) {
          final consumed = unallocatedSpend < remaining ? unallocatedSpend : remaining;
          remaining -= consumed;
          unallocatedSpend -= consumed;
        }

        if (remaining > 0 && lot.isExpiredAsOf(at)) {
          writeOffs[lot.id] = remaining;
          expired += remaining;
        }
      }

      if (expired <= 0) return;

      // The running balance is authoritative and must not go negative. If the
      // lots say more should lapse than the customer actually holds, the two
      // have drifted (a hand-edited row, a legacy sale that predates the event
      // log); take what is there and leave the discrepancy visible rather than
      // writing a negative balance.
      if (expired > customer.loyaltyPoints) {
        expired = customer.loyaltyPoints;
      }
      if (expired <= 0) {
        expired = 0;
        return;
      }

      for (final entry in writeOffs.entries) {
        await _events.addExpiredPoints(entry.key, entry.value, executor: txn);
      }

      written = await _events.insertEvent(
        LoyaltyPointEvent.create(
          customerId: customerId,
          pointsRedeemed: expired,
          eventType: LoyaltyEventType.expire,
          date: at,
          note: 'Expired $expired point(s) past their validity date',
        ),
        executor: txn,
      );

      await txn.rawUpdate(
        'UPDATE customers SET loyalty_points = loyalty_points - ?, updated_at = ? WHERE id = ?',
        [expired, at.millisecondsSinceEpoch ~/ 1000, customerId],
      );
    });

    return LoyaltyExpiryResult(
      customersProcessed: 1,
      customersAffected: expired > 0 ? 1 : 0,
      pointsExpired: expired,
      events: written == null ? const [] : [written!],
    );
  }

  // ----------------------------------------------------------- adjustments

  /// Manually moves a customer's points by [points] (positive to grant,
  /// negative to deduct) and logs why.
  ///
  /// [note] and [userId] are both required and [points] may not be zero — a
  /// movement with no actor and no reason is worse than no movement, and this
  /// is the one path that can change a balance without a bill behind it.
  /// Granted points follow the same expiry rule as earned ones, so a goodwill
  /// grant cannot quietly become the only permanent points in the system.
  Future<LoyaltyPointEvent> adjustPoints({
    required String customerId,
    required int points,
    required String note,
    required String userId,
    DateTime? at,
  }) async {
    if (points == 0) {
      throw InvalidLoyaltyAdjustment('A loyalty adjustment of zero points does nothing — nothing was recorded.');
    }
    if (note.trim().isEmpty) {
      throw InvalidLoyaltyAdjustment('A loyalty adjustment needs a reason. Say why these points moved.');
    }

    final when = at ?? DateTime.now();
    final expiresAt = points > 0 ? await expiryDateFor(when) : null;
    final db = await _dbHelper.database;
    late LoyaltyPointEvent event;

    await db.transaction((txn) async {
      final customer = await _requireCustomer(customerId, txn);

      if (points < 0 && customer.loyaltyPoints < -points) {
        throw InsufficientLoyaltyPoints(
          'Cannot deduct ${-points} points — ${customer.name} only has ${customer.loyaltyPoints}.',
        );
      }

      event = await _events.insertEvent(
        LoyaltyPointEvent.create(
          customerId: customerId,
          pointsEarned: points > 0 ? points : 0,
          pointsRedeemed: points < 0 ? -points : 0,
          eventType: LoyaltyEventType.adjust,
          date: when,
          expiresAt: expiresAt,
          note: note.trim(),
          createdByUserId: userId,
        ),
        executor: txn,
      );

      await txn.rawUpdate(
        'UPDATE customers SET loyalty_points = loyalty_points + ?, updated_at = ? WHERE id = ?',
        [points, when.millisecondsSinceEpoch ~/ 1000, customerId],
      );

      // Inside the transaction, same as `SaleCancellationRepository` — the
      // audit row and the balance change commit together or not at all. An
      // adjustment that moved points but failed to record who moved them is
      // exactly the state this log exists to make impossible.
      await _dbHelper.logAudit(
        userId: userId,
        actionType: 'LOYALTY_POINTS_ADJUSTED',
        tableName: 'bonus_points',
        recordId: event.id,
        newValue: jsonEncode({'customerId': customerId, 'points': points, 'note': note.trim()}),
        executor: txn,
      );
    });

    return event;
  }

  // -------------------------------------------------------------- reporting

  Future<CustomerLoyaltySummary> getCustomerSummary(
    String customerId, {
    int recentLimit = 25,
  }) async {
    final db = await _dbHelper.database;
    final customer = await _requireCustomer(customerId, db);
    final valuePerPoint = await _stores.getLoyaltyValuePerPoint();
    final recent = await _events.getEventsForCustomer(customerId, limit: recentLimit);

    // Lifetime totals come from every event, not just the recent page.
    final all = await _events.getEventsForCustomer(customerId);
    var earned = 0;
    var redeemed = 0;
    var expired = 0;
    DateTime? nextExpiry;
    for (final e in all) {
      earned += e.pointsEarned;
      if (e.eventType == LoyaltyEventType.expire) {
        expired += e.pointsRedeemed;
      } else {
        redeemed += e.pointsRedeemed;
      }
      if (e.expiresAt != null && e.unexpiredEarned > 0) {
        final d = e.expiresAtDateTime!;
        if (nextExpiry == null || d.isBefore(nextExpiry)) nextExpiry = d;
      }
    }

    final expiringSoon = await _events.getPointsExpiringBefore(
      DateTime.now().add(expiryWarningWindow),
      customerId: customerId,
    );

    return CustomerLoyaltySummary(
      customer: customer,
      pointsBalance: customer.loyaltyPoints,
      valuePerPoint: valuePerPoint,
      tier: customer.effectiveRating,
      recentEvents: recent,
      lifetimeEarned: earned,
      lifetimeRedeemed: redeemed,
      lifetimeExpired: expired,
      // Never advertise more as "expiring" than the customer actually holds —
      // the repository figure is a per-lot upper bound that ignores spending.
      pointsExpiringSoon: expiringSoon > customer.loyaltyPoints ? customer.loyaltyPoints : expiringSoon,
      nextExpiryDate: nextExpiry,
    );
  }

  Future<StoreLoyaltySummary> getStoreSummary({DateTime? from, DateTime? to}) async {
    final periodTo = to ?? DateTime.now();
    final periodFrom = from ?? DateTime(periodTo.year, periodTo.month, 1);

    final outstanding = await _events.getTotalOutstandingPoints();
    final valuePerPoint = await _stores.getLoyaltyValuePerPoint();
    final customers = await _events.getCustomerCountWithPoints();
    final expiryDays = await _stores.getLoyaltyExpiryDays();

    final inPeriod = await _events.getEventsInRange(from: periodFrom, to: periodTo);
    var earned = 0;
    var redeemed = 0;
    var expired = 0;
    for (final e in inPeriod) {
      earned += e.pointsEarned;
      if (e.eventType == LoyaltyEventType.expire) {
        expired += e.pointsRedeemed;
      } else {
        redeemed += e.pointsRedeemed;
      }
    }

    return StoreLoyaltySummary(
      outstandingPoints: outstanding,
      valuePerPoint: valuePerPoint,
      customersWithPoints: customers,
      pointsEarnedInPeriod: earned,
      pointsRedeemedInPeriod: redeemed,
      pointsExpiredInPeriod: expired,
      periodFrom: periodFrom,
      periodTo: periodTo,
      expiryDays: expiryDays,
    );
  }

  /// What the balance *would* be if rebuilt from the event log alone.
  ///
  /// A reconciliation aid, not a repair: it deliberately does not write
  /// anything. A gap between this and `customers.loyalty_points` means either
  /// points predating the event log (`bonus_points` had no writer before the
  /// change that added one to `SaleRepository`, so older customers legitimately
  /// hold points with no events behind them) or a real bug — and those two need
  /// a human to tell apart, not an automatic overwrite.
  Future<int> recomputeBalanceFromEvents(String customerId) async {
    final all = await _events.getEventsForCustomer(customerId);
    return all.fold<int>(0, (sum, e) => sum + e.netPoints);
  }

  /// Tier a customer would sit at for [totalSpent], using this store's
  /// thresholds. Thin wrapper over `computeTier` so callers do not each have to
  /// fetch the thresholds and remember the argument order.
  Future<CustomerRating> tierForSpend(double totalSpent) async {
    final t = await _stores.getTierThresholds();
    return computeTier(
      totalSpent: totalSpent,
      bronzeMin: t['bronze'] ?? 2000,
      silverMin: t['silver'] ?? 10000,
      goldMin: t['gold'] ?? 25000,
    );
  }

  // ----------------------------------------------------------------- shared

  Future<Customer> _requireCustomer(String customerId, DatabaseExecutor db) async {
    final rows = await db.query('customers', where: 'id = ?', whereArgs: [customerId], limit: 1);
    if (rows.isEmpty) {
      throw LoyaltyCustomerNotFound('No customer with id $customerId.');
    }
    return Customer.fromJson(rows.first);
  }
}

final loyaltyServiceProvider = Provider<LoyaltyService>((ref) => LoyaltyService());
