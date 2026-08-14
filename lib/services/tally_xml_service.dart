import 'package:uuid/uuid.dart';
import 'package:xml/xml.dart';

import '../models/customer_model.dart';
import '../models/product_model.dart';
import '../models/sale_item_model.dart';
import '../models/sale_model.dart';

/// Builds and parses Tally-compatible "All Masters" / voucher XML envelopes
/// (the `<ENVELOPE><HEADER>...<BODY><IMPORTDATA>...` shape Tally itself
/// exports/imports) so Stock Items, Ledgers, and Sales Vouchers can move
/// between this app and Tally Prime/ERP 9.
class TallyXmlService {
  TallyXmlService._();

  static const _uuid = Uuid();

  // ---------------------------------------------------------------------
  // Parsing (Tally export -> app models)
  // ---------------------------------------------------------------------

  /// Parses `<STOCKITEM>` elements out of a Tally masters export into
  /// [Product]s. Elements missing a NAME are skipped since a product can't
  /// be created without one; a missing PARTNO (barcode) is filled with a
  /// generated placeholder rather than dropping the row.
  static List<Product> parseStockItems(String xmlContent) {
    final document = XmlDocument.parse(xmlContent);
    final products = <Product>[];

    for (final stockItem in document.findAllElements('STOCKITEM')) {
      final name = _text(stockItem, 'NAME') ?? stockItem.getAttribute('NAME');
      if (name == null || name.trim().isEmpty) continue;

      final partNo = _text(stockItem, 'PARTNO');
      final barcode = (partNo != null && partNo.trim().isNotEmpty)
          ? partNo.trim()
          : 'TALLY-${_uuid.v4()}';

      final baseUnits = _text(stockItem, 'BASEUNITS');
      final unit = (baseUnits != null && baseUnits.trim().isNotEmpty) ? baseUnits.trim() : 'Pcs';

      final stockQuantity = double.tryParse(_text(stockItem, 'OPENINGBALANCE') ?? '') ?? 0;
      final mrp = double.tryParse(_text(stockItem, 'OPENINGRATE') ?? '') ?? 0;

      products.add(Product.create(
        barcode: barcode,
        name: name.trim(),
        unit: unit,
        mrp: mrp,
        stockQuantity: stockQuantity,
      ));
    }

    return products;
  }

  /// Parses `<LEDGER>` elements out of a Tally masters export into
  /// [Customer]s. A ledger without NAME or LEDGERPHONE is skipped —
  /// [Customer.create] requires both a name and a phone number, and Tally
  /// ledgers (e.g. expense/income heads) frequently have no phone at all.
  static List<Customer> parseLedgers(String xmlContent) {
    final document = XmlDocument.parse(xmlContent);
    final customers = <Customer>[];

    for (final ledger in document.findAllElements('LEDGER')) {
      final name = _text(ledger, 'NAME') ?? ledger.getAttribute('NAME');
      if (name == null || name.trim().isEmpty) continue;

      final phone = _text(ledger, 'LEDGERPHONE');
      if (phone == null || phone.trim().isEmpty) continue;

      final address = _text(ledger, 'ADDRESS');
      final openingBalance = double.tryParse(_text(ledger, 'OPENINGBALANCE') ?? '') ?? 0;

      customers.add(Customer.create(
        name: name.trim(),
        phone: phone.trim(),
        address: (address != null && address.trim().isNotEmpty) ? address.trim() : null,
        creditLimit: openingBalance,
      ));
    }

    return customers;
  }

  // ---------------------------------------------------------------------
  // Building (app models -> Tally import envelope)
  // ---------------------------------------------------------------------

  static String buildStockItemEnvelope(List<Product> products) {
    final builder = XmlBuilder();
    builder.element('ENVELOPE', nest: () {
      builder.element('HEADER', nest: () {
        builder.element('TALLYREQUEST', nest: 'Import Data');
      });
      builder.element('BODY', nest: () {
        builder.element('IMPORTDATA', nest: () {
          builder.element('REQUESTDESC', nest: () {
            builder.element('REPORTNAME', nest: 'All Masters');
          });
          builder.element('REQUESTDATA', nest: () {
            for (final product in products) {
              builder.element('TALLYMESSAGE', attributes: {'xmlns:UDF': 'TallyUDF'}, nest: () {
                builder.element('STOCKITEM', attributes: {
                  'NAME': product.name,
                  'ACTION': 'Create',
                }, nest: () {
                  builder.element('NAME', nest: product.name);
                  builder.element('PARTNO', nest: product.barcode);
                  builder.element('BASEUNITS', nest: product.unit);
                  builder.element('OPENINGBALANCE', nest: _num(product.stockQuantity));
                  builder.element('OPENINGRATE', nest: _num(product.mrp));
                  builder.element('OPENINGVALUE', nest: _num(product.stockQuantity * product.mrp));
                });
              });
            }
          });
        });
      });
    });

    final document = builder.buildDocument();
    return document.toXmlString(pretty: true);
  }

