import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/change_password_screen.dart';
import '../../features/dashboard/screens/dashboard_screen.dart';
import '../../features/billing/screens/billing_screen.dart';
import '../../features/products/screens/product_list_screen.dart';
import '../../features/products/screens/product_form_screen.dart';
import '../../features/promotions/screens/promotion_list_screen.dart';
import '../../features/promotions/screens/promotion_form_screen.dart';
import '../../features/coupons/screens/coupon_list_screen.dart';
import '../../features/coupons/screens/coupon_form_screen.dart';
import '../../features/banking/screens/bank_account_list_screen.dart';
import '../../features/banking/screens/bank_reconciliation_screen.dart';
import '../../features/loyalty/screens/loyalty_summary_screen.dart';
import '../../features/payments/screens/payment_gateway_screen.dart';
import '../../features/collections/screens/collections_screen.dart';
import '../../features/commission/screens/commission_screen.dart';
import '../../features/stock_groups/screens/stock_group_list_screen.dart';
import '../../features/stock_groups/screens/stock_group_detail_screen.dart';
import '../../models/promotion_model.dart';
import '../../models/coupon_model.dart';
import '../../features/customers/screens/customer_list_screen.dart';
import '../../features/customers/screens/customer_form_screen.dart';
import '../../features/customers/screens/service_reminders_screen.dart';
import '../../features/customers/screens/campaigns_screen.dart';
import '../../features/reports/screens/customer_history_screen.dart';
import '../../features/suppliers/screens/supplier_list_screen.dart';
import '../../features/suppliers/screens/supplier_form_screen.dart';
import '../../features/purchases/screens/purchase_list_screen.dart';
import '../../features/purchases/screens/purchase_form_screen.dart';
import '../../features/counter/screens/counter_open_screen.dart';
import '../../features/counter/screens/counter_close_screen.dart';
import '../../features/reports/screens/reports_screen.dart';
import '../../features/reports/screens/product_performance_screen.dart';
import '../../features/reports/screens/ai_analysis_screen.dart';
import '../../features/reports/screens/sales_dashboard_screen.dart';
import '../../features/sales_cancel/screens/sale_cancellations_list_screen.dart';
import '../../features/sales_cancel/screens/sale_cancel_form_screen.dart';
import '../../features/exchange/screens/exchange_list_screen.dart';
import '../../features/exchange/screens/exchange_form_screen.dart';
import '../../features/settings/screens/settings_screen.dart';
import '../../features/settings/screens/business_profile_screen.dart';
import '../../features/users/screens/user_list_screen.dart';
import '../../features/users/screens/user_form_screen.dart';
import '../../features/credit/screens/receive_payment_screen.dart';
import '../../features/sales_history/screens/sales_history_screen.dart';
import '../../features/returns/screens/returns_list_screen.dart';
import '../../features/returns/screens/return_form_screen.dart';
import '../../features/sales_summary/screens/sales_summary_screen.dart';
import '../../features/quotation/screens/quotation_list_screen.dart';
import '../../features/quotation/screens/quotation_form_screen.dart';
import '../../features/holds/screens/hold_bills_screen.dart'; // ✅ Added Hold Bills route
import '../../features/barcode/screens/barcode_generator_screen.dart';
import '../../features/utilities/screens/export_items_screen.dart';
import '../../features/utilities/screens/import_items_screen.dart';
import '../../features/utilities/screens/bulk_update_items_screen.dart';
import '../../features/utilities/screens/import_parties_screen.dart';
import '../../features/utilities/screens/import_tally_screen.dart';
import '../../features/utilities/screens/export_tally_screen.dart';
import '../../features/utilities/screens/accountant_access_screen.dart';
import '../../features/utilities/screens/verify_data_screen.dart';
import '../../features/utilities/screens/close_financial_year_screen.dart';
import '../../features/utilities/screens/festival_calendar_screen.dart';
import '../../features/salesmen/screens/salesman_list_screen.dart';
import '../../features/salesmen/screens/salesman_form_screen.dart';
import '../../models/salesman_model.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';

