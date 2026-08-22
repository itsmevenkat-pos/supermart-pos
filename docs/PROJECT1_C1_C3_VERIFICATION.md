# Project 1 — Critical Financial Control Verification & Hardening

**Date:** 2026-08-16 · **Scope:** verify and harden the already-implemented C1/C2/C3 fixes from `AUDIT_2026-08-16.md`
**Method:** static review of every cash/GL writer, then real `sqflite_common_ffi` tests against the actual repositories, services and database transactions. No mocks of application logic; no arithmetic-only tests.

---

## 1. Baseline

Measured before any change was made.

| | Result |
|---|---|
| Tests | **478 passed, 0 failed** |
| Analyzer errors | **0** |
| Analyzer warnings | **0** |
| Analyzer info | **138** |

Matches the reported baseline exactly. No investigation of a discrepancy was needed.

---

## 2. C1 — Cash reconciliation

**Status: PASS** (after one correction)

### What was already correct

The `cash_movements` table (`MigrationV34`) and `CashMovementRepository` are a sound single-writer design. All five cash writers were verified wired and correct:

| Writer | Direction | Amount | Session | User |
|---|---|---|---|---|
| `SaleRepository.insertSaleWithItems` | in | cash leg of `payment_methods` only | from the sale | from the sale |
| `CustomerRepository.receivePayment` | in | full amount, cash method only | passed, else inferred from the open shift | passed |
| `SalesReturnRepository.insertReturn` | out | `refundAmount`, cash method only | from the return header, else inferred | from the header |
| `SaleCancellationRepository.cancelSale` | out | see correction below | from the sale | from the canceller |
| `ExchangeRepository.processExchange` | both legs | via the composed return + sale | inherited | inherited |

Opening cash is not a movement — it lives on `sessions.opening_cash` and is added to the ledger net. Correct: it is a starting balance, not a transaction.

Exchange double-counting was checked specifically. A cash-settled exchange writes both legs gross (return out, replacement sale in) and they net to the price difference — the only amount that actually crosses the counter. A `credit_adjust` exchange writes nothing, because `ExchangeRepository` rewrites the return's method to `exchange_settled` and the replacement sale carries no payment methods. Both verified by test.

### Defect found and corrected

**`CounterService.closeShift` still used the sales-only figure.** `counter_close_screen.dart` was updated to read `CashMovementRepository.getSessionNet`, but the service that actually *computes, persists and derives the shortage from* expected cash still called `SaleRepository.getCashTotalBySession`, which filters `source_type = 'sale'`. That method's own docstring says "shift reconciliation must NOT use this" — and reconciliation was using it.

So the number on screen was right while the number written to `sessions.expected_cash`, the `difference` used to flag shrinkage, and the day-end report printed from it were all still blind to khata collections and cash refunds. C1 was fixed in the display layer and open in the record.

Proven, not assumed: reverting only this change fails 5 of the 13 new tests, including
- a ₹5,000 khata collection reading as expected ₹2,000 instead of ₹7,000 (the original audit scenario, pocketable in full), and
- an honest ₹200 cash refund reading as a ₹200 overage.

**Fix:** `lib/services/counter_service.dart` now computes `expectedCash = openingCash + CashMovementRepository.getSessionNet(sessionId)`. One definition, one source.

### Acceptance criteria

| Criterion | Result |
|---|---|
| All cash writers identified | ✅ 5 writers, table above |
| Correct session attribution | ✅ incl. inference from the open shift when unstamped |
| Khata collection affects expected cash | ✅ C1-03 |
| Cash refunds affect expected cash correctly | ✅ C1-04 |
| Cancellation behaves correctly | ✅ C1-05 (behaviour corrected, see §4) |
| Exchange not double-counted | ✅ C1-06, both settlement methods |
| Sessions isolated | ✅ C1-07 |
| Failed transactions roll back | ✅ C1-08, two failure paths |
| Duplicate movements prevented | ✅ C1-09 |
| Counter close uses the intended source | ✅ **this was the defect** |
| Existing tests still pass | ✅ |

### Tests added

