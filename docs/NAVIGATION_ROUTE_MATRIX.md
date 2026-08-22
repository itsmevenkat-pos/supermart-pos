# Navigation Route Matrix — SuperMart POS

**Phase 2 Deliverable** | Date: 2026-08-18 | Read-only — no code changes

---

## 1. Complete Route Matrix

**Status legend**:
- `KEEP` — route preserved, moves to new parent
- `MOVE` — sidebar visibility changes (gains or loses sidebar presence)
- `INTERNAL` — sub-screen reached from parent, never a sidebar item
- `WORKFLOW` — reached through operational flow (billing, counter)
- `AUTH/SYSTEM` — authentication/system route, not in sidebar
- `DUPLICATE REVIEW` — overlaps with another item, flagged for consolidation

**Type legend**:
- `A` — Sidebar child (visible in new sidebar)
- `B` — Dashboard shortcut (quick action on dashboard, not a sidebar duplicate)
- `C` — Modal/dialog (opens as overlay, no route change)
- `D` — Internal screen (child form/detail, not in sidebar)
- `E` — Workflow-only route (reached through operational flow)
- `F` — Auth/system route

**Permission** — Minimum role from `_routeMinRole` + accountant allowlist (corrected from source code verification):
- `all` = any logged-in role (cashier, manager, admin)
- `mgr` = manager or admin
- `admin` = admin only
- `acct✓` = accountant-allowed via `_accountantAllowedRoutes`

### Auth / System Routes

| Route | Screen | Current Parent | New Parent | New Child | Type | Permission | Shortcut | Status |
|-------|--------|---------------|------------|-----------|------|------------|----------|--------|
| `/login` | LoginScreen | — | — | — | F | unauthenticated | — | AUTH/SYSTEM |
| `/change-password` | ChangePasswordScreen | — | — | — | F | must-change gate | — | AUTH/SYSTEM |

### Main Routes

