# Project 2 — Accounting Reconciliation, Cash Management & Approval Enforcement

**Date:** 2026-08-17 · **Baseline:** Project 1 (530 tests, analyzer 0/0/138, schema v34)
**Final:** 606 tests passing, 0 failing · analyzer 0 errors / 0 warnings / 138 info · schema **v35**

---

## 1. Executive Summary

Four objectives, all met, plus one substantial defect found during inspection that none of them named.

That defect is the headline. **The GL had no notion of payment method.** It knew only "receivable" versus "not receivable" and booked everything else to Cash 1000 — while Project 1's cash book used the far stricter rule `method == 'cash'`. So GL Cash was neither the drawer nor the bank: overstated by every UPI and card sale, understated by every UPI and card refund, and impossible to reconcile against the cash movement ledger. A four-transaction test shift moved GL Cash by ₹850 against a real drawer movement of ₹300.

That one root cause explained most of what Project 1 left open, including the item Project 1 flagged as "cancellation posts no GL entry for the refund". On inspection **that diagnosis was wrong**, and acting on it would have made things worse: for a cash sale the reversal's own `Cr Cash` *is* the refund, so adding a second entry would have paid it twice. What was broken was the original posting. Fixing that made the reversal correct by construction and required no new cancellation entry at all.

The other three objectives:

- **Customer payments now post to the GL.** The divergence Project 1 documented and pinned with a deliberate failing-when-fixed assertion is closed. Accounts Receivable and the customer ledger now agree, always.
- **Manual cash management exists.** Drops, transfers, payouts, top-ups and adjustments can be recorded, attributed, approved and reconciled — closing the gap that made every real-world till payout surface as an unexplained shortage.
- **The approval threshold moved from the screen to the service.** Project 1's own closing risk — "a non-screen caller can still take a ₹50,000 receipt with no approver at all" — is now refused by the repository, inside the transaction.

Four accounting decisions were escalated rather than guessed, and all four were approved as recommended before any code was written.

---

## 2. Project 1 Baseline

Re-verified before inspection began, not taken on trust.

| | Recorded |
|---|---|
| Tests | 530 passed, 0 failed |
| Analyzer | 0 errors, 0 warnings, 138 info |
| Schema | v34 |

---

## 3. Phase 0 Inspection Findings

Full inspection output is in [`PROJECT2_PHASE0_INSPECTION.md`](PROJECT2_PHASE0_INSPECTION.md), including the complete writer census. Ten gaps were identified and labelled G1–G10; seven were addressed in this project.

| | Gap | Status |
|---|---|---|
| **G1** | Non-cash sales debit GL Cash | **Fixed** |
| **G2** | Non-cash refunds credit GL Cash | **Fixed** |
| **G3** | Customer payments post nothing to the GL | **Fixed** |
| **G4** | Credit-adjusted exchange credits Cash and skips AR entirely | **Fixed** |
| **G5** | No manual cash movements can be recorded | **Fixed** |
| **G6** | Sales-return audit row written by the screen, outside the transaction, approver-only | **Open** — see §16 |
| **G7** | Exchange audit row carries no financial detail | **Open** — see §16 |
| **G8** | `receivePayment` accepted only one payment method | **Fixed** |
| **G9** | Shift shortage/overage posts nowhere | **Open by decision** — AD-5 |
| **G10** | Sales are never audited | **Open by design** — the `sales` table is the record |

Ruled out as non-writers, so they could stop being suspects: `CollectionsRepository`/`CollectionsService` (read-only over `customer_ledger`), `PaymentGatewayService` (posts GL, never touches customer balance or cash book), `PurchaseRepository` (Inventory/AP, out of scope).

---

## 4. Financial Transaction Map

Post-change. `✓` = covered by a passing test in this project or Project 1.

