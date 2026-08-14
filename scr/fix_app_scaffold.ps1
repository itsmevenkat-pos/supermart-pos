# fix_app_scaffold.ps1 – Fixes AppScaffold and router issues
$base = "lib"

$files = @{

    # ---------- FIXED APP SCAFFOLD (with FAB) ----------
    "core/widgets/app_scaffold.dart" = @'
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AppScaffold extends StatelessWidget {
  final Widget body;
  final String title;
  final bool showBackButton;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;

  const AppScaffold({
    super.key,
    required this.body,
    required this.title,
    this.showBackButton = true,
    this.actions,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: showBackButton
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/dashboard');
                  }
                },
              )
            : null,
        actions: actions,
      ),
      drawer: _buildDrawer(context),
      body: body,
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: floatingActionButtonLocation,
    );
  }

  Widget _buildDrawer(BuildContext context) {
    return Drawer(
      child: ListView(
        children: [
          const DrawerHeader(
            child: Text('SuperMart POS', style: TextStyle(fontSize: 24)),
          ),
          _drawerTile(context, 'Dashboard', Icons.dashboard, '/dashboard'),
          _drawerTile(context, 'Billing', Icons.point_of_sale, '/billing'),
          _drawerTile(context, 'Products', Icons.inventory, '/products'),
          _drawerTile(context, 'Customers', Icons.people, '/customers'),
          _drawerTile(context, 'Suppliers', Icons.business, '/suppliers'),
          _drawerTile(context, 'Purchases', Icons.receipt_long, '/purchases'),
          _drawerTile(context, 'Sales History', Icons.history, '/sales-history'),
          _drawerTile(context, 'Reports', Icons.assessment, '/reports/sales'),
          _drawerTile(context, 'Users', Icons.people_outline, '/users'),
          _drawerTile(context, 'Settings', Icons.settings, '/settings'),
        ],
      ),
    );
  }

  Widget _drawerTile(BuildContext context, String title, IconData icon, String route) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      onTap: () {
        Navigator.pop(context);
        context.go(route);
      },
    );
  }
}
'@

    # ---------- FIXED ROUTER ----------
    "core/routes/app_router.dart" = @'
