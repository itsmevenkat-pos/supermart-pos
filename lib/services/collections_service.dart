import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/collection_activity_model.dart';
import '../models/customer_ledger_model.dart';
import '../models/customer_model.dart';
import '../repositories/collections_repository.dart';
import 'collections_exceptions.dart';
import 'whatsapp_share_service.dart';

/// How overdue a piece of an outstanding balance is.
///
/// **Boundaries are lower-inclusive, upper-exclusive**: `current` is 0–29
/// days, `days30` is 30–59, `days60` is 60–89, `days90Plus` is 90 and over.
/// So a charge that is *exactly* 30 days old sits in [days30], not [current].
/// Task 2.4 asks for this call to be made explicitly: the label names the age
/// a debt has *reached*, which is the reading under which "30-60" contains
/// everything a shop would describe as "a month overdue". It is tested
/// directly, at 29, 30, 59, 60, 89 and 90 days.
enum AgingBucket { current, days30, days60, days90Plus }

/// Human labels for the report header, kept next to the boundaries they
/// describe so the two cannot drift apart.
extension AgingBucketLabel on AgingBucket {
  String get label => switch (this) {
        AgingBucket.current => '0-30 days',
        AgingBucket.days30 => '30-60 days',
        AgingBucket.days60 => '60-90 days',
        AgingBucket.days90Plus => '90+ days',
      };
}

/// One still-unpaid piece of a customer's balance, traced back to the ledger
/// entry that created it.
///
/// [outstanding] can be less than [originalAmount] when a payment has partly
/// cleared this charge — FIFO means a payment eats the oldest charge first
/// and can stop halfway through it.
class OpenCharge {
  final String ledgerEntryId;
  final String referenceType;
  final String referenceId;

  /// Seconds since epoch — the date the debt arose, which is what it is aged
  /// against. This app has no invoice due date to age from; see the class doc
  /// on [CollectionsService].
  final int createdAt;

  final double originalAmount;
  final double outstanding;
  final int ageInDays;

  const OpenCharge({
    required this.ledgerEntryId,
    required this.referenceType,
    required this.referenceId,
    required this.createdAt,
    required this.originalAmount,
    required this.outstanding,
    required this.ageInDays,
  });

  AgingBucket get bucket {
    if (ageInDays >= 90) return AgingBucket.days90Plus;
    if (ageInDays >= 60) return AgingBucket.days60;
    if (ageInDays >= 30) return AgingBucket.days30;
    return AgingBucket.current;
  }
}

/// One customer's row in the aging report.
class CustomerAging {
  final Customer customer;

  /// Total still owed. Equals the sum of [openCharges]' outstanding amounts,
  /// and — barring a ledger the app itself wrote inconsistently — equals the
  /// running `balance` on the customer's newest ledger entry.
  final double totalOutstanding;

  /// Money the customer has paid that no charge has absorbed yet (an
  /// advance). Mutually exclusive with [totalOutstanding] being positive: the
  /// FIFO walk applies credits as it goes, so a customer either still owes
  /// something or is in advance, never both.
  final double unappliedCredit;

  final Map<AgingBucket, double> buckets;
  final List<OpenCharge> openCharges;

  const CustomerAging({
    required this.customer,
    required this.totalOutstanding,
    required this.unappliedCredit,
    required this.buckets,
    required this.openCharges,
  });

  double amountIn(AgingBucket bucket) => buckets[bucket] ?? 0;

  /// Age of the oldest unpaid charge, or 0 if nothing is outstanding. This is
  /// the number a collector sorts by.
  int get oldestChargeDays =>
      openCharges.isEmpty ? 0 : openCharges.map((c) => c.ageInDays).reduce((a, b) => a > b ? a : b);

  bool get isOverdue => openCharges.any((c) => c.bucket != AgingBucket.current);
}

/// The whole receivable, aged, as of one moment.
class AgingReport {
  /// Seconds since epoch — the moment the report was computed against.
  final int asOf;

  /// Customers with something outstanding, most overdue first.
  final List<CustomerAging> rows;