| Transaction | Customer Ledger | Cash Book | GL | Stock | Audit | Session |
|---|---|---|---|---|---|---|
| Cash sale | — | ✓ in | ✓ Dr **Cash** / Cr Revenue | ✓ | — | ✓ |
| UPI sale | — | ✓ nothing | ✓ Dr **Bank** / Cr Revenue | ✓ | — | ✓ |
| Card sale | — | ✓ nothing | ✓ Dr **Bank** / Cr Revenue | ✓ | — | ✓ |
| Split sale (cash + UPI) | — | ✓ cash leg only | ✓ Dr Cash + Dr Bank / Cr Revenue | ✓ | — | ✓ |
| Credit sale | ✓ +net | ✓ nothing | ✓ Dr AR / Cr Revenue | ✓ | — | ✓ |
| Part-cash part-credit sale | ✓ +unpaid | ✓ cash leg | ✓ Dr Cash + Dr Bank + Dr AR / Cr Revenue | ✓ | — | ✓ |
| Khata collection — cash | ✓ −amt | ✓ in | ✓ **Dr Cash / Cr AR** | — | ✓ | ✓ |
| Khata collection — UPI/card | ✓ −amt | ✓ nothing | ✓ **Dr Bank / Cr AR** | — | ✓ | ✓ |
| Khata collection — split | ✓ −amt | ✓ cash leg | ✓ Dr Cash + Dr Bank / Cr AR | — | ✓ | ✓ |
| Advance / overpayment | ✓ split payment + advance, one ref | ✓ cash leg | ✓ whole receipt to AR (AD-3) | — | ✓ | ✓ |
| Cash refund (return) | ✓ if credit_adjust | ✓ out | ✓ Dr Revenue / Cr **Cash** | ✓ if restocked | ⚠ G6 | ✓ |
| UPI/card refund | — | ✓ nothing | ✓ Dr Revenue / Cr **Bank** | ✓ if restocked | ⚠ G6 | ✓ |
| Credit-adjust refund | ✓ −refund | ✓ nothing | ✓ Dr Revenue / Cr AR | ✓ if restocked | ⚠ G6 | ✓ |
| Cash-sale cancellation | ✓ if customer | ✓ out, capped at cash taken | ✓ full reversal | ✓ | ✓ | ✓ |
| Credit-sale cancellation | ✓ reversal | ✓ nothing | ✓ full reversal | ✓ | ✓ | ✓ |
| Credit cancellation after part-collection | ✓ goes to advance | ✓ nothing | ✓ **AR nets negative, matches ledger** | ✓ | ✓ | ✓ |
| Split-bill cancellation | ✓ | ✓ cash leg only | ✓ **Cr Cash + Cr Bank per leg** | ✓ | ✓ | ✓ |
| Exchange — cash settled | ✓ consolidated | ✓ nets to difference | ✓ nets to Dr Cash = difference | ✓ | ⚠ G7 | ✓ |
| Exchange — credit adjust | ✓ consolidated | ✓ nothing | ✓ **AR moves by the difference; Cash untouched** | ✓ | ⚠ G7 | ✓ |
| Manual cash in | — | ✓ in | none (AD-5) | — | ✓ | ✓ |
| Manual cash out — uncategorised | — | ✓ out | none (AD-5) | — | ✓ | ✓ |
| Manual cash out — expense | — | ✓ out | ✓ Dr chosen expense / Cr Cash | — | ✓ | ✓ |
| Cash drop (till → safe) | — | ✓ out | none (AD-5) | — | ✓ | ✓ |
| Cash transfer (counter → counter) | — | ✓ out of A, in to B | none (AD-5) | — | ✓ | ✓ both |
| Manual adjustment | — | ✓ either | none (AD-5) | — | ✓ | ✓ |
| Opening float | — | not a movement | never posted | — | — | ✓ `opening_cash` |
| Shift shortage/overage | — | — | ⚠ still nowhere (G9) | — | ⚠ none | ✓ `difference` |

---

## 5. P2-C1 — Customer Payment → GL

**New:** `GLService.postCustomerPaymentEntries` — debits whichever account now holds the money, credits Accounts Receivable, posts no revenue (the credit sale already recorded that; posting again would double the takings). Filed under reference type `CustomerPayment` with Project 1's `paymentRef` as the reference id, so one identifier walks customer → ledger → cash book → GL → audit.

**Changed:** `CustomerRepository.receivePayment` posts inside its existing transaction, so a GL failure fails the whole receipt rather than committing a collection the books never learn about. It also now accepts `methodAmounts` for split collection (G8), validating that the legs add up to the total.

**Advances** credit Accounts Receivable along with everything else, per AD-3. That is the decision that buys the project's central invariant.

Verified by 12 tests in `customer_payment_gl_test.dart`: partial, full, cash, UPI, card, split, advance, overpayment, duplicate independence, rollback on a closed financial year, and the reconciliation invariant driven by real credit sales.

