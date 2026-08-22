import 'package:flutter_test/flutter_test.dart';
import 'package:supermart_pos/core/navigation/app_navigation.dart';
import 'package:supermart_pos/models/user_model.dart';

void main() {
  group('Navigation model — structure', () {
    test('has exactly 11 top-level parents', () {
      expect(appNavigation.length, 11);
    });

    test('parent IDs are unique', () {
      final ids = appNavigation.map((p) => p.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('child IDs are globally unique', () {
      final ids = <String>[];
      for (final parent in appNavigation) {
        for (final child in parent.children) {
          ids.add(child.id);
        }
      }
      expect(ids.toSet().length, ids.length);
    });

    test('parents are in the correct order', () {
      final parentIds = appNavigation.map((p) => p.id).toList();
      expect(parentIds, [
        'home',
        'sales',
        'purchases',
        'inventory',
        'products_pricing',
        'customers',
        'documents',
        'expenses_cash',
        'reports',
        'people',
        'settings',
      ]);
    });

    test('every child has a non-empty route', () {
      for (final parent in appNavigation) {
        for (final child in parent.children) {
          expect(child.route, isNotEmpty, reason: '${child.id} has empty route');
          expect(child.route.startsWith('/'), isTrue, reason: '${child.id} route must start with /');
        }
      }
    });

    test('every child has a non-empty label', () {
      for (final parent in appNavigation) {
        for (final child in parent.children) {
          expect(child.label, isNotEmpty, reason: '${child.id} has empty label');
        }
      }
    });

    test('every parent has at least one child', () {
      for (final parent in appNavigation) {
        expect(parent.children, isNotEmpty, reason: '${parent.id} has no children');
      }
    });
  });

  group('Navigation model — sidebar items (Type A)', () {
    test('40 total sidebar children mapped across all parents', () {
      int count = 0;
      for (final parent in appNavigation) {
        count += parent.children.length;
      }
      expect(count, 40);
    });

    test('HOME has 1 child — Dashboard', () {
      final home = appNavigation.firstWhere((p) => p.id == 'home');
      expect(home.children.length, 1);
      expect(home.children.first.route, '/dashboard');
    });

    test('SALES has 6 children', () {
      final sales = appNavigation.firstWhere((p) => p.id == 'sales');
      expect(sales.children.length, 6);
      final routes = sales.children.map((c) => c.route).toSet();
      expect(routes, containsAll([
        '/billing', '/sales-history', '/quotations', '/holds',
        '/sales-summary', '/sales-cancellations',
      ]));
    });

    test('PURCHASES has 2 children', () {
      final purchases = appNavigation.firstWhere((p) => p.id == 'purchases');
      expect(purchases.children.length, 2);
      final routes = purchases.children.map((c) => c.route).toSet();
      expect(routes, containsAll(['/purchases', '/suppliers']));
    });

    test('INVENTORY has 6 children including migrated utilities', () {
      final inv = appNavigation.firstWhere((p) => p.id == 'inventory');
      expect(inv.children.length, 6);
      final routes = inv.children.map((c) => c.route).toSet();
      expect(routes, containsAll([
        '/products', '/stock-groups',
        '/utilities/barcode-generator', '/utilities/import-items',
        '/utilities/export-items', '/utilities/bulk-update-items',
      ]));
    });

    test('PRODUCTS & PRICING has 2 children', () {
      final pp = appNavigation.firstWhere((p) => p.id == 'products_pricing');
      expect(pp.children.length, 2);
      final routes = pp.children.map((c) => c.route).toSet();
      expect(routes, containsAll(['/promotions', '/coupons']));
    });

    test('CUSTOMERS & PERKS has 3 children', () {
      final cust = appNavigation.firstWhere((p) => p.id == 'customers');
      expect(cust.children.length, 3);
      final routes = cust.children.map((c) => c.route).toSet();
      expect(routes, containsAll(['/customers', '/loyalty', '/credit/receive-payment']));
    });

    test('DOCUMENTS has 2 children', () {
      final docs = appNavigation.firstWhere((p) => p.id == 'documents');
      expect(docs.children.length, 2);
      final routes = docs.children.map((c) => c.route).toSet();
      expect(routes, containsAll(['/returns', '/exchanges']));
    });

    test('EXPENSES & CASH has 6 children', () {
      final exp = appNavigation.firstWhere((p) => p.id == 'expenses_cash');
      expect(exp.children.length, 6);
      final routes = exp.children.map((c) => c.route).toSet();
      expect(routes, containsAll([
        '/cash-management', '/banking', '/counter/open',
        '/counter/close', '/collections', '/payment-gateways',
      ]));
    });

    test('REPORTS has 1 child — Reports hub', () {
      final reports = appNavigation.firstWhere((p) => p.id == 'reports');
      expect(reports.children.length, 1);
      expect(reports.children.first.route, '/reports');
    });

    test('PEOPLE has 4 children including migrated utilities', () {
      final people = appNavigation.firstWhere((p) => p.id == 'people');
      expect(people.children.length, 4);
      final routes = people.children.map((c) => c.route).toSet();
      expect(routes, containsAll([
        '/users', '/utilities/track-salesmen',
        '/utilities/accountant-access', '/commission',
      ]));
    });

    test('SETTINGS has 7 children including migrated utilities', () {
      final settings = appNavigation.firstWhere((p) => p.id == 'settings');
      expect(settings.children.length, 7);
      final routes = settings.children.map((c) => c.route).toSet();
      expect(routes, containsAll([
        '/settings', '/utilities/close-financial-year',
        '/utilities/import-tally', '/utilities/export-tally',
        '/utilities/import-parties', '/utilities/festival-calendar',
        '/utilities/verify-data',
      ]));
    });
  });

  group('Navigation model — utility migration', () {
    final allRoutes = <String>[];

    setUpAll(() {
      for (final parent in appNavigation) {
        for (final child in parent.children) {
          allRoutes.add(child.route);
        }
      }
    });

    test('all 13 utility routes are present in the new navigation', () {
      final utilityRoutes = [
        '/utilities/import-items',
        '/utilities/barcode-generator',
        '/utilities/export-items',
        '/utilities/bulk-update-items',
        '/utilities/import-tally',
        '/utilities/export-tally',
        '/utilities/import-parties',
        '/utilities/track-salesmen',
        '/utilities/accountant-access',
        '/utilities/verify-data',
        '/utilities/close-financial-year',
        '/utilities/festival-calendar',
        '/settings/business-profile',
      ];
      for (final route in utilityRoutes) {
        final found = allRoutes.contains(route) ||
            appNavigation.any((p) => p.children.any((c) =>
                c.route == route || route.startsWith('${c.route}/')));
        expect(found, isTrue, reason: 'Utility route $route not found in navigation');
      }
    });

    test('no Utilities parent exists', () {
      expect(appNavigation.any((p) => p.id == 'utilities'), isFalse);
      expect(appNavigation.any((p) => p.label.toLowerCase().contains('utilities')), isFalse);
    });
  });

  group('Navigation model — permissions', () {
    test('cashier sees HOME, SALES, CUSTOMERS, DOCUMENTS, EXPENSES & CASH', () {
      const role = UserRole.cashier;
      final visible = appNavigation.where((p) => p.isVisibleTo(role)).map((p) => p.id).toList();
      expect(visible, containsAll(['home', 'sales', 'customers', 'documents', 'expenses_cash']));
      expect(visible, isNot(contains('purchases')));
      expect(visible, isNot(contains('inventory')));
      expect(visible, isNot(contains('products_pricing')));
      expect(visible, isNot(contains('reports')));
      expect(visible, isNot(contains('people')));
      expect(visible, isNot(contains('settings')));
    });

    test('cashier SALES children: all 6 items', () {
      final sales = appNavigation.firstWhere((p) => p.id == 'sales');
      final visible = sales.visibleChildren(UserRole.cashier);
      expect(visible.length, 6);
    });

    test('cashier CUSTOMERS children: Customers and Receive Payment only', () {
      final cust = appNavigation.firstWhere((p) => p.id == 'customers');
      final visible = cust.visibleChildren(UserRole.cashier);
      final routes = visible.map((c) => c.route).toSet();
      expect(routes, containsAll(['/customers', '/credit/receive-payment']));
      expect(routes, isNot(contains('/loyalty')));
    });

    test('cashier EXPENSES & CASH children: Counter Open and Close only', () {
      final exp = appNavigation.firstWhere((p) => p.id == 'expenses_cash');
      final visible = exp.visibleChildren(UserRole.cashier);
      final routes = visible.map((c) => c.route).toSet();
      expect(routes, containsAll(['/counter/open', '/counter/close']));
      expect(visible.length, 2);
    });

    test('manager sees 10-11 parents', () {
      final visible = appNavigation.where((p) => p.isVisibleTo(UserRole.manager)).toList();
      expect(visible.length, greaterThanOrEqualTo(10));
    });

    test('manager PEOPLE children: Salesmen and Commission only (no Users, no Accountant Access)', () {
      final people = appNavigation.firstWhere((p) => p.id == 'people');
      final visible = people.visibleChildren(UserRole.manager);
      final routes = visible.map((c) => c.route).toSet();
      expect(routes, contains('/utilities/track-salesmen'));
      expect(routes, contains('/commission'));
      expect(routes, isNot(contains('/users')));
      expect(routes, isNot(contains('/utilities/accountant-access')));
    });

    test('admin sees all 11 parents', () {
      final visible = appNavigation.where((p) => p.isVisibleTo(UserRole.admin)).toList();
      expect(visible.length, 11);
    });

    test('admin sees all 4 PEOPLE children', () {
      final people = appNavigation.firstWhere((p) => p.id == 'people');
      final visible = people.visibleChildren(UserRole.admin);
      expect(visible.length, 4);
    });

    test('accountant sees limited parents', () {
      final visible = appNavigation.where((p) => p.isVisibleTo(UserRole.accountant)).map((p) => p.id).toList();
      expect(visible, containsAll(['home', 'sales', 'purchases', 'inventory', 'customers', 'reports', 'settings']));
      expect(visible, isNot(contains('products_pricing')));
      expect(visible, isNot(contains('documents')));
      expect(visible, isNot(contains('expenses_cash')));
      expect(visible, isNot(contains('people')));
    });

    test('accountant SALES children: History and Summary only', () {
      final sales = appNavigation.firstWhere((p) => p.id == 'sales');
      final visible = sales.visibleChildren(UserRole.accountant);
      final routes = visible.map((c) => c.route).toSet();
      expect(routes, containsAll(['/sales-history', '/sales-summary']));
      expect(visible.length, 2);
    });

    test('accountant INVENTORY children: Export Items only', () {
      final inv = appNavigation.firstWhere((p) => p.id == 'inventory');
      final visible = inv.visibleChildren(UserRole.accountant);
      expect(visible.length, 1);
      expect(visible.first.route, '/utilities/export-items');
    });

    test('accountant SETTINGS children: Export To Tally and Verify Data only', () {
      final settings = appNavigation.firstWhere((p) => p.id == 'settings');
      final visible = settings.visibleChildren(UserRole.accountant);
      final routes = visible.map((c) => c.route).toSet();
      expect(routes, containsAll(['/utilities/export-tally', '/utilities/verify-data']));
      expect(visible.length, 2);
    });
  });

  group('Navigation model — active state detection', () {
    test('findParentForRoute returns correct parent for direct routes', () {
      expect(findParentForRoute('/dashboard')?.id, 'home');
      expect(findParentForRoute('/billing')?.id, 'sales');
      expect(findParentForRoute('/products')?.id, 'inventory');
      expect(findParentForRoute('/promotions')?.id, 'products_pricing');
      expect(findParentForRoute('/customers')?.id, 'customers');
      expect(findParentForRoute('/returns')?.id, 'documents');
      expect(findParentForRoute('/cash-management')?.id, 'expenses_cash');
      expect(findParentForRoute('/reports')?.id, 'reports');
      expect(findParentForRoute('/users')?.id, 'people');
      expect(findParentForRoute('/settings')?.id, 'settings');
    });

    test('findParentForRoute detects sub-routes via prefix matching', () {
      expect(findParentForRoute('/products/form')?.id, 'inventory');
      expect(findParentForRoute('/promotions/form')?.id, 'products_pricing');
      expect(findParentForRoute('/customers/form')?.id, 'customers');
      expect(findParentForRoute('/customers/history')?.id, 'customers');
      expect(findParentForRoute('/customers/reminders')?.id, 'customers');
      expect(findParentForRoute('/returns/form')?.id, 'documents');
      expect(findParentForRoute('/exchanges/form')?.id, 'documents');
      expect(findParentForRoute('/banking/reconcile')?.id, 'expenses_cash');
      expect(findParentForRoute('/settings/business-profile')?.id, 'settings');
      expect(findParentForRoute('/sales-cancellations/form')?.id, 'sales');
      expect(findParentForRoute('/quotations/form')?.id, 'sales');
      expect(findParentForRoute('/utilities/track-salesmen/form')?.id, 'people');
    });

    test('findParentForRoute returns null for auth routes', () {
      expect(findParentForRoute('/login'), isNull);
      expect(findParentForRoute('/change-password'), isNull);
    });

    test('activeChild returns the correct child for sub-routes', () {
      final inv = appNavigation.firstWhere((p) => p.id == 'inventory');
      final active = inv.activeChild('/products/form');
      expect(active?.id, 'inventory.products');
    });

    test('activeChild returns the child itself for direct routes', () {
      final sales = appNavigation.firstWhere((p) => p.id == 'sales');
      final active = sales.activeChild('/billing');
      expect(active?.id, 'sales.billing');
    });
  });

  group('Navigation model — route completeness', () {
    test('no duplicate routes across all children', () {
      final routes = <String>[];
      for (final parent in appNavigation) {
        for (final child in parent.children) {
          routes.add(child.route);
        }
      }
      expect(routes.toSet().length, routes.length,
          reason: 'Duplicate routes found: ${routes.where((r) => routes.indexOf(r) != routes.lastIndexOf(r)).toSet()}');
    });

    test('every parent has an icon', () {
      for (final parent in appNavigation) {
        expect(parent.icon, isNotNull, reason: '${parent.id} missing icon');
      }
    });
  });
}
