import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../models/customer_model.dart';
import '../../../models/customer_ledger_model.dart';
import '../../../models/sale_model.dart';
import '../../../providers/customer_provider.dart';
import '../../../repositories/customer_ledger_repository.dart';
import '../../../repositories/sale_repository.dart';
import '../../../services/advanced_report_service.dart';
import '../../customers/screens/customer_form_screen.dart';

final _dateFormat = DateFormat('dd MMM yyyy, hh:mm a');

/// Customer detail screen — purchase history + credit ledger. Previously a
/// "Coming Soon" placeholder that nothing even navigated to; customer_list
/// tapped straight into the edit form instead.
class CustomerHistoryScreen extends ConsumerStatefulWidget {
  final String customerId;

  const CustomerHistoryScreen({super.key, required this.customerId});

  @override
  ConsumerState<CustomerHistoryScreen> createState() => _CustomerHistoryScreenState();
}

class _CustomerHistoryScreenState extends ConsumerState<CustomerHistoryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late Future<Customer?> _customerFuture;
  late Future<List<Sale>> _salesFuture;
  late Future<List<CustomerLedger>> _ledgerFuture;
  late Future<Map<String, dynamic>?> _favoriteProductFuture;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  void _load() {
    _customerFuture = ref.read(customerNotifierProvider.notifier).getById(widget.customerId);
    _salesFuture = SaleRepository().getByCustomer(widget.customerId);
    _ledgerFuture = CustomerLedgerRepository().getEntries(widget.customerId);
    _favoriteProductFuture = AdvancedReportService().getCustomerFavoriteProduct(widget.customerId);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _editCustomer(Customer customer) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CustomerFormScreen(customer: customer)),
    );
    setState(_load);
  }

  Future<void> _goToReceivePayment() async {
    await context.push('/credit/receive-payment');
    setState(_load);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Customer?>(
      future: _customerFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const AppScaffold(
            title: 'Customer',
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final customer = snapshot.data;
        if (customer == null) {
          return const AppScaffold(
            title: 'Customer',
            body: Center(child: Text('Customer not found')),
          );
        }

        return AppScaffold(
          title: customer.name,
          actions: [
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: 'Edit customer',
              onPressed: () => _editCustomer(customer),
            ),
          ],
          body: Column(
            children: [
              _buildHeader(customer),
              TabBar(
                controller: _tabController,
                labelColor: Theme.of(context).colorScheme.primary,
                tabs: const [
                  Tab(text: 'Credit Ledger'),
                  Tab(text: 'Purchase History'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildLedgerTab(customer),
                    _buildPurchaseHistoryTab(),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(Customer customer) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.phone, size: 16, color: Colors.grey),
              const SizedBox(width: 6),
              Text(customer.phone),
              if (customer.address != null && customer.address!.isNotEmpty) ...[
                const SizedBox(width: 16),
                const Icon(Icons.location_on, size: 16, color: Colors.grey),
                const SizedBox(width: 6),
                Expanded(child: Text(customer.address!, overflow: TextOverflow.ellipsis)),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _statTile('Total Spent', '₹${customer.totalSpent.toStringAsFixed(2)}', Colors.green),
              _statTile('Loyalty Points', '${customer.loyaltyPoints}', Colors.purple),
              // A negative outstanding_balance means the customer has paid
              // more than they owe — that's an advance held for future
              // purchases, not a (nonsensical) negative due. Label and
              // color it as what it actually is instead of showing
              // "Outstanding Due: ₹-400.00".
              if (customer.outstandingBalance < 0)
                _statTile(
                  'Advance Balance',
                  '₹${(-customer.outstandingBalance).toStringAsFixed(2)}',
                  Colors.blue,
                )
              else
                _statTile(
                  'Outstanding Due',
                  '₹${customer.outstandingBalance.toStringAsFixed(2)}',
                  customer.outstandingBalance > 0 ? Colors.red : Colors.grey,
                ),
            ],
          ),
          const SizedBox(height: 12),
          FutureBuilder<Map<String, dynamic>?>(
            future: _favoriteProductFuture,
            builder: (context, snapshot) {
              final favorite = snapshot.data;
              if (snapshot.connectionState != ConnectionState.done || favorite == null) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    const Icon(Icons.star, size: 16, color: Colors.amber),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Favorite: ${favorite['name']} '
                        '(${(favorite['totalQuantity'] as num).toStringAsFixed(0)} units across '
                        '${favorite['timesPurchased']} bills)',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _goToReceivePayment,
              icon: const Icon(Icons.payments_outlined),
              label: Text(customer.outstandingBalance > 0 ? 'Receive Payment' : 'Receive Payment / Advance'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statTile(String label, String value, Color color) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _buildLedgerTab(Customer customer) {
    return FutureBuilder<List<CustomerLedger>>(
      future: _ledgerFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final entries = snapshot.data ?? [];
        if (entries.isEmpty) {
          return const Center(child: Text('No credit transactions yet'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(8),
          itemCount: entries.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, index) {
            // Newest first for display, even though they're stored oldest-first.
            final entry = entries[entries.length - 1 - index];
            final isDebit = entry.amount > 0;
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: (isDebit ? Colors.red : Colors.green).withValues(alpha: 0.15),
                child: Icon(
                  isDebit ? Icons.arrow_upward : Icons.arrow_downward,
                  color: isDebit ? Colors.red : Colors.green,
                  size: 18,
                ),
              ),
              title: Text(_ledgerReferenceLabel(entry.referenceType)),
              subtitle: Text(
                '${_dateFormat.format(DateTime.fromMillisecondsSinceEpoch(entry.createdAt * 1000))}'
                '${entry.note != null ? '\n${entry.note}' : ''}',
              ),
              isThreeLine: entry.note != null,
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${isDebit ? '+' : '-'}₹${entry.amount.abs().toStringAsFixed(2)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isDebit ? Colors.red : Colors.green,
                    ),
                  ),
                  Text(
                    'Bal: ₹${entry.balance.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _ledgerReferenceLabel(String referenceType) {
    switch (referenceType) {
      case 'sale':
        return 'Credit Sale';
      case 'payment':
        return 'Payment Received';
      case 'advance':
        return 'Advance Received';
      case 'opening_balance':
        return 'Opening Balance';
      default:
        return referenceType;
    }
  }

  Widget _buildPurchaseHistoryTab() {
    return FutureBuilder<List<Sale>>(
      future: _salesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final sales = snapshot.data ?? [];
        if (sales.isEmpty) {
          return const Center(child: Text('No purchases yet'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(8),
          itemCount: sales.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, index) {
            final sale = sales[index];
            return ListTile(
              leading: const CircleAvatar(child: Icon(Icons.receipt_long, size: 18)),
              title: Text('Invoice ${sale.invoiceLabel}'),
              subtitle: Text(_dateFormat.format(DateTime.fromMillisecondsSinceEpoch(sale.createdAt * 1000))),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('₹${sale.netAmount.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  if (sale.isCreditSale)
                    const Text('Credit', style: TextStyle(fontSize: 11, color: Colors.orange)),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