  static String buildLedgerEnvelope(List<Customer> customers) {
    final builder = XmlBuilder();
    builder.element('ENVELOPE', nest: () {
      builder.element('HEADER', nest: () {
        builder.element('TALLYREQUEST', nest: 'Import Data');
      });
      builder.element('BODY', nest: () {
        builder.element('IMPORTDATA', nest: () {
          builder.element('REQUESTDESC', nest: () {
            builder.element('REPORTNAME', nest: 'All Masters');
          });
          builder.element('REQUESTDATA', nest: () {
            for (final customer in customers) {
              builder.element('TALLYMESSAGE', attributes: {'xmlns:UDF': 'TallyUDF'}, nest: () {
                builder.element('LEDGER', attributes: {
                  'NAME': customer.name,
                  'ACTION': 'Create',
                }, nest: () {
                  builder.element('NAME', nest: customer.name);
                  builder.element('PARENT', nest: 'Sundry Debtors');
                  builder.element('LEDGERPHONE', nest: customer.phone);
                  builder.element('OPENINGBALANCE', nest: _num(customer.outstandingBalance));
                });
              });
            }
          });
        });
      });
    });

    final document = builder.buildDocument();
    return document.toXmlString(pretty: true);
  }

  /// [itemsBySaleId] maps `sale.id` to that sale's line items — used only to
  /// keep this method's signature future-proof for a fuller voucher export
  /// (e.g. per-item `<INVENTORYENTRIES.LIST>`); the current export writes a
  /// single summarized `<ALLLEDGERENTRIES.LIST>` line per sale against a
  /// generic "Sales Account" ledger. PARTYLEDGERNAME is simplified to
  /// 'Cash' for every sale rather than resolving/looking up the actual
  /// customer ledger name.
  static String buildSalesVoucherEnvelope(
    List<Sale> sales,
    Map<String, List<SaleItem>> itemsBySaleId,
  ) {
    final builder = XmlBuilder();
    builder.element('ENVELOPE', nest: () {
      builder.element('HEADER', nest: () {
        builder.element('TALLYREQUEST', nest: 'Import Data');
      });
      builder.element('BODY', nest: () {
        builder.element('IMPORTDATA', nest: () {
          builder.element('REQUESTDESC', nest: () {
            builder.element('REPORTNAME', nest: 'All Masters');
          });
          builder.element('REQUESTDATA', nest: () {
            for (final sale in sales) {
              final date = DateTime.fromMillisecondsSinceEpoch(sale.createdAt * 1000);
              final dateStr = '${date.year.toString().padLeft(4, '0')}'
                  '${date.month.toString().padLeft(2, '0')}'
                  '${date.day.toString().padLeft(2, '0')}';

              builder.element('TALLYMESSAGE', attributes: {'xmlns:UDF': 'TallyUDF'}, nest: () {
                builder.element('VOUCHER', attributes: {
                  'VCHTYPE': 'Sales',
                  'ACTION': 'Create',
                }, nest: () {
                  builder.element('DATE', nest: dateStr);
                  builder.element('VOUCHERNUMBER', nest: sale.invoiceLabel);
                  builder.element('PARTYLEDGERNAME', nest: 'Cash');
                  builder.element('ALLLEDGERENTRIES.LIST', nest: () {
                    builder.element('LEDGERNAME', nest: 'Sales Account');
                    builder.element('ISDEEMEDPOSITIVE', nest: 'No');
                    builder.element('AMOUNT', nest: sale.netAmount.toStringAsFixed(2));
                  });
                });
              });
            }
          });
        });
      });
    });

    final document = builder.buildDocument();
    return document.toXmlString(pretty: true);
  }

  // ---------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------

  static String? _text(XmlElement parent, String tagName) {
    final matches = parent.findElements(tagName);
    if (matches.isEmpty) return null;
    return matches.first.innerText;
  }

  /// Renders a number the way Tally XML expects — no trailing ".0" for
  /// whole numbers, but preserving decimals otherwise.
  static String _num(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toString();
  }
}
