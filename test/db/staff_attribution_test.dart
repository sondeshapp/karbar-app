import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:m_pos/db/database_helper.dart';
import 'package:m_pos/models/cart_item.dart';
import 'package:m_pos/models/daily_cash_close.dart';
import 'package:m_pos/models/product.dart';
import 'package:m_pos/models/product_variant.dart';
import 'package:m_pos/models/sale.dart';
import 'package:m_pos/providers/staff_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    DatabaseHelper.setTestPath(inMemoryDatabasePath);
    await DatabaseHelper.resetForTesting();
  });

  tearDown(() async => DatabaseHelper.resetForTesting());

  test('new sales and daily closes retain the staff account ID', () async {
    final db = DatabaseHelper();
    final staffId = await StaffAccess(
      db: db,
    ).create(name: 'Cashier', role: 'owner', pin: '1234');
    await db.insertProduct(
      Product(
        name: 'Tea',
        variants: [
          const ProductVariant(name: 'Pack', barcode: '', price: 10, stock: 3),
        ],
      ),
    );
    final product = (await db.getAllProducts()).single;
    await db.insertSale(
      Sale(
        items: [
          CartItem(
            product: product,
            variant: product.variants.single,
            quantity: 1,
          ),
        ],
        totalAmount: 10,
        createdAt: DateTime(2026, 10, 1),
        staffId: staffId,
      ),
    );
    await db.recordDailyClose(
      DailyCashClose(
        businessDate: DateTime(2026, 10, 1),
        expectedCash: 10,
        countedCash: 10,
        cashReceipts: 10,
        bakiIssued: 0,
        bakiCollected: 0,
        refundsTotal: 0,
        paymentTotals: const {'cash': 10},
        note: '',
        closedAt: DateTime(2026, 10, 1, 20),
        staffId: staffId,
      ),
    );

    expect((await db.getAllSales()).single.staffId, staffId);
    expect((await db.getDailyCloses()).single.staffId, staffId);
  });

  test(
    'version 13 databases upgrade without losing sales or close records',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'karbar-migration',
      );
      addTearDown(() => directory.delete(recursive: true));
      final legacyPath = '${directory.path}/legacy.db';
      DatabaseHelper.setTestPath(legacyPath);
      final legacy = await databaseFactory.openDatabase(
        legacyPath,
        options: OpenDatabaseOptions(
          version: 13,
          onCreate: (db, _) async {
            await db.execute('''
            CREATE TABLE products (
              id INTEGER PRIMARY KEY, name TEXT NOT NULL,
              quantity_precision INTEGER NOT NULL DEFAULT 0
            )
          ''');
            await db.execute('''
            CREATE TABLE product_variants (
              id INTEGER PRIMARY KEY, product_id INTEGER NOT NULL
            )
          ''');
            await db.execute('''
            CREATE TABLE customers (
              id INTEGER PRIMARY KEY, name TEXT NOT NULL
            )
          ''');
            await db.insert('products', {'id': 3, 'name': 'Legacy product'});
            await db.insert('product_variants', {'id': 4, 'product_id': 3});
            await db.insert('customers', {'id': 5, 'name': 'Legacy customer'});
            await db.execute('''
            CREATE TABLE sales (
              id INTEGER PRIMARY KEY, total_amount REAL NOT NULL,
              created_at TEXT NOT NULL, payment_type TEXT NOT NULL,
              customer_id INTEGER, customer_name TEXT,
              discount_amount REAL DEFAULT 0, discount_type TEXT DEFAULT 'flat',
              tax_amount REAL NOT NULL DEFAULT 0
            )
          ''');
            await db.execute('''
            CREATE TABLE daily_closes (
              id INTEGER PRIMARY KEY, business_date TEXT NOT NULL,
              expected_cash REAL NOT NULL, counted_cash REAL NOT NULL,
              cash_receipts REAL NOT NULL, baki_issued REAL NOT NULL,
              baki_collected REAL NOT NULL, refunds_total REAL NOT NULL,
              payment_totals_json TEXT NOT NULL, note TEXT NOT NULL,
              closed_at TEXT NOT NULL
            )
          ''');
            await db.insert('sales', {
              'id': 1,
              'total_amount': 12,
              'created_at': '2026-10-01T10:00:00',
              'payment_type': 'cash',
            });
            await db.insert('daily_closes', {
              'id': 1,
              'business_date': '2026-10-01T00:00:00',
              'expected_cash': 12,
              'counted_cash': 12,
              'cash_receipts': 12,
              'baki_issued': 0,
              'baki_collected': 0,
              'refunds_total': 0,
              'payment_totals_json': '{"cash":12}',
              'note': '',
              'closed_at': '2026-10-01T20:00:00',
            });
          },
        ),
      );
      await legacy.close();

      final migrated = await DatabaseHelper().database;
      final sales = await migrated.query('sales');
      final closes = await migrated.query('daily_closes');
      final staffTable = await migrated.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'staff_users'",
      );
      final product = (await migrated.query('products')).single;
      final variant = (await migrated.query('product_variants')).single;
      final customer = (await migrated.query('customers')).single;

      expect(sales.single['total_amount'], 12);
      expect(sales.single['staff_id'], isNull);
      expect(closes.single['counted_cash'], 12);
      expect(closes.single['staff_id'], isNull);
      expect(staffTable, hasLength(1));
      expect(product['sync_id'], isNotEmpty);
      expect(variant['sync_id'], isNotEmpty);
      expect(customer['sync_id'], isNotEmpty);
    },
  );
}
