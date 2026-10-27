import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/product.dart';
import '../models/product_variant.dart';
import '../models/cart_item.dart';
import '../models/sale.dart';
import '../models/customer.dart';
import '../models/baki_payment.dart';
import '../models/dashboard_data.dart';
import '../models/sales_report.dart';
import '../models/sale_payment.dart';
import '../models/sale_return.dart';
import '../models/supplier.dart';
import '../models/purchase.dart';
import '../core/quantity_format.dart';
import '../models/daily_cash_close.dart';
import '../models/staff_user.dart';
import '../models/sync_outbox_event.dart';
import '../models/remote_sync_event.dart';
import '../models/cloud_catalog.dart';
import '../services/product_image_storage.dart';

class DatabaseHelper {
  static const cloudSettingsSyncId = '00000000-0000-4000-8000-000000000001';
  static const backupTableNames = [
    'products',
    'product_variants',
    'customers',
    'suppliers',
    'sales',
    'sale_items',
    'sale_returns',
    'sale_return_items',
    'sale_payments',
    'purchases',
    'purchase_items',
    'baki_payments',
    'stock_movements',
    'app_settings',
    'daily_closes',
    'staff_users',
    'sync_outbox',
  ];
  static const _backupDeleteOrder = [
    'sale_return_items',
    'sale_returns',
    'sale_payments',
    'sale_items',
    'purchase_items',
    'purchases',
    'suppliers',
    'baki_payments',
    'stock_movements',
    'sales',
    'product_variants',
    'products',
    'customers',
    'daily_closes',
    'staff_users',
    'sync_outbox',
    'app_settings',
  ];
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _db;
  static String? _testPath;
  final ProductImageStorage _productImageStorage = ProductImageStorage();

  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  @visibleForTesting
  static void setTestPath(String path) => _testPath = path;