- `test/services/counter_service_test.dart` — **new**, 13 tests (C1-01, 02, 03, 03b, 04, 07 + non-cash/credit/split-bill cases, ledger-derived assertion, lifecycle guards)
- `test/repositories/cash_movement_repository_test.dart` — **extended**, 10 → 21 tests (C1-05 ×4, C1-06 ×2, C1-08 ×2, C1-09 ×3)

### Remaining risk

- **No manual cash movement writer exists.** `CashMovementSource.manualAdjustment` is defined and the repository supports it, but nothing in `lib/` writes one — there is no till pay-out, cash drop or safe-transfer screen. Any such movement today is invisible to reconciliation and will read as a shortage. Not a regression; a gap.
- **No unique constraint on `(source_type, source_id)`.** Idempotency is enforced upstream (the `sales` primary key, the already-cancelled guard) rather than by the cash table. That holds for every current writer but would not stop a future one.

---

## 3. C2 — Receive-payment control

**Status: PASS, with one criterion PARTIAL** (named below rather than glossed)

### What was already correct

`receive_payment_screen.dart` reads the configurable threshold from `StoreRepository.getReturnThreshold()`, escalates above it through `requireApprovalWithApprover`, resolves the open shift via `CounterService.getActiveSession`, and passes collector, approver and session into the repository, which writes a `CUSTOMER_PAYMENT_RECEIVED` audit row inside the payment transaction. The route is deliberately left ungated so cashiers can collect normal khata payments — the stated business decision, and correct.

Credit-limit protection in `customer_form_screen.dart` is correctly conditioned: the approval gate fires only when the requested limit **exceeds** the previous one, so creating a walk-in, editing details and lowering a limit stay open to cashiers. Refusal keeps the old limit rather than discarding the whole edit. The two other write paths to `credit_limit` (`import-parties`, `import-tally`) are role-gated at manager/admin in `_routeMinRole`.

### Defects found and corrected

1. **A claimed approver was never checked.** `approvedByUserId` was accepted verbatim and written into the audit row. Any caller could stamp any id — including a cashier's own — and produce an audit trail asserting a manager signed off. An approval record that can be forged is worse than none, because it is believed. `receivePayment` now verifies the approver exists, holds `admin` or `manager`, and is active; otherwise the whole payment rolls back.
2. **A payment had no reference of its own.** The cash movement's `source_id` was the *customer* id and each ledger row got a throwaway UUID, so a customer's tenth collection was indistinguishable from their first and no drawer figure could be walked back to the receipt that caused it. `receivePayment` now mints one `paymentRef` shared by the ledger row(s), the cash movement and the audit row, and returns it.

### Acceptance criteria

| Criterion | Result |
|---|---|
| Normal cashier collection works | ✅ C2-01 |
| Approval threshold works | ⚠️ **PARTIAL** — the store setting and the `amount > threshold` boundary are tested; the dialog itself is not (see below) |
| Unauthorized approval fails | ✅ C2-04 ×5 (cashier self-approval, peer cashier, accountant, deactivated manager, nonexistent user) |
| Approver recorded | ✅ C2-03, C2-08 |
| Collector recorded | ✅ on the audit row and the cash movement |
| Session recorded | ✅ incl. inference and the no-shift case |
| Audit row recorded | ✅ C2-08, with both balances, method, note, reference, session, approver, timestamp |
| Duplicate payment prevented | ✅ C2-06 — two collections are two distinct receipts, each independently traceable |
| Transaction rollback works | ✅ C2-07 — a rejected approval leaves balance, ledger, drawer *and audit log* untouched |
| Credit-limit escalation protected | ⚠️ **PARTIAL** — gate verified by inspection and its rule pinned by test; the dialog is not widget-tested |
| Existing cashier workflow usable | ✅ |

### The PARTIAL, stated plainly

`requireApprovalWithApprover` and the credit-limit gate both need a `BuildContext`. This repository has **zero widget tests**, because repositories and services are constructed directly inside widgets (audit finding H4) and cannot be substituted. So the *prompt* — that it appears above the threshold, and that a cashier cannot dismiss past it — is verified by code reading only, not by test.

What is tested is everything on both sides of it: the threshold value the screen reads, the boundary rule, and the fact that the resulting approval cannot be forged. Closing the remainder needs H4, which belongs to a later project.

