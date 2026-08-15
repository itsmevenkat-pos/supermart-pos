import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:supermart_pos/core/database/database_helper.dart';
import 'package:supermart_pos/models/commission_rule_model.dart';
import 'package:supermart_pos/models/commission_settlement_model.dart';
import 'package:supermart_pos/models/salesman_model.dart';
import 'package:supermart_pos/repositories/commission_repository.dart';
import 'package:supermart_pos/repositories/salesman_repository.dart';
import 'package:supermart_pos/services/commission_exceptions.dart';
import 'package:supermart_pos/services/commission_service.dart';

class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this._path);
  final String _path;

  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late CommissionService service;
  late CommissionRepository repository;

  final periodFrom = DateTime(2026, 5, 1);
  final periodTo = DateTime(2026, 5, 31, 23, 59, 59);

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('commission_service_test');
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
    repository = CommissionRepository();
    service = CommissionService(
      repository: repository,
      salesmanRepository: SalesmanRepository(),
    );
    final db = await DatabaseHelper.instance.database;
    await db.delete('commission_ledger');
    await db.delete('commission_rules');
    await db.delete('sales');
    await db.delete('salesmen');
  });

  Future<Salesman> makeSalesman({String name = 'Kumar'}) async {
    final salesman = Salesman.create(name: name);
    final db = await DatabaseHelper.instance.database;
    await db.insert('salesmen', salesman.toJson());
    return salesman;
  }

  var invoiceSeq = 2000;

  Future<void> addSale(
    String salesmanId, {
    required double netAmount,
    DateTime? at,
    String status = 'completed',
  }) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert('sales', {
      'id': 'sale_$invoiceSeq',
      'salesman_id': salesmanId,
      'invoice_no': invoiceSeq++,
      'net_amount': netAmount,
      'status': status,
      'created_at': (at ?? DateTime(2026, 5, 15)).millisecondsSinceEpoch ~/ 1000,
    });
  }

  Future<CommissionRule> givePercentageRule(
    String salesmanId, {
    double rate = 0.02,
    DateTime? from,
    DateTime? to,
  }) async {
    final rule = CommissionRule.percentage(
      salesmanId: salesmanId,
      rate: rate,
      effectiveFrom: from ?? DateTime(2026, 1, 1),
      effectiveTo: to,
    );
    await repository.insertRule(rule);
    return rule;
  }

  Future<CommissionRule> giveTieredRule(
    String salesmanId, {
    List<CommissionTier>? tiers,
    DateTime? from,
    DateTime? to,
  }) async {
    final rule = CommissionRule.tiered(
      salesmanId: salesmanId,
      tiers: tiers ??
          const [
            CommissionTier(upTo: 50000, rate: 0.02),
            CommissionTier(upTo: null, rate: 0.03),
          ],
      effectiveFrom: from ?? DateTime(2026, 1, 1),
      effectiveTo: to,
    );
    await repository.insertRule(rule);
    return rule;
  }

  group('percentage rules', () {
    test('commission is the flat rate on gross sales', () async {
      final salesman = await makeSalesman();
      await givePercentageRule(salesman.id, rate: 0.025);
      await addSale(salesman.id, netAmount: 40000);

      final result = await service.calculateCommission(salesman.id, periodFrom, periodTo);

      expect(result.grossSales, 40000);
      expect(result.commissionAmount, 1000);
      expect(result.bands, isEmpty);
      expect(result.effectiveRate, closeTo(0.025, 1e-9));
    });

    test('cancelled sales earn nothing', () async {
      final salesman = await makeSalesman();
      await givePercentageRule(salesman.id, rate: 0.10);
      await addSale(salesman.id, netAmount: 1000);
      await addSale(salesman.id, netAmount: 50000, status: 'cancelled');

      final result = await service.calculateCommission(salesman.id, periodFrom, periodTo);

      expect(result.grossSales, 1000);
      expect(result.commissionAmount, 100);
    });

    test('no sales gives zero commission without throwing', () async {
      final salesman = await makeSalesman();
      await givePercentageRule(salesman.id);

      final result = await service.calculateCommission(salesman.id, periodFrom, periodTo);

      expect(result.grossSales, 0);
      expect(result.commissionAmount, 0);
      expect(result.effectiveRate, 0);
    });

    test('commission is rounded to paise', () async {
      final salesman = await makeSalesman();
      await givePercentageRule(salesman.id, rate: 0.0333);
      await addSale(salesman.id, netAmount: 1010.10);

      final result = await service.calculateCommission(salesman.id, periodFrom, periodTo);

      // 1010.10 * 0.0333 = 33.63633
      expect(result.commissionAmount, 33.64);
    });
  });

  group('tiered rules', () {
    test('tiers are marginal, not applied to the whole amount', () async {
      final salesman = await makeSalesman();
      await giveTieredRule(salesman.id);
      await addSale(salesman.id, netAmount: 60000);

      final result = await service.calculateCommission(salesman.id, periodFrom, periodTo);

      // 50000 @ 2% = 1000, then 10000 @ 3% = 300. NOT 60000 @ 3% = 1800.
      expect(result.commissionAmount, 1300);
      expect(result.bands, hasLength(2));
      expect(result.bands[0].salesInBand, 50000);
      expect(result.bands[0].commission, 1000);
      expect(result.bands[1].salesInBand, 10000);
      expect(result.bands[1].commission, 300);
    });

    test('sales exactly at a tier boundary stay entirely in the lower band', () async {
      final salesman = await makeSalesman();
      await giveTieredRule(salesman.id);
      await addSale(salesman.id, netAmount: 50000);

      final result = await service.calculateCommission(salesman.id, periodFrom, periodTo);

      // The upper bound is exclusive, so ₹50,000 is all at 2% — and one rupee
      // more earns 3 paise, not another ₹500.
      expect(result.commissionAmount, 1000);
      expect(result.bands, hasLength(1));
      expect(result.bands.single.salesInBand, 50000);
    });

    test('one rupee past the boundary earns only that rupee at the higher rate', () async {
      final salesman = await makeSalesman();
      await giveTieredRule(salesman.id);
      await addSale(salesman.id, netAmount: 50001);

      final result = await service.calculateCommission(salesman.id, periodFrom, periodTo);

      expect(result.commissionAmount, 1000.03);
    });

    test('sales below the first tier use only that tier', () async {
      final salesman = await makeSalesman();
      await giveTieredRule(salesman.id);
      await addSale(salesman.id, netAmount: 20000);

      final result = await service.calculateCommission(salesman.id, periodFrom, periodTo);

      expect(result.commissionAmount, 400);
      expect(result.bands, hasLength(1));
      expect(result.bands.single.to, 50000);
    });

    test('three bands all contribute', () async {
      final salesman = await makeSalesman();
      await giveTieredRule(salesman.id, tiers: const [
        CommissionTier(upTo: 10000, rate: 0.01),
        CommissionTier(upTo: 20000, rate: 0.02),
        CommissionTier(upTo: null, rate: 0.05),
      ]);
      await addSale(salesman.id, netAmount: 30000);

      final result = await service.calculateCommission(salesman.id, periodFrom, periodTo);

      // 10000@1% = 100, 10000@2% = 200, 10000@5% = 500.
      expect(result.commissionAmount, 800);
      expect(result.bands, hasLength(3));
      expect(result.bands.map((b) => b.commission).toList(), [100, 200, 500]);
    });

    test('bands sum to the total commission', () async {
      final salesman = await makeSalesman();
      await giveTieredRule(salesman.id, tiers: const [
        CommissionTier(upTo: 33333, rate: 0.017),
        CommissionTier(upTo: null, rate: 0.029),
      ]);
      await addSale(salesman.id, netAmount: 74321.55);

      final result = await service.calculateCommission(salesman.id, periodFrom, periodTo);

      final bandSum = result.bands.fold<double>(0, (s, b) => s + b.commission);
      expect(bandSum, closeTo(result.commissionAmount, 0.01));
    });

    test('a tiered rule with no usable bands is refused, not paid as zero', () async {
      final salesman = await makeSalesman();
      final db = await DatabaseHelper.instance.database;
      await db.insert('commission_rules', {
        'id': 'empty_tiers',
        'salesman_id': salesman.id,
        'rule_type': 'tiered',
        'base_rate': 0,
        'tiered_rates': null,
        'effective_from': 0,
        'is_active': 1,
        'created_at': 0,
      });
      await addSale(salesman.id, netAmount: 40000);

      expect(
        () => service.calculateCommission(salesman.id, periodFrom, periodTo),
        throwsA(isA<InvalidCommissionRule>()),
      );
    });
  });

  group('rule validation', () {
    test('a negative percentage rate is rejected', () async {
      final salesman = await makeSalesman();
      expect(
        () => service.createRule(CommissionRule.percentage(
          salesmanId: salesman.id,
          rate: -0.01,
          effectiveFrom: DateTime(2026, 1, 1),
        )),
        throwsA(isA<InvalidCommissionRule>()),
      );
    });

    test('descending bands are rejected', () async {
      final salesman = await makeSalesman();
      expect(
        () => service.createRule(CommissionRule.tiered(
          salesmanId: salesman.id,
          tiers: const [
            CommissionTier(upTo: 50000, rate: 0.02),
            CommissionTier(upTo: 10000, rate: 0.03),
          ],
          effectiveFrom: DateTime(2026, 1, 1),
        )),
        throwsA(isA<InvalidCommissionRule>()),
      );
    });

    test('an open-ended band that is not last is rejected', () async {
      final salesman = await makeSalesman();
      expect(
        () => service.createRule(CommissionRule.tiered(
          salesmanId: salesman.id,
          tiers: const [
            CommissionTier(upTo: null, rate: 0.03),
            CommissionTier(upTo: 50000, rate: 0.02),
          ],
          effectiveFrom: DateTime(2026, 1, 1),
        )),
        throwsA(isA<InvalidCommissionRule>()),
      );
    });

    test('a rule that ends before it starts is rejected', () async {
      final salesman = await makeSalesman();
      expect(
        () => service.createRule(CommissionRule.percentage(
          salesmanId: salesman.id,
          rate: 0.02,
          effectiveFrom: DateTime(2026, 5, 1),
          effectiveTo: DateTime(2026, 4, 1),
        )),
        throwsA(isA<InvalidCommissionRule>()),
      );
    });

    test('a rule for an unknown salesman is rejected', () async {
      expect(
        () => service.createRule(CommissionRule.percentage(
          salesmanId: 'ghost',
          rate: 0.02,
          effectiveFrom: DateTime(2026, 1, 1),
        )),
        throwsA(isA<SalesmanNotFound>()),
      );
    });

    test('a valid rule is stored', () async {
      final salesman = await makeSalesman();
      final rule = await service.createRule(CommissionRule.percentage(
        salesmanId: salesman.id,
        rate: 0.02,
        effectiveFrom: DateTime(2026, 1, 1),
      ));

      expect(await service.getRules(salesman.id), hasLength(1));
      expect(rule.baseRate, 0.02);
    });
  });

  group('rule selection', () {
    test('no rule at all is refused rather than paid as zero', () async {
      final salesman = await makeSalesman();
      await addSale(salesman.id, netAmount: 40000);

      expect(
        () => service.calculateCommission(salesman.id, periodFrom, periodTo),
        throwsA(isA<NoCommissionRule>()),
      );
    });

    test('a deactivated rule does not apply', () async {
      final salesman = await makeSalesman();
      final rule = await givePercentageRule(salesman.id);
      await service.deactivateRule(rule.id);

      expect(
        () => service.calculateCommission(salesman.id, periodFrom, periodTo),
        throwsA(isA<NoCommissionRule>()),
      );
    });

    test('two overlapping rules are refused, not silently resolved', () async {
      final salesman = await makeSalesman();
      await givePercentageRule(salesman.id, rate: 0.02, from: DateTime(2026, 1, 1));
      await givePercentageRule(salesman.id, rate: 0.05, from: DateTime(2026, 5, 15));

      expect(
        () => service.calculateCommission(salesman.id, periodFrom, periodTo),
        throwsA(isA<AmbiguousCommissionRule>()),
      );
    });

    test('a rule covering only part of the period is refused', () async {
      final salesman = await makeSalesman();
      // Starts mid-period, so the first fortnight has no rate.
      await givePercentageRule(salesman.id, from: DateTime(2026, 5, 15));

      expect(
        () => service.calculateCommission(salesman.id, periodFrom, periodTo),
        throwsA(isA<NoCommissionRule>()),
      );
    });

    test('a rule that ends mid-period is refused', () async {
      final salesman = await makeSalesman();
      await givePercentageRule(
        salesman.id,
        from: DateTime(2026, 1, 1),
        to: DateTime(2026, 5, 20),
      );

      expect(
        () => service.calculateCommission(salesman.id, periodFrom, periodTo),
        throwsA(isA<NoCommissionRule>()),
      );
    });

    test('a closed rule that exactly spans the period applies', () async {
      final salesman = await makeSalesman();
      await givePercentageRule(
        salesman.id,
        rate: 0.03,
        from: periodFrom,
        to: periodTo,
      );
      await addSale(salesman.id, netAmount: 10000);

      final result = await service.calculateCommission(salesman.id, periodFrom, periodTo);

      expect(result.commissionAmount, 300);
    });

    test('an earlier retired rule and a current one do not collide', () async {
      final salesman = await makeSalesman();
      await givePercentageRule(
        salesman.id,
        rate: 0.01,
        from: DateTime(2025, 1, 1),
        to: DateTime(2025, 12, 31),
      );
      await givePercentageRule(salesman.id, rate: 0.04, from: DateTime(2026, 1, 1));
      await addSale(salesman.id, netAmount: 10000);

      final result = await service.calculateCommission(salesman.id, periodFrom, periodTo);

      expect(result.commissionAmount, 400);
    });

    test('an unknown salesman is refused', () async {
      expect(
        () => service.calculateCommission('ghost', periodFrom, periodTo),
        throwsA(isA<SalesmanNotFound>()),
      );
    });

    test('a period that runs backwards is refused', () async {
      final salesman = await makeSalesman();
      expect(
        () => service.calculateCommission(salesman.id, periodTo, periodFrom),
        throwsA(isA<InvalidCommissionPeriod>()),
      );
    });
  });

  group('settlements', () {
    test('creating a settlement stores the calculated figures', () async {
      final salesman = await makeSalesman();
      await givePercentageRule(salesman.id, rate: 0.02);
      await addSale(salesman.id, netAmount: 75000);

      final settlement = await service.createSettlement(salesman.id, periodFrom, periodTo);

      expect(settlement.grossSales, 75000);
      expect(settlement.commissionAmount, 1500);
      expect(settlement.status, CommissionSettlementStatus.calculated);
      expect(settlement.settledDate, isNull);
    });

    test('a second settlement for the same period is refused', () async {
      final salesman = await makeSalesman();
      await givePercentageRule(salesman.id);
      await addSale(salesman.id, netAmount: 10000);
      await service.createSettlement(salesman.id, periodFrom, periodTo);

      expect(
        () => service.createSettlement(salesman.id, periodFrom, periodTo),
        throwsA(isA<CommissionSettlementExists>()),
      );
    });

    test('creating a settlement with no rule leaves nothing behind', () async {
      final salesman = await makeSalesman();
      await addSale(salesman.id, netAmount: 10000);

      await expectLater(
        () => service.createSettlement(salesman.id, periodFrom, periodTo),
        throwsA(isA<NoCommissionRule>()),
      );
      expect(await service.getSettlements(salesmanId: salesman.id), isEmpty);
    });

    test('marking settled records the date and reference', () async {
      final salesman = await makeSalesman();
      await givePercentageRule(salesman.id);
      await addSale(salesman.id, netAmount: 10000);
      final settlement = await service.createSettlement(salesman.id, periodFrom, periodTo);

      final settled = await service.markAsSettled(
        settlement.id,
        settledDate: DateTime(2026, 6, 5),
        salaryReference: 'PAYSLIP-2026-06',
      );

      expect(settled.isSettled, isTrue);
      expect(settled.salaryReference, 'PAYSLIP-2026-06');
      expect(settled.settledDate, DateTime(2026, 6, 5).millisecondsSinceEpoch ~/ 1000);
      // And the figures are untouched by settling.
      expect(settled.commissionAmount, settlement.commissionAmount);
    });

    test('settling twice is refused', () async {
      final salesman = await makeSalesman();
      await givePercentageRule(salesman.id);
      await addSale(salesman.id, netAmount: 10000);
      final settlement = await service.createSettlement(salesman.id, periodFrom, periodTo);
      await service.markAsSettled(settlement.id);

      expect(
        () => service.markAsSettled(settlement.id),
        throwsA(isA<InvalidSettlementState>()),
      );
    });

    test('a paid settlement cannot be deleted', () async {
      final salesman = await makeSalesman();
      await givePercentageRule(salesman.id);
      await addSale(salesman.id, netAmount: 10000);
      final settlement = await service.createSettlement(salesman.id, periodFrom, periodTo);
      await service.markAsSettled(settlement.id);

      expect(
        () => service.deleteSettlement(settlement.id),
        throwsA(isA<InvalidSettlementState>()),
      );
    });

    test('an unpaid settlement can be deleted and recalculated', () async {
      final salesman = await makeSalesman();
      await givePercentageRule(salesman.id, rate: 0.02);
      await addSale(salesman.id, netAmount: 10000);
      final first = await service.createSettlement(salesman.id, periodFrom, periodTo);

      // A late sale turns up for the same period.
      await addSale(salesman.id, netAmount: 5000);
      await service.deleteSettlement(first.id);
      final second = await service.createSettlement(salesman.id, periodFrom, periodTo);

      expect(second.grossSales, 15000);
      expect(second.commissionAmount, 300);
    });

    test('acting on an unknown settlement is refused', () async {
      expect(
        () => service.markAsSettled('ghost'),
        throwsA(isA<CommissionSettlementNotFound>()),
      );
      expect(
        () => service.deleteSettlement('ghost'),
        throwsA(isA<CommissionSettlementNotFound>()),
      );
    });

    test('outstanding commission counts only unpaid settlements', () async {
      final a = await makeSalesman(name: 'A');
      final b = await makeSalesman(name: 'B');
      await givePercentageRule(a.id, rate: 0.02);
      await givePercentageRule(b.id, rate: 0.02);
      await addSale(a.id, netAmount: 100000); // 2000
      await addSale(b.id, netAmount: 50000); // 1000
      final settlementA = await service.createSettlement(a.id, periodFrom, periodTo);
      await service.createSettlement(b.id, periodFrom, periodTo);

      expect(await service.outstandingCommission(), 3000);

      await service.markAsSettled(settlementA.id);

      expect(await service.outstandingCommission(), 1000);
      expect(await service.outstandingCommission(salesmanId: a.id), 0);
      expect(await service.outstandingCommission(salesmanId: b.id), 1000);
    });

    test('grossSalesFor works without a rule in place', () async {
      final salesman = await makeSalesman();
      await addSale(salesman.id, netAmount: 1234.50);

      expect(await service.grossSalesFor(salesman.id, periodFrom, periodTo),
          closeTo(1234.50, 0.001));
    });
  });
}
