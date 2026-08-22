# Project 2 — Phase 0 Inspection (no code changed)

**Date:** 2026-08-17 · **Baseline:** Project 1 complete — 530 tests passing, analyzer 0 errors / 0 warnings / 138 info, schema **v34**
**Status:** inspection only. Nothing in `lib/` or `test/` has been modified. Every defect named below is inspection-derived and will be reproduced with a failing test before any correction is applied.

---

## 0. Baseline re-verified before inspection

| | Recorded |
|---|---|
| Tests | **530 passed, 0 failed** |
| Analyzer | **0 errors, 0 warnings, 138 info** |
| Schema | **v34** (`AppConstants.dbVersion = 34`) |
| Working tree | Project 1's changes present and uncommitted |

---

## 1. The single root cause behind most of what follows

Almost every reconciliation gap in this application traces to one fact:

> **The GL has no notion of payment method.** It only knows "receivable" vs. "not receivable", and it books everything not receivable to **Cash (1000)**.

`GLService.postSaleEntries` splits `netAmount` into `receivable = creditUsed + partialPaymentAmount` and puts the entire remainder in Cash. `GLService.postSalesReturnEntries` mirrors it: `credit_adjust` → Accounts Receivable, **everything else → Cash**.

Meanwhile Project 1 built `cash_movements` on a much stricter rule — `isCashMethod(method) => method == 'cash'` — so the cash book knows the difference between notes and UPI and the GL does not. The two were correct in isolation and were never reconciled against each other.

That mismatch, plus the total absence of GL posting for customer payments, produces gaps G1–G7 below.

---

## A. Financial Transaction Map

`✓` = behaviour verified by an existing passing test · `~` = inspection-derived, not yet covered by a test · `✗` = the writer does not fire at all

