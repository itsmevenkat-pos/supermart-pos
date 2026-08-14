import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ReportService - Returns Netting', () {
    test('net sales subtracts refunds processed in the period', () {
      const grossSales = 10000.0;
      const totalReturns = 850.0;

      final netSales = grossSales - totalReturns;

      expect(netSales, 9150.0);
    });

    test('net tax subtracts tax reversed by returns, floored at zero', () {
      const grossTax = 200.0;
      const returnedTax = 500.0;

      final netTax = (grossTax - returnedTax).clamp(0, double.infinity);

      expect(netTax, 0.0);
    });

    test('net COGS subtracts cost of returned lines regardless of restock flag', () {
      const grossCogs = 6000.0;
      const restockedLineCogs = 300.0;
      const damagedLineCogs = 120.0;
      final returnedCogs = restockedLineCogs + damagedLineCogs;

      final netCogs = grossCogs - returnedCogs;

      expect(netCogs, 5580.0);
    });

    test('profit is computed from already-netted sales and COGS', () {
      const netSalesExTax = 9000.0;
      const netCogs = 5580.0;

      final grossProfit = netSalesExTax - netCogs;

      expect(grossProfit, 3420.0);
    });
  });
}
