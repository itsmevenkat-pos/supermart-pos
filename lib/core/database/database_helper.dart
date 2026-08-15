import 'dart:convert';
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'migrations/migration_v1.dart';
import 'migrations/migration_v13.dart';
import 'migrations/migration_v15.dart';
import 'migrations/migration_v16.dart';
import 'migrations/migration_v17.dart';
import 'migrations/migration_v18.dart';
import 'migrations/migration_v19.dart';
import 'migrations/migration_v24.dart';
import 'migrations/migration_v26.dart';
import 'migrations/migration_v28.dart';
import 'migrations/migration_v29.dart';
import 'migrations/migration_v30.dart';
import '../../constants/app_constants.dart';

class DatabaseHelper {
  DatabaseHelper._privateConstructor();
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  /// The on-disk path of the live database file — for backup/restore.
  /// Computed the same way as [_initDatabase] so it always points at the
  /// exact file actually in use, not a guess at a similar-looking path.
  Future<String> getDatabasePath() async {
    final appDir = await getApplicationDocumentsDirectory();
    return join(appDir.path, AppConstants.dbName);
  }

  /// Closes the cached connection so the underlying file is safe to
  /// overwrite (e.g. during restore) or copy without a concurrent writer.
  /// The next call to [database] transparently reopens it.
  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }

  Future<Database> _initDatabase() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    // ✅ Use application documents directory (persistent)
    final appDir = await getApplicationDocumentsDirectory();
    final dbPath = join(appDir.path, AppConstants.dbName);

    // Ensure directory exists
    final dir = Directory(dirname(dbPath));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    return await openDatabase(
      dbPath,
      version: AppConstants.dbVersion,
      // SQLite ignores FK constraints (ON DELETE CASCADE/SET NULL/RESTRICT
      // etc.) unless this pragma is set on every connection — it is NOT
      // persisted in the database file itself, so it must run here, not
      // just once in a migration.
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await MigrationV1.up(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 3) {
          await db.execute('''
            CREATE TABLE quotations (
              id TEXT PRIMARY KEY,
              store_id TEXT REFERENCES stores(id) ON DELETE CASCADE,
              customer_id TEXT REFERENCES customers(id) ON DELETE SET NULL,
              customer_name TEXT NOT NULL,
              customer_phone TEXT,
              customer_email TEXT,
              quote_no TEXT NOT NULL,
              subtotal REAL NOT NULL DEFAULT 0,
              tax_total REAL NOT NULL DEFAULT 0,
              discount_total REAL NOT NULL DEFAULT 0,
              discount_reason TEXT,
              net_amount REAL NOT NULL DEFAULT 0,
              notes TEXT,
              expiry_date INTEGER,
              status TEXT DEFAULT 'pending',
              created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
              updated_at INTEGER
            )
          ''');
          await db.execute('CREATE INDEX idx_quotations_customer ON quotations(customer_id)');
          await db.execute('CREATE INDEX idx_quotations_status ON quotations(status)');
          // Note: no manual db.setVersion() call here — sqflite sets
          // PRAGMA user_version to `newVersion` automatically once
          // onUpgrade returns successfully. Calling setVersion mid-callback
          // is redundant — better to let sqflite own it.
        }

        if (oldVersion < 4) {
          // `products.barcode` used to be UNIQUE, which meant a purchase
          // entry for the same barcode at a new MRP silently overwrote the
          // one existing row — so older stock on the shelf ended up showing
          // the new MRP too. Recreate the table without that constraint so
          // a barcode can have one row per MRP; billing's MRP-selection
          // dialog already handles multiple rows per barcode, it just
          // couldn't get more than one written to disk before this.
          // Renaming `products` directly would make SQLite rewrite the FK
          // definitions in every child table (purchase_items, stock_ledger,
          // ...) to point at the renamed name — so dropping that renamed
          // table afterward orphans those child rows. Instead build the
          // replacement under a temp name first: nothing references that
          // temp name, so child tables' FK text never changes, and once we
          // rename the temp table to `products` at the end those FKs are
          // simply valid again.
          await db.execute('PRAGMA foreign_keys = OFF');
          await db.execute('''
            CREATE TABLE products_new (
              id TEXT PRIMARY KEY,
              store_id TEXT REFERENCES stores(id) ON DELETE CASCADE,
              barcode TEXT NOT NULL,
              name TEXT NOT NULL,
              search_name TEXT,
              display_name TEXT,
              category_id TEXT REFERENCES categories(id) ON DELETE SET NULL,
              unit TEXT DEFAULT 'Pcs',
              mrp REAL NOT NULL DEFAULT 0,
              retail_price REAL NOT NULL DEFAULT 0,
              wholesale_price REAL NOT NULL DEFAULT 0,
              cost_price REAL NOT NULL DEFAULT 0,
              tax_rate REAL NOT NULL DEFAULT 0,
              stock_quantity INTEGER NOT NULL DEFAULT 0,
              reorder_level INTEGER NOT NULL DEFAULT 5,
              bonus_eligible INTEGER DEFAULT 1,
              is_active INTEGER DEFAULT 1,
              is_deleted INTEGER DEFAULT 0,
              created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
              updated_at INTEGER
            )
          ''');
          await db.execute('INSERT INTO products_new SELECT * FROM products');
          await db.execute('DROP TABLE products');
          await db.execute('ALTER TABLE products_new RENAME TO products');
          await db.execute('CREATE INDEX idx_products_barcode ON products(barcode)');
          await db.execute('CREATE INDEX idx_products_search_name ON products(search_name)');
          await db.execute('PRAGMA foreign_keys = ON');
        }

        if (oldVersion < 5) {
          // New default categories for existing installs. ConflictAlgorithm
          // .ignore means this is safe to run even if a category with the
          // same id already exists — it won't duplicate or throw.
          final newCategories = [
            {'id': 'cat_fruits_veg', 'name': 'Fruits & Vegetables', 'allow_negative_stock': 1},
            {'id': 'cat_grocery_staples', 'name': 'Grocery & Staples', 'allow_negative_stock': 0},
            {'id': 'cat_personal_care', 'name': 'Personal Care', 'allow_negative_stock': 0},
            {'id': 'cat_health_wellness', 'name': 'Health & Wellness', 'allow_negative_stock': 0},
            {'id': 'cat_baby_care', 'name': 'Baby Care', 'allow_negative_stock': 0},
            {'id': 'cat_frozen_foods', 'name': 'Frozen Foods', 'allow_negative_stock': 1},
            {'id': 'cat_meat_fish_eggs', 'name': 'Meat, Fish & Eggs', 'allow_negative_stock': 1},
            {'id': 'cat_cleaning_home', 'name': 'Cleaning & Home Care', 'allow_negative_stock': 0},
            {'id': 'cat_stationery_gifts', 'name': 'Stationery & Gifts', 'allow_negative_stock': 0},
            {'id': 'cat_pooja_festive', 'name': 'Pooja & Festive Needs', 'allow_negative_stock': 0},
            {'id': 'cat_pet_care', 'name': 'Pet Care', 'allow_negative_stock': 0},
            {'id': 'cat_confectionery', 'name': 'Confectionery & Chocolates', 'allow_negative_stock': 0},
          ];
          for (final cat in newCategories) {
            await db.insert('categories', cat, conflictAlgorithm: ConflictAlgorithm.ignore);
          }
        }

        if (oldVersion < 6) {
          // Round Off wasn't tracked before — add it for existing installs.
          // (Existing sales rows get round_off = 0 via the column default,
          // which is correct since round off wasn't applied to any past
          // sale.)
          try {
            await db.execute('ALTER TABLE sales ADD COLUMN round_off REAL DEFAULT 0');
          } catch (_) {
            // Column may already exist on some upgrade paths — safe to ignore.
          }
        }

        if (oldVersion < 7) {
          // Per-product negative-stock override, on top of the existing
          // category-level allowNegativeStock. Defaults to off for every
          // existing product — nothing changes in behavior until someone
          // explicitly turns it on for a specific item.
          try {
            await db.execute('ALTER TABLE products ADD COLUMN allow_negative_stock INTEGER DEFAULT 0');
          } catch (_) {
            // Column may already exist on some upgrade paths — safe to ignore.
          }
        }

        if (oldVersion < 8) {
          // Snapshot the product's cost price onto each sale line at sale
          // time, so profit reports can compute real COGS-based profit
          // instead of approximating it from purchase totals (see
          // ReportService.getProfitLoss). Existing rows default to 0 —
          // historical bills predate cost tracking here and can't be
          // retroactively reconstructed.
          try {
            await db.execute('ALTER TABLE sale_items ADD COLUMN cost_price REAL NOT NULL DEFAULT 0');
          } catch (_) {
            // Column may already exist on some upgrade paths — safe to ignore.
          }
        }

        if (oldVersion < 9) {
          // Customer credit/khata previously had no transaction-level
          // history — just a single mutated outstanding_balance field on
          // `customers`, with no way to see what made up that number or to
          // record a payment against it. This mirrors the existing, working
          // `supplier_ledger` table/pattern.
          await db.execute('''
            CREATE TABLE IF NOT EXISTS customer_ledger (
              id TEXT PRIMARY KEY,
              customer_id TEXT REFERENCES customers(id) ON DELETE CASCADE,
              reference_type TEXT NOT NULL,
              reference_id TEXT NOT NULL,
              amount REAL NOT NULL,
              balance REAL NOT NULL,
              note TEXT,
              created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
            )
          ''');
          await db.execute('CREATE INDEX IF NOT EXISTS idx_customer_ledger_customer ON customer_ledger(customer_id)');

          // Backfill one opening-balance entry per customer with a
          // nonzero balance, so existing dues are represented in the
          // ledger instead of appearing to come from nowhere.
          final customersWithBalance = await db.query(
            'customers',
            where: 'outstanding_balance != 0',
          );
          for (final customer in customersWithBalance) {
            final balance = (customer['outstanding_balance'] as num).toDouble();
            await db.insert('customer_ledger', {
              'id': const Uuid().v4(),
              'customer_id': customer['id'],
              'reference_type': 'opening_balance',
              'reference_id': customer['id'],
              'amount': balance,
              'balance': balance,
              'note': 'Opening balance carried over from before ledger tracking',
              'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
            });
          }
        }

        if (oldVersion < 10) {
          // Bill numbers were a raw sequential integer with no store
          // identifier or financial-year grouping, which auditors expect
          // (e.g. SM/25-26/00001). invoice_no itself stays exactly as-is —
          // it's the gapless legal sequence — this adds a formatted label
          // alongside it, backed by a per-financial-year counter so the
          // sequence portion resets each year without touching invoice_no.
          try {
            await db.execute("ALTER TABLE stores ADD COLUMN invoice_prefix TEXT NOT NULL DEFAULT 'SM'");
          } catch (_) {
            // Column may already exist on some upgrade paths — safe to ignore.
          }
          await db.execute('''
            CREATE TABLE IF NOT EXISTS invoice_counters (
              financial_year TEXT PRIMARY KEY,
              next_seq INTEGER NOT NULL DEFAULT 1
            )
          ''');
          try {
            await db.execute('ALTER TABLE sales ADD COLUMN invoice_display_no TEXT');
          } catch (_) {
            // Column may already exist on some upgrade paths — safe to ignore.
          }
          // Existing bills keep invoice_display_no = NULL rather than being
          // retroactively renumbered — reprinting an already-issued invoice
          // under a new number would break the audit trail it's meant to
          // protect. The UI falls back to the plain invoice_no for those.
        }

        if (oldVersion < 11) {
          // Business Profile screen needs more than just name/invoice_prefix
          // on `stores` — GSTIN, contact details, classification, and
          // logo/signature image paths for printed invoices.
          for (final column in [
            'phone TEXT',
            'gstin TEXT',
            'email TEXT',
            'business_type TEXT',
            'business_category TEXT',
            'address TEXT',
            'state TEXT',
            'pincode TEXT',
            'logo_path TEXT',
            'signature_path TEXT',
          ]) {
            try {
              await db.execute('ALTER TABLE stores ADD COLUMN $column');
            } catch (_) {
              // Column may already exist on some upgrade paths — safe to ignore.
            }
          }
        }

        if (oldVersion < 12) {
          // Utilities: Track Your Salesmen + Close Financial Year.
          await db.execute('''
            CREATE TABLE IF NOT EXISTS salesmen (
              id TEXT PRIMARY KEY,
              store_id TEXT REFERENCES stores(id) ON DELETE CASCADE,
              name TEXT NOT NULL,
              phone TEXT,
              is_active INTEGER NOT NULL DEFAULT 1,
              created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
            )
          ''');
          try {
            await db.execute('ALTER TABLE sales ADD COLUMN salesman_id TEXT REFERENCES salesmen(id) ON DELETE SET NULL');
          } catch (_) {
            // Column may already exist on some upgrade paths — safe to ignore.
          }
          await db.execute('''
            CREATE TABLE IF NOT EXISTS financial_year_closures (
              id TEXT PRIMARY KEY,
              financial_year TEXT NOT NULL UNIQUE,
              closed_at INTEGER NOT NULL,
              closed_by_user_id TEXT REFERENCES users(id) ON DELETE SET NULL,
              notes TEXT
            )
          ''');
        }

        if (oldVersion < 13) {
          // Advanced Reports: HSN/SAC-grouped GST reports need a code on
          // each product to group by. See MigrationV13.
          await MigrationV13.up(db);
        }

        if (oldVersion < 14) {
          // Multi-store Supabase sync (design stage — see
          // SUPABASE_SYNC_DESIGN.md): tracks the last time each pulled
          // table's master data was refreshed from Supabase, so
          // SupabaseSyncService only asks for rows updated since then
          // instead of re-pulling everything every sync.
          await db.execute('''
            CREATE TABLE IF NOT EXISTS sync_state (
              table_name TEXT PRIMARY KEY,
              last_pulled_at INTEGER NOT NULL DEFAULT 0
            )
          ''');
        }

        if (oldVersion < 15) {
          // Returns/Refunds — see MigrationV15.
          await MigrationV15.up(db);
        }

        if (oldVersion < 16) {
          // Sale Cancellations + Exchanges — see MigrationV16.
          await MigrationV16.up(db);
        }

        if (oldVersion < 17) {
          // Product & Item Master completion — see MigrationV17.
          await MigrationV17.up(db);
        }

        if (oldVersion < 18) {
          // Configurable discount cap + bill remarks — see MigrationV18.
          await MigrationV18.up(db);
        }

        if (oldVersion < 19) {
          // Customer/CRM & Loyalty completion — see MigrationV19.
          await MigrationV19.up(db);
        }

        if (oldVersion < 20) {
          // Coupon codes — separate from `promotions` (which auto-apply),
          // these are customer-entered at checkout. See CouponRepository.
          await db.execute('''
            CREATE TABLE IF NOT EXISTS coupons (
              id TEXT PRIMARY KEY,
              code TEXT NOT NULL UNIQUE,
              type TEXT NOT NULL,
              value REAL NOT NULL,
              min_bill_amount REAL NOT NULL DEFAULT 0,
              max_uses INTEGER,
              times_used INTEGER NOT NULL DEFAULT 0,
              start_date INTEGER,
              end_date INTEGER,
              is_active INTEGER NOT NULL DEFAULT 1,
              created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
            )
          ''');
          await db.execute('CREATE INDEX IF NOT EXISTS idx_coupons_code ON coupons(code)');
        }

        if (oldVersion < 21) {
          // Weighing-scale barcode decoding — products.is_weighted existed
          // but nothing ever read it; a scale-printed barcode (item code +
          // embedded weight/price) just failed to match any product. See
          // decodeWeighingBarcode in weighing_barcode.dart. Empty prefix
          // (the default) means the feature stays off until a manager
          // configures it in Settings for their actual scale.
          try {
            await db.execute("ALTER TABLE stores ADD COLUMN weighing_barcode_prefix TEXT NOT NULL DEFAULT ''");
          } catch (_) {
            // Column may already exist on some upgrade paths — safe to ignore.
          }
          try {
            await db.execute(
                "ALTER TABLE stores ADD COLUMN weighing_barcode_value_type TEXT NOT NULL DEFAULT 'weight_grams'");
          } catch (_) {
            // Column may already exist on some upgrade paths — safe to ignore.
          }
        }

        if (oldVersion < 22) {
          // Pooled/shared stock groups — e.g. several ₹10 chip flavors
          // drawing from one common stock count instead of separate
          // per-flavor counts, so one flavor selling out doesn't read as a
          // stockout while siblings still have plenty. See
          // StockGroupRepository, especially propagateDelta.
          await db.execute('''
            CREATE TABLE IF NOT EXISTS stock_groups (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
            )
          ''');
          try {
            await db.execute('ALTER TABLE products ADD COLUMN stock_group_id TEXT REFERENCES stock_groups(id) ON DELETE SET NULL');
          } catch (_) {
            // Column may already exist on some upgrade paths — safe to ignore.
          }
          await db.execute('CREATE INDEX IF NOT EXISTS idx_products_stock_group ON products(stock_group_id)');
        }

        if (oldVersion < 23) {
          // Real ESC/POS thermal printer config — receipts previously only
          // ever rendered as a PDF through the OS print dialog. Type 'none'
          // (the default) keeps that PDF fallback; 'network' or 'windows'
          // switches billing's print action to raw ESC/POS bytes instead.
          // See thermal_print_service.dart / windows_printer.dart /
          // network_printer.dart.
          for (final column in [
            "printer_type TEXT NOT NULL DEFAULT 'none'",
            'printer_target TEXT',
            'printer_port INTEGER',
            'printer_chars_per_line INTEGER NOT NULL DEFAULT 32',
          ]) {
            try {
              await db.execute('ALTER TABLE stores ADD COLUMN $column');
            } catch (_) {
              // Column may already exist on some upgrade paths — safe to ignore.
            }
          }
        }

        if (oldVersion < 24) {
          // Price revision history — see MigrationV24.
          await MigrationV24.up(db);
        }

        if (oldVersion < 25) {
          // Ollama (local LLM) config for the AI Analysis report, and a
          // festival date calendar it and the festival-stock-suggestion
          // query compare historical sales against. Off/empty by default —
          // AI Analysis falls back to plain data-only reports until a
          // manager enables it in Settings with a running local Ollama.
          for (final column in [
            'ollama_enabled INTEGER NOT NULL DEFAULT 0',
            "ollama_base_url TEXT NOT NULL DEFAULT 'http://localhost:11434'",
            "ollama_model TEXT NOT NULL DEFAULT 'llama3.2'",
          ]) {
            try {
              await db.execute('ALTER TABLE stores ADD COLUMN $column');
            } catch (_) {
              // Column may already exist on some upgrade paths — safe to ignore.
            }
          }

          await db.execute('''
            CREATE TABLE IF NOT EXISTS festival_calendar (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              month INTEGER NOT NULL,
              day INTEGER NOT NULL,
              notes TEXT,
              is_active INTEGER NOT NULL DEFAULT 1
            )
          ''');

          for (final festival in _defaultFestivals) {
            await db.insert('festival_calendar', festival, conflictAlgorithm: ConflictAlgorithm.ignore);
          }
        }

        if (oldVersion < 26) {
          // Loyalty earn-rate as a real per-store setting — see MigrationV26.
          await MigrationV26.up(db);
        }

        if (oldVersion < 27) {
          // `products.unitsPerPurchaseUnit` (e.g. 12 Pcs per Box) was stored
          // and editable but nothing ever multiplied by it when receiving
          // stock. These two columns let a purchase line record whether its
          // quantity/freeQuantity were entered in the product's purchaseUnit
          // (Box/Case) rather than its base stock unit, plus a snapshot of
          // the conversion factor at entry time — so PurchaseRepository can
          // convert to the correct stock delta, and an edit/delete later
          // reverses that exact same factor even if the product's
          // conversion is changed afterward. Defaults (0 / 1) are a no-op
          // for every existing row, so past purchases are unaffected.
          try {
            await db.execute('ALTER TABLE purchase_items ADD COLUMN is_purchase_unit_entry INTEGER DEFAULT 0');
          } catch (_) {
            // Column may already exist on some upgrade paths — safe to ignore.
          }
          try {
            await db.execute('ALTER TABLE purchase_items ADD COLUMN purchase_unit_factor REAL DEFAULT 1');
          } catch (_) {
            // Column may already exist on some upgrade paths — safe to ignore.
          }
        }

        if (oldVersion < 28) {
          // General Ledger: chart of accounts, double-entry journal and the
          // per-financial-year balance cache — see MigrationV28. MigrationV1
          // calls the same method, so onCreate and onUpgrade produce
          // identical GL schema and the same seeded accounts.
          await MigrationV28.up(db);
        }

        if (oldVersion < 29) {
          // Bank reconciliation: bank account master, imported statements and
          // their lines — see MigrationV29. MigrationV1 calls the same method,
          // so onCreate and onUpgrade produce identical schema.
          await MigrationV29.up(db);
        }

        if (oldVersion < 30) {
          // Loyalty point event log + expiry. Widens the existing
          // `bonus_points` table rather than adding a second events table —
          // see MigrationV30 for why. `stores.loyalty_points_expiry_days`
          // defaults to 0 (never expire), so this upgrade does not change any
          // customer's balance. MigrationV1 calls the same method.
          await MigrationV30.up(db);
        }
      },
    );
  }

  // Seeded Tamil Nadu festival calendar — editable afterward from Settings
  // → Utilities → Festival Calendar. Fixed-date (solar) festivals are
  // accurate every year; lunar-calendar ones shift, so their seeded day is
  // only a rough placeholder flagged in `notes` for a manager to correct
  // each year.
  static const _defaultFestivals = [
    {'id': 'fest_pongal', 'name': 'Pongal', 'month': 1, 'day': 14, 'notes': null, 'is_active': 1},
    {'id': 'fest_tamil_new_year', 'name': 'Tamil New Year', 'month': 4, 'day': 14, 'notes': null, 'is_active': 1},
    {
      'id': 'fest_aadi_perukku',
      'name': 'Aadi Perukku',
      'month': 8,
      'day': 3,
      'notes': 'Approximate — falls on the 18th day of the Tamil Aadi month, verify each year.',
      'is_active': 1,
    },
    {
      'id': 'fest_vinayagar_chaturthi',
      'name': 'Vinayagar Chaturthi',
      'month': 8,
      'day': 27,
      'notes': 'Lunar calendar — date shifts yearly, verify and update before relying on it.',
      'is_active': 1,
    },
    {
      'id': 'fest_navaratri',
      'name': 'Navaratri / Dussehra',
      'month': 10,
      'day': 2,
      'notes': 'Lunar calendar — date shifts yearly, verify and update before relying on it.',
      'is_active': 1,
    },
    {
      'id': 'fest_diwali',
      'name': 'Diwali / Deepavali',
      'month': 10,
      'day': 21,
      'notes': 'Lunar calendar — date shifts yearly, verify and update before relying on it.',
      'is_active': 1,
    },
    {'id': 'fest_christmas', 'name': 'Christmas', 'month': 12, 'day': 25, 'notes': null, 'is_active': 1},
    {'id': 'fest_new_year', 'name': "New Year's Day", 'month': 1, 'day': 1, 'notes': null, 'is_active': 1},
  ];

  /// Insert a sync-queue row. Pass [executor] as the active `txn` when
  /// calling this from inside a `database.transaction(...)` block — omitting
  /// it makes this run on a fresh top-level connection reference instead of
  /// the open transaction, which is not just non-atomic but can deadlock
  /// against that same transaction on sqflite.
  Future<void> queueSync(
    String table,
    String recordId,
    String operation,
    Map<String, dynamic> payload, {
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await database;
    await db.insert('sync_queue', {
      'id': const Uuid().v4(),
      'table_name': table,
      'record_id': recordId,
      'operation': operation,
      'payload_json': jsonEncode(payload),
      'retry_count': 0,
      'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    });
  }

  /// Insert an audit-log row. Pass [executor] as the active `txn` when
  /// calling this from inside a transaction — see [queueSync] for why.
  Future<void> logAudit({
    required String userId,
    required String actionType,
    required String tableName,
    required String recordId,
    String? oldValue,
    String? newValue,
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await database;
    await db.insert('audit_log', {
      'id': const Uuid().v4(),
      'user_id': userId,
      'action_type': actionType,
      'table_name': tableName,
      'record_id': recordId,
      'old_value': oldValue,
      'new_value': newValue,
      'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    });
  }
}