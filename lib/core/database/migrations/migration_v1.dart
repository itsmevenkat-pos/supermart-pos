import 'package:sqflite/sqflite.dart';
import '../../security/password_hasher.dart';
import 'migration_v28.dart';
import 'migration_v29.dart';
import 'migration_v30.dart';
import 'migration_v31.dart';
import 'migration_v32.dart';

class MigrationV1 {
  static Future<void> up(Database db) async {
    await db.execute('''
      CREATE TABLE stores (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        timezone TEXT DEFAULT 'UTC',
        invoice_prefix TEXT NOT NULL DEFAULT 'SM',
        phone TEXT,
        gstin TEXT,
        email TEXT,
        business_type TEXT,
        business_category TEXT,
        address TEXT,
        state TEXT,
        pincode TEXT,
        logo_path TEXT,
        signature_path TEXT,
        return_threshold_no_approval REAL DEFAULT 500,
        max_discount_percent_no_approval REAL DEFAULT 10,
        tier_bronze_min_spent REAL DEFAULT 2000,
        tier_silver_min_spent REAL DEFAULT 10000,
        tier_gold_min_spent REAL DEFAULT 25000,
        loyalty_value_per_point REAL DEFAULT 0.5,
        weighing_barcode_prefix TEXT NOT NULL DEFAULT '',
        weighing_barcode_value_type TEXT NOT NULL DEFAULT 'weight_grams',
        printer_type TEXT NOT NULL DEFAULT 'none',
        printer_target TEXT,
        printer_port INTEGER,
        printer_chars_per_line INTEGER NOT NULL DEFAULT 32,
        ollama_enabled INTEGER NOT NULL DEFAULT 0,
        ollama_base_url TEXT NOT NULL DEFAULT 'http://localhost:11434',
        ollama_model TEXT NOT NULL DEFAULT 'llama3.2',
        bonus_points_threshold REAL DEFAULT 300
      )
    ''');

    await db.execute('''
      CREATE TABLE festival_calendar (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        month INTEGER NOT NULL,
        day INTEGER NOT NULL,
        notes TEXT,
        is_active INTEGER NOT NULL DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE invoice_counters (
        financial_year TEXT PRIMARY KEY,
        next_seq INTEGER NOT NULL DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE users (
        id TEXT PRIMARY KEY,
        username TEXT UNIQUE NOT NULL,
        password_hash TEXT NOT NULL,
        role TEXT NOT NULL DEFAULT 'cashier',
        name TEXT NOT NULL,
        must_change_password INTEGER DEFAULT 1,
        is_active INTEGER DEFAULT 1,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
      )
    ''');

    await db.execute('''
      CREATE TABLE sessions (
        id TEXT PRIMARY KEY,
        user_id TEXT REFERENCES users(id) ON DELETE CASCADE,
        opening_time INTEGER NOT NULL,
        closing_time INTEGER,
        opening_cash REAL NOT NULL DEFAULT 0,
        opening_denominations TEXT,
        closing_cash REAL DEFAULT 0,
        closing_denominations TEXT,
        expected_cash REAL DEFAULT 0,
        difference REAL DEFAULT 0,
        status TEXT DEFAULT 'open',
        notes TEXT,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
      )
    ''');

    await db.execute('''
      CREATE TABLE categories (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        allow_negative_stock INTEGER DEFAULT 0,
        is_active INTEGER DEFAULT 1,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
      )
    ''');

    await db.execute('''
      CREATE TABLE stock_groups (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
      )
    ''');

    await db.execute('''
      CREATE TABLE products (
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
        allow_negative_stock INTEGER NOT NULL DEFAULT 0,
        bonus_eligible INTEGER DEFAULT 1,
        is_active INTEGER DEFAULT 1,
        is_deleted INTEGER DEFAULT 0,
        hsn_code TEXT,
        local_name TEXT,
        purchase_unit TEXT,
        units_per_purchase_unit REAL DEFAULT 1,
        is_weighted INTEGER DEFAULT 0,
        max_stock_level REAL,
        parent_product_id TEXT REFERENCES products(id) ON DELETE SET NULL,
        is_kit INTEGER DEFAULT 0,
        is_service INTEGER DEFAULT 0,
        image_path TEXT,
        stock_group_id TEXT REFERENCES stock_groups(id) ON DELETE SET NULL,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
        updated_at INTEGER
      )
    ''');
    await db.execute('CREATE INDEX idx_products_barcode ON products(barcode)');
    await db.execute('CREATE INDEX idx_products_search_name ON products(search_name)');
    await db.execute('CREATE INDEX idx_products_stock_group ON products(stock_group_id)');

    await db.execute('''
      CREATE TABLE product_kit_components (
        id TEXT PRIMARY KEY,
        kit_product_id TEXT NOT NULL REFERENCES products(id) ON DELETE CASCADE,
        component_product_id TEXT NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
        quantity REAL NOT NULL DEFAULT 1
      )
    ''');
    await db.execute('CREATE INDEX idx_kit_components_kit ON product_kit_components(kit_product_id)');

    await db.execute('''
      CREATE TABLE customers (
        id TEXT PRIMARY KEY,
        store_id TEXT REFERENCES stores(id) ON DELETE CASCADE,
        phone TEXT UNIQUE NOT NULL,
        name TEXT NOT NULL,
        email TEXT,
        address TEXT,
        locality TEXT,
        loyalty_points INTEGER NOT NULL DEFAULT 0,
        total_spent REAL NOT NULL DEFAULT 0,
        credit_limit REAL NOT NULL DEFAULT 0,
        outstanding_balance REAL NOT NULL DEFAULT 0,
        rating TEXT DEFAULT 'regular',
        rating_manual_override TEXT,
        date_of_birth INTEGER,
        is_deleted INTEGER DEFAULT 0,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
        updated_at INTEGER
      )
    ''');
    await db.execute('CREATE INDEX idx_customers_phone ON customers(phone)');

    await db.execute('''
      CREATE TABLE suppliers (
        id TEXT PRIMARY KEY,
        store_id TEXT REFERENCES stores(id) ON DELETE CASCADE,
        name TEXT NOT NULL,
        phone TEXT,
        email TEXT,
        address TEXT,
        opening_balance REAL NOT NULL DEFAULT 0,
        is_deleted INTEGER DEFAULT 0,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
      )
    ''');

    await db.execute('''
      CREATE TABLE salesmen (
        id TEXT PRIMARY KEY,
        store_id TEXT REFERENCES stores(id) ON DELETE CASCADE,
        name TEXT NOT NULL,
        phone TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
      )
    ''');

    await db.execute('''
      CREATE TABLE sales (
        id TEXT PRIMARY KEY,
        store_id TEXT REFERENCES stores(id) ON DELETE CASCADE,
        customer_id TEXT REFERENCES customers(id) ON DELETE SET NULL,
        session_id TEXT REFERENCES sessions(id) ON DELETE SET NULL,
        user_id TEXT REFERENCES users(id) ON DELETE SET NULL,
        salesman_id TEXT REFERENCES salesmen(id) ON DELETE SET NULL,
        invoice_no INTEGER NOT NULL UNIQUE,
        invoice_display_no TEXT,
        subtotal REAL NOT NULL DEFAULT 0,
        tax_total REAL NOT NULL DEFAULT 0,
        discount_total REAL NOT NULL DEFAULT 0,
        discount_reason TEXT,
        round_off REAL DEFAULT 0,
        net_amount REAL NOT NULL DEFAULT 0,
        payment_methods TEXT,
        partial_payment_amount REAL DEFAULT 0,
        credit_used REAL DEFAULT 0,
        delivery_address TEXT,
        is_delivery INTEGER DEFAULT 0,
        delivery_charge REAL DEFAULT 0,
        is_credit_sale INTEGER DEFAULT 0,
        status TEXT DEFAULT 'completed',
        remarks TEXT,
        loyalty_points_redeemed INTEGER DEFAULT 0,
        loyalty_redemption_amount REAL DEFAULT 0,
        synced INTEGER DEFAULT 0,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
      )
    ''');
    await db.execute('CREATE INDEX idx_sales_invoice ON sales(invoice_no)');
    await db.execute('CREATE INDEX idx_sales_session ON sales(session_id)');

    await db.execute('''
      CREATE TABLE sale_items (
        id TEXT PRIMARY KEY,
        sale_id TEXT REFERENCES sales(id) ON DELETE CASCADE,
        product_id TEXT REFERENCES products(id) ON DELETE RESTRICT,
        quantity INTEGER NOT NULL DEFAULT 1,
        unit_price REAL NOT NULL DEFAULT 0,
        tax_amount REAL NOT NULL DEFAULT 0,
        discount_amount REAL NOT NULL DEFAULT 0,
        total_price REAL NOT NULL DEFAULT 0,
        line_discount_reason TEXT,
        cost_price REAL NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('CREATE INDEX idx_sale_items_sale ON sale_items(sale_id)');

    await db.execute('''
      CREATE TABLE payments (
        id TEXT PRIMARY KEY,
        sale_id TEXT REFERENCES sales(id) ON DELETE CASCADE,
        customer_id TEXT REFERENCES customers(id) ON DELETE SET NULL,
        amount REAL NOT NULL,
        method TEXT NOT NULL,
        reference_no TEXT,
        payment_date INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
      )
    ''');

    await db.execute('''
      CREATE TABLE holds (
        id TEXT PRIMARY KEY,
        user_id TEXT REFERENCES users(id) ON DELETE CASCADE,
        data TEXT NOT NULL,
        note TEXT,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
      )
    ''');

    await db.execute('''
      CREATE TABLE purchases (
        id TEXT PRIMARY KEY,
        store_id TEXT REFERENCES stores(id) ON DELETE CASCADE,
        supplier_id TEXT REFERENCES suppliers(id) ON DELETE SET NULL,
        grn_no TEXT NOT NULL,
        purchase_date INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
        location TEXT,
        supplier_name TEXT,
        supplier_merchant TEXT,
        supplier_address TEXT,
        total REAL NOT NULL DEFAULT 0,
        bill_total REAL NOT NULL DEFAULT 0,
        difference REAL NOT NULL DEFAULT 0,
        account_percent REAL DEFAULT 0,
        account REAL DEFAULT 0,
        tax_rate REAL DEFAULT 0,
        tax_percent REAL DEFAULT 0,
        tax REAL DEFAULT 0,
        chess TEXT,
        net_amount REAL NOT NULL DEFAULT 0,
        transport_status TEXT,
        transport TEXT,
        labour_status TEXT,
        labour_charges REAL DEFAULT 0,
        transport_charge REAL DEFAULT 0,
        total_qty INTEGER DEFAULT 0,
        remarks TEXT,
        received INTEGER DEFAULT 0,
        c_form TEXT,
        due_status TEXT,
        close_status TEXT,
        due_date INTEGER,
        status TEXT DEFAULT 'received',
        synced INTEGER DEFAULT 0,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
        updated_at INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE purchase_items (
        id TEXT PRIMARY KEY,
        purchase_id TEXT REFERENCES purchases(id) ON DELETE CASCADE,
        product_id TEXT REFERENCES products(id) ON DELETE RESTRICT,
        barcode TEXT,
        product_name TEXT,
        mrp REAL DEFAULT 0,
        quantity INTEGER DEFAULT 1,
        doz_amt REAL DEFAULT 0,
        purchase_price REAL DEFAULT 0,
        discount REAL DEFAULT 0,
        tax_percent REAL DEFAULT 0,
        net_rate REAL DEFAULT 0,
        cost_price REAL DEFAULT 0,
        profit REAL DEFAULT 0,
        margin REAL DEFAULT 0,
        last REAL DEFAULT 0,
        last_margin REAL DEFAULT 0,
        sales_price REAL DEFAULT 0,
        total REAL DEFAULT 0,
        is_repack INTEGER DEFAULT 0,
        bulk_quantity REAL DEFAULT 0,
        bulk_unit TEXT,
        pack_size REAL DEFAULT 0,
        pack_unit TEXT,
        pack_count INTEGER DEFAULT 0,
        batch_no TEXT,
        expiry_date INTEGER,
        free_quantity INTEGER DEFAULT 0,
        tax_amount REAL DEFAULT 0,
        discount_amount REAL DEFAULT 0,
        is_purchase_unit_entry INTEGER DEFAULT 0,
        purchase_unit_factor REAL DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE stock_ledger (
        id TEXT PRIMARY KEY,
        product_id TEXT REFERENCES products(id) ON DELETE CASCADE,
        store_id TEXT REFERENCES stores(id) ON DELETE CASCADE,
        reference_type TEXT NOT NULL,
        reference_id TEXT NOT NULL,
        quantity_change INTEGER NOT NULL,
        batch_no TEXT,
        expiry_date INTEGER,
        cost_price REAL NOT NULL,
        selling_price REAL NOT NULL,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
      )
    ''');
    await db.execute('CREATE INDEX idx_ledger_product ON stock_ledger(product_id)');
    await db.execute('CREATE INDEX idx_ledger_reference ON stock_ledger(reference_type, reference_id)');

    await db.execute('''
      CREATE TABLE product_batches (
        id TEXT PRIMARY KEY,
        product_id TEXT NOT NULL REFERENCES products(id) ON DELETE CASCADE,
        purchase_id TEXT REFERENCES purchases(id) ON DELETE SET NULL,
        batch_no TEXT,
        mrp REAL,
        cost_price REAL,
        selling_price REAL,
        expiry_date INTEGER,
        quantity_received REAL NOT NULL,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
      )
    ''');
    await db.execute('CREATE INDEX idx_product_batches_product ON product_batches(product_id)');

    await db.execute('''
      CREATE TABLE supplier_ledger (
        id TEXT PRIMARY KEY,
        supplier_id TEXT REFERENCES suppliers(id) ON DELETE CASCADE,
        reference_type TEXT NOT NULL,
        reference_id TEXT NOT NULL,
        amount REAL NOT NULL,
        balance REAL NOT NULL,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
      )
    ''');
    await db.execute('CREATE INDEX idx_supplier_ledger_supplier ON supplier_ledger(supplier_id)');

    await db.execute('''
      CREATE TABLE customer_ledger (
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
    await db.execute('CREATE INDEX idx_customer_ledger_customer ON customer_ledger(customer_id)');

    await db.execute('''
      CREATE TABLE sales_returns (
        id TEXT PRIMARY KEY,
        sale_id TEXT REFERENCES sales(id) ON DELETE SET NULL,
        customer_id TEXT REFERENCES customers(id) ON DELETE SET NULL,
        store_id TEXT REFERENCES stores(id),
        session_id TEXT,
        user_id TEXT NOT NULL,
        approved_by_user_id TEXT REFERENCES users(id) ON DELETE SET NULL,
        reason TEXT NOT NULL,
        refund_method TEXT NOT NULL,
        refund_amount REAL NOT NULL DEFAULT 0,
        is_untied INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
      )
    ''');
    await db.execute('CREATE INDEX idx_sales_returns_sale ON sales_returns(sale_id)');
    await db.execute('CREATE INDEX idx_sales_returns_customer ON sales_returns(customer_id)');

    await db.execute('''
      CREATE TABLE sales_return_items (
        id TEXT PRIMARY KEY,
        return_id TEXT NOT NULL REFERENCES sales_returns(id) ON DELETE CASCADE,
        sale_item_id TEXT REFERENCES sale_items(id),
        product_id TEXT NOT NULL REFERENCES products(id),
        quantity REAL NOT NULL,
        unit_price REAL NOT NULL DEFAULT 0,
        tax_amount REAL NOT NULL DEFAULT 0,
        total_price REAL NOT NULL DEFAULT 0,
        cost_price REAL NOT NULL DEFAULT 0,
        restocked INTEGER NOT NULL DEFAULT 1
      )
    ''');
    await db.execute('CREATE INDEX idx_sales_return_items_return ON sales_return_items(return_id)');
    await db.execute('CREATE INDEX idx_sales_return_items_product ON sales_return_items(product_id)');

    await db.execute('''
      CREATE TABLE sale_cancellations (
        id TEXT PRIMARY KEY,
        sale_id TEXT UNIQUE NOT NULL REFERENCES sales(id),
        customer_id TEXT REFERENCES customers(id) ON DELETE SET NULL,
        reason TEXT NOT NULL,
        refund_method TEXT NOT NULL,
        refund_amount REAL NOT NULL DEFAULT 0,
        user_id TEXT NOT NULL,
        approved_by_user_id TEXT REFERENCES users(id) ON DELETE SET NULL,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
      )
    ''');
    await db.execute('CREATE INDEX idx_sale_cancellations_sale ON sale_cancellations(sale_id)');
    await db.execute('CREATE INDEX idx_sale_cancellations_customer ON sale_cancellations(customer_id)');

    await db.execute('''
      CREATE TABLE exchanges (
        id TEXT PRIMARY KEY,
        return_id TEXT NOT NULL REFERENCES sales_returns(id),
        new_sale_id TEXT REFERENCES sales(id) ON DELETE SET NULL,
        customer_id TEXT REFERENCES customers(id) ON DELETE SET NULL,
        price_difference REAL NOT NULL DEFAULT 0,
        settlement_method TEXT NOT NULL,
        user_id TEXT NOT NULL,
        approved_by_user_id TEXT REFERENCES users(id) ON DELETE SET NULL,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
      )
    ''');
    await db.execute('CREATE INDEX idx_exchanges_return ON exchanges(return_id)');
    await db.execute('CREATE INDEX idx_exchanges_new_sale ON exchanges(new_sale_id)');
    await db.execute('CREATE INDEX idx_exchanges_customer ON exchanges(customer_id)');

    await db.execute('''
      CREATE TABLE promotions (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        product_id TEXT REFERENCES products(id) ON DELETE CASCADE,
        category_id TEXT REFERENCES categories(id) ON DELETE CASCADE,
        min_quantity INTEGER NOT NULL DEFAULT 1,
        discount_value REAL,
        free_product_id TEXT REFERENCES products(id) ON DELETE CASCADE,
        start_date INTEGER,
        end_date INTEGER,
        is_active INTEGER DEFAULT 1,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
      )
    ''');

    await db.execute('''
      CREATE TABLE coupons (
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
    await db.execute('CREATE INDEX idx_coupons_code ON coupons(code)');

    await db.execute('''
      CREATE TABLE bonus_points (
        id TEXT PRIMARY KEY,
        customer_id TEXT REFERENCES customers(id) ON DELETE CASCADE,
        sale_id TEXT REFERENCES sales(id) ON DELETE CASCADE,
        points_earned INTEGER DEFAULT 0,
        points_redeemed INTEGER DEFAULT 0,
        date INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
      )
    ''');

    await db.execute('''
      CREATE TABLE audit_log (
        id TEXT PRIMARY KEY,
        user_id TEXT REFERENCES users(id) ON DELETE SET NULL,
        action_type TEXT NOT NULL,
        table_name TEXT NOT NULL,
        record_id TEXT NOT NULL,
        old_value TEXT,
        new_value TEXT,
        timestamp INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
      )
    ''');

    await db.execute('''
      CREATE TABLE sync_queue (
        id TEXT PRIMARY KEY,
        table_name TEXT NOT NULL,
        record_id TEXT NOT NULL,
        operation TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        retry_count INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
      )
    ''');
    await db.execute('CREATE INDEX idx_sync_pending ON sync_queue(retry_count, created_at)');

    await db.execute('''
      CREATE TABLE sync_state (
        table_name TEXT PRIMARY KEY,
        last_pulled_at INTEGER NOT NULL DEFAULT 0
      )
    ''');

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

    await db.execute('''
      CREATE TABLE quotation_items (
        id TEXT PRIMARY KEY,
        quotation_id TEXT NOT NULL REFERENCES quotations(id) ON DELETE CASCADE,
        product_id TEXT NOT NULL REFERENCES products(id),
        quantity REAL NOT NULL DEFAULT 1,
        unit_price REAL NOT NULL DEFAULT 0,
        total_price REAL NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('CREATE INDEX idx_quotation_items_quotation ON quotation_items(quotation_id)');

    await db.execute('''
      CREATE TABLE financial_year_closures (
        id TEXT PRIMARY KEY,
        financial_year TEXT NOT NULL UNIQUE,
        closed_at INTEGER NOT NULL,
        closed_by_user_id TEXT REFERENCES users(id) ON DELETE SET NULL,
        notes TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE price_history (
        id TEXT PRIMARY KEY,
        product_id TEXT NOT NULL REFERENCES products(id) ON DELETE CASCADE,
        field TEXT NOT NULL,
        old_value REAL,
        new_value REAL NOT NULL,
        changed_by_user_id TEXT REFERENCES users(id) ON DELETE SET NULL,
        changed_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))
      )
    ''');
    await db.execute('CREATE INDEX idx_price_history_product ON price_history(product_id)');

    // Default store
    await db.insert('stores', {
      'id': 'store_default',
      'name': 'Main Store',
      'timezone': 'Asia/Kolkata',
    });

    // Admin user — default password is still "admin", but it's stored
    // hashed and must_change_password forces a change on first login.
    await db.insert('users', {
      'id': 'user_admin',
      'username': 'admin',
      'password_hash': PasswordHasher.hash('admin'),
      'role': 'admin',
      'name': 'Super Admin',
      'must_change_password': 1,
      'is_active': 1,
    });

    // Default categories
    final categories = [
      {'id': 'cat_dairy', 'name': 'Dairy', 'allow_negative_stock': 1},
      {'id': 'cat_bakery', 'name': 'Bakery', 'allow_negative_stock': 0},
      {'id': 'cat_beverages', 'name': 'Beverages', 'allow_negative_stock': 0},
      {'id': 'cat_snacks', 'name': 'Snacks', 'allow_negative_stock': 0},
      {'id': 'cat_household', 'name': 'Household', 'allow_negative_stock': 0},
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
    for (final cat in categories) {
      await db.insert('categories', cat);
    }

    // Seeded Tamil Nadu festival calendar for the festival-stock-suggestion
    // report — editable afterward from Settings → Utilities → Festival
    // Calendar. Fixed-date (solar) festivals are accurate every year;
    // lunar-calendar ones shift, so their seeded day is only a rough
    // placeholder flagged in `notes` for a manager to correct each year.
    final festivals = [
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
    for (final festival in festivals) {
      await db.insert('festival_calendar', festival);
    }

    // General Ledger tables + default chart of accounts. Delegated rather
    // than inlined (unlike the older tables above, which this file duplicates
    // from their original migrations): the GL schema has to be provably
    // identical on a fresh install and on an upgrade from v27, and a single
    // shared implementation is the only way that stays true as the GL evolves.
    await MigrationV28.up(db);

    // Bank reconciliation tables — delegated for the same reason as the GL
    // schema above: one implementation, so a fresh install and an upgrade can
    // never disagree.
    await MigrationV29.up(db);

    // Loyalty event-log columns on `bonus_points` (created above) plus the
    // store expiry setting. Delegated for the same reason; every statement in
    // there is an idempotent ADD COLUMN / CREATE INDEX IF NOT EXISTS, so
    // running it right after the CREATE is safe.
    await MigrationV30.up(db);

    // Payment gateway tables + the store credential columns. Delegated for
    // the same reason as the three above: one definition of the schema, used
    // by both the fresh-create and the upgrade path.
    await MigrationV31.up(db);

    // Collection activity + commission rule/settlement tables. Delegated for
    // the same reason as the four above. Note this one references `salesmen`
    // and `customers`, both created earlier in this method.
    await MigrationV32.up(db);
  }
}