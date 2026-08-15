import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

/// How the shop contacted (or intends to contact) a customer about an overdue
/// balance.
///
/// `payment` is in the list because a collection history that records five
/// phone calls but not the payment they produced is useless for judging
/// whether chasing this customer works. It is the one type that normally
/// carries a non-null `amountCollected`.
///
/// Only `whatsapp` can actually send anything from this app — it reuses
/// `WhatsAppShareService.sendCampaignMessage`, the same path the Campaigns
/// screen uses. `sms` is recorded but never sent: this app has no SMS gateway
/// and Task 2.4 explicitly rules out adding one as a side effect. See
/// `docs/COLLECTIONS_COMMISSION_ARCHITECTURE.md`.
enum CollectionActivityType { call, email, sms, whatsapp, visit, payment }

/// Where a follow-up stands.
///
/// `pending` with a future `scheduledDate` is this module's entire dunning
/// schedule — there is no separate schedule table. `skipped` exists so a
/// follow-up that was consciously dropped is distinguishable from one still
/// waiting, which matters when the worklist is "everything still pending".
enum CollectionActivityStatus { pending, completed, skipped }

/// One collection touchpoint against a customer — either already done, or
/// scheduled for later.
///
/// [amountCollected] is nullable rather than 0-by-default: "this call
/// collected nothing" and "this call has not happened yet" are different
/// facts, and collapsing them loses the ability to report on either.
///
/// Note this record does **not** move money. Logging a `payment` activity for
/// ₹500 records that ₹500 was collected; the payment itself still goes
/// through `CustomerRepository.recordPayment`, which is what writes the
/// customer ledger and the outstanding balance. Keeping them separate means
/// this log can never become a second, disagreeing account of what a customer
/// owes.
class CollectionActivity extends Equatable {
  final String id;
  final String customerId;
  final CollectionActivityType activityType;

  /// Seconds since epoch, or null for an activity logged as already done.
  final int? scheduledDate;

  /// Seconds since epoch. Set when the activity moves to
  /// [CollectionActivityStatus.completed].
  final int? completedDate;

  final CollectionActivityStatus status;
  final String? notes;

  /// Rupees actually collected by this touchpoint, or null if none/not yet.
  final double? amountCollected;

  final int createdAt;

  const CollectionActivity({
    required this.id,
    required this.customerId,
    required this.activityType,
    this.scheduledDate,
    this.completedDate,
    this.status = CollectionActivityStatus.pending,
    this.notes,
    this.amountCollected,
    this.createdAt = 0,
  });

  /// A touchpoint that has already happened.
  factory CollectionActivity.logged({
    required String customerId,
    required CollectionActivityType activityType,
    DateTime? completedDate,
    String? notes,
    double? amountCollected,
  }) {
    final now = DateTime.now();
    return CollectionActivity(
      id: const Uuid().v4(),
      customerId: customerId,
      activityType: activityType,
      completedDate: (completedDate ?? now).millisecondsSinceEpoch ~/ 1000,
      status: CollectionActivityStatus.completed,
      notes: notes,
      amountCollected: amountCollected,
      createdAt: now.millisecondsSinceEpoch ~/ 1000,
    );
  }

  /// A touchpoint planned for later — this module's dunning reminder.
  factory CollectionActivity.scheduled({
    required String customerId,
    required CollectionActivityType activityType,
    required DateTime scheduledDate,
    String? notes,
  }) {
    return CollectionActivity(
      id: const Uuid().v4(),
      customerId: customerId,
      activityType: activityType,
      scheduledDate: scheduledDate.millisecondsSinceEpoch ~/ 1000,
      notes: notes,
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
  }

  bool get isPending => status == CollectionActivityStatus.pending;

  /// True for a pending activity whose scheduled date has arrived or passed.
  /// An activity with no scheduled date is never overdue — it is a log entry,
  /// not a reminder.
  bool isDue({DateTime? asOf}) {
    if (!isPending || scheduledDate == null) return false;
    final now = (asOf ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
    return scheduledDate! <= now;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'customer_id': customerId,
        'activity_type': activityType.name,
        'scheduled_date': scheduledDate,
        'completed_date': completedDate,
        'status': status.name,
        'notes': notes,
        'amount_collected': amountCollected,
        'created_at': createdAt,
      };

  factory CollectionActivity.fromJson(Map<String, dynamic> map) => CollectionActivity(
        id: map['id'] as String,
        customerId: map['customer_id'] as String,
        activityType: CollectionActivityType.values.firstWhere(
          (t) => t.name == map['activity_type'],
          orElse: () => CollectionActivityType.call,
        ),
        scheduledDate: map['scheduled_date'] as int?,
        completedDate: map['completed_date'] as int?,
        status: CollectionActivityStatus.values.firstWhere(
          (s) => s.name == map['status'],
          orElse: () => CollectionActivityStatus.pending,
        ),
        notes: map['notes'] as String?,
        amountCollected: (map['amount_collected'] as num?)?.toDouble(),
        createdAt: map['created_at'] as int? ?? 0,
      );

  @override
  List<Object?> get props => [id, customerId, activityType, status, scheduledDate, completedDate, amountCollected];
}
