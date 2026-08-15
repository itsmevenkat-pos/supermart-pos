import 'package:sqflite/sqflite.dart';

/// Payment gateway integration (Phase 2, Task 2.3).
///
/// Two tables plus the per-store gateway credentials.
///
/// **`payment_gateway_transactions.payment_id` points at the `payments`
/// table, which nothing in this app has ever written to.** `payments` has
/// existed since `MigrationV1` and has zero readers or writers in `lib/` —
/// what a sale actually records is the `sales.payment_methods` JSON map. The
/// task file for this module assumed every payment already flows through
/// `payments`; it does not. Rather than invent a third place a payment can
/// live, [PaymentGatewayService] becomes the table's first writer: a gateway
/// payment gets a real `payments` row and the gateway-specific detail hangs
/// off it one-to-one, exactly the shape the task file describes. Cash and
/// card sales are untouched and still record only the JSON map, so `payments`
/// is populated for gateway payments and nothing else — see
/// `docs/PAYMENT_GATEWAY_ARCHITECTURE.md` for why that asymmetry was
/// preferred over rewriting the whole billing path in this task.
///
/// `gateway_transaction_id` is UNIQUE because it is the gateway's own id for
/// the payment (`pay_XXX` on Razorpay). That constraint is what makes
/// recording a payment idempotent under a retried callback: a duplicate
/// verify for the same gateway payment hits the constraint instead of
/// crediting the shop twice. It is nullable because a transaction exists from
/// the moment an order is created, before any payment id exists.
///
/// Credentials live on `stores`, matching how this app already stores the
/// Ollama and printer configuration — not in a checked-in constants file. See
/// the architecture doc for the honest limitations of holding a gateway key
/// secret on a POS terminal.
///
/// Like [MigrationV28], [MigrationV30] and [MigrationV31] this runs from both
/// paths — `onUpgrade` (`oldVersion < 32`) and `onCreate` (via `MigrationV1`,
/// which delegates here). Every statement is `IF NOT EXISTS` or an
/// `ADD COLUMN` in a try/catch, so running it against a database that already
/// has the schema is a no-op.
class MigrationV32 {
  static Future<void> up(Database db) async {
    // ------------------------------------------- gateway transaction detail
    await db.execute('''
      CREATE TABLE IF NOT EXISTS payment_gateway_transactions (
        id TEXT PRIMARY KEY,
        payment_id TEXT NOT NULL REFERENCES payments(id),
        gateway TEXT NOT NULL,
        gateway_order_id TEXT,
        gateway_transaction_id TEXT UNIQUE,
        status TEXT NOT NULL DEFAULT 'pending',
        gateway_response TEXT,
        created_at INTEGER NOT NULL,
        completed_at INTEGER
      )
    ''');

    // ------------------------------------------------------- payout batches
    // What the gateway actually deposited, as the gateway reports it. Kept
    // separate from the transactions above because a settlement is the
    // gateway's aggregate of many payments minus its fee, and the shop only
    // ever learns it after the fact.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS payment_settlements (
        id TEXT PRIMARY KEY,
        gateway TEXT NOT NULL,
        settlement_date INTEGER NOT NULL,
        transaction_count INTEGER NOT NULL,
        total_amount REAL NOT NULL,
        fees_charged REAL NOT NULL DEFAULT 0,
        settled_amount REAL NOT NULL,
        settlement_reference TEXT,
        created_at INTEGER NOT NULL
      )
    ''');

    // ------------------------------------------------------------- indexes
    // "Show me the gateway detail for this payment" — the one-to-one lookup.
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_pgt_payment ON payment_gateway_transactions(payment_id)',
    );
    // "What is still pending / what failed on Razorpay today" — the status
    // dashboard and the stale-pending sweep both filter on this pair.
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_pgt_gateway_status ON payment_gateway_transactions(gateway, status)',
    );
    // Settlement reconciliation walks transactions by completion date to work
    // out which ones a payout covers.
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_pgt_completed_at ON payment_gateway_transactions(completed_at)',
    );
    // The settlements list is always "this gateway, most recent first".
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_settlements_gateway_date ON payment_settlements(gateway, settlement_date)',
    );

    // ----------------------------------------------- per-store credentials
    // Disabled by default with empty keys: upgrading to v32 must not make a
    // till start offering a payment method the shop has not configured.
    try {
      await db.execute('ALTER TABLE stores ADD COLUMN razorpay_enabled INTEGER NOT NULL DEFAULT 0');
    } catch (_) {
      // Column may already exist on some upgrade paths — safe to ignore.
    }
    try {
      await db.execute('ALTER TABLE stores ADD COLUMN razorpay_key_id TEXT');
    } catch (_) {
      // Column may already exist on some upgrade paths — safe to ignore.
    }
    try {
      await db.execute('ALTER TABLE stores ADD COLUMN razorpay_key_secret TEXT');
    } catch (_) {
      // Column may already exist on some upgrade paths — safe to ignore.
    }
  }
}