import 'package:go_router/go_router.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/change_password_screen.dart';
import '../../features/dashboard/screens/dashboard_screen.dart';
import '../../features/billing/screens/billing_screen.dart';
import '../../features/products/screens/product_list_screen.dart';
import '../../features/products/screens/product_form_screen.dart';
import '../../features/customers/screens/customer_list_screen.dart';
import '../../features/customers/screens/customer_form_screen.dart';
import '../../features/customers/screens/customer_history_screen.dart';
import '../../features/suppliers/screens/supplier_list_screen.dart';
import '../../features/suppliers/screens/supplier_form_screen.dart';
import '../../features/purchases/screens/purchase_list_screen.dart';
import '../../features/purchases/screens/purchase_form_screen.dart';
import '../../features/counter/screens/counter_open_screen.dart';
import '../../features/counter/screens/counter_close_screen.dart';
import '../../features/reports/screens/sales_report_screen.dart';
import '../../features/reports/screens/customer_history_screen.dart';
import '../../features/reports/screens/product_performance_screen.dart';
import '../../features/reports/screens/ai_analysis_screen.dart';
import '../../features/settings/screens/settings_screen.dart';
import '../../features/users/screens/user_list_screen.dart';
import '../../features/users/screens/user_form_screen.dart';
import '../../features/credit/screens/receive_payment_screen.dart';
import '../../features/sales_history/screens/sales_history_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/login',
  routes: [
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/change-password',
      builder: (context, state) => const ChangePasswordScreen(),
    ),
    GoRoute(
      path: '/dashboard',
      builder: (context, state) => const DashboardScreen(),
    ),
    GoRoute(
      path: '/billing',
      builder: (context, state) => const BillingScreen(),
    ),
    GoRoute(
      path: '/products',
      builder: (context, state) => const ProductListScreen(),
    ),
    GoRoute(
      path: '/products/form',
      builder: (context, state) => const ProductFormScreen(),
    ),
    GoRoute(
      path: '/customers',
      builder: (context, state) => const CustomerListScreen(),
    ),
    GoRoute(
      path: '/customers/form',
      builder: (context, state) => const CustomerFormScreen(),
    ),
    GoRoute(
      path: '/customers/history',
      builder: (context, state) => const CustomerHistoryScreen(),
    ),
    GoRoute(
      path: '/suppliers',
      builder: (context, state) => const SupplierListScreen(),
    ),
    GoRoute(
      path: '/suppliers/form',
      builder: (context, state) => const SupplierFormScreen(),
    ),
    GoRoute(
      path: '/purchases',
      builder: (context, state) => const PurchaseListScreen(),
    ),
    GoRoute(
      path: '/purchases/form',
      builder: (context, state) => const PurchaseFormScreen(),
    ),
    GoRoute(
      path: '/counter/open',
      builder: (context, state) => const CounterOpenScreen(),
    ),
    GoRoute(
      path: '/counter/close',
      builder: (context, state) => const CounterCloseScreen(),
    ),
    GoRoute(
      path: '/reports/sales',
      builder: (context, state) => const SalesReportScreen(),
    ),
    GoRoute(
      path: '/reports/product-performance',
      builder: (context, state) => const ProductPerformanceScreen(),
    ),
    GoRoute(
      path: '/reports/ai-analysis',
      builder: (context, state) => const AIAnalysisScreen(),
    ),
    GoRoute(
      path: '/users',
      builder: (context, state) => const UserListScreen(),
    ),
    GoRoute(
      path: '/users/form',
      builder: (context, state) => const UserFormScreen(),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
    GoRoute(
      path: '/credit/receive-payment',
      builder: (context, state) => const ReceivePaymentScreen(),
    ),
    GoRoute(
      path: '/sales-history',
      builder: (context, state) => const SalesHistoryScreen(),
    ),
  ],
);
'@

    # ---------- FIXED PRODUCT LIST ----------
    "features/products/screens/product_list_screen.dart" = @'
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../providers/product_provider.dart';
import '../../../models/product_model.dart';
import 'product_form_screen.dart';

class ProductListScreen extends ConsumerStatefulWidget {
  const ProductListScreen({super.key});

  @override
  ConsumerState<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends ConsumerState<ProductListScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productNotifierProvider);

    return AppScaffold(
      title: 'Products',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () => ref.invalidate(productNotifierProvider),
        ),
      ],
      floatingActionButton: FloatingActionButton(
        onPressed: () => _navigateToForm(),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Search by name or barcode',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                if (value.isNotEmpty) {
                  ref.read(productNotifierProvider.notifier).search(value);
                } else {
                  ref.invalidate(productNotifierProvider);
                }
              },
            ),
          ),
          Expanded(
            child: productsAsync.when(
              data: (products) {
                if (products.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inventory, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text('No products found'),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: products.length,
                  itemBuilder: (context, index) {
                    final product = products[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: product.stockQuantity > 0 ? Colors.green.shade100 : Colors.red.shade100,
                          child: Text(
                            product.stockQuantity.toString(),
                            style: TextStyle(
                              color: product.stockQuantity > 0 ? Colors.green.shade800 : Colors.red.shade800,
                            ),
                          ),
                        ),
                        title: Text(product.name),
                        subtitle: Text('Barcode: ${product.barcode} | MRP: ₹${product.mrp.toStringAsFixed(2)}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('₹${product.retailPrice.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.edit, size: 20),
                              onPressed: () => _navigateToForm(product),
                            ),
                          ],
                        ),
                        onTap: () => _navigateToForm(product),
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => Center(child: Text('Error: $err', style: const TextStyle(color: Colors.red))),
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToForm([Product? product]) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProductFormScreen(initialProduct: product),
      ),
    ).then((_) => ref.invalidate(productNotifierProvider));
  }
}
'@

    # ---------- FIXED CUSTOMER LIST ----------
    "features/customers/screens/customer_list_screen.dart" = @'
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../providers/customer_provider.dart';
import '../../../models/customer_model.dart';
import 'customer_form_screen.dart';