/// Lower number = more privilege. Used to decide whether a user's role
/// meets a route's minimum required role. Accountant doesn't fit this
/// linear scale (it's a narrow, cross-cutting allowlist, not "less
/// privileged than cashier") so it gets an arbitrary rank here — routes
/// gated by rank alone never intentionally admit accountant; see
/// [_accountantAllowedRoutes] for what it actually can reach.
int _roleRank(UserRole role) {
  switch (role) {
    case UserRole.admin:
      return 0;
    case UserRole.manager:
      return 1;
    case UserRole.cashier:
      return 2;
    case UserRole.accountant:
      return 3;
  }
}

bool _hasAccess(UserRole userRole, UserRole minRequiredRole) {
  return _roleRank(userRole) <= _roleRank(minRequiredRole);
}

/// Minimum role required to reach a given route. Any route not listed here
/// is open to every logged-in role (billing, counters, customers, holds,
/// quotations, credit payment, sales history/summary). Does not apply to
/// UserRole.accountant, which is checked against [_accountantAllowedRoutes]
/// instead — see the `redirect` callback below.
final Map<String, UserRole> _routeMinRole = {
  '/products': UserRole.manager,
  '/products/form': UserRole.manager,
  '/promotions': UserRole.manager,
  '/promotions/form': UserRole.manager,
  '/coupons': UserRole.manager,
  '/coupons/form': UserRole.manager,
  '/stock-groups': UserRole.manager,
  '/stock-groups/detail': UserRole.manager,
  // Manager, matching every other write-capable record-keeping route. Not in
  // _accountantAllowedRoutes below: reconciliation is arguably an accountant's
  // job, but that set is documented as a read/export-only slice and this would
  // be the first route in it that writes. Widening it is a policy call for a
  // human, not something to slip in with a feature.
  '/banking': UserRole.manager,
  '/loyalty': UserRole.manager,
  '/payment-gateways': UserRole.manager,
  '/collections': UserRole.manager,
  '/commission': UserRole.manager,
  '/banking/reconcile': UserRole.manager,
  '/suppliers': UserRole.manager,
  '/suppliers/form': UserRole.manager,
  '/purchases': UserRole.manager,
  '/purchases/form': UserRole.manager,
  '/reports': UserRole.manager,
  '/reports/product-performance': UserRole.manager,
  '/reports/ai-analysis': UserRole.manager,
  '/reports/detail': UserRole.manager,
  '/reports/sales-dashboard': UserRole.manager,
  '/settings': UserRole.manager,
  '/settings/business-profile': UserRole.manager,
  '/users': UserRole.admin,
  '/users/form': UserRole.admin,
  '/utilities/barcode-generator': UserRole.manager,
  '/utilities/export-items': UserRole.manager,
  '/utilities/import-items': UserRole.manager,
  '/utilities/bulk-update-items': UserRole.manager,
  '/utilities/import-parties': UserRole.manager,
  '/utilities/import-tally': UserRole.admin,
  '/utilities/export-tally': UserRole.admin,
  '/utilities/track-salesmen': UserRole.manager,
  '/utilities/track-salesmen/form': UserRole.manager,
  '/utilities/accountant-access': UserRole.admin,
  '/utilities/verify-data': UserRole.manager,
  '/utilities/close-financial-year': UserRole.admin,
  '/utilities/festival-calendar': UserRole.manager,
};

/// The only routes an accountant-role user may reach — a narrow, read/
/// export-oriented slice of the app (reports, sales history, ledgers,
/// item/Tally exports, data verification) rather than a point on the
/// admin/manager/cashier privilege scale. Anything not listed here bounces
/// to the dashboard, including routes with no [_routeMinRole] entry that
/// are otherwise open to every other logged-in role.
const Set<String> _accountantAllowedRoutes = {
  '/dashboard',
  '/reports',
  '/reports/product-performance',
  '/reports/ai-analysis',
  '/reports/detail',
  '/reports/sales-dashboard',
  '/sales-history',
  '/sales-summary',
  '/customers',
  '/suppliers',
  '/utilities/export-items',
  '/utilities/export-tally',
  '/utilities/verify-data',
};

