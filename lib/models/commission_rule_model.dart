import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

/// How a salesman's commission is worked out.
///
/// Only these two are implemented. The original Phase 2 draft also listed
/// `slab` and `target` rule types; Task 2.4's corrected file drops them
/// because neither is specified precisely enough to build (what a "slab per
/// quantity range" means here is a product decision, not an implementation
/// detail). Adding a third value to this enum without also handling it in
/// `CommissionService.calculateCommission` would be caught by that method's
/// exhaustive switch.
enum CommissionRuleType { percentage, tiered }

/// One band of a tiered rule: everything up to [upTo] earns [rate].
///
/// A null [upTo] is the open-ended top band and must be the last entry.
/// Rates are fractions, not percentages — `0.02` is 2%.
class CommissionTier extends Equatable {
  /// Upper bound of this band in rupees of gross sales, or null for "and
  /// everything above".
  final double? upTo;

  /// Fraction of sales in this band paid as commission. `0.02` = 2%.
  final double rate;

  const CommissionTier({required this.upTo, required this.rate});

  Map<String, dynamic> toJson() => {'upTo': upTo, 'rate': rate};

  factory CommissionTier.fromJson(Map<String, dynamic> map) => CommissionTier(
        upTo: (map['upTo'] as num?)?.toDouble(),
        rate: (map['rate'] as num?)?.toDouble() ?? 0,
      );

  @override
  List<Object?> get props => [upTo, rate];
}

/// The commission agreement in force for one salesman over a date range.
///
/// [effectiveTo] is null for an open-ended rule. Nothing here prevents two
/// rules from overlapping — `CommissionService` refuses to calculate a period
/// covered by more than one rule rather than silently picking one, which is
/// the only safe answer when the shop's own records disagree about what it
/// promised to pay.
///
/// **Tiers are marginal, not cliff-edged**: with bands `[{upTo: 50000, rate:
/// 0.02}, {upTo: null, rate: 0.03}]`, sales of ₹60,000 earn 2% on the first
/// ₹50,000 and 3% on the remaining ₹10,000 — not 3% on the whole ₹60,000.
/// See `CommissionService.calculateCommission` and the architecture doc for
/// why: a cliff makes one extra rupee of sales worth hundreds in commission,
/// which is an incentive to game the period boundary.
class CommissionRule extends Equatable {
  final String id;
  final String salesmanId;
  final CommissionRuleType ruleType;

  /// The whole rate for a `percentage` rule, as a fraction. Ignored for
  /// `tiered` rules, where [tiers] carries the rates.
  final double baseRate;

  /// Empty for a `percentage` rule.
  final List<CommissionTier> tiers;

  /// Seconds since epoch, inclusive.
  final int effectiveFrom;

  /// Seconds since epoch, inclusive. Null = open-ended.
  final int? effectiveTo;

  final bool isActive;
  final int createdAt;

  const CommissionRule({
    required this.id,
    required this.salesmanId,
    required this.ruleType,
    this.baseRate = 0,
    this.tiers = const [],
    required this.effectiveFrom,
    this.effectiveTo,
    this.isActive = true,
    this.createdAt = 0,
  });

  factory CommissionRule.percentage({
    required String salesmanId,
    required double rate,
    required DateTime effectiveFrom,
    DateTime? effectiveTo,
  }) {
    return CommissionRule(
      id: const Uuid().v4(),
      salesmanId: salesmanId,
      ruleType: CommissionRuleType.percentage,
      baseRate: rate,
      effectiveFrom: effectiveFrom.millisecondsSinceEpoch ~/ 1000,
      effectiveTo: effectiveTo == null ? null : effectiveTo.millisecondsSinceEpoch ~/ 1000,
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
  }

  factory CommissionRule.tiered({
    required String salesmanId,
    required List<CommissionTier> tiers,
    required DateTime effectiveFrom,
    DateTime? effectiveTo,
  }) {
    return CommissionRule(
      id: const Uuid().v4(),
      salesmanId: salesmanId,
      ruleType: CommissionRuleType.tiered,
      tiers: tiers,
      effectiveFrom: effectiveFrom.millisecondsSinceEpoch ~/ 1000,
      effectiveTo: effectiveTo == null ? null : effectiveTo.millisecondsSinceEpoch ~/ 1000,
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
  }

  /// Whether this rule covers the whole of [from]..[to] (both seconds since
  /// epoch, inclusive). A rule that covers only part of a settlement period
  /// deliberately does **not** count as covering it — see
  /// `CommissionService.calculateCommission`, which would otherwise have to
  /// invent a rate for the uncovered days.
  bool coversPeriod(int from, int to) {
    if (!isActive) return false;
    if (effectiveFrom > from) return false;
    if (effectiveTo != null && effectiveTo! < to) return false;
    return true;
  }

  /// Whether this rule overlaps [from]..[to] at all, even partially. Used to
  /// detect the ambiguous case where several rules touch one period.
  bool overlapsPeriod(int from, int to) {
    if (!isActive) return false;
    if (effectiveTo != null && effectiveTo! < from) return false;
    if (effectiveFrom > to) return false;
    return true;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'salesman_id': salesmanId,
        'rule_type': ruleType.name,
        'base_rate': baseRate,
        'tiered_rates': tiers.isEmpty ? null : jsonEncode(tiers.map((t) => t.toJson()).toList()),
        'effective_from': effectiveFrom,
        'effective_to': effectiveTo,
        'is_active': isActive ? 1 : 0,
        'created_at': createdAt,
      };

  factory CommissionRule.fromJson(Map<String, dynamic> map) {
    final raw = map['tiered_rates'] as String?;
    var tiers = const <CommissionTier>[];
    if (raw != null && raw.isNotEmpty) {
      // A rule whose JSON is corrupt reads back as having no tiers, and
      // CommissionService rejects a tiered rule with no tiers rather than
      // paying zero commission on it — a silent 0 is the failure mode worth
      // designing against here.
      try {
        tiers = (jsonDecode(raw) as List)
            .map((e) => CommissionTier.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        tiers = const [];
      }
    }
    return CommissionRule(
      id: map['id'] as String,
      salesmanId: map['salesman_id'] as String,
      ruleType: CommissionRuleType.values.firstWhere(
        (t) => t.name == map['rule_type'],
        orElse: () => CommissionRuleType.percentage,
      ),
      baseRate: (map['base_rate'] as num?)?.toDouble() ?? 0,
      tiers: tiers,
      effectiveFrom: map['effective_from'] as int,
      effectiveTo: map['effective_to'] as int?,
      isActive: (map['is_active'] as int?) == 1,
      createdAt: map['created_at'] as int? ?? 0,
    );
  }

  @override
  List<Object?> get props => [id, salesmanId, ruleType, baseRate, tiers, effectiveFrom, effectiveTo, isActive];
}
