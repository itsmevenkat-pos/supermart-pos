# Task 2.3: Payment Gateway Integration

Read [README.md](README.md) first. Confirmed genuinely not built — no
Razorpay/PayPal/Square references anywhere in `lib/`.

## Integrate with the existing `payments` table — don't replace it

This app already has a generic `payments` table (since `migration_v1.dart`):
`id, sale_id, customer_id, amount, method, reference_no, payment_date`. Every
sale's payment already flows through this, cash or otherwise. The original
task draft's `payment_orders`/`payment_transactions` design duplicates this
concept with a second `sale_id`-linked table — don't do that. Instead:

```sql
CREATE TABLE payment_gateway_transactions (
  id TEXT PRIMARY KEY,
  payment_id TEXT NOT NULL REFERENCES payments(id),
  gateway TEXT NOT NULL, -- 'razorpay' | 'paypal' | 'square'
  gateway_order_id TEXT,
  gateway_transaction_id TEXT UNIQUE,
  status TEXT NOT NULL DEFAULT 'pending', -- 'pending' | 'success' | 'failed' | 'refunded'
  gateway_response TEXT, -- raw JSON, for debugging/audit
  created_at INTEGER NOT NULL,
  completed_at INTEGER
);

CREATE TABLE payment_settlements (
  id TEXT PRIMARY KEY,
  gateway TEXT NOT NULL,
  settlement_date INTEGER NOT NULL,
  transaction_count INTEGER NOT NULL,
  total_amount REAL NOT NULL,
  fees_charged REAL NOT NULL DEFAULT 0,
  settled_amount REAL NOT NULL,
  settlement_reference TEXT,
  created_at INTEGER NOT NULL
);

CREATE INDEX idx_pgt_payment ON payment_gateway_transactions(payment_id);
CREATE INDEX idx_pgt_gateway_status ON payment_gateway_transactions(gateway, status);
```

`payments.method` gets the gateway name (`'razorpay'`, etc.) same as it
already stores `'Cash'`/`'Card'`/whatever this app currently uses — check
existing `method` values in the billing flow before inventing new ones, so
reports that group by `method` keep working. The `payments` row is created
the same way it already is today; `payment_gateway_transactions` is
gateway-specific detail hung off it, one-to-one.

## Abstraction layer

The `PaymentGateway` abstract class / `RazorpayGateway` implementation from
the original draft is reasonable — keep that shape
(`createOrder`/`verifyPayment`/`refund`/`getStatus`). Only implement
**Razorpay** for real in this task (it's the one with actual India UPI/card
relevance for this app's market — same reasoning the original draft used to
rank it first). Stub `PayPalGateway`/`SquareGateway` behind the same
interface with a clear `UnimplementedError` rather than half-implementing
three gateways — a broken partial integration is worse than an honest stub.

**Do not hardcode API keys anywhere in the repo** (the original draft's
`payment_config.dart` with literal `apiKey`/`apiSecret` fields is not
acceptable, even as a placeholder — check how this app already handles
secrets, e.g. Supabase/backup service credentials in Settings, and follow
that pattern for gateway keys instead).

## GL integration

On a successful gateway payment, post through `GLService`
(`lib/services/gl_service.dart`, already exists from Phase 1) —
debit Bank (`1010`), credit whatever the sale already credits (don't
double-post; the sale's own GL entries from Phase 1's `postSaleEntries`
already credit Sales Revenue for the sale total. The gateway payment isn't
a second sale event, it's just *how* the receivable/cash side got settled —
if the sale was cash/receivable at `1000`/`1100`, adjust `signedBalance`
between those and `1010` Bank instead of posting new revenue).

## UI

Payment method selection in `billing_screen.dart`'s existing payment flow —
check how cash/card are currently selected there before adding gateway
options as a fully separate screen.

## Tests

Unit tests for order creation, signature verification (mock the HTTP call —
don't hit real Razorpay in tests), and the GL posting math. Integration
test: full flow from sale → gateway payment success → GL entries correct,
using a mocked gateway response.

## Done when

`flutter analyze` clean, tests pass (mocked gateway calls only, no real API
keys needed to run the suite), full existing suite still green.