---

## 6. P2-C2 — Cancellation / Refund Accounting

**The finding that mattered was a non-finding.** Project 1's open item — "cancellation posts no GL entry for the refund itself" — was investigated and **rejected**. No entry was added. Adding one would double the refund on every cash cancellation, because the reversal already credits Cash.

The real defect was upstream, and fixing it made three things correct at once:

- **G1** — `postSaleEntries` now takes the sale's payment split and books the settled portion per method: Cash for notes, Bank for UPI/card. Legs that settle nothing (`credit`, `credit_adjust`, `exchange_settled`) go to Accounts Receivable. Because billing records a credit leg in *both* `paymentMethods` and `creditUsed`, the two are reconciled by taking the larger rather than the sum — summing would double the receivable on every ordinary credit sale.
- **G2** — `postSalesReturnEntries` now takes the refund method and credits the account the money actually leaves.
- **G4** — a credit-adjusted exchange rewrites both legs, not just one. `SalesReturnRepository` treats `exchange_settled` as settled-against-credit for GL purposes, and `ExchangeRepository` marks the replacement sale the same way. The asset side now lands in Accounts Receivable and Cash is untouched — previously GL Cash moved by the price difference and AR did not move at all.

Verified by 12 tests in `gl_settlement_test.dart` and 6 in `cancellation_accounting_test.dart`, including the split-bill cancellation that Project 1's cash-refund cap could not reconcile, and a credit sale cancelled after partial collection.

---

## 7. P2-C3 — Cash Management

**New:** `CashManagementService` with five operations — `cashIn`, `cashOut`, `cashDrop`, `cashTransfer`, `manualAdjustment` — each one transaction covering the cash movement, any GL posting, and the audit row.

**GL treatment follows AD-5, and most of it is deliberately nothing.** A drop to the safe and a counter-to-counter transfer move cash between places; with a single Cash account they have no GL consequence, and inventing a "Cash in Safe" account to make them look like accounting was explicitly ruled out. Only a categorised payout posts, and the operator must name the expense account — the service refuses rather than defaulting to one, and rejects a non-expense account outright.

**`manualAdjustment` always requires a manager, whatever the amount.** This is the one operation that can make a till balance by assertion rather than by counting; an unrestricted version would undo the control Project 1 built. It also requires a reason.

**`cashTransfer` writes both legs in one transaction**, each naming the other session as counterparty and the receiving leg pointing back at the sending one. A test proves that a transfer into a closed shift destroys nothing: the sending leg does not survive the failure of the receiving one.

Movements can only be attributed to an **open** shift — otherwise a payout could silently rewrite a reconciliation somebody had already signed off.

Verified by 21 tests in `cash_management_service_test.dart`.

---

## 8. P2-C4 — Approval Enforcement

**New:** `ApprovalService` — the one place that decides whether a financial action is authorised, with typed failures (`ApprovalRequired` vs `UnauthorizedApprover`) so a screen can tell "show the approval dialog" apart from "those credentials are not allowed".

The threshold is `stores.return_threshold_no_approval`, reused deliberately: it is the shop's single "how much may a cashier move unsupervised" figure, and giving cash management a second one would let a shop tighten refunds while leaving till payouts open. The boundary is `amount > limit`, unchanged from what the screens always did.

**What moved:** the rule, not the experience. `receive_payment_screen` still shows the dialog and still decides when to show it — but `receivePayment` re-checks and refuses regardless. Project 1's closing risk is directly covered by a test named for it.

**Credit limit:** the rule moved from `customer_form_screen` into `CustomerRepository.insert`/`update`, compared against the **stored** limit rather than whatever the caller claims the old value was. Preserved exactly: raising needs a manager; creating, editing details, keeping and lowering do not. Creating a customer already holding a limit is gated too, otherwise "raise the limit" would be evadable by delete-and-re-add.

A split receipt is gated on its **total**, not its largest leg — gating per-leg would be a trivially exploitable loophole.

Verified by 19 tests in `approval_enforcement_test.dart` plus 6 credit-limit tests. Note that the credit-limit tests are a genuine upgrade: in Project 1 that rule lived in a screen and could only be asserted by restating its arithmetic, which the brief rightly calls unacceptable evidence.

---

## 9. Accounting Decisions

