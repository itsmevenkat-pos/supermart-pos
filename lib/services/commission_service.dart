import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/commission_rule_model.dart';
import '../models/commission_settlement_model.dart';
import '../repositories/commission_repository.dart';
import '../repositories/salesman_repository.dart';
import 'commission_exceptions.dart';

/// One band's contribution to a tiered calculation, kept so the UI can show a
/// salesman *why* they earned what they earned rather than a single number.
class CommissionBandBreakdown {
  /// Inclusive lower bound of the band in rupees of gross sales.
  final double from;

  /// Exclusive upper bound, or null for the open-ended top band.
  final double? to;

  final double rate;

  /// Sales that actually fell in this band for the period.
  final double salesInBand;

  final double commission;

  const CommissionBandBreakdown({
    required this.from,
    required this.to,
    required this.rate,
    required this.salesInBand,
    required this.commission,
  });
}

/// What a salesman earned over a period, and the working behind it.
class CommissionCalculation {
  final String salesmanId;

  /// Seconds since epoch, inclusive.
  final int periodFrom;

  /// Seconds since epoch, inclusive.
  final int periodTo;

  /// Sum of `sales.net_amount`, cancelled sales excluded.
  final double grossSales;

  final double commissionAmount;

  /// The rule this was worked out under.
  final CommissionRule rule;

  /// Empty for a `percentage` rule; one entry per band that had sales in it
  /// for a `tiered` rule.
  final List<CommissionBandBreakdown> bands;

  const CommissionCalculation({
    required this.salesmanId,
    required this.periodFrom,
    required this.periodTo,
    required this.grossSales,
    required this.commissionAmount,
    required this.rule,
    this.bands = const [],
  });

  /// Blended rate actually paid, for display. Zero-safe.
  double get effectiveRate => grossSales == 0 ? 0 : commissionAmount / grossSales;
}

/// Commission calculation and settlement for salesmen.
///
/// **Commission is not posted to the general ledger.** It is a real expense
/// and a real payable, but the Phase 1 chart of accounts has neither a
/// commission-expense account nor an accrued-commission liability, and adding
/// them plus a posting rule is an accounting decision for a human rather than
/// something to infer inside this task. Consistent with the same call made
/// for loyalty liability (Task 2.2) and gateway settlement fees (Task 2.3).
/// See `docs/COLLECTIONS_COMMISSION_ARCHITECTURE.md`.
class CommissionService {
  CommissionService({
    CommissionRepository? repository,
    SalesmanRepository? salesmanRepository,
  })  : _repository = repository ?? CommissionRepository(),
        _salesmen = salesmanRepository ?? SalesmanRepository();

  final CommissionRepository _repository;
  final SalesmanRepository _salesmen;

  /// Commission is money; it is rounded to paise once, at the end, rather
  /// than band by band, so the bands always sum to the total.
  static double _round(double value) => (value * 100).roundToDouble() / 100;

  // ------------------------------------------------------------------ rules

  /// Stores a rule after checking it is usable. Validation lives here rather
  /// than in the model so a rule that is already in the database (written by
  /// an older build, or edited by hand) still gets checked when it is used.
  Future<CommissionRule> createRule(CommissionRule rule) async {
    await _requireSalesman(rule.salesmanId);
    validateRule(rule);
    if (rule.effectiveTo != null && rule.effectiveTo! < rule.effectiveFrom) {
      throw InvalidCommissionRule(
        'Rule ends before it starts (effective_from ${rule.effectiveFrom}, effective_to ${rule.effectiveTo}).',
      );
    }
    await _repository.insertRule(rule);
    return rule;
  }

  /// Throws [InvalidCommissionRule] if the rule cannot be applied.
  ///
  /// Tiered bands must be in ascending order with at most one open-ended top
  /// band, and that band must be last — otherwise "everything above X" would
  /// swallow the bands after it and the rate a salesman is paid would depend
  /// on the order rows happened to be written in.
  void validateRule(CommissionRule rule) {
    switch (rule.ruleType) {
      case CommissionRuleType.percentage:
        if (rule.baseRate < 0) {
          throw InvalidCommissionRule('Commission rate cannot be negative (got ${rule.baseRate}).');
        }
      case CommissionRuleType.tiered:
        if (rule.tiers.isEmpty) {
          throw InvalidCommissionRule(
            'Tiered rule ${rule.id} has no bands. A tiered rule with no bands would pay ₹0 silently, '
            'which is indistinguishable from a salesman who sold nothing.',
          );
        }
        double? previousUpTo;
        for (var i = 0; i < rule.tiers.length; i++) {
          final tier = rule.tiers[i];
          if (tier.rate < 0) {
            throw InvalidCommissionRule('Band ${i + 1} has a negative rate (${tier.rate}).');
          }
          if (tier.upTo == null) {
            if (i != rule.tiers.length - 1) {
              throw InvalidCommissionRule(
                'The open-ended band must be last; band ${i + 1} of ${rule.tiers.length} has no upper bound.',
              );
            }
            continue;
          }
          if (tier.upTo! <= 0) {
            throw InvalidCommissionRule('Band ${i + 1} has a non-positive upper bound (${tier.upTo}).');
          }
          if (previousUpTo != null && tier.upTo! <= previousUpTo) {
            throw InvalidCommissionRule(
              'Bands must ascend: band ${i + 1} ends at ${tier.upTo} but band $i already ended at $previousUpTo.',
            );
          }
          previousUpTo = tier.upTo;
        }
    }
  }