### Tests added

- `test/repositories/customer_payment_test.dart` — **new**, 20 tests (C2-01 ×2, C2-02 ×2, C2-03 ×2, C2-04 ×5, C2-05 ×2, C2-06/07 ×3, C2-08 ×2, credit-limit workflow ×2)

### Remaining risk

- **Khata collections post nothing to the GL.** A cash receipt moves the customer ledger and the drawer but writes no `gl_entries` row, so GL Accounts Receivable diverges from the customer ledger the moment a payment is taken. This is *not* something C1/C2/C3 introduced and is not in the audit's C2 fix list, but it is material and is now pinned by an explicit assertion in the integration test so the day it is fixed, that expectation fails and is updated deliberately. Fixing it is an accounting decision (which accounts; how advances are represented) and belongs in the same piece of work as the three accounting questions Phase 2 escalated.
- The approval gate remains **UI-side for the threshold**. The repository now validates *who* approved but not *whether* approval was required. A non-screen caller can still take a ₹50,000 receipt with no approver at all.

---

## 4. C3 — Sale cancellation GL reversal

**Status: PASS** (after one correction)

### What was already correct

`SaleCancellationRepository.cancelSale` calls `GLService.reverseByReference(GLService.saleReferenceType, sale.id, …)` with the cancellation's own `txn`, so the ledger commits or rolls back with the cancellation. `reverseByReference` skips lines already reversed, and reversals inherit the original's reference type/id, date and financial year. Double-cancellation is blocked by the fresh-read status guard, and cancelling a sale with a return against it is refused.

Verified by test: reversals are exact mirrors (same account, debit ↔ credit, same financial year), each points at the line it undoes, each original is reversed exactly once, a replayed `reverseByReference` returns empty and adds no rows, and every touched account nets to zero.

### Defect found and corrected

**A cancelled credit sale paid out cash that was never taken.** The cash movement used `cancellation.refundAmount` (always the full `netAmount`) whenever the operator picked "cash" on the cancel form — regardless of how the sale was actually paid. Cancelling a ₹300 credit sale therefore cleared the ₹300 receivable *and* took ₹300 out of the drawer: the shop paid ₹300 for its own void. The same applied to the non-cash leg of a split bill.

**Fix:** the payout is capped at the cash the sale actually took, read from the sale's own `payment_methods`. `sale_cancellations.refund_amount` is deliberately left at the full value — that is the total refunded across all methods; only the *cash book* row is capped.

> ⚠️ **This is a behaviour change and should be confirmed as intended.** It is the only change in this project that alters what the application does rather than what it records. The reasoning: for a full void there is no reading under which returning more cash than was received is correct. If the shop's actual practice is to settle credit-sale cancellations in cash, that is a receivable settlement and belongs in the receive-payment flow, not the cancellation.

### Acceptance criteria

| Criterion | Result |
|---|---|
| Original GL exists | ✅ asserted before every reversal check |
| Cancellation creates reversal | ✅ |
| Correct reference | ✅ C3-02 |
| Correct amount | ✅ C3-03, exact mirror per line |
| No duplicate reversal | ✅ C3-04/05 |
| Transaction rollback works | ✅ C3-06 |
| Cash sale works | ✅ C3-07 |
| Credit sale works | ✅ C3-08 |
| Tax/discount sale works | ✅ C3-09 |
| Stock/customer/GL consistent | ✅ |

The rollback test (C3-06) is the strongest of these: it closes the financial year so `GLService` refuses to post, which makes the reversal throw from inside the cancellation transaction *after* stock, customer balance, loyalty points, sale status, the cancellation row and the audit row have all been written. All seven are verified back to their prior state, and the sale is still `completed`.

### Tests added

- `test/repositories/sale_cancellation_repository_test.dart` — **extended**, 4 → 11 tests (C3-02, 03, 04/05, 06, 07, 08, 09)

### Remaining risk

- Cancellation reverses the sale's GL but posts **no** entry for the refund itself. That is correct for a full void, but it means the cash book and the GL cash account disagree by the refunded amount for a cash cancellation — the same class of divergence as the khata-collection gap above.

---

## 5. Cross-module integration