  @visibleForTesting
  static Future<void> resetForTesting() async {
    await _db?.close();
    _db = null;
  }

  Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    final String path;
    if (_testPath != null) {
      path = _testPath!;
    } else {
      final dir = await getApplicationDocumentsDirectory();
      path = join(dir.path, 'mpos.db');
    }
    return openDatabase(
      path,
      version: 25,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async => _createTables(db);

  Future<void> _addColumnIfMissing(
    DatabaseExecutor db, {
    required String table,
    required String column,
    required String definition,
  }) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    if (columns.any((entry) => entry['name'] == column)) return;
    await db.execute('ALTER TABLE $table ADD COLUMN $definition');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // ponytail: additive-only; never DROP. try/catch because SQLite ALTER TABLE
    // has no IF NOT EXISTS for columns.
    if (oldVersion < 2) {
      try {
        await db.execute(
          "ALTER TABLE sales ADD COLUMN payment_type TEXT NOT NULL DEFAULT 'cash'",
        );
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE sales ADD COLUMN customer_id INTEGER');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE sales ADD COLUMN customer_name TEXT');
      } catch (_) {}
      await db.execute('''
        CREATE TABLE IF NOT EXISTS customers (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          phone TEXT DEFAULT '',
          created_at TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS baki_payments (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          customer_id INTEGER NOT NULL,
          amount REAL NOT NULL,
          note TEXT DEFAULT '',
          paid_at TEXT NOT NULL,
          FOREIGN KEY (customer_id) REFERENCES customers(id)
        )
      ''');
    }
    // v2 → v3: no schema changes
    if (oldVersion < 4) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS stock_movements (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          variant_id INTEGER NOT NULL,
          quantity REAL NOT NULL,
          cost_price REAL DEFAULT 0,
          supplier TEXT DEFAULT '',
          created_at TEXT NOT NULL,
          FOREIGN KEY (variant_id) REFERENCES product_variants(id)
        )
      ''');
    }
    if (oldVersion < 5) {
      try {
        await db.execute(
          'ALTER TABLE sales ADD COLUMN discount_amount REAL DEFAULT 0',
        );
      } catch (_) {}
      try {
        await db.execute(
          "ALTER TABLE sales ADD COLUMN discount_type TEXT DEFAULT 'flat'",
        );
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE sale_items ADD COLUMN discount_amount REAL DEFAULT 0',
        );
      } catch (_) {}
    }
    if (oldVersion < 6) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS app_settings (
          setting_key TEXT PRIMARY KEY,
          setting_value TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 7) {
      await db.execute(
        'ALTER TABLE sales ADD COLUMN tax_amount REAL NOT NULL DEFAULT 0',
      );
    }
    if (oldVersion < 8) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS sale_payments (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          sale_id INTEGER NOT NULL,
          method TEXT NOT NULL,
          amount REAL NOT NULL,
          note TEXT DEFAULT '',
          FOREIGN KEY (sale_id) REFERENCES sales(id) ON DELETE CASCADE
        )
      ''');
    }
    if (oldVersion < 9) await _createReturnTables(db);
    if (oldVersion < 10) await _createPurchaseTables(db);
    if (oldVersion < 11) {
      await db.execute(
        'ALTER TABLE products ADD COLUMN quantity_precision INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (oldVersion < 12) await _createDailyCloseTable(db);
    if (oldVersion < 13) {
      await db.execute(
        'ALTER TABLE sale_items ADD COLUMN cost_price_snapshot REAL',
      );
    }
    if (oldVersion < 14) {
      await _addColumnIfMissing(
        db,
        table: 'sales',
        column: 'staff_id',
        definition: 'staff_id INTEGER',
      );
      await _addColumnIfMissing(
        db,
        table: 'daily_closes',
        column: 'staff_id',
        definition: 'staff_id INTEGER',
      );
      await _createStaffUserTable(db);
    }
    if (oldVersion < 15) await _createSyncOutbox(db);
    if (oldVersion < 16) await _createSyncInbox(db);
    if (oldVersion < 17) await _createSyncIdentity(db);
    if (oldVersion < 18) await _createCloudCatalogSyncTables(db);
    if (oldVersion < 19) await _createCloudCatalogInbox(db);
    if (oldVersion < 20) {
      try {
        await db.execute(
          'ALTER TABLE cloud_catalog_inbox ADD COLUMN conflict_reason TEXT',
        );
      } catch (_) {}
    }
    if (oldVersion < 21) {
      for (final statement in [
        'ALTER TABLE sales ADD COLUMN origin_shop_id TEXT',
        'ALTER TABLE sales ADD COLUMN origin_event_id TEXT',
        'ALTER TABLE sale_returns ADD COLUMN origin_shop_id TEXT',
        'ALTER TABLE sale_returns ADD COLUMN origin_event_id TEXT',
        'ALTER TABLE baki_payments ADD COLUMN origin_shop_id TEXT',
        'ALTER TABLE baki_payments ADD COLUMN origin_event_id TEXT',
        'ALTER TABLE sync_inbox ADD COLUMN apply_error TEXT',
      ]) {
        try {
          await db.execute(statement);
        } catch (_) {}
      }
      await _createRemoteOriginIndexes(db);
    }
    if (oldVersion < 22) {
      await _createSupplierSyncIdentity(db);
    }
    if (oldVersion < 23) {
      for (final statement in [
        'ALTER TABLE purchases ADD COLUMN origin_shop_id TEXT',
        'ALTER TABLE purchases ADD COLUMN origin_event_id TEXT',
      ]) {
        try {
          await db.execute(statement);
        } catch (_) {}
      }
      await _createRemoteOriginIndexes(db);
    }
    if (oldVersion < 24) {
      try {
        await db.execute('ALTER TABLE staff_users ADD COLUMN sync_id TEXT');
      } catch (_) {}
      await _createStaffSyncIdentity(db);
    }
    if (oldVersion < 25) {
      await _addColumnIfMissing(
        db,
        table: 'staff_users',
        column: 'pin_length',
        definition: 'pin_length INTEGER NOT NULL DEFAULT 0',
      );
    }
  }

  Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        description TEXT DEFAULT '',
        category TEXT DEFAULT '',
        brand TEXT DEFAULT '',
        sku TEXT DEFAULT '',
        unit TEXT DEFAULT 'pcs',
        image_path TEXT DEFAULT '',
        cost_price REAL DEFAULT 0,
        low_stock_alert INTEGER DEFAULT 5,
        quantity_precision INTEGER NOT NULL DEFAULT 0,
        sync_id TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE product_variants (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL,
        name TEXT NOT NULL DEFAULT 'Default',
        barcode TEXT DEFAULT '',
        price REAL NOT NULL,
        stock REAL NOT NULL DEFAULT 0,
        sync_id TEXT,
        FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE customers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT DEFAULT '',
        sync_id TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE sales (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        total_amount REAL NOT NULL,
        created_at TEXT NOT NULL,
        payment_type TEXT NOT NULL DEFAULT 'cash',
        customer_id INTEGER,
        customer_name TEXT,
        discount_amount REAL DEFAULT 0,
        discount_type TEXT DEFAULT 'flat',
        tax_amount REAL NOT NULL DEFAULT 0,
        staff_id INTEGER,
        origin_shop_id TEXT,
        origin_event_id TEXT,
        FOREIGN KEY (customer_id) REFERENCES customers(id)
      )
    ''');
    await db.execute('''
      CREATE TABLE sale_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sale_id INTEGER NOT NULL,
        product_id INTEGER NOT NULL,
        variant_id INTEGER NOT NULL,
        product_name TEXT NOT NULL,
        variant_name TEXT NOT NULL DEFAULT '',
        product_price REAL NOT NULL,
        quantity REAL NOT NULL,
        cost_price_snapshot REAL,
        discount_amount REAL DEFAULT 0,
        FOREIGN KEY (sale_id) REFERENCES sales(id)
      )
    ''');
    await db.execute('''
      CREATE TABLE baki_payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_id INTEGER NOT NULL,
        amount REAL NOT NULL,
        note TEXT DEFAULT '',
        paid_at TEXT NOT NULL,
        origin_shop_id TEXT,
        origin_event_id TEXT,
        FOREIGN KEY (customer_id) REFERENCES customers(id)
      )
    ''');
    await db.execute('''
      CREATE TABLE stock_movements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        variant_id INTEGER NOT NULL,
        quantity REAL NOT NULL,
        cost_price REAL DEFAULT 0,
        supplier TEXT DEFAULT '',
        created_at TEXT NOT NULL,
        FOREIGN KEY (variant_id) REFERENCES product_variants(id)
      )
    ''');
    await db.execute('''
      CREATE TABLE app_settings (
        setting_key TEXT PRIMARY KEY,
        setting_value TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE sale_payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sale_id INTEGER NOT NULL,
        method TEXT NOT NULL,
        amount REAL NOT NULL,
        note TEXT DEFAULT '',
        FOREIGN KEY (sale_id) REFERENCES sales(id) ON DELETE CASCADE
      )
    ''');
    await _createReturnTables(db);
    await _createPurchaseTables(db);
    await _createDailyCloseTable(db);
    await _createStaffUserTable(db);
    await _createStaffSyncIdentity(db);
    await _createSyncOutbox(db);
    await _createSyncInbox(db);
    await _createRemoteOriginIndexes(db);
    await _createSyncIdentity(db);
    await _createSupplierSyncIdentity(db);
    await _createCloudCatalogSyncTables(db);
    await _createCloudCatalogInbox(db);
  }

  Future<void> _createCloudCatalogSyncTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cloud_catalog_state (
        remote_shop_id TEXT NOT NULL,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        revision INTEGER NOT NULL,
        payload_json TEXT NOT NULL,
        deleted INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (remote_shop_id, entity_type, entity_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cloud_catalog_outbox (
        remote_shop_id TEXT NOT NULL,
        mutation_id TEXT NOT NULL UNIQUE,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        base_revision INTEGER NOT NULL,
        payload_json TEXT NOT NULL,
        deleted INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        UNIQUE (remote_shop_id, entity_type, entity_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cloud_catalog_deletions (
        remote_shop_id TEXT NOT NULL,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        PRIMARY KEY (remote_shop_id, entity_type, entity_id)
      )
    ''');
  }

  Future<void> _createCloudCatalogInbox(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cloud_catalog_cursor (
        remote_shop_id TEXT PRIMARY KEY,
        cursor INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cloud_catalog_inbox (
        remote_shop_id TEXT NOT NULL,
        cursor INTEGER NOT NULL,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        mutation_id TEXT NOT NULL,
        base_revision INTEGER NOT NULL,
        revision INTEGER NOT NULL,
        payload_json TEXT NOT NULL,
        deleted INTEGER NOT NULL,
        changed_at TEXT NOT NULL,
        received_at TEXT NOT NULL,
        applied_at TEXT,
        conflict_reason TEXT,
        PRIMARY KEY (remote_shop_id, cursor)
      )
    ''');
  }

  Future<void> _createSyncOutbox(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_outbox (
        sequence INTEGER PRIMARY KEY AUTOINCREMENT,
        idempotency_key TEXT NOT NULL UNIQUE,
        event_type TEXT NOT NULL,
        entity_id INTEGER NOT NULL,
        payload_json TEXT NOT NULL,
        created_at TEXT NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0,
        last_error TEXT NOT NULL DEFAULT '',
        synced_at TEXT
      )
    ''');
  }

  Future<void> _createSyncInbox(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_inbox (
        remote_shop_id TEXT NOT NULL,
        cursor INTEGER NOT NULL,
        event_id TEXT NOT NULL,
        event_type TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        received_at TEXT NOT NULL,
        applied_at TEXT,
        apply_error TEXT,
        PRIMARY KEY (remote_shop_id, cursor),
        UNIQUE (remote_shop_id, event_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_state (
        remote_shop_id TEXT PRIMARY KEY,
        pull_cursor INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  Future<void> _createRemoteOriginIndexes(DatabaseExecutor db) async {
    for (final table in [
      'sales',
      'sale_returns',
      'baki_payments',
      'purchases',
    ]) {
      final tableRows = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
        [table],
      );
      if (tableRows.isEmpty) continue;
      final columns = await db.rawQuery('PRAGMA table_info($table)');
      final names = columns.map((row) => row['name']).toSet();
      if (!names.contains('origin_shop_id') ||
          !names.contains('origin_event_id')) {
        continue;
      }
      await db.execute('''
        CREATE UNIQUE INDEX IF NOT EXISTS ${table}_remote_origin_idx
        ON $table(origin_shop_id, origin_event_id)
        WHERE origin_shop_id IS NOT NULL AND origin_event_id IS NOT NULL
      ''');
    }
  }

  Future<void> _createSyncIdentity(DatabaseExecutor db) async {
    for (final table in ['products', 'product_variants', 'customers']) {
      try {
        await db.execute('ALTER TABLE $table ADD COLUMN sync_id TEXT');
      } catch (_) {
        // Fresh databases already create these columns.
      }
    }
    await _backfillSyncIds(db);
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS products_sync_id_idx ON products(sync_id)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS product_variants_sync_id_idx ON product_variants(sync_id)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS customers_sync_id_idx ON customers(sync_id)',
    );
  }

  Future<void> _createSupplierSyncIdentity(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS suppliers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT NOT NULL DEFAULT '',
        address TEXT NOT NULL DEFAULT '',
        notes TEXT NOT NULL DEFAULT ''
      )
    ''');
    try {
      await db.execute('ALTER TABLE suppliers ADD COLUMN sync_id TEXT');
    } catch (_) {}
    await _backfillSupplierSyncIds(db);
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS suppliers_sync_id_idx ON suppliers(sync_id)',
    );
  }

  Future<void> _backfillSyncIds(DatabaseExecutor db) async {
    for (final table in ['products', 'product_variants', 'customers']) {
      final rows = await db.query(
        table,
        columns: ['id', 'sync_id'],
        where: "sync_id IS NULL OR sync_id = ''",
      );
      for (final row in rows) {
        await db.update(
          table,
          {'sync_id': _newUuid()},
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }
    }
  }

  Future<void> _backfillSupplierSyncIds(DatabaseExecutor db) async {
    final rows = await db.query(
      'suppliers',
      columns: ['id', 'sync_id'],
      where: "sync_id IS NULL OR sync_id = ''",
    );
    for (final row in rows) {
      await db.update(
        'suppliers',
        {'sync_id': _newUuid()},
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }
  }

  Future<void> _createStaffUserTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS staff_users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sync_id TEXT,
        name TEXT NOT NULL,
        role TEXT NOT NULL CHECK(role IN ('owner', 'cashier')),
        pin_salt TEXT NOT NULL,
        pin_hash TEXT NOT NULL,
        pin_length INTEGER NOT NULL DEFAULT 0,
        active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _createStaffSyncIdentity(DatabaseExecutor db) async {
    final table = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'staff_users'",
    );
    if (table.isEmpty) return;
    final columns = await db.rawQuery('PRAGMA table_info(staff_users)');
    if (columns.every((column) => column['name'] != 'sync_id')) {
      await db.execute('ALTER TABLE staff_users ADD COLUMN sync_id TEXT');
    }
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS staff_users_sync_id_idx ON staff_users(sync_id)',
    );
    final rows = await db.query(
      'staff_users',
      columns: ['id', 'sync_id'],
      where: "sync_id IS NULL OR sync_id = ''",
    );
    for (final row in rows) {
      await db.update(
        'staff_users',
        {'sync_id': _newUuid()},
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }
  }

  Future<void> _createDailyCloseTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS daily_closes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        business_date TEXT NOT NULL,
        expected_cash REAL NOT NULL,
        counted_cash REAL NOT NULL,
        cash_receipts REAL NOT NULL,
        baki_issued REAL NOT NULL,
        baki_collected REAL NOT NULL,
        refunds_total REAL NOT NULL,
        payment_totals_json TEXT NOT NULL,
        note TEXT NOT NULL DEFAULT '',
        closed_at TEXT NOT NULL,
        staff_id INTEGER
      )
    ''');
  }

  Future<void> _createPurchaseTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS suppliers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sync_id TEXT,
        name TEXT NOT NULL,
        phone TEXT NOT NULL DEFAULT '',
        address TEXT NOT NULL DEFAULT '',
        notes TEXT NOT NULL DEFAULT ''
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS purchases (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        supplier_id INTEGER,
        supplier_name TEXT NOT NULL,
        total_amount REAL NOT NULL,
        note TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        origin_shop_id TEXT,
        origin_event_id TEXT,
        FOREIGN KEY (supplier_id) REFERENCES suppliers(id)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS purchase_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        purchase_id INTEGER NOT NULL,
        variant_id INTEGER NOT NULL,
        product_name TEXT NOT NULL,
        variant_name TEXT NOT NULL DEFAULT '',
        quantity REAL NOT NULL,
        cost_price REAL NOT NULL,
        FOREIGN KEY (purchase_id) REFERENCES purchases(id),
        FOREIGN KEY (variant_id) REFERENCES product_variants(id)
      )
    ''');
  }

  Future<void> _createReturnTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sale_returns (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sale_id INTEGER NOT NULL,
        amount REAL NOT NULL,
        reason TEXT NOT NULL,
        refund_method TEXT NOT NULL,
        created_at TEXT NOT NULL,
        origin_shop_id TEXT,
        origin_event_id TEXT,
        FOREIGN KEY (sale_id) REFERENCES sales(id)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sale_return_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        return_id INTEGER NOT NULL,
        sale_item_id INTEGER NOT NULL,
        product_name TEXT NOT NULL,
        variant_name TEXT NOT NULL DEFAULT '',
        quantity REAL NOT NULL,
        amount REAL NOT NULL,
        FOREIGN KEY (return_id) REFERENCES sale_returns(id),
        FOREIGN KEY (sale_item_id) REFERENCES sale_items(id)
      )
    ''');
  }

  Future<Map<String, String>> getAppSettings() async {
    final db = await database;
    final rows = await db.query('app_settings');
    return {
      for (final row in rows)
        row['setting_key'] as String: row['setting_value'] as String,
    };
  }

  Future<void> saveAppSettings(Map<String, String> values) async {
    final db = await database;
    await db.transaction((txn) async {
      for (final entry in values.entries) {
        await txn.insert('app_settings', {
          'setting_key': entry.key,
          'setting_value': entry.value,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<List<StaffUser>> getStaffUsers({bool activeOnly = false}) async {
    final db = await database;
    final rows = await db.query(
      'staff_users',
      where: activeOnly ? 'active = 1' : null,
      orderBy: 'role DESC, name COLLATE NOCASE',
    );
    return rows.map(StaffUser.fromMap).toList();
  }

  Future<int> insertStaffUser({
    required String name,
    required String role,
    required String pinSalt,
    required String pinHash,
    required int pinLength,
  }) async {
    if (!{'owner', 'cashier'}.contains(role) || name.trim().isEmpty) {
      throw ArgumentError('A staff name and valid role are required.');
    }
    final db = await database;
    return db.insert('staff_users', {
      'sync_id': _newUuid(),
      'name': name.trim(),
      'role': role,
      'pin_salt': pinSalt,
      'pin_hash': pinHash,
      'pin_length': pinLength,
      'active': 1,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> setStaffUserActive(int id, bool active) async {
    final db = await database;
    if (!active) {
      final rows = await db.query(
        'staff_users',
        columns: ['role', 'active'],
        where: 'id = ?',
        whereArgs: [id],
      );
      if (rows.isEmpty) return;
      if (rows.first['role'] == 'owner' && rows.first['active'] == 1) {
        final owners = await db.query(
          'staff_users',
          columns: ['id'],
          where: "role = 'owner' AND active = 1",
        );
        if (owners.length <= 1) {
          throw StateError('At least one active owner must remain.');
        }
      }
    }
    await db.update(
      'staff_users',
      {'active': active ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateStaffPin(
    int id,
    String pinSalt,
    String pinHash,
    int pinLength,
  ) async {
    final db = await database;
    final updated = await db.update(
      'staff_users',
      {'pin_salt': pinSalt, 'pin_hash': pinHash, 'pin_length': pinLength},
      where: 'id = ?',
      whereArgs: [id],
    );
    if (updated == 0) throw StateError('Staff account no longer exists.');
  }

  Future<void> updateStaffPinLength(int id, int pinLength) async {
    final db = await database;
    await db.update(
      'staff_users',
      {'pin_length': pinLength},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<Map<String, List<Map<String, Object?>>>> exportBackupTables() async {
    final db = await database;
    return db.transaction((txn) async {
      final tables = <String, List<Map<String, Object?>>>{};
      for (final table in backupTableNames) {
        final rows = await txn.query(table, orderBy: 'rowid ASC');
        tables[table] = rows
            .map((row) => Map<String, Object?>.from(row))
            .toList();
      }
      return tables;
    });
  }

  Future<void> restoreBackupTables(
    Map<String, List<Map<String, Object?>>> tables,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      // Sync cursors belong to this device/account, not to a business backup.
      await txn.delete('sync_inbox');
      await txn.delete('sync_state');
      await txn.delete('cloud_catalog_inbox');
      await txn.delete('cloud_catalog_cursor');
      for (final table in _backupDeleteOrder) {
        await txn.delete(table);
      }
      for (final table in backupTableNames) {
        for (final row in tables[table]!) {
          await txn.insert(table, row);
        }
      }
      await _backfillSyncIds(txn);
      await _backfillSupplierSyncIds(txn);
      await _createStaffSyncIdentity(txn);
    });
  }

  Future<List<SyncOutboxEvent>> getPendingSyncEvents({int limit = 100}) async {
    if (limit < 1 || limit > 1000) {
      throw ArgumentError.value(limit, 'limit', 'Must be between 1 and 1000.');
    }
    final db = await database;
    final rows = await db.query(
      'sync_outbox',
      where: 'synced_at IS NULL',
      orderBy: 'sequence ASC',
      limit: limit,
    );
    return rows.map(SyncOutboxEvent.fromMap).toList();
  }

  Future<int> getPendingSyncEventCount() async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM sync_outbox WHERE synced_at IS NULL',
    );
    return (rows.first['count'] as int?) ?? 0;
  }

  Future<void> markSyncEventSent(String idempotencyKey) async {
    final db = await database;
    await db.update(
      'sync_outbox',
      {'synced_at': DateTime.now().toUtc().toIso8601String(), 'last_error': ''},
      where: 'idempotency_key = ? AND synced_at IS NULL',
      whereArgs: [idempotencyKey],
    );
  }

  Future<void> markSyncEventFailed(String idempotencyKey, String error) async {
    final db = await database;
    final trimmedError = error.trim();
    final boundedError = trimmedError.length > 500
        ? trimmedError.substring(0, 500)
        : trimmedError;
    await db.rawUpdate(
      '''
      UPDATE sync_outbox
      SET attempts = attempts + 1, last_error = ?
      WHERE idempotency_key = ? AND synced_at IS NULL
      ''',
      [boundedError, idempotencyKey],
    );
  }

  Future<int> getRemoteSyncCursor(String remoteShopId) async {
    final db = await database;
    final rows = await db.query(
      'sync_state',
      columns: ['pull_cursor'],
      where: 'remote_shop_id = ?',
      whereArgs: [remoteShopId],
      limit: 1,
    );
    return rows.isEmpty ? 0 : rows.single['pull_cursor'] as int;
  }

  Future<int> getUnappliedRemoteEventCount(String remoteShopId) async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM sync_inbox WHERE remote_shop_id = ? AND applied_at IS NULL',
      [remoteShopId],
    );
    return rows.isEmpty ? 0 : rows.single['count'] as int;
  }

  Future<int> saveRemoteSyncEvents({
    required String remoteShopId,
    required int nextCursor,
    required List<RemoteSyncEvent> events,
  }) async {
    if (remoteShopId.trim().isEmpty ||
        nextCursor < 0 ||
        events.any((event) => event.cursor > nextCursor)) {
      throw ArgumentError('Invalid remote sync page.');
    }
    final db = await database;
    return db.transaction((txn) async {
      final currentRows = await txn.query(
        'sync_state',
        columns: ['pull_cursor'],
        where: 'remote_shop_id = ?',
        whereArgs: [remoteShopId],
        limit: 1,
      );
      final currentCursor = currentRows.isEmpty
          ? 0
          : currentRows.single['pull_cursor'] as int;
      if (nextCursor < currentCursor) {
        throw StateError('Remote sync cursor moved backwards.');
      }
      var inserted = 0;
      final now = DateTime.now().toUtc().toIso8601String();
      for (final event in events) {
        if (event.cursor <= currentCursor) continue;
        inserted += await txn.insert('sync_inbox', {
          'remote_shop_id': remoteShopId,
          'cursor': event.cursor,
          'event_id': event.eventId,
          'event_type': event.eventType,
          'payload_json': event.toJsonString(),
          'received_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      await txn.insert('sync_state', {
        'remote_shop_id': remoteShopId,
        'pull_cursor': nextCursor,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return inserted;
    });
  }

  Future<List<Map<String, Object?>>> getUnappliedRemoteEvents(
    String remoteShopId, {
    int limit = 500,
  }) async {
    final db = await database;
    return db.query(
      'sync_inbox',
      where: 'remote_shop_id = ? AND applied_at IS NULL',
      whereArgs: [remoteShopId],
      orderBy: 'cursor ASC',
      limit: limit,
    );
  }

  Future<int> getRemoteSyncApplyErrorCount(String remoteShopId) async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM sync_inbox WHERE remote_shop_id = ? AND applied_at IS NULL AND apply_error IS NOT NULL',
      [remoteShopId],
    );
    return rows.first['count'] as int;
  }

  Future<RemoteSyncApplyResult> applyPendingRemoteSyncEvents(
    String remoteShopId, {
    int limit = 500,
  }) async {
    if (remoteShopId.trim().isEmpty) {
      throw ArgumentError.value(remoteShopId, 'remoteShopId');
    }
    final db = await database;
    final pendingRows = await getUnappliedRemoteEvents(
      remoteShopId,
      limit: limit,
    );
    var applied = 0;
    for (final row in pendingRows) {
      final cursor = row['cursor'] as int;
      try {
        final event = RemoteSyncEvent.fromJson(
          jsonDecode(row['payload_json'] as String) as Map<String, dynamic>,
        );
        await db.transaction((txn) async {
          final inboxRows = await txn.query(
            'sync_inbox',
            where: 'remote_shop_id = ? AND cursor = ? AND applied_at IS NULL',
            whereArgs: [remoteShopId, cursor],
            limit: 1,
          );
          if (inboxRows.isEmpty) return;
          await _applyRemoteEvent(txn, remoteShopId, event);
          await txn.update(
            'sync_inbox',
            {
              'applied_at': DateTime.now().toUtc().toIso8601String(),
              'apply_error': null,
            },
            where: 'remote_shop_id = ? AND cursor = ?',
            whereArgs: [remoteShopId, cursor],
          );
        });
        applied++;
      } catch (error) {
        final message = error.toString();
        await db.update(
          'sync_inbox',
          {
            'apply_error': message.length > 500
                ? message.substring(0, 500)
                : message,
          },
          where: 'remote_shop_id = ? AND cursor = ? AND applied_at IS NULL',
          whereArgs: [remoteShopId, cursor],
        );
      }
    }
    return RemoteSyncApplyResult(
      applied: applied,
      pending: await getUnappliedRemoteEventCount(remoteShopId),
      errors: await getRemoteSyncApplyErrorCount(remoteShopId),
    );
  }

  Future<void> _applyRemoteEvent(
    Transaction txn,
    String remoteShopId,
    RemoteSyncEvent event,
  ) async {
    final existingTable = switch (event.eventType) {
      'sale.created' => 'sales',
      'sale.returned' => 'sale_returns',
      'baki.payment_recorded' => 'baki_payments',
      'purchase.recorded' => 'purchases',
      _ => throw FormatException(
        'Unsupported remote event: ${event.eventType}',
      ),
    };
    final duplicate = await txn.query(
      existingTable,
      columns: ['id'],
      where: 'origin_shop_id = ? AND origin_event_id = ?',
      whereArgs: [remoteShopId, event.eventId],
      limit: 1,
    );
    if (duplicate.isNotEmpty) return;
    switch (event.eventType) {
      case 'sale.created':
        await _applyRemoteSale(txn, remoteShopId, event);
        break;
      case 'sale.returned':
        await _applyRemoteReturn(txn, remoteShopId, event);
        break;
      case 'baki.payment_recorded':
        await _applyRemoteBakiPayment(txn, remoteShopId, event);
        break;
      case 'purchase.recorded':
        await _applyRemotePurchase(txn, remoteShopId, event);
        break;
    }
  }

  Future<void> _applyRemoteSale(
    Transaction txn,
    String remoteShopId,
    RemoteSyncEvent event,
  ) async {
    final payload = event.payload;
    if (payload['idempotencyKey'] != event.eventId ||
        payload['items'] is! List ||
        (payload['items'] as List).isEmpty) {
      throw const FormatException('Remote sale data is incomplete.');
    }
    final total = _remoteNumber(payload['totalAmount'], 'sale total');
    final discount = _remoteNumber(payload['discountAmount'] ?? 0, 'discount');
    final tax = _remoteNumber(payload['taxAmount'] ?? 0, 'tax');
    final createdAt = _remoteDate(payload['createdAt'], event.createdAt);
    final customerSyncId = payload['customerSyncId'];
    int? customerId;
    if (customerSyncId is String && customerSyncId.isNotEmpty) {
      final customers = await txn.query(
        'customers',
        columns: ['id'],
        where: 'sync_id = ?',
        whereArgs: [customerSyncId],
        limit: 1,
      );
      if (customers.isEmpty) {
        throw StateError('Waiting for the sale customer catalog record.');
      }
      customerId = customers.single['id'] as int;
    }
    final staffSyncId = payload['staffSyncId'];
    int? staffId;
    if (staffSyncId is String && staffSyncId.isNotEmpty) {
      final staff = await txn.query(
        'staff_users',
        columns: ['id'],
        where: 'sync_id = ?',
        whereArgs: [staffSyncId],
        limit: 1,
      );
      if (staff.isEmpty) {
        throw StateError('Waiting for the sale staff account catalog record.');
      }
      staffId = staff.single['id'] as int;
    }
    final items = <Map<String, Object?>>[];
    for (final raw in payload['items'] as List) {
      if (raw is! Map<String, dynamic>) {
        throw const FormatException('Remote sale item is invalid.');
      }
      final productSyncId = raw['productSyncId'];
      final variantSyncId = raw['variantSyncId'];
      if (productSyncId is! String ||
          productSyncId.isEmpty ||
          variantSyncId is! String ||
          variantSyncId.isEmpty) {
        throw const FormatException('Remote sale item is missing catalog IDs.');
      }
      final found = await txn.rawQuery(
        '''SELECT pv.id AS variant_id, pv.product_id, p.name AS current_product_name,
                  pv.name AS current_variant_name, p.cost_price
           FROM product_variants pv JOIN products p ON p.id = pv.product_id
           WHERE p.sync_id = ? AND pv.sync_id = ? LIMIT 1''',
        [productSyncId, variantSyncId],
      );
      if (found.isEmpty) {
        throw StateError('Waiting for a sale product catalog record.');
      }
      final quantity = _remoteNumber(raw['quantity'], 'item quantity');
      if (quantity <= 0) {
        throw const FormatException('Sale quantity must be positive.');
      }
      items.add({
        'product_id': found.single['product_id'],
        'variant_id': found.single['variant_id'],
        'product_name': raw['productName'] is String
            ? raw['productName']
            : found.single['current_product_name'],
        'variant_name': raw['variantName'] is String
            ? raw['variantName']
            : found.single['current_variant_name'],
        'product_price': _remoteNumber(raw['unitPrice'], 'unit price'),
        'quantity': quantity,
        'discount_amount': _remoteNumber(
          raw['discountAmount'] ?? 0,
          'item discount',
        ),
        'cost_price_snapshot': raw['costPrice'] is num
            ? (raw['costPrice'] as num).toDouble()
            : found.single['cost_price'],
      });
    }
    final paymentsRaw = payload['payments'];
    final payments = <Map<String, Object?>>[];
    if (paymentsRaw != null) {
      if (paymentsRaw is! List) {
        throw const FormatException('Remote sale payments are invalid.');
      }
      for (final raw in paymentsRaw) {
        if (raw is! Map<String, dynamic> || raw['method'] is! String) {
          throw const FormatException('Remote sale payment is invalid.');
        }
        payments.add({
          'method': raw['method'],
          'amount': _remoteNumber(raw['amount'], 'payment amount'),
          'note': raw['note'] is String ? raw['note'] : '',
        });
      }
    }
    final paymentType = payload['paymentType'] is String
        ? payload['paymentType'] as String
        : 'cash';
    final saleId = await txn.insert('sales', {
      'total_amount': total,
      'created_at': createdAt,
      'payment_type': paymentType,
      'customer_id': customerId,
      'customer_name': payload['customerName'],
      'discount_amount': discount,
      'discount_type': payload['discountType'] is String
          ? payload['discountType']
          : 'flat',
      'tax_amount': tax,
      'staff_id': staffId,
      'origin_shop_id': remoteShopId,
      'origin_event_id': event.eventId,
    });
    for (final item in items) {
      await txn.insert('sale_items', {'sale_id': saleId, ...item});
    }
    for (final payment in payments) {
      await txn.insert('sale_payments', {'sale_id': saleId, ...payment});
    }
  }

  Future<void> _applyRemoteReturn(
    Transaction txn,
    String remoteShopId,
    RemoteSyncEvent event,
  ) async {
    final payload = event.payload;
    final saleEventId = payload['saleEventId'];
    if (saleEventId is! String ||
        saleEventId.isEmpty ||
        payload['lines'] is! List) {
      throw const FormatException('Remote return data is incomplete.');
    }
    final sales = await txn.query(
      'sales',
      columns: ['id'],
      where: 'origin_shop_id = ? AND origin_event_id = ?',
      whereArgs: [remoteShopId, saleEventId],
      limit: 1,
    );
    if (sales.isEmpty) throw StateError('Waiting for the original sale event.');
    final saleId = sales.single['id'] as int;
    final lines = <({int saleItemId, Map<String, Object?> payload})>[];
    for (final raw in payload['lines'] as List) {
      if (raw is! Map<String, dynamic> ||
          raw['productSyncId'] is! String ||
          raw['variantSyncId'] is! String) {
        throw const FormatException('Remote return line is invalid.');
      }
      final saleItems = await txn.rawQuery(
        '''SELECT si.id, si.quantity,
             COALESCE((SELECT SUM(sri.quantity) FROM sale_return_items sri
                       JOIN sale_returns sr ON sr.id = sri.return_id
                       WHERE sr.sale_id = si.sale_id AND sri.sale_item_id = si.id), 0) AS returned
           FROM sale_items si JOIN products p ON p.id = si.product_id
           JOIN product_variants pv ON pv.id = si.variant_id
           WHERE si.sale_id = ? AND p.sync_id = ? AND pv.sync_id = ? LIMIT 1''',
        [saleId, raw['productSyncId'], raw['variantSyncId']],
      );
      if (saleItems.isEmpty) {
        throw StateError('Return item is not present on the original sale.');
      }
      final quantity = _remoteNumber(raw['quantity'], 'return quantity');
      final remaining =
          (saleItems.single['quantity'] as num).toDouble() -
          (saleItems.single['returned'] as num).toDouble();
      if (quantity <= 0 || quantity > remaining + 0.000001) {
        throw StateError('Remote return exceeds the original sold quantity.');
      }
      lines.add((saleItemId: saleItems.single['id'] as int, payload: raw));
    }
    if (lines.isEmpty) {
      throw const FormatException('Remote return has no lines.');
    }
    final returnId = await txn.insert('sale_returns', {
      'sale_id': saleId,
      'amount': _remoteNumber(payload['refundAmount'], 'refund amount'),
      'reason': payload['reason'] is String ? payload['reason'] : '',
      'refund_method': payload['refundMethod'] is String
          ? payload['refundMethod']
          : 'cash',
      'created_at': _remoteDate(null, event.createdAt),
      'origin_shop_id': remoteShopId,
      'origin_event_id': event.eventId,
    });
    for (final line in lines) {
      final raw = line.payload;
      await txn.insert('sale_return_items', {
        'return_id': returnId,
        'sale_item_id': line.saleItemId,
        'product_name': raw['productName'] is String ? raw['productName'] : '',
        'variant_name': raw['variantName'] is String ? raw['variantName'] : '',
        'quantity': _remoteNumber(raw['quantity'], 'return quantity'),
        'amount': _remoteNumber(raw['amount'], 'return line amount'),
      });
    }
  }

  Future<void> _applyRemoteBakiPayment(
    Transaction txn,
    String remoteShopId,
    RemoteSyncEvent event,
  ) async {
    final payload = event.payload;
    final customerSyncId = payload['customerSyncId'];
    if (customerSyncId is! String || customerSyncId.isEmpty) {
      throw const FormatException(
        'Remote customer payment is missing its customer ID.',
      );
    }
    final customers = await txn.query(
      'customers',
      columns: ['id'],
      where: 'sync_id = ?',
      whereArgs: [customerSyncId],
      limit: 1,
    );
    if (customers.isEmpty) {
      throw StateError('Waiting for the payment customer catalog record.');
    }
    await txn.insert('baki_payments', {
      'customer_id': customers.single['id'],
      'amount': _remoteNumber(payload['amount'], 'payment amount'),
      'note': payload['note'] is String ? payload['note'] : '',
      'paid_at': _remoteDate(payload['paidAt'], event.createdAt),
      'origin_shop_id': remoteShopId,
      'origin_event_id': event.eventId,
    });
  }

  Future<void> _applyRemotePurchase(
    Transaction txn,
    String remoteShopId,
    RemoteSyncEvent event,
  ) async {
    final payload = event.payload;
    final supplierSyncId = payload['supplierSyncId'];
    final rawItems = payload['items'];
    if (supplierSyncId is! String ||
        supplierSyncId.isEmpty ||
        rawItems is! List) {
      throw const FormatException('Remote purchase data is incomplete.');
    }
    final suppliers = await txn.query(
      'suppliers',
      columns: ['id', 'name'],
      where: 'sync_id = ?',
      whereArgs: [supplierSyncId],
      limit: 1,
    );
    if (suppliers.isEmpty) {
      throw StateError('Waiting for the purchase supplier catalog record.');
    }
    final lines =
        <
          ({
            int variantId,
            String productName,
            String variantName,
            double quantity,
            double costPrice,
          })
        >[];
    for (final raw in rawItems) {
      if (raw is! Map<String, dynamic> ||
          raw['productSyncId'] is! String ||
          raw['variantSyncId'] is! String) {
        throw const FormatException('Remote purchase item is invalid.');
      }
      final matches = await txn.rawQuery(
        '''SELECT pv.id, pv.name AS variant_name, p.name AS product_name
           FROM product_variants pv JOIN products p ON p.id = pv.product_id
           WHERE p.sync_id = ? AND pv.sync_id = ? LIMIT 1''',
        [raw['productSyncId'], raw['variantSyncId']],
      );
      if (matches.isEmpty) {
        throw StateError('Waiting for a purchase product catalog record.');
      }
      final quantity = _remoteNumber(raw['quantity'], 'purchase quantity');
      if (quantity <= 0) {
        throw const FormatException(
          'Remote purchase quantity must be positive.',
        );
      }
      lines.add((
        variantId: matches.single['id'] as int,
        productName: raw['productName'] is String
            ? raw['productName'] as String
            : matches.single['product_name'] as String,
        variantName: raw['variantName'] is String
            ? raw['variantName'] as String
            : matches.single['variant_name'] as String,
        quantity: quantity,
        costPrice: _remoteNumber(raw['costPrice'], 'purchase cost'),
      ));
    }
    if (lines.isEmpty) {
      throw const FormatException('Remote purchase has no items.');
    }
    final createdAt = _remoteDate(payload['createdAt'], event.createdAt);
    final total = _remoteNumber(payload['totalAmount'], 'purchase total');
    final purchaseId = await txn.insert('purchases', {
      'supplier_id': suppliers.single['id'],
      'supplier_name': payload['supplierName'] is String
          ? payload['supplierName']
          : suppliers.single['name'],
      'total_amount': total,
      'note': payload['note'] is String ? payload['note'] : '',
      'created_at': createdAt,
      'origin_shop_id': remoteShopId,
      'origin_event_id': event.eventId,
    });
    for (final line in lines) {
      await txn.insert('purchase_items', {
        'purchase_id': purchaseId,
        'variant_id': line.variantId,
        'product_name': line.productName,
        'variant_name': line.variantName,
        'quantity': line.quantity,
        'cost_price': line.costPrice,
      });
      // Retain the source movement for audit; catalog sync owns current stock and cost.
      await txn.insert('stock_movements', {
        'variant_id': line.variantId,
        'quantity': line.quantity,
        'cost_price': line.costPrice,
        'supplier': payload['supplierName'] is String
            ? payload['supplierName']
            : suppliers.single['name'],
        'created_at': createdAt,
      });
    }
  }

  double _remoteNumber(Object? value, String label) {
    if (value is! num || !value.toDouble().isFinite || value < 0) {
      throw FormatException('Remote $label is invalid.');
    }
    return value.toDouble();
  }

  String _remoteDate(Object? value, DateTime fallback) {
    if (value == null) return fallback.toUtc().toIso8601String();
    if (value is! String || DateTime.tryParse(value) == null) {
      throw const FormatException('Remote event date is invalid.');
    }
    return DateTime.parse(value).toUtc().toIso8601String();
  }

  Future<void> markRemoteSyncEventApplied(
    String remoteShopId,
    int cursor,
  ) async {
    final db = await database;
    await db.update(
      'sync_inbox',
      {'applied_at': DateTime.now().toUtc().toIso8601String()},
      where: 'remote_shop_id = ? AND cursor = ? AND applied_at IS NULL',
      whereArgs: [remoteShopId, cursor],
    );
  }

  String _newUuid() {
    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  Future<void> _queueSyncEvent(
    DatabaseExecutor executor, {
    required String eventType,
    required int entityId,
    required DateTime createdAt,
    required Map<String, Object?> payload,
  }) async {
    final idempotencyKey = _newUuid();
    await executor.insert('sync_outbox', {
      'idempotency_key': idempotencyKey,
      'event_type': eventType,
      'entity_id': entityId,
      'payload_json': jsonEncode({
        'idempotencyKey': idempotencyKey,
        ...payload,
      }),
      'created_at': createdAt.toUtc().toIso8601String(),
    });
  }

  // ── Products ──────────────────────────────────────────────────────────────

  Future<List<Map<String, Object?>>> _currentCloudCatalogEntities(
    DatabaseExecutor txn,
  ) async {
    final entities = <Map<String, Object?>>[];
    final products = await txn.query('products', orderBy: 'id ASC');
    for (final product in products) {
      final syncId = product['sync_id'] as String?;
      if (syncId == null || syncId.isEmpty) continue;
      final variants = await txn.query(
        'product_variants',
        where: 'product_id = ?',
        whereArgs: [product['id']],
        orderBy: 'id ASC',
      );
      entities.add({
        'entity_type': 'product',
        'entity_id': syncId,
        'payload': <String, Object?>{
          'syncId': syncId,
          'name': product['name'],
          'description': product['description'] ?? '',
          'category': product['category'] ?? '',
          'brand': product['brand'] ?? '',
          'sku': product['sku'] ?? '',
          'unit': product['unit'] ?? 'pcs',
          'costPrice': (product['cost_price'] as num?)?.toDouble() ?? 0,
          'lowStockAlert': product['low_stock_alert'] ?? 5,
          'quantityPrecision': product['quantity_precision'] ?? 0,
          'createdAt': product['created_at'],
          'imageData': await _productImageStorage.encodeForCloud(
            product['image_path'] as String? ?? '',
          ),
          'variants': variants
              .where(
                (variant) =>
                    (variant['sync_id'] as String?)?.isNotEmpty == true,
              )
              .map(
                (variant) => <String, Object?>{
                  'syncId': variant['sync_id'],
                  'name': variant['name'],
                  'barcode': variant['barcode'] ?? '',
                  'price': (variant['price'] as num).toDouble(),
                  'stock': (variant['stock'] as num).toDouble(),
                },
              )
              .toList(growable: false),
        },
      });
    }
    final customers = await txn.query('customers', orderBy: 'id ASC');
    for (final customer in customers) {
      final syncId = customer['sync_id'] as String?;
      if (syncId == null || syncId.isEmpty) continue;
      entities.add({
        'entity_type': 'customer',
        'entity_id': syncId,
        'payload': <String, Object?>{
          'syncId': syncId,
          'name': customer['name'],
          'phone': customer['phone'] ?? '',
          'createdAt': customer['created_at'],
        },
      });
    }
    final suppliers = await txn.query('suppliers', orderBy: 'id ASC');
    for (final supplier in suppliers) {
      final syncId = supplier['sync_id'] as String?;
      if (syncId == null || syncId.isEmpty) continue;
      entities.add({
        'entity_type': 'supplier',
        'entity_id': syncId,
        'payload': <String, Object?>{
          'syncId': syncId,
          'name': supplier['name'],
          'phone': supplier['phone'] ?? '',
          'address': supplier['address'] ?? '',
          'notes': supplier['notes'] ?? '',
        },
      });
    }
    final staffUsers = await txn.query('staff_users', orderBy: 'id ASC');
    for (final staff in staffUsers) {
      final syncId = staff['sync_id'] as String?;
      if (syncId == null || syncId.isEmpty) continue;
      entities.add({
        'entity_type': 'staff',
        'entity_id': syncId,
        'payload': <String, Object?>{
          'syncId': syncId,
          'name': staff['name'],
          'role': staff['role'],
          'pinSalt': staff['pin_salt'],
          'pinHash': staff['pin_hash'],
          'pinLength': staff['pin_length'] ?? 0,
          'active': staff['active'] == 1,
          'createdAt': staff['created_at'],
        },
      });
    }
    final settingRows = await txn.query('app_settings');
    final settings = {
      for (final row in settingRows)
        row['setting_key'] as String: row['setting_value'] as String,
    };
    final shopSettingsConfigured =
        settings['setup_complete'] == 'true' ||
        settings['shop_name']?.trim().isNotEmpty == true ||
        settings['shop_phone']?.trim().isNotEmpty == true ||
        settings['shop_address']?.trim().isNotEmpty == true ||
        settings['currency_symbol']?.trim().isNotEmpty == true &&
            settings['currency_symbol'] != r'$' ||
        settings['currency_locale']?.trim().isNotEmpty == true &&
            settings['currency_locale'] != 'en_US' ||
        (double.tryParse(settings['tax_rate'] ?? '0') ?? 0) != 0 ||
        settings['show_tax'] == 'true';
    if (shopSettingsConfigured) {
      entities.add({
        'entity_type': 'settings',
        'entity_id': cloudSettingsSyncId,
        'payload': <String, Object?>{
          'syncId': cloudSettingsSyncId,
          'name': 'Shop settings',
          'currencySymbol': settings['currency_symbol'] ?? r'$',
          'currencyLocale': settings['currency_locale'] ?? 'en_US',
          'taxRate': double.tryParse(settings['tax_rate'] ?? '0') ?? 0,
          'showTax': settings['show_tax'] == 'true',
          'shopName': settings['shop_name'] ?? '',
          'shopPhone': settings['shop_phone'] ?? '',
          'shopAddress': settings['shop_address'] ?? '',
          'setupComplete': settings['setup_complete'] == 'true',
        },
      });
    }
    return entities;
  }

  Object? _sortCatalogJson(Object? value) {
    if (value is Map) {
      final keys = value.keys.cast<String>().toList()..sort();
      return <String, Object?>{
        for (final key in keys) key: _sortCatalogJson(value[key]),
      };
    }
    if (value is List) return value.map(_sortCatalogJson).toList();
    return value;
  }

  String _catalogPayloadJson(Map<String, Object?> payload) =>
      jsonEncode(_sortCatalogJson(payload));

  bool _catalogValuesEqual(Object? left, Object? right) {
    if (left is num && right is num) return left == right;
    if (left is Map && right is Map) {
      if (left.length != right.length ||
          left.keys.toSet().difference(right.keys.toSet()).isNotEmpty) {
        return false;
      }
      return left.keys.every(
        (key) => _catalogValuesEqual(left[key], right[key]),
      );
    }
    if (left is List && right is List) {
      if (left.length != right.length) return false;
      for (var index = 0; index < left.length; index++) {
        if (!_catalogValuesEqual(left[index], right[index])) return false;
      }
      return true;
    }
    return left == right;
  }

  bool _catalogPayloadsEqual(
    Map<String, Object?> left,
    Map<String, Object?> right,
  ) {
    if (left.containsKey('imageData') != right.containsKey('imageData')) {
      final present = left.containsKey('imageData') ? left : right;
      if (present['imageData'] != null) return false;
      final leftWithoutImage = Map<String, Object?>.from(left)
        ..remove('imageData');
      final rightWithoutImage = Map<String, Object?>.from(right)
        ..remove('imageData');
      return _catalogValuesEqual(leftWithoutImage, rightWithoutImage);
    }
    return _catalogValuesEqual(left, right);
  }

  /// Creates durable, idempotent cloud mutations for local catalog changes.
  /// A pending mutation is retained unchanged until the server acknowledges it.
  Future<List<CloudCatalogMutation>> prepareCloudCatalogMutations(
    String remoteShopId,
  ) async {
    if (remoteShopId.isEmpty) throw ArgumentError('A remote shop is required.');
    final db = await database;
    return db.transaction((txn) async {
      final now = DateTime.now().toUtc().toIso8601String();
      final entities = await _currentCloudCatalogEntities(txn);
      for (final entity in entities) {
        final type = entity['entity_type']! as String;
        final id = entity['entity_id']! as String;
        final pending = await txn.query(
          'cloud_catalog_outbox',
          where: 'remote_shop_id = ? AND entity_type = ? AND entity_id = ?',
          whereArgs: [remoteShopId, type, id],
          limit: 1,
        );
        if (pending.isNotEmpty) continue;
        final stateRows = await txn.query(
          'cloud_catalog_state',
          where: 'remote_shop_id = ? AND entity_type = ? AND entity_id = ?',
          whereArgs: [remoteShopId, type, id],
          limit: 1,
        );
        final state = stateRows.firstOrNull;
        final payload = entity['payload']! as Map<String, Object?>;
        final payloadJson = _catalogPayloadJson(payload);
        if (state != null &&
            state['deleted'] == 0 &&
            _catalogPayloadsEqual(
              payload,
              (jsonDecode(state['payload_json'] as String) as Map)
                  .cast<String, Object?>(),
            )) {
          continue;
        }
        await txn.insert('cloud_catalog_outbox', {
          'remote_shop_id': remoteShopId,
          'mutation_id': _newUuid(),
          'entity_type': type,
          'entity_id': id,
          'base_revision': state?['revision'] ?? 0,
          'payload_json': payloadJson,
          'deleted': 0,
          'created_at': now,
        });
      }

      final deletions = await txn.query(
        'cloud_catalog_deletions',
        where: 'remote_shop_id = ?',
        whereArgs: [remoteShopId],
      );
      for (final deletion in deletions) {
        final type = deletion['entity_type'] as String;
        final id = deletion['entity_id'] as String;
        final stateRows = await txn.query(
          'cloud_catalog_state',
          where: 'remote_shop_id = ? AND entity_type = ? AND entity_id = ?',
          whereArgs: [remoteShopId, type, id],
          limit: 1,
        );
        final state = stateRows.firstOrNull;
        final pending = await txn.query(
          'cloud_catalog_outbox',
          where: 'remote_shop_id = ? AND entity_type = ? AND entity_id = ?',
          whereArgs: [remoteShopId, type, id],
          limit: 1,
        );
        if (state == null) {
          if (pending.isNotEmpty) continue;
          await txn.delete(
            'cloud_catalog_deletions',
            where: 'remote_shop_id = ? AND entity_type = ? AND entity_id = ?',
            whereArgs: [remoteShopId, type, id],
          );
          continue;
        }
        if (state['deleted'] == 1) {
          await txn.delete(
            'cloud_catalog_deletions',
            where: 'remote_shop_id = ? AND entity_type = ? AND entity_id = ?',
            whereArgs: [remoteShopId, type, id],
          );
          continue;
        }
        if (pending.isNotEmpty) continue;
        await txn.insert('cloud_catalog_outbox', {
          'remote_shop_id': remoteShopId,
          'mutation_id': _newUuid(),
          'entity_type': type,
          'entity_id': id,
          'base_revision': state['revision'],
          'payload_json': state['payload_json'],
          'deleted': 1,
          'created_at': now,
        });
      }
      final rows = await txn.query(
        'cloud_catalog_outbox',
        where: 'remote_shop_id = ?',
        whereArgs: [remoteShopId],
        orderBy: 'created_at ASC, entity_type ASC, entity_id ASC',
        limit: 100,
      );
      return rows.map(CloudCatalogMutation.fromMap).toList(growable: false);
    });
  }

  Future<void> acknowledgeCloudCatalogMutation(
    String remoteShopId,
    String mutationId,
    int revision,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'cloud_catalog_outbox',
        where: 'remote_shop_id = ? AND mutation_id = ?',
        whereArgs: [remoteShopId, mutationId],
        limit: 1,
      );
      if (rows.isEmpty) return;
      final mutation = rows.single;
      await txn.insert('cloud_catalog_state', {
        'remote_shop_id': remoteShopId,
        'entity_type': mutation['entity_type'],
        'entity_id': mutation['entity_id'],
        'revision': revision,
        'payload_json': mutation['payload_json'],
        'deleted': mutation['deleted'],
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.delete(
        'cloud_catalog_outbox',
        where: 'remote_shop_id = ? AND mutation_id = ?',
        whereArgs: [remoteShopId, mutationId],
      );
      if (mutation['deleted'] == 1) {
        await txn.delete(
          'cloud_catalog_deletions',
          where: 'remote_shop_id = ? AND entity_type = ? AND entity_id = ?',
          whereArgs: [
            remoteShopId,
            mutation['entity_type'],
            mutation['entity_id'],
          ],
        );
      }
    });
  }

  Future<int> getPendingCloudCatalogMutationCount(String remoteShopId) async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM cloud_catalog_outbox WHERE remote_shop_id = ?',
      [remoteShopId],
    );
    return (rows.first['count'] as int?) ?? 0;
  }

  Future<int> getCloudCatalogCursor(String remoteShopId) async {
    final db = await database;
    final rows = await db.query(
      'cloud_catalog_cursor',
      columns: ['cursor'],
      where: 'remote_shop_id = ?',
      whereArgs: [remoteShopId],
      limit: 1,
    );
    return rows.isEmpty ? 0 : rows.single['cursor'] as int;
  }

  Future<int> saveRemoteCloudCatalogChanges({
    required String remoteShopId,
    required CloudCatalogPage page,
  }) async {
    if (remoteShopId.isEmpty) throw ArgumentError('A remote shop is required.');
    final db = await database;
    return db.transaction((txn) async {
      final current = await getCloudCatalogCursorFrom(txn, remoteShopId);
      if (page.cursor < current) {
        throw StateError('The remote catalog cursor moved backwards.');
      }
      var previous = current;
      for (final change in page.changes) {
        if (change.cursor <= current) continue;
        if (change.cursor <= previous || change.cursor > page.cursor) {
          throw StateError('The remote catalog page is out of order.');
        }
        previous = change.cursor;
      }
      var received = 0;
      final now = DateTime.now().toUtc().toIso8601String();
      for (final change in page.changes) {
        if (change.cursor <= current) continue;
        received += await txn.insert('cloud_catalog_inbox', {
          'remote_shop_id': remoteShopId,
          'cursor': change.cursor,
          'entity_type': change.entityType,
          'entity_id': change.entityId,
          'mutation_id': change.mutationId,
          'base_revision': change.baseRevision,
          'revision': change.revision,
          'payload_json': _catalogPayloadJson(change.payload),
          'deleted': change.deleted ? 1 : 0,
          'changed_at': change.changedAt.toUtc().toIso8601String(),
          'received_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      await txn.insert('cloud_catalog_cursor', {
        'remote_shop_id': remoteShopId,
        'cursor': page.cursor,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return received;
    });
  }

  Future<CloudCatalogApplyResult> applyPendingCloudCatalogChanges(
    String remoteShopId, {
    int limit = 100,
  }) async {
    if (remoteShopId.isEmpty || limit < 1 || limit > 500) {
      throw ArgumentError('Invalid cloud catalog apply request.');
    }
    final db = await database;
    return db.transaction((txn) async {
      final rows = await txn.query(
        'cloud_catalog_inbox',
        where:
            'remote_shop_id = ? AND applied_at IS NULL AND conflict_reason IS NULL',
        whereArgs: [remoteShopId],
        orderBy: 'cursor ASC',
        limit: limit,
      );
      var applied = 0;
      var conflicts = 0;
      final blockedEntities = <String>{};
      for (final row in rows) {
        final type = row['entity_type'] as String;
        final entityId = row['entity_id'] as String;
        final entityKey = '$type:$entityId';
        if (blockedEntities.contains(entityKey)) continue;
        final revision = row['revision'] as int;
        final baseRevision = row['base_revision'] as int;
        final deleted = row['deleted'] == 1;
        final payload = (jsonDecode(row['payload_json'] as String) as Map)
            .cast<String, Object?>();
        final incomingJson = _catalogPayloadJson(payload);
        final stateRows = await txn.query(
          'cloud_catalog_state',
          where: 'remote_shop_id = ? AND entity_type = ? AND entity_id = ?',
          whereArgs: [remoteShopId, type, entityId],
          limit: 1,
        );
        final state = stateRows.firstOrNull;
        final local = (await _currentCloudCatalogEntities(txn))
            .where(
              (entity) =>
                  entity['entity_type'] == type &&
                  entity['entity_id'] == entityId,
            )
            .firstOrNull;
        final pending = await txn.query(
          'cloud_catalog_outbox',
          where: 'remote_shop_id = ? AND entity_type = ? AND entity_id = ?',
          whereArgs: [remoteShopId, type, entityId],
          limit: 1,
        );

        String? conflict;
        if (state != null && (state['revision'] as int) >= revision) {
          await _markCloudCatalogChangeApplied(
            txn,
            remoteShopId,
            row['cursor'] as int,
          );
          applied++;
          continue;
        }
        if (pending.isNotEmpty) {
          conflict =
              'This record has a local catalog change waiting to upload.';
        } else if (state == null) {
          if (local == null) {
            if (!deleted) {
              conflict = await _applyRemoteCatalogPayload(
                txn,
                type: type,
                entityId: entityId,
                payload: payload,
                deleted: false,
              );
            }
          } else if (!deleted &&
              _catalogPayloadsEqual(
                local['payload']! as Map<String, Object?>,
                payload,
              )) {
            // A restored backup can already contain the cloud version.
          } else {
            conflict =
                'This device has a catalog record with no matching cloud revision.';
          }
        } else if (baseRevision != state['revision']) {
          conflict =
              'The downloaded change does not follow this device’s saved cloud revision.';
        } else if (state['deleted'] == 1) {
          if (local != null && !deleted) {
            conflict =
                'A locally recreated record needs review before the cloud version is applied.';
          } else if (!deleted) {
            conflict = await _applyRemoteCatalogPayload(
              txn,
              type: type,
              entityId: entityId,
              payload: payload,
              deleted: false,
            );
          }
        } else if (local == null) {
          conflict =
              'This record was removed locally while it still exists in the cloud.';
        } else if (!_catalogPayloadsEqual(
          local['payload']! as Map<String, Object?>,
          (jsonDecode(state['payload_json'] as String) as Map)
              .cast<String, Object?>(),
        )) {
          conflict =
              'This device has local edits that are not in the cloud yet.';
        } else {
          conflict = await _applyRemoteCatalogPayload(
            txn,
            type: type,
            entityId: entityId,
            payload: payload,
            deleted: deleted,
          );
        }

        if (conflict != null) {
          blockedEntities.add(entityKey);
          await txn.update(
            'cloud_catalog_inbox',
            {'conflict_reason': conflict},
            where: 'remote_shop_id = ? AND cursor = ?',
            whereArgs: [remoteShopId, row['cursor']],
          );
          conflicts++;
          continue;
        }
        await txn.insert('cloud_catalog_state', {
          'remote_shop_id': remoteShopId,
          'entity_type': type,
          'entity_id': entityId,
          'revision': revision,
          'payload_json': incomingJson,
          'deleted': deleted ? 1 : 0,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        await _markCloudCatalogChangeApplied(
          txn,
          remoteShopId,
          row['cursor'] as int,
        );
        applied++;
      }
      return CloudCatalogApplyResult(applied: applied, conflicts: conflicts);
    });
  }

  Future<String?> _applyRemoteCatalogPayload(
    DatabaseExecutor txn, {
    required String type,
    required String entityId,
    required Map<String, Object?> payload,
    required bool deleted,
  }) async {
    if (payload['syncId'] != entityId || payload['name'] is! String) {
      return 'The downloaded record is missing its identity or name.';
    }
    if (type == 'supplier') {
      final rows = await txn.query(
        'suppliers',
        where: 'sync_id = ?',
        whereArgs: [entityId],
        limit: 1,
      );
      final existing = rows.firstOrNull;
      if (deleted) {
        if (existing == null) return null;
        final purchases = await txn.query(
          'purchases',
          columns: ['id'],
          where: 'supplier_id = ?',
          whereArgs: [existing['id']],
          limit: 1,
        );
        if (purchases.isNotEmpty) {
          return 'This supplier is referenced by purchase history and cannot be removed automatically.';
        }
        await txn.delete(
          'suppliers',
          where: 'id = ?',
          whereArgs: [existing['id']],
        );
        return null;
      }
      final name = payload['name'];
      final phone = payload['phone'] ?? '';
      final address = payload['address'] ?? '';
      final notes = payload['notes'] ?? '';
      if (name is! String ||
          name.trim().isEmpty ||
          name.length > 200 ||
          phone is! String ||
          phone.length > 40 ||
          address is! String ||
          address.length > 500 ||
          notes is! String ||
          notes.length > 1000) {
        return 'The downloaded supplier details are invalid.';
      }
      final values = {
        'sync_id': entityId,
        'name': name,
        'phone': phone,
        'address': address,
        'notes': notes,
      };
      if (existing == null) {
        await txn.insert('suppliers', values);
      } else {
        await txn.update(
          'suppliers',
          values,
          where: 'id = ?',
          whereArgs: [existing['id']],
        );
      }
      return null;
    }
    if (type == 'settings') {
      if (deleted || entityId != cloudSettingsSyncId) {
        return 'The shared shop settings record has an invalid identity.';
      }
      final symbol = payload['currencySymbol'];
      final locale = payload['currencyLocale'];
      final taxRate = payload['taxRate'];
      final showTax = payload['showTax'];
      final shopName = payload['shopName'];
      final shopPhone = payload['shopPhone'];
      final shopAddress = payload['shopAddress'];
      final setupComplete = payload['setupComplete'];
      if (symbol is! String ||
          symbol.isEmpty ||
          symbol.length > 8 ||
          locale is! String ||
          locale.isEmpty ||
          locale.length > 32 ||
          taxRate is! num ||
          !taxRate.isFinite ||
          taxRate < 0 ||
          taxRate > 100 ||
          showTax is! bool ||
          shopName is! String ||
          shopName.length > 200 ||
          shopPhone is! String ||
          shopPhone.length > 40 ||
          shopAddress is! String ||
          shopAddress.length > 500 ||
          setupComplete is! bool) {
        return 'The downloaded shop settings are invalid.';
      }
      final values = <String, String>{
        'currency_symbol': symbol,
        'currency_locale': locale,
        'tax_rate': taxRate.toDouble().toString(),
        'show_tax': showTax.toString(),
        'shop_name': shopName,
        'shop_phone': shopPhone,
        'shop_address': shopAddress,
        'setup_complete': setupComplete.toString(),
      };
      for (final entry in values.entries) {
        await txn.insert('app_settings', {
          'setting_key': entry.key,
          'setting_value': entry.value,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      return null;
    }
    if (type == 'staff') {
      final name = payload['name'] as String;
      if (deleted) {
        return 'Staff accounts are deactivated instead of deleted so sales attribution is preserved.';
      }
      final rows = await txn.query(
        'staff_users',
        where: 'sync_id = ?',
        whereArgs: [entityId],
        limit: 1,
      );
      final existing = rows.firstOrNull;
      final role = payload['role'];
      final salt = payload['pinSalt'];
      final hash = payload['pinHash'];
      final active = payload['active'];
      final createdAt = payload['createdAt'];
      final pinLength = payload['pinLength'] as int? ?? 0;
      if (payload['syncId'] != entityId ||
          name.trim().isEmpty ||
          name.length > 200 ||
          (role != 'owner' && role != 'cashier') ||
          salt is! String ||
          !RegExp(r'^[0-9a-f]{32}$').hasMatch(salt) ||
          hash is! String ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(hash) ||
          !{0, 4, 6}.contains(pinLength) ||
          active is! bool ||
          createdAt is! String ||
          DateTime.tryParse(createdAt) == null) {
        return 'The downloaded staff account is invalid.';
      }
      if (active && role == 'owner') {
        // An active incoming owner always satisfies the owner invariant.
      } else {
        final ownerRows = await txn.query(
          'staff_users',
          columns: ['id'],
          where: "role = 'owner' AND active = 1 AND sync_id != ?",
          whereArgs: [entityId],
        );
        if (ownerRows.isEmpty) {
          return 'At least one active owner must remain on this device.';
        }
      }
      final values = <String, Object?>{
        'sync_id': entityId,
        'name': name,
        'role': role,
        'pin_salt': salt,
        'pin_hash': hash,
        'pin_length': pinLength,
        'active': active ? 1 : 0,
        'created_at': createdAt,
      };
      if (existing == null) {
        await txn.insert('staff_users', values);
      } else {
        await txn.update(
          'staff_users',
          values,
          where: 'id = ?',
          whereArgs: [existing['id']],
        );
      }
      return null;
    }
    if (type == 'customer') {
      final rows = await txn.query(
        'customers',
        where: 'sync_id = ?',
        whereArgs: [entityId],
        limit: 1,
      );
      final existing = rows.firstOrNull;
      if (deleted) {
        if (existing == null) return null;
        final customerId = existing['id'];
        for (final table in ['sales', 'baki_payments']) {
          final refs = await txn.query(
            table,
            columns: ['id'],
            where: 'customer_id = ?',
            whereArgs: [customerId],
            limit: 1,
          );
          if (refs.isNotEmpty) {
            return 'This customer is referenced by sales or baki history and cannot be removed automatically.';
          }
        }
        await txn.delete('customers', where: 'id = ?', whereArgs: [customerId]);
        return null;
      }
      final createdAt = payload['createdAt'];
      if (createdAt is! String || DateTime.tryParse(createdAt) == null) {
        return 'The downloaded customer has an invalid creation date.';
      }
      final values = {
        'name': payload['name'],
        'phone': payload['phone'] is String ? payload['phone'] : '',
        'sync_id': entityId,
        'created_at': createdAt,
      };
      if (existing == null) {
        await txn.insert('customers', values);
      } else {
        await txn.update(
          'customers',
          values,
          where: 'id = ?',
          whereArgs: [existing['id']],
        );
      }
      return null;
    }
    if (type != 'product') return 'The downloaded catalog type is unsupported.';
    final variantsValue = payload['variants'];
    if (variantsValue is! List) {
      return 'The downloaded product variants are invalid.';
    }
    final variants = <Map<String, Object?>>[];
    final seenVariantIds = <String>{};
    for (final value in variantsValue) {
      if (value is! Map) {
        return 'The downloaded product contains an invalid variant.';
      }
      final variant = value.cast<String, Object?>();
      final variantId = variant['syncId'];
      final name = variant['name'];
      final price = variant['price'];
      final stock = variant['stock'];
      if (variantId is! String ||
          variantId.isEmpty ||
          !seenVariantIds.add(variantId) ||
          name is! String ||
          price is! num ||
          !price.isFinite ||
          stock is! num ||
          !stock.isFinite ||
          stock < 0) {
        return 'The downloaded product contains an invalid variant.';
      }
      variants.add(variant);
    }
    final productRows = await txn.query(
      'products',
      where: 'sync_id = ?',
      whereArgs: [entityId],
      limit: 1,
    );
    final existingProduct = productRows.firstOrNull;
    if (deleted) {
      if (existingProduct == null) return null;
      final history = await _productHasHistory(
        txn,
        existingProduct['id'] as int,
      );
      if (history) {
        return 'This product is used by sales, purchases, or stock history and cannot be removed automatically.';
      }
      await txn.delete(
        'product_variants',
        where: 'product_id = ?',
        whereArgs: [existingProduct['id']],
      );
      await txn.delete(
        'products',
        where: 'id = ?',
        whereArgs: [existingProduct['id']],
      );
      return null;
    }
    final createdAt = payload['createdAt'];
    final costPrice = payload['costPrice'];
    final lowStockAlert = payload['lowStockAlert'];
    final quantityPrecision = payload['quantityPrecision'];
    if (createdAt is! String ||
        DateTime.tryParse(createdAt) == null ||
        costPrice is! num ||
        !costPrice.isFinite ||
        costPrice < 0 ||
        lowStockAlert is! int ||
        lowStockAlert < 0 ||
        quantityPrecision is! int ||
        quantityPrecision < 0 ||
        quantityPrecision > 3) {
      return 'The downloaded product has an invalid creation date.';
    }
    final rawImageData = payload['imageData'];
    if (rawImageData != null && rawImageData is! String) {
      return 'The downloaded product image is invalid.';
    }
    String imagePath = '';
    final resolvedProductId = existingProduct?['id'] as int?;
    for (final variant in variants) {
      final idRows = await txn.query(
        'product_variants',
        columns: ['id', 'product_id'],
        where: 'sync_id = ?',
        whereArgs: [variant['syncId']],
        limit: 1,
      );
      if (idRows.isNotEmpty &&
          idRows.single['product_id'] != resolvedProductId) {
        return 'A product variant identity is already used by another local product.';
      }
    }
    if (rawImageData is String && rawImageData.isNotEmpty) {
      try {
        imagePath = await _productImageStorage.saveCloudImage(
          entityId,
          rawImageData,
        );
      } on FormatException {
        return 'The downloaded product image is invalid.';
      } on StateError {
        return 'The downloaded product image is invalid.';
      }
    }
    final hasImageData = payload.containsKey('imageData');
    final productValues = {
      'name': payload['name'],
      'description': payload['description'] is String
          ? payload['description']
          : '',
      'category': payload['category'] is String ? payload['category'] : '',
      'brand': payload['brand'] is String ? payload['brand'] : '',
      'sku': payload['sku'] is String ? payload['sku'] : '',
      'unit': payload['unit'] is String ? payload['unit'] : 'pcs',
      'cost_price': payload['costPrice'] is num ? payload['costPrice'] : 0,
      'low_stock_alert': payload['lowStockAlert'] is int
          ? payload['lowStockAlert']
          : 5,
      'quantity_precision': payload['quantityPrecision'] is int
          ? payload['quantityPrecision']
          : 0,
      'created_at': createdAt,
      'sync_id': entityId,
    };
    int productId;
    if (existingProduct == null) {
      productId = await txn.insert('products', {
        'image_path': imagePath,
        ...productValues,
      });
    } else {
      productId = existingProduct['id'] as int;
      final existingVariants = await txn.query(
        'product_variants',
        where: 'product_id = ?',
        whereArgs: [productId],
      );
      final incomingIds = variants.map((variant) => variant['syncId']).toSet();
      for (final variant in existingVariants) {
        final variantId = variant['sync_id'] as String?;
        if (variantId != null && incomingIds.contains(variantId)) continue;
        final used = await _variantHasHistory(txn, variant['id'] as int);
        if (used) {
          return 'A product variant removed in the cloud is referenced by local history.';
        }
      }
      final otherRows = await txn.query(
        'products',
        where: 'id = ?',
        whereArgs: [productId],
        limit: 1,
      );
      final keepImage = !hasImageData
          ? otherRows.single['image_path'] ?? ''
          : imagePath.isEmpty
          ? ''
          : imagePath;
      await txn.update(
        'products',
        {'image_path': keepImage, ...productValues},
        where: 'id = ?',
        whereArgs: [productId],
      );
      for (final variant in existingVariants) {
        if (!incomingIds.contains(variant['sync_id'])) {
          await txn.delete(
            'product_variants',
            where: 'id = ?',
            whereArgs: [variant['id']],
          );
        }
      }
    }
    for (final variant in variants) {
      final variantSyncId = variant['syncId'] as String;
      final idRows = await txn.query(
        'product_variants',
        where: 'sync_id = ?',
        whereArgs: [variantSyncId],
        limit: 1,
      );
      final existingVariant = idRows.firstOrNull;
      final values = {
        'product_id': productId,
        'sync_id': variantSyncId,
        'name': variant['name'],
        'barcode': variant['barcode'] is String ? variant['barcode'] : '',
        'price': (variant['price'] as num).toDouble(),
        'stock': (variant['stock'] as num).toDouble(),
      };
      if (existingVariant == null) {
        await txn.insert('product_variants', values);
      } else {
        await txn.update(
          'product_variants',
          values,
          where: 'id = ?',
          whereArgs: [existingVariant['id']],
        );
      }
    }
    return null;
  }

  Future<bool> _productHasHistory(DatabaseExecutor txn, int productId) async {
    final variants = await txn.query(
      'product_variants',
      columns: ['id'],
      where: 'product_id = ?',
      whereArgs: [productId],
    );
    for (final variant in variants) {
      if (await _variantHasHistory(txn, variant['id'] as int)) return true;
    }
    return false;
  }

  Future<bool> _variantHasHistory(DatabaseExecutor txn, int variantId) async {
    for (final table in ['sale_items', 'purchase_items', 'stock_movements']) {
      final rows = await txn.query(
        table,
        columns: ['id'],
        where: 'variant_id = ?',
        whereArgs: [variantId],
        limit: 1,
      );
      if (rows.isNotEmpty) return true;
    }
    return false;
  }

  Future<void> _markCloudCatalogChangeApplied(
    DatabaseExecutor txn,
    String remoteShopId,
    int cursor,
  ) async {
    await txn.update(
      'cloud_catalog_inbox',
      {
        'applied_at': DateTime.now().toUtc().toIso8601String(),
        'conflict_reason': null,
      },
      where: 'remote_shop_id = ? AND cursor = ?',
      whereArgs: [remoteShopId, cursor],
    );
  }

  Future<int> getCloudCatalogCursorFrom(
    DatabaseExecutor executor,
    String remoteShopId,
  ) async {
    final rows = await executor.query(
      'cloud_catalog_cursor',
      columns: ['cursor'],
      where: 'remote_shop_id = ?',
      whereArgs: [remoteShopId],
      limit: 1,
    );
    return rows.isEmpty ? 0 : rows.single['cursor'] as int;
  }

  Future<int> getUnappliedCloudCatalogChangeCount(String remoteShopId) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''SELECT COUNT(*) AS count FROM cloud_catalog_inbox
         WHERE remote_shop_id = ? AND applied_at IS NULL''',
      [remoteShopId],
    );
    return (rows.first['count'] as int?) ?? 0;
  }

  Future<int> getCloudCatalogConflictCount(String remoteShopId) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''SELECT COUNT(*) AS count FROM cloud_catalog_inbox
         WHERE remote_shop_id = ? AND conflict_reason IS NOT NULL''',
      [remoteShopId],
    );
    return (rows.first['count'] as int?) ?? 0;
  }

  Future<List<CloudCatalogConflict>> getCloudCatalogConflicts(
    String remoteShopId,
  ) async {
    final db = await database;
    final rows = await db.query(
      'cloud_catalog_inbox',
      where: 'remote_shop_id = ? AND conflict_reason IS NOT NULL',
      whereArgs: [remoteShopId],
      orderBy: 'cursor ASC',
    );
    final localEntities = await _currentCloudCatalogEntities(db);
    final localById = {
      for (final entity in localEntities)
        '${entity['entity_type']}:${entity['entity_id']}':
            entity['payload'] as Map<String, Object?>,
    };
    return rows
        .map((row) {
          final entityKey = '${row['entity_type']}:${row['entity_id']}';
          final payload = localById[entityKey];
          return CloudCatalogConflict.fromMap({
            ...row,
            if (payload != null)
              'local_payload_json': _catalogPayloadJson(payload),
          });
        })
        .toList(growable: false);
  }

  Future<void> recordCloudCatalogWriteConflict({
    required String remoteShopId,
    required CloudCatalogMutation mutation,
    required Map<String, dynamic> details,
  }) async {
    final revision = details['currentRevision'];
    final remotePayload = details['currentPayload'];
    final remoteDeleted = details['deleted'];
    if (revision is! int ||
        revision < 0 ||
        (remotePayload != null && remotePayload is! Map<String, dynamic>) ||
        remoteDeleted is! bool) {
      throw const FormatException(
        'The server returned invalid catalog conflict details.',
      );
    }
    final db = await database;
    await db.transaction((txn) async {
      var syntheticCursor = -DateTime.now().microsecondsSinceEpoch;
      while ((await txn.query(
        'cloud_catalog_inbox',
        columns: ['cursor'],
        where: 'remote_shop_id = ? AND cursor = ?',
        whereArgs: [remoteShopId, syntheticCursor],
        limit: 1,
      )).isNotEmpty) {
        syntheticCursor--;
      }
      final payload = remotePayload is Map<String, dynamic>
          ? remotePayload.cast<String, Object?>()
          : mutation.payload;
      final isMissingOnServer = remotePayload == null && revision == 0;
      await txn.insert('cloud_catalog_inbox', {
        'remote_shop_id': remoteShopId,
        'cursor': syntheticCursor,
        'entity_type': mutation.entityType,
        'entity_id': mutation.entityId,
        'mutation_id': mutation.mutationId,
        'base_revision': revision > 0 ? revision - 1 : 0,
        'revision': revision,
        'payload_json': _catalogPayloadJson(payload),
        'deleted': remoteDeleted || isMissingOnServer ? 1 : 0,
        'changed_at': DateTime.now().toUtc().toIso8601String(),
        'received_at': DateTime.now().toUtc().toIso8601String(),
        'conflict_reason': details['message'] is String
            ? details['message']
            : 'The server has a newer catalog revision.',
      });
    });
  }

  Future<void> resolveCloudCatalogConflict({
    required String remoteShopId,
    required int cursor,
    required bool useRemote,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'cloud_catalog_inbox',
        where:
            'remote_shop_id = ? AND cursor = ? AND conflict_reason IS NOT NULL',
        whereArgs: [remoteShopId, cursor],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw StateError('This catalog conflict is no longer available.');
      }
      final row = rows.single;
      final type = row['entity_type'] as String;
      final entityId = row['entity_id'] as String;
      final revision = row['revision'] as int;
      final deleted = row['deleted'] == 1;
      final payload = (jsonDecode(row['payload_json'] as String) as Map)
          .cast<String, Object?>();
      final payloadJson = _catalogPayloadJson(payload);
      final stateRows = await txn.query(
        'cloud_catalog_state',
        where: 'remote_shop_id = ? AND entity_type = ? AND entity_id = ?',
        whereArgs: [remoteShopId, type, entityId],
        limit: 1,
      );
      final state = stateRows.firstOrNull;
      if (state != null && (state['revision'] as int) > revision) {
        throw StateError(
          'A newer cloud revision arrived. Sync again before resolving this conflict.',
        );
      }

      final local = (await _currentCloudCatalogEntities(txn))
          .where(
            (entity) =>
                entity['entity_type'] == type &&
                entity['entity_id'] == entityId,
          )
          .firstOrNull;
      if (useRemote) {
        final error = await _applyRemoteCatalogPayload(
          txn,
          type: type,
          entityId: entityId,
          payload: payload,
          deleted: deleted,
        );
        if (error != null) throw StateError(error);
        await txn.delete(
          'cloud_catalog_outbox',
          where: 'remote_shop_id = ? AND entity_type = ? AND entity_id = ?',
          whereArgs: [remoteShopId, type, entityId],
        );
        await txn.delete(
          'cloud_catalog_deletions',
          where: 'remote_shop_id = ? AND entity_type = ? AND entity_id = ?',
          whereArgs: [remoteShopId, type, entityId],
        );
      } else {
        await txn.delete(
          'cloud_catalog_outbox',
          where: 'remote_shop_id = ? AND entity_type = ? AND entity_id = ?',
          whereArgs: [remoteShopId, type, entityId],
        );
        Map<String, Object?>? localPayload =
            local?['payload'] as Map<String, Object?>?;
        var outgoingDeleted = false;
        if (localPayload == null && !deleted) {
          localPayload = payload;
          outgoingDeleted = true;
        } else if (localPayload == null && deleted) {
          outgoingDeleted = false;
        } else if (deleted) {
          outgoingDeleted = false;
        } else if (_catalogPayloadsEqual(localPayload!, payload)) {
          localPayload = null;
        }
        if (localPayload != null) {
          await txn.insert('cloud_catalog_outbox', {
            'remote_shop_id': remoteShopId,
            'mutation_id': _newUuid(),
            'entity_type': type,
            'entity_id': entityId,
            'base_revision': revision,
            'payload_json': _catalogPayloadJson(localPayload),
            'deleted': outgoingDeleted ? 1 : 0,
            'created_at': DateTime.now().toUtc().toIso8601String(),
          });
        }
      }

      await txn.insert('cloud_catalog_state', {
        'remote_shop_id': remoteShopId,
        'entity_type': type,
        'entity_id': entityId,
        'revision': revision,
        'payload_json': payloadJson,
        'deleted': deleted ? 1 : 0,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await _markCloudCatalogChangeApplied(txn, remoteShopId, cursor);
    });
  }

  Future<List<Product>> getAllProducts() async {
    final db = await database;
    final rows = await db.query('products', orderBy: 'name ASC');
    final List<Product> products = [];
    for (final row in rows) {
      final variants = await _getVariantsForProduct(db, row['id'] as int);
      products.add(Product.fromMap(row, variants: variants));
    }
    return products;
  }

  Future<List<ProductVariant>> _getVariantsForProduct(
    Database db,
    int productId,
  ) async {
    final rows = await db.query(
      'product_variants',
      where: 'product_id = ?',
      whereArgs: [productId],
      orderBy: 'id ASC',
    );
    return rows.map(ProductVariant.fromMap).toList();
  }

  Future<int> insertProduct(Product product) async {
    final db = await database;
    return db.transaction((txn) async {
      final map = product.toMap()..remove('id');
      map['sync_id'] = product.syncId ?? _newUuid();
      final productId = await txn.insert('products', map);
      for (final v in product.variants) {
        final vMap = v.toMap()
          ..remove('id')
          ..['product_id'] = productId;
        vMap['sync_id'] = v.syncId ?? _newUuid();
        await txn.insert('product_variants', vMap);
      }
      return productId;
    });
  }

  Future<void> updateProduct(Product product) async {
    final db = await database;
    await db.transaction((txn) async {
      final productRows = await txn.query(
        'products',
        columns: ['sync_id'],
        where: 'id = ?',
        whereArgs: [product.id],
        limit: 1,
      );
      if (productRows.isEmpty) throw StateError('Product no longer exists.');
      final productMap = product.toMap()
        ..['sync_id'] = product.syncId ?? productRows.single['sync_id'];
      await txn.update(
        'products',
        productMap,
        where: 'id = ?',
        whereArgs: [product.id],
      );

      final existingIds = product.variants
          .where((v) => v.id != null)
          .map((v) => v.id!)
          .toList();

      if (existingIds.isEmpty) {
        await txn.delete(
          'product_variants',
          where: 'product_id = ?',
          whereArgs: [product.id],
        );
      } else {
        final ph = existingIds.map((_) => '?').join(', ');
        await txn.delete(
          'product_variants',
          where: 'product_id = ? AND id NOT IN ($ph)',
          whereArgs: [product.id, ...existingIds],
        );
      }

      for (final v in product.variants) {
        if (v.id != null) {
          final variantRows = await txn.query(
            'product_variants',
            columns: ['sync_id'],
            where: 'id = ?',
            whereArgs: [v.id],
            limit: 1,
          );
          if (variantRows.isEmpty) {
            throw StateError('Product variant no longer exists.');
          }
          final variantMap = v.toMap()
            ..['sync_id'] = v.syncId ?? variantRows.single['sync_id']
            ..['product_id'] = product.id;
          await txn.update(
            'product_variants',
            variantMap,
            where: 'id = ?',
            whereArgs: [v.id],
          );
        } else {
          final vMap = v.toMap()
            ..remove('id')
            ..['product_id'] = product.id;
          vMap['sync_id'] = v.syncId ?? _newUuid();
          await txn.insert('product_variants', vMap);
        }
      }
    });
  }

  Future<void> deleteProduct(int id) async {
    final db = await database;
    await db.transaction((txn) async {
      final products = await txn.query(
        'products',
        columns: ['sync_id'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      final syncId = products.firstOrNull?['sync_id'] as String?;
      if (syncId != null && syncId.isNotEmpty) {
        final shops = await txn.rawQuery(
          '''SELECT remote_shop_id FROM cloud_catalog_state
             WHERE entity_type = 'product' AND entity_id = ?
             UNION SELECT remote_shop_id FROM cloud_catalog_outbox
             WHERE entity_type = 'product' AND entity_id = ?''',
          [syncId, syncId],
        );
        for (final shop in shops) {
          await txn.insert('cloud_catalog_deletions', {
            'remote_shop_id': shop['remote_shop_id'],
            'entity_type': 'product',
            'entity_id': syncId,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      }
      await txn.delete(
        'product_variants',
        where: 'product_id = ?',
        whereArgs: [id],
      );
      await txn.delete('products', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<void> stockIn(
    int variantId,
    double quantity, {
    double costPrice = 0,
    String supplier = '',
  }) async {
    if (!quantity.isFinite || quantity <= 0) {
      throw ArgumentError('Stock quantity must be a positive finite value.');
    }
    final db = await database;
    await db.transaction((txn) async {
      final precisionRows = await txn.rawQuery(
        '''SELECT p.quantity_precision FROM product_variants pv
           JOIN products p ON p.id = pv.product_id WHERE pv.id = ?''',
        [variantId],
      );
      if (precisionRows.isEmpty ||
          !isQuantityAllowed(
            quantity,
            precisionRows.first['quantity_precision'] as int? ?? 0,
          )) {
        throw ArgumentError('Stock quantity does not match product precision.');
      }
      await _receiveStock(
        txn,
        variantId,
        quantity,
        costPrice,
        supplier,
        DateTime.now(),
      );
    });
  }

  Future<void> _receiveStock(
    DatabaseExecutor txn,
    int variantId,
    double quantity,
    double costPrice,
    String supplier,
    DateTime createdAt,
  ) async {
    await txn.rawUpdate(
      'UPDATE product_variants SET stock = stock + ? WHERE id = ?',
      [quantity, variantId],
    );
    await txn.insert('stock_movements', {
      'variant_id': variantId,
      'quantity': quantity,
      'cost_price': costPrice,
      'supplier': supplier,
      'created_at': createdAt.toIso8601String(),
    });
  }

  Future<List<Supplier>> getSuppliers() async {
    final db = await database;
    final rows = await db.query('suppliers', orderBy: 'name COLLATE NOCASE');
    return rows.map(Supplier.fromMap).toList();
  }

  Future<int> saveSupplier(Supplier supplier) async {
    if (supplier.name.trim().isEmpty) {
      throw ArgumentError('Supplier name is required.');
    }
    final db = await database;
    final values = supplier.toMap()..remove('id');
    if (supplier.id == null) {
      values['sync_id'] = supplier.syncId ?? _newUuid();
      return db.insert('suppliers', values);
    }
    final existing = await db.query(
      'suppliers',
      columns: ['sync_id'],
      where: 'id = ?',
      whereArgs: [supplier.id],
      limit: 1,
    );
    if (existing.isEmpty) throw ArgumentError('Supplier was not found.');
    values['sync_id'] =
        supplier.syncId ?? existing.single['sync_id'] ?? _newUuid();
    await db.update(
      'suppliers',
      values,
      where: 'id = ?',
      whereArgs: [supplier.id],
    );
    return supplier.id!;
  }

  Future<int> recordPurchase({
    required Supplier supplier,
    required List<PurchaseLine> items,
    String note = '',
    DateTime? createdAt,
  }) async {
    if (supplier.id == null ||
        items.isEmpty ||
        items.any(
          (item) =>
              !item.quantity.isFinite ||
              item.quantity <= 0 ||
              !item.costPrice.isFinite ||
              item.costPrice < 0 ||
              item.variantId <= 0,
        )) {
      throw ArgumentError('Purchase details are invalid.');
    }
    final db = await database;
    return db.transaction((txn) async {
      final supplierRows = await txn.query(
        'suppliers',
        where: 'id = ?',
        whereArgs: [supplier.id],
        limit: 1,
      );
      if (supplierRows.isEmpty) throw ArgumentError('Supplier was not found.');
      final supplierSyncId = supplierRows.single['sync_id'] as String?;
      if (supplierSyncId == null || supplierSyncId.isEmpty) {
        throw StateError('Supplier sync identity is missing.');
      }
      var total = 0.0;
      for (final item in items) {
        total += item.total;
      }
      final date = createdAt ?? DateTime.now();
      final purchaseId = await txn.insert('purchases', {
        'supplier_id': supplier.id,
        'supplier_name': supplier.name,
        'total_amount': total,
        'note': note.trim(),
        'created_at': date.toIso8601String(),
      });
      final syncItems = <Map<String, Object?>>[];
      for (final item in items) {
        final variantRows = await txn.rawQuery(
          '''
          SELECT pv.id, pv.name, pv.product_id, pv.sync_id AS variant_sync_id,
                 p.sync_id AS product_sync_id, p.name AS product_name,
                 p.quantity_precision
          FROM product_variants pv
          JOIN products p ON p.id = pv.product_id
          WHERE pv.id = ?
        ''',
          [item.variantId],
        );
        if (variantRows.isEmpty) {
          throw ArgumentError('A purchase item no longer exists.');
        }
        final variant = variantRows.single;
        final productSyncId = variant['product_sync_id'] as String?;
        final variantSyncId = variant['variant_sync_id'] as String?;
        if (productSyncId == null || variantSyncId == null) {
          throw StateError('Purchase product sync identity is missing.');
        }
        if (!isQuantityAllowed(
          item.quantity,
          variant['quantity_precision'] as int? ?? 0,
        )) {
          throw ArgumentError(
            'Purchase quantity does not match product precision.',
          );
        }
        await txn.insert('purchase_items', {
          'purchase_id': purchaseId,
          'variant_id': item.variantId,
          'product_name': variant['product_name'],
          'variant_name': variant['name'],
          'quantity': item.quantity,
          'cost_price': item.costPrice,
        });
        await _receiveStock(
          txn,
          item.variantId,
          item.quantity,
          item.costPrice,
          supplier.name,
          date,
        );
        await txn.update(
          'products',
          {'cost_price': item.costPrice},
          where: 'id = ?',
          whereArgs: [variant['product_id']],
        );
        syncItems.add({
          'productSyncId': productSyncId,
          'variantSyncId': variantSyncId,
          'productName': variant['product_name'],
          'variantName': variant['name'],
          'quantity': item.quantity,
          'costPrice': item.costPrice,
        });
      }
      await _queueSyncEvent(
        txn,
        eventType: 'purchase.recorded',
        entityId: purchaseId,
        createdAt: date,
        payload: {
          'supplierSyncId': supplierSyncId,
          'supplierName': supplier.name,
          'totalAmount': total,
          'createdAt': date.toUtc().toIso8601String(),
          'note': note.trim(),
          'items': syncItems,
        },
      );
      return purchaseId;
    });
  }

  Future<List<Purchase>> getPurchases() async {
    final db = await database;
    final rows = await db.query('purchases', orderBy: 'created_at DESC');
    final purchases = <Purchase>[];
    for (final row in rows) {
      final purchaseId = row['id'] as int;
      final lineRows = await db.query(
        'purchase_items',
        where: 'purchase_id = ?',
        whereArgs: [purchaseId],
        orderBy: 'id ASC',
      );
      purchases.add(
        Purchase(
          id: purchaseId,
          supplierId: row['supplier_id'] as int?,
          supplierName: row['supplier_name'] as String,
          totalAmount: (row['total_amount'] as num).toDouble(),
          createdAt: DateTime.parse(row['created_at'] as String),
          note: row['note'] as String? ?? '',
          items: lineRows
              .map(
                (line) => PurchaseLine(
                  variantId: line['variant_id'] as int,
                  productName: line['product_name'] as String,
                  variantName: line['variant_name'] as String? ?? '',
                  quantity: (line['quantity'] as num).toDouble(),
                  costPrice: (line['cost_price'] as num).toDouble(),
                ),
              )
              .toList(),
        ),
      );
    }
    return purchases;
  }

  // ── Sales ─────────────────────────────────────────────────────────────────

  Future<int> insertSale(Sale sale) async {
    if (sale.items.any(
      (item) =>
          !isQuantityAllowed(item.quantity, item.product.quantityPrecision),
    )) {
      throw ArgumentError('Sale quantities must match each product precision.');
    }
    if (sale.payments.isNotEmpty) {
      const allowedMethods = {'cash', 'bkash', 'nagad', 'card', 'baki'};
      if (sale.payments.any(
        (payment) =>
            !allowedMethods.contains(payment.method) ||
            !payment.amount.isFinite ||
            payment.amount <= 0,
      )) {
        throw ArgumentError(
          'Sale payments must use a valid method and amount.',
        );
      }
      final allocated = sale.payments.fold(
        0.0,
        (total, payment) => total + payment.amount,
      );
      if ((allocated - sale.totalAmount).abs() > 0.01) {
        throw ArgumentError(
          'Sale payment allocations must equal the sale total.',
        );
      }
      if (sale.payments.any((payment) => payment.method == 'baki') &&
          sale.customerId == null) {
        throw ArgumentError(
          'A customer is required when a sale includes baki.',
        );
      }
    }
    final db = await database;
    return db.transaction((txn) async {
      final customerSyncId = sale.customerId == null
          ? null
          : (await txn.query(
              'customers',
              columns: ['sync_id'],
              where: 'id = ?',
              whereArgs: [sale.customerId],
              limit: 1,
            )).firstOrNull?['sync_id'];
      final staffSyncId = sale.staffId == null
          ? null
          : (await txn.query(
              'staff_users',
              columns: ['sync_id'],
              where: 'id = ?',
              whereArgs: [sale.staffId],
              limit: 1,
            )).firstOrNull?['sync_id'];
      final bakiAllocated = sale.payments
          .where((payment) => payment.method == 'baki')
          .fold(0.0, (total, payment) => total + payment.amount);
      final paymentType = sale.payments.isEmpty
          ? sale.paymentType
          : bakiAllocated > 0
          ? 'baki'
          : sale.payments.length == 1
          ? sale.payments.single.method
          : 'split';
      final saleId = await txn.insert('sales', {
        'total_amount': sale.totalAmount,
        'created_at': sale.createdAt.toIso8601String(),
        'payment_type': paymentType,
        'customer_id': sale.customerId,
        'customer_name': sale.customerName,
        'discount_amount': sale.discountAmount,
        'discount_type': sale.discountType,
        'tax_amount': sale.taxAmount,
        'staff_id': sale.staffId,
      });
      for (final item in sale.items) {
        await txn.insert('sale_items', {
          'sale_id': saleId,
          'product_id': item.product.id ?? 0,
          'variant_id': item.variant.id ?? 0,
          'product_name': item.product.name,
          'variant_name': item.variant.name,
          'product_price': item.variant.price,
          'quantity': item.quantity,
          'discount_amount': item.discountAmount,
          'cost_price_snapshot': item.product.costPrice > 0
              ? item.product.costPrice
              : null,
        });
        if (item.variant.id != null) {
          await txn.rawUpdate(
            'UPDATE product_variants SET stock = MAX(0, stock - ?) WHERE id = ?',
            [item.quantity, item.variant.id],
          );
        }
      }
      for (final payment in sale.payments) {
        await txn.insert('sale_payments', {
          'sale_id': saleId,
          ...payment.toMap()..remove('id'),
        });
      }
      final idempotencyKey = _newUuid();
      await txn.insert('sync_outbox', {
        'idempotency_key': idempotencyKey,
        'event_type': 'sale.created',
        'entity_id': saleId,
        'payload_json': jsonEncode({
          'idempotencyKey': idempotencyKey,
          'localSaleId': saleId,
          'totalAmount': sale.totalAmount,
          'createdAt': sale.createdAt.toIso8601String(),
          'paymentType': paymentType,
          'localCustomerId': sale.customerId,
          'customerSyncId': customerSyncId,
          'customerName': sale.customerName,
          'discountAmount': sale.discountAmount,
          'discountType': sale.discountType,
          'taxAmount': sale.taxAmount,
          'localStaffId': sale.staffId,
          'staffSyncId': staffSyncId,
          'items': sale.items
              .map(
                (item) => {
                  'localProductId': item.product.id,
                  'localVariantId': item.variant.id,
                  'productSyncId': item.product.syncId,
                  'variantSyncId': item.variant.syncId,
                  'productName': item.product.name,
                  'variantName': item.variant.name,
                  'unitPrice': item.variant.price,
                  'costPrice': item.product.costPrice > 0
                      ? item.product.costPrice
                      : null,
                  'quantity': item.quantity,
                  'discountAmount': item.discountAmount,
                },
              )
              .toList(),
          'payments': sale.payments
              .map((payment) => payment.toMap()..remove('id'))
              .toList(),
        }),
        'created_at': DateTime.now().toIso8601String(),
      });
      return saleId;
    });
  }

  Future<SaleReturn> createSaleReturn({
    required int saleId,
    required Map<int, double> quantitiesBySaleItemId,
    required String reason,
    required String refundMethod,
    DateTime? createdAt,
  }) async {
    const refundMethods = {'cash', 'bkash', 'nagad', 'card', 'baki'};
    if (quantitiesBySaleItemId.isEmpty ||
        quantitiesBySaleItemId.values.any(
          (quantity) => !quantity.isFinite || quantity <= 0,
        ) ||
        reason.trim().isEmpty ||
        !refundMethods.contains(refundMethod)) {
      throw ArgumentError('Return details are invalid.');
    }
    final db = await database;
    return db.transaction((txn) async {
      final sales = await txn.query(
        'sales',
        where: 'id = ?',
        whereArgs: [saleId],
        limit: 1,
      );
      if (sales.isEmpty) throw ArgumentError('Sale was not found.');
      final sale = sales.single;
      if (refundMethod == 'baki' && sale['customer_id'] == null) {
        throw ArgumentError('A customer is required to reduce baki.');
      }
      final saleItems = await txn.rawQuery(
        '''
        SELECT si.*, p.sync_id AS product_sync_id,
               pv.sync_id AS variant_sync_id
        FROM sale_items si
        LEFT JOIN products p ON p.id = si.product_id
        LEFT JOIN product_variants pv ON pv.id = si.variant_id
        WHERE si.sale_id = ?
        ''',
        [saleId],
      );
      final selectedIds = quantitiesBySaleItemId.keys.toSet();
      if (saleItems.any(
        (item) =>
            selectedIds.contains(item['id']) &&
            (item['variant_id'] as int) <= 0,
      )) {
        throw ArgumentError('Returned item is not linked to stock.');
      }
      final previousRows = await txn.rawQuery(
        '''
        SELECT sri.sale_item_id, SUM(sri.quantity) AS quantity
        FROM sale_return_items sri
        JOIN sale_returns sr ON sr.id = sri.return_id
        WHERE sr.sale_id = ?
        GROUP BY sri.sale_item_id
      ''',
        [saleId],
      );
      final alreadyReturned = {
        for (final row in previousRows)
          row['sale_item_id'] as int: (row['quantity'] as num).toDouble(),
      };
      final saleById = {for (final row in saleItems) row['id'] as int: row};
      if (selectedIds.any((id) => !saleById.containsKey(id))) {
        throw ArgumentError('Returned item does not belong to this sale.');
      }
      for (final entry in quantitiesBySaleItemId.entries) {
        final sold = (saleById[entry.key]!['quantity'] as num).toDouble();
        if (entry.value + (alreadyReturned[entry.key] ?? 0) > sold) {
          throw ArgumentError('Return quantity exceeds the unreturned items.');
        }
        final precisionRows = await txn.query(
          'products',
          columns: ['quantity_precision'],
          where: 'id = ?',
          whereArgs: [saleById[entry.key]!['product_id']],
          limit: 1,
        );
        if (precisionRows.isEmpty ||
            !isQuantityAllowed(
              entry.value,
              precisionRows.single['quantity_precision'] as int? ?? 0,
            )) {
          throw ArgumentError(
            'Return quantity does not match product precision.',
          );
        }
      }

      var totalWeight = 0.0;
      for (final row in saleItems) {
        final price = (row['product_price'] as num).toDouble();
        final discount = (row['discount_amount'] as num? ?? 0).toDouble();
        final quantity = (row['quantity'] as num).toDouble();
        totalWeight +=
            (price - discount).clamp(0.0, double.infinity) * quantity;
      }
      if (totalWeight <= 0) {
        throw ArgumentError('Sale has no refundable value.');
      }
      final total = (sale['total_amount'] as num).toDouble();
      var amount = 0.0;
      final lineAmounts = <int, double>{};
      for (final entry in quantitiesBySaleItemId.entries) {
        final row = saleById[entry.key]!;
        final price = (row['product_price'] as num).toDouble();
        final discount = (row['discount_amount'] as num? ?? 0).toDouble();
        final quantity = (row['quantity'] as num).toDouble();
        final lineWeight =
            (price - discount).clamp(0.0, double.infinity) * quantity;
        final lineAmount =
            total * lineWeight / totalWeight * entry.value / quantity;
        lineAmounts[entry.key] = lineAmount;
        amount += lineAmount;
      }
      amount = double.parse(amount.toStringAsFixed(2));
      if (refundMethod == 'baki') {
        final customerId = sale['customer_id'] as int;
        final allocations = await txn.rawQuery(
          '''
          SELECT COALESCE(SUM(CASE WHEN EXISTS (
            SELECT 1 FROM sale_payments sp WHERE sp.sale_id = s.id
          ) THEN COALESCE((SELECT SUM(sp.amount) FROM sale_payments sp
                           WHERE sp.sale_id = s.id AND sp.method = 'baki'), 0)
            WHEN s.payment_type = 'baki' THEN s.total_amount ELSE 0 END), 0) AS issued
          FROM sales s WHERE s.customer_id = ?
        ''',
          [customerId],
        );
        final saleBakiRows = await txn.rawQuery(
          '''
          SELECT CASE WHEN EXISTS (
            SELECT 1 FROM sale_payments sp WHERE sp.sale_id = s.id
          ) THEN COALESCE((SELECT SUM(sp.amount) FROM sale_payments sp
                           WHERE sp.sale_id = s.id AND sp.method = 'baki'), 0)
            WHEN s.payment_type = 'baki' THEN s.total_amount ELSE 0 END AS issued,
            COALESCE((SELECT SUM(sr.amount) FROM sale_returns sr
                      WHERE sr.sale_id = s.id AND sr.refund_method = 'baki'), 0) AS refunded
          FROM sales s WHERE s.id = ?
        ''',
          [saleId],
        );
        final refunds = await txn.rawQuery(
          '''
          SELECT COALESCE(SUM(amount), 0) AS amount
          FROM sale_returns sr JOIN sales s ON s.id = sr.sale_id
          WHERE s.customer_id = ? AND sr.refund_method = 'baki'
        ''',
          [customerId],
        );
        final collections = await txn.rawQuery(
          '''
          SELECT COALESCE(SUM(amount), 0) AS amount
          FROM baki_payments WHERE customer_id = ?
        ''',
          [customerId],
        );
        final issued = (allocations.first['issued'] as num).toDouble();
        final refunded = (refunds.first['amount'] as num).toDouble();
        final collected = (collections.first['amount'] as num).toDouble();
        final saleBaki = (saleBakiRows.first['issued'] as num).toDouble();
        final saleRefunded = (saleBakiRows.first['refunded'] as num).toDouble();
        if (saleBaki <= saleRefunded ||
            amount >
                (issued - refunded - collected).clamp(0.0, double.infinity) +
                    0.01 ||
            amount > saleBaki - saleRefunded + 0.01) {
          throw ArgumentError(
            'Baki refund cannot exceed the outstanding balance.',
          );
        }
      }
      final returnedAt = createdAt ?? DateTime.now();
      final saleEventRows = await txn.query(
        'sync_outbox',
        columns: ['idempotency_key'],
        where: "event_type = 'sale.created' AND entity_id = ?",
        whereArgs: [saleId],
        orderBy: 'sequence ASC',
        limit: 1,
      );
      final returnId = await txn.insert('sale_returns', {
        'sale_id': saleId,
        'amount': amount,
        'reason': reason.trim(),
        'refund_method': refundMethod,
        'created_at': returnedAt.toIso8601String(),
      });
      for (final entry in quantitiesBySaleItemId.entries) {
        final row = saleById[entry.key]!;
        await txn.insert('sale_return_items', {
          'return_id': returnId,
          'sale_item_id': entry.key,
          'product_name': row['product_name'],
          'variant_name': row['variant_name'],
          'quantity': entry.value,
          'amount': lineAmounts[entry.key],
        });
        await txn.rawUpdate(
          'UPDATE product_variants SET stock = stock + ? WHERE id = ?',
          [entry.value, row['variant_id']],
        );
        await txn.insert('stock_movements', {
          'variant_id': row['variant_id'],
          'quantity': entry.value,
          'cost_price': 0,
          'supplier': 'Sale return #$saleId',
          'created_at': returnedAt.toIso8601String(),
        });
      }
      await _queueSyncEvent(
        txn,
        eventType: 'sale.returned',
        entityId: returnId,
        createdAt: returnedAt,
        payload: {
          'localSaleId': saleId,
          'saleEventId': saleEventRows.firstOrNull?['idempotency_key'],
          'refundAmount': amount,
          'refundMethod': refundMethod,
          'reason': reason.trim(),
          'lines': quantitiesBySaleItemId.entries.map((entry) {
            final row = saleById[entry.key]!;
            return {
              'localSaleItemId': entry.key,
              'productName': row['product_name'],
              'variantName': row['variant_name'],
              'productSyncId': row['product_sync_id'],
              'variantSyncId': row['variant_sync_id'],
              'quantity': entry.value,
              'amount': lineAmounts[entry.key],
            };
          }).toList(),
        },
      );
      return SaleReturn(
        id: returnId,
        saleId: saleId,
        amount: amount,
        reason: reason.trim(),
        refundMethod: refundMethod,
        createdAt: returnedAt,
        items: quantitiesBySaleItemId.entries.map((entry) {
          final row = saleById[entry.key]!;
          return SaleReturnLine(
            saleItemId: entry.key,
            productName: row['product_name'] as String,
            variantName: row['variant_name'] as String,
            quantity: entry.value,
            amount: lineAmounts[entry.key]!,
          );
        }).toList(),
      );
    });
  }

  Future<List<Sale>> getAllSales() async {
    final db = await database;
    final saleRows = await db.query('sales', orderBy: 'created_at DESC');
    final List<Sale> sales = [];
    for (final saleRow in saleRows) {
      final saleId = saleRow['id'] as int;
      final itemRows = await db.query(
        'sale_items',
        where: 'sale_id = ?',
        whereArgs: [saleId],
      );
      final returnedItems = await db.rawQuery(
        '''
        SELECT sri.sale_item_id, SUM(sri.quantity) AS quantity
        FROM sale_return_items sri
        JOIN sale_returns sr ON sr.id = sri.return_id
        WHERE sr.sale_id = ? GROUP BY sri.sale_item_id
      ''',
        [saleId],
      );
      final returnedQuantities = {
        for (final row in returnedItems)
          row['sale_item_id'] as int: (row['quantity'] as num).toDouble(),
      };
      final items = itemRows.map((row) {
        final product = Product(
          id: row['product_id'] as int,
          name: row['product_name'] as String,
        );
        final variant = ProductVariant(
          id: row['variant_id'] as int,
          name: row['variant_name'] as String? ?? '',
          barcode: '',
          price: (row['product_price'] as num).toDouble(),
          stock: 0,
        );
        return CartItem(
          product: product,
          variant: variant,
          quantity: (row['quantity'] as num).toDouble(),
          discountAmount: (row['discount_amount'] as num? ?? 0).toDouble(),
          saleItemId: row['id'] as int,
          returnedQuantity: (returnedQuantities[row['id'] as int] ?? 0)
              .toDouble(),
        );
      }).toList();
      final paymentRows = await db.query(
        'sale_payments',
        where: 'sale_id = ?',
        whereArgs: [saleId],
        orderBy: 'id ASC',
      );
      final returnTotals = await db.rawQuery(
        '''
        SELECT COALESCE(SUM(sr.amount), 0) AS total,
               COALESCE(SUM(CASE WHEN sr.refund_method = 'baki'
                                 THEN sr.amount ELSE 0 END), 0) AS baki
        FROM sale_returns sr WHERE sr.sale_id = ?
      ''',
        [saleId],
      );
      sales.add(
        Sale(
          id: saleId,
          items: items,
          totalAmount: (saleRow['total_amount'] as num).toDouble(),
          createdAt: DateTime.parse(saleRow['created_at'] as String),
          paymentType: saleRow['payment_type'] as String? ?? 'cash',
          customerId: saleRow['customer_id'] as int?,
          customerName: saleRow['customer_name'] as String?,
          discountAmount: (saleRow['discount_amount'] as num? ?? 0).toDouble(),
          discountType: saleRow['discount_type'] as String? ?? 'flat',
          taxAmount: (saleRow['tax_amount'] as num? ?? 0).toDouble(),
          payments: paymentRows.map((row) => SalePayment.fromMap(row)).toList(),
          returnedAmount: (returnTotals.first['total'] as num).toDouble(),
          returnedBakiAmount: (returnTotals.first['baki'] as num).toDouble(),
          staffId: saleRow['staff_id'] as int?,
        ),
      );
    }
    return sales;
  }

  Future<void> clearAllSales() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('sale_return_items');
      await txn.delete('sale_returns');
      await txn.delete('sale_items');
      await txn.delete('sale_payments');
      await txn.delete('sales');
    });
  }

  // ── Customers ─────────────────────────────────────────────────────────────

  Future<int> insertCustomer(Customer customer) async {
    final db = await database;
    final map = customer.toMap()..['sync_id'] = customer.syncId ?? _newUuid();
    return db.insert('customers', map);
  }

  Future<List<Customer>> getAllCustomers() async {
    final db = await database;
    final rows = await db.query('customers', orderBy: 'name ASC');
    return rows.map(Customer.fromMap).toList();
  }

  Future<List<Customer>> searchCustomers(String query) async {
    final db = await database;
    final q = '%${query.toLowerCase()}%';
    final rows = await db.rawQuery(
      'SELECT * FROM customers WHERE LOWER(name) LIKE ? OR phone LIKE ? ORDER BY name ASC',
      [q, q],
    );
    return rows.map(Customer.fromMap).toList();
  }

  // ── Baki Payments ─────────────────────────────────────────────────────────

  Future<int> insertBakiPayment(BakiPayment payment) async {
    final db = await database;
    return db.transaction((txn) async {
      final paymentId = await txn.insert('baki_payments', payment.toMap());
      await _queueSyncEvent(
        txn,
        eventType: 'baki.payment_recorded',
        entityId: paymentId,
        createdAt: payment.paidAt,
        payload: {
          'localPaymentId': paymentId,
          'localCustomerId': payment.customerId,
          'customerSyncId': (await txn.query(
            'customers',
            columns: ['sync_id'],
            where: 'id = ?',
            whereArgs: [payment.customerId],
            limit: 1,
          )).firstOrNull?['sync_id'],
          'amount': payment.amount,
          'note': payment.note,
          'paidAt': payment.paidAt.toIso8601String(),
        },
      );
      return paymentId;
    });
  }

  Future<List<BakiPayment>> getBakiPaymentsForCustomer(int customerId) async {
    final db = await database;
    final rows = await db.query(
      'baki_payments',
      where: 'customer_id = ?',
      whereArgs: [customerId],
      orderBy: 'paid_at DESC',
    );
    return rows.map(BakiPayment.fromMap).toList();
  }

  Future<List<Sale>> getBakiSalesForCustomer(int customerId) async {
    final db = await database;
    final saleRows = await db.query(
      'sales',
      where: 'customer_id = ? AND payment_type = ?',
      whereArgs: [customerId, 'baki'],
      orderBy: 'created_at DESC',
    );
    final List<Sale> sales = [];
    for (final saleRow in saleRows) {
      final saleId = saleRow['id'] as int;
      final itemRows = await db.query(
        'sale_items',
        where: 'sale_id = ?',
        whereArgs: [saleId],
      );
      final returnedItems = await db.rawQuery(
        '''
        SELECT sri.sale_item_id, SUM(sri.quantity) AS quantity
        FROM sale_return_items sri
        JOIN sale_returns sr ON sr.id = sri.return_id
        WHERE sr.sale_id = ? GROUP BY sri.sale_item_id
      ''',
        [saleId],
      );
      final returnedQuantities = {
        for (final row in returnedItems)
          row['sale_item_id'] as int: (row['quantity'] as num).toDouble(),
      };
      final items = itemRows.map((row) {
        final product = Product(
          id: row['product_id'] as int,
          name: row['product_name'] as String,
        );
        final variant = ProductVariant(
          id: row['variant_id'] as int,
          name: row['variant_name'] as String? ?? '',
          barcode: '',
          price: (row['product_price'] as num).toDouble(),
          stock: 0,
        );
        return CartItem(
          product: product,
          variant: variant,
          quantity: (row['quantity'] as num).toDouble(),
          saleItemId: row['id'] as int,
          returnedQuantity: (returnedQuantities[row['id'] as int] ?? 0)
              .toDouble(),
        );
      }).toList();
      final paymentRows = await db.query(
        'sale_payments',
        where: 'sale_id = ?',
        whereArgs: [saleId],
        orderBy: 'id ASC',
      );
      final returnTotals = await db.rawQuery(
        '''
        SELECT COALESCE(SUM(sr.amount), 0) AS total,
               COALESCE(SUM(CASE WHEN sr.refund_method = 'baki'
                                 THEN sr.amount ELSE 0 END), 0) AS baki
        FROM sale_returns sr WHERE sr.sale_id = ?
      ''',
        [saleId],
      );
      sales.add(
        Sale(
          id: saleId,
          items: items,
          totalAmount: (saleRow['total_amount'] as num).toDouble(),
          createdAt: DateTime.parse(saleRow['created_at'] as String),
          paymentType: 'baki',
          customerId: customerId,
          customerName: saleRow['customer_name'] as String?,
          taxAmount: (saleRow['tax_amount'] as num? ?? 0).toDouble(),
          payments: paymentRows.map((row) => SalePayment.fromMap(row)).toList(),
          returnedAmount: (returnTotals.first['total'] as num).toDouble(),
          returnedBakiAmount: (returnTotals.first['baki'] as num).toDouble(),
          staffId: saleRow['staff_id'] as int?,
        ),
      );
    }
    return sales;
  }

  Future<List<CustomerBakiSummary>> getCustomerBakiSummaries() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT
        c.id, c.name, c.phone, c.created_at,
        MAX(0, COALESCE((SELECT SUM(
          CASE WHEN EXISTS (
            SELECT 1 FROM sale_payments sp WHERE sp.sale_id = s.id
          ) THEN COALESCE((
            SELECT SUM(sp.amount) FROM sale_payments sp
            WHERE sp.sale_id = s.id AND sp.method = 'baki'
          ), 0) ELSE s.total_amount END
        ) FROM sales s
          WHERE s.customer_id = c.id AND s.payment_type = 'baki'), 0) -
          COALESCE((SELECT SUM(sr.amount) FROM sale_returns sr
                    JOIN sales rs ON rs.id = sr.sale_id
                    WHERE rs.customer_id = c.id AND sr.refund_method = 'baki'), 0)) AS total_baki,
        COALESCE((SELECT SUM(amount) FROM baki_payments
                  WHERE customer_id = c.id), 0) AS total_paid,
        (SELECT MAX(created_at) FROM sales
         WHERE customer_id = c.id AND payment_type = 'baki') AS last_sale
      FROM customers c
      ORDER BY c.name ASC
    ''');

    final summaries = rows
        .map(
          (r) => CustomerBakiSummary(
            customer: Customer(
              id: r['id'] as int,
              name: r['name'] as String,
              phone: r['phone'] as String? ?? '',
              createdAt: DateTime.parse(r['created_at'] as String),
            ),
            totalBaki: (r['total_baki'] as num).toDouble(),
            totalPaid: (r['total_paid'] as num).toDouble(),
            lastActivity: r['last_sale'] != null
                ? DateTime.tryParse(r['last_sale'] as String)
                : null,
          ),
        )
        .where((s) => s.outstanding > 0)
        .toList();

    summaries.sort((a, b) => b.outstanding.compareTo(a.outstanding));
    return summaries;
  }

  // ── Analytics ─────────────────────────────────────────────────────────────

  Future<double> _profitFrom(Database db, String? from) async {
    final where = from != null ? 'WHERE s.created_at >= ?' : '';
    final args = from != null ? [from] : <dynamic>[];
    final rows = await db.rawQuery('''
      SELECT COALESCE(SUM((si.product_price - COALESCE(si.cost_price_snapshot, 0)) * si.quantity), 0) AS profit
      FROM sale_items si
      JOIN sales s ON si.sale_id = s.id
      $where
    ''', args);
    return (rows.first['profit'] as num).toDouble();
  }

  Future<int> recordDailyClose(DailyCashClose close) async {
    final values = [
      close.expectedCash,
      close.countedCash,
      close.cashReceipts,
      close.bakiIssued,
      close.bakiCollected,
      close.refundsTotal,
      ...close.paymentTotals.values,
    ];
    if (values.any((value) => !value.isFinite)) {
      throw ArgumentError('Close totals must be finite numbers.');
    }
    final db = await database;
    return db.insert('daily_closes', {
      'business_date': DateTime(
        close.businessDate.year,
        close.businessDate.month,
        close.businessDate.day,
      ).toIso8601String(),
      'expected_cash': close.expectedCash,
      'counted_cash': close.countedCash,
      'cash_receipts': close.cashReceipts,
      'baki_issued': close.bakiIssued,
      'baki_collected': close.bakiCollected,
      'refunds_total': close.refundsTotal,
      'payment_totals_json': jsonEncode(close.paymentTotals),
      'note': close.note.trim(),
      'closed_at': close.closedAt.toIso8601String(),
      'staff_id': close.staffId,
    });
  }

  Future<List<DailyCashClose>> getDailyCloses({DateTime? businessDate}) async {
    final db = await database;
    final normalizedDate = businessDate == null
        ? null
        : DateTime(
            businessDate.year,
            businessDate.month,
            businessDate.day,
          ).toIso8601String();
    final rows = await db.query(
      'daily_closes',
      where: normalizedDate == null ? null : 'business_date = ?',
      whereArgs: normalizedDate == null ? null : [normalizedDate],
      orderBy: 'closed_at DESC',
    );
    return rows.map((row) {
      final rawTotals = jsonDecode(row['payment_totals_json'] as String);
      final totals = rawTotals is Map<String, dynamic>
          ? rawTotals.map(
              (key, value) => MapEntry(key, (value as num).toDouble()),
            )
          : <String, double>{};
      return DailyCashClose(
        id: row['id'] as int,
        businessDate: DateTime.parse(row['business_date'] as String),
        expectedCash: (row['expected_cash'] as num).toDouble(),
        countedCash: (row['counted_cash'] as num).toDouble(),
        cashReceipts: (row['cash_receipts'] as num).toDouble(),
        bakiIssued: (row['baki_issued'] as num).toDouble(),
        bakiCollected: (row['baki_collected'] as num).toDouble(),
        refundsTotal: (row['refunds_total'] as num).toDouble(),
        paymentTotals: totals,
        note: row['note'] as String? ?? '',
        closedAt: DateTime.parse(row['closed_at'] as String),
        staffId: row['staff_id'] as int?,
      );
    }).toList();
  }

  Future<SalesReportData> getSalesReportData(ReportRange range) async {
    final db = await database;
    final start = range.start.toIso8601String();
    final end = range.endExclusive.toIso8601String();
    final saleRows = await db.query(
      'sales',
      where: 'created_at >= ? AND created_at < ?',
      whereArgs: [start, end],
      orderBy: 'created_at ASC',
    );

    var grossSales = 0.0;
    var discounts = 0.0;
    var netSales = 0.0;
    var taxCollected = 0.0;
    var totalReceivable = 0.0;
    var returns = 0.0;
    var estimatedProfit = 0.0;
    var linesWithoutCost = 0;
    var bakiIssued = 0.0;
    final paymentTotals = <String, double>{};
    final products = <String, ({double quantity, double netSales})>{};

    for (final sale in saleRows) {
      final saleId = sale['id'] as int;
      final saleTotal = (sale['total_amount'] as num).toDouble();
      final saleTax = (sale['tax_amount'] as num? ?? 0).toDouble();
      final paymentType = sale['payment_type'] as String? ?? 'cash';
      final lineRows = await db.rawQuery(
        '''
        SELECT si.product_name, si.product_price, si.quantity,
               COALESCE(si.discount_amount, 0) AS item_discount,
               si.cost_price_snapshot
        FROM sale_items si
        WHERE si.sale_id = ?
      ''',
        [saleId],
      );

      var saleGross = 0.0;
      var saleItemDiscount = 0.0;
      for (final line in lineRows) {
        final quantity = (line['quantity'] as num).toDouble();
        saleGross += (line['product_price'] as num).toDouble() * quantity;
        saleItemDiscount +=
            (line['item_discount'] as num).toDouble() * quantity;
      }
      final afterItemDiscount = (saleGross - saleItemDiscount).clamp(
        0.0,
        double.infinity,
      );
      final rawOrderDiscount = (sale['discount_amount'] as num? ?? 0)
          .toDouble();
      final orderDiscount = sale['discount_type'] == 'percent'
          ? afterItemDiscount * rawOrderDiscount.clamp(0, 100) / 100
          : rawOrderDiscount.clamp(0, afterItemDiscount);
      final saleDiscount = saleItemDiscount + orderDiscount;
      final saleNet = (afterItemDiscount - orderDiscount).clamp(
        0.0,
        double.infinity,
      );

      grossSales += saleGross;
      discounts += saleDiscount;
      netSales += saleNet;
      taxCollected += saleTax;
      totalReceivable += saleTotal;
      final paymentRows = await db.query(
        'sale_payments',
        where: 'sale_id = ?',
        whereArgs: [saleId],
      );
      if (paymentRows.isEmpty) {
        paymentTotals[paymentType] =
            (paymentTotals[paymentType] ?? 0) + saleTotal;
        if (paymentType == 'baki') bakiIssued += saleTotal;
      } else {
        for (final payment in paymentRows) {
          final method = payment['method'] as String;
          final amount = (payment['amount'] as num).toDouble();
          paymentTotals[method] = (paymentTotals[method] ?? 0) + amount;
          if (method == 'baki') bakiIssued += amount;
        }
      }

      for (final line in lineRows) {
        final quantity = (line['quantity'] as num).toDouble();
        final price = (line['product_price'] as num).toDouble();
        final itemDiscount = (line['item_discount'] as num).toDouble();
        final lineNetBeforeOrder =
            (price - itemDiscount).clamp(0.0, double.infinity) * quantity;
        final allocatedOrderDiscount = afterItemDiscount > 0
            ? orderDiscount * lineNetBeforeOrder / afterItemDiscount
            : 0.0;
        final lineNet = (lineNetBeforeOrder - allocatedOrderDiscount).clamp(
          0.0,
          double.infinity,
        );
        final cost = (line['cost_price_snapshot'] as num?)?.toDouble();
        if (cost == null || cost <= 0) {
          linesWithoutCost++;
        } else {
          estimatedProfit += lineNet - cost * quantity;
        }
        final name = line['product_name'] as String;
        final previous = products[name] ?? (quantity: 0.0, netSales: 0.0);
        products[name] = (
          quantity: previous.quantity + quantity,
          netSales: previous.netSales + lineNet,
        );
      }
    }

    final returnRows = await db.query(
      'sale_returns',
      where: 'created_at >= ? AND created_at < ?',
      whereArgs: [start, end],
    );
    for (final returned in returnRows) {
      final amount = (returned['amount'] as num).toDouble();
      final method = returned['refund_method'] as String;
      returns += amount;
      totalReceivable -= amount;
      paymentTotals[method] = (paymentTotals[method] ?? 0) - amount;
      if (method == 'baki') bakiIssued -= amount;
      final originalSale = await db.query(
        'sales',
        columns: ['tax_amount', 'total_amount'],
        where: 'id = ?',
        whereArgs: [returned['sale_id']],
        limit: 1,
      );
      var taxPart = 0.0;
      if (originalSale.isNotEmpty) {
        final originalTotal = (originalSale.single['total_amount'] as num)
            .toDouble();
        final originalTax = (originalSale.single['tax_amount'] as num? ?? 0)
            .toDouble();
        if (originalTotal > 0) {
          taxPart = originalTax * amount / originalTotal;
          taxCollected -= taxPart;
          netSales -= amount - taxPart;
        } else {
          netSales -= amount;
        }
      }
      final returnedLines = await db.rawQuery(
        '''
        SELECT sri.product_name, sri.quantity, sri.amount, si.cost_price_snapshot
        FROM sale_return_items sri
        JOIN sale_items si ON si.id = sri.sale_item_id
        WHERE sri.return_id = ?
      ''',
        [returned['id']],
      );
      for (final line in returnedLines) {
        final cost = (line['cost_price_snapshot'] as num?)?.toDouble();
        final quantity = (line['quantity'] as num).toDouble();
        final lineAmount = (line['amount'] as num).toDouble();
        final lineTax = amount > 0 ? taxPart * lineAmount / amount : 0.0;
        final netRefund = lineAmount - lineTax;
        estimatedProfit -= netRefund;
        if (cost != null && cost > 0) estimatedProfit += cost * quantity;
        final name = line['product_name'] as String;
        final previous = products[name] ?? (quantity: 0.0, netSales: 0.0);
        products[name] = (
          quantity: previous.quantity - quantity,
          netSales: previous.netSales - netRefund,
        );
      }
    }

    final paymentRows = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(amount), 0) AS amount
      FROM baki_payments
      WHERE paid_at >= ? AND paid_at < ?
    ''',
      [start, end],
    );
    final purchaseRows = await db.query(
      'purchases',
      where: 'created_at >= ? AND created_at < ?',
      whereArgs: [start, end],
    );
    var purchaseCosts = 0.0;
    final supplierPurchaseTotals = <String, double>{};
    for (final purchase in purchaseRows) {
      final amount = (purchase['total_amount'] as num).toDouble();
      final supplier = purchase['supplier_name'] as String;
      purchaseCosts += amount;
      supplierPurchaseTotals[supplier] =
          (supplierPurchaseTotals[supplier] ?? 0) + amount;
    }
    final lowStock =
        (await getAllProducts())
            .where((product) => product.totalStock <= product.lowStockAlert)
            .toList()
          ..sort((a, b) => a.totalStock.compareTo(b.totalStock));
    final topProducts =
        products.entries
            .map(
              (entry) => ReportProductSummary(
                name: entry.key,
                quantity: entry.value.quantity,
                netSales: entry.value.netSales,
              ),
            )
            .toList()
          ..sort((a, b) => b.netSales.compareTo(a.netSales));

    return SalesReportData(
      grossSales: grossSales,
      discounts: discounts,
      netSales: netSales,
      taxCollected: taxCollected,
      totalReceivable: totalReceivable,
      returns: returns,
      purchaseCosts: purchaseCosts,
      supplierPurchaseTotals: supplierPurchaseTotals,
      saleCount: saleRows.length,
      averageSale: saleRows.isEmpty ? 0 : totalReceivable / saleRows.length,
      estimatedProfit: estimatedProfit,
      linesWithoutCost: linesWithoutCost,
      bakiIssued: bakiIssued,
      bakiCollected: (paymentRows.first['amount'] as num).toDouble(),
      paymentTotals: paymentTotals,
      topProducts: topProducts,
      lowStockProducts: lowStock,
    );
  }

  Future<DashboardData> getDashboardData() async {
    final db = await database;
    final now = DateTime.now();

    Future<({double revenue, int count})> statsFrom(String? from) async {
      final where = from != null ? 'WHERE created_at >= ?' : '';
      final args = from != null ? [from] : <dynamic>[];
      final rows = await db.rawQuery(
        'SELECT COALESCE(SUM(total_amount),0) AS rev, COUNT(*) AS cnt FROM sales $where',
        args,
      );
      return (
        revenue: (rows.first['rev'] as num).toDouble(),
        count: rows.first['cnt'] as int,
      );
    }

    final todayStr = DateTime(now.year, now.month, now.day).toIso8601String();
    final weekDay = now.subtract(Duration(days: now.weekday - 1));
    final weekStr = DateTime(
      weekDay.year,
      weekDay.month,
      weekDay.day,
    ).toIso8601String();
    final monthStr = DateTime(now.year, now.month, 1).toIso8601String();

    final today = await statsFrom(todayStr);
    final week = await statsFrom(weekStr);
    final month = await statsFrom(monthStr);
    final allTime = await statsFrom(null);

    final sellerRows = await db.rawQuery('''
      SELECT product_name, variant_name,
             SUM(quantity) AS qty,
             SUM(quantity * product_price) AS rev
      FROM sale_items
      GROUP BY product_name, variant_name
      ORDER BY qty DESC
      LIMIT 5
    ''');
    final topSellers = sellerRows
        .map(
          (r) => BestSellerItem(
            productName: r['product_name'] as String,
            variantName: r['variant_name'] as String? ?? '',
            quantitySold: (r['qty'] as num).toDouble(),
            revenue: (r['rev'] as num).toDouble(),
          ),
        )
        .toList();

    final last7 = <DailyRevenue>[];
    for (int i = 6; i >= 0; i--) {
      final day = now.subtract(Duration(days: i));
      final start = DateTime(day.year, day.month, day.day).toIso8601String();
      final end = DateTime(
        day.year,
        day.month,
        day.day,
        23,
        59,
        59,
      ).toIso8601String();
      final rows = await db.rawQuery(
        'SELECT COALESCE(SUM(total_amount),0) AS rev, COUNT(*) AS cnt FROM sales WHERE created_at >= ? AND created_at <= ?',
        [start, end],
      );
      last7.add(
        DailyRevenue(
          date: day,
          amount: (rows.first['rev'] as num).toDouble(),
          salesCount: rows.first['cnt'] as int,
        ),
      );
    }

    final allProducts = await getAllProducts();
    final lowStock =
        allProducts.where((p) => p.totalStock <= p.lowStockAlert).toList()
          ..sort((a, b) => a.totalStock.compareTo(b.totalStock));

    final productCount =
        (await db.rawQuery('SELECT COUNT(*) AS c FROM products')).first['c']
            as int;
    final variantCount =
        (await db.rawQuery(
              'SELECT COUNT(*) AS c FROM product_variants',
            )).first['c']
            as int;

    final todayProfit = await _profitFrom(db, todayStr);
    final margin = today.revenue > 0 ? todayProfit / today.revenue * 100 : 0.0;

    return DashboardData(
      revenueToday: today.revenue,
      salesToday: today.count,
      revenueThisWeek: week.revenue,
      salesThisWeek: week.count,
      revenueThisMonth: month.revenue,
      salesThisMonth: month.count,
      revenueAllTime: allTime.revenue,
      salesAllTime: allTime.count,
      avgSaleValue: allTime.count > 0 ? allTime.revenue / allTime.count : 0,
      profitToday: todayProfit,
      marginPercent: margin,
      totalProducts: productCount,
      totalVariants: variantCount,
      topSellers: topSellers,
      lowStockProducts: lowStock,
      last7Days: last7,
    );
  }
}

// ── View model ────────────────────────────────────────────────────────────────

class CustomerBakiSummary {
  final Customer customer;
  final double totalBaki;
  final double totalPaid;
  final DateTime? lastActivity;

  const CustomerBakiSummary({
    required this.customer,
    required this.totalBaki,
    required this.totalPaid,
    this.lastActivity,
  });

  double get outstanding => totalBaki - totalPaid;
}
