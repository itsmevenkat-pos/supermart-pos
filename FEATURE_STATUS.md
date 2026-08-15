# SuperMart POS — Feature Status (verified against code)

Owner: Venkat | Store: Kootaripattu, Tamil Nadu | Stack: Flutter (Windows desktop) + SQLite (local) + Supabase (planned, not implemented)

This corrects the original master spec's ✅/🔶/⬜ markers against what's actually in the codebase as of 2026-08-12 — several items were mismarked in both directions. File:line citations point to where each verdict comes from. Update these markers as work lands so this stays the live reference.

Status legend: ✅ Built and wired | 🔶 Partially built / wired but incomplete | ⬜ Not started | ⚠️ Confirmed bug

## 1. Billing / Point-of-Sale Screen (Core)

- ✅ Spreadsheet-style billing cart, F1–F12 shortcuts, decimal quantity, price override guard, sequential invoicing (as originally marked)
- ⬜ **Live per-row stock display** — not ported
- ⬜ **Dual counter / multi-till** — not ported
- ✅ **Barcode scanner input** — real keyboard-wedge handling exists (`billing_screen.dart` `_handleSearchKeyEvent`, `HardwareKeyboard.instance.addHandler`, ~line 107/522/1143). Was marked ⬜, actually built. Weighing-scale embedded-price barcodes not separately verified.
- 🔶 **Item search** — barcode/name search works via the keyboard-wedge handler; fuzzy/alias matching not confirmed.
- ✅ **Hold / recall bill** — real, `hold_provider.dart` + `hold_model.dart` serialize cart to a `holds` table (`saveHold`). Was marked ⬜.
- ✅ **Split payment** — real. `payment_dialog.dart` supports multiple payment rows (cash/UPI/card/credit) summed against the bill total, with change calc capped at amount owed. Was marked ⬜.
- ⬜ **Split bill** (one cart, multiple payers) — not built.
- ⬜ **Quick-key/favorites grid** — not built.
- ✅ **Multi-MRP billing** — real, unconventional design: `purchase_repository.dart` (`_resolveProductId`) creates a distinct product row per MRP under the same barcode; `billing_screen.dart` `_showMRPSelectionDialog` lets the cashier pick. Was marked ⬜; works, but isn't a batch-tracked model (see §2).
- ⬜ Weighing scale integration, bill/line discounts with approval threshold, round-off logic, negative-stock control (config exists as `allow_negative_stock` flag used in the stock-deduction guard, but no UI to configure it), void/cancel with reason+audit, offline billing queue — not built.
- ✅ **Customer attach at billing** — `customer_picker_dialog.dart` wired into billing for credit/loyalty.

## 2. Inventory & Stock Management

- ✅ `quantity_utils.dart` decimal-safe math (as marked)
- ✅ **Real-time stock deduction on sale** — solid. `sale_repository.dart:49-61` does an atomic conditional `UPDATE ... WHERE stock_quantity >= ? OR allow_negative_stock=1`, rolls back the sale on 0 rows affected, writes a `stock_ledger` row per line. Was marked ⬜.
- ✅ **Low-stock alerts** — real filter (`stockQuantity <= reorderLevel`) in `product_repository.dart:81` and `dashboard_provider.dart:72-74`. Was marked ⬜.
- ⬜ Stock adjustment module (damage/expiry/theft/count correction with reason codes) — zero matches in `lib/`, not built.
- 🔶 Batch & expiry — captured as free-text columns on `purchase_items`/`stock_ledger` (`migration_v1.dart:252-253,268-269`) but never surfaced back to products for FEFO/expiry alerts. Data capture only, not a tracking system.
- 🔶 Multi-MRP — see §1, implemented via per-MRP product rows rather than true batch tracking against one SKU.
- ⬜ Unit conversion, stock transfer between counters, physical stock take/cycle count, category/sub-category/brand hierarchy, shared/pooled stock groups (no `group_id` anywhere in schema or models) — not built.
- ✅ Product master core fields (barcode, tax rate, MRP, cost price, reorder level, unit) exist; HSN code, image, computed margin not confirmed present.

## 3. Purchase & Supplier Management

