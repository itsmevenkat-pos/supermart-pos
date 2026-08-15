import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite/sqflite.dart';

import 'package:supermart_pos/core/database/database_helper.dart';
import 'package:supermart_pos/models/gl_entry_model.dart';
import 'package:supermart_pos/repositories/gl_repository.dart';
import 'package:supermart_pos/services/financial_statement_service.dart';
import 'package:supermart_pos/services/gl_service.dart';

/// See the note on the same class in
/// `test/services/financial_year_close_service_test.dart`.
class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this._path);
  final String _path;

  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Database db;
  late GLService gl;
  late FinancialStatementService statements;

  const fy = '25-26';
  final inFy = DateTime(2025, 6, 15);

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('financial_statement_test');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
    db = await DatabaseHelper.instance.database;
  });

  tearDownAll(() async {
    await DatabaseHelper.instance.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  setUp(() async {
    gl = GLService();
    statements = FinancialStatementService();
    await db.delete('gl_entries');
    await db.delete('gl_balances');
    await db.delete('financial_year_closures');
    await db.update('chart_of_accounts', {'is_active': 1});
  });

  /// A small but complete set of books for FY 25-26:
  ///
  /// - Owner puts in 50,000 capital                (Dr Bank      Cr Capital)
  /// - Buys stock for 30,000 on account            (Dr Inventory Cr Payables)
  /// - Sells for 45,000 cash                       (Dr Cash      Cr Revenue)
  /// - Pays 8,000 rent in cash                     (Dr Rent      Cr Cash)
  ///
  /// Expected: Cash 37,000 · Bank 50,000 · Inventory 30,000 · Payables 30,000
  /// Capital 50,000 · Revenue 45,000 · Rent 8,000 · net profit 37,000.
  Future<void> seedBooks() async {
    await gl.postCompoundEntry(
      entryDate: inFy,
      description: 'Owner capital',
      referenceType: 'Manual',
      referenceId: 'capital-1',
      accounts: {'coa_1010': 50000, 'coa_3000': -50000},
    );
    await gl.postCompoundEntry(
      entryDate: inFy,
      description: 'Stock purchase on account',
      referenceType: 'Purchase',
      referenceId: 'purchase-1',
      accounts: {'coa_1200': 30000, 'coa_2000': -30000},
    );
    await gl.postCompoundEntry(
      entryDate: inFy,
      description: 'Cash sales',
      referenceType: 'Sale',
      referenceId: 'sale-1',
      accounts: {'coa_1000': 45000, 'coa_4000': -45000},
    );
    await gl.postCompoundEntry(
      entryDate: inFy,
      description: 'Shop rent',
      referenceType: 'Manual',
      referenceId: 'rent-1',
      accounts: {'coa_5200': 8000, 'coa_1000': -8000},
    );
  }

  group('generateTrialBalance', () {
    test('is balanced and matches hand-computed column totals', () async {
      await seedBooks();

      final tb = await statements.generateTrialBalance(fy);

      // Debits:  Cash 37,000 + Bank 50,000 + Inventory 30,000 + Rent 8,000
      // Credits: Payables 30,000 + Capital 50,000 + Revenue 45,000
      expect(tb.totalDebits, 125000);
      expect(tb.totalCredits, 125000);
      expect(tb.isBalanced, isTrue);
    });

    test('puts each account in the correct column', () async {
      await seedBooks();

      final tb = await statements.generateTrialBalance(fy);
      final byCode = {for (final r in tb.rows) r.account.code: r};

      // Debit balances.
      expect(byCode['1000']!.debit, 37000); // Cash: 45,000 in less 8,000 rent
      expect(byCode['1000']!.credit, 0);
      expect(byCode['1010']!.debit, 50000); // Bank
      expect(byCode['1200']!.debit, 30000); // Inventory
      expect(byCode['5200']!.debit, 8000); // Rent

      // Credit balances.
      expect(byCode['2000']!.credit, 30000); // Accounts Payable
      expect(byCode['2000']!.debit, 0);
      expect(byCode['3000']!.credit, 50000); // Capital
      expect(byCode['4000']!.credit, 45000); // Sales Revenue
    });

    test('lists every active account but offers the non-zero ones separately', () async {
      await seedBooks();

      final tb = await statements.generateTrialBalance(fy);

      expect(tb.rows, hasLength(20), reason: 'every active account is listed');
      expect(tb.nonZeroRows.map((r) => r.account.code).toSet(),
          {'1000', '1010', '1200', '2000', '3000', '4000', '5200'});
    });

    test('an empty year is balanced at zero rather than an error', () async {
      final tb = await statements.generateTrialBalance('99-00');

      expect(tb.totalDebits, 0);
      expect(tb.totalCredits, 0);
      expect(tb.isBalanced, isTrue);
      expect(tb.nonZeroRows, isEmpty);
    });

    test('counts only the requested financial year', () async {
      await seedBooks();
      await gl.postCompoundEntry(
        entryDate: DateTime(2026, 6, 1), // FY 26-27
        description: 'Next year sale',
        referenceType: 'Sale',
        accounts: {'coa_1000': 999, 'coa_4000': -999},
      );

      expect((await statements.generateTrialBalance(fy)).totalDebits, 125000);
      expect((await statements.generateTrialBalance('26-27')).totalDebits, 999);
    });

    test('stays balanced after a reversal', () async {
      await seedBooks();
      final saleLines = await GLRepository().getEntriesByReference('Sale', 'sale-1');
      await gl.reverseEntry(saleLines.first.id, reason: 'Wrong amount');

      final tb = await statements.generateTrialBalance(fy);

      expect(tb.isBalanced, isFalse, reason: 'reversing one side only genuinely unbalances the books');

      // Reversing the other side too restores the balance.
      await gl.reverseEntry(saleLines.last.id, reason: 'Wrong amount');
      final restored = await statements.generateTrialBalance(fy);
      expect(restored.isBalanced, isTrue);
    });

    test('reports a broken state instead of throwing', () async {
      await seedBooks();
      // A one-sided line written straight to the repository, bypassing
      // GLService's balancing check — the only way to construct this. These
      // are diagnostic reports: they must surface a broken ledger, not crash
      // on one.
      await GLRepository().postEntry(GLEntry.post(
        entryDate: inFy,
        accountId: 'coa_1000',
        amount: 5000,
        isDebit: true,
        description: 'Corrupt one-sided line',
        referenceType: 'Manual',
      ));

      final tb = await statements.generateTrialBalance(fy);

      expect(tb.isBalanced, isFalse);
      expect(tb.totalDebits - tb.totalCredits, 5000);
    });
  });

  group('generatePLStatement', () {
    test('matches hand-computed revenue, expenses and profit', () async {
      await seedBooks();

      final pl = await statements.generatePLStatement(financialYear: fy);

      expect(pl.revenue, 45000);
      expect(pl.otherExpenses, 8000);
      expect(pl.netProfit, 37000);
      expect(pl.totalExpenses, 8000);
    });

    test('breaks COGS out of the other expenses using account 5000', () async {
      await seedBooks();
      // Post COGS by hand — nothing in the app posts to 5000 yet (see the
      // note on generatePLStatement), so this proves the split works for
      // when something does.
      await gl.postCompoundEntry(
        entryDate: inFy,
        description: 'Cost of goods sold',
        referenceType: 'Manual',
        accounts: {'coa_5000': 20000, 'coa_1200': -20000},
      );

      final pl = await statements.generatePLStatement(financialYear: fy);

      expect(pl.cogs, 20000);
      expect(pl.otherExpenses, 8000, reason: 'rent is not folded into COGS');
      expect(pl.grossProfit, 25000, reason: '45,000 revenue less 20,000 COGS');
      expect(pl.netProfit, 17000, reason: 'gross profit less 8,000 rent');
    });

    test('COGS reads zero while nothing posts to account 5000', () async {
      await seedBooks();

      final pl = await statements.generatePLStatement(financialYear: fy);

      // Documented limitation, asserted so a future COGS posting makes this
      // test fail loudly rather than changing reports silently.
      expect(pl.cogs, 0);
      expect(pl.grossProfit, pl.revenue);
    });

    test('nets a sales return out of revenue', () async {
      await seedBooks();
      await gl.postCompoundEntry(
        entryDate: inFy,
        description: 'Sales return',
        referenceType: 'Return',
        referenceId: 'ret-1',
        accounts: {'coa_4000': 5000, 'coa_1000': -5000},
      );

      final pl = await statements.generatePLStatement(financialYear: fy);

      expect(pl.revenue, 40000);
      expect(pl.netProfit, 32000);
    });

    test('a loss is reported as a negative net profit, not zero', () async {
      await gl.postCompoundEntry(
        entryDate: inFy,
        description: 'Small sale',
        referenceType: 'Sale',
        accounts: {'coa_1000': 1000, 'coa_4000': -1000},
      );
      await gl.postCompoundEntry(
        entryDate: inFy,
        description: 'Large rent',
        referenceType: 'Manual',
        accounts: {'coa_5200': 9000, 'coa_1000': -9000},
      );

      final pl = await statements.generatePLStatement(financialYear: fy);

      expect(pl.netProfit, -8000);
    });

    test('lists per-account revenue and expense detail', () async {
      await seedBooks();

      final pl = await statements.generatePLStatement(financialYear: fy);

      expect(pl.revenueLines.map((r) => r.account.code), ['4000', '4100', '4900']);
      expect(pl.expenseLines.map((r) => r.account.code).toList(),
          ['5000', '5100', '5200', '5300', '5400', '5500']);
      expect(pl.revenueLines.firstWhere((r) => r.account.code == '4000').credit, 45000);
    });
  });

  group('generateBalanceSheet', () {
    test('balances: assets equal liabilities plus equity', () async {
      await seedBooks();

      final bs = await statements.generateBalanceSheet(financialYear: fy);

      // Assets: Cash 37,000 + Bank 50,000 + Inventory 30,000 = 117,000
      expect(bs.totalAssets, 117000);
      // Liabilities: Accounts Payable 30,000
      expect(bs.totalLiabilities, 30000);
      // Equity: Capital 50,000 + this year's profit 37,000 = 87,000
      expect(bs.totalEquity, 87000);
      expect(bs.isBalanced, isTrue);
    });

    test('splits assets and liabilities by sub_type', () async {
      await seedBooks();
      await gl.postCompoundEntry(
        entryDate: inFy,
        description: 'Buy a chiller on a long-term loan',
        referenceType: 'Manual',
        accounts: {'coa_1500': 120000, 'coa_2200': -120000},
      );

      final bs = await statements.generateBalanceSheet(financialYear: fy);

      expect(bs.currentAssets.total, 117000, reason: 'cash, bank and inventory');
      expect(bs.fixedAssets.total, 120000, reason: 'the chiller');
      expect(bs.currentLiabilities.total, 30000, reason: 'accounts payable');
      expect(bs.longTermLiabilities.total, 120000, reason: 'the loan');
      expect(bs.isBalanced, isTrue, reason: 'a bigger balance sheet still balances');
    });

    test('carries this year\'s profit into equity without posting it', () async {
      await seedBooks();

      final bs = await statements.generateBalanceSheet(financialYear: fy);

      expect(bs.netProfit, 37000);
      expect(bs.equity.total, 50000, reason: 'only the posted capital');
      expect(bs.totalEquity, 87000, reason: 'posted equity plus the year\'s profit');

      // Retained Earnings must NOT have been posted to — that only happens
      // when the year is closed.
      final retained = await GLRepository().getEntriesByAccount('coa_3100');
      expect(retained, isEmpty);
    });

    test('a loss reduces equity', () async {
      await gl.postCompoundEntry(
        entryDate: inFy,
        description: 'Owner capital',
        referenceType: 'Manual',
        accounts: {'coa_1000': 10000, 'coa_3000': -10000},
      );
      await gl.postCompoundEntry(
        entryDate: inFy,
        description: 'Rent, no sales',
        referenceType: 'Manual',
        accounts: {'coa_5200': 4000, 'coa_1000': -4000},
      );

      final bs = await statements.generateBalanceSheet(financialYear: fy);

      expect(bs.totalAssets, 6000);
      expect(bs.netProfit, -4000);
      expect(bs.totalEquity, 6000, reason: '10,000 capital less a 4,000 loss');
      expect(bs.isBalanced, isTrue);
    });

    test('asOf excludes entries dated after the cut-off', () async {
      await gl.postCompoundEntry(
        entryDate: DateTime(2025, 5, 1),
        description: 'May sale',
        referenceType: 'Sale',
        accounts: {'coa_1000': 1000, 'coa_4000': -1000},
      );
      await gl.postCompoundEntry(
        entryDate: DateTime(2025, 9, 1),
        description: 'September sale',
        referenceType: 'Sale',
        accounts: {'coa_1000': 5000, 'coa_4000': -5000},
      );

      final asAtJune = await statements.generateBalanceSheet(
        financialYear: fy,
        asOf: DateTime(2025, 6, 30),
      );
      final wholeYear = await statements.generateBalanceSheet(financialYear: fy);

      expect(asAtJune.totalAssets, 1000);
      expect(asAtJune.isBalanced, isTrue);
      expect(wholeYear.totalAssets, 6000);
      expect(wholeYear.isBalanced, isTrue);
    });

    test('an empty year balances at zero', () async {
      final bs = await statements.generateBalanceSheet(financialYear: '99-00');

      expect(bs.totalAssets, 0);
      expect(bs.totalLiabilities, 0);
      expect(bs.totalEquity, 0);
      expect(bs.isBalanced, isTrue);
    });

    test('reports a broken state instead of throwing', () async {
      await seedBooks();
      await GLRepository().postEntry(GLEntry.post(
        entryDate: inFy,
        accountId: 'coa_1000',
        amount: 2500,
        isDebit: true,
        description: 'Corrupt one-sided line',
        referenceType: 'Manual',
      ));

      final bs = await statements.generateBalanceSheet(financialYear: fy);

      expect(bs.isBalanced, isFalse);
      expect(bs.totalAssets - (bs.totalLiabilities + bs.totalEquity), 2500);
    });

    test('an asset with an unrecognised sub_type is still counted', () async {
      await db.update('chart_of_accounts', {'sub_type': 'something_new'},
          where: 'id = ?', whereArgs: ['coa_1000']);
      await seedBooks();

      final bs = await statements.generateBalanceSheet(financialYear: fy);

      // Filed as current rather than dropped — a mislabelled asset is a
      // labelling problem, a dropped one unbalances the statement.
      expect(bs.currentAssets.lines.any((r) => r.account.code == '1000'), isTrue);
      expect(bs.isBalanced, isTrue);

      await db.update('chart_of_accounts', {'sub_type': 'current_asset'},
          where: 'id = ?', whereArgs: ['coa_1000']);
    });
  });

  group('the three statements agree with each other', () {
    test('P&L net profit is the same figure the Balance Sheet uses', () async {
      await seedBooks();

      final pl = await statements.generatePLStatement(financialYear: fy);
      final bs = await statements.generateBalanceSheet(financialYear: fy);

      expect(bs.netProfit, pl.netProfit);
    });

    test('Trial Balance revenue and expense columns match the P&L', () async {
      await seedBooks();

      final tb = await statements.generateTrialBalance(fy);
      final pl = await statements.generatePLStatement(financialYear: fy);
      final byCode = {for (final r in tb.rows) r.account.code: r};

      expect(byCode['4000']!.credit, pl.revenue);
      expect(byCode['5200']!.debit, pl.otherExpenses);
    });
  });

  group('getFinancialYearsWithEntries', () {
    test('lists only years with activity, newest first', () async {
      await seedBooks();
      await gl.postCompoundEntry(
        entryDate: DateTime(2026, 6, 1),
        description: 'Next year',
        referenceType: 'Sale',
        accounts: {'coa_1000': 100, 'coa_4000': -100},
      );

      expect(await statements.getFinancialYearsWithEntries(), ['26-27', '25-26']);
    });

    test('is empty on a ledger with no entries', () async {
      expect(await statements.getFinancialYearsWithEntries(), isEmpty);
    });
  });
}
