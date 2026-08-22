# Navigation Model — SuperMart POS

**Phase 2 Deliverable** | Date: 2026-08-18 | Read-only — no code changes  
**Companion documents**: `NAVIGATION_TREE.md`, `NAVIGATION_ROUTE_MATRIX.md`

---

## 1. Navigation Philosophy

### Current state

The existing sidebar is a flat list of 22 items plus a 13-item overlay flyout — 35 navigation targets with no hierarchy. A cashier looking for Sales History must know it's accessed from the Dashboard, not the sidebar. A manager looking for "Import From Tally" must know it's behind a flyout called "Utilities." This forces users to memorize locations rather than navigate logically.

### Target state

A professional Parent → Child hierarchy with at most two visible levels:

```
PARENT (icon + label, expandable)
  └── Child (indented label, clickable → opens screen)
```

Reports and Settings have an additional internal grouping level rendered within their own screens, not as a third sidebar nesting level.

### Design principles

1. **One canonical location per feature.** Every screen appears in exactly one place in the sidebar. No duplicates.
2. **Group by workflow, not by data model.** A cashier thinks "I need to process a return," not "I need the SalesReturn entity." Place features where users look for them.
3. **Progressive disclosure.** Show parents collapsed by default. Expanding a parent reveals its children. A cashier sees 5 parents (HOME, SALES, CUSTOMERS, DOCUMENTS, EXPENSES & CASH). A manager sees all 11.
4. **Permission-driven visibility.** Parents with zero accessible children for the current role are hidden entirely. No empty groups, no grayed-out parents.
5. **No orphans.** Every existing route and screen file maps to a parent. The Utilities flyout is eliminated; its items redistributed.
6. **Preserve all routes.** Not a single GoRouter route is renamed, removed, or renumbered. The sidebar changes how you get to a route, not the route itself.
7. **Preserve all shortcuts.** Billing keyboard shortcuts (F1–F12, Enter, Escape, arrows) are untouched. They operate within the BillingScreen, which merely moves from the top-level sidebar to SALES → New Sale.

---

## 2. Top-Level Navigation (11 Parents)

| # | Parent | Icon | Description | Visible To |
|---|--------|------|-------------|------------|
| 1 | HOME | `Icons.home` | Dashboard with KPIs and quick actions | all roles |
| 2 | SALES | `Icons.point_of_sale` | Billing, sales history, quotations, holds, cancellations | all roles |
| 3 | PURCHASES | `Icons.shopping_cart` | Purchase orders, supplier management | manager+ |
| 4 | INVENTORY | `Icons.inventory_2` | Products, stock groups, barcode tools, import/export | manager+ (accountant sees Export Items) |
| 5 | PRODUCTS & PRICING | `Icons.local_offer` | Promotions, coupons, pricing rules | manager+ |
| 6 | CUSTOMERS & PERKS | `Icons.people` | Customer list, loyalty, receive payment | all roles (partial for cashier) |
| 7 | DOCUMENTS | `Icons.description` | Returns, exchanges, credit notes | all roles |
| 8 | EXPENSES & CASH | `Icons.account_balance_wallet` | Cash management, banking, counters, collections | all roles (partial for cashier) |
| 9 | REPORTS | `Icons.assessment` | Grouped reports: sales, purchase, inventory, financial, GST, etc. | manager+ and accountant |
| 10 | PEOPLE | `Icons.badge` | Users, salesmen, accountant access, commission | manager+ |
| 11 | SETTINGS | `Icons.settings` | Business config, hardware, payments, data/sync | manager+ |

---

## 3. Complete Parent → Child Tree

See `NAVIGATION_TREE.md` for the full tree with route mappings, FUTURE markers, and design decision log.

**Summary counts**:

| Parent | Existing Children | FUTURE Children | INTERNAL Screens |
|--------|-------------------|-----------------|------------------|
| HOME | 1 | 0 | 0 |
| SALES | 6 | 7 | 3 |
| PURCHASES | 2 | 6 | 2 |
| INVENTORY | 6 | 5 | 3 |
| PRODUCTS & PRICING | 2 | 2 | 2 |
| CUSTOMERS & PERKS | 3 | 2 | 4 |
| DOCUMENTS | 2 | 3 | 2 |
| EXPENSES & CASH | 6 | 2 | 1 |
| REPORTS | 8 subcategories, ~40 reports | — | 4 route-based |
| PEOPLE | 4 | 2 | 2 |
| SETTINGS | 8 subcategories, ~23 items | 5+ | 1 |
| **Total** | **~40 sidebar items** | **~34** | **~24** |