  const AgingReport({required this.asOf, required this.rows});

  double totalIn(AgingBucket bucket) =>
      rows.fold(0.0, (sum, row) => sum + row.amountIn(bucket));

  double get grandTotal => rows.fold(0.0, (sum, row) => sum + row.totalOutstanding);

  int get customerCount => rows.length;

  /// Customers with anything at all past the `current` bucket.
  int get overdueCustomerCount => rows.where((r) => r.isOverdue).length;
}

/// Accounts-receivable aging and collection follow-up tracking.
///
/// **Aging is computed, never stored.** There is no aging table; every figure
/// here is derived from `customer_ledger`, which has recorded credit sales,
/// payments, advances, returns, exchanges and cancellations since
/// `MigrationV1`. A stored snapshot would disagree with the ledger the moment
/// the next payment landed.
///
/// **What debts are aged against.** This app has no invoice due date — the
/// only `due_date` in the schema is on `purchases`, which is what the shop
/// owes suppliers. So a debt is aged from the *transaction date* of the
/// ledger entry that created it. In a shop that sells on informal credit that
/// is the honest reading of "how long has this been outstanding": there was
/// never a promised date to be late against.
///
/// **Payments clear the oldest debt first (FIFO).** Walking the ledger in
/// order, a payment consumes the oldest open charge, then the next, and a
/// charge that arrives while the customer is in advance absorbs that advance
/// before becoming outstanding. The alternative — spreading each payment
/// proportionally across all open charges — would leave every charge
/// partly unpaid forever and put a share of a two-year-old debt in the
/// `current` bucket, which is precisely the picture an aging report exists to
/// prevent.
class CollectionsService {
  CollectionsService({CollectionsRepository? repository})
      : _repository = repository ?? CollectionsRepository();

  final CollectionsRepository _repository;

  /// Rupee dust below this is treated as zero. Ledger amounts are doubles and
  /// a chain of FIFO subtractions leaves remainders like 1e-13, which would
  /// otherwise show up as an open charge of ₹0.00 that can never be cleared.
  static const double _epsilon = 0.005;

  static const int _secondsPerDay = 86400;

  // -------------------------------------------------------------- aging

  /// Ages the whole receivable as of [asOf] (default: now).
  ///
  /// Customers who owe nothing are left out entirely — including those in
  /// advance, who are a payables question, not a collections one. Rows come
  /// back oldest-debt-first, which is the order a collector works.
  Future<AgingReport> generateAgingReport({DateTime? asOf}) async {
    final at = asOf ?? DateTime.now();
    final entries = await _repository.getLedgerEntries(asOf: at);

    final byCustomer = <String, List<CustomerLedger>>{};
    for (final entry in entries) {
      byCustomer.putIfAbsent(entry.customerId, () => []).add(entry);
    }

    // Work out who actually owes something before fetching customer records,
    // so a shop with thousands of settled customers does not load them all.
    final walked = <String, _FifoResult>{};
    for (final e in byCustomer.entries) {
      final result = _walkFifo(e.value, at);
      if (result.openCharges.isNotEmpty) walked[e.key] = result;
    }

    final customers = await _repository.getCustomersByIds(walked.keys);

    final rows = <CustomerAging>[];
    for (final e in walked.entries) {
      final customer = customers[e.key];
      // A ledger entry whose customer row has been hard-deleted would
      // otherwise crash the report. Skipping it loses a real receivable, so
      // it is kept under a placeholder that says what happened.
      rows.add(_toAging(customer ?? _missingCustomer(e.key), e.value));
    }

    rows.sort((a, b) {
      final byAge = b.oldestChargeDays.compareTo(a.oldestChargeDays);
      if (byAge != 0) return byAge;
      return b.totalOutstanding.compareTo(a.totalOutstanding);
    });

    return AgingReport(asOf: at.millisecondsSinceEpoch ~/ 1000, rows: rows);
  }