**Status: PASS** — `test/integration/financial_integration_test.dart`, 1 test, 9 steps, one continuous shift.

Every figure is derived from the state the previous step actually left in the database.

| # | Operation | Amount | Method | Cash movement | Customer | Stock | GL | Session | User |
|---|---|---|---|---|---|---|---|---|---|
| 1 | Open shift | ₹2,000 float | — | none (opening balance) | — | — | — | created | cashier |
| 2 | Create Ravi | — | — | — | balance 0 | — | — | — | cashier |
| 3 | Create Demo Product | ₹100 | — | — | — | 100 | — | — | cashier |
| 4 | Cash sale, qty 2 | ₹200 | cash | **+200** | — | 100 → 98 | Dr Cash 200 / Cr Revenue 200 | stamped | cashier |
| 5 | Credit sale, qty 3 | ₹300 | credit | none | 0 → 300 owed | 98 → 95 | Dr AR 300 / Cr Revenue 300 | stamped | cashier |
| 6 | Collect khata | ₹150 | cash | **+150** | 300 → 150 owed | — | *none* ⚠️ | stamped | cashier |
| 7 | Cash refund | ₹50 | cash | **−50** | — | 95 (not restocked) | Dr Revenue 50 / Cr Cash 50 | stamped | cashier, mgr-approved |
| 8 | Cancel the credit sale | ₹300 | cash chosen | **none** (no cash was taken) | 150 owed → 150 **advance** | 95 → 98 | all 4 lines reversed, nets 0 | stamped | cashier, mgr-approved |
| 9 | Close shift | — | — | net **+300** | — | — | — | closed | cashier |

**Close:** expected ₹2,300 = ₹2,000 + 200 + 150 − 50. Counted ₹2,300. Difference ₹0.
**Shift revenue:** GL Sales Revenue nets ₹150 = the ₹200 cash sale less the ₹50 refund; the credit sale and its reversal cancel out. Correct.
**Cash book:** three rows, all carrying session and user, and replaying them from the opening float reproduces `expected_cash` exactly.

Step 8 produces the one result worth stating out loud: Ravi had paid ₹150 toward a sale that was then voided, so he ends the shift ₹150 **in credit**. The shop owes him. That is the correct outcome, not a defect.

⚠️ Step 6 is the documented divergence: GL Accounts Receivable reads 0 while Ravi's ledger holds a ₹150 advance, because customer payments post no GL entry. Asserted explicitly in the test rather than left silent.

---

## 6. Final test result

| | Result |
|---|---|
| Tests passed | **530** |
| Tests failed | **0** |

Baseline 478 → 530. **+52 tests**, all exercising real repositories, services, transactions and business state.

---

## 7. Analyzer

| | Baseline | Final |
|---|---|---|
| Errors | 0 | **0** |
| Warnings | 0 | **0** |
| Info | 138 | **138** |

The new test code initially added 6 `prefer_const_literals_to_create_immutables` hints; those were cleaned up so this project adds no analyzer noise. No pre-existing issue was touched.

---

## 8. Files changed

**Modified — `lib/` (3):**
- `lib/services/counter_service.dart` — expected cash from the cash movement ledger (C1)
- `lib/repositories/customer_repository.dart` — approver validation, shared payment reference, richer audit payload; `receivePayment` now returns the reference (C2)
- `lib/repositories/sale_cancellation_repository.dart` — cash refund capped at the cash the sale took (C1/C3)

**Modified — `test/` (2):**
- `test/repositories/cash_movement_repository_test.dart` — 10 → 21 tests
- `test/repositories/sale_cancellation_repository_test.dart` — 4 → 11 tests

**Created — `test/` (3):**
- `test/services/counter_service_test.dart` — 13 tests
- `test/repositories/customer_payment_test.dart` — 20 tests
- `test/integration/financial_integration_test.dart` — 1 test, 9 steps

**Deleted:** none.

No test was deleted, weakened or skipped. No unrelated module, report, UI or repository was touched.

---

## 9. Database changes

**None.** No migration was added, no table or column created, renamed or dropped. Schema version remains **34**; `MigrationV34` is unchanged. All corrections are behavioural and fit the existing schema.

---

## 10. Security impact

