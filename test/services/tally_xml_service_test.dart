import 'package:flutter_test/flutter_test.dart';

import 'package:supermart_pos/models/customer_model.dart';
import 'package:supermart_pos/models/product_model.dart';
import 'package:supermart_pos/services/tally_xml_service.dart';

void main() {
  group('TallyXmlService - Stock Item round-trip', () {
    test('builds and parses back product name/barcode/unit', () {
      final products = [
        Product.create(
          barcode: '8901234567890',
          name: 'Parle-G Biscuit 100g',
          unit: 'Pcs',
          mrp: 10,
          stockQuantity: 25,
        ),
        Product.create(
          barcode: '8909876543210',
          name: 'Amul Milk 500ml',
          unit: 'Ltr',
          mrp: 32.5,
          stockQuantity: 12.5,
        ),
      ];

      final xml = TallyXmlService.buildStockItemEnvelope(products);

      expect(xml, contains('<ENVELOPE>'));
      expect(xml, contains('<STOCKITEM'));

      final parsed = TallyXmlService.parseStockItems(xml);

      expect(parsed.length, 2);

      expect(parsed[0].name, 'Parle-G Biscuit 100g');
      expect(parsed[0].barcode, '8901234567890');
      expect(parsed[0].unit, 'Pcs');
      expect(parsed[0].stockQuantity, 25);
      expect(parsed[0].mrp, 10);

      expect(parsed[1].name, 'Amul Milk 500ml');
      expect(parsed[1].barcode, '8909876543210');
      expect(parsed[1].unit, 'Ltr');
      expect(parsed[1].stockQuantity, 12.5);
      expect(parsed[1].mrp, 32.5);
    });

    test('missing PARTNO falls back to a generated placeholder barcode', () {
      const xml = '''
<ENVELOPE>
  <BODY>
    <IMPORTDATA>
      <REQUESTDATA>
        <TALLYMESSAGE>
          <STOCKITEM NAME="No Barcode Item" ACTION="Create">
            <NAME>No Barcode Item</NAME>
            <BASEUNITS>Pcs</BASEUNITS>
            <OPENINGBALANCE>5</OPENINGBALANCE>
            <OPENINGRATE>20</OPENINGRATE>
          </STOCKITEM>
        </TALLYMESSAGE>
      </REQUESTDATA>
    </IMPORTDATA>
  </BODY>
</ENVELOPE>
''';

      final parsed = TallyXmlService.parseStockItems(xml);

      expect(parsed.length, 1);
      expect(parsed[0].name, 'No Barcode Item');
      expect(parsed[0].barcode, startsWith('TALLY-'));
    });
  });

  group('TallyXmlService - Ledger round-trip', () {
    test('builds and parses back customer name/phone', () {
      final customers = [
        Customer.create(name: 'Ravi Kumar', phone: '9876543210'),
        Customer.create(name: 'Sita Traders', phone: '9123456780'),
      ];

      final xml = TallyXmlService.buildLedgerEnvelope(customers);

      expect(xml, contains('<ENVELOPE>'));
      expect(xml, contains('<LEDGER'));
      expect(xml, contains('Sundry Debtors'));

      final parsed = TallyXmlService.parseLedgers(xml);

      expect(parsed.length, 2);
      expect(parsed[0].name, 'Ravi Kumar');
      expect(parsed[0].phone, '9876543210');
      expect(parsed[1].name, 'Sita Traders');
      expect(parsed[1].phone, '9123456780');
    });

    test('ledger without LEDGERPHONE is skipped', () {
      const xml = '''
<ENVELOPE>
  <BODY>
    <IMPORTDATA>
      <REQUESTDATA>
        <TALLYMESSAGE>
          <LEDGER NAME="Sales Account" ACTION="Create">
            <NAME>Sales Account</NAME>
            <PARENT>Sales Accounts</PARENT>
          </LEDGER>
        </TALLYMESSAGE>
      </REQUESTDATA>
    </IMPORTDATA>
  </BODY>
</ENVELOPE>
''';

      final parsed = TallyXmlService.parseLedgers(xml);

      expect(parsed, isEmpty);
    });
  });
}
