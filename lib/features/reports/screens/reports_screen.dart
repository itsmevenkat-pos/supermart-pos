import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../providers/report_provider.dart';
import '../widgets/report_card.dart';
import '../../../core/utils/quantity_utils.dart';
import '../widgets/date_filter_widget.dart';
import '../../../services/advanced_report_service.dart';
import 'generic_report_screen.dart';
import 'party_statement_screen.dart';
import 'item_detail_screen.dart';
import 'trial_balance_screen.dart';
import 'pl_statement_screen.dart';
import 'balance_sheet_screen.dart';

final _advancedReportService = AdvancedReportService();

const _gstDisclaimer =
    'Unofficial computation for internal reference only — grouped by tax rate, '
    'not a filing-ready statutory format. Verify with your CA/GST software before filing.';
const _simplifiedDisclaimer =
    'Simplified summary built from ledger balances and current stock value — '
    'not a statutory-format statement.';

String _money(dynamic v) => '₹${((v as num?)?.toDouble() ?? 0).toStringAsFixed(2)}';
String _qty(dynamic v) => ((v as num?)?.toDouble() ?? 0).toStringAsFixed(2);
String _date(dynamic v) {
  if (v == null) return '';
  final seconds = v is int ? v : (v as num).toInt();
  return DateTime.fromMillisecondsSinceEpoch(seconds * 1000).toLocal().toString().split(' ')[0];
}

/// A sub-report link inside a tab's "Detailed Reports" section — pushes
/// whatever `build()` returns (a [GenericReportScreen] built inline, or a
/// dedicated picker screen) via the shared `/reports/detail` catch-all
/// route, so individual reports don't each need their own named GoRoute.
Widget _reportTile(BuildContext context, String title, Widget Function() build) {
  return ListTile(
    dense: true,
    title: Text(title),
    trailing: const Icon(Icons.chevron_right),
    onTap: () => context.push('/reports/detail', extra: build()),
  );
}

/// Same as [_reportTile] but for a link to an existing top-level route
/// (Sales History, Sales Summary, Quotations) rather than a report built
/// from [AdvancedReportService].
Widget _routeTile(BuildContext context, String title, String route) {
  return ListTile(
    dense: true,
    title: Text(title),
    trailing: const Icon(Icons.chevron_right),
    onTap: () => context.push(route),
  );
}

class ReportsScreen extends ConsumerStatefulWidget {
  final int initialTabIndex;