All four escalated before implementation and approved as recommended.

| | Decision | Taken | Consequence |
|---|---|---|---|
| **AD-1** | Non-cash settlement account | **Bank 1010** | Matches the existing gateway path. Balance Sheet Cash and Bank both change; prior periods not restated. |
| **AD-2** | Customer payment posting | Dr settlement / Cr AR | Follows from AD-1; no separate sign-off needed. |
| **AD-3** | Customer advances | **Stay in AR 1100**, which may go net-negative | Buys the invariant `SUM(outstanding_balance) ≡ GL AR`. Cost: the Balance Sheet receivable is net of advances. |
| **AD-4** | Extra cancellation entry | **No** — fix the original posting instead | Avoided double-refunding every cash cancellation. |
| **AD-5** | Manual cash GL | **No GL for drops/transfers**; expense payouts require a chosen account | No arbitrary postings. Till short/over deliberately not implemented. |
| **AD-6** | Split-method collection | Accept a method map | Additive; matches `Sale.paymentMethods`. |
| **AD-7** | Migration v35 | **Approved** | Three nullable columns; additive, no backfill. |

**AD-3 is the one to revisit if your accountant disagrees.** A separate `2300 Customer Advances` liability is the textbook presentation. It was not chosen because it needs a new account, a migration, and reclassification entries whenever a balance crosses zero — three new failure modes — to improve a Balance Sheet presentation a single-shop POS does not file. The alternative is implemented-ready: it is a change to one method plus a seeded account.

---

## 10. Defects Found

Every one reproduced with a failing test before any fix, per the defect-proof requirement.

| # | Defect | Demonstrated failure | Fix |
|---|---|---|---|
| **D1** | UPI/card sales debit GL Cash | UPI sale: GL Cash +₹500, drawer +₹0 | Method-aware `postSaleEntries` |
| **D2** | Split sale books the whole bill to Cash | ₹400 cash + ₹600 UPI → GL Cash +₹1,000 | Same |
| **D3** | Part-credit bill misallocates settlement | Expected Cash ₹300, got ₹500 | Same |
| **D4** | UPI refunds credit GL Cash | GL Cash −₹100 with no drawer movement | Method-aware `postSalesReturnEntries` |
| **D5** | GL Cash irreconcilable with the cash book | One shift: GL ₹850 vs cash book ₹300 | D1–D4 together |
| **D6** | Credit-adjusted exchange moves GL Cash and skips AR | GL Cash +₹100, AR +₹0 | `exchange_settled` treated as receivable on both legs |
| **D7** | Customer payments post nothing to the GL | GL AR ₹0 against a ₹150 ledger advance | `postCustomerPaymentEntries` |
| **D8** | Approval threshold bypassable off-screen | ₹50,000 receipt accepted with no approver | `ApprovalService` at the repository boundary |
| **D9** | Credit-limit rule bypassable off-screen | Limit 0 → ₹5,000 with no approval | Rule moved into `insert`/`update` |

A tenth issue surfaced during implementation: `CashManagementService.manualAdjustment` validated its arguments synchronously, so failures threw at the call site instead of as a rejected Future. Caught by its own test and fixed by making the method `async`.

---

## 11. Tests Added

Baseline 530 → **606**. All exercise real repositories, services, transactions and database state.

| File | Tests | Covers |
|---|---|---|
| `test/services/gl_settlement_test.dart` | **12** (new) | G1, G2, G4 — settlement accounts, GL-vs-cash-book reconciliation |
| `test/repositories/customer_payment_gl_test.dart` | **12** (new) | P2-C1 — all payment methods, split, advance, rollback, invariant |
| `test/repositories/cancellation_accounting_test.dart` | **6** (new) | P2-C2 — cash/credit/split cancellation, part-collected, partial refund |
| `test/services/cash_management_service_test.dart` | **21** (new) | P2-C3 — every operation, approval, rollback, session reconciliation |
| `test/services/approval_enforcement_test.dart` | **19** (new) | P2-C4 — threshold, boundary, roles, bypass, rollback |
| `test/integration/accounting_integration_test.dart` | **1** (new) | Cross-module scenario, 11 steps |
| `test/repositories/customer_payment_test.dart` | 20 → **25** | Credit-limit rule now tested against real enforcement |
| `test/repositories/cash_movement_repository_test.dart` | 21 (updated) | Above-threshold collections now carry an approver |
| `test/services/counter_service_test.dart` | 13 (updated) | Same |
| `test/integration/financial_integration_test.dart` | 1 (updated) | Pinned divergence closed — see below |