---

## 4. Route Mapping

See `NAVIGATION_ROUTE_MATRIX.md` for the complete route-by-route matrix.

**Summary**:
- 61 GoRouter routes audited
- 1 Navigator.push screen (PriceHistoryScreen)
- 38 routes become sidebar children (Type A)
- 20 routes are internal/form screens (Type D)
- 2 auth/system routes
- 0 routes deleted, 0 routes added, 0 routes renamed

---

## 5. Utility Migration

All 13 Utilities flyout items are redistributed:

| Destination | Items Absorbed |
|-------------|---------------|
| INVENTORY | Import Items, Export Items, Bulk Update Items, Barcode Generator |
| SETTINGS → Data & Sync | Import From Tally, Export To Tally, Import Parties, Festival Calendar, Verify Data |
| SETTINGS → Business | Close Financial Year |
| PEOPLE | Salesmen (Track Your Salesmen), Accountant Access |
| DUPLICATE (removed) | Set Up My Business (= Settings → Business Profile) |

The Utilities flyout widget (`_UtilitiesFlyoutTile`, `app_scaffold.dart` lines 173–306) and its `OverlayEntry` / `CompositedTransformFollower` implementation are removed entirely during Phase 3.

---

## 6. Permission Mapping

### Correction from Phase 1

The Phase 1 audit incorrectly listed many routes as "cashier (rank 2)" accessible. Source code verification against `_routeMinRole` (app_router.dart lines 102–149) reveals:

- **Routes NOT in `_routeMinRole`** = open to all logged-in roles including cashier
- **Routes IN `_routeMinRole`** = require the specified role (manager or admin)

