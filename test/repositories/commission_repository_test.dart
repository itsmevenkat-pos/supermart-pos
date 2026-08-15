import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:supermart_pos/core/database/database_helper.dart';
import 'package:supermart_pos/models/commission_rule_model.dart';
import 'package:supermart_pos/models/commission_settlement_model.dart';
import 'package:supermart_pos/models/salesman_model.dart';
import 'package:supermart_pos/repositories/commission_repository.dart';

class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this._path);
  final String _path;

  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late CommissionRepository repository;

  final periodFrom = DateTime(2026, 5, 1);
  final periodTo = DateTime(2026, 5, 31, 23, 59, 59);

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('commission_repo_test');
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

  var invoiceSeq = 1000;

  Future<void> addSale(
    String? salesmanId, {
    required double netAmount,
    required DateTime at,
    String status = 'completed',
  }) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert('sales', {
      'id': 'sale_$invoiceSeq',
      'salesman_id': salesmanId,
      'invoice_no': invoiceSeq++,
      'net_amount': netAmount,
      'status': status,
      'created_at': at.millisecondsSinceEpoch ~/ 1000,
    });
  }

  group('rules', () {
    test('a percentage rule round-trips', () async {
      final salesman = await makeSalesman();
      final rule = CommissionRule.percentage(
        salesmanId: salesman.id,
        rate: 0.025,
        effectiveFrom: DateTime(2026, 1, 1),
      );

      await repository.insertRule(rule);
      final loaded = await repository.getRuleById(rule.id);

      expect(loaded!.ruleType, CommissionRuleType.percentage);
      expect(loaded.baseRate, 0.025);
      expect(loaded.tiers, isEmpty);
      expect(loaded.effectiveTo, isNull);
      expect(loaded.isActive, isTrue);
    });

    test('a tiered rule round-trips its bands, open-ended band included', () async {
      final salesman = await makeSalesman();
      final rule = CommissionRule.tiered(
        salesmanId: salesman.id,
        tiers: const [
          CommissionTier(upTo: 50000, rate: 0.02),
          CommissionTier(upTo: 100000, rate: 0.03),
          CommissionTier(upTo: null, rate: 0.04),
        ],
        effectiveFrom: DateTime(2026, 1, 1),
      );

      await repository.insertRule(rule);
      final loaded = await repository.getRuleById(rule.id);

      expect(loaded!.ruleType, CommissionRuleType.tiered);
      expect(loaded.tiers, hasLength(3));
      expect(loaded.tiers[0].upTo, 50000);
      expect(loaded.tiers[0].rate, 0.02);
      expect(loaded.tiers.last.upTo, isNull);
      expect(loaded.tiers.last.rate, 0.04);
    });

    test('corrupt tier JSON reads back as no bands rather than throwing', () async {
      final salesman = await makeSalesman();
      final db = await DatabaseHelper.instance.database;
      await db.insert('commission_rules', {
        'id': 'broken',
        'salesman_id': salesman.id,
        'rule_type': 'tiered',
        'base_rate': 0,
        'tiered_rates': 'not json at all',
        'effective_from': 0,
        'is_active': 1,
        'created_at': 0,
      });

      final loaded = await repository.getRuleById('broken');

      // CommissionService rejects a tiered rule with no bands, so this
      // surfaces as a refusal rather than a silent ₹0 commission.
      expect(loaded!.tiers, isEmpty);
    });

    test('rules come back newest agreement first', () async {
      final salesman = await makeSalesman();
      await repository.insertRule(CommissionRule.percentage(
        salesmanId: salesman.id,
        rate: 0.01,
        effectiveFrom: DateTime(2025, 1, 1),
        effectiveTo: DateTime(2025, 12, 31),
      ));
      await repository.insertRule(CommissionRule.percentage(
        salesmanId: salesman.id,
        rate: 0.02,
        effectiveFrom: DateTime(2026, 1, 1),
      ));

      final rules = await repository.getRulesForSalesman(salesman.id);

      expect(rules.map((r) => r.baseRate).toList(), [0.02, 0.01]);
    });

    test('activeOnly filters out deactivated rules', () async {
      final salesman = await makeSalesman();
      final rule = CommissionRule.percentage(
        salesmanId: salesman.id,
        rate: 0.02,
        effectiveFrom: DateTime(2026, 1, 1),
      );
      await repository.insertRule(rule);

      await repository.deactivateRule(rule.id);

      expect(await repository.getRulesForSalesman(salesman.id, activeOnly: true), isEmpty);
      // Deactivation keeps the row, so a past settlement's reason survives.
      expect(await repository.getRulesForSalesman(salesman.id), hasLength(1));
      expect((await repository.getRuleById(rule.id))!.isActive, isFalse);
    });

    test('rules are scoped per salesman', () async {
      final a = await makeSalesman(name: 'A');
      final b = await makeSalesman(name: 'B');
      await repository.insertRule(CommissionRule.percentage(
        salesmanId: a.id,
        rate: 0.02,
        effectiveFrom: DateTime(2026, 1, 1),
      ));

      expect(await repository.getRulesForSalesman(b.id), isEmpty);
    });

    test('updateRule replaces the stored row', () async {
      final salesman = await makeSalesman();
      final rule = CommissionRule.percentage(
        salesmanId: salesman.id,
        rate: 0.02,
        effectiveFrom: DateTime(2026, 1, 1),
      );
      await repository.insertRule(rule);

      await repository.updateRule(CommissionRule(
        id: rule.id,
        salesmanId: rule.salesmanId,
        ruleType: rule.ruleType,
        baseRate: 0.05,
        effectiveFrom: rule.effectiveFrom,
        createdAt: rule.createdAt,
      ));

      expect((await repository.getRuleById(rule.id))!.baseRate, 0.05);
    });
  });

  group('gross sales', () {
    test('sums net_amount for the salesman in range', () async {
      final salesman = await makeSalesman();
      await addSale(salesman.id, netAmount: 1000, at: DateTime(2026, 5, 10));
      await addSale(salesman.id, netAmount: 2500.50, at: DateTime(2026, 5, 20));

      expect(await repository.getGrossSales(salesman.id, periodFrom, periodTo),
          closeTo(3500.50, 0.001));
    });

    test('excludes cancelled sales', () async {
      final salesman = await makeSalesman();
      await addSale(salesman.id, netAmount: 1000, at: DateTime(2026, 5, 10));
      await addSale(salesman.id, netAmount: 9999, at: DateTime(2026, 5, 11), status: 'cancelled');

      // Paying commission on a bill the shop reversed would be simply wrong.
      expect(await repository.getGrossSales(salesman.id, periodFrom, periodTo), 1000);
    });

    test('treats a null status as completed', () async {
      final salesman = await makeSalesman();
      final db = await DatabaseHelper.instance.database;
      await db.insert('sales', {
        'id': 'sale_nullstatus',
        'salesman_id': salesman.id,
        'invoice_no': 9911,
        'net_amount': 750,
        'status': null,
        'created_at': DateTime(2026, 5, 12).millisecondsSinceEpoch ~/ 1000,
      });

      expect(await repository.getGrossSales(salesman.id, periodFrom, periodTo), 750);
    });

    test('excludes sales outside the period and includes both boundaries', () async {
      final salesman = await makeSalesman();
      await addSale(salesman.id, netAmount: 100, at: DateTime(2026, 4, 30, 23, 59, 59));
      await addSale(salesman.id, netAmount: 200, at: periodFrom);
      await addSale(salesman.id, netAmount: 400, at: periodTo);
      await addSale(salesman.id, netAmount: 800, at: DateTime(2026, 6, 1));

      // Both bounds inclusive: 200 + 400.
      expect(await repository.getGrossSales(salesman.id, periodFrom, periodTo), 600);
    });

    test('excludes other salesmen and unattributed sales', () async {
      final a = await makeSalesman(name: 'A');
      final b = await makeSalesman(name: 'B');
      await addSale(a.id, netAmount: 100, at: DateTime(2026, 5, 10));
      await addSale(b.id, netAmount: 5000, at: DateTime(2026, 5, 10));
      await addSale(null, netAmount: 7000, at: DateTime(2026, 5, 10));

      expect(await repository.getGrossSales(a.id, periodFrom, periodTo), 100);
    });

    test('no sales at all is zero, not null', () async {
      final salesman = await makeSalesman();
      expect(await repository.getGrossSales(salesman.id, periodFrom, periodTo), 0);
    });
  });

  group('settlements', () {
    Future<CommissionSettlement> makeSettlement(String salesmanId) async {
      final settlement = CommissionSettlement.create(
        salesmanId: salesmanId,
        periodFrom: periodFrom,
        periodTo: periodTo,
        grossSales: 100000,
        commissionAmount: 2500,
      );
      await repository.insertSettlement(settlement);
      return settlement;
    }

    test('a settlement round-trips', () async {
      final salesman = await makeSalesman();
      final settlement = await makeSettlement(salesman.id);

      final loaded = await repository.getSettlementById(settlement.id);

      expect(loaded!.grossSales, 100000);
      expect(loaded.commissionAmount, 2500);
      expect(loaded.status, CommissionSettlementStatus.calculated);
      expect(loaded.settledDate, isNull);
      expect(loaded.salaryReference, isNull);
    });

    test('getSettlementForPeriod finds an exact period match', () async {
      final salesman = await makeSalesman();
      final settlement = await makeSettlement(salesman.id);

      expect((await repository.getSettlementForPeriod(salesman.id, periodFrom, periodTo))!.id,
          settlement.id);
      // A different period is not a match.
      expect(
        await repository.getSettlementForPeriod(salesman.id, periodFrom, DateTime(2026, 5, 30)),
        isNull,
      );
    });

    test('the UNIQUE constraint blocks a duplicate period', () async {
      final salesman = await makeSalesman();
      await makeSettlement(salesman.id);

      expect(() => makeSettlement(salesman.id), throwsA(anything));
    });

    test('settlements filter by salesman and status', () async {
      final a = await makeSalesman(name: 'A');
      final b = await makeSalesman(name: 'B');
      final settledOne = await makeSettlement(a.id);
      await makeSettlement(b.id);

      await repository.updateSettlement(CommissionSettlement(
        id: settledOne.id,
        salesmanId: settledOne.salesmanId,
        periodFrom: settledOne.periodFrom,
        periodTo: settledOne.periodTo,
        grossSales: settledOne.grossSales,
        commissionAmount: settledOne.commissionAmount,
        status: CommissionSettlementStatus.settled,
        settledDate: DateTime(2026, 6, 5).millisecondsSinceEpoch ~/ 1000,
        salaryReference: 'PAYSLIP-42',
        createdAt: settledOne.createdAt,
      ));

      expect(await repository.getSettlements(salesmanId: a.id), hasLength(1));
      expect(
        await repository.getSettlements(status: CommissionSettlementStatus.calculated),
        hasLength(1),
      );
      final settled =
          await repository.getSettlements(status: CommissionSettlementStatus.settled);
      expect(settled.single.salaryReference, 'PAYSLIP-42');
      expect(settled.single.settledDate, isNotNull);
    });

    test('settlements come back most recent period first', () async {
      final salesman = await makeSalesman();
      await repository.insertSettlement(CommissionSettlement.create(
        salesmanId: salesman.id,
        periodFrom: DateTime(2026, 3, 1),
        periodTo: DateTime(2026, 3, 31),
        grossSales: 1000,
        commissionAmount: 20,
      ));
      await repository.insertSettlement(CommissionSettlement.create(
        salesmanId: salesman.id,
        periodFrom: DateTime(2026, 4, 1),
        periodTo: DateTime(2026, 4, 30),
        grossSales: 2000,
        commissionAmount: 40,
      ));

      final all = await repository.getSettlements(salesmanId: salesman.id);

      expect(all.map((s) => s.commissionAmount).toList(), [40, 20]);
    });

    test('delete removes the row', () async {
      final salesman = await makeSalesman();
      final settlement = await makeSettlement(salesman.id);

      await repository.deleteSettlement(settlement.id);

      expect(await repository.getSettlementById(settlement.id), isNull);
    });
  });
}