  /// The same walk for a single customer, for their detail screen. Returns
  /// null when the customer owes nothing.
  Future<CustomerAging?> getCustomerAging(String customerId, {DateTime? asOf}) async {
    final at = asOf ?? DateTime.now();
    final entries = await _repository.getLedgerEntries(asOf: at, customerId: customerId);
    if (entries.isEmpty) return null;

    final result = _walkFifo(entries, at);
    if (result.openCharges.isEmpty) return null;

    final customers = await _repository.getCustomersByIds([customerId]);
    return _toAging(customers[customerId] ?? _missingCustomer(customerId), result);
  }

  /// The FIFO walk itself. [entries] must be in chronological order.
  ///
  /// Positive amounts are charges (the customer owes more), negative ones are
  /// credits (payments, advances, returns, cancellations) — the sign
  /// convention `CustomerLedger` documents and every writer in this app
  /// follows.
  _FifoResult _walkFifo(List<CustomerLedger> entries, DateTime asOf) {
    final open = <_MutableCharge>[];
    var creditPool = 0.0;

    for (final entry in entries) {
      if (entry.amount > 0) {
        // A new debt. Any advance on hand pays it down before it counts as
        // outstanding.
        var remaining = entry.amount;
        if (creditPool > 0) {
          final applied = creditPool < remaining ? creditPool : remaining;
          creditPool -= applied;
          remaining -= applied;
        }
        if (remaining > _epsilon) {
          open.add(_MutableCharge(entry: entry, remaining: remaining));
        }
      } else if (entry.amount < 0) {
        // A payment. Clears the oldest open charge first, then the next.
        var credit = -entry.amount;
        for (final charge in open) {
          if (credit <= _epsilon) break;
          if (charge.remaining <= 0) continue;
          final applied = charge.remaining < credit ? charge.remaining : credit;
          charge.remaining -= applied;
          credit -= applied;
        }
        open.removeWhere((c) => c.remaining <= _epsilon);
        if (credit > _epsilon) creditPool += credit;
      }
    }

    final asOfSeconds = asOf.millisecondsSinceEpoch ~/ 1000;
    final charges = open.map((c) {
      final ageSeconds = asOfSeconds - c.entry.createdAt;
      final age = ageSeconds <= 0 ? 0 : ageSeconds ~/ _secondsPerDay;
      return OpenCharge(
        ledgerEntryId: c.entry.id,
        referenceType: c.entry.referenceType,
        referenceId: c.entry.referenceId,
        createdAt: c.entry.createdAt,
        originalAmount: c.entry.amount,
        outstanding: c.remaining,
        ageInDays: age,
      );
    }).toList();

    return _FifoResult(openCharges: charges, unappliedCredit: creditPool);
  }

  CustomerAging _toAging(Customer customer, _FifoResult result) {
    final buckets = <AgingBucket, double>{for (final b in AgingBucket.values) b: 0.0};
    var total = 0.0;
    for (final charge in result.openCharges) {
      buckets[charge.bucket] = buckets[charge.bucket]! + charge.outstanding;
      total += charge.outstanding;
    }
    return CustomerAging(
      customer: customer,
      totalOutstanding: total,
      unappliedCredit: result.unappliedCredit,
      buckets: buckets,
      openCharges: result.openCharges,
    );
  }

  /// Stand-in for a ledger entry whose customer row is gone. Keeps the money
  /// visible in the report rather than dropping it.
  Customer _missingCustomer(String id) => Customer(
        id: id,
        phone: '',
        name: '(deleted customer $id)',
      );

  // --------------------------------------------------------- activities

  /// Records a touchpoint that has already happened.
  ///
  /// Logging a `payment` activity records that money was collected; it does
  /// **not** move it. The payment itself goes through
  /// `CustomerRepository.recordPayment`, which writes the ledger and the
  /// outstanding balance. Keeping the two apart is what stops this log from
  /// becoming a second, disagreeing account of what a customer owes.
  Future<CollectionActivity> logActivity({
    required String customerId,
    required CollectionActivityType activityType,
    DateTime? completedDate,
    String? notes,
    double? amountCollected,
  }) async {
    await _requireCustomer(customerId);
    final activity = CollectionActivity.logged(
      customerId: customerId,
      activityType: activityType,
      completedDate: completedDate,
      notes: notes,
      amountCollected: amountCollected,
    );
    await _repository.insertActivity(activity);
    return activity;
  }

