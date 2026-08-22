import 'package:flutter/material.dart';

import '../../models/user_model.dart';
import 'navigation_item.dart';

const List<NavParent> appNavigation = [
  // ── HOME ──
  NavParent(
    id: 'home',
    label: 'HOME',
    icon: Icons.home,
    directRoute: '/dashboard',
    children: [
      NavChild(
        id: 'home.dashboard',
        label: 'Dashboard',
        route: '/dashboard',
        icon: Icons.dashboard,
        accountantAllowed: true,
      ),
    ],
  ),

  // ── SALES ──
  NavParent(
    id: 'sales',
    label: 'SALES',
    icon: Icons.point_of_sale,
    children: [
      NavChild(
        id: 'sales.billing',
        label: 'New Sale',
        route: '/billing',
        icon: Icons.receipt,
      ),
      NavChild(
        id: 'sales.history',
        label: 'Sales History',
        route: '/sales-history',
        icon: Icons.history,
        accountantAllowed: true,
      ),
      NavChild(
        id: 'sales.quotations',
        label: 'Quotations',
        route: '/quotations',
        icon: Icons.request_quote,
      ),
      NavChild(
        id: 'sales.holds',
        label: 'Hold Bills',
        route: '/holds',
        icon: Icons.pause_circle_outline,
      ),
      NavChild(
        id: 'sales.summary',
        label: 'Sales Summary',
        route: '/sales-summary',
        icon: Icons.summarize,
        accountantAllowed: true,
      ),
      NavChild(
        id: 'sales.cancellations',
        label: 'Sale Cancellations',
        route: '/sales-cancellations',
        icon: Icons.cancel_outlined,
      ),
    ],
  ),

  // ── PURCHASES ──
  NavParent(
    id: 'purchases',
    label: 'PURCHASES',
    icon: Icons.shopping_cart,
    children: [
      NavChild(
        id: 'purchases.list',
        label: 'Purchases',
        route: '/purchases',
        icon: Icons.receipt_long,
        minRole: UserRole.manager,
      ),
      NavChild(
        id: 'purchases.suppliers',
        label: 'Suppliers',
        route: '/suppliers',
        icon: Icons.business,
        minRole: UserRole.manager,
        accountantAllowed: true,
      ),
    ],
  ),

  // ── INVENTORY ──
  NavParent(
    id: 'inventory',
    label: 'INVENTORY',
    icon: Icons.inventory_2,
    children: [
      NavChild(
        id: 'inventory.products',
        label: 'Products',
        route: '/products',
        icon: Icons.inventory,
        minRole: UserRole.manager,
      ),
      NavChild(
        id: 'inventory.stock_groups',
        label: 'Stock Groups',
        route: '/stock-groups',
        icon: Icons.merge_type,
        minRole: UserRole.manager,
      ),
      NavChild(
        id: 'inventory.barcode_generator',
        label: 'Barcode Generator',
        route: '/utilities/barcode-generator',
        icon: Icons.qr_code,
        minRole: UserRole.manager,
      ),
      NavChild(
        id: 'inventory.import_items',
        label: 'Import Items',
        route: '/utilities/import-items',
        icon: Icons.upload_file,
        minRole: UserRole.manager,
      ),
      NavChild(
        id: 'inventory.export_items',
        label: 'Export Items',
        route: '/utilities/export-items',
        icon: Icons.download,
        minRole: UserRole.manager,
        accountantAllowed: true,
      ),
      NavChild(
        id: 'inventory.bulk_update',
        label: 'Bulk Update Items',
        route: '/utilities/bulk-update-items',
        icon: Icons.edit_note,
        minRole: UserRole.manager,
      ),
    ],
  ),

  // ── PRODUCTS & PRICING ──
  NavParent(
    id: 'products_pricing',
    label: 'PRODUCTS & PRICING',
    icon: Icons.local_offer,
    children: [
      NavChild(
        id: 'products_pricing.promotions',
        label: 'Promotions',
        route: '/promotions',
        icon: Icons.local_offer,
        minRole: UserRole.manager,
      ),
      NavChild(
        id: 'products_pricing.coupons',
        label: 'Coupons',
        route: '/coupons',
        icon: Icons.confirmation_number,
        minRole: UserRole.manager,
      ),
    ],
  ),

  // ── CUSTOMERS & PERKS ──
  NavParent(
    id: 'customers',
    label: 'CUSTOMERS & PERKS',
    icon: Icons.people,
    children: [
      NavChild(
        id: 'customers.list',
        label: 'Customers',
        route: '/customers',
        icon: Icons.people,
        accountantAllowed: true,
      ),
      NavChild(
        id: 'customers.loyalty',
        label: 'Loyalty Points',
        route: '/loyalty',
        icon: Icons.card_giftcard,
        minRole: UserRole.manager,
      ),
      NavChild(
        id: 'customers.receive_payment',
        label: 'Receive Payment',
        route: '/credit/receive-payment',
        icon: Icons.payment,
      ),
    ],
  ),

  // ── DOCUMENTS ──
  NavParent(
    id: 'documents',
    label: 'DOCUMENTS',
    icon: Icons.description,
    children: [
      NavChild(
        id: 'documents.returns',
        label: 'Sales Returns',
        route: '/returns',
        icon: Icons.assignment_return,
      ),
      NavChild(
        id: 'documents.exchanges',
        label: 'Exchanges',
        route: '/exchanges',
        icon: Icons.swap_horiz,
      ),
    ],
  ),

  // ── EXPENSES & CASH ──
  NavParent(
    id: 'expenses_cash',
    label: 'EXPENSES & CASH',
    icon: Icons.account_balance_wallet,
    children: [
      NavChild(
        id: 'expenses_cash.cash_management',
        label: 'Cash Management',
        route: '/cash-management',
        icon: Icons.account_balance_wallet,
        minRole: UserRole.manager,
      ),
      NavChild(
        id: 'expenses_cash.bank_accounts',
        label: 'Bank Accounts',
        route: '/banking',
        icon: Icons.account_balance,
        minRole: UserRole.manager,
      ),
      NavChild(
        id: 'expenses_cash.counter_open',
        label: 'Open Counter',
        route: '/counter/open',
        icon: Icons.login,
      ),
      NavChild(
        id: 'expenses_cash.counter_close',
        label: 'Close Counter',
        route: '/counter/close',
        icon: Icons.logout,
      ),
      NavChild(
        id: 'expenses_cash.collections',
        label: 'Collections',
        route: '/collections',
        icon: Icons.receipt_long,
        minRole: UserRole.manager,
      ),
      NavChild(
        id: 'expenses_cash.payment_gateways',
        label: 'Payment Gateways',
        route: '/payment-gateways',
        icon: Icons.credit_card,
        minRole: UserRole.manager,
      ),
    ],
  ),

  // ── REPORTS ──
  NavParent(
    id: 'reports',
    label: 'REPORTS',
    icon: Icons.assessment,
    children: [
      NavChild(
        id: 'reports.hub',
        label: 'Reports',
        route: '/reports',
        icon: Icons.assessment,
        minRole: UserRole.manager,
        accountantAllowed: true,
      ),
    ],
  ),

  // ── PEOPLE ──
  NavParent(
    id: 'people',
    label: 'PEOPLE',
    icon: Icons.badge,
    children: [
      NavChild(
        id: 'people.users',
        label: 'Users',
        route: '/users',
        icon: Icons.people_outline,
        minRole: UserRole.admin,
      ),
      NavChild(
        id: 'people.salesmen',
        label: 'Salesmen',
        route: '/utilities/track-salesmen',
        icon: Icons.badge_outlined,
        minRole: UserRole.manager,
      ),
      NavChild(
        id: 'people.accountant_access',
        label: 'Accountant Access',
        route: '/utilities/accountant-access',
        icon: Icons.manage_accounts,
        minRole: UserRole.admin,
      ),
      NavChild(
        id: 'people.commission',
        label: 'Commission',
        route: '/commission',
        icon: Icons.percent,
        minRole: UserRole.manager,
      ),
    ],
  ),

  // ── SETTINGS ──
  NavParent(
    id: 'settings',
    label: 'SETTINGS',
    icon: Icons.settings,
    children: [
      NavChild(
        id: 'settings.hub',
        label: 'Settings',
        route: '/settings',
        icon: Icons.settings,
        minRole: UserRole.manager,
      ),
      NavChild(
        id: 'settings.close_fy',
        label: 'Close Financial Year',
        route: '/utilities/close-financial-year',
        icon: Icons.event_busy,
        minRole: UserRole.admin,
      ),
      NavChild(
        id: 'settings.import_tally',
        label: 'Import From Tally',
        route: '/utilities/import-tally',
        icon: Icons.file_download,
        minRole: UserRole.admin,
      ),
      NavChild(
        id: 'settings.export_tally',
        label: 'Export To Tally',
        route: '/utilities/export-tally',
        icon: Icons.file_upload,
        minRole: UserRole.admin,
        accountantAllowed: true,
      ),
      NavChild(
        id: 'settings.import_parties',
        label: 'Import Parties',
        route: '/utilities/import-parties',
        icon: Icons.group_add,
        minRole: UserRole.manager,
      ),
      NavChild(
        id: 'settings.festival_calendar',
        label: 'Festival Calendar',
        route: '/utilities/festival-calendar',
        icon: Icons.celebration_outlined,
        minRole: UserRole.manager,
      ),
      NavChild(
        id: 'settings.verify_data',
        label: 'Verify Data',
        route: '/utilities/verify-data',
        icon: Icons.fact_check,
        minRole: UserRole.manager,
        accountantAllowed: true,
      ),
    ],
  ),
];

NavParent? findParentForRoute(String route) {
  for (final parent in appNavigation) {
    if (parent.ownsRoute(route)) return parent;
  }
  return null;
}