**Corrected breakdown**:
- Open to all (cashier+): 21 routes (dashboard, billing, customers/*, counter/*, returns/*, exchanges/*, cancellations/*, quotations/*, holds, sales-history, sales-summary, credit/receive-payment)
- Manager required: 35 routes (products, promotions, coupons, stock-groups, banking, loyalty, payment-gateways, collections, commission, suppliers, purchases, reports, settings, most utilities, cash-management)
- Admin required: 6 routes (users, import-tally, export-tally, accountant-access, close-financial-year)
- Accountant allowlist: 13 routes (dashboard, reports/*, sales-history, sales-summary, customers, suppliers, export-items, export-tally, verify-data)

### Sidebar auto-hide rule

Each parent computes whether it has at least one visible child for the current user's role:

```
visible(parent) = parent.children.any(child => userCanAccess(child.route))
```

For accountants, this means:
- HOME ✓ (dashboard)
- SALES ✓ (sales-history, sales-summary)
- PURCHASES ✓ (suppliers — view only)
- INVENTORY ✓ (export-items)
- PRODUCTS & PRICING ✗ (hidden)
- CUSTOMERS & PERKS ✓ (customers)
- DOCUMENTS ✗ (hidden — accountant cannot access returns or exchanges)
- EXPENSES & CASH ✗ (hidden)
- REPORTS ✓ (reports hub)
- PEOPLE ✗ (hidden)
- SETTINGS ✗ (hidden)

Accountant sees 6 parents. Cashier sees 5–6 parents. Manager sees 10–11 parents. Admin sees all 11.

---

## 7. Shortcut Mapping

All 18 keyboard shortcuts are billing-scoped and remain unchanged. Navigation reorganization does not affect them because:

1. The `CallbackShortcuts` widget is inside `BillingScreen`, not the sidebar
2. Shortcuts operate on billing state (cart, customer, payment), not navigation
3. The BillingScreen widget is the same; only its sidebar parent changes (Billing → SALES → New Sale)

See `NAVIGATION_ROUTE_MATRIX.md` Section 2 for the complete shortcut preservation table.

---

## 8. Duplicate Feature Analysis

| Feature | Locations | Resolution |
|---------|----------|------------|
| Business Profile | Settings → first item + Utilities → "Set Up My Business" | Remove Utilities duplicate. One entry under SETTINGS → Business. |
| Trial Balance | GL-based (`TrialBalanceScreen`) + simplified (`AdvancedReportService`) | Keep both under REPORTS → Financial. Label: "Trial Balance (General Ledger)" vs "Trial Balance (Summary)". **CONSOLIDATION CANDIDATE** for Phase 5+. |
| Profit & Loss | GL-based (`PLStatementScreen`) + P&L tab quick stats | Keep both. Different purposes (statement vs overview). Label distinctly. **CONSOLIDATION CANDIDATE**. |
| Balance Sheet | GL-based (`BalanceSheetScreen`) + simplified (`AdvancedReportService`) | Keep both. Label: "Balance Sheet (General Ledger)" vs "Balance Sheet (Summary)". **CONSOLIDATION CANDIDATE**. |
| Sales report links | Reports → Sales tab links to `/sales-history`, `/sales-cancellations`, `/exchanges` | **Not a duplicate.** Cross-reference links within the reports screen. These are convenience links, not duplicate sidebar entries. |

**Action**: 1 duplicate removed (Business Profile). 3 report pairs flagged for future consolidation. No features deleted.

---

## 9. Orphan / Internal Route Classification

### Internal routes (Type D — not in sidebar)

These are form/detail screens reached from their parent list screen:

| Route | Reached From |
|-------|-------------|
| `/products/form` | Products list → Add/Edit button |
| `/promotions/form` | Promotions list → Add/Edit button |
| `/coupons/form` | Coupons list → Add/Edit button |
| `/stock-groups/detail` | Stock Groups list → Detail button |
| `/banking/reconcile` | Bank Accounts → Reconcile button |
| `/customers/form` | Customer list → Add/Edit button |
| `/customers/reminders` | Customer section internal navigation |
| `/customers/campaigns` | Customer section internal navigation |
| `/customers/history` | Customer list → History button |
| `/suppliers/form` | Supplier list → Add/Edit button |
| `/purchases/form` | Purchase list → Add/Edit button |
| `/reports/product-performance` | Reports screen → Sales tab |
| `/reports/ai-analysis` | Reports screen → Sales tab |
| `/reports/detail` | Reports screen → any report tile (dynamic via `extra:`) |
| `/reports/sales-dashboard` | Reports screen → Sales tab |
| `/users/form` | User list → Add/Edit button |
| `/settings/business-profile` | Settings screen → Business Profile tile |
| `/returns/form` | Returns list → Add button |
| `/sales-cancellations/form` | Cancellations list → Add button |
| `/exchanges/form` | Exchanges list → Add button |
| `/quotations/form` | Quotation list → Add button |
| `/utilities/track-salesmen/form` | Salesmen list → Add/Edit button |
| `/credit/receive-payment` | Customer History → Receive Payment button |

Note: `/credit/receive-payment` is listed as both sidebar-visible (under CUSTOMERS & PERKS) and internal (reached from Customer History). The sidebar entry makes it directly accessible for the first time. The existing internal path from Customer History remains.

### Auth/system routes

| Route | Purpose |
|-------|---------|
| `/login` | Authentication. Shown only when logged out. |
| `/change-password` | Forced password change gate. Shown only when `must_change_password` flag is set. |

### Non-GoRouter screen

| Screen | Access Method |
|--------|--------------|
| `PriceHistoryScreen` | `Navigator.push()` from `ProductFormScreen`. Not a GoRouter route. No change needed. |

---

## 10. Report Hierarchy

The existing `reports_screen.dart` renders reports across 6 tabs. The new navigation model defines 8 report subcategories in the sidebar. Implementation can take two approaches:

**Approach A (recommended)**: The sidebar shows report subcategories as children of REPORTS. Clicking a subcategory navigates to `/reports` with the appropriate tab pre-selected or a filter parameter. The existing 6-tab architecture inside `reports_screen.dart` is preserved.

**Approach B**: Each report subcategory gets its own route and screen. This is a larger refactor and is NOT recommended for Phase 3.

### Report subcategory → existing tab mapping

| New Subcategory | Maps To | Existing Tab(s) |
|----------------|---------|-----------------|
| Sales Reports | Sales tab → detailed reports | Tab 1 (Sales) |
| Purchase Reports | Purchase tab stats | Tab 3 (Purchase) |
| Inventory Reports | Stock tab → detailed reports | Tab 2 (Stock) |
| Customer Reports | More tab → Party Report | Tab 6 (More) |
| Product Reports | Sales tab (performance), Stock tab (P&L) | Tabs 1, 2 |
| Financial Reports | P&L tab + More tab → Accounts | Tabs 5, 6 |
| GST / Tax Reports | GST tab → detailed reports | Tab 4 (GST) |
| Payment & Banking Reports | More tab → Business Status | Tab 6 (More) |
| Operations Reports | More tab → Transaction Report | Tab 6 (More) |

### Complete report inventory (40 reports)

**Sales Reports** (9):
1. Sales Dashboard (`/reports/sales-dashboard`)
2. Bill Wise Profit (GenericReportScreen)
3. User Wise Sales Report (GenericReportScreen)
4. Sale Return Report (GenericReportScreen)
5. Sales Cancel Report (GenericReportScreen)
6. Exchange Report (GenericReportScreen)
7. Payment Mode Summary (embedded card, not standalone)
8. Sales History link (→ `/sales-history`)
9. Sales Summary link (→ `/sales-summary`)

**Purchase Reports** (1):
1. Purchase Summary (tab 3 quick stats only — no detail reports exist)

**Inventory Reports** (7):
1. Stock Detail (GenericReportScreen)
2. Stock Summary By Item Category (GenericReportScreen)
3. Low Stock Summary (GenericReportScreen)
4. Near-Expiry / Expired Stock (GenericReportScreen)
5. Slow Moving Stock (GenericReportScreen)
6. Item Detail (ItemDetailScreen)
7. Sale/Purchase Report By Item Category (GenericReportScreen)

**Customer Reports** (6):
1. Party Statement (PartyStatementScreen)
2. All Parties (GenericReportScreen)
3. Customer Last Visit (GenericReportScreen)
4. Party Report By Item (GenericReportScreen)
5. Sale Purchase By Party (GenericReportScreen)
6. Sale Purchase By Party Group (GenericReportScreen)

**Product Reports** (5):
1. Top Selling Products (`/reports/product-performance`)
2. AI Analysis (`/reports/ai-analysis`)
3. Item Wise Profit & Loss (GenericReportScreen)
4. Item Category Wise P&L (GenericReportScreen)
5. Item Wise Discount (GenericReportScreen)

**Financial Reports** (6):
1. Trial Balance — GL-based (TrialBalanceScreen)
2. Profit & Loss — GL-based (PLStatementScreen)
3. Balance Sheet — GL-based (BalanceSheetScreen)
4. Party Wise Profit & Loss (GenericReportScreen)
5. Trial Balance — simplified (GenericReportScreen) ⚠ CONSOLIDATION
6. Balance Sheet — simplified (GenericReportScreen) ⚠ CONSOLIDATION

**GST / Tax Reports** (6):
1. GSTR 1 (GenericReportScreen)
2. GSTR 2 (GenericReportScreen)
3. GSTR 3B (GenericReportScreen)
4. GSTR 9 Annual (GenericReportScreen)
5. Sale Summary By HSN (GenericReportScreen)
6. GST Rate Report (GenericReportScreen)

**Payment & Banking Reports** (2):
1. Bank Statement (GenericReportScreen)
2. Discount Report (GenericReportScreen)

**Operations Reports** (2):
1. Day Book (GenericReportScreen)
2. All Transactions (GenericReportScreen)

**Total**: 44 report items (including 2 links to operational screens and 1 embedded card)

---

## 11. Settings Hierarchy

The existing `settings_screen.dart` renders all settings as a flat `ListView`. The new model groups settings into subcategories. Implementation options:

**Approach A (recommended)**: Restructure `settings_screen.dart` to use `ExpansionTile` groups (like reports). No new routes needed. The Settings sidebar item opens `/settings` which now shows grouped tiles.

**Approach B**: Each settings group gets its own route. This is overkill for the current number of settings.

### Settings groups

| Group | Items | Existing Implementation |
|-------|-------|----------------------|
| **Business** | Business Profile, Invoice Prefix, Currency (read-only), MRP Warning (read-only), Close Financial Year | Business Profile = sub-route. Others = dialog/read-only in settings_screen. Close FY = utility route. |
| **Approvals** | Return Approval Threshold, Max Discount Without Approval | Dialogs in settings_screen. |
| **Loyalty** | Points Earn Rate, Loyalty Point Value, Membership Tier Thresholds | Dialogs in settings_screen. |
| **Hardware** | Thermal Printer, Weighing Scale Barcodes | Dialogs in settings_screen. |
| **Payments** | Payment Gateways (Razorpay) | Dialog in settings_screen. |
| **AI** | AI Analysis (Ollama) | Dialog in settings_screen. |
| **Appearance** | [FUTURE] Theme, Layout, Accessibility | Not implemented. |
| **Notifications** | [FUTURE] | Not implemented. |
| **Data & Sync** | Backup Database, Restore Database, Google Drive Backup, OneDrive Backup, Multi-Store Sync, Import From Tally, Export To Tally, Import Parties, Festival Calendar, Verify Data | Backup/Restore/Sync = actions in settings_screen. Others = utility routes. |

---

## 12. Sidebar Behavior

### Expand / collapse

- Clicking a parent with children toggles expand/collapse
- Clicking a parent without children (HOME → Dashboard) navigates directly
- Only one parent expanded at a time (accordion behavior) — reduces sidebar height
- Current route's parent auto-expands on navigation

### Active state

Current implementation: `currentRoute == route` (exact string match).

New implementation: a child is "active" when `currentRoute == child.route`. The parent is "active" (visually highlighted) when any of its children is active OR when the current route starts with a prefix matching any child route.

Example: when on `/products/form`, the child "Products" (`/products`) is highlighted and the parent "INVENTORY" is expanded and highlighted, because `/products/form` starts with `/products`.

### Scroll behavior

- Sidebar content is scrollable when children overflow the viewport
- On route change, if the active child is not visible, scroll to bring it into view
- Scroll position is preserved during expand/collapse of other parents

### State persistence

- Expanded/collapsed state is held in memory (Riverpod provider) for the session
- On app restart, all parents start collapsed except the one containing the current route
- No database persistence needed for sidebar state

### Animation

- Expand/collapse uses `AnimatedCrossFade` or `AnimatedSize` for smooth transition
- Duration: ~200ms, curve: `Curves.easeInOut`
- No jank on long lists (Reports has 8+ children, Settings has 8+ groups)

---

## 13. UX Rules

### Sidebar dimensions
- Width: 260px (unchanged from current `_sidebarWidth`)
- Background: `#1E2433` (unchanged from current `_sidebarBg`)
- Selected background: `#2A3245` (unchanged from current `_sidebarSelectedBg`)
- Parent item height: ~48px
- Child item height: ~40px
- Child indent: 40px from left edge (icon-width + padding)

### Visual hierarchy
- Parent: icon (20px) + label (14px medium weight) + chevron (right-aligned, rotates on expand)
- Child: bullet/dot or small icon (optional) + label (13px regular weight)
- Active child: background highlight (`_sidebarSelectedBg`) + left accent bar (3px, primary color)
- Active parent: subtle background tint when expanded

### Responsive behavior
- At 1280×720: sidebar visible, content area ~1020px
- At widths below 768px: sidebar collapses to icon-only rail or overlay drawer (existing `sidebarOpenProvider` toggle)
- No horizontal scrollbar on sidebar
- Long labels truncate with ellipsis

### Report subcategories in sidebar
- Reports parent expands to show 8 subcategory children
- Clicking a subcategory navigates to `/reports` with appropriate context
- This is a 2-level hierarchy (parent → child), not 3-level (no grandchildren in sidebar)

### Settings in sidebar
- Settings parent opens `/settings` directly (no children in sidebar)
- Settings screen internally renders grouped tiles
- This avoids a long sidebar section for Settings

---

## 14. Migration Safety Rules

### During Phase 3 implementation

1. **DO NOT** delete any GoRouter route
2. **DO NOT** rename any route path
3. **DO NOT** modify any screen widget (only the sidebar navigation to those screens)
4. **DO NOT** change `_routeMinRole` or `_accountantAllowedRoutes`
5. **DO NOT** modify keyboard shortcut bindings
6. **DO NOT** change any business logic, repository, service, or provider
7. **DO NOT** modify the database schema
8. **DO NOT** change any financial calculation
9. **DO** remove the Utilities flyout widget entirely
10. **DO** replace the flat sidebar with an expandable parent → child sidebar
11. **DO** implement active-state detection using prefix matching
12. **DO** implement role-based parent visibility
13. **DO** verify all 61 routes remain reachable after the sidebar change

### Testing checklist for Phase 3

- [ ] Navigate to every sidebar child and verify the correct screen loads
- [ ] Verify every internal/form route still works (accessed from parent screen)
- [ ] Verify billing keyboard shortcuts (F1–F12) still work
- [ ] Log in as cashier: verify only permitted parents are visible
- [ ] Log in as manager: verify all non-admin items are visible
- [ ] Log in as admin: verify all items visible
- [ ] Log in as accountant: verify only allowlisted items visible
- [ ] Verify sidebar active state highlights correctly on navigation
- [ ] Verify sidebar auto-expands the correct parent on route change
- [ ] Verify sidebar scrolls correctly when content overflows
- [ ] Verify `/reports/detail` (dynamic extra: parameter) still works
- [ ] Verify PriceHistoryScreen (Navigator.push) still works from product form
- [ ] Run full test suite: `flutter test` — 0 failures expected
- [ ] Run `flutter analyze` — 0 errors, 0 warnings

---

## 15. Future Expansion Rules

### Adding a new screen

1. Create the screen widget under `lib/features/<parent>/screens/`
2. Add a GoRouter route in `app_router.dart`
3. Add the route to `_routeMinRole` if not open to all roles
4. Add the route to `_accountantAllowedRoutes` if accountants need it
5. Add a child entry to the sidebar navigation model under the appropriate parent
6. If the screen has a form sub-route, classify it as INTERNAL (Type D)

### Adding a new parent

This should be rare. The 11 parents cover the standard POS domain. If needed:
1. Add the parent to the sidebar model
2. Define its icon, label, and visibility rules
3. Add at least one child — never add an empty parent

### Converting a FUTURE item to implemented

1. Build the screen
2. Remove the `[FUTURE]` marker from the tree
3. Add the route and permissions
4. The sidebar child becomes visible automatically

### Search feature (Phase 5+)

A sidebar search box that filters across all children and report names. Implementation:
1. Text input at top of sidebar
2. As user types, filter children across all parents
3. Show matching children with their parent label
4. Clicking a result navigates and clears the search
5. Data source: the same navigation model used to render the sidebar

---

## 16. Recommended Phase 3 Implementation Plan

### Step 1: Navigation data model

Create `lib/core/navigation/navigation_model.dart`:
- Define `NavParent` (label, icon, children, route for leaf parents)
- Define `NavChild` (label, route, icon optional)
- Build the static tree from this document
- Include permission check: `bool isVisible(UserRole role)` per child

### Step 2: Replace sidebar widget

In `app_scaffold.dart`:
- Remove flat `_SidebarItem` list (lines 124–149)
- Remove `_UtilitiesFlyoutTile` entirely (lines 173–306)
- Build new `_SidebarParentTile` with expand/collapse
- Build new `_SidebarChildTile` with indented label
- Implement active-state detection with prefix matching
- Implement accordion behavior (one parent open at a time)
- Implement role-based visibility filtering

### Step 3: Test

- Manual testing of all 38 sidebar routes
- Verify all 20 internal routes via their parent screens
- Role-based login tests (cashier, manager, admin, accountant)
- Keyboard shortcut verification
- Full `flutter test` regression

### Step 4: Polish

- Smooth expand/collapse animation
- Scroll-to-active behavior
- Responsive width handling
- Visual alignment audit

---

## Appendix A: Screen File → New Parent Mapping

| Screen File | New Parent |
|-------------|-----------|
| `login_screen.dart` | AUTH/SYSTEM |
| `change_password_screen.dart` | AUTH/SYSTEM |
| `dashboard_screen.dart` | HOME |
| `billing_screen.dart` | SALES |
| `sales_history_screen.dart` | SALES |
| `quotation_list_screen.dart` | SALES |
| `quotation_form_screen.dart` | SALES (internal) |
| `hold_bills_screen.dart` | SALES |
| `sales_summary_screen.dart` | SALES |
| `sale_cancellations_list_screen.dart` | SALES |
| `sale_cancel_form_screen.dart` | SALES (internal) |
| `purchase_list_screen.dart` | PURCHASES |
| `purchase_form_screen.dart` | PURCHASES (internal) |
| `supplier_list_screen.dart` | PURCHASES |
| `supplier_form_screen.dart` | PURCHASES (internal) |
| `product_list_screen.dart` | INVENTORY |
| `product_form_screen.dart` | INVENTORY (internal) |
| `price_history_screen.dart` | INVENTORY (internal, Navigator.push) |
| `stock_group_list_screen.dart` | INVENTORY |
| `stock_group_detail_screen.dart` | INVENTORY (internal) |
| `barcode_generator_screen.dart` | INVENTORY |
| `import_items_screen.dart` | INVENTORY |
| `export_items_screen.dart` | INVENTORY |
| `bulk_update_items_screen.dart` | INVENTORY |
| `promotion_list_screen.dart` | PRODUCTS & PRICING |
| `promotion_form_screen.dart` | PRODUCTS & PRICING (internal) |
| `coupon_list_screen.dart` | PRODUCTS & PRICING |
| `coupon_form_screen.dart` | PRODUCTS & PRICING (internal) |
| `customer_list_screen.dart` | CUSTOMERS & PERKS |
| `customer_form_screen.dart` | CUSTOMERS & PERKS (internal) |
| `customer_history_screen.dart` | CUSTOMERS & PERKS (internal) |
| `service_reminders_screen.dart` | CUSTOMERS & PERKS (internal) |
| `campaigns_screen.dart` | CUSTOMERS & PERKS (internal) |
| `loyalty_summary_screen.dart` | CUSTOMERS & PERKS |
| `receive_payment_screen.dart` | CUSTOMERS & PERKS |
| `returns_list_screen.dart` | DOCUMENTS |
| `return_form_screen.dart` | DOCUMENTS (internal) |
| `exchange_list_screen.dart` | DOCUMENTS |
| `exchange_form_screen.dart` | DOCUMENTS (internal) |
| `cash_management_screen.dart` | EXPENSES & CASH |
| `bank_account_list_screen.dart` | EXPENSES & CASH |
| `bank_reconciliation_screen.dart` | EXPENSES & CASH (internal) |
| `counter_open_screen.dart` | EXPENSES & CASH |
| `counter_close_screen.dart` | EXPENSES & CASH |
| `collections_screen.dart` | EXPENSES & CASH |
| `payment_gateway_screen.dart` | EXPENSES & CASH |
| `reports_screen.dart` | REPORTS |
| `product_performance_screen.dart` | REPORTS (internal) |
| `ai_analysis_screen.dart` | REPORTS (internal) |
| `sales_dashboard_screen.dart` | REPORTS (internal) |
| `generic_report_screen.dart` | REPORTS (internal, dynamic) |
| `party_statement_screen.dart` | REPORTS (internal) |
| `item_detail_screen.dart` | REPORTS (internal) |
| `balance_sheet_screen.dart` | REPORTS (internal) |
| `pl_statement_screen.dart` | REPORTS (internal) |
| `trial_balance_screen.dart` | REPORTS (internal) |
| `user_list_screen.dart` | PEOPLE |
| `user_form_screen.dart` | PEOPLE (internal) |
| `salesman_list_screen.dart` | PEOPLE |
| `salesman_form_screen.dart` | PEOPLE (internal) |
| `accountant_access_screen.dart` | PEOPLE |
| `commission_screen.dart` | PEOPLE |
| `settings_screen.dart` | SETTINGS |
| `business_profile_screen.dart` | SETTINGS (internal) |
| `close_financial_year_screen.dart` | SETTINGS |
| `import_tally_screen.dart` | SETTINGS |
| `export_tally_screen.dart` | SETTINGS |
| `import_parties_screen.dart` | SETTINGS |
| `festival_calendar_screen.dart` | SETTINGS |
| `verify_data_screen.dart` | SETTINGS |

**Total: 70 screen files mapped. 0 unmapped.**