**No test was deleted, skipped or weakened.** Fifteen pre-existing tests were updated because P2-C4 deliberately changed behaviour: collecting above ₹500 now requires a manager, so those tests supply one. That makes them stronger, not weaker — they now exercise the approval path as well.

**One assertion was inverted on purpose.** Project 1's integration test pinned the GL/ledger divergence with a comment saying it should fail the day it was fixed and be updated deliberately. That day was this project. It now asserts the two figures agree.

---

## 12. Integration Test

`test/integration/accounting_integration_test.dart` — one shift, 11 steps, every figure derived from what the application actually produced.

| Step | Event | Ledger | Cash book | GL |
|---|---|---|---|---|
| 1 | Open shift, ₹2,000 float | — | — | — |
| 2–3 | Customer Ravi; Demo Product ×100 | — | — | — |
| 4 | Cash sale ₹500 | — | +500 | Dr Cash 500 / Cr Rev 500 |
| 5 | Credit sale ₹300 | +300 | — | Dr AR 300 / Cr Rev 300 |
| 6 | Khata collection ₹150 cash | −150 | +150 | Dr Cash 150 / Cr AR 150 |
| 7 | Khata collection ₹100 UPI | −100 | — | Dr Bank 100 / Cr AR 100 |
| 8 | Cash refund ₹50 | — | −50 | Dr Rev 50 / Cr Cash 50 |
| 9 | Cash drop ₹200 to safe | — | −200 | **none** (AD-5) |
| 10 | Cash expense ₹100 | — | −100 | Dr Utilities 100 / Cr Cash 100 |
| 11 | Cancel the credit sale | −300 → **−250** | — | reversal, AR nets −250 |

**Closing reconciliation, all asserted:**
- Expected cash **₹2,300**, counted ₹2,300, difference ₹0 — and reconstructible line by line from the cash book.
- **Customer ledger ≡ GL AR**: both −₹250. Ravi paid ₹250 toward an order that was voided, so the shop owes him.
- **GL Cash ₹500 = till movement ₹300 + ₹200 dropped.** These answer different questions and the difference is exactly the drop, by nothing else — GL Cash is cash held by the *business*, the session book is cash in the *till*.
- GL Bank ₹100 (the one UPI collection). Revenue −₹450. Utilities ₹100.
- **Trial balance nets to zero.**
- Audit rows for both collections, the cancellation, the drop and the expense.
- Both collection references walk customer → ledger → GL; only the cash one appears in the cash book.

---

## 13. Database Changes

**Migration v35** (approved under AD-7). Schema **v34 → v35**.

Three nullable columns on `cash_movements`, plus one index:

| Column | Purpose |
|---|---|
| `counterparty TEXT` | Where the money went — "Main safe", the other session's id |
| `approved_by_user_id TEXT` | Who authorised it. No `REFERENCES` clause: SQLite cannot add a column with a foreign key to an existing table, and the application validates against `users` anyway — a FK could not tell a manager from a cashier |
| `reason TEXT` | Why, structured rather than buried in free-text `note` |

`CREATE INDEX idx_cash_movements_counterparty` — manual movements are looked up by counterparty far more than by source id, which is null for them.

**Backward compatibility is total.** All columns nullable, no defaults, no backfill. Every existing row stays valid; every existing query, index and `SELECT *` keeps working; the v34 writers leave all three null, which is correct. Guarded by `PRAGMA table_info` so a re-run is a no-op. Delegated from `MigrationV1` so `onCreate` and `onUpgrade` produce identical schema, following the established pattern. Rollback implication: an older build reading a v35 database simply does not see the new columns.

No `CHECK` constraint ties the approver to a direction or amount — which movements need approval is a business rule that belongs in the service where it can read a configurable threshold and be tested. Freezing it into the schema would make a policy change a migration.

---

## 14. Security Impact

**Roles:** unchanged. No route gating altered.

