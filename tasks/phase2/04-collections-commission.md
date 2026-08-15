# Task 2.4: Collections & Commission Settlement

Read [README.md](README.md) first. Both halves genuinely not built —
confirmed no `aging`/`dunning`/`collection` or `commission` references
anywhere in `lib/`.

## Part A: Accounts Receivable Aging & Collections

**No `due_date` exists on sales or customers.** The original draft's aging
buckets assume an invoice due date to age against — this app has no such
field (the only `due_date` in the schema is on `purchases`, i.e. what *you*
owe suppliers, unrelated). Age against the **credit sale's transaction
date** instead, via `customer_ledger` (already exists —
`lib/repositories/customer_ledger_repository.dart` — `referenceType='Sale'`
rows with positive `amount` are money owed). A customer's outstanding
balance is their ledger's running `balance`; days overdue = today minus the
`created_at` of the ledger entries that make up that outstanding amount
(oldest-unpaid-first, since payments should logically clear the oldest debt
first — FIFO, not proportionally across all open entries).

```sql
CREATE TABLE collection_activities (
  id TEXT PRIMARY KEY,
  customer_id TEXT NOT NULL REFERENCES customers(id),
  activity_type TEXT NOT NULL, -- 'call' | 'email' | 'sms' | 'whatsapp' | 'visit' | 'payment'
  scheduled_date INTEGER,
  completed_date INTEGER,
  status TEXT NOT NULL DEFAULT 'pending', -- 'pending' | 'completed' | 'skipped'
  notes TEXT,
  amount_collected REAL,
  created_at INTEGER NOT NULL
);
```

No separate `aging_analysis` table (the original draft's version) — aging
is computed on demand from `customer_ledger`, not stored/duplicated; a
stored aging snapshot goes stale the moment a payment comes in. No
`dunning_schedules` table either — a scheduled reminder is just a
`collection_activities` row with `status='pending'` and a future
`scheduled_date`.

**Sending actual SMS/WhatsApp reminders**: check whether
`lib/services/whatsapp_share_service.dart` already provides a hook to
reuse before building new send logic. If there's no SMS capability in this
app at all (there wasn't as of the last feature audit), don't add a new SMS
gateway dependency as a side effect of this task — scope this to *tracking*
dunning activities and reusing whatever channel(s) already exist; flag SMS
as a separate, out-of-scope integration if it's genuinely missing.

**Service**: `lib/services/collections_service.dart` —
`generateAgingReport({DateTime? asOf})` (returns customers grouped into
0-30/30-60/60-90/90+ day buckets from ledger data), `logActivity(...)`,
`scheduleFollowUp(...)`.

## Part B: Commission Settlement

`lib/models/salesman_model.dart` currently has no commission fields at all
— this is entirely new, not a gap-fill.

```sql
CREATE TABLE commission_rules (
  id TEXT PRIMARY KEY,
  salesman_id TEXT NOT NULL REFERENCES salesmen(id),
  rule_type TEXT NOT NULL, -- 'percentage' | 'tiered'
  base_rate REAL NOT NULL DEFAULT 0, -- e.g. 0.02 = 2%
  tiered_rates TEXT, -- JSON: [{"upTo": 50000, "rate": 0.02}, {"upTo": null, "rate": 0.03}]
  effective_from INTEGER NOT NULL,
  effective_to INTEGER,
  is_active INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE commission_ledger (
  id TEXT PRIMARY KEY,
  salesman_id TEXT NOT NULL REFERENCES salesmen(id),
  period_from INTEGER NOT NULL,
  period_to INTEGER NOT NULL,
  gross_sales REAL NOT NULL,
  commission_amount REAL NOT NULL,
  status TEXT NOT NULL DEFAULT 'calculated', -- 'calculated' | 'settled'
  settled_date INTEGER,
  UNIQUE(salesman_id, period_from, period_to)
);
```

Only implement `percentage` and `tiered` rule types (drop `slab`/`target`
from the original draft — check with the user before building those if
actually wanted; they need product decisions this task file doesn't
specify, e.g. what "slab per quantity range" means precisely here).

**Gross sales per salesman per period**: `Sale.salesmanId` already exists
(`lib/models/sale_model.dart`) — sum `sales.net_amount` (or whatever the
canonical bill-total field is; confirm against how existing sales reports
compute totals) grouped by `salesman_id` and date range. No schema gap
here.

**Service**: `lib/services/commission_service.dart` —
`calculateCommission(salesmanId, from, to)`, `createSettlement(...)`,
`markAsSettled(...)`. No "salary integration" (the original draft's
mention of linking to a salary module) — there's no salary/payroll module
in this app to integrate with; a settlement record with a free-text
`salary_reference` field (already in the table above) is as far as this
goes.

## Tests

Aging bucket boundaries (a ledger entry exactly 30 days old — which bucket?
Pick one, document it, test it). Commission calculation for both rule types
including a tier boundary. Follow the real in-memory-DB pattern from
`test/services/financial_year_close_service_test.dart`.

## Done when

`flutter analyze` clean, tests pass, full suite green.