  const ReportsScreen({super.key, this.initialTabIndex = 0});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  DateTime? _fromDate;
  DateTime? _toDate;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 6,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 5),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Reports',
      actions: [
        DateFilterWidget(
          fromDate: _fromDate,
          toDate: _toDate,
          onFilterApplied: (from, to) {
            setState(() {
              _fromDate = from;
              _toDate = to;
            });
            _refreshAllReports();
          },
          onFilterCleared: () {
            setState(() {
              _fromDate = null;
              _toDate = null;
            });
            _refreshAllReports();
          },
        ),
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: _refreshAllReports,
        ),
      ],
      body: Column(
        children: [
          TabBar(
            controller: _tabController,
            isScrollable: true,
            labelColor: Theme.of(context).primaryColor,
            indicatorColor: Theme.of(context).primaryColor,
            tabs: const [
              Tab(text: 'Sales'),
              Tab(text: 'Stock'),
              Tab(text: 'Purchase'),
              Tab(text: 'GST'),
              Tab(text: 'Profit & Loss'),
              Tab(text: 'More'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _SalesReportTab(
                  fromDate: _fromDate,
                  toDate: _toDate,
                ),
                const _StockReportTab(),
                _PurchaseReportTab(
                  fromDate: _fromDate,
                  toDate: _toDate,
                ),
                _GstReportTab(
                  fromDate: _fromDate,
                  toDate: _toDate,
                ),
                _ProfitLossTab(
                  fromDate: _fromDate,
                  toDate: _toDate,
                ),
                const _MoreReportsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _refreshAllReports() {
    ref.invalidate(salesReportProvider);
    ref.invalidate(stockReportProvider);
    ref.invalidate(purchaseReportProvider);
    ref.invalidate(gstReportProvider);
    ref.invalidate(profitLossReportProvider);
    ref.invalidate(paymentModeSummaryProvider);
  }
}

/// A collapsible section of related detailed reports, placed at the top of
/// a tab above its existing quick-stats content — keeps every sales-related
/// report reachable from Report → Sales, every stock-related one from
/// Report → Stock, and so on, instead of a separate "browse all" screen.
class _DetailedReportsSection extends StatelessWidget {
  final List<Widget> tiles;

  const _DetailedReportsSection({required this.tiles});

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        title: const Text('Detailed Reports', style: TextStyle(fontWeight: FontWeight.bold)),
        children: tiles,
      ),
    );
  }
}

// ---------- More Tab: categories that don't belong to a single named tab ----------
class _MoreReportsTab extends StatelessWidget {
  const _MoreReportsTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _category(context, 'Transaction Report', [
          _reportTile(
            context,
            'Day Book',
            () => GenericReportScreen(
              title: 'Day Book',
              fetch: (from, to) => _advancedReportService.getDayBook(from: from, to: to),
              columns: [
                const ReportColumn(key: 'type', label: 'Type'),
                ReportColumn(key: 'date', label: 'Date', formatter: _date),
                const ReportColumn(key: 'reference', label: 'Reference'),
                const ReportColumn(key: 'party', label: 'Party'),
                ReportColumn(key: 'amount', label: 'Amount', formatter: _money),
              ],
            ),
          ),
          _reportTile(
            context,
            'All Transactions',
            () => GenericReportScreen(
              title: 'All Transactions',
              fetch: (from, to) => _advancedReportService.getAllTransactions(from: from, to: to),
              columns: [
                const ReportColumn(key: 'type', label: 'Type'),
                ReportColumn(key: 'date', label: 'Date', formatter: _date),
                const ReportColumn(key: 'reference', label: 'Reference'),
                const ReportColumn(key: 'party', label: 'Party'),
                ReportColumn(key: 'amount', label: 'Amount', formatter: _money),
                ReportColumn(key: 'runningBalance', label: 'Running Balance', formatter: _money),
              ],
            ),
          ),
        ]),
        _category(context, 'Party Report', [
          _reportTile(context, 'Party Statement', () => const PartyStatementScreen()),
          _reportTile(
            context,
            'All Parties',
            () => GenericReportScreen(
              title: 'All Parties',
              fetch: (from, to) => _advancedReportService.getAllParties(from: from, to: to),
              columns: [
                const ReportColumn(key: 'name', label: 'Name'),
                const ReportColumn(key: 'type', label: 'Type'),
                const ReportColumn(key: 'phone', label: 'Phone'),
                ReportColumn(key: 'balance', label: 'Balance', formatter: _money),
              ],
            ),
          ),
          _reportTile(
            context,
            'Customer Last Visit',
            () => GenericReportScreen(
              title: 'Customer Last Visit',
              fetch: (from, to) => _advancedReportService.getCustomerLastVisit(),
              columns: [
                const ReportColumn(key: 'name', label: 'Customer'),
                const ReportColumn(key: 'phone', label: 'Phone'),
                ReportColumn(key: 'totalSpent', label: 'Total Spent', formatter: _money),
                ReportColumn(key: 'lastVisit', label: 'Last Visit', formatter: _date),
                ReportColumn(key: 'daysSinceVisit', label: 'Days Since'),
              ],
              disclaimerText: 'Sorted most-overdue first. Blank "Last Visit" means they\'ve never purchased.',
            ),
          ),
          _reportTile(
            context,
            'Party Report By Item',
            () => GenericReportScreen(
              title: 'Party Report By Item',
              fetch: (from, to) => _advancedReportService.getPartyReportByItem(from: from, to: to),
              columns: [
                const ReportColumn(key: 'customerName', label: 'Customer'),
                const ReportColumn(key: 'productName', label: 'Item'),
                ReportColumn(key: 'quantity', label: 'Qty', formatter: _qty),
                ReportColumn(key: 'amount', label: 'Amount', formatter: _money),
              ],
            ),
          ),
          _reportTile(
            context,
            'Sale Purchase By Party',
            () => GenericReportScreen(
              title: 'Sale Purchase By Party',
              fetch: (from, to) => _advancedReportService.getSalePurchaseByParty(from: from, to: to),
              columns: [
                const ReportColumn(key: 'partyType', label: 'Type'),
                const ReportColumn(key: 'party', label: 'Party'),
                ReportColumn(key: 'amount', label: 'Amount', formatter: _money),
              ],
            ),
          ),
          _reportTile(
            context,
            'Sale Purchase By Party Group',
            () => GenericReportScreen(
              title: 'Sale Purchase By Party Group',
              fetch: (from, to) => _advancedReportService.getSalePurchaseByPartyGroup(from: from, to: to),
              columns: [
                const ReportColumn(key: 'partyType', label: 'Type'),
                const ReportColumn(key: 'groupName', label: 'Group'),
                ReportColumn(key: 'amount', label: 'Amount', formatter: _money),
              ],
              disclaimerText:
                  'Customers are grouped by their rating (gold/silver/bronze/regular). '
                  'Suppliers have no grouping field in this app, so all supplier purchases show as one "Ungrouped" row.',
            ),
          ),
        ]),
        _category(context, 'Business Status', [
          _reportTile(
            context,
            'Bank Statement',
            () => GenericReportScreen(
              title: 'Bank Statement',
              fetch: (from, to) => _advancedReportService.getBankStatement(from: from, to: to),
              columns: [
                const ReportColumn(key: 'type', label: 'Type'),
                ReportColumn(key: 'date', label: 'Date', formatter: _date),
                const ReportColumn(key: 'method', label: 'Method'),
                ReportColumn(key: 'amount', label: 'Amount', formatter: _money),
                const ReportColumn(key: 'reference', label: 'Reference'),
              ],
              disclaimerText: 'Derived from recorded payment methods, not a reconciled bank feed.',
            ),
          ),
          _reportTile(
            context,
            'Discount Report',
            () => GenericReportScreen(
              title: 'Discount Report',
              fetch: (from, to) => _advancedReportService.getDiscountReport(from: from, to: to),
              columns: [
                const ReportColumn(key: 'day', label: 'Date'),
                ReportColumn(key: 'totalDiscount', label: 'Total Discount', formatter: _money),
              ],
            ),
          ),
        ]),
        // Built from the General Ledger (`gl_entries`) rather than from
        // sales/purchase tables like the reports above — these three are
        // double-entry statements and pick their own financial year, so they
        // don't take the shared from/to date filter.
        _category(context, 'Accounting Statements (General Ledger)', [
          _reportTile(context, 'Trial Balance (GL)', () => const TrialBalanceScreen()),
          _reportTile(context, 'Profit & Loss (GL)', () => const PLStatementScreen()),
          _reportTile(context, 'Balance Sheet (GL)', () => const BalanceSheetScreen()),
        ]),
      ],
    );
  }

  Widget _category(BuildContext context, String title, List<Widget> children) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        children: children,
      ),
    );
  }
}