  Future<List<CommissionRule>> getRules(String salesmanId, {bool activeOnly = false}) =>
      _repository.getRulesForSalesman(salesmanId, activeOnly: activeOnly);

  Future<void> deactivateRule(String ruleId) async {
    final rule = await _repository.getRuleById(ruleId);
    if (rule == null) throw NoCommissionRule('No commission rule with id $ruleId.');
    await _repository.deactivateRule(ruleId);
  }

  // ------------------------------------------------------------ calculation

  /// Gross sales for a salesman over a period — cancelled sales excluded.
  /// Exposed separately so a screen can show turnover without a rule in
  /// place.
  Future<double> grossSalesFor(String salesmanId, DateTime from, DateTime to) {
    _requirePeriod(from, to);
    return _repository.getGrossSales(salesmanId, from, to);
  }

  /// Works out what [salesmanId] earned between [from] and [to], inclusive.
  ///
  /// Throws [NoCommissionRule] when no active rule covers the *whole* period,
  /// and [AmbiguousCommissionRule] when more than one overlaps it. Both are
  /// refusals rather than guesses: a rule covering half the month gives no
  /// honest rate for the other half, and two overlapping rules mean the
  /// shop's own records disagree about what it promised. In both cases the
  /// fix is to settle the stretches separately, which the messages say.
  Future<CommissionCalculation> calculateCommission(
    String salesmanId,
    DateTime from,
    DateTime to,
  ) async {
    _requirePeriod(from, to);
    await _requireSalesman(salesmanId);

    final fromSeconds = from.millisecondsSinceEpoch ~/ 1000;
    final toSeconds = to.millisecondsSinceEpoch ~/ 1000;

    final rules = await _repository.getRulesForSalesman(salesmanId, activeOnly: true);
    final overlapping = rules.where((r) => r.overlapsPeriod(fromSeconds, toSeconds)).toList();

    if (overlapping.isEmpty) {
      throw NoCommissionRule(
        'No active commission rule covers ${from.toLocal()} to ${to.toLocal()} for salesman $salesmanId.',
      );
    }
    if (overlapping.length > 1) {
      throw AmbiguousCommissionRule(
        '${overlapping.length} active commission rules overlap ${from.toLocal()} to ${to.toLocal()} '
        'for salesman $salesmanId. Settle each stretch separately, or retire the rules that no longer apply.',
      );
    }

    final rule = overlapping.first;
    if (!rule.coversPeriod(fromSeconds, toSeconds)) {
      throw NoCommissionRule(
        'Commission rule ${rule.id} covers only part of ${from.toLocal()} to ${to.toLocal()}. '
        'Settle the covered stretch separately rather than applying its rate to days it does not cover.',
      );
    }

    validateRule(rule);

    final gross = await _repository.getGrossSales(salesmanId, from, to);
    final bands = <CommissionBandBreakdown>[];
    double commission;

    switch (rule.ruleType) {
      case CommissionRuleType.percentage:
        commission = gross * rule.baseRate;
      case CommissionRuleType.tiered:
        commission = 0;
        var lower = 0.0;
        for (final tier in rule.tiers) {
          if (gross <= lower) break;
          // Marginal, not cliff-edged: each band charges its own rate on only
          // the sales that fall inside it. A cliff would make one extra rupee
          // of sales worth hundreds in commission, which is an incentive to
          // game the period boundary.
          final upper = tier.upTo;
          final bandTop = upper == null ? gross : (upper < gross ? upper : gross);
          final salesInBand = bandTop - lower;
          if (salesInBand > 0) {
            final bandCommission = salesInBand * tier.rate;
            commission += bandCommission;
            bands.add(CommissionBandBreakdown(
              from: lower,
              to: upper,
              rate: tier.rate,
              salesInBand: salesInBand,
              commission: _round(bandCommission),
            ));
          }
          if (upper == null) break;
          lower = upper;
        }
    }

    return CommissionCalculation(
      salesmanId: salesmanId,
      periodFrom: fromSeconds,
      periodTo: toSeconds,
      grossSales: gross,
      commissionAmount: _round(commission),
      rule: rule,
      bands: bands,
    );
  }