**Approval — materially strengthened.**
- The receive-payment threshold is now enforced at the repository, inside the transaction. Project 1's named residual risk is closed.
- The credit-limit rule likewise, compared against the stored value rather than a caller-supplied claim.
- Cash out, cash drops and transfers are threshold-gated; manual adjustments always require a manager.
- Supplied approvers are validated in every path — role, existence and active status — and a bad approver is rejected even below the threshold, so a forged id cannot ride in on a small transaction.
- Typed failures let a screen distinguish "needs approval" from "that approver is not allowed" without parsing message strings.

**Audit — extended.** Cash management writes `CASH_MOVEMENT_RECORDED` inside the transaction with type, direction, amount, reason, counterparty, session, approver and any expense account. Customer payment audit now also carries the method breakdown and session. No credentials or secrets are recorded anywhere.

**Session attribution:** movements can only attach to an open shift.

**Residual, and stated plainly:** `CustomerRepository.bulkInsert` (Import Parties) is not credit-limit gated. It sits behind a manager-only route, and prompting per row of a thousand-row spreadsheet would make the feature unusable — so the route is the control there, not an approval.

---

## 15. Financial Reconciliation Results

Four invariants, each asserted by test rather than argued.

**1. Customer ledger ≡ GL Accounts Receivable.**
`SUM(customers.outstanding_balance)` equals the GL receivable balance after any sequence of credit sales, collections, advances, cancellations and exchanges. Asserted as a delta over real transactions in `customer_payment_gl_test.dart` and absolutely in the integration test.

**2. GL Cash ≡ the cash book, adjusted for location.**
```
GL Cash movement = session cash book net + drops + transfers out − transfers in
```
Cash, UPI and card sales, refunds, collections and expense payouts all move both figures identically. Drops and transfers move the till without moving the business — the one legitimate difference, and the integration test asserts it is exactly the drop and nothing else.

**3. Expected cash ≡ opening float + cash book.**
```
Opening + cash sales + cash collections + cash in
      − cash refunds − cash out − drops ± transfers = Expected
```
Unchanged from Project 1 and still reconstructible row by row.

**4. The books balance.** Trial balance nets to zero across every entry.

**Where the model intentionally differs, and why:**
- **Advances sit inside Accounts Receivable** (AD-3) — buys invariant 1; costs Balance Sheet presentation.
- **Drops and transfers post nothing** (AD-5) — with one Cash account they have no GL consequence.
- **The shift shortage/overage posts nothing** (G9) — needs a Cash Short/Over account and a write-off policy; both open decisions.
- **Sale revenue includes GST** — a pre-existing Phase 1 simplification, untouched.

---

## 16. Remaining Risks

**Carried into this project and still open:**
- **G6 — the sales-return audit row is written by the screen**, after the transaction commits, and only when an approver exists. A below-threshold return leaves no audit row; a non-screen caller leaves none; a crash between commit and audit leaves a refund with no trace. `SaleCancellationRepository` shows the right pattern. Not fixed here because it belongs with the returns approval work, which this project did not open.
- **G7 — the exchange audit row carries no financial detail.** It records that something happened, not what.
- **G9 — the shift difference posts nowhere.** A till short ₹500 daily produces a number on a screen and no accounting consequence.

**New, created by this project's scope boundaries:**
- **Returns, cancellations and exchanges still gate approval in the UI only.** P2-C4 moved the rule to the service for customer payments and credit limits; the other three sensitive flows still hold their thresholds in their screens and remain bypassable by a direct repository call. This is now the largest remaining control gap and is the obvious P3 item.
- **No UI exists for cash management.** The service, schema and controls are complete and tested; no screen calls them yet. The capability is unreachable from the app until one is built.
- **`bulkInsert` remains un-gated** for credit limits (§14).

**From the original audit, untouched:** H3 route gating fails open · H4 repositories constructed in widgets (still zero widget tests, so both approval dialogs remain verifiable only by inspection) · M1 money-as-double · M2 file sizes · M3 split migration strategy · M4 secrets at rest · M5 silent catches · M6 GST is a stub · M7 coverage gaps. The three Phase 2 accounting questions (loyalty liability, gateway fees, commission) remain undecided.

---

## 17. Files Changed

**Created — `lib/` (3):**
- `lib/services/approval_service.dart` — the authorisation rule
- `lib/services/cash_management_service.dart` — manual cash operations
- `lib/core/database/migrations/migration_v35.dart` — three nullable columns