  /// Schedules a follow-up — this module's entire dunning mechanism.
  ///
  /// A date in the past is refused: a reminder that is born overdue cannot be
  /// told apart in the worklist from one the shop genuinely missed.
  Future<CollectionActivity> scheduleFollowUp({
    required String customerId,
    required CollectionActivityType activityType,
    required DateTime scheduledDate,
    String? notes,
    DateTime? now,
  }) async {
    await _requireCustomer(customerId);
    final at = now ?? DateTime.now();
    if (scheduledDate.isBefore(at)) {
      throw InvalidFollowUpDate(
        'Cannot schedule a follow-up for ${scheduledDate.toLocal()}, which is in the past. '
        'Log it as a completed activity instead if it has already happened.',
      );
    }
    final activity = CollectionActivity.scheduled(
      customerId: customerId,
      activityType: activityType,
      scheduledDate: scheduledDate,
      notes: notes,
    );
    await _repository.insertActivity(activity);
    return activity;
  }

  /// Marks a scheduled follow-up done, optionally recording what it
  /// collected.
  Future<CollectionActivity> completeActivity(
    String activityId, {
    DateTime? completedDate,
    String? notes,
    double? amountCollected,
  }) async {
    final existing = await _requireActivity(activityId);
    if (!existing.isPending) {
      throw InvalidCollectionActivityState(
        'Activity $activityId is already ${existing.status.name}; only a pending activity can be completed.',
      );
    }
    final updated = CollectionActivity(
      id: existing.id,
      customerId: existing.customerId,
      activityType: existing.activityType,
      scheduledDate: existing.scheduledDate,
      completedDate: (completedDate ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000,
      status: CollectionActivityStatus.completed,
      notes: notes ?? existing.notes,
      amountCollected: amountCollected ?? existing.amountCollected,
      createdAt: existing.createdAt,
    );
    await _repository.updateActivity(updated);
    return updated;
  }

  /// Drops a follow-up without doing it — the customer paid in the meantime,
  /// or the shop decided not to chase. Kept rather than deleted so the
  /// history shows the decision.
  Future<CollectionActivity> skipActivity(String activityId, {String? notes}) async {
    final existing = await _requireActivity(activityId);
    if (!existing.isPending) {
      throw InvalidCollectionActivityState(
        'Activity $activityId is already ${existing.status.name}; only a pending activity can be skipped.',
      );
    }
    final updated = CollectionActivity(
      id: existing.id,
      customerId: existing.customerId,
      activityType: existing.activityType,
      scheduledDate: existing.scheduledDate,
      completedDate: existing.completedDate,
      status: CollectionActivityStatus.skipped,
      notes: notes ?? existing.notes,
      amountCollected: existing.amountCollected,
      createdAt: existing.createdAt,
    );
    await _repository.updateActivity(updated);
    return updated;
  }

  Future<List<CollectionActivity>> getActivitiesForCustomer(String customerId) =>
      _repository.getActivitiesForCustomer(customerId);

  /// Everything pending and due by [dueBy] (default: now) — the worklist.
  Future<List<CollectionActivity>> getDueFollowUps({DateTime? dueBy}) =>
      _repository.getPendingActivities(dueBy: dueBy ?? DateTime.now());

  /// Every pending follow-up, due or not.
  Future<List<CollectionActivity>> getPendingFollowUps() => _repository.getPendingActivities();

  Future<void> deleteFollowUp(String activityId) async {
    final existing = await _requireActivity(activityId);
    if (!existing.isPending) {
      throw InvalidCollectionActivityState(
        'Activity $activityId is ${existing.status.name} and is part of the collection history; '
        'only a pending follow-up can be deleted.',
      );
    }
    await _repository.deleteActivity(activityId);
  }

  // ----------------------------------------------------------- reminders

  /// The dues reminder text. Pure and separately testable — the sending part
  /// below only opens WhatsApp with whatever this returns.
  ///
  /// Deliberately states the total and the age of the oldest item rather than
  /// itemising: a customer with fourteen open credit slips gets a message
  /// they will actually read.
  String buildDuesReminderMessage(CustomerAging aging) {
    final buffer = StringBuffer();
    buffer.writeln('Hello ${aging.customer.name},');
    buffer.writeln();
    buffer.writeln(
      'This is a friendly reminder from SuperMart POS about your outstanding '
      'balance of ₹${aging.totalOutstanding.toStringAsFixed(2)}.',
    );
    if (aging.oldestChargeDays > 0) {
      buffer.writeln('The oldest item has been pending for ${aging.oldestChargeDays} days.');
    }
    buffer.writeln();
    buffer.writeln('Please arrange payment at your convenience. Thank you!');
    return buffer.toString();
  }

  /// Opens WhatsApp with the dues reminder for [customerId], and records the
  /// attempt as a completed `whatsapp` activity.
  ///
  /// Reuses `WhatsAppShareService.sendCampaignMessage` — the same path the
  /// Campaigns screen uses — rather than adding a messaging dependency.
  /// **Nothing is actually sent by this app**: that method opens WhatsApp's
  /// compose screen with the text filled in and the user presses send. The
  /// activity is therefore logged as "reminder sent to WhatsApp", which is
  /// the most this app can honestly claim. There is no SMS equivalent, and
  /// Task 2.4 rules out adding an SMS gateway as a side effect of this work —
  /// `CollectionActivityType.sms` exists for recording a message sent by some
  /// other means.
  ///
  /// [sender] exists so tests can drive this without launching anything, the
  /// same reason `PaymentGatewayService` takes a `gatewayOverride`.
  Future<CollectionActivity> sendDuesReminder(
    String customerId, {
    DateTime? asOf,
    Future<void> Function({required String phone, required String message})? sender,
  }) async {
    final aging = await getCustomerAging(customerId, asOf: asOf);
    if (aging == null) {
      throw InvalidCollectionActivityState(
        'Customer $customerId has nothing outstanding; there is no reminder to send.',
      );
    }
    final phone = aging.customer.phone.trim();
    if (phone.isEmpty) {
      throw NoContactNumber(
        'Customer ${aging.customer.name} has no phone number on record, so a WhatsApp reminder '
        'cannot be addressed.',
      );
    }

    final message = buildDuesReminderMessage(aging);
    final send = sender ?? WhatsAppShareService.sendCampaignMessage;
    await send(phone: phone, message: message);

    return logActivity(
      customerId: customerId,
      activityType: CollectionActivityType.whatsapp,
      notes: 'Dues reminder for ₹${aging.totalOutstanding.toStringAsFixed(2)} opened in WhatsApp.',
    );
  }

  // ------------------------------------------------------------- helpers

  Future<Customer> _requireCustomer(String customerId) async {
    final customers = await _repository.getCustomersByIds([customerId]);
    final customer = customers[customerId];
    if (customer == null) {
      throw CollectionCustomerNotFound('No customer with id $customerId.');
    }
    return customer;
  }

  Future<CollectionActivity> _requireActivity(String activityId) async {
    final activity = await _repository.getActivityById(activityId);
    if (activity == null) {
      throw CollectionActivityNotFound('No collection activity with id $activityId.');
    }
    return activity;
  }
}

/// A charge being consumed during the FIFO walk.
class _MutableCharge {
  _MutableCharge({required this.entry, required this.remaining});

  final CustomerLedger entry;
  double remaining;
}

class _FifoResult {
  const _FifoResult({required this.openCharges, required this.unappliedCredit});

  final List<OpenCharge> openCharges;
  final double unappliedCredit;
}

final collectionsServiceProvider = Provider<CollectionsService>((ref) => CollectionsService());