| Transaction | Customer Ledger | Cash Movement | GL | Stock | Audit | Session |
|---|---|---|---|---|---|---|
| **Cash sale** | ✗ none (no customer) | ✓ in, cash leg | ✓ Dr Cash / Cr Revenue | ✓ deducted | ✗ **none** | ✓ from sale |
| **Credit sale** | ✓ `sale` row, balance +net | ✓ nothing | ✓ Dr AR / Cr Revenue | ✓ deducted | ✗ **none** | ✓ from sale |
| **UPI sale** | ✗ none | ✓ nothing (correct) | ~ **Dr Cash** / Cr Revenue ← **G1** | ✓ deducted | ✗ none | ✓ |
| **Card sale** | ✗ none | ✓ nothing (correct) | ~ **Dr Cash** / Cr Revenue ← **G1** | ✓ deducted | ✗ none | ✓ |
| **Gateway sale** (Razorpay etc.) | ✗ none | ✓ nothing | ~ Dr Cash/Cr Rev, then Dr Bank / Cr Cash — nets correct | ✓ | ✗ none | ✓ |
| **Split sale** (cash + UPI) | ✗ none | ✓ in, cash leg only | ~ Dr Cash **for the whole bill** ← **G1** | ✓ | ✗ none | ✓ |
| **Partial-payment sale** | ✓ balance += unpaid | ✓ in, cash leg | ✓ Dr Cash + Dr AR / Cr Revenue | ✓ | ✗ none | ✓ |
| **Khata collection — cash** | ✓ `payment` row, balance −amt | ✓ in, full amount | ✗ **NOTHING POSTED** ← **G3** | n/a | ✓ `CUSTOMER_PAYMENT_RECEIVED` | ✓ passed or inferred |
| **Khata collection — UPI** | ✓ `payment` row | ✓ nothing (correct) | ✗ **NOTHING POSTED** ← **G3** | n/a | ✓ | ✓ |
| **Khata collection — card** | ✓ `payment` row | ✓ nothing | ✗ **NOTHING POSTED** ← **G3** | n/a | ✓ | ✓ |
| **Khata collection — split** | ~ **not supported** — `receivePayment` takes one `method` ← **G8** | — | — | — | — | — |
| **Advance (no due)** | ✓ `advance` row, balance goes negative | ✓ in if cash | ✗ **NOTHING POSTED** ← **G3** | n/a | ✓ | ✓ |
| **Overpayment** | ✓ split `payment` + `advance`, one reference | ✓ in, full amount | ✗ **NOTHING POSTED** ← **G3** | n/a | ✓ | ✓ |
| **Cash refund (return)** | ✓ only if `credit_adjust` | ✓ out | ✓ Dr Revenue / Cr Cash | ✓ if restocked | ~ screen-only, approver-only ← **G6** | ✓ from header or inferred |
| **UPI/card refund (return)** | ✗ none | ✓ nothing (correct) | ~ Dr Revenue / **Cr Cash** ← **G2** | ✓ if restocked | ~ G6 | ✓ |
| **Credit-adjust refund** | ✓ balance −refund | ✓ nothing | ✓ Dr Revenue / Cr AR | ✓ if restocked | ~ G6 | ✓ |
| **Cash-sale cancellation** | ✓ reversal row if customer | ✓ out, capped at cash taken (P1) | ✓ full line-by-line reversal | ✓ restocked | ✓ `SALE_CANCELLED` | ✓ from sale |
| **Credit-sale cancellation** | ✓ reversal row | ✓ nothing (P1 fix) | ✓ full reversal | ✓ restocked | ✓ | ✓ |
| **Credit cancellation after part-collection** | ✓ balance goes negative (advance) | ✓ nothing | ~ AR nets negative once G3 is fixed — **currently AR = 0** ← **G3** | ✓ | ✓ | ✓ |
| **Split-bill cancellation** | ✓ | ✓ out, cash leg only (P1) | ~ reversal credits Cash for the **whole** bill ← **G1** | ✓ | ✓ | ✓ |
| **Exchange — cash settled** | ✓ consolidated `exchange` row | ✓ both legs gross, nets to difference | ~ nets to Dr Cash = difference — **correct** | ✓ | ~ thin (no amounts) ← **G7** | ✓ inherited |
| **Exchange — credit adjust** | ✓ consolidated `exchange` row | ✓ nothing (correct) | ~ **Cr Cash on the return leg + Dr Cash on the new sale; the AR movement is never posted** ← **G4** | ✓ | ~ G7 | ✓ |
| **Manual cash in** | n/a | ~ repository supports it | ✗ no writer | n/a | ✗ no writer | ~ inferred |
| **Manual cash out** | n/a | ~ repository supports it | ✗ no writer | n/a | ✗ no writer | ~ inferred |
| **Cash drop (till → safe)** | n/a | ✗ **no such operation** ← **G5** | ✗ | n/a | ✗ | ✗ |
| **Cash transfer (counter → counter)** | n/a | ✗ **no such operation** ← **G5** | ✗ | n/a | ✗ | ✗ |
| **Opening cash (float)** | n/a | ✗ not a movement (by design) | ✗ never posted | n/a | ✗ | ✓ `sessions.opening_cash` |
| **Shift shortage / overage** | n/a | ✗ not a movement | ✗ **never posted** ← **G9** | n/a | ✗ **no audit row** | ✓ `difference` |

**Confirmed non-writers** (checked so they can be ruled out): `CollectionsRepository` / `CollectionsService` read `customer_ledger` only. `PaymentGatewayService` posts GL and never touches `customer_ledger`, `outstanding_balance` or `cash_movements`. `PurchaseRepository` posts Dr Inventory / Cr AP and is out of scope.

---

## B. Accounting Gap Report

### Customer Ledger ≠ GL