- ✅ Supplier management forms (as marked)
- 🔶 **Purchase entry** — real, but it's a single-step direct stock-in with a GRN number *field*, not an actual ordered→received→partially-received PO workflow.
- ✅ **Supplier ledger** — real, running-balance append-only ledger (`supplier_ledger_repository.dart`, entries inserted/reversed on purchase insert/edit/delete in `purchase_repository.dart:109-123`). Was marked ⬜; this is solid.
- ⬜ PO creation/tracking, GRN-against-PO with variance flagging, purchase return/debit note — not built.
- 🔶 Landed cost — `transport_charge`/`labour_charges` fields exist on `purchase_model.dart` and are stored, but never apportioned into per-item `cost_price`. Fields without the math.
- ⬜ Auto reorder suggestion — not built.

## 4. Customer Management

- ⬜ Customer master GSTIN field — not present on `customer_model.dart`.
- ✅ **Khata/credit ledger** — fixed 2026-08-13. `customer_ledger` table (mirrors `supplier_ledger`) + `CustomerLedgerRepository`, written on every credit sale and payment. Real detail screen at `/customers/history?id=<id>` shows transaction-wise history and purchase history. `receive_payment_screen.dart` (previously also a placeholder) now actually records payments against the balance.
- 🔶 **Loyalty points** — earning is real (`sale_repository.dart:90`, points accrue via `bonus_points` threshold), but **no redemption logic anywhere** despite a `points_redeemed` column existing in schema. Unchanged by the 2026-08-13 pass — still open.
- ✅ Dead-code duplicate `customer_history_screen.dart` deleted; the real detail screen replaces the "Coming Soon" placeholder that used to live at the routed path.
- ✅ Tapping a customer in `customer_list_screen.dart` now opens the detail/ledger screen; editing moved to an explicit pencil icon.
- 🔶 **WhatsApp bill delivery** — real but manual: `whatsapp_share_service.dart` opens `wa.me/?text=...` with a text summary (or OS share sheet fallback); no PDF attachment, no auto-send.
- ⬜ Customer segmentation/RFM — not built.

## 5. Pricing, Discounts & Promotions

- ⬜ **Promotions engine is dead code, not partial.** `promotion_model.dart` looks fully-featured (percentage/fixed/free-item, min qty, category/product scope, date range) and a `promotions` table exists (`migration_v1.dart:291-306`) — but there is no `PromotionRepository`, no provider, no UI, and `billing_service.dart` never reads the table. Zero runtime effect.
- ⬜ Coupon codes, Buy-X-Get-Y, slab discounts, category/brand bulk discounts, time-bound promotions — not built. Only manual per-line/per-bill discount *amounts* exist in billing.

## 6. Returns, Exchange & Refunds

- ⬜ **Entirely not built.** Zero matches for `refund`, `exchange`, `sales_return` anywhere in `lib/`. No return workflow, no exchange flow, no refund-method selection, no reason capture. This is a bigger gap than the original doc's item-by-item ⬜ list implied — there is no scaffolding at all to build on.

## 7. Payments

- ✅ **Cash/UPI/card/credit as first-class types with real split payment** — see §1. Was marked ⬜.
- ✅ Change calculation (capped correctly at amount owed).
- ⬜ UPI QR generation, cash drawer trigger, card-machine reconciliation — not built; UPI today is a manual amount-entry field with no QR/deep-link.

## 8. Tax & Statutory Compliance

- ⬜ **`gst_service.dart` is a stub (11 lines)** — flat `amount * taxRate / 100` and its inverse. No CGST/SGST/IGST split, no HSN/SAC anywhere in the product model or invoice, no GSTR-1/3B export, no credit/debit-note numbering, no HSN-wise summary. The GST tab in `reports_screen.dart` shows only a single aggregate (total tax / taxable / effective rate), not a compliance report.
- ⬜ E-invoicing/IRN — not built (correctly gated on verifying current turnover threshold before building).
- ✅ **Invoice number prefix + financial-year reset** — fixed 2026-08-13, see Known Bugs below.

## 9. Multi-Store & Sync Architecture

