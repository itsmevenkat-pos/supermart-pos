# Multi-Store Supabase Sync — Design

Status: **designed and implemented in code, not yet connected to a live Supabase project.** `SupabaseSyncService.isConfigured` is `false` until real credentials are added — every method throws a clear "not set up" error rather than silently doing nothing. This document is what to follow when you're ready to turn it on.

## Why this design

The app already has a local outbox (`sync_queue`, written to by every repository on insert/update/delete — see `DatabaseHelper.queueSync` and its call sites in `product_repository.dart`, `customer_repository.dart`, `sale_repository.dart`, etc.). That existed before this work but nothing ever consumed it. This design turns it into a real push mechanism and adds a pull side for master data, rather than building a separate sync system from scratch.

## Conflict resolution — the explicit decision the original spec asked for

Different tables need different rules, because they behave differently:

| Table category | Tables | Sync direction | Conflict rule |
|---|---|---|---|
| **Append-only / transactional** | `sales`, `sale_items`, `purchases`, `purchase_items`, `stock_ledger`, `customer_ledger`, `supplier_ledger`, `payments` | Push only | **None possible.** Every row has a client-generated UUID primary key and is written exactly once by the store that created it — rows are never mutated after creation, only reversed via a new compensating row (see the existing reversal-ledger pattern in `purchase_repository.dart`). Two stores can never collide on the same id. |
| **Mutable master data** | `products`, `customers`, `suppliers` | Push + pull | **Last-Write-Wins by `updated_at`.** The simplest strategy that's tractable for a small chain. A remote row only overwrites the local one if it's genuinely newer. **Tradeoff, stated plainly:** if two stores edit the same customer/product within the same sync window, one edit silently loses. Acceptable at the scale of a few stores with the same owner; would need a real merge/CRDT strategy at bank-grade scale, which this is not attempting to be. |
| **Stock quantity specifically** | `products.stock_quantity` | **Never pulled** | This is the one deliberate exception to "products sync." Stock isn't a single authoritative number — it's the sum of that store's own `stock_ledger` entries. Pulling a remote value here would silently overwrite real local stock with whatever another store happens to have on the shelf. `SupabaseSyncService._pullTable` explicitly strips `stock_quantity` from every products update it applies. |
| **Categories** | `categories` | Not synced yet | This table has no `updated_at` column to diff against. Categories rarely change; add a timestamp column first if central category sync becomes a real need — don't guess at a sync strategy for a table with no way to tell what changed. |

## What's built (`lib/services/supabase_sync_service.dart`)

- **`pushPending()`** — drains `sync_queue` (oldest first, batched), upserts each row's `payload_json` to the matching Supabase table, deletes it from the queue on success, increments `retry_count` on failure. Table-agnostic: it never needs updating when some other table gains a column, because it just replays whatever `toJson()` produced at write time.
- **`pullMasterData()`** — pulls `products` (minus `stock_quantity`), `customers`, `suppliers`, each filtered to rows with `updated_at` newer than the last successful pull (tracked per-table in the new `sync_state` table), applying Last-Write-Wins.
- **`getStatus()`** — pending count, failed count (retry_count >= 5), last pull time. Wired into Settings → Multi-Store Sync, with a manual "Sync Now" button that runs push then pull.

## Setup steps (when you're ready to connect)

1. **Create a Supabase project** at supabase.com.
2. **Create the mirrored tables.** Same shape as the local SQLite schema for the tables in the table above — same column names (this app's push/pull code assumes 1:1 column names, since it just replays `toJson()`/reads raw rows). Every table needs an `id` (text/uuid) primary key and, for the pull-eligible tables (`products`, `customers`, `suppliers`), an `updated_at` column storing epoch seconds (same convention as SQLite here — `DateTime.now().millisecondsSinceEpoch ~/ 1000`).
3. **Decide on Row Level Security (RLS) before going further — this matters.** This design uses the Supabase **anon key** embedded in the app, with no per-user Supabase Auth login. That means:
   - **If you enable RLS with a permissive policy** (e.g. "anyone with the anon key can read/write"), anyone who extracts the anon key from the compiled app (not hard — it's just a string) has full read/write access to every store's data in your Supabase project. Acceptable only if you fully trust everyone who could get their hands on the app binary (e.g. a single owner running 2 stores they personally control).
   - **The more correct approach**, before connecting more than one trusted store, is to add real Supabase Auth (e.g. one login per store/device) and scope RLS policies to `auth.uid()` or a `store_id` claim, so a compromised anon key alone isn't enough. That's a real follow-on task, not done here — this design intentionally stops at "ready to connect for a single trusted owner," not "production-hardened multi-tenant."
4. **Paste credentials** into `SupabaseSyncService.supabaseUrl` / `supabaseAnonKey` (`lib/services/supabase_sync_service.dart`) — this flips `isConfigured` to `true` and the Settings screen's "Sync Now" starts working instead of showing the setup dialog.
5. **Test with two devices** pointed at the same project before trusting it with real data — create a sale on device A, confirm it appears (in the ledger sense — sales don't pull back down, but you should be able to see it in the Supabase table directly), then edit a product on device A and confirm device B picks it up on its next "Sync Now" and doesn't clobber device B's own stock count.

## What this doesn't do yet (in case you build toward it)

- No background/scheduled sync — "Sync Now" is manual. A periodic timer or a sync-on-app-resume hook would be the natural next step.
- No sync status indicator outside Settings (e.g. a small badge on the dashboard).
- No inter-store stock transfer flow — that's a separate feature (a "transfer" would need to write a stock_ledger entry on both the sending and receiving store, which today are separate local databases; the transfer UI itself doesn't exist).
- No central cross-store dashboard — that would be a separate reporting surface reading directly from Supabase rather than local SQLite, out of scope for this sync layer itself.
