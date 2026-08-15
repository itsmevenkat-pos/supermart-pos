# Payment Gateway Architecture

What Phase 2 Task 2.3 actually built, and why it differs from
`tasks/phase2/03-payment-gateways.md` in a few places. Written for the same
reason Phase 1 has `GL_ARCHITECTURE.md`: the task file's assumptions about the
existing codebase turned out to be wrong in one important way, and the next
person to work here needs a description of reality rather than of the plan.

**Trust this document over the task file.**

## The headline finding: the `payments` table was dead

`tasks/phase2/03-payment-gateways.md` opens with:

> This app already has a generic `payments` table (since `migration_v1.dart`)
> … Every sale's payment already flows through this, cash or otherwise.

It does not. The table has existed since `MigrationV1`, but at the start of
this task it had **zero readers and zero writers** anywhere in `lib/` or
`test/` — grep for `'payments'` and the only hits were the `CREATE TABLE`
itself and a comment in `supabase_sync_service.dart`. What a sale really
records is the `sales.payment_methods` column: a JSON map of
`{method: amount}`, written by `BillingService.processSale`.

So the task file's instruction — hang gateway detail off the `payments` row
that already exists — had nothing to hang off.

### What was done instead

`PaymentGatewayRepository` became the table's **first writer**. A gateway
payment gets a real `payments` row, and `payment_gateway_transactions`
references it one-to-one, which is exactly the shape the task file describes.
Cash, card and UPI sales are untouched and still record only the JSON map.

The alternative — adding a second `sale_id`-linked table for gateway payments
— is the design the task file explicitly rules out, and rightly. The other
alternative, making `payments` authoritative for *every* payment type, means
rewriting the billing path, backfilling historical sales and re-pointing
whatever comes to read it. That is a much larger change than "add a payment
gateway", so it was not done inside this task.

**The consequence, stated plainly: `payments` is populated for gateway
payments and nothing else.** Anyone who later treats that table as the
complete record of money taken will be wrong. Either finish the job (write
`payments` rows for all methods from `BillingService`) or keep reading
`sales.payment_methods`. Do not read both and assume they agree.

## Collection happens before the sale exists

`payments.sale_id` is a real foreign key to `sales(id)`, and this app takes
payment *inside* the payment dialog and only then calls
`BillingService.processSale`. At the moment a gateway order is created, the
sale row does not exist, so `sale_id` cannot be set — inserting one fails at
the database (this is enforced; there is a test for it).

The flow is therefore split:

1. `PaymentGatewayService.createOrder(...)` with **no** `saleId` — writes the
   `payments` row and a `pending` transaction.
2. Customer pays; `verifyAndRecordPayment` proves it and posts to the ledger.
3. `BillingService.processSale` writes the sale.
4. `PaymentGatewayService.attachSale(...)` links the two.

Step 4 is deliberately non-fatal in `billing_screen.dart`. The money is
already taken and recorded by then; failing a completed sale over a missing
link would be much worse than a payment row somebody has to join up by hand.

## What posts to the ledger, and what does not