| Route | Screen | Current Parent | New Parent | New Child | Type | Permission | Shortcut | Status |
|-------|--------|---------------|------------|-----------|------|------------|----------|--------|
| `/dashboard` | DashboardScreen | Sidebar: Dashboard | HOME | Dashboard | A | all, acct✓ | — | KEEP |
| `/billing` | BillingScreen | Sidebar: Billing | SALES | New Sale | A | all | F1–F12 | MOVE |
| `/sales-history` | SalesHistoryScreen | — (no sidebar) | SALES | Sales History | A | all, acct✓ | — | MOVE |
| `/quotations` | QuotationListScreen | — (no sidebar) | SALES | Quotations | A | all | — | MOVE |
| `/quotations/form` | QuotationFormScreen | — | SALES | — | D | all | F10 (billing) | INTERNAL |
| `/holds` | HoldBillsScreen | — (no sidebar) | SALES | Hold Bills | A | all | F4 (billing) | MOVE |
| `/sales-summary` | SalesSummaryScreen | — (no sidebar) | SALES | Sales Summary | A | all, acct✓ | — | MOVE |
| `/sales-cancellations` | SaleCancellationsListScreen | Sidebar: Sale Cancellations | SALES | Sale Cancellations | A | all | — | MOVE |
| `/sales-cancellations/form` | SaleCancelFormScreen | — | SALES | — | D | all | — | INTERNAL |
| `/purchases` | PurchaseListScreen | Sidebar: Purchases | PURCHASES | Purchases | A | mgr | — | MOVE |
| `/purchases/form` | PurchaseFormScreen | — | PURCHASES | — | D | mgr | — | INTERNAL |
| `/suppliers` | SupplierListScreen | Sidebar: Suppliers | PURCHASES | Suppliers | A | mgr, acct✓ | — | MOVE |
| `/suppliers/form` | SupplierFormScreen | — | PURCHASES | — | D | mgr | — | INTERNAL |
| `/products` | ProductListScreen | Sidebar: Products | INVENTORY | Products | A | mgr | — | MOVE |
| `/products/form` | ProductFormScreen | — | INVENTORY | — | D | mgr | — | INTERNAL |
| `/stock-groups` | StockGroupListScreen | Sidebar: Stock Groups | INVENTORY | Stock Groups | A | mgr | — | MOVE |
| `/stock-groups/detail` | StockGroupDetailScreen | — | INVENTORY | — | D | mgr | — | INTERNAL |
| `/utilities/barcode-generator` | BarcodeGeneratorScreen | Utilities flyout | INVENTORY | Barcode Generator | A | mgr | — | MOVE |
| `/utilities/import-items` | ImportItemsScreen | Utilities flyout | INVENTORY | Import Items | A | mgr | — | MOVE |
| `/utilities/export-items` | ExportItemsScreen | Utilities flyout | INVENTORY | Export Items | A | mgr, acct✓ | — | MOVE |
| `/utilities/bulk-update-items` | BulkUpdateItemsScreen | Utilities flyout | INVENTORY | Bulk Update Items | A | mgr | — | MOVE |
| `/promotions` | PromotionListScreen | Sidebar: Promotions | PRODUCTS & PRICING | Promotions | A | mgr | — | MOVE |
| `/promotions/form` | PromotionFormScreen | — | PRODUCTS & PRICING | — | D | mgr | — | INTERNAL |
| `/coupons` | CouponListScreen | Sidebar: Coupons | PRODUCTS & PRICING | Coupons | A | mgr | — | MOVE |
| `/coupons/form` | CouponFormScreen | — | PRODUCTS & PRICING | — | D | mgr | — | INTERNAL |
| `/customers` | CustomerListScreen | Sidebar: Customers | CUSTOMERS & PERKS | Customers | A | all, acct✓ | — | MOVE |
| `/customers/form` | CustomerFormScreen | — | CUSTOMERS & PERKS | — | D | all | — | INTERNAL |
| `/customers/reminders` | ServiceRemindersScreen | — | CUSTOMERS & PERKS | — | D | all | — | INTERNAL |
| `/customers/campaigns` | CampaignsScreen | — | CUSTOMERS & PERKS | — | D | all | — | INTERNAL |
| `/customers/history` | CustomerHistoryScreen | — | CUSTOMERS & PERKS | — | D | all | — | INTERNAL |
| `/loyalty` | LoyaltySummaryScreen | Sidebar: Loyalty Points | CUSTOMERS & PERKS | Loyalty Points | A | mgr | — | MOVE |
| `/credit/receive-payment` | ReceivePaymentScreen | — (hidden) | CUSTOMERS & PERKS | Receive Payment | A | all | — | MOVE |
| `/returns` | ReturnsListScreen | Sidebar: Returns | DOCUMENTS | Sales Returns | A | all | — | MOVE |
| `/returns/form` | ReturnFormScreen | — | DOCUMENTS | — | D | all | — | INTERNAL |
| `/exchanges` | ExchangeListScreen | Sidebar: Exchanges | DOCUMENTS | Exchanges | A | all | — | MOVE |
| `/exchanges/form` | ExchangeFormScreen | — | DOCUMENTS | — | D | all | — | INTERNAL |
| `/cash-management` | CashManagementScreen | Sidebar: Cash Management | EXPENSES & CASH | Cash Management | A | mgr | — | MOVE |
| `/banking` | BankAccountListScreen | Sidebar: Bank Accounts | EXPENSES & CASH | Bank Accounts | A | mgr | — | MOVE |
| `/banking/reconcile` | BankReconciliationScreen | — | EXPENSES & CASH | — | D | mgr | — | INTERNAL |
| `/counter/open` | CounterOpenScreen | — (no sidebar) | EXPENSES & CASH | Open Counter | A | all | — | MOVE |
| `/counter/close` | CounterCloseScreen | — (no sidebar) | EXPENSES & CASH | Close Counter | A | all | — | MOVE |
| `/collections` | CollectionsScreen | Sidebar: Collections | EXPENSES & CASH | Collections | A | mgr | — | MOVE |
| `/payment-gateways` | PaymentGatewayScreen | Sidebar: Payment Gateways | EXPENSES & CASH | Payment Gateways | A | mgr | — | MOVE |
| `/reports` | ReportsScreen | Sidebar: Reports | REPORTS | Reports Hub | A | mgr, acct✓ | — | KEEP |
| `/reports/product-performance` | ProductPerformanceScreen | — | REPORTS | — | D | mgr, acct✓ | — | INTERNAL |
| `/reports/ai-analysis` | AiAnalysisScreen | — | REPORTS | — | D | mgr, acct✓ | — | INTERNAL |
| `/reports/detail` | GenericReportScreen (dynamic) | — | REPORTS | — | D | mgr, acct✓ | — | INTERNAL |
| `/reports/sales-dashboard` | SalesDashboardScreen | — | REPORTS | — | D | mgr, acct✓ | — | INTERNAL |
| `/users` | UserListScreen | Sidebar: Users | PEOPLE | Users | A | admin | — | MOVE |
| `/users/form` | UserFormScreen | — | PEOPLE | — | D | admin | — | INTERNAL |
| `/utilities/track-salesmen` | SalesmanListScreen | Utilities flyout | PEOPLE | Salesmen | A | mgr | — | MOVE |
| `/utilities/track-salesmen/form` | SalesmanFormScreen | — | PEOPLE | — | D | mgr | — | INTERNAL |
| `/utilities/accountant-access` | AccountantAccessScreen | Utilities flyout | PEOPLE | Accountant Access | A | admin | — | MOVE |
| `/commission` | CommissionScreen | Sidebar: Commission | PEOPLE | Commission | A | mgr | — | MOVE |
| `/settings` | SettingsScreen | Sidebar: Settings | SETTINGS | Settings Hub | A | mgr | — | KEEP |
| `/settings/business-profile` | BusinessProfileScreen | Settings list + Utilities | SETTINGS | Business Profile | D | mgr | — | INTERNAL |
| `/utilities/close-financial-year` | CloseFinancialYearScreen | Utilities flyout | SETTINGS | Close Financial Year | A | admin | — | MOVE |
| `/utilities/import-tally` | ImportTallyScreen | Utilities flyout | SETTINGS | Import From Tally | A | admin | — | MOVE |
| `/utilities/export-tally` | ExportTallyScreen | Utilities flyout | SETTINGS | Export To Tally | A | admin, acct✓ | — | MOVE |
| `/utilities/import-parties` | ImportPartiesScreen | Utilities flyout | SETTINGS | Import Parties | A | mgr | — | MOVE |
| `/utilities/festival-calendar` | FestivalCalendarScreen | Utilities flyout | SETTINGS | Festival Calendar | A | mgr | — | MOVE |
| `/utilities/verify-data` | VerifyDataScreen | Utilities flyout | SETTINGS | Verify Data | A | mgr, acct✓ | — | MOVE |