- ⬜ **Confirmed: Supabase is not implemented at all**, not even scaffolded. No `supabase`/`supabase_flutter` dependency in `pubspec.yaml`, no `supabase` string anywhere in `lib/`. `sync_service.dart` (21 lines) only writes to a local `sync_queue` table via `DatabaseHelper.queueSync` — nothing ever reads or pushes that queue anywhere. It's an unconsumed local outbox, not a sync client.
- ⬜ Store isolation, central dashboard, conflict resolution strategy, product/price push from HQ, inter-store transfer sync, sync status indicator — all depend on the above and are not built.

## 10. Reporting & Analytics

- ✅ `reports_screen.dart` has 6 real DB-backed tabs (Sales, Stock, Purchase, GST, Profit & Loss, More) via `report_service.dart` — genuinely computed, not placeholder data. P&L tab now also shows Cost of Goods Sold.
- ✅ Sales History, Sales Summary, and Quotations are now reachable from a "More" tab inside Reports. **Deliberately left** as separate top-level routes too, still open to every role — they're intentionally cashier-accessible (see Known Bugs below for why gating them would have been wrong), so this was a discoverability fix, not a permissions change.
- 🔶 **Day-close/Z-report** — no dedicated Z-report screen, but `counter_close_screen.dart:130-235` already does real cash reconciliation (expected cash from opening + cash sales vs counted cash, shows over/short). Closer to done than the original ⬜ implied; needs a report/printout wrapper, not the core logic.
- ⬜ Item/category sales report, fast/slow-mover report, stock valuation, expiry-due report, aging report, PDF/Excel export — not independently confirmed built; treat as still open.
- ✅ `ai_analysis_screen.dart` and `product_performance_screen.dart` exist and are routed (manager-gated), reachable.
- ✅ **Trial Balance / P&L / Balance Sheet** — real double-entry statements computed from `gl_entries`, under Reports → More → "Accounts (General Ledger)". See §15. Distinct from the existing P&L *tab*, which is computed from sales/cost-price rather than from the ledger; both exist deliberately, see the COGS note in §15.

## 15. Accounting / General Ledger (Phase 1, landed 2026-08-14)

Full detail in [docs/GL_ARCHITECTURE.md](docs/GL_ARCHITECTURE.md); reconciler-facing notes in [docs/GL_USER_GUIDE.md](docs/GL_USER_GUIDE.md).

- ✅ **Double-entry schema** — `chart_of_accounts`, `gl_entries` (append-only), `gl_balances` (cached per account *per financial year*, since years get closed). `migration_v28.dart`, `AppConstants.dbVersion` 28. Seeded 20-account chart, all `is_system`.
- ✅ **Balanced posting enforced** — `gl_service.dart` sums both sides and throws `UnbalancedEntry` before the first insert, so an unbalanced entry never lands even partially. `GLEntry`'s constructor separately rejects two-sided/zero/negative lines.
- ✅ **Auto-posting from real transactions** — sale (`sale_repository.dart` `_insertSaleBody`), purchase (`purchase_repository.dart` `insertWithItems`), sales return (`sales_return_repository.dart` `_insertReturnBody`). All **inside the caller's existing transaction**: a sale whose GL post fails rolls back as a sale rather than committing unrecorded.
- ✅ **Respects the financial-year lock** — posting into a year closed via `financial_year_close_service.dart` throws `ClosedPeriod`; a real sale into a closed year is refused outright, leaving no sale row, no ledger line and no stock deduction.
- ✅ **Corrections are reversals** — `reverseEntry`/`reverseByReference` post the mirror line and link back via `reversal_of_entry_id`; the original is never mutated or deleted.
- ✅ **Trial Balance / P&L / Balance Sheet** — `financial_statement_service.dart`, strictly read-only, all three sharing one query. Balance Sheet balances by construction (`Assets = Liabilities + Equity + net profit`). All three report a broken ledger as `isBalanced == false` with the discrepancy rather than crashing.
- 🔶 **Cost of Goods Sold reads 0.00 on the GL P&L** — nothing posts to account `5000`; the sale posting is cash/receivable against revenue with no inventory-to-COGS movement. A missing *posting*, not a missing calculation, and left visible on purpose rather than back-filled from `sale_items.cost_price` (which `report_service.dart` already does — two COGS figures that can drift apart would be worse). A test asserts the zero so adding the posting later fails loudly.
- ⬜ **Sale cancellations don't post to the GL** — `sale_cancellation_repository.dart` is untouched, so a cancelled sale leaves its entries standing and revenue reads high for a period with cancellations. Returns *are* handled. `reverseByReference` is the right tool, just not called yet.
- ⬜ **GST not split out** — the whole bill including tax credits Sales Revenue; no output-tax liability account in the chart.
- ⬜ `chart_of_accounts.opening_balance` is stored but never read.
- ⚠️ **Not verified in a running app.** The three screens compile clean and are registered in `reports_screen.dart` the same way every other report is, and the service beneath them is covered by 91 tests — but no build of this app was possible in the CI container (no GTK for Linux; web blocked by pre-existing `dart:ffi` in `windows_printer.dart`). A widget smoke test was also blocked, see the note below.
- ⚠️ **Widget tests of any `AppScaffold` screen currently fail**, GL or otherwise: `_Sidebar` builds `ListTile`s inside `Container(color: _sidebarBg)` (`app_scaffold.dart:112`, `:154`), which trips Flutter's "ListTile background color or ink splashes may be invisible" assertion on every debug render. Pre-existing and app-wide; fixing it means wrapping those tiles in their own `Material`.