**A successful gateway payment posts no revenue.** The sale's own entries
(Phase 1's `GLService.postSaleEntries`) already credited Sales Revenue for the
whole bill. A gateway payment is not a second sale — it is the shop learning
*how* that amount was settled. `GLService.postGatewayPaymentEntries` therefore
only ever moves the same money between two asset accounts:

| The sale recorded the amount as | Debit | Credit |
|---|---|---|
| cash at the till (the default)  | `1010` Bank | `1000` Cash |
| owed by the customer (`settlesReceivable: true`) | `1010` Bank | `1100` Accounts Receivable |

Net effect on total assets: nil, which is correct. Nothing new was earned; the
money was only ever in the wrong account. There is a test asserting account
`4000` stays at zero across a gateway payment, because double-counting the
day's takings is the obvious way to get this wrong.

A refund reverses those entries by reference, so the journal shows the
original and its reversal as a pair rather than erasing anything.

**Settlements post nothing at all, including their fees.** See the gaps
section below.

## The gateway abstraction

`lib/services/gateways/`:

- `payment_gateway.dart` — the `PaymentGateway` interface
  (`createOrder` / `verifyPayment` / `refund` / `getStatus`) plus its result
  types and `PaymentGatewayException`.
- `razorpay_gateway.dart` — the only real implementation.
- `stub_gateways.dart` — `PayPalGateway` and `SquareGateway`, every method
  throwing `UnimplementedError`, `isConfigured` permanently false so they can
  never appear at the till.

Razorpay specifics worth knowing:

- **Rupees in, paise on the wire.** Conversion happens in exactly two private
  functions so a factor-of-100 error is not possible elsewhere. `_toPaise`
  rounds rather than truncates — ₹10.005 would otherwise undercharge.
- **Verification is two things, both required.** The HMAC-SHA256 signature
  over `"<order_id>|<payment_id>"` proves the callback came from someone
  holding the shared secret; a follow-up status call proves the payment
  actually *captured*. A valid signature over a failed payment does not
  settle a sale. Signature comparison is constant-time.
- **`authorized` maps to `pending`, not success.** Money authorised is not
  money taken, and a POS must not let a customer leave on an authorisation
  that is never captured.

## Credentials

Stored on the `stores` row (`razorpay_enabled`, `razorpay_key_id`,
`razorpay_key_secret`), read through `StoreRepository.getRazorpayConfig()`,
edited in Settings → Payment Gateways. This follows the pattern this app
already uses for the Ollama and printer configuration.

The task file rules out a checked-in `payment_config.dart` with literal keys,
and that rule is respected — no key or secret exists anywhere in this
repository. Note that `supabase_sync_service.dart` *does* hold placeholder
constants; that is the older pattern and was not followed here.

**Be honest about what this protects against.** Keys are out of source
control, which is the thing that actually matters. They are *not* encrypted at
rest: the SQLite file on the till holds the key secret in plain text, and a
gateway key secret on a shop-floor machine is a real exposure. Use a
restricted key where the gateway offers one, and treat the till's disk as
sensitive. Encrypting it properly needs a key this app has nowhere to keep.

## Idempotency

`payment_gateway_transactions.gateway_transaction_id` is `UNIQUE`. This is
load-bearing, not decoration: a retried or replayed confirmation for the same
gateway payment must not be able to credit the shop twice.
`verifyAndRecordPayment` checks for a duplicate before spending a network
call and throws `DuplicateGatewayPayment`; the constraint underneath is what
catches anything that gets past the check.

When a *signature* fails, the claimed payment id is deliberately **not**
stamped onto the failed row — otherwise an unverified caller could burn a real
payment id by claiming it against a bad signature.

## UI

- **Settings → Payment Gateways** — enable Razorpay, key id, masked secret.
- **Payment Gateways screen** (`/payment-gateways`, manager-gated) —
  transactions with status/refund/status-check, settlements with recording and
  reconciliation.
- **Billing** — a configured gateway appears in the payment dialog's method
  dropdown next to Cash/UPI/Card/Credit. Its amount **cannot be typed**: the
  cashier presses "Collect", `GatewayCollectDialog` takes and verifies the
  payment, and only a verified amount enters the split. A shop with no gateway
  configured sees the dialog exactly as before.

### Why the cashier types the payment id and signature

A phone app would use Razorpay's checkout SDK and get these in a callback.
This is a desktop/Windows POS with no such SDK, so the customer pays against
the order (UPI link, hosted checkout on their own phone) and the till confirms
with what the gateway returns. **Nothing typed is trusted** — it goes straight
to signature verification against the shop's own secret, then to a status
check with the gateway. An invented value fails and records a failed attempt.

## Known gaps

Listed rather than quietly dropped; also in `tasks/phase2/PROGRESS.md`.

- **`payments` is populated only for gateway payments** — see above.
- **Settlement fees are not posted to the GL.** The money reached `1010` Bank
  when each payment was verified; a payout is the gateway moving its own
  float. The fee genuinely is an expense, but booking it correctly needs a
  gateway-clearing account and a posting rule for the gap between "collected"
  and "deposited" — an accounting decision for a human, and one the task file
  does not ask for. The chart of accounts has no payment-processing-fee
  account either. `reconcileSettlement` surfaces the fee instead of burying
  it.
- **Partial refunds are refused.** The GL posting is a two-line
  reclassification; reversing part of it means deciding how a part-refunded
  sale is represented, which is a sale-level question. `SalesReturnService` is
  where a partial refund belongs.
- **No webhook listener.** This app has no server and no background job
  runner, so a payment whose callback never arrives is recovered by a cashier
  pressing "Check with gateway", not automatically. `refreshStatus`
  deliberately cannot settle a payment it finds successful — that would skip
  the signature check.
- **Settlement figures are entered by hand**, not fetched from the gateway's
  settlements API.
- **No widget tests** for the new screens or the dialog, following this
  codebase's convention — it has essentially none. Service, repository and
  gateway logic is covered by 90 tests.