class CustomerListScreen extends ConsumerStatefulWidget {
  const CustomerListScreen({super.key});

  @override
  ConsumerState<CustomerListScreen> createState() => _CustomerListScreenState();
}

class _CustomerListScreenState extends ConsumerState<CustomerListScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final customersAsync = ref.watch(customerNotifierProvider);

    return AppScaffold(
      title: 'Customers',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () => ref.invalidate(customerNotifierProvider),
        ),
      ],
      floatingActionButton: FloatingActionButton(
        onPressed: () => _navigateToForm(),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(hintText: 'Search by name or phone', prefixIcon: Icon(Icons.search), border: OutlineInputBorder()),
              onChanged: (value) {
                if (value.isNotEmpty) {
                  ref.read(customerNotifierProvider.notifier).search(value);
                } else {
                  ref.invalidate(customerNotifierProvider);
                }
              },
            ),
          ),
          Expanded(
            child: customersAsync.when(
              data: (customers) {
                if (customers.isEmpty) return const Center(child: Text('No customers'));
                return ListView.builder(
                  itemCount: customers.length,
                  itemBuilder: (_, index) {
                    final c = customers[index];
                    return ListTile(
                      title: Text(c.name),
                      subtitle: Text(c.phone),
                      trailing: Text('₹${c.totalSpent.toStringAsFixed(0)}'),
                      onTap: () => _navigateToForm(c),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => Center(child: Text('Error: $err')),
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToForm([Customer? customer]) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CustomerFormScreen(customer: customer),
      ),
    ).then((_) => ref.invalidate(customerNotifierProvider));
  }
}
'@

    # ---------- FIXED SUPPLIER LIST ----------
    "features/suppliers/screens/supplier_list_screen.dart" = @'
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../providers/supplier_provider.dart';
import '../../../models/supplier_model.dart';
import 'supplier_form_screen.dart';

class SupplierListScreen extends ConsumerStatefulWidget {
  const SupplierListScreen({super.key});

  @override
  ConsumerState<SupplierListScreen> createState() => _SupplierListScreenState();
}

class _SupplierListScreenState extends ConsumerState<SupplierListScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final suppliersAsync = ref.watch(supplierNotifierProvider);

    return AppScaffold(
      title: 'Suppliers',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () => ref.invalidate(supplierNotifierProvider),
        ),
      ],
      floatingActionButton: FloatingActionButton(
        onPressed: () => _navigateToForm(),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(hintText: 'Search by name or phone', prefixIcon: Icon(Icons.search), border: OutlineInputBorder()),
              onChanged: (value) {
                if (value.isNotEmpty) {
                  ref.read(supplierNotifierProvider.notifier).search(value);
                } else {
                  ref.invalidate(supplierNotifierProvider);
                }
              },
            ),
          ),
          Expanded(
            child: suppliersAsync.when(
              data: (suppliers) {
                if (suppliers.isEmpty) return const Center(child: Text('No suppliers'));
                return ListView.builder(
                  itemCount: suppliers.length,
                  itemBuilder: (_, index) {
                    final s = suppliers[index];
                    return ListTile(
                      title: Text(s.name),
                      subtitle: Text(s.phone ?? ''),
                      trailing: Text('₹${s.openingBalance.toStringAsFixed(0)}'),
                      onTap: () => _navigateToForm(s),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => Center(child: Text('Error: $err')),
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToForm([Supplier? supplier]) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SupplierFormScreen(supplier: supplier),
      ),
    ).then((_) => ref.invalidate(supplierNotifierProvider));
  }
}
'@

    # ---------- FIXED PURCHASE LIST ----------
    "features/purchases/screens/purchase_list_screen.dart" = @'
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../providers/purchase_provider.dart';
import 'purchase_form_screen.dart';

class PurchaseListScreen extends ConsumerStatefulWidget {
  const PurchaseListScreen({super.key});

  @override
  ConsumerState<PurchaseListScreen> createState() => _PurchaseListScreenState();
}

class _PurchaseListScreenState extends ConsumerState<PurchaseListScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final purchasesAsync = ref.watch(purchaseNotifierProvider);

    return AppScaffold(
      title: 'Purchases',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () => ref.read(purchaseNotifierProvider.notifier).refresh(),
        ),
      ],
      floatingActionButton: FloatingActionButton(
        onPressed: () => _navigateToForm(),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(hintText: 'Search by GRN or supplier', prefixIcon: Icon(Icons.search), border: OutlineInputBorder()),
              onChanged: (value) {
                setState(() {});
              },
            ),
          ),
          Expanded(
            child: purchasesAsync.when(
              data: (purchases) {
                final filtered = _searchController.text.isEmpty
                    ? purchases
                    : purchases.where((p) => p.grnNo.contains(_searchController.text) || (p.supplierName ?? '').contains(_searchController.text)).toList();
                if (filtered.isEmpty) return const Center(child: Text('No purchases'));
                return ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (_, index) {
                    final p = filtered[index];
                    return ListTile(
                      title: Text('GRN: ${p.grnNo}'),
                      subtitle: Text('₹${p.netAmount.toStringAsFixed(2)} • ${p.supplierName ?? ''}'),
                      trailing: Text(p.received ? 'Received' : 'Pending'),
                      onTap: () => _navigateToForm(p),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => Center(child: Text('Error: $err')),
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToForm([Purchase? purchase]) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PurchaseFormScreen(existingPurchase: purchase),
      ),
    ).then((_) => ref.read(purchaseNotifierProvider.notifier).refresh());
  }
}
'@

    # ---------- FIXED USER LIST ----------
    "features/users/screens/user_list_screen.dart" = @'
import 'package:flutter/material.dart';
import '../../../core/widgets/app_scaffold.dart';

class UserListScreen extends StatelessWidget {
  const UserListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Users',
      body: const Center(child: Text('User List – Coming Soon')),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        child: const Icon(Icons.add),
      ),
    );
  }
}
'@

    # ---------- CUSTOMER HISTORY (Reports) ----------
    "features/reports/screens/customer_history_screen.dart" = @'