**Roles:** unchanged. No route gating was altered; `/credit/receive-payment` and `/customers/form` remain open to cashiers by the existing business decision.

**Approval:** strengthened. A supplied `approvedByUserId` on a customer payment is now verified to be an existing, active `admin` or `manager`; a forged or stale approver rolls the payment back rather than being recorded as genuine. The threshold decision itself is unchanged and still lives in the screen.

**Audit:** strengthened. The `CUSTOMER_PAYMENT_RECEIVED` row now also carries the payment reference and the session id, so a receipt can be joined to its cash movement and its ledger entry. A payment that fails now leaves no audit row at all (previously untested; verified).

**Session attribution:** corrected where it mattered most — the persisted `expected_cash` and `difference` on a closed shift are now derived from session-attributed cash movements rather than from sales alone.

---

## 11. Financial integrity

**Cash.** One table, one writer, one definition. Every path that moves notes writes `cash_movements` inside the transaction that caused it, so a movement cannot outlive a rolled-back sale (verified) and cannot be created without its cause. `expectedCash = openingCash + SUM(signed amount)` is now the single formula, used identically by the close screen and by the service that persists the reconciliation. Non-cash settlement — UPI, card, store credit, `exchange_settled` — writes nothing, so the cash book contains only real notes.

**Customer ledger.** Balance and history move together in one transaction. A sale adds a `sale` row, a payment adds `payment` and/or `advance` rows under one reference, a cancellation adds a compensating `sale_cancellation` row rather than editing history. Every row carries the running balance, so the ledger is independently reconstructible.

**Stock.** Deducted by atomic check-and-decrement, so a losing race fails the whole sale rather than pushing stock negative. Cancellations and restocked returns add compensating `stock_ledger` rows; a non-restocked return moves nothing.

**GL.** Posted with the caller's transaction, so a sale whose ledger post fails fails as a sale. Cancellation reverses by reference, skipping already-reversed lines, and the mirror lands in the same financial year so the year nets out. Verified: every account touched by a cancelled sale returns to zero.

**Where they are known *not* to tie.** Stated rather than implied: GL Accounts Receivable does not follow the customer ledger through a khata collection, and GL Cash does not follow the drawer through one, because customer payments post no GL entry. This predates the C1–C3 work and is now covered by an explicit assertion.

---

## 12. Remaining audit findings — still open

This project verified and hardened **C1, C2 and C3 only**. The audit is not closed.

**Newly identified here (not in the original audit):**
- Customer payments post no GL entry — GL receivable and cash diverge from the ledger and the drawer on every khata collection.
- Sale cancellations post no GL entry for the cash refund itself.
- No manual cash movement writer — no till pay-out, cash drop or safe transfer exists, so any such movement reads as a shortage.
- The receive-payment approval *threshold* is enforced only in the UI; a non-screen caller can bypass it entirely.

**Open from the audit:**
- **H3** — route gating fails open: 23 of 63 routes have no `_routeMinRole` entry, and adding a route grants universal access by default. No test asserts coverage.
- **H4** — repositories and services constructed inside widgets; zero widget tests possible. This is what blocks full verification of the two approval dialogs.
- **M1** — money is `double` throughout (133 fields); "balanced" is an approximation to ±0.01.
- **M2** — five files over 1,000 lines; `billing_screen.dart` at 1,847.
- **M3** — migrations split between extracted files and inline blocks; no v1→v34 round-trip test.
- **M4** — Razorpay key secret in plaintext SQLite; placeholder OAuth secret compiled in.
- **M5** — 20 silent `catch (_)` sites, including in `sale_repository.dart`.
- **M6** — GST is an 11-line stub: no CGST/SGST/IGST split, no HSN/SAC, no GSTR-1/3B. Largest single gap, with statutory exposure.
- **M7** — repository/service test coverage gaps remain across 17 repositories and 28 services.
- The three Phase 2 accounting questions (loyalty liability, gateway fees, commission) are still undecided.

**Explicitly out of scope and untouched, as instructed:** GST and GST reports, GSTR-1/3B, H4/Riverpod architecture, money-as-double migration, `billing_screen.dart` refactor, Razorpay secret architecture, unrelated reports, unrelated UI, unrelated repositories.