**Modified — `lib/` (10):**
- `lib/services/gl_service.dart` — settlement account resolution; method-aware sale and return posting; `postCustomerPaymentEntries`
- `lib/repositories/customer_repository.dart` — GL posting, split methods, service-enforced approval, credit-limit rule
- `lib/repositories/cash_movement_repository.dart` — manual source types; `counterparty`/`approver`/`reason`; `record` returns the row id
- `lib/repositories/sale_repository.dart` — passes the payment split to the GL
- `lib/repositories/sales_return_repository.dart` — passes the refund method; treats `exchange_settled` as receivable
- `lib/repositories/exchange_repository.dart` — marks the replacement sale's settlement
- `lib/models/sale_model.dart` — `copyWith` accepts `paymentMethods`
- `lib/providers/customer_provider.dart` — threads the approver
- `lib/features/customers/screens/customer_form_screen.dart` — passes the approver it authenticated
- `lib/features/credit/screens/receive_payment_screen.dart` — reads the threshold from `ApprovalService`
- `lib/core/database/database_helper.dart`, `lib/core/database/migrations/migration_v1.dart`, `lib/constants/app_constants.dart` — v35 registration

**Created — `test/` (6):** `gl_settlement_test.dart`, `customer_payment_gl_test.dart`, `cancellation_accounting_test.dart`, `cash_management_service_test.dart`, `approval_enforcement_test.dart`, `accounting_integration_test.dart`

**Modified — `test/` (4):** `customer_payment_test.dart`, `cash_movement_repository_test.dart`, `counter_service_test.dart`, `financial_integration_test.dart`

**Created — `docs/` (2):** `PROJECT2_PHASE0_INSPECTION.md`, `PROJECT2_ACCOUNTING_RECONCILIATION.md`

**Deleted:** none.

---

## 18. Explicitly Out of Scope

Untouched, as instructed: GST implementation and reports, GSTR-1, GSTR-3B, money-as-double migration, `billing_screen.dart` refactor, global Riverpod/DI architecture, route authorization (H3), Razorpay secret architecture, unrelated reports, unrelated UI, unrelated repositories, and the product/purchase modules.

`PurchaseRepository` was inspected as a GL writer and confirmed out of scope. `payment_dialog.dart` was read to establish what `payment_methods` contains; it was not modified.

---

## 19. Final Test / Analyzer Results

| | Project 1 baseline | Project 2 final |
|---|---|---|
| Tests passed | 530 | **606** |
| Tests failed | 0 | **0** |
| Analyzer errors | 0 | **0** |
| Analyzer warnings | 0 | **0** |
| Analyzer info | 138 | **138** |
| Schema | v34 | **v35** |

New test code initially added one `prefer_const_constructors` hint; it was cleared, so this project adds no analyzer noise. No pre-existing issue was touched.

---

## 20. Recommendation for Project 3

**Do first — it is the same defect this project just closed, in three more places.** Move the approval rule for **returns, cancellations and exchanges** into the service boundary, exactly as P2-C4 did for customer payments and credit limits. `ApprovalService` already exists; the work is threading it through three repositories and updating three screens to pass the approver they authenticate. This is the largest remaining control gap and the cheapest to close.

**Do at the same time, because it is the same code path:** fix **G6** by moving the sales-return audit row into `SalesReturnRepository`'s transaction and writing it unconditionally, and **G7** by giving the exchange audit row its amounts and settlement method.

**Then, one of two directions depending on what the business needs more:**

- **H4 / widget tests.** Both approval dialogs remain verifiable only by code reading, and will stay that way until repositories stop being constructed inside widgets. Doing this per-feature as they are touched would let the approval work above be tested end to end rather than to the service boundary. It would also unblock a UI for cash management, which currently has a complete tested service and no screen.
- **GST (M6).** Still an 11-line stub, still the largest single piece of unbuilt work, and the only one with statutory exposure for a Tamil Nadu retail business.

**Deferred decisions worth settling before either:** whether advances should move to a `2300 Customer Advances` liability (AD-3), whether a `Cash Short/Over` account should exist so G9 can be closed, and the three Phase 2 accounting questions (loyalty liability, gateway fees, commission) — which all want the same new chart-of-accounts entries and should be treated as one task.

**Leave alone:** the GL design, the cash movement single-writer pattern, and the `ApprovalService` boundary. All three are now load-bearing and working.