### Non-GoRouter Screens

| Screen | Current Access | New Parent | Type | Notes |
|--------|---------------|------------|------|-------|
| PriceHistoryScreen | Navigator.push from ProductFormScreen | INVENTORY | D | Not a GoRouter route. Launched from product form. No change needed. |

---

## 2. Keyboard Shortcut Preservation Table

All shortcuts are scoped to BillingScreen (`lib/features/billing/screens/billing_screen.dart`).

| Shortcut | Existing Action | Screen | New Navigation Path | Status |
|----------|----------------|--------|-------------------|--------|
| F1 | Open Customer picker dialog | BillingScreen | SALES → New Sale | KEEP |
| F2 | Open Discount dialog | BillingScreen | SALES → New Sale | KEEP |
| F3 | Hold current bill | BillingScreen | SALES → New Sale | KEEP |
| F4 | Show held bills | BillingScreen | SALES → New Sale | KEEP |
| F5 | Open Payment dialog | BillingScreen | SALES → New Sale | KEEP |
| F6 | Focus barcode/search input | BillingScreen | SALES → New Sale | KEEP |
| F7 | Focus last item quantity | BillingScreen | SALES → New Sale | KEEP |
| F8 | Remove focused cart item | BillingScreen | SALES → New Sale | KEEP |
| F9 | Share on WhatsApp | BillingScreen | SALES → New Sale | KEEP |
| F10 | Open Quotation dialog | BillingScreen | SALES → New Sale | KEEP |
| F11 | Partial payment (credit) | BillingScreen | SALES → New Sale | KEEP |
| F12 | Start new bill | BillingScreen | SALES → New Sale | KEEP |
| Enter | Open Payment dialog | BillingScreen | SALES → New Sale | KEEP |
| Escape | Clear search | BillingScreen | SALES → New Sale | KEEP |
| Arrow Up | Navigate search results up | BillingScreen | SALES → New Sale | KEEP |
| Arrow Down | Navigate search results down | BillingScreen | SALES → New Sale | KEEP |
| Enter (qty field) | Commit quantity change | CartListView | SALES → New Sale | KEEP |
| Arrow Up/Down | Navigate customer picker | CustomerPickerDialog | SALES → New Sale | KEEP |
| Enter | Select customer | CustomerPickerDialog | SALES → New Sale | KEEP |

**Total shortcuts**: 18  
**Shortcuts modified**: 0  
**Shortcuts removed**: 0

---

## 3. Permission Safety Matrix

### Corrected Permission Map

**IMPORTANT CORRECTION**: The Phase 1 audit incorrectly classified many manager-only routes as cashier-accessible. This matrix is verified against `_routeMinRole` (app_router.dart lines 102–149) and `_accountantAllowedRoutes` (lines 157–171).

#### Routes open to ALL roles (including cashier)

These routes have NO entry in `_routeMinRole` — the code comment confirms they are "open to every logged-in role."