  // ------------------------------------------------------------ settlements

  /// Turns a calculation into a payable.
  ///
  /// Refuses if one already exists for exactly this salesman and period —
  /// the readable form of the `UNIQUE(salesman_id, period_from, period_to)`
  /// constraint, so re-running a month is safe rather than duplicating what
  /// the shop owes.
  ///
  /// Note the uniqueness is on the *exact* period. Two overlapping but
  /// differently-bounded periods (1–31 Jan and 15 Jan–15 Feb) are not caught
  /// by the constraint and would double-pay the overlap; the screen only
  /// offers whole months, and the limitation is recorded in the architecture
  /// doc.
  Future<CommissionSettlement> createSettlement(
    String salesmanId,
    DateTime from,
    DateTime to,
  ) async {
    final existing = await _repository.getSettlementForPeriod(salesmanId, from, to);
    if (existing != null) {
      throw CommissionSettlementExists(
        'A ${existing.status.name} settlement already exists for salesman $salesmanId over this period '
        '(₹${existing.commissionAmount.toStringAsFixed(2)}). Delete it first if it needs recalculating.',
      );
    }

    final calculation = await calculateCommission(salesmanId, from, to);
    final settlement = CommissionSettlement.create(
      salesmanId: salesmanId,
      periodFrom: from,
      periodTo: to,
      grossSales: calculation.grossSales,
      commissionAmount: calculation.commissionAmount,
    );
    await _repository.insertSettlement(settlement);
    return settlement;
  }

  /// Marks a settlement paid out. [salaryReference] is free text — a payslip
  /// or voucher number — and is the whole of the "salary integration" this
  /// app can offer, there being no payroll module to link to.
  Future<CommissionSettlement> markAsSettled(
    String settlementId, {
    DateTime? settledDate,
    String? salaryReference,
  }) async {
    final existing = await _requireSettlement(settlementId);
    if (existing.isSettled) {
      throw InvalidSettlementState(
        'Settlement $settlementId was already settled on '
        '${DateTime.fromMillisecondsSinceEpoch(existing.settledDate! * 1000).toLocal()}.',
      );
    }
    final updated = CommissionSettlement(
      id: existing.id,
      salesmanId: existing.salesmanId,
      periodFrom: existing.periodFrom,
      periodTo: existing.periodTo,
      grossSales: existing.grossSales,
      commissionAmount: existing.commissionAmount,
      status: CommissionSettlementStatus.settled,
      settledDate: (settledDate ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000,
      salaryReference: salaryReference ?? existing.salaryReference,
      createdAt: existing.createdAt,
    );
    await _repository.updateSettlement(updated);
    return updated;
  }

  Future<List<CommissionSettlement>> getSettlements({
    String? salesmanId,
    CommissionSettlementStatus? status,
  }) =>
      _repository.getSettlements(salesmanId: salesmanId, status: status);

  /// Removes a settlement raised in error. Only while it is still
  /// `calculated` — a commission that has been paid is history, and deleting
  /// it would leave the payout unexplained.
  Future<void> deleteSettlement(String settlementId) async {
    final existing = await _requireSettlement(settlementId);
    if (existing.isSettled) {
      throw InvalidSettlementState(
        'Settlement $settlementId has been paid out and cannot be deleted. '
        'Raise a correcting settlement for the next period instead.',
      );
    }
    await _repository.deleteSettlement(settlementId);
  }

  /// Total commission owed but not yet paid — the outstanding liability the
  /// payout screen leads with.
  Future<double> outstandingCommission({String? salesmanId}) async {
    final unpaid = await _repository.getSettlements(
      salesmanId: salesmanId,
      status: CommissionSettlementStatus.calculated,
    );
    return unpaid.fold<double>(0.0, (sum, s) => sum + s.commissionAmount);
  }

  // ------------------------------------------------------------- helpers

  void _requirePeriod(DateTime from, DateTime to) {
    if (to.isBefore(from)) {
      throw InvalidCommissionPeriod(
        'Period end ${to.toLocal()} is before its start ${from.toLocal()}.',
      );
    }
  }

  Future<void> _requireSalesman(String salesmanId) async {
    final salesman = await _salesmen.getById(salesmanId);
    if (salesman == null) {
      throw SalesmanNotFound('No salesman with id $salesmanId.');
    }
  }

  Future<CommissionSettlement> _requireSettlement(String id) async {
    final settlement = await _repository.getSettlementById(id);
    if (settlement == null) {
      throw CommissionSettlementNotFound('No commission settlement with id $id.');
    }
    return settlement;
  }
}

final commissionServiceProvider = Provider<CommissionService>((ref) => CommissionService());