/// Bridges Riverpod's [authProvider] changes into a [Listenable] so
/// go_router re-evaluates `redirect` whenever login state changes
/// (login, logout, role change), not just on navigation.
class _AuthRefreshNotifier extends ChangeNotifier {
  _AuthRefreshNotifier(Ref ref) {
    ref.listen<AuthState>(authProvider, (previous, next) {
      notifyListeners();
    });
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = _AuthRefreshNotifier(ref);

  return GoRouter(
    initialLocation: '/login',
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final authState = ref.read(authProvider);
      final user = authState.user;
      final loggedIn = user != null;
      final loggingIn = state.matchedLocation == '/login';
      final changingPassword = state.matchedLocation == '/change-password';

      // Not logged in: only the login screen is reachable.
      if (!loggedIn) {
        return loggingIn ? null : '/login';
      }

      // Logged in but must change password: force that screen first.
      if (user.mustChangePassword && !changingPassword) {
        return '/change-password';
      }

      // Already logged in: don't allow sitting on the login screen.
      if (loggingIn) {
        return '/dashboard';
      }

      // Accountant is a narrow allowlist, not a point on the rank scale —
      // checked separately from (and instead of) the rank-based check below.
      if (user.role == UserRole.accountant) {
        if (!_accountantAllowedRoutes.contains(state.matchedLocation)) {
          return '/dashboard';
        }
        return null;
      }

      // Role check: bounce unauthorized users back to the dashboard.
      final requiredRole = _routeMinRole[state.matchedLocation];
      if (requiredRole != null && !_hasAccess(user.role, requiredRole)) {
        return '/dashboard';
      }

      return null;
    },
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
      path: '/promotions',
      builder: (context, state) => const PromotionListScreen(),
    ),
    GoRoute(
      path: '/promotions/form',
      builder: (context, state) => PromotionFormScreen(
        promotion: state.extra is Promotion ? state.extra as Promotion : null,
      ),
    ),
    GoRoute(
      path: '/coupons',
      builder: (context, state) => const CouponListScreen(),
    ),
    GoRoute(
      path: '/coupons/form',
      builder: (context, state) => CouponFormScreen(
        coupon: state.extra is Coupon ? state.extra as Coupon : null,
      ),
    ),
    GoRoute(
      path: '/banking',
      builder: (context, state) => const BankAccountListScreen(),
    ),
    GoRoute(
      path: '/loyalty',
      builder: (context, state) => const LoyaltySummaryScreen(),
    ),
    GoRoute(
      path: '/payment-gateways',
      builder: (context, state) => const PaymentGatewayScreen(),
    ),
    GoRoute(
      path: '/collections',
      builder: (context, state) => const CollectionsScreen(),
    ),
    GoRoute(
      path: '/commission',
      builder: (context, state) => const CommissionScreen(),
    ),
    GoRoute(
      // `extra`, not a `:id` path param — same reason as /stock-groups/detail
      // below: _routeMinRole matches the literal location, so a parameterized
      // path would bypass the manager gate.
      path: '/banking/reconcile',
      builder: (context, state) => BankReconciliationScreen(bankAccountId: state.extra as String),
    ),
    GoRoute(
      path: '/stock-groups',
      builder: (context, state) => const StockGroupListScreen(),
    ),
    GoRoute(
      // Deliberately not a `:id` path param — _routeMinRole below matches
      // state.matchedLocation as an exact string, which for a parameterized
      // route resolves to the literal path (e.g. "/stock-groups/abc123"),
      // never the pattern — so a `:id` route would silently bypass the
      // manager gate below it. Every other detail screen in this app
      // (promotions/coupons forms, reports detail) uses `extra` for exactly
      // this reason; matching that convention here instead of being the
      // first exception.
      path: '/stock-groups/detail',
      builder: (context, state) => StockGroupDetailScreen(groupId: state.extra as String),
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
      path: '/customers/reminders',
      builder: (context, state) => const ServiceRemindersScreen(),
    ),
    GoRoute(
      path: '/customers/campaigns',
      builder: (context, state) => const CampaignsScreen(),
    ),
    GoRoute(
      path: '/customers/history',
      builder: (context, state) => CustomerHistoryScreen(
        customerId: state.uri.queryParameters['id'] ?? '',
      ),
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
    // ----- Reports Routes (Consolidated) -----
    GoRoute(
      path: '/reports',
      builder: (context, state) => ReportsScreen(
        initialTabIndex: state.extra is int ? state.extra as int : 0,
      ),
    ),
    GoRoute(
      path: '/reports/product-performance',
      builder: (context, state) => const ProductPerformanceScreen(),
    ),
    GoRoute(
      path: '/reports/ai-analysis',
      builder: (context, state) => const AIAnalysisScreen(),
    ),
    // Catch-all used by the Reports screen's "Detailed Reports" sections to
    // push a report screen built inline (e.g. `GenericReportScreen(...)`)
    // without needing a separate named GoRoute per report — `extra` carries
    // the already-built widget.
    GoRoute(
      path: '/reports/detail',
      builder: (context, state) => state.extra as Widget,
    ),
    GoRoute(
      path: '/reports/sales-dashboard',
      builder: (context, state) => const SalesDashboardScreen(),
    ),
    // ---------------------------------------
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
      path: '/settings/business-profile',
      builder: (context, state) => const BusinessProfileScreen(),
    ),
    GoRoute(
      path: '/credit/receive-payment',
      builder: (context, state) => const ReceivePaymentScreen(),
    ),
    GoRoute(
      path: '/sales-history',
      builder: (context, state) => const SalesHistoryScreen(),
    ),
    GoRoute(
      path: '/returns',
      builder: (context, state) => const ReturnsListScreen(),
    ),
    GoRoute(
      path: '/returns/form',
      builder: (context, state) => ReturnFormScreen(
        saleId: state.uri.queryParameters['saleId'],
      ),
    ),
    GoRoute(
      path: '/sales-cancellations',
      builder: (context, state) => const SaleCancellationsListScreen(),
    ),
    GoRoute(
      path: '/sales-cancellations/form',
      builder: (context, state) => SaleCancelFormScreen(
        saleId: state.uri.queryParameters['saleId'],
      ),
    ),
    GoRoute(
      path: '/exchanges',
      builder: (context, state) => const ExchangeListScreen(),
    ),
    GoRoute(
      path: '/exchanges/form',
      builder: (context, state) => ExchangeFormScreen(
        saleId: state.uri.queryParameters['saleId'],
      ),
    ),
    GoRoute(
      path: '/sales-summary',
      builder: (context, state) => const SalesSummaryScreen(),
    ),
    GoRoute(
      path: '/quotations',
      builder: (context, state) => const QuotationListScreen(),
    ),
    GoRoute(
      path: '/quotations/form',
      builder: (context, state) => const QuotationFormScreen(),
    ),
    // ✅ Hold Bills Route
    GoRoute(
      path: '/holds',
      builder: (context, state) => const HoldBillsScreen(),
    ),
    // ----- Utilities Routes -----
    GoRoute(
      path: '/utilities/barcode-generator',
      builder: (context, state) => const BarcodeGeneratorScreen(),
    ),
    GoRoute(
      path: '/utilities/export-items',
      builder: (context, state) => const ExportItemsScreen(),
    ),
    GoRoute(
      path: '/utilities/import-items',
      builder: (context, state) => const ImportItemsScreen(),
    ),
    GoRoute(
      path: '/utilities/festival-calendar',
      builder: (context, state) => const FestivalCalendarScreen(),
    ),
    GoRoute(
      path: '/utilities/bulk-update-items',
      builder: (context, state) => const BulkUpdateItemsScreen(),
    ),
    GoRoute(
      path: '/utilities/import-parties',
      builder: (context, state) => const ImportPartiesScreen(),
    ),
    GoRoute(
      path: '/utilities/import-tally',
      builder: (context, state) => const ImportTallyScreen(),
    ),
    GoRoute(
      path: '/utilities/export-tally',
      builder: (context, state) => const ExportTallyScreen(),
    ),
    GoRoute(
      path: '/utilities/track-salesmen',
      builder: (context, state) => const SalesmanListScreen(),
    ),
    GoRoute(
      path: '/utilities/track-salesmen/form',
      builder: (context, state) => SalesmanFormScreen(
        salesman: state.extra is Salesman ? state.extra as Salesman : null,
      ),
    ),
    GoRoute(
      path: '/utilities/accountant-access',
      builder: (context, state) => const AccountantAccessScreen(),
    ),
    GoRoute(
      path: '/utilities/verify-data',
      builder: (context, state) => const VerifyDataScreen(),
    ),
    GoRoute(
      path: '/utilities/close-financial-year',
      builder: (context, state) => const CloseFinancialYearScreen(),
    ),
    // ----------------------------
  ],
  );
});