| Route | Feature |
|-------|---------|
| `/dashboard` | Dashboard |
| `/billing` | New Sale / Billing |
| `/customers` | Customer List |
| `/customers/form` | Customer Add/Edit |
| `/customers/reminders` | Service Reminders |
| `/customers/campaigns` | Campaigns |
| `/customers/history` | Customer History |
| `/counter/open` | Open Counter |
| `/counter/close` | Close Counter |
| `/credit/receive-payment` | Receive Payment |
| `/sales-history` | Sales History |
| `/returns` | Returns List |
| `/returns/form` | Return Form |
| `/sales-cancellations` | Sale Cancellations List |
| `/sales-cancellations/form` | Cancellation Form |
| `/exchanges` | Exchanges List |
| `/exchanges/form` | Exchange Form |
| `/sales-summary` | Sales Summary |
| `/quotations` | Quotations List |
| `/quotations/form` | Quotation Form |
| `/holds` | Hold Bills |

#### Routes requiring MANAGER (rank 1)

| Route | Feature |
|-------|---------|
| `/products` | Products List |
| `/products/form` | Product Add/Edit |
| `/promotions` | Promotions List |
| `/promotions/form` | Promotion Form |
| `/coupons` | Coupons List |
| `/coupons/form` | Coupon Form |
| `/stock-groups` | Stock Groups |
| `/stock-groups/detail` | Stock Group Detail |
| `/banking` | Bank Accounts |
| `/banking/reconcile` | Bank Reconciliation |
| `/loyalty` | Loyalty Summary |
| `/payment-gateways` | Payment Gateways |
| `/collections` | Collections |
| `/commission` | Commission |
| `/suppliers` | Suppliers List |
| `/suppliers/form` | Supplier Form |
| `/purchases` | Purchases List |
| `/purchases/form` | Purchase Form |
| `/reports` | Reports |
| `/reports/product-performance` | Product Performance |
| `/reports/ai-analysis` | AI Analysis |
| `/reports/detail` | Generic Report Detail |
| `/reports/sales-dashboard` | Sales Dashboard |
| `/settings` | Settings |
| `/settings/business-profile` | Business Profile |
| `/utilities/barcode-generator` | Barcode Generator |
| `/utilities/export-items` | Export Items |
| `/utilities/import-items` | Import Items |
| `/utilities/bulk-update-items` | Bulk Update Items |
| `/utilities/import-parties` | Import Parties |
| `/utilities/track-salesmen` | Salesmen List |
| `/utilities/track-salesmen/form` | Salesman Form |
| `/utilities/verify-data` | Verify Data |
| `/utilities/festival-calendar` | Festival Calendar |
| `/cash-management` | Cash Management |

#### Routes requiring ADMIN (rank 0)

| Route | Feature |
|-------|---------|
| `/users` | Users List |
| `/users/form` | User Add/Edit |
| `/utilities/import-tally` | Import From Tally |
| `/utilities/export-tally` | Export To Tally |
| `/utilities/accountant-access` | Accountant Access |
| `/utilities/close-financial-year` | Close Financial Year |

#### Accountant Allowlist (rank 3, special handling)

Accountants bypass the normal role check and can ONLY access these routes:

| Route | Feature |
|-------|---------|
| `/dashboard` | Dashboard |
| `/reports` | Reports |
| `/reports/product-performance` | Product Performance |
| `/reports/ai-analysis` | AI Analysis |
| `/reports/detail` | Generic Report Detail |
| `/reports/sales-dashboard` | Sales Dashboard |
| `/sales-history` | Sales History |
| `/sales-summary` | Sales Summary |
| `/customers` | Customer List |
| `/suppliers` | Supplier List |
| `/utilities/export-items` | Export Items |
| `/utilities/export-tally` | Export To Tally |
| `/utilities/verify-data` | Verify Data |

### Sidebar Visibility by Role

| Parent | Cashier | Manager | Admin | Accountant |
|--------|---------|---------|-------|------------|
| HOME | Dashboard | Dashboard | Dashboard | Dashboard |
| SALES | 6 items (Billing, History, Quotations, Holds, Summary, Cancellations) | 6 items | 6 items | History, Summary only |
| PURCHASES | — | 2 items | 2 items | Suppliers (view only) |
| INVENTORY | — | 6 items | 6 items | Export Items only |
| PRODUCTS & PRICING | — | 2 items | 2 items | — |
| CUSTOMERS & PERKS | 2 items (Customers, Receive Payment) | 3 items (+Loyalty) | 3 items | Customers only |
| DOCUMENTS | 2 items (Returns, Exchanges) | 2 items | 2 items | — |
| EXPENSES & CASH | 2 items (Counter Open, Close) | 6 items | 6 items | — |
| REPORTS | — | Reports Hub | Reports Hub | Reports Hub |
| PEOPLE | — | 3 items (Salesmen, Commission) | 4 items (+Users, Accountant Access) | — |
| SETTINGS | — | Settings Hub (most) | Settings Hub (all) | — |