**G3 — Customer payments post nothing to the GL.** *(carried forward from Project 1, now P2-C1's core)*
`CustomerRepository.receivePayment` writes the customer ledger, the cash movement and the audit row inside one transaction, and never calls `GLService`. Accounts Receivable in the GL is therefore reduced only by cancellations and `credit_adjust` returns — never by an actual collection. GL AR drifts upward without limit against the customer ledger, permanently.
*Already pinned by an assertion in `test/integration/financial_integration_test.dart` (GL AR reads 0 while Ravi holds a ₹150 advance).*

**G4 — A `credit_adjust` exchange posts the wrong account and skips AR entirely.**
`ExchangeRepository` rewrites the return leg's `refundMethod` from `credit_adjust` to `exchange_settled` to stop `SalesReturnRepository` applying a second customer-balance adjustment. That rewrite has an unintended second effect: `postSalesReturnEntries` computes `refundedAgainstCredit = customerId != null && refundMethod == 'credit_adjust'`, which is now **false**, so the return credits **Cash** for money that never moved. Separately, the consolidated `priceDifference` applied to the customer's balance gets a `customer_ledger` row but **no GL entry at all**.
Net effect on a credit-adjusted exchange: GL Cash moves by the price difference (should be zero), GL AR does not move (should be the price difference).

### Cash Movement ≠ GL Cash

**G1 — Non-cash sales debit GL Cash.**
`postSaleEntries` books everything not receivable to Cash 1000. A ₹1,000 UPI sale therefore debits GL Cash ₹1,000 while the cash book correctly records ₹0. Gateway-processed payments are corrected afterwards by `postGatewayPaymentEntries` (Dr Bank / Cr Cash), so they net out — but a UPI or card sale keyed manually in the payment dialog (methods `'upi'`, `'card'`) is never corrected. GL Cash is overstated by every such sale, for ever.

**G2 — Non-cash refunds credit GL Cash.**
The mirror image. `postSalesReturnEntries` sends anything that is not `credit_adjust` to Cash, so a UPI or card refund credits GL Cash while the cash book correctly records nothing. GL Cash is understated by every such refund.

G1 and G2 together mean **GL Cash is not the drawer and is not the bank — it is an unlabelled mixture of both**, and no report can tell them apart.

### Session Reconciliation ≠ Cash Book

No gap. Project 1 closed this: `CounterService.closeShift` and `counter_close_screen` both derive expected cash from `CashMovementRepository.getSessionNet`, and the integration test reconstructs `expected_cash` row by row from the cash book. The remaining issue is one of *coverage*, not of agreement:

**G5 — Legitimate non-sale cash movements cannot be recorded.**
`CashMovementSource.manualAdjustment` is defined and `CashMovementRepository.record` supports it, but nothing in `lib/` writes one and there is no UI. A shop that takes ₹200 out of the till for a delivery driver, or drops ₹5,000 to the safe mid-shift, has no way to record it — the shift simply reads short. The control works; the vocabulary is missing.

**G9 — The shift difference is never posted anywhere.**
`sessions.difference` records a shortage or overage and nothing consumes it: no GL entry, no audit row, no follow-up. A till that is short ₹500 every day produces a number on a screen and no accounting consequence.

### Audit Trail ≠ Financial Transaction

**G6 — The sales-return audit row is written by the screen, outside the transaction, and only when an approver exists.**
`return_form_screen.dart:298` writes `SALES_RETURN_APPROVED` *after* `createReturn` has already committed, and only inside `if (approvedByUserId != null)`. So: a below-threshold return leaves **no audit row at all**; a return created by any non-screen caller leaves none; and a crash between the commit and the audit write leaves a refund with no trace. Compare `SaleCancellationRepository`, which writes its audit row inside the transaction unconditionally — that is the pattern the return path should follow.

**G7 — The exchange audit row carries no financial detail.**
`ExchangeRepository` logs `EXCHANGE_PROCESSED` with a record id and nothing else — no amounts, no settlement method, no approver, no price difference. It records that something happened, not what.

**G10 — Sales themselves are never audited.** No `logAudit` call exists in `SaleRepository`. This is arguably by design (the `sales` table *is* the record) and is noted for completeness rather than proposed for change.

### Additional structural gap

**G8 — `receivePayment` accepts a single payment method.** The signature is `method: String`, so the split collection required by P2-C1 ("₹400 cash + ₹600 UPI against one ₹1,000 receivable") cannot be expressed. Supporting it changes a public signature and the cash/GL split logic — see decision **AD-6**.

---

## C. Existing Chart of Accounts

Seeded by `MigrationV28.seedDefaultAccounts`, idempotent, `is_system = 1` on all 22 (undeletable by UI, deactivatable). `GLRepository.seedDefaultAccounts()` delegates here, so migration and repository can never disagree.

| Code | Id | Name | Type | Sub-type |
|---|---|---|---|---|
| 1000 | `coa_1000` | **Cash** | asset | current_asset |
| 1010 | `coa_1010` | **Bank** | asset | current_asset |
| 1100 | `coa_1100` | **Accounts Receivable** | asset | current_asset |
| 1200 | `coa_1200` | Inventory | asset | current_asset |
| 1500 | `coa_1500` | Fixed Assets | asset | fixed_asset |
| 2000 | `coa_2000` | Accounts Payable | liability | current_liability |
| 2010 | `coa_2010` | Credit Card | liability | current_liability |
| 2100 | `coa_2100` | Short-term Loans | liability | current_liability |
| 2200 | `coa_2200` | Long-term Loans | liability | long_term_liability |
| 3000 | `coa_3000` | Capital | equity | equity |
| 3100 | `coa_3100` | Retained Earnings | equity | equity |
| 4000 | `coa_4000` | **Sales Revenue** | revenue | operating_revenue |
| 4100 | `coa_4100` | Service Revenue | revenue | operating_revenue |
| 4900 | `coa_4900` | Other Income | revenue | other_income |
| 5000 | `coa_5000` | Cost of Goods Sold | expense | cogs |
| 5100 | `coa_5100` | Salaries & Wages | expense | operating_expense |
| 5200 | `coa_5200` | Rent | expense | operating_expense |
| 5300 | `coa_5300` | Utilities | expense | operating_expense |
| 5400 | `coa_5400` | Depreciation | expense | operating_expense |
| 5500 | `coa_5500` | Interest Expense | expense | other_expense |

**Codes referenced in posting code:** `1000` cash, `1010` bank, `1100` receivable, `1200` inventory, `2000` payable, `4000` sales revenue. Everything else is reporting-only.

**What does not exist, and matters for Project 2:**
- **No customer-advance liability account.** Advances currently push AR negative.
- **No UPI / card / gateway clearing account.** `2010 Credit Card` is a *company* credit card liability, not customer card receipts — using it would be wrong.
- **No sales-returns contra-revenue account.** Returns debit `4000` directly, so gross revenue is not recoverable from the GL.
- **No petty cash, cash-in-transit or safe account.** Relevant to cash drops.
- **No cash short/over account.** Relevant to G9.

**Precedent worth noting:** `bank_accounts.gl_account_id` (v30) already links a real-world money location to a `chart_of_accounts` row. Any "where does this money live" mapping should follow that pattern rather than invent a new one.

`sub_type` is not decoration — `FinancialStatementService` splits the Balance Sheet and P&L on it. Any new account must carry a consistent sub-type.

---

## D. Accounting Decision List

Six decisions. **AD-1, AD-3, AD-5 and AD-7 need your sign-off before I write code**; AD-2 and AD-4 follow from them.

---

### AD-1 — Which account receives non-cash settlement?

1. **Current behaviour.** Everything not receivable goes to Cash 1000 — UPI sales, card sales, UPI refunds, card refunds. Only gateway-processed payments get corrected to Bank 1010 afterwards.
2. **Financial problem.** GL Cash is neither the drawer nor the bank. It cannot be reconciled against the cash book (G1, G2) and the Balance Sheet's cash figure is wrong by the running total of all manual UPI/card activity.
3. **Possible treatments.**
   - **(a) Post UPI/card straight to Bank 1010.** Follows the existing gateway precedent exactly. No new accounts, no migration.
   - **(b) Add clearing accounts** (e.g. `1020 UPI Clearing`, `1030 Card Clearing`) that later clear to Bank. Textbook-correct for card settlement timing (T+2) and fees.
   - **(c) Leave as-is** and redefine account 1000 as "undeposited funds". Zero work, but the name lies and the drawer stays unreconcilable.
4. **Recommended: (a).** 
5. **Why.** It is the treatment this codebase already chose for gateway payments, so it makes the two paths consistent instead of adding a third model. It needs no new accounts and no migration, and it makes GL Cash equal the cash book exactly — which is the invariant Project 2 is being asked to establish. (b) is more correct but only pays off once settlement timing and fees are modelled, which is Phase 2's escalated "gateway fees" question and not this project.
6. **Approval required: YES.** This moves money between two reported accounts. Your Balance Sheet's Cash and Bank lines will both change, and prior periods will not be restated.

---

### AD-2 — Customer payment posting

1. **Current behaviour.** Nothing posted (G3).
2. **Financial problem.** GL AR never falls; it diverges from the customer ledger permanently.
3. **Possible treatments.** Dr the settlement account (Cash 1000 for cash, per AD-1 Bank 1010 for UPI/card) / Cr Accounts Receivable 1100. There is no serious alternative for the receivable portion.
4. **Recommended:** as stated, posted inside the existing `receivePayment` transaction with a new `referenceType` of `CustomerPayment` and the Project 1 `paymentRef` as `referenceId`.
5. **Why.** It is the standard treatment, it reuses the reference Project 1 already created, and posting inside the existing transaction means a GL failure rolls the whole receipt back — satisfying the atomicity requirement with no new transaction boundary.
6. **Approval required: NO** for the receivable portion. The *advance* portion depends on AD-3.

---

### AD-3 — How should a customer advance be represented in the GL?

1. **Current behaviour.** The customer ledger writes a separate `advance` row and lets `outstanding_balance` go negative. The GL knows nothing (G3).
2. **Financial problem.** An advance is money the shop **owes**. Sitting it inside an asset account nets it against genuine receivables, so the Balance Sheet understates both what is owed to the shop and what the shop owes.
3. **Possible treatments.**
   - **(a) Credit AR 1100 for the whole receipt**, letting AR go net-negative when a customer is in credit.
   - **(b) Split the posting** — credit AR for the portion that clears a due, credit a new `2300 Customer Advances` liability for the excess.
4. **Recommended: (a), with the presentation caveat recorded.**
5. **Why.** This is the decision I would most like you to overrule if your accountant disagrees, so here is the full reasoning. (b) is textbook-correct. But (a) produces an invariant that (b) does not: **`customers.outstanding_balance` ≡ GL Accounts Receivable balance, always**, for every transaction type including the awkward credit-cancellation-after-part-collection case. That single equality is testable in one assertion, is what "the ledger and the GL reconcile" actually means operationally, and is the strongest control this project can install. (b) requires a new account, a migration, *and* reclassification entries whenever a balance crosses zero — three new failure modes to protect a Balance Sheet presentation that a single-shop POS does not file. If you want (b), say so and I will implement it; it is more work but not much more.
6. **Approval required: YES.** This is a genuine accounting-policy choice, not a technical one.

---

### AD-4 — Should cancellations and refunds post an *additional* cash entry?

1. **Current behaviour.** A cancellation reverses the sale's original lines and posts nothing else. A return posts a fresh `Dr Revenue / Cr <cash or AR>` entry.
2. **Financial problem.** Project 1 flagged "cancellation posts no GL entry for the refund itself" as an open item. On inspection **that flag was wrong, and no new entry should be added.** For a cash sale the reversal's `Cr Cash` *is* the refund; adding a second entry would double it. The apparent mismatch on a split bill — where Project 1's cap sends less cash out of the drawer than the reversal credits — is not a cancellation defect at all. It is G1: the *original* sale should never have debited Cash for the UPI leg.
3. **Possible treatments.** Add a compensating refund entry (wrong — double-counts) / fix the original posting so the reversal is automatically right (correct).
4. **Recommended:** post nothing new on cancellation. Fix AD-1 and the reversal becomes correct by construction.
5. **Why.** This is precisely the "do not simply add another GL entry without understanding the existing reversal architecture" trap the brief warns about. The reversal architecture is sound; the thing being reversed was wrong.
6. **Approval required: NO** — this is a technical finding, and it *reduces* the amount of change.

---

### AD-5 — Manual cash management: what, if anything, hits the GL?

1. **Current behaviour.** No manual cash operations exist (G5).
2. **Financial problem.** Real cash leaves and enters the drawer for reasons the system cannot express, so those amounts surface as unexplained shortages and destroy the credibility of the control Project 1 fixed.
3. **Possible treatments, per movement type.**

| Movement | Cash book | Session | GL |
|---|---|---|---|
| Cash drop (till → safe) | out | reduces expected cash | **none** — cash is still cash, and no safe account exists |
| Cash transfer (counter → counter) | out of A, in to B | affects both | **none** — same reason |
| Cash in (petty cash return, float correction) | in | increases expected | **none** unless a counterpart is named |
| Cash out — **expense** | out | reduces expected | **needs an expense account chosen by the operator** |
| Manual adjustment (till short/over) | either | adjusts expected | **needs a cash short/over account, which does not exist** |

4. **Recommended.** Implement drops, transfers and uncategorised cash in/out as **cash-book + session + audit only, with no GL posting**, and make that explicit in the code and the report. For cash-out-as-expense, require the operator to pick an existing expense account (5100–5500) and post `Dr <expense> / Cr Cash`; refuse the movement if no account is chosen rather than defaulting to one. Do **not** implement till short/over posting in this project.
5. **Why.** A cash drop genuinely has no GL consequence under a chart of accounts with one cash account — inventing a "Cash in Safe" account to make it look like accounting would be exactly the arbitrary posting the brief forbids. Requiring an explicit expense account keeps the operator, not the code, responsible for the classification. Till short/over needs a new account and a policy on who may write one off; that is a decision, not an implementation.
6. **Approval required: YES**, on two points: (i) is "no GL effect for drops/transfers" acceptable to your accountant, and (ii) do you want a `Cash in Safe` asset account and/or a `Cash Short/Over` expense account created (each needs a migration — see AD-7).

---

### AD-6 — Should `receivePayment` support split methods?

1. **Current behaviour.** One `method: String` per receipt (G8). A customer paying ₹400 cash + ₹600 UPI must be recorded as two separate receipts.
2. **Financial problem.** None, strictly — two receipts are financially accurate and each is independently traceable. The problem is ergonomic and reporting-level: one economic event becomes two references.
3. **Possible treatments.** Change the signature to accept a method→amount map (matching `Sale.paymentMethods`) / leave it and let the screen record two receipts.
4. **Recommended:** change the signature to accept a map, keeping the single-method form working via a convenience overload so no existing caller breaks.
5. **Why.** P2-C1 explicitly requires split collection, and `Sale.paymentMethods` already establishes the map shape — reusing it keeps one vocabulary. The cash/GL split then falls out naturally: cash leg → cash book + Dr Cash, non-cash legs → Dr Bank, one Cr AR for the total.
6. **Approval required: NO** — additive, and it matches an existing pattern.

---

### AD-7 — Does any of this need a schema change?

**v34 is sufficient for P2-C1, P2-C2 and P2-C4.** Customer payment GL posting, the exchange fix and service-level approval enforcement all fit existing tables. No migration needed.

**P2-C3 (manual cash) is the only pressure point.** `cash_movements` currently holds `id, session_id, direction, amount, source_type, source_id, user_id, note, created_at`. A cash drop or transfer wants three things it has nowhere to put:

| Need | Workaround in v34 | Cost of the workaround |
|---|---|---|
| Destination / counterparty ("safe", "counter 2") | encode in `note` | not queryable; no transfer can be matched to its pair |
| Approver | encode in `note` | an approval that cannot be queried is not a control |
| Structured reason/category | `note` is free text | expense category cannot drive GL posting |

**Options.**
- **(a) No migration.** Use new `source_type` values (`cash_in`, `cash_out`, `cash_drop`, `cash_transfer`) and put JSON in `note`. Ships without schema risk; produces a cash book that cannot answer "which drops did Priya approve last week".
- **(b) Migration v35** adding three nullable columns to `cash_movements`: `counterparty TEXT`, `approved_by_user_id TEXT REFERENCES users(id)`, `reason TEXT`. Purely additive, all nullable, no backfill needed, no existing row or query affected, no rollback risk beyond dropping forward.

**Recommended: (b).** It is the smallest schema change that makes the new movements auditable, and P2-C3's own requirements list ("source session, source user, amount, reason, destination, timestamp, reference, approval") cannot be met honestly without it.

**Approval required: YES** — per your instruction to stop before any migration.

**If approved,** the migration strategy is: new `MigrationV35.up` with three `ALTER TABLE cash_movements ADD COLUMN` statements; register under `oldVersion < 35`; delegate from `MigrationV1` so `onCreate` and `onUpgrade` stay identical (the established pattern); bump `AppConstants.dbVersion` to 35. Backward compatibility is total — every existing column, index and query is untouched, and an older build reading a v35 database would simply not see the new columns.

---

## Summary of what needs your decision

| | Question | My recommendation |
|---|---|---|
| **AD-1** | UPI/card → Bank 1010, or clearing accounts? | Bank 1010 (matches existing gateway treatment) |
| **AD-3** | Advances in AR (net-negative), or a new liability account? | Keep in AR — gives an exact ledger ≡ GL AR invariant |
| **AD-5** | No GL effect for drops/transfers? New safe / short-over accounts? | No GL effect; no new accounts this project |
| **AD-7** | Approve migration v35 (3 nullable columns on `cash_movements`)? | Yes — otherwise cash drops cannot be audited |

### Decisions taken — 2026-08-17

All four were approved as recommended:

- **AD-1 → Bank 1010.** UPI/card settlement posts to Bank 1010, matching the existing gateway path. No clearing accounts.
- **AD-3 → advances stay in AR 1100.** AR may go net-negative. The binding invariant for this project is therefore `customers.outstanding_balance ≡ GL Accounts Receivable`.
- **AD-5 → no GL effect for drops/transfers.** Cash-out-as-expense requires an operator-chosen expense account (5100–5500) and is refused without one. No `Cash in Safe`, no `Cash Short/Over`, no till short/over posting in this project.
- **AD-7 → migration v35 approved.** Three nullable columns on `cash_movements`: `counterparty`, `approved_by_user_id`, `reason`.

AD-2, AD-4 and AD-6 follow mechanically and needed no separate sign-off.