## 11. User Management & Security

- ✅ Role-based route gating — real (`app_router.dart` `_routeMinRole`/`_hasAccess`), admin/manager/cashier enforced.
- 🔶 **Audit log — infrastructure exists, coverage is thin.** `audit_log` table + `DatabaseHelper.logAudit()` exist, but the **only caller in the entire codebase** is `price_override_guard.dart:97` (manager PIN approval). Voids, ordinary discounts, and stock adjustments are not logged anywhere (mostly because those features don't exist yet either).
- ⬜ Session timeout/auto-lock on idle — not built.
- ✅ **Shift open/close with starting/closing cash count** — solid and real (`counter_service.dart`, `counter_open_screen.dart`, `counter_close_screen.dart`).

## 12. Hardware & Peripheral Integration

- 🔶 **Thermal receipt printer — not real ESC/POS.** `thermal_print_service.dart:14-15` literally comments "For Windows, we'll use PDF generation as fallback and later we can connect to thermal printer via USB/Bluetooth" — it renders a PDF and opens the OS print dialog. Functional for now, not ESC/POS-native.
- ✅ Barcode scanner (HID/keyboard-wedge) — real, see §1.
- ⬜ Cash drawer trigger, weighing scale integration — not built.
- ✅ **Barcode label printer — real and fairly complete**, not a stub. `barcode_label_service.dart` generates Code128 labels (single-product or A4 multi-label sheet) via the `barcode`/`pdf` packages. Was marked ⬜.

## 13. Data Safety, Backup & Reliability

- ✅ DB v7 with migration paths (as marked)
- ⬜ **Automatic local backup, DB export/import — literal no-op placeholders.** `settings_screen.dart:37-51`: both `onTap` bodies are just `// Placeholder` comments.
- ⬜ **Crash recovery — not built.** `cart_provider.dart` is pure in-memory Riverpod state with no persistence (no `SharedPreferences` usage anywhere in `lib/`). "Hold Bill" is a *manual, explicit* action, not automatic — a crash without tapping Hold loses the cart. These are not the same mechanism, contrary to how the original doc grouped them.
- ⬜ Restore-from-backup — not built/testable (no backup exists yet to restore from).

## 14. UX / Operational Polish

- ⬜ All items (dark mode, startup-time budget, receipt template config, multi-language receipt, end-of-day checklist) — not independently verified, treat as still open per original doc.

---

## Known Bugs — status after the 2026-08-13 fix pass

All six real bugs are fixed and verified (`flutter analyze`: 0 errors; `flutter test`: 87/87 passing). One reported item didn't reproduce in code.

- ✅ **FIXED — Dashboard mislabeled sales as profit.** `report_service.dart` `getProfitLoss()` used to compute `profit = totalSales - totalPurchases`, which for "today" (purchases usually 0) was just today's sales relabeled. Now: `sale_items.cost_price` is snapshotted at sale time (new column, `billing_service.dart`), and profit is computed as real COGS-based margin (`getCostOfGoodsSold()` in `report_service.dart`). The P&L report tab also now shows a "Cost of Goods Sold" line for transparency.
- ✅ **FIXED — "Today's Sales" KPI card had no tap handler.** Now navigates to `/sales-history` (`dashboard_screen.dart`), matching the Low Stock and Pending Dues cards next to it.
- ✅ **NOT A BUG, confirmed on re-check — low-stock filter is correct.** `stockQuantity <= reorderLevel` in both `product_repository.dart` and `dashboard_provider.dart`. If this still looks wrong live, check whether `reorderLevel` is actually set on the affected products — that's a data issue, not a logic one.
- ✅ **FIXED — customer detail dead end.** Built a real detail screen (`features/reports/screens/customer_history_screen.dart`) with a Credit Ledger tab and a Purchase History tab, routed at `/customers/history?id=<id>`. Tapping a customer in the list now opens this screen (with a working back button via `AppScaffold`); editing is now a separate pencil icon, both on the list row and in the detail screen's app bar. Deleted the dead-code duplicate that used to live at `features/customers/screens/customer_history_screen.dart`.
- ✅ **FIXED — no credit ledger existed.** Added a `customer_ledger` table (mirrors the existing `supplier_ledger` pattern) via `CustomerLedgerRepository`, written to on every credit sale (`sale_repository.dart`) and on payments. Also discovered and fixed a related gap while building this: `features/credit/screens/receive_payment_screen.dart` was **also** a "Coming Soon" placeholder — there was no way to record a payment against a customer's due anywhere in the app. Built a real screen (customer search → amount/method/note → `CustomerRepository.receivePayment()`), reachable from the credit route and from a "Receive Payment" button on the new customer detail screen. Existing nonzero balances were backfilled as one "Opening Balance" ledger entry per customer during the migration, so historical dues don't appear to come from nowhere.
- ✅ **FIXED — invoice numbering had no prefix or FY reset.** `sales.invoice_no` (the gapless integer) is unchanged — it's the legally-significant sequence and reprinting old bills under a new number would break that guarantee. Added `sales.invoice_display_no` (e.g. `SM/25-26/00001`), built from a configurable store prefix (`stores.invoice_prefix`, editable via Settings → Invoice Prefix) + financial year (Apr–Mar, `core/utils/financial_year.dart`) + a per-FY sequence (`invoice_counters` table, resets each financial year). All display surfaces (billing confirmation, thermal/PDF receipt, WhatsApp share, sales history, customer history, dashboard recent sales) now show `sale.invoiceLabel`, which falls back to the plain `#invoiceNo` for bills issued before this existed.
- ✅ **FIXED — Sales History / Sales Summary / Quotations sat outside Reports.** Added a "More" tab inside `reports_screen.dart` linking to all three. **Deliberately did not** gate them behind the manager-only `/reports` role restriction, or remove their standalone drawer entries — `dashboard_screen.dart`'s cashier home has direct buttons to Quotations and Hold Bills, and `app_router.dart`'s own comment confirms sales history/summary/quotations are intentionally open to every role for daily cashier use. Gating them would have been a functional regression, not a fix. This addresses the "hard to find" complaint without breaking cashier access.

---

## What changed in the 2026-08-13 fix pass (schema)

Database version bumped **7 → 10** across three migrations, all with upgrade paths for existing installs (no data loss, additive columns/tables only):

- **v8**: `sale_items.cost_price` — cost snapshot per line at sale time, powers real profit calculation.
- **v9**: `customer_ledger` table — transaction-level credit history, with a one-time backfill of existing nonzero balances as opening-balance entries.
- **v10**: `stores.invoice_prefix`, `invoice_counters` table, `sales.invoice_display_no` — formatted invoice numbering.

## What this changes about the priority roadmap

Known bugs (step 0) are done. Two things worth knowing before picking the next roadmap item:

1. **Returns/Refunds (§6) has zero scaffolding** — worth pricing in as a from-scratch build, not a partial one, when it comes up.
2. **Settings screen is still mostly cosmetic** — only "Invoice Prefix" is now a real, saved setting; Currency/Tax Rate/Bonus Threshold/MRP Multiplier tiles still just display hardcoded `app_constants.dart` values, and Export/Import Database are still no-op placeholders (§13).

Everything else in the original priority order (multi-MRP hardening → Supabase → GST compliance → returns/loyalty → reporting suite → hardware → polish) is unaffected by this audit and still applies.