import 'package:flutter/material.dart';
import '../../../core/widgets/app_scaffold.dart';

class CustomerHistoryScreen extends StatelessWidget {
  const CustomerHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Customer History',
      body: const Center(child: Text('Customer History – Coming Soon')),
    );
  }
}
'@

    # ---------- ENSURE CUSTOMER HISTORY EXISTS (in customers folder) ----------
    "features/customers/screens/customer_history_screen.dart" = @'
import 'package:flutter/material.dart';
import '../../../core/widgets/app_scaffold.dart';

class CustomerHistoryScreen extends StatelessWidget {
  const CustomerHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Customer History',
      body: const Center(child: Text('Customer History – Coming Soon')),
    );
  }
}
'@
}

# Write all files
foreach ($key in $files.Keys) {
    $fullPath = Join-Path $base $key
    $dir = Split-Path $fullPath
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    Set-Content -Path $fullPath -Value $files[$key] -Force
    Write-Host "Fixed: $key" -ForegroundColor Green
}

Write-Host "`n✅ All issues fixed!" -ForegroundColor Cyan
Write-Host "`nNow run:" -ForegroundColor Yellow
Write-Host "flutter clean" -ForegroundColor White
Write-Host "flutter pub get" -ForegroundColor White
Write-Host "flutter pub run build_runner build --delete-conflicting-outputs" -ForegroundColor White
Write-Host "flutter run -d windows" -ForegroundColor White