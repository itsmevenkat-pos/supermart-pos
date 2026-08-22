# Report Duplication Audit

Date: 2026-08-20

---

## Audit Methodology

Searched the entire project for:
- All report screens, tiles, navigation entries, and routes
- Specifically: Trial Balance, Profit & Loss, Balance Sheet, and all other report names
- Traced each: UI tile -> route -> screen -> service -> data source -> calculation

---

## Findings

| Report | Implementation A | Implementation B | Same Data? | Same Logic? | Decision |
|--------|-----------------|-----------------|------------|-------------|----------|
| Trial Balance | **Simplified** — Tab 4 "Profit & Loss", `AdvancedReportService.getTrialBalance()`, 5 hardcoded rows (Cash Sales, Credit Sales, Receivables, Payables, Stock Value), date-filtered | **GL-based** — Tab 5 "More" > "Accounting Statements (GL)", `FinancialStatementService.generateTrialBalance()`, full chart of accounts from `gl_entries`, financial-year based | No | No | KEEP BOTH — NAVIGATION-ONLY CONSOLIDATION |
| Balance Sheet | **Simplified** — Tab 4 "Profit & Loss", `AdvancedReportService.getBalanceSheet()`, 3 hardcoded rows (Stock, Receivables, Payables), ignores date filter | **GL-based** — Tab 5 "More" > "Accounting Statements (GL)", `FinancialStatementService.generateBalanceSheet()`, full Assets/Liabilities/Equity from `gl_entries`, financial-year based with optional asOf cut-off | No | No | KEEP BOTH — NAVIGATION-ONLY CONSOLIDATION |
| Profit & Loss | **Operational** — Tab 4 quick-stat cards, `ReportService.getProfitLoss()`, sales revenue minus COGS from `sale_items.cost_price` | **GL-based** — Tab 5 "More" > "Accounting Statements (GL)", `FinancialStatementService.generatePLStatement()`, full revenue/expense breakdown from `gl_entries` | No | No | KEEP BOTH — no navigation change needed |

---

## Detailed Analysis

### Trial Balance

**Implementation A (Simplified):**
- File: `lib/services/advanced_report_service.dart:190`
- Returns 5 rows: Cash Sales, Credit Sales, Accounts Receivable, Accounts Payable, Stock Value
- Data source: `sales`, `customer_ledger`, `supplier_ledger`, `products` tables
- UI shows disclaimer: "Simplified summary built from ledger balances and current stock value — not a statutory-format statement."
- Purpose: Quick operational snapshot

**Implementation B (GL-based):**
- File: `lib/services/financial_statement_service.dart:202`
- Returns every active account's debit/credit balance from `gl_entries`
- Full double-entry accounting with balance verification
- Has CSV export and financial year selector
- Purpose: Statutory-grade accounting statement

**Why different:** The simplified version aggregates from sales/purchase tables. The GL version reads from the general ledger journal. They compute fundamentally different things from different data sources.

**Decision:** KEEP BOTH. Renamed to "Trial Balance (Summary)" and "Trial Balance (GL)" to eliminate confusion.

### Balance Sheet

**Implementation A (Simplified):**
- File: `lib/services/advanced_report_service.dart:221`
- Returns 3 rows: Stock (Assets), Receivables (Assets), Payables (Liabilities)
- No equity, no sub-categories, no balance verification
- Ignores date range filter (always uses current balances)

**Implementation B (GL-based):**
- File: `lib/services/financial_statement_service.dart:302`
- Full Balance Sheet: Current Assets, Fixed Assets, Current Liabilities, Long-term Liabilities, Equity
- Verifies assets = liabilities + equity
- Has CSV export and financial year selector

**Why different:** The simplified version is essentially a 3-line snapshot of receivables/payables/stock. The GL version is a proper double-entry balance sheet.

**Decision:** KEEP BOTH. Renamed to "Balance Sheet (Summary)" and "Balance Sheet (GL)" to eliminate confusion.

### Profit & Loss

**Implementation A (Operational):**
- Tab 4 quick-stat cards (not a pushable sub-report tile)
- Shows: Total Sales, Total Purchases, COGS, Gross Profit, Profit Margin
- Calculated directly from sales/purchase tables

**Implementation B (GL-based):**
- Full P&L statement from `gl_entries`
- Revenue minus COGS minus other expenses with per-account breakdowns
- Note: COGS account (5000) currently reads zero because sale integration doesn't post to it

**Why different:** One is operational (what did we sell, what did it cost), the other is accounting (what does the ledger say). The GL version has a known gap (no COGS posting) — the fix belongs on the posting side, not the report side.

**Decision:** KEEP BOTH. No navigation change needed — they already live in different tabs with different presentations. GL version renamed to "Profit & Loss (GL)".

---

## Other Reports Audited

| Report | Duplicates Found? | Notes |
|--------|-------------------|-------|
| Sales History | No | Single implementation via `SaleRepository` |
| Sales Summary | No | Single implementation via `SalesSummaryService` |
| Stock Detail | No | Single implementation via `AdvancedReportService` |
| GST Reports (GSTR 1/2/3B/9) | No | Single implementation via `AdvancedReportService` |
| Party Statement | No | Dedicated `PartyStatementScreen` |
| Day Book | No | Single implementation via `AdvancedReportService` |
| Bank Statement | No | Single implementation via `AdvancedReportService` |
| Item Detail | No | Dedicated `ItemDetailScreen` |
| Customer History | No | Dedicated `CustomerHistoryScreen` |

---

## Changes Made

1. Renamed "Trial Balance Report" (Tab 4) to "Trial Balance (Summary)"
2. Renamed "Balance Sheet" (Tab 4) to "Balance Sheet (Summary)"
3. Renamed Tab 5 GL category from "Accounts (General Ledger)" to "Accounting Statements (General Ledger)"
4. Renamed GL reports to "Trial Balance (GL)", "Profit & Loss (GL)", "Balance Sheet (GL)"
5. No reports deleted, no routes changed, no calculations modified
