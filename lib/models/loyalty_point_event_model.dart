import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

/// What caused a loyalty point movement.
///
/// - [sale] — the ordinary path. Written by `SaleRepository` inside the sale
///   transaction; may carry both an earn and a redeem on the same row, because
///   a single bill can do both.
/// - [cancellation] — a sale was cancelled and its points reversed. Recorded
///   as its own event rather than deleting the original `sale` row, so the
///   history shows what happened instead of quietly losing it.
/// - [adjust] — a manual correction by a manager (goodwill points, fixing a
///   mis-keyed bill). Always carries a [LoyaltyPointEvent.note].
/// - [expire] — written by `LoyaltyService.expireOldPoints`; the points on
///   earn lots that passed their `expires_at` without being spent.
enum LoyaltyEventType { sale, cancellation, adjust, expire }

/// One row of `bonus_points` — the loyalty point event log.
///
/// **This is the existing table, not a new one.** `bonus_points` predates
/// Phase 2 and `SaleRepository` has always written to it; Task 2.2 widened it
/// (see `MigrationV30`) and gave it a model, a repository and readers. There
/// is deliberately no separate `loyalty_accounts` / `points_transactions`
/// structure: `customers.loyalty_points` remains the authoritative running
/// balance and this table is its audit trail, so the two can be reconciled
/// against each other rather than competing.
///
/// [pointsEarned] and [pointsRedeemed] are both non-negative magnitudes, not a
/// single signed column — that is the shape the table has had since the
/// original schema and the shape `SaleRepository` already writes. [netPoints]
/// gives the signed effect on the balance where that is what a caller wants.
class LoyaltyPointEvent extends Equatable {
  final String id;
  final String customerId;

  /// Null for [LoyaltyEventType.adjust] and [LoyaltyEventType.expire], which
  /// have no originating bill.
  final String? saleId;

  final int pointsEarned;
  final int pointsRedeemed;

  /// Seconds since epoch.
  final int date;

  final LoyaltyEventType eventType;

  /// Seconds since epoch at which [pointsEarned] on *this* row lapse, or null
  /// for points that never expire. Frozen at earn time — see `MigrationV30`
  /// for why this is not derived from the store setting at read time.
  final int? expiresAt;

  /// How many of [pointsEarned] an expiry run has already written off. Always
  /// `<= pointsEarned`. Non-zero only on rows that had an [expiresAt] in the
  /// past when [LoyaltyService.expireOldPoints] last ran.
  final int expiredPoints;

  final String? note;
  final String? createdByUserId;

  const LoyaltyPointEvent({
    required this.id,
    required this.customerId,
    this.saleId,
    this.pointsEarned = 0,
    this.pointsRedeemed = 0,
    required this.date,
    this.eventType = LoyaltyEventType.sale,
    this.expiresAt,
    this.expiredPoints = 0,
    this.note,
    this.createdByUserId,
  });

  factory LoyaltyPointEvent.create({
    required String customerId,
    String? saleId,
    int pointsEarned = 0,
    int pointsRedeemed = 0,
    LoyaltyEventType eventType = LoyaltyEventType.sale,
    DateTime? date,
    DateTime? expiresAt,
    String? note,
    String? createdByUserId,
  }) {
    return LoyaltyPointEvent(
      id: const Uuid().v4(),
      customerId: customerId,
      saleId: saleId,
      pointsEarned: pointsEarned,
      pointsRedeemed: pointsRedeemed,
      date: (date ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000,
      eventType: eventType,
      expiresAt: expiresAt == null ? null : expiresAt.millisecondsSinceEpoch ~/ 1000,
      note: note,
      createdByUserId: createdByUserId,
    );
  }

  DateTime get dateTime => DateTime.fromMillisecondsSinceEpoch(date * 1000);

  DateTime? get expiresAtDateTime =>
      expiresAt == null ? null : DateTime.fromMillisecondsSinceEpoch(expiresAt! * 1000);

  /// Signed effect on `customers.loyalty_points`. Note this does **not**
  /// subtract [expiredPoints]: an expiry writes its own [LoyaltyEventType.expire]
  /// row carrying the write-off as [pointsRedeemed], so counting it here too
  /// would double it.
  int get netPoints => pointsEarned - pointsRedeemed;

  /// Points from this lot still available to spend — what it earned, less what
  /// expiry has already taken. Redemptions are *not* deducted here: they are
  /// separate rows, and which lot a redemption drew from is resolved by the
  /// FIFO walk in `LoyaltyService`, not stored per row.
  int get unexpiredEarned => pointsEarned - expiredPoints;

  bool get hasExpiry => expiresAt != null;

  /// True when this lot's expiry date has passed as of [asOf]. Says nothing
  /// about whether the points were already spent or already written off.
  bool isExpiredAsOf(DateTime asOf) =>
      expiresAt != null && expiresAt! <= asOf.millisecondsSinceEpoch ~/ 1000;

  LoyaltyPointEvent copyWith({int? expiredPoints, String? note}) {
    return LoyaltyPointEvent(
      id: id,
      customerId: customerId,
      saleId: saleId,
      pointsEarned: pointsEarned,
      pointsRedeemed: pointsRedeemed,
      date: date,
      eventType: eventType,
      expiresAt: expiresAt,
      expiredPoints: expiredPoints ?? this.expiredPoints,
      note: note ?? this.note,
      createdByUserId: createdByUserId,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'customer_id': customerId,
        'sale_id': saleId,
        'points_earned': pointsEarned,
        'points_redeemed': pointsRedeemed,
        'date': date,
        'event_type': eventType.name,
        'expires_at': expiresAt,
        'expired_points': expiredPoints,
        'note': note,
        'created_by_user_id': createdByUserId,
      };

  factory LoyaltyPointEvent.fromJson(Map<String, dynamic> map) => LoyaltyPointEvent(
        id: map['id'] as String,
        customerId: map['customer_id'] as String,
        saleId: map['sale_id'] as String?,
        pointsEarned: (map['points_earned'] as num?)?.toInt() ?? 0,
        pointsRedeemed: (map['points_redeemed'] as num?)?.toInt() ?? 0,
        date: (map['date'] as num).toInt(),
        eventType: LoyaltyEventType.values.byName(map['event_type'] as String? ?? 'sale'),
        expiresAt: (map['expires_at'] as num?)?.toInt(),
        expiredPoints: (map['expired_points'] as num?)?.toInt() ?? 0,
        note: map['note'] as String?,
        createdByUserId: map['created_by_user_id'] as String?,
      );

  @override
  List<Object?> get props => [
        id,
        customerId,
        saleId,
        pointsEarned,
        pointsRedeemed,
        date,
        eventType,
        expiresAt,
        expiredPoints,
        note,
        createdByUserId,
      ];
}
