# Navigation Tree — SuperMart POS

**Phase 2 Deliverable** | Date: 2026-08-18 | Read-only — no code changes

Legend:
- `→ /route` = existing GoRouter route
- `[INTERNAL]` = not a sidebar item; reached from parent screen
- `[WORKFLOW]` = reached through operational flow, not sidebar click
- `[FUTURE]` = screen does not exist yet; placeholder for future development
- `(canonical)` = this is the ONE location for this feature
- `⚠ CONSOLIDATION` = duplicate exists, flagged for review

---

```
HOME
 └── Dashboard                            → /dashboard

SALES
 ├── New Sale (Billing)                   → /billing              (canonical)
 ├── Sales History                        → /sales-history        (canonical)
 ├── Quotations                           → /quotations           (canonical)
 ├── Hold Bills                           → /holds                (canonical)
 ├── Sales Summary                        → /sales-summary        (canonical)
 ├── Sale Cancellations                   → /sales-cancellations  (canonical)
 ├── Orders                               [FUTURE]
 ├── Invoices                             [FUTURE]
 ├── Payments Received                    [FUTURE]
 ├── Packages                             [FUTURE]
 ├── Shipments                            [FUTURE]
 ├── Delivery Challans                    [FUTURE]
 └── Sessions                             [FUTURE]
     ├── [INTERNAL] Billing shortcuts     → (F1–F12, see shortcut table)
     ├── [INTERNAL] Quotation Form        → /quotations/form
     └── [INTERNAL] Cancellation Form     → /sales-cancellations/form

PURCHASES
 ├── Purchases                            → /purchases            (canonical)
 ├── Suppliers                            → /suppliers            (canonical)
 ├── Purchase Orders                      [FUTURE]
 ├── Purchase Receives                    [FUTURE]
 ├── Purchase Bills                       [FUTURE]
 ├── Purchase Payments                    [FUTURE]
 ├── Purchase Returns                     [FUTURE]
 └── Vendor Credits                       [FUTURE]
     ├── [INTERNAL] Purchase Form         → /purchases/form
     └── [INTERNAL] Supplier Form         → /suppliers/form

INVENTORY
 ├── Products                             → /products             (canonical)
 ├── Stock Groups                         → /stock-groups         (canonical)
 ├── Barcode Generator                    → /utilities/barcode-generator  (canonical)
 ├── Import Items                         → /utilities/import-items       (canonical)
 ├── Export Items                         → /utilities/export-items       (canonical)
 ├── Bulk Update Items                    → /utilities/bulk-update-items  (canonical)
 ├── Categories                           [FUTURE — currently managed within Product Form]
 ├── Stock Adjustments                    [FUTURE]
 ├── Stock Transfer                       [FUTURE]
 ├── Stock Movement                       [FUTURE]
 └── Stock Counts                         [FUTURE]
     ├── [INTERNAL] Product Form          → /products/form
     ├── [INTERNAL] Stock Group Detail    → /stock-groups/detail
     └── [INTERNAL] Price History         → Navigator.push from Product Form

PRODUCTS & PRICING
 ├── Promotions                           → /promotions           (canonical)
 ├── Coupons                              → /coupons              (canonical)
 ├── Brands                               [FUTURE]
 └── Pricing                              [FUTURE]
     ├── [INTERNAL] Promotion Form        → /promotions/form
     └── [INTERNAL] Coupon Form           → /coupons/form

CUSTOMERS & PERKS
 ├── Customers                            → /customers            (canonical)
 ├── Loyalty Points                       → /loyalty              (canonical)
 ├── Receive Payment                      → /credit/receive-payment  (canonical)
 ├── Customer Groups                      [FUTURE]
 └── Customer Statements                  [FUTURE — Party Statement exists as report]
     ├── [INTERNAL] Customer Form         → /customers/form
     ├── [INTERNAL] Customer History      → /customers/history
     ├── [INTERNAL] Service Reminders     → /customers/reminders
     └── [INTERNAL] Campaigns             → /customers/campaigns

DOCUMENTS
 ├── Sales Returns                        → /returns              (canonical)
 ├── Exchanges                            → /exchanges            (canonical)
 ├── Credit Notes                         [FUTURE]
 ├── Delivery Challans                    [FUTURE]
 └── Other Documents                      [FUTURE]
     ├── [INTERNAL] Return Form           → /returns/form
     └── [INTERNAL] Exchange Form         → /exchanges/form

EXPENSES & CASH
 ├── Cash Management                      → /cash-management      (canonical)
 ├── Bank Accounts                        → /banking              (canonical)
 ├── Counter
 │    ├── Open Counter                    → /counter/open         (canonical)
 │    └── Close Counter                   → /counter/close        (canonical)
 ├── Collections                          → /collections          (canonical)
 ├── Payment Gateways                     → /payment-gateways     (canonical)
 ├── Expenses                             [FUTURE]
 └── Cash Sessions                        [FUTURE]
     └── [INTERNAL] Bank Reconciliation   → /banking/reconcile

REPORTS
 ├── Sales Reports
 │    ├── Sales Dashboard                 → /reports/sales-dashboard
 │    ├── Bill Wise Profit                → /reports/detail (GenericReportScreen)
 │    ├── User Wise Sales                 → /reports/detail (GenericReportScreen)
 │    ├── Sale Return Report              → /reports/detail (GenericReportScreen)
 │    ├── Sales Cancel Report             → /reports/detail (GenericReportScreen)
 │    ├── Exchange Report                 → /reports/detail (GenericReportScreen)
 │    └── Payment Mode Summary            → (embedded in reports_screen Sales tab)
 │
 ├── Purchase Reports
 │    └── Purchase Summary                → (reports_screen Purchase tab — stats only)
 │
 ├── Inventory Reports
 │    ├── Stock Detail                    → /reports/detail (GenericReportScreen)
 │    ├── Stock Summary By Category       → /reports/detail (GenericReportScreen)
 │    ├── Low Stock Summary               → /reports/detail (GenericReportScreen)
 │    ├── Near-Expiry / Expired Stock     → /reports/detail (GenericReportScreen)
 │    ├── Slow Moving Stock               → /reports/detail (GenericReportScreen)
 │    ├── Item Detail                     → /reports/detail (ItemDetailScreen)
 │    └── Sale/Purchase By Category       → /reports/detail (GenericReportScreen)
 │
 ├── Customer Reports
 │    ├── Party Statement                 → /reports/detail (PartyStatementScreen)
 │    ├── All Parties                     → /reports/detail (GenericReportScreen)
 │    ├── Customer Last Visit             → /reports/detail (GenericReportScreen)
 │    ├── Party Report By Item            → /reports/detail (GenericReportScreen)
 │    ├── Sale Purchase By Party          → /reports/detail (GenericReportScreen)
 │    └── Sale Purchase By Party Group    → /reports/detail (GenericReportScreen)
 │
 ├── Product Reports
 │    ├── Top Selling Products            → /reports/product-performance
 │    ├── AI Analysis                     → /reports/ai-analysis
 │    ├── Item Wise Profit & Loss         → /reports/detail (GenericReportScreen)
 │    ├── Item Category Wise P&L          → /reports/detail (GenericReportScreen)
 │    └── Item Wise Discount              → /reports/detail (GenericReportScreen)
 │
 ├── Financial Reports
 │    ├── Trial Balance (GL)              → /reports/detail (TrialBalanceScreen)
 │    ├── Profit & Loss (GL)              → /reports/detail (PLStatementScreen)
 │    ├── Balance Sheet (GL)              → /reports/detail (BalanceSheetScreen)
 │    ├── Party Wise Profit & Loss        → /reports/detail (GenericReportScreen)
 │    ├── Trial Balance (simplified)      → /reports/detail (GenericReportScreen)  ⚠ CONSOLIDATION
 │    └── Balance Sheet (simplified)      → /reports/detail (GenericReportScreen)  ⚠ CONSOLIDATION
 │
 ├── GST / Tax Reports
 │    ├── GSTR 1                          → /reports/detail (GenericReportScreen)
 │    ├── GSTR 2                          → /reports/detail (GenericReportScreen)
 │    ├── GSTR 3B                         → /reports/detail (GenericReportScreen)
 │    ├── GSTR 9 (Annual)                 → /reports/detail (GenericReportScreen)
 │    ├── Sale Summary By HSN             → /reports/detail (GenericReportScreen)
 │    └── GST Rate Report                 → /reports/detail (GenericReportScreen)
 │
 ├── Payment & Banking Reports
 │    ├── Bank Statement                  → /reports/detail (GenericReportScreen)
 │    └── Discount Report                 → /reports/detail (GenericReportScreen)
 │
 └── Operations Reports
      ├── Day Book                        → /reports/detail (GenericReportScreen)
      └── All Transactions                → /reports/detail (GenericReportScreen)

PEOPLE
 ├── Users                                → /users                (canonical)
 ├── Salesmen                             → /utilities/track-salesmen  (canonical)
 ├── Accountant Access                    → /utilities/accountant-access  (canonical)
 ├── Commission                           → /commission           (canonical)
 ├── Roles & Permissions                  [FUTURE]
 └── Staff Reports                        [FUTURE]
     ├── [INTERNAL] User Form             → /users/form
     └── [INTERNAL] Salesman Form         → /utilities/track-salesmen/form

SETTINGS
 ├── Business
 │    ├── Business Profile                → /settings/business-profile
 │    ├── Invoice Prefix                  → (dialog in settings_screen)
 │    ├── Currency                        → (read-only in settings_screen, INR)
 │    ├── MRP Warning Multiplier          → (read-only in settings_screen)
 │    └── Close Financial Year            → /utilities/close-financial-year
 │
 ├── Approvals
 │    ├── Return Approval Threshold       → (dialog in settings_screen)
 │    └── Max Discount Without Approval   → (dialog in settings_screen)
 │
 ├── Loyalty
 │    ├── Points Earn Rate                → (dialog in settings_screen)
 │    ├── Loyalty Point Value             → (dialog in settings_screen)
 │    └── Membership Tier Thresholds      → (dialog in settings_screen)
 │
 ├── Hardware
 │    ├── Thermal Printer                 → (dialog in settings_screen)
 │    ├── Weighing Scale Barcodes         → (dialog in settings_screen)
 │    ├── Barcode Scanner                 [FUTURE]
 │    ├── Pole Display                    [FUTURE]
 │    └── Cash Drawer                     [FUTURE]
 │
 ├── Payments
 │    └── Payment Gateways (Razorpay)     → (dialog in settings_screen)
 │
 ├── AI
 │    └── AI Analysis (Ollama)            → (dialog in settings_screen)
 │
 ├── Appearance                           [FUTURE — Theme, Layout, Accessibility]
 ├── Notifications                        [FUTURE]
 │
 └── Data & Sync
      ├── Backup Database                 → (action in settings_screen)
      ├── Restore Database                → (action in settings_screen)
      ├── Backup to Google Drive          → (action in settings_screen)
      ├── Backup to OneDrive             → (action in settings_screen)
      ├── Multi-Store Sync                → (action in settings_screen)
      ├── Import From Tally               → /utilities/import-tally
      ├── Export To Tally                 → /utilities/export-tally
      ├── Import Parties                  → /utilities/import-parties
      ├── Festival Calendar               → /utilities/festival-calendar
      └── Verify Data                     → /utilities/verify-data

AUTH / SYSTEM (not in sidebar)
 ├── Login                                → /login
 └── Change Password                      → /change-password
```