**Rule**: A parent with zero visible children for a role MUST be hidden from that role's sidebar.

---

## 4. Utility Migration Table

| # | Current Utility | Current Route | New Parent | New Sidebar Child | Status |
|---|----------------|---------------|------------|-------------------|--------|
| 1 | Import Items | `/utilities/import-items` | INVENTORY | Import Items | MOVE |
| 2 | Set Up My Business | `/settings/business-profile` | SETTINGS | Business Profile | DUPLICATE REVIEW — same route as Settings → Business Profile. Remove from sidebar; keep route. |
| 3 | Accountant Access | `/utilities/accountant-access` | PEOPLE | Accountant Access | MOVE |
| 4 | Barcode Generator | `/utilities/barcode-generator` | INVENTORY | Barcode Generator | MOVE |
| 5 | Festival Calendar | `/utilities/festival-calendar` | SETTINGS → Data & Sync | Festival Calendar | MOVE |
| 6 | Update Items In Bulk | `/utilities/bulk-update-items` | INVENTORY | Bulk Update Items | MOVE |
| 7 | Import From Tally | `/utilities/import-tally` | SETTINGS → Data & Sync | Import From Tally | MOVE |
| 8 | Import Parties | `/utilities/import-parties` | SETTINGS → Data & Sync | Import Parties | MOVE |
| 9 | Track Your Salesmen | `/utilities/track-salesmen` | PEOPLE | Salesmen | MOVE |
| 10 | Exports To Tally | `/utilities/export-tally` | SETTINGS → Data & Sync | Export To Tally | MOVE |
| 11 | Export Items | `/utilities/export-items` | INVENTORY | Export Items | MOVE |
| 12 | Verify My Data | `/utilities/verify-data` | SETTINGS → Data & Sync | Verify Data | MOVE |
| 13 | Close Financial Year | `/utilities/close-financial-year` | SETTINGS → Business | Close Financial Year | MOVE |

**Utilities flyout**: eliminated entirely. All 13 items redistributed.  
**Duplicate**: 1 (Set Up My Business = Business Profile). Only one sidebar entry retained.

---

## 5. Duplicate / Consolidation Candidates

| Feature | Location A | Location B | Recommendation |
|---------|-----------|-----------|----------------|
| Business Profile | Settings → Business Profile (route) | Utilities flyout → "Set Up My Business" | **Keep Settings location only.** Remove the Utilities duplicate. Same route `/settings/business-profile`. |
| Trial Balance | Reports → Financial → GL-based (`TrialBalanceScreen`) | Reports → P&L tab → simplified (`AdvancedReportService.getTrialBalance`) | **Keep both for now.** GL-based is authoritative (double-entry). Simplified is a quick view. Label distinctly: "Trial Balance (General Ledger)" vs "Trial Balance (Summary)". Flag for future consolidation. |
| Profit & Loss Statement | Reports → Financial → GL-based (`PLStatementScreen`) | Reports → P&L tab → simplified (quick stats only) | **Keep both.** GL-based is the real P&L statement. Tab provides overview stats. Label clearly. |
| Balance Sheet | Reports → Financial → GL-based (`BalanceSheetScreen`) | Reports → P&L tab → simplified (`AdvancedReportService.getBalanceSheet`) | **Keep both.** Same rationale. Flag for consolidation. |
| Sales-related reports | Reports → Sales tab (links to `/sales-history`, `/sales-cancellations`, `/exchanges`) | SALES sidebar children + DOCUMENTS sidebar children | **Not a duplication.** Reports link to operational screens for convenience. The report-tile links in `reports_screen.dart` are cross-references, not duplicate features. |

---

## 6. Route Counts Summary

| Category | Count |
|----------|-------|
| Auth/System routes | 2 |
| Sidebar-visible routes (Type A) | 38 |
| Internal/form routes (Type D) | 20 |
| Workflow routes (Type E) | 0 (Counter Open/Close promoted to sidebar) |
| Non-GoRouter screens | 1 (PriceHistoryScreen) |
| **Total routes** | **61** |
| **Total screen files** | **70** |
| Routes deleted | **0** |
| Routes added | **0** |
| Routes renamed | **0** |