// ---------- Payment Mode Summary (day-close breakdown) ----------
// Previously nothing aggregated sales.payment_methods into a cash/UPI/card/
// credit breakdown — "Bank Statement" under More Reports lists individual
// non-cash transactions, but that's a transaction log, not a same-glance
// total per method, and it explicitly excludes cash. This is always
// scoped to today (see paymentModeSummaryProvider) — a day-close summary
// for last month isn't a meaningful thing to ask for.
class _PaymentModeSummaryCard extends ConsumerWidget {
  const _PaymentModeSummaryCard();

  static const _methodColors = {
    'cash': Colors.green,
    'upi': Colors.purple,
    'card': Colors.blue,
    'credit': Colors.orange,
  };

  Color _colorFor(String method) => _methodColors[method] ?? Colors.blueGrey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(paymentModeSummaryProvider);

    return summaryAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (err, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text('Could not load payment mode summary: $err'),
      ),
      data: (totals) {
        final total = totals.values.fold<double>(0, (sum, v) => sum + v);
        final entries = totals.entries.where((e) => e.value != 0).toList()
          ..sort((a, b) => b.value.compareTo(a.value));

        return Card(
          margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Payment Modes — Today', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    Text(
                      '₹${total.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (entries.isEmpty)
                  const Text('No completed sales yet today', style: TextStyle(color: Colors.grey))
                else
                  Wrap(
                    spacing: 16,
                    runSpacing: 12,
                    children: [
                      for (final entry in entries)
                        SizedBox(
                          width: 130,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                entry.key[0].toUpperCase() + entry.key.substring(1),
                                style: const TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                              Text(
                                '₹${entry.value.toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: _colorFor(entry.key),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ---------- Sales Report Tab ----------
class _SalesReportTab extends ConsumerWidget {
  final DateTime? fromDate;
  final DateTime? toDate;

  const _SalesReportTab({this.fromDate, this.toDate});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportAsync = ref.watch(salesReportProvider);

    return Column(
      children: [
        const _PaymentModeSummaryCard(),
        _DetailedReportsSection(tiles: [
          _routeTile(context, 'Sales History', '/sales-history'),
          _routeTile(context, 'Sales Summary', '/sales-summary'),
          _routeTile(context, 'Quotations', '/quotations'),
          _routeTile(context, 'Sales Dashboard', '/reports/sales-dashboard'),
          _routeTile(context, 'Top Selling Products', '/reports/product-performance'),
          _routeTile(context, 'AI Analysis', '/reports/ai-analysis'),
          _routeTile(context, 'Sale Cancellations', '/sales-cancellations'),
          _routeTile(context, 'Exchanges', '/exchanges'),
          _reportTile(
            context,
            'Bill Wise Profit',
            () => GenericReportScreen(
              title: 'Bill Wise Profit',
              fetch: (from, to) => _advancedReportService.getBillWiseProfit(from: from, to: to),
              columns: [
                const ReportColumn(key: 'invoiceNo', label: 'Invoice No'),
                ReportColumn(key: 'date', label: 'Date', formatter: _date),
                const ReportColumn(key: 'customerName', label: 'Customer'),
                ReportColumn(key: 'netSaleAmount', label: 'Net Sale', formatter: _money),
                ReportColumn(key: 'cogs', label: 'COGS', formatter: _money),
                ReportColumn(key: 'profit', label: 'Profit', formatter: _money),
              ],
            ),
          ),
          _reportTile(
            context,
            'User Wise Sales Report',
            () => GenericReportScreen(
              title: 'User Wise Sales Report',
              fetch: (from, to) => _advancedReportService.getUserWiseSales(from: from, to: to),
              columns: [
                const ReportColumn(key: 'userName', label: 'Cashier'),
                const ReportColumn(key: 'billCount', label: 'Bills'),
                ReportColumn(key: 'totalSales', label: 'Total Sales', formatter: _money),
                ReportColumn(key: 'cash', label: 'Cash', formatter: _money),
                ReportColumn(key: 'upi', label: 'UPI', formatter: _money),
                ReportColumn(key: 'card', label: 'Card', formatter: _money),
                ReportColumn(key: 'credit', label: 'Credit', formatter: _money),
              ],
            ),
          ),
          _reportTile(
            context,
            'Sale Return Report',
            () => GenericReportScreen(
              title: 'Sale Return Report',
              fetch: (from, to) => _advancedReportService.getSalesReturnReport(from: from, to: to),
              columns: [
                ReportColumn(key: 'date', label: 'Date', formatter: _date),
                const ReportColumn(key: 'invoiceRef', label: 'Invoice'),
                const ReportColumn(key: 'customerName', label: 'Customer'),
                const ReportColumn(key: 'reason', label: 'Reason'),
                const ReportColumn(key: 'refundMethod', label: 'Refund Method'),
                ReportColumn(key: 'refundAmount', label: 'Refund Amount', formatter: _money),
                const ReportColumn(key: 'itemCount', label: 'Items'),
                const ReportColumn(key: 'restockedCount', label: 'Restocked'),
              ],
            ),
          ),
          _reportTile(
            context,
            'Sales Cancel Report',
            () => GenericReportScreen(
              title: 'Sales Cancel Report',
              fetch: (from, to) => _advancedReportService.getSalesCancelReport(from: from, to: to),
              columns: [
                ReportColumn(key: 'date', label: 'Date', formatter: _date),
                const ReportColumn(key: 'invoiceRef', label: 'Invoice'),
                const ReportColumn(key: 'customerName', label: 'Customer'),
                const ReportColumn(key: 'reason', label: 'Reason'),
                const ReportColumn(key: 'refundMethod', label: 'Refund Method'),
                ReportColumn(key: 'refundAmount', label: 'Refund Amount', formatter: _money),
              ],
            ),
          ),
          _reportTile(
            context,
            'Exchange Report',
            () => GenericReportScreen(
              title: 'Exchange Report',
              fetch: (from, to) => _advancedReportService.getExchangeReport(from: from, to: to),
              columns: [
                ReportColumn(key: 'date', label: 'Date', formatter: _date),
                const ReportColumn(key: 'originalInvoiceRef', label: 'Original Invoice'),
                const ReportColumn(key: 'newInvoiceRef', label: 'New Invoice'),
                const ReportColumn(key: 'customerName', label: 'Customer'),
                ReportColumn(key: 'priceDifference', label: 'Price Difference', formatter: _money),
                const ReportColumn(key: 'settlementMethod', label: 'Settlement'),
              ],
            ),
          ),
        ]),
        Expanded(
          child: reportAsync.when(
            data: (data) {
              final items = [
                ReportItem(
                  title: 'Total Sales',
                  value: '₹${(data['totalSales'] ?? 0).toStringAsFixed(2)}',
                  color: Colors.green,
                  icon: Icons.currency_rupee,
                ),
                ReportItem(
                  title: 'Total Bills',
                  value: '${data['totalBills'] ?? 0}',
                  color: Colors.blue,
                  icon: Icons.receipt,
                ),
                ReportItem(
                  title: 'Average Bill',
                  value: '₹${(data['averageBill'] ?? 0).toStringAsFixed(2)}',
                  color: Colors.purple,
                  icon: Icons.trending_up,
                ),
                ReportItem(
                  title: 'Total Tax',
                  value: '₹${(data['totalTax'] ?? 0).toStringAsFixed(2)}',
                  color: Colors.orange,
                  icon: Icons.account_balance,
                ),
                ReportItem(
                  title: 'Total Discount',
                  value: '₹${(data['totalDiscount'] ?? 0).toStringAsFixed(2)}',
                  color: Colors.red,
                  icon: Icons.percent,
                ),
                ReportItem(
                  title: 'Returns',
                  value: '₹${(data['totalReturns'] ?? 0).toStringAsFixed(2)}',
                  color: Colors.deepOrange,
                  icon: Icons.assignment_return,
                ),
              ];

              return _ReportGrid(items: items);
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, stack) => Center(child: Text('Error: $err')),
          ),
        ),
      ],
    );
  }
}

// ---------- Stock Report Tab ----------
class _StockReportTab extends ConsumerStatefulWidget {
  const _StockReportTab();

  @override
  ConsumerState<_StockReportTab> createState() => _StockReportTabState();
}

class _StockReportTabState extends ConsumerState<_StockReportTab> {
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    final reportAsync = ref.watch(stockReportProvider);

    return Column(
      children: [
        _DetailedReportsSection(tiles: [
          _reportTile(
            context,
            'Stock Detail',
            () => GenericReportScreen(
              title: 'Stock Detail',
              fetch: (from, to) => _advancedReportService.getStockDetail(from: from, to: to),
              columns: [
                ReportColumn(key: 'date', label: 'Date', formatter: _date),
                const ReportColumn(key: 'productName', label: 'Item'),
                const ReportColumn(key: 'referenceType', label: 'Reference'),
                ReportColumn(key: 'quantityChange', label: 'Qty Change', formatter: _qty),
                const ReportColumn(key: 'batchNo', label: 'Batch No'),
              ],
            ),
          ),
          _reportTile(
            context,
            'Stock Summary Report By Item Category',
            () => GenericReportScreen(
              title: 'Stock Summary Report By Item Category',
              fetch: (from, to) => _advancedReportService.getStockSummaryByItemCategory(),
              columns: [
                const ReportColumn(key: 'category', label: 'Category'),
                ReportColumn(key: 'stockValue', label: 'Stock Value', formatter: _money),
              ],
            ),
          ),
          _reportTile(
            context,
            'Low Stock Summary',
            () => GenericReportScreen(
              title: 'Low Stock Summary',
              fetch: (from, to) => _advancedReportService.getLowStockSummary(),
              columns: const [
                ReportColumn(key: 'name', label: 'Item'),
                ReportColumn(key: 'barcode', label: 'Barcode'),
                ReportColumn(key: 'stockQuantity', label: 'In Stock'),
                ReportColumn(key: 'reorderLevel', label: 'Reorder Level'),
                ReportColumn(key: 'category', label: 'Category'),
              ],
            ),
          ),
          _reportTile(
            context,
            'Near-Expiry / Expired Stock',
            () => GenericReportScreen(
              title: 'Near-Expiry / Expired Stock',
              fetch: (from, to) => _advancedReportService.getExpiryAlerts(),
              columns: [
                const ReportColumn(key: 'productName', label: 'Item'),
                const ReportColumn(key: 'batchNo', label: 'Batch'),
                ReportColumn(key: 'expiryDate', label: 'Expiry Date', formatter: _date),
                const ReportColumn(key: 'status', label: 'Status'),
                ReportColumn(key: 'quantityReceived', label: 'Qty Received', formatter: _qty),
                ReportColumn(key: 'currentProductStock', label: 'Current Total Stock', formatter: _qty),
              ],
              disclaimerText:
                  'Quantity Received is the batch\'s original purchase quantity, not what\'s currently left — '
                  'this app doesn\'t track per-batch remaining stock (FIFO), only total stock per product. '
                  'Use this to spot which batches/expiry dates need physical checking.',
            ),
          ),
          _reportTile(
            context,
            'Slow Moving Stock',
            () => GenericReportScreen(
              title: 'Slow Moving Stock',
              fetch: (from, to) => _advancedReportService.getSlowMovingStock(),
              columns: const [
                ReportColumn(key: 'name', label: 'Item'),
                ReportColumn(key: 'barcode', label: 'Barcode'),
                ReportColumn(key: 'stockQuantity', label: 'In Stock'),
                ReportColumn(key: 'soldQuantity', label: 'Sold (60d)'),
                ReportColumn(key: 'daysSinceLastSale', label: 'Days Since Last Sale'),
              ],
              disclaimerText: 'In-stock items that sold little or nothing in the last 60 days. '
                  'Blank "Days Since Last Sale" means it has never sold at all.',
            ),
          ),
          _reportTile(context, 'Item Detail', () => const ItemDetailScreen()),
          _reportTile(
            context,
            'Item Wise Profit And Loss',
            () => GenericReportScreen(
              title: 'Item Wise Profit And Loss',
              fetch: (from, to) => _advancedReportService.getItemWiseProfitLoss(from: from, to: to),
              columns: [
                const ReportColumn(key: 'name', label: 'Item'),
                ReportColumn(key: 'quantity', label: 'Qty', formatter: _qty),
                ReportColumn(key: 'revenue', label: 'Revenue', formatter: _money),
                ReportColumn(key: 'cogs', label: 'COGS', formatter: _money),
                ReportColumn(key: 'profit', label: 'Profit', formatter: _money),
              ],
            ),
          ),
          _reportTile(
            context,
            'Item Category Wise Profit And Loss',
            () => GenericReportScreen(
              title: 'Item Category Wise Profit And Loss',
              fetch: (from, to) => _advancedReportService.getItemCategoryWiseProfitLoss(from: from, to: to),
              columns: [
                const ReportColumn(key: 'category', label: 'Category'),
                ReportColumn(key: 'quantity', label: 'Qty', formatter: _qty),
                ReportColumn(key: 'revenue', label: 'Revenue', formatter: _money),
                ReportColumn(key: 'cogs', label: 'COGS', formatter: _money),
                ReportColumn(key: 'profit', label: 'Profit', formatter: _money),
              ],
            ),
          ),
          _reportTile(
            context,
            'Item Wise Discount',
            () => GenericReportScreen(
              title: 'Item Wise Discount',
              fetch: (from, to) => _advancedReportService.getItemWiseDiscount(from: from, to: to),
              columns: [
                const ReportColumn(key: 'name', label: 'Item'),
                ReportColumn(key: 'totalDiscount', label: 'Total Discount', formatter: _money),
                const ReportColumn(key: 'discountCount', label: 'Times Discounted'),
              ],
            ),
          ),
          _reportTile(
            context,
            'Sale/Purchase Report By Item Category',
            () => GenericReportScreen(
              title: 'Sale/Purchase Report By Item Category',
              fetch: (from, to) => _advancedReportService.getSalePurchaseByItemCategory(from: from, to: to),
              columns: [
                const ReportColumn(key: 'type', label: 'Type'),
                const ReportColumn(key: 'category', label: 'Category'),
                ReportColumn(key: 'amount', label: 'Amount', formatter: _money),
              ],
            ),
          ),
        ]),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            IconButton(
              icon: Icon(
                _filter == 'all' ? Icons.filter_list : Icons.filter_list_off,
              ),
              onPressed: () {
                setState(() {
                  _filter = _filter == 'all' ? 'low_stock' : 'all';
                });
              },
            ),
          ],
        ),
        Expanded(
          child: reportAsync.when(
            data: (items) {
              final filtered = _filter == 'low_stock'
                  ? items.where((i) => i['isLowStock'] == true).toList()
                  : items;

              if (filtered.isEmpty) {
                return const Center(
                  child: Text(
                    'No products found',
                    style: TextStyle(color: Colors.grey),
                  ),
                );
              }

              double totalStockValue = 0;
              double totalSellValue = 0;

              for (final item in filtered) {
                totalStockValue += item['stockValue'] ?? 0;
                totalSellValue += item['sellValue'] ?? 0;
              }

              return Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _summaryItem('Items', '${filtered.length}'),
                        _summaryItem('Stock Value', '₹${totalStockValue.toStringAsFixed(2)}', color: Colors.green),
                        _summaryItem('Sell Value', '₹${totalSellValue.toStringAsFixed(2)}', color: Colors.blue),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (_, index) {
                        final item = filtered[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: (item['isLowStock'] as bool)
                                  ? Colors.red.shade100
                                  : Colors.green.shade100,
                              child: Text(
                                formatQty((item['stockQuantity'] as num).toDouble()),
                                style: TextStyle(
                                  color: (item['isLowStock'] as bool)
                                      ? Colors.red
                                      : Colors.green,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            title: Text(item['name'] ?? ''),
                            subtitle: Text(
                              'Barcode: ${item['barcode'] ?? ''} | ${item['category'] ?? ''}',
                            ),
                            trailing: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '₹${(item['stockValue'] ?? 0).toStringAsFixed(2)}',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  '₹${(item['retailPrice'] ?? 0).toStringAsFixed(2)}',
                                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, stack) => Center(child: Text('Error: $err')),
          ),
        ),
      ],
    );
  }

  Widget _summaryItem(String label, String value, {Color color = Colors.black}) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Text(
          value,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }
}

// ---------- Purchase Report Tab ----------
class _PurchaseReportTab extends ConsumerWidget {
  final DateTime? fromDate;
  final DateTime? toDate;

  const _PurchaseReportTab({this.fromDate, this.toDate});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportAsync = ref.watch(purchaseReportProvider);

    return reportAsync.when(
      data: (data) {
        final items = [
          ReportItem(
            title: 'Total Purchases',
            value: '₹${(data['totalPurchases'] ?? 0).toStringAsFixed(2)}',
            color: Colors.red,
            icon: Icons.shopping_cart,
          ),
          ReportItem(
            title: 'Total Orders',
            value: '${data['totalOrders'] ?? 0}',
            color: Colors.blue,
            icon: Icons.receipt_long,
          ),
          ReportItem(
            title: 'Average Order',
            value: '₹${(data['averageOrder'] ?? 0).toStringAsFixed(2)}',
            color: Colors.purple,
            icon: Icons.trending_up,
          ),
        ];

        return _ReportGrid(items: items);
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('Error: $err')),
    );
  }
}

// ---------- GST Report Tab ----------
class _GstReportTab extends ConsumerWidget {
  final DateTime? fromDate;
  final DateTime? toDate;

  const _GstReportTab({this.fromDate, this.toDate});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportAsync = ref.watch(gstReportProvider);

    return Column(
      children: [
        _DetailedReportsSection(tiles: [
          _reportTile(
            context,
            'GSTR 1',
            () => GenericReportScreen(
              title: 'GSTR 1',
              fetch: (from, to) => _advancedReportService.getGstr1(from: from, to: to),
              columns: [
                ReportColumn(key: 'rate', label: 'Tax Rate %', formatter: _qty),
                ReportColumn(key: 'taxableValue', label: 'Taxable Value', formatter: _money),
                ReportColumn(key: 'taxAmount', label: 'Tax Amount', formatter: _money),
                const ReportColumn(key: 'invoiceCount', label: 'Invoices'),
              ],
              disclaimerText: _gstDisclaimer,
            ),
          ),
          _reportTile(
            context,
            'GSTR 2',
            () => GenericReportScreen(
              title: 'GSTR 2',
              fetch: (from, to) => _advancedReportService.getGstr2(from: from, to: to),
              columns: [
                ReportColumn(key: 'rate', label: 'Tax Rate %', formatter: _qty),
                ReportColumn(key: 'taxableValue', label: 'Taxable Value', formatter: _money),
                ReportColumn(key: 'taxAmount', label: 'Tax Amount', formatter: _money),
                const ReportColumn(key: 'invoiceCount', label: 'Bills'),
              ],
              disclaimerText: _gstDisclaimer,
            ),
          ),
          _reportTile(
            context,
            'GSTR 3B',
            () => GenericReportScreen(
              title: 'GSTR 3B',
              fetch: (from, to) => _advancedReportService.getGstr3b(from: from, to: to),
              columns: [
                ReportColumn(key: 'outputTax', label: 'Output Tax', formatter: _money),
                ReportColumn(key: 'inputTaxCredit', label: 'Input Tax Credit', formatter: _money),
                ReportColumn(key: 'netTaxPayable', label: 'Net Tax Payable', formatter: _money),
              ],
              disclaimerText: _gstDisclaimer,
            ),
          ),
          _reportTile(
            context,
            'GSTR 9',
            () => GenericReportScreen(
              title: 'GSTR 9 (Annual)',
              fetch: (from, to) => _advancedReportService.getGstr9(from: from, to: to),
              columns: [
                ReportColumn(key: 'outputTax', label: 'Output Tax', formatter: _money),
                ReportColumn(key: 'inputTaxCredit', label: 'Input Tax Credit', formatter: _money),
                ReportColumn(key: 'netTaxPayable', label: 'Net Tax Payable', formatter: _money),
              ],
              disclaimerText: _gstDisclaimer,
            ),
          ),
          _reportTile(
            context,
            'Sale Summary By HSN',
            () => GenericReportScreen(
              title: 'Sale Summary By HSN',
              fetch: (from, to) => _advancedReportService.getSaleSummaryByHsn(from: from, to: to),
              columns: [
                const ReportColumn(key: 'code', label: 'HSN Code'),
                ReportColumn(key: 'quantity', label: 'Qty', formatter: _qty),
                ReportColumn(key: 'taxableValue', label: 'Taxable Value', formatter: _money),
                ReportColumn(key: 'taxAmount', label: 'Tax Amount', formatter: _money),
              ],
              disclaimerText:
                  'Products without an HSN code (see item edit) show as "Not set". '
                  'Also covers SAC reporting — this app has no separate services code, so SAC generally does not apply to a goods retailer.',
            ),
          ),
          _reportTile(
            context,
            'GST Rate Report',
            () => GenericReportScreen(
              title: 'GST Rate Report',
              fetch: (from, to) => _advancedReportService.getGstRateReport(from: from, to: to),
              columns: [
                const ReportColumn(key: 'taxName', label: 'Tax Name'),
                ReportColumn(key: 'taxableSaleAmount', label: 'Taxable Sale Amount', formatter: _money),
                ReportColumn(key: 'taxIn', label: 'Tax In', formatter: _money),
                ReportColumn(key: 'taxablePurchaseAmount', label: 'Taxable Purchase Amount', formatter: _money),
                ReportColumn(key: 'taxOut', label: 'Tax Out', formatter: _money),
              ],
              disclaimerText:
                  'Each item\'s tax rate is split evenly into SGST + CGST, assuming intra-state sales. '
                  'Inter-state (IGST) transactions are not distinguished in this app.',
            ),
          ),
        ]),
        Expanded(
          child: reportAsync.when(
            data: (data) {
              final items = [
                ReportItem(
                  title: 'Total Tax Collected',
                  value: '₹${(data['totalTax'] ?? 0).toStringAsFixed(2)}',
                  color: Colors.orange,
                  icon: Icons.account_balance,
                ),
                ReportItem(
                  title: 'Total Taxable Amount',
                  value: '₹${(data['totalTaxable'] ?? 0).toStringAsFixed(2)}',
                  color: Colors.blue,
                  icon: Icons.currency_rupee,
                ),
                ReportItem(
                  title: 'Effective Tax Rate',
                  value: '${(data['taxRate'] ?? 0).toStringAsFixed(2)}%',
                  color: Colors.green,
                  icon: Icons.percent,
                ),
              ];

              return _ReportGrid(items: items);
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, stack) => Center(child: Text('Error: $err')),
          ),
        ),
      ],
    );
  }
}

// ---------- Profit & Loss Tab ----------
class _ProfitLossTab extends ConsumerWidget {
  final DateTime? fromDate;
  final DateTime? toDate;

  const _ProfitLossTab({this.fromDate, this.toDate});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportAsync = ref.watch(profitLossReportProvider);

    return Column(
      children: [
        _DetailedReportsSection(tiles: [
          _reportTile(
            context,
            'Party wise Profit & Loss',
            () => GenericReportScreen(
              title: 'Party wise Profit & Loss',
              fetch: (from, to) => _advancedReportService.getPartyWiseProfitLoss(from: from, to: to),
              columns: [
                const ReportColumn(key: 'name', label: 'Customer'),
                ReportColumn(key: 'totalSales', label: 'Sales', formatter: _money),
                ReportColumn(key: 'totalCogs', label: 'COGS', formatter: _money),
                ReportColumn(key: 'profit', label: 'Profit', formatter: _money),
              ],
            ),
          ),
          _reportTile(
            context,
            'Trial Balance (Summary)',
            () => GenericReportScreen(
              title: 'Trial Balance (Summary)',
              fetch: (from, to) => _advancedReportService.getTrialBalance(from: from, to: to),
              columns: [
                const ReportColumn(key: 'account', label: 'Account'),
                ReportColumn(key: 'debit', label: 'Debit', formatter: _money),
                ReportColumn(key: 'credit', label: 'Credit', formatter: _money),
              ],
              disclaimerText: _simplifiedDisclaimer,
            ),
          ),
          _reportTile(
            context,
            'Balance Sheet (Summary)',
            () => GenericReportScreen(
              title: 'Balance Sheet (Summary)',
              fetch: (from, to) => _advancedReportService.getBalanceSheet(from: from, to: to),
              columns: [
                const ReportColumn(key: 'category', label: 'Category'),
                const ReportColumn(key: 'item', label: 'Item'),
                ReportColumn(key: 'amount', label: 'Amount', formatter: _money),
              ],
              disclaimerText: _simplifiedDisclaimer,
            ),
          ),
        ]),
        Expanded(
          child: reportAsync.when(
            data: (data) {
              final grossProfit = data['grossProfit'] ?? 0.0;
              final items = [
                ReportItem(
                  title: 'Total Sales',
                  value: '₹${(data['totalSales'] ?? 0).toStringAsFixed(2)}',
                  color: Colors.green,
                  icon: Icons.arrow_upward,
                ),
                ReportItem(
                  title: 'Total Purchases',
                  value: '₹${(data['totalPurchases'] ?? 0).toStringAsFixed(2)}',
                  color: Colors.red,
                  icon: Icons.arrow_downward,
                ),
                ReportItem(
                  title: 'Cost of Goods Sold',
                  value: '₹${(data['totalCogs'] ?? 0).toStringAsFixed(2)}',
                  color: Colors.orange,
                  icon: Icons.inventory_2,
                ),
                ReportItem(
                  title: 'Gross Profit',
                  value: '₹${grossProfit.toStringAsFixed(2)}',
                  color: grossProfit >= 0 ? Colors.blue : Colors.red,
                  icon: Icons.trending_up,
                ),
                ReportItem(
                  title: 'Profit Margin',
                  value: '${(data['profitMargin'] ?? 0).toStringAsFixed(2)}%',
                  color: (data['profitMargin'] ?? 0) >= 0 ? Colors.green : Colors.red,
                  icon: Icons.percent,
                ),
              ];

              return _ReportGrid(items: items);
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, stack) => Center(child: Text('Error: $err')),
          ),
        ),
      ],
    );
  }
}

// ---------- Reusable Report Grid ----------
class _ReportGrid extends StatelessWidget {
  final List<ReportItem> items;

  const _ReportGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 1.2,
        ),
        itemCount: items.length,
        itemBuilder: (_, index) {
          final item = items[index];
          return ReportCard(
            title: item.title,
            value: item.value,
            color: item.color,
            icon: item.icon,
          );
        },
      ),
    );
  }
}

// ---------- Data Classes ----------
class ReportItem {
  final String title;
  final String value;
  final Color color;
  final IconData icon;

  ReportItem({
    required this.title,
    required this.value,
    required this.color,
    required this.icon,
  });
}