---

## Design Decision Log

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Products placement | INVENTORY (not Products & Pricing) | Products are stock items in this retail POS. Avoids duplication. Products & Pricing holds pricing RULES only. |
| Quotations placement | SALES (not Documents) | Created from billing (F10 shortcut). Pre-sale document. Operational for cashiers. |
| Sale Cancellations placement | SALES (not Documents) | Voiding a sale is a sales operation, not document generation. |
| Returns placement | DOCUMENTS | Post-sale document (refund authorization). User spec alignment. |
| Exchanges placement | DOCUMENTS | Post-sale document (exchange authorization). User spec alignment. |
| Collections placement | EXPENSES & CASH | AR aging and follow-up is a cash-flow operation. Per user spec. |
| Commission placement | PEOPLE | Salesman compensation. Per user spec (Staff / Commission). |
| Counter Open/Close | EXPENSES & CASH → Counter | Cash session management. Also reached via billing workflow. |
| Receive Payment | CUSTOMERS & PERKS | Customer credit payment. Per user spec. |
| Payment Gateways (screen) | EXPENSES & CASH | Operational payment processing. Config stays in SETTINGS → Payments. |
| Festival Calendar | SETTINGS → Data & Sync | Configuration data for AI Analysis reports. |

## Conflict Resolutions

| Feature | Appears In (user spec) | Canonical Location | Removed From |
|---------|----------------------|-------------------|-------------|
| Products | INVENTORY + PRODUCTS & PRICING | INVENTORY | PRODUCTS & PRICING |
| Quotations | SALES + DOCUMENTS | SALES | DOCUMENTS |
| Delivery Challans | SALES + DOCUMENTS | DOCUMENTS [FUTURE] | SALES [FUTURE] |
| Business Profile | SETTINGS + old Utilities flyout | SETTINGS → Business | Utilities (eliminated) |
