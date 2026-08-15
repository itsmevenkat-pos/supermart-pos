# General Ledger — Guide for whoever reconciles the books

For the person checking the shop's accounts, not for developers. The technical
side is in [GL_ARCHITECTURE.md](GL_ARCHITECTURE.md).

## Where to find the reports

**Reports → More → Accounts (General Ledger)** — Trial Balance, Profit & Loss
and Balance Sheet.

Each one picks its own **financial year** (the `25-26` style label, 1 April to
31 March) from the dropdown at the top, rather than the from/to date filter the
other reports use. Every report has an **Export CSV** button.

## What the app records on its own

You do not enter journal entries by hand for normal trade. Every completed
sale, purchase and sales return writes its own ledger entries as it is saved:

| What happened | What the ledger records |
|---|---|
| Sale paid in cash | Cash goes up, Sales Revenue goes up |
| Sale on credit | Accounts Receivable goes up (what customers owe), Sales Revenue goes up |
| Part-paid sale | Split between Cash and Accounts Receivable |
| Purchase received | Inventory goes up, Accounts Payable goes up (what you owe suppliers) |
| Sales return | Sales Revenue comes down, and Cash (or Accounts Receivable, if the refund was adjusted against the customer's balance) comes down |

Because both halves are always recorded together, the books balance
automatically. Nothing needs to be balanced by hand.

## Reading the three reports

### Trial Balance

A list of every account and its balance, in a debit column or a credit column,
with a total at the bottom of each. **The two totals should be equal.** This is
the quickest check that the books are internally consistent.

It is not a summary of profit or of what the shop is worth — it is a
correctness check. Use the other two for meaning.

### Profit & Loss

What the shop earned and spent over the financial year:

- **Total Revenue** — sales, net of returns.
- **Cost of Goods Sold** — what the goods that were sold actually cost.
- **Gross Profit** — revenue less cost of goods sold.
- **Operating & Other Expenses** — rent, salaries, utilities and so on.
- **Net Profit** (or **Net Loss**) — what is left after everything.

> **Cost of Goods Sold currently shows 0.00**, so Gross Profit is the same as
> Total Revenue on this report. Nothing posts to the Cost of Goods Sold account
> yet — this is a known gap, not a sign your data is wrong. Until it is
> filled, use the existing **Reports → Profit & Loss tab** for a
> cost-of-goods figure; that one is computed from the cost price recorded on
> each sale line.

### Balance Sheet

What the shop owns, owes, and what is left over for the owner, as at the end of
the financial year:

- **Assets** — cash, bank, stock, money customers owe you, fixed assets like
  fittings and equipment.
- **Liabilities** — money you owe suppliers, loans.
- **Equity** — the owner's capital, plus this year's profit.

**Total Assets should equal Total Liabilities + Total Equity.**

The line "Current Year Profit (not yet posted)" is this year's profit shown
inside Equity. It is displayed only — it is not written into Retained Earnings
until the financial year is closed. That is normal and is how the statement
balances before year-end.

## "NOT balanced" — what it means and what to do

Both the Trial Balance and the Balance Sheet show a green banner when they
balance and a **red "NOT balanced"** banner, with the exact difference, when
they do not.

The app cannot create an unbalanced entry through normal use: an entry that
doesn't balance is rejected before anything is saved, and a sale whose ledger
entries can't be written is refused outright rather than saved half-recorded.
So a red banner means something reached the database another way — a restored
or hand-edited backup, a partial data import, or a bug.

The reports deliberately **show** this rather than hiding or "correcting" it.
If you see it:

1. Note the difference shown in the banner.
2. Note which financial year is selected — check the other years too.
3. Export the Trial Balance to CSV.
4. Send both to whoever maintains the app. Nothing here is fixed by re-entering
   transactions, and re-entering them will make it harder to trace.

## Closing a financial year is permanent

**Settings → Utilities → Close Financial Year.**

Closing is **one-way. There is no reopen anywhere in this app.** Once a year is
closed:

- No new ledger entry can be posted into it.
- **Existing entries in it can no longer be corrected**, because a correction
  is itself a new entry dated in the same year. This is the correct accounting
  outcome — a closed year's books do not move — but it means any correction
  must be made *before* you close.
- A sale or purchase dated in that year will be **refused**, not saved without
  its ledger entries.

Closing asks you to type the year label to confirm, for this reason.

Before closing, check that:

- The Trial Balance for the year is balanced.
- The Balance Sheet for the year is balanced.
- Every return, correction and adjustment for the year has been entered.

## Things worth knowing

- **Sales tax (GST) is included in Sales Revenue.** It is not separated into a
  tax liability account. Use the GST tab under Reports for tax figures.
- **Cancelled sales are not reflected in the ledger yet.** A cancelled sale
  leaves its original entries in place, so revenue for a period with
  cancellations will read high. Returns *are* handled correctly.
- **Accounts can be deactivated, never deleted.** Deleting one would orphan the
  history posted against it. Deactivating hides it from new entries and leaves
  past entries readable.
- **Nothing is ever deleted from the ledger.** A correction is added as an
  opposite entry that points back at the one it corrects, so the original stays
  visible. A corrected transaction therefore shows as two lines, not none.
