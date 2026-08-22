# PROJECT 3 — PHASE 0 INSPECTION REPORT

**Date:** 2026-08-17
**Scope:** Financial Authorization, Returns/Refunds/Exchanges & Cash Management UI
**Inspector:** Claude (automated)
**Status:** Inspection complete — no code modified

---

## 1. BASELINE

| Metric | Value |
|---|---|
| Tests | 606 passing, 0 failures |
| Analyzer | 0 errors, 0 warnings, 138 infos |
| Schema version | v35 (`dbVersion = 35` in `app_constants.dart`) |
| Starting commit | `0e9a80a` (Clear the audit's housekeeping and doc-drift findings) |
| Prior projects | P1 (478→530 tests, v34), P2 (530→606 tests, v34→v35) |

**Authoritative documents read:**
1. `docs/AUDIT_2026-08-16.md` — original audit (C1/C2/C3/H1–H4)
2. `docs/PROJECT1_C1_C3_VERIFICATION.md` — P1 final report
3. `docs/PROJECT2_PHASE0_INSPECTION.md` — P2 inspection (G1–G10, AD-1–AD-7)
4. `docs/PROJECT2_ACCOUNTING_RECONCILIATION.md` — P2 final report (G1–G5,G8 closed; G6,G7 open)

---

## 2. FINANCIAL APPROVAL MATRIX

Each row shows where authorization lives today: UI (screen dialog), Service (`ApprovalService`), and Repository (validation inside the transaction).

| Operation | UI Check | Service Check | Repo Check | Threshold | Approver Validated | Risk |
|---|---|---|---|---|---|---|
| **Customer payment** (`receivePayment`) | Screen reads threshold, shows dialog | YES — `authorise()` inside txn | YES — `CustomerRepository` calls `_approvals.authorise()` at line 145 | `stores.return_threshold_no_approval` | **YES** — `requireValidApprover` | LOW — closed by P2-C4 |
| **Credit-limit change** (`insert`/`update`) | Screen checks for increase | N/A | YES — `_authoriseCreditLimit()` inside txn | Any increase | **YES** — `requireValidApprover` | LOW — closed by P2-C4 |
| **Sales return** | Screen: `return_form_screen.dart:253–266` — if untied OR amount > threshold | **NONE** | **NONE** — `approvedByUserId` stored verbatim | `stores.return_threshold_no_approval` + always for untied | **NO** — accepted without validation | **CRITICAL** |
| **Sale cancellation** | Screen: `sale_cancel_form_screen.dart:155–159` — always requires manager | **NONE** | **NONE** — `approvedByUserId` is `String?`, stored verbatim at line 69 | None (always) | **NO** — accepted without validation | **CRITICAL** |
| **Exchange** | Screen: `exchange_form_screen.dart:254–258` — always requires manager | **NONE** | **NONE** — `approvedByUserId` is `String?`, stored verbatim at line 94 | None (always) | **NO** — accepted without validation | **CRITICAL** |
| **Cash in** | No screen | Service: `cashIn` passes `requireApproval: false` | N/A | Not gated | Validated if provided | LOW — service enforces |
| **Cash out** | No screen | YES — `authorise()` | N/A | `stores.return_threshold_no_approval` | **YES** | LOW — service enforces |
| **Cash drop** | No screen | YES — `authorise()` | N/A | `stores.return_threshold_no_approval` | **YES** | LOW — service enforces |
| **Cash transfer** | No screen | YES — `authorise()` | N/A | `stores.return_threshold_no_approval` | **YES** | LOW — service enforces |
| **Manual adjustment** | No screen | YES — `authoriseAlways()` | N/A | Always | **YES** | LOW — service enforces |

**Summary:** Three operations — returns, cancellations, and exchanges — have approval enforced exclusively in the screen's `_submit()` method using `requireApprovalWithApprover()`, a UI dialog function from `price_override_guard.dart` that takes `BuildContext` and `WidgetRef`. Their repositories accept `approvedByUserId` as an unvalidated optional string. A direct caller (test harness, sync handler, bulk tool, future screen) can:

1. Pass `null` — bypassing approval entirely
2. Pass any string — forging a non-existent approver
3. Pass a cashier's own id — self-approving

The P2-fixed operations (customer payment, credit-limit change, cash management) all validate inside the transaction. These three do not.

---

## 3. RETURNS / REFUNDS / EXCHANGES FLOW MATRIX

### 3A. Sales Return

**Path:** `return_form_screen.dart` → `SalesReturnNotifier.createReturn()` → `SalesReturnRepository.insertReturn()`

| Step | Location | Inside txn? | Notes |
|---|---|---|---|
| Threshold check | `return_form_screen.dart:252–253` | N/A (UI) | `StoreRepository().getReturnThreshold()` |
| Approval dialog | `return_form_screen.dart:256–266` | N/A (UI) | `requireApprovalWithApprover(context, ref, ...)` |
| Insert header | `sales_return_repository.dart:67` | YES | `approvedByUserId` stored, never validated |
| Insert items | `sales_return_repository.dart:69–82` | YES | |
| Restock (if flagged) | `sales_return_repository.dart:84–107` | YES | Atomic `stock_quantity` increment + `stock_ledger` |
| Credit adjust (if applicable) | `sales_return_repository.dart:110–138` | YES | Updates `customers.outstanding_balance` + `customer_ledger` |
| GL posting | `sales_return_repository.dart:149–163` | YES | `postSalesReturnEntries()` — method-aware |
| Cash book | `sales_return_repository.dart:169–179` | YES | `recordOut()` — only if `isCashMethod()` |
| Sync queue | `sales_return_repository.dart:181` | YES | |
| **Audit** | **`return_form_screen.dart:297–305`** | **NO — outside txn** | **Only if `approvedByUserId != null`** |

**Defects found:**
- **D1 (P3-C1):** `approvedByUserId` is never validated at the repository level. Any caller can supply any string or null.
- **D2 (P3-C2, G6):** Audit row is written by the screen, OUTSIDE the transaction, ONLY when `approvedByUserId != null`. A crash between commit and audit leaves a completed refund with no trace. Below-threshold returns produce no audit row at all. Non-screen callers produce no audit row at all.
- **D3 (P3-C2):** No duplicate protection — the same return can be submitted multiple times (no status check on the originating sale to prevent overlapping returns beyond the UI's navigation flow).

### 3B. Sale Cancellation

**Path:** `sale_cancel_form_screen.dart` → `SaleCancellationRepository.cancelSale()`

| Step | Location | Inside txn? | Notes |
|---|---|---|---|
| Approval dialog | `sale_cancel_form_screen.dart:155–159` | N/A (UI) | Always requires manager |
| Re-fetch sale (race guard) | `sale_cancellation_repository.dart:48–55` | YES | Checks `status != 'cancelled'` — duplicate protection |
| Check no existing returns | `sale_cancellation_repository.dart:57–59` | YES | Prevents cancel after partial return |
| Create cancellation record | `sale_cancellation_repository.dart:62–70` | YES | `approvedByUserId` stored verbatim |
| Restock all items | `sale_cancellation_repository.dart:72–93` | YES | Atomic `stock_quantity` + `stock_ledger` |
| Customer balance reversal | `sale_cancellation_repository.dart:95–217` | YES | Points, ledger, balance — all reversed |
| Update sale status | `sale_cancellation_repository.dart:220` | YES | `status = 'cancelled'` |
| Insert cancellation | `sale_cancellation_repository.dart:222` | YES | |
| GL reversal | `sale_cancellation_repository.dart:230–236` | YES | `reverseByReference()` — idempotent |
| **Audit** | **`sale_cancellation_repository.dart:238–251`** | **YES** | **Always written, inside txn — correct pattern** |
| Cash book | `sale_cancellation_repository.dart:266–279` | YES | Capped at cash actually taken (P1 fix) |

**Defects found:**
- **D4 (P3-C1):** `approvedByUserId` is `String?` and is never validated. A direct caller can cancel any sale without approval.
- Note: Duplicate protection IS present (re-fetch + status check). Audit IS inside the transaction. Stock reversal IS atomic. Cash refund IS properly capped. These are correct.

### 3C. Exchange

**Path:** `exchange_form_screen.dart` → `ExchangeRepository.processExchange()`

| Step | Location | Inside txn? | Notes |
|---|---|---|---|
| Approval dialog | `exchange_form_screen.dart:254–258` | N/A (UI) | Always requires manager |
| Rewrite `credit_adjust` → `exchange_settled` | `exchange_repository.dart:42–57` | YES | Prevents double-counting in return leg |
| Compose return | `exchange_repository.dart:59–63` | YES | Delegates to `SalesReturnRepository.insertReturn(txn:)` |
| Compose new sale | `exchange_repository.dart:76–82` | YES | Delegates to `SaleRepository.insertSaleWithItems(txn:)` |
| Customer balance (price difference) | `exchange_repository.dart:97–128` | YES | Single consolidated adjustment |
| Insert exchange record | `exchange_repository.dart:130` | YES | |
| **Audit** | **`exchange_repository.dart:132–138`** | **YES — but no financial detail** | **G7: no amounts, no method, no approver, no price difference** |
| Sync queue | `exchange_repository.dart:140` | YES | |

**Defects found:**
- **D5 (P3-C1):** `approvedByUserId` is `String?` and is never validated. A direct caller can process any exchange without approval.
- **D6 (P3-C2, G7):** Audit row at line 132 carries only `userId`, `actionType`, `tableName`, `recordId`. No `newValue` — no record of amounts, refund method, settlement method, price difference, or approver. This audit row is forensically useless.

---

## 4. CASH MANAGEMENT UI STATUS

| Component | Exists? | Location |
|---|---|---|
| `CashManagementService` | YES | `lib/services/cash_management_service.dart` — fully tested (21 tests) |
| `CashMovementRepository` | YES | `lib/repositories/cash_movement_repository.dart` — all source types supported |
| `ApprovalService` integration | YES | Service calls `authorise()` / `authoriseAlways()` inside transaction |
| **Screen** | **NO** | No file exists |
| **Route** | **NO** | No `/cash-management` route in `app_router.dart` |
| **Navigation entry** | **NO** | No sidebar tile in `app_scaffold.dart` (lines 112–149) |
| **Provider** | **NO** | No Riverpod provider for a cash management UI exists |

**Conclusion:** `CashManagementService` is a complete, tested, approval-gated service with no way to reach it from the application. P3-C3 must build the screen, route, navigation, and provider layer.

---

## 5. TILL vs BUSINESS CASH MODEL

**Current architecture:**

| Concept | Where it lives | How it's measured |
|---|---|---|
| **Till cash** (physical notes in the drawer) | `sessions` table | `openingCash + CashMovementRepository.getSessionNet(sessionId)` |
| **Business cash** (total cash the company holds) | GL account `1000` (Cash) | `SUM(debit) - SUM(credit)` on GL entries for account 1000 |
| **The difference** | Conceptual — validated in integration tests | GL Cash − Till Movement = drops to safe (AD-5) |

**Key invariant** (from `accounting_integration_test.dart:268–271`):
```
GL Cash movement = till movement + dropped-to-safe
```

A drop to the safe leaves the till (reduces `getSessionNet`) but NOT the business (no GL entry, per AD-5). So the two figures differ by exactly the amount dropped. This invariant is tested and passing but is NOT visible in any UI.

**Schema support:**
- `cash_movements.counterparty` (v35) records where dropped cash went (e.g., `'Main safe'`)
- `cash_movements.reason` (v35) records why
- No "safe balance" table or account exists — the safe total is derivable as `SUM(drops) − SUM(transfers back)` but not materialised

**v35 is sufficient for P3.** The existing columns support all needed cash management operations. No v36 migration is required.

---

## 6. EXISTING ROUTES (P3-relevant)

| Route | Min Role | In Sidebar? | Notes |
|---|---|---|---|
| `/returns` | Any logged-in | YES (line 138) | List screen |
| `/returns/form` | Any logged-in | Via list | `?saleId=` optional — untied if absent |
| `/sales-cancellations` | Any logged-in | YES (line 139) | List screen |
| `/sales-cancellations/form` | Any logged-in | Via list | `?saleId=` optional |
| `/exchanges` | Any logged-in | YES (line 140) | List screen |
| `/exchanges/form` | Any logged-in | Via list | `?saleId=` required |
| `/credit/receive-payment` | Any logged-in | Via customers | Covered by P2 |
| `/cash-management` | **Does not exist** | **NO** | P3-C3 must create |

**Observation:** Returns, cancellations, and exchanges are open to all logged-in roles including cashier. This is correct — the *route* is not the authorization boundary; the *approval dialog* (currently) and the *service layer* (after P3-C1) are. A cashier may initiate a return but must obtain manager approval for amounts above threshold or for cancellations/exchanges.

---

## 7. EXISTING PERMISSIONS

**Role hierarchy** (`app_router.dart:79–89`):
- `admin` (rank 0) → full access
- `manager` (rank 1) → everything except `/users` and admin-only utilities
- `cashier` (rank 2) → billing, counters, customers, returns, cancellations, exchanges, credit payment, sales history/summary, quotations, holds
- `accountant` (rank 3) → narrow allowlist: reports, sales history, customers, suppliers, exports, verify data

**Approval roles** (`approval_service.dart:55`): `{'admin', 'manager'}`

**`requireApprovalWithApprover`** (`price_override_guard.dart`): UI dialog. Takes `BuildContext` and `WidgetRef`. Returns `User?` (the approving user) or `null` (cancelled). Cannot be used at the service/repository level.

---

## 8. EXISTING SERVICES (P3-relevant)

| Service | File | Approval Integration | Status |
|---|---|---|---|
| `ApprovalService` | `lib/services/approval_service.dart` | IS the approval service | P2 — complete |
| `CashManagementService` | `lib/services/cash_management_service.dart` | Calls `authorise()` / `authoriseAlways()` | P2 — complete, no UI |
| `GLService` | `lib/services/gl_service.dart` | N/A | P2 — complete |
| `CounterService` | `lib/services/counter_service.dart` | N/A (shift open/close) | P1 — complete |

---

## 9. EXISTING REPOSITORIES (P3-relevant)

| Repository | File | Approval? | Audit? | GL? | Cash Book? |
|---|---|---|---|---|---|
| `SalesReturnRepository` | `lib/repositories/sales_return_repository.dart` | **NO** | **NO** (screen does it outside txn) | YES | YES (cash only) |
| `SaleCancellationRepository` | `lib/repositories/sale_cancellation_repository.dart` | **NO** | YES (inside txn) | YES | YES (capped) |
| `ExchangeRepository` | `lib/repositories/exchange_repository.dart` | **NO** | YES (inside txn, but no detail) | YES (via composed return+sale) | YES (via composed return+sale) |
| `CustomerRepository` | `lib/repositories/customer_repository.dart` | YES | YES | YES | YES (cash only) | 
| `CashMovementRepository` | `lib/repositories/cash_movement_repository.dart` | N/A (writer only) | N/A | N/A | IS the cash book |

---

## 10. EXISTING TESTS (P3-relevant)

| Test file | Count | What it covers |
|---|---|---|
| `test/services/approval_enforcement_test.dart` | 19 | `ApprovalService` rules: threshold, roles, deactivated, below-threshold |
| `test/services/cash_management_service_test.dart` | 21 | All 5 operations, approval gates, open-session guards |
| `test/services/counter_service_test.dart` | 13 | Shift open/close, expected cash from `getSessionNet` |
| `test/repositories/cash_movement_repository_test.dart` | 21 | Cash book: sales, returns, cancellations, collections, direction, session isolation |
| `test/repositories/sale_cancellation_repository_test.dart` | 11 | Duplicate protection, stock reversal, customer reversal, GL reversal, cash cap |
| `test/repositories/exchange_repository_test.dart` | 2 | Basic exchange flow (positive and negative price difference) |
| `test/repositories/customer_payment_test.dart` | 25 | Payment recording, approval enforcement, balance updates |
| `test/repositories/customer_payment_gl_test.dart` | 12 | GL posting for customer payments: cash/UPI/card/split/advance |
| `test/repositories/cancellation_accounting_test.dart` | 6 | Cancellation GL reversal, balanced entries |
| `test/integration/financial_integration_test.dart` | 1 (9 steps) | Full shift: sale → return → cancellation → customer payment → close → reconcile |
| `test/integration/accounting_integration_test.dart` | 1 (11 steps) | Full shift: cash sale → credit sale → collections → refund → drop → expense → cancel → close → reconcile |
| `test/services/gl_settlement_test.dart` | 12 | Settlement account routing for all payment methods |

**No existing tests for:**
- Approval enforcement on returns (repository level)
- Approval enforcement on cancellations (repository level)
- Approval enforcement on exchanges (repository level)
- Return audit row completeness
- Exchange audit row financial detail

---

## 11. DEFECTS FOUND

### CRITICAL — Approval Bypass (P3-C1)

| ID | Operation | Location | Description |
|---|---|---|---|
| D1 | Sales return | `sales_return_repository.dart:45–58` | `approvedByUserId` is accepted as-is. No call to `ApprovalService`. A direct caller can process any return without authorization. |
| D4 | Sale cancellation | `sale_cancellation_repository.dart:35–42` | `approvedByUserId` is `String?` — optional and unvalidated. A direct caller can cancel any sale without authorization. |
| D5 | Exchange | `exchange_repository.dart:20–28` | `approvedByUserId` is `String?` — optional and unvalidated. A direct caller can process any exchange without authorization. |

### HIGH — Audit Integrity (P3-C2)

| ID | Operation | Location | Description |
|---|---|---|---|
| D2 | Sales return audit | `return_form_screen.dart:297–305` | Audit row written OUTSIDE the transaction, ONLY when `approvedByUserId != null`. Below-threshold returns and non-screen callers leave no audit trail. A crash between DB commit and audit write produces a refund with no trace. |
| D6 | Exchange audit detail | `exchange_repository.dart:132–138` | Audit row has no `newValue` — no amounts, settlement method, price difference, or approver. Forensically useless. |

### MEDIUM — Missing UI (P3-C3)

| ID | Component | Description |
|---|---|---|
| D7 | Cash management screen | `CashManagementService` has no UI, no route, no navigation entry. All five operations are unreachable from the app. |

### LOW — Visibility (P3-C4)

| ID | Component | Description |
|---|---|---|
| D8 | Till vs business cash | The distinction is validated in integration tests but never surfaced to the user. No screen or report shows the reconciliation. |

---

## 12. RISKS

| Risk | Severity | Mitigation |
|---|---|---|
| Adding `ApprovalService` calls to repositories changes the method signature (requires `approvedByUserId` or `DatabaseExecutor`) | MEDIUM | The three repositories already accept `approvedByUserId` as an optional parameter. Making it validated does not change the caller contract — it changes what happens when the parameter is wrong. Existing callers (the screens) already supply a validated approver from the dialog. |
| Moving the return audit into the repository transaction changes when it fires | LOW | Existing behavior is buggy (fires outside txn, only when approver is non-null). Moving it inside is a correctness fix, not a behavior change. No existing test asserts the old behavior. |
| Cash management screen must gate on role | LOW | Route gating follows the existing `_routeMinRole` pattern. Service already enforces approval. |
| Exchange audit `newValue` addition changes the audit row shape | LOW | No existing code reads exchange audit `newValue` — it was always null. Adding it is additive. |

---

## 13. PROPOSED IMPLEMENTATION

### Phase 1: P3-C1 — Universal Financial Approval Enforcement

**Strategy:** Add `ApprovalService` calls inside each repository's transaction, matching the pattern `CustomerRepository.receivePayment` already uses (P2-C4).

1. `SalesReturnRepository.insertReturn`:
   - Accept the `refundAmount` (already on header) and use `ApprovalService.authorise()` inside the transaction
   - Threshold-gated: below threshold, cashier acts alone; above, manager required
   - Untied returns (`isUntied == true`): always require manager (matches current screen behavior)
   - Move audit into the transaction (fixes D2 simultaneously)

2. `SaleCancellationRepository.cancelSale`:
   - Add `ApprovalService.authoriseAlways()` inside the transaction (cancellation always requires manager, matching current screen behavior)
   - Audit is already inside txn — no change needed

3. `ExchangeRepository.processExchange`:
   - Add `ApprovalService.authoriseAlways()` inside the transaction (exchange always requires manager, matching current screen behavior)
   - Enrich audit `newValue` with financial detail (fixes D6)

**Testing:** Write failing tests first for each defect (D1, D4, D5), demonstrating that direct repository calls currently bypass approval. Fix. Verify.

### Phase 2: P3-C2 — Returns/Refunds/Exchanges Audit & Accounting Integrity

**Strategy:** Fix D2 and D6 (may overlap with Phase 1 since the approval fix naturally touches the same code paths).

1. Move return audit into `_insertReturnBody` inside the transaction
2. Write audit for ALL returns, not just approved ones (below-threshold returns still deserve a trace)
3. Enrich exchange audit with amounts, settlement method, price difference, approver

**Testing:** Write tests asserting audit rows exist for below-threshold returns, above-threshold returns, and exchanges with financial detail.

### Phase 3: P3-C3 — Cash Management UI

**Strategy:** Build a screen exposing `CashManagementService`'s five operations.

1. Create `lib/features/cash_management/screens/cash_management_screen.dart`
2. Add route `/cash-management` gated to `UserRole.manager` in `app_router.dart`
3. Add sidebar tile in `app_scaffold.dart`
4. Create Riverpod provider for state management
5. Sections: Cash In, Cash Out, Cash Drop, Transfer, Manual Adjustment, History
6. History section shows `manualMovementsForSession` for the active shift

**Testing:** UI testing is out of scope for sqflite-based tests. Service is already fully tested. Visual verification required.

### Phase 4: P3-C4 — Till vs Business Cash Reconciliation & Audit Visibility

**Strategy:** Surface the till/business cash distinction in the shift close flow or in a dedicated view.

1. Show till cash (session net + opening) alongside GL cash on shift close
2. Show drops as the reconciling item
3. Cash management history provides the line-by-line breakdown

**Testing:** Integration test already validates the invariant. UI verification required.

---

## 14. DECISIONS REQUIRING APPROVAL

### AD-P3-1: Return approval threshold rule

**Question:** Should the repository-level return approval threshold use the same rule as the screen?
**Current screen rule:** `needsApproval = isUntied || refundAmount > threshold`
**Proposed repository rule:** Same — `authorise(amount: refundAmount, ...)` for tied returns (threshold-gated), `authoriseAlways(...)` for untied returns.
**Recommendation:** Match the screen exactly. The threshold is already in `stores.return_threshold_no_approval` and `ApprovalService.authorise()` already reads it.
**Risk of divergence:** If repository uses a different rule, the screen's dialog would fire when the repository wouldn't enforce (or vice versa), confusing users.

### AD-P3-2: Cancellation approval rule

**Question:** Should cancellation always require a manager at the repository level?
**Current screen behavior:** Always requires manager (no threshold exemption).
**Proposed:** `authoriseAlways()` — matching screen behavior.
**Recommendation:** Yes. A full sale cancellation is destructive and should always require authorization.

### AD-P3-3: Exchange approval rule

**Question:** Should exchange always require a manager at the repository level?
**Current screen behavior:** Always requires manager.
**Proposed:** `authoriseAlways()` — matching screen behavior.
**Recommendation:** Yes. An exchange composes a return with a new sale; it is at least as sensitive as a cancellation.

### AD-P3-4: Cash management route minimum role

**Question:** What minimum role should access `/cash-management`?
**Proposed:** `UserRole.manager` — matching other write-capable operational routes.
**Rationale:** `CashManagementService` already enforces approval via `ApprovalService` inside transactions. The route gate is a navigation convenience, not a security boundary. However, a cashier seeing cash management options they can't use (because the service would refuse without a manager approver) is confusing. Gating to manager keeps the UI honest.
**Alternative:** `UserRole.cashier` for read/history only, manager for write operations. More complex, probably not needed for V1.

### AD-P3-5: Return audit for below-threshold tied returns

**Question:** Should below-threshold tied returns (currently no audit at all) get an audit row?
**Proposed:** YES — every return should be auditable regardless of amount.
**Current state:** Only returns where the screen obtained `approvedByUserId` get an audit row. A ₹100 return against a ₹100 threshold leaves no trace.
**Recommendation:** Write an audit row for every return, inside the transaction. The `actionType` can distinguish `SALES_RETURN_PROCESSED` (any return) from approval-specific audit (which the approval enforcement naturally records).

---

## 15. EXPLICITLY OUT OF SCOPE

Per the user's specification, the following are NOT part of P3:

- GST overhaul, GSTR-1, GSTR-3B, HSN/SAC overhaul
- `double`-to-`Decimal` migration
- Global dependency injection refactor
- Entire route authorization rewrite (we add approval to 3 repositories, not rewrite the router)
- `billing_screen.dart` rewrite
- Product / purchase / supplier / stock architecture refactor
- Performance optimization, cloud architecture, Firebase/Supabase changes
- Payment gateway redesign
- Unrelated UI redesign or reports
- Price override / discount approval (screen-only, noted as MEDIUM risk but explicitly out of scope)
- v36 schema migration (v35 is sufficient)

---

## APPENDIX: FILE REFERENCE

| File | Relevance |
|---|---|
| `lib/services/approval_service.dart` | P3-C1: the service all three repos must call |
| `lib/repositories/sales_return_repository.dart` | P3-C1/C2: needs approval + audit fix |
| `lib/repositories/sale_cancellation_repository.dart` | P3-C1: needs approval |
| `lib/repositories/exchange_repository.dart` | P3-C1/C2: needs approval + audit enrichment |
| `lib/features/returns/screens/return_form_screen.dart` | P3-C1: screen that currently owns the approval check |
| `lib/features/sales_cancel/screens/sale_cancel_form_screen.dart` | P3-C1: screen that currently owns the approval check |
| `lib/features/exchange/screens/exchange_form_screen.dart` | P3-C1: screen that currently owns the approval check |
| `lib/core/permissions/price_override_guard.dart` | Contains `requireApprovalWithApprover()` — UI-only |
| `lib/core/routes/app_router.dart` | P3-C3: needs new route |
| `lib/core/widgets/app_scaffold.dart` | P3-C3: needs new sidebar tile |
| `lib/services/cash_management_service.dart` | P3-C3: the service the UI will front |
| `lib/repositories/cash_movement_repository.dart` | P3-C3/C4: cash book queries |
| `lib/services/counter_service.dart` | P3-C4: shift close flow |
| `lib/models/sales_return_model.dart` | Has `approvedByUserId` field |
| `lib/constants/app_constants.dart` | `dbVersion = 35` — confirmed sufficient |
