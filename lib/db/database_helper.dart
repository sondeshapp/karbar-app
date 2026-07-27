import 'dart:io';
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

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _db;
  static String? _testPath;

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
      version: 3,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async =>
      _createTables(db);

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    await db.execute('DROP TABLE IF EXISTS baki_payments');
    await db.execute('DROP TABLE IF EXISTS customers');
    await db.execute('DROP TABLE IF EXISTS sale_items');
    await db.execute('DROP TABLE IF EXISTS sales');
    await db.execute('DROP TABLE IF EXISTS product_variants');
    await db.execute('DROP TABLE IF EXISTS products');
    await _createTables(db);
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
        stock INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE customers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT DEFAULT '',
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
        quantity INTEGER NOT NULL,
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
        FOREIGN KEY (customer_id) REFERENCES customers(id)
      )
    ''');
  }

  // ── Products ──────────────────────────────────────────────────────────────

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
      Database db, int productId) async {
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
      final productId = await txn.insert('products', map);
      for (final v in product.variants) {
        final vMap = v.toMap()
          ..remove('id')
          ..['product_id'] = productId;
        await txn.insert('product_variants', vMap);
      }
      return productId;
    });
  }

  Future<void> updateProduct(Product product) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.update('products', product.toMap(),
          where: 'id = ?', whereArgs: [product.id]);

      final existingIds = product.variants
          .where((v) => v.id != null)
          .map((v) => v.id!)
          .toList();

      if (existingIds.isEmpty) {
        await txn.delete('product_variants',
            where: 'product_id = ?', whereArgs: [product.id]);
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
          await txn.update('product_variants', v.toMap(),
              where: 'id = ?', whereArgs: [v.id]);
        } else {
          final vMap = v.toMap()
            ..remove('id')
            ..['product_id'] = product.id;
          await txn.insert('product_variants', vMap);
        }
      }
    });
  }

  Future<void> deleteProduct(int id) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('product_variants',
          where: 'product_id = ?', whereArgs: [id]);
      await txn.delete('products', where: 'id = ?', whereArgs: [id]);
    });
  }

  // ── Sales ─────────────────────────────────────────────────────────────────

  Future<int> insertSale(Sale sale) async {
    final db = await database;
    return db.transaction((txn) async {
      final saleId = await txn.insert('sales', {
        'total_amount': sale.totalAmount,
        'created_at': sale.createdAt.toIso8601String(),
        'payment_type': sale.paymentType,
        'customer_id': sale.customerId,
        'customer_name': sale.customerName,
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
        });
        if (item.variant.id != null) {
          await txn.rawUpdate(
            'UPDATE product_variants SET stock = MAX(0, stock - ?) WHERE id = ?',
            [item.quantity, item.variant.id],
          );
        }
      }
      return saleId;
    });
  }

  Future<List<Sale>> getAllSales() async {
    final db = await database;
    final saleRows = await db.query('sales', orderBy: 'created_at DESC');
    final List<Sale> sales = [];
    for (final saleRow in saleRows) {
      final saleId = saleRow['id'] as int;
      final itemRows = await db.query('sale_items',
          where: 'sale_id = ?', whereArgs: [saleId]);
      final items = itemRows.map((row) {
        final product = Product(
            id: row['product_id'] as int,
            name: row['product_name'] as String);
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
            quantity: row['quantity'] as int);
      }).toList();
      sales.add(Sale(
        id: saleId,
        items: items,
        totalAmount: (saleRow['total_amount'] as num).toDouble(),
        createdAt: DateTime.parse(saleRow['created_at'] as String),
        paymentType: saleRow['payment_type'] as String? ?? 'cash',
        customerId: saleRow['customer_id'] as int?,
        customerName: saleRow['customer_name'] as String?,
      ));
    }
    return sales;
  }

  Future<void> clearAllSales() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('sale_items');
      await txn.delete('sales');
    });
  }

  // ── Customers ─────────────────────────────────────────────────────────────

  Future<int> insertCustomer(Customer customer) async {
    final db = await database;
    return db.insert('customers', customer.toMap());
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
    return db.insert('baki_payments', payment.toMap());
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
      final itemRows = await db.query('sale_items',
          where: 'sale_id = ?', whereArgs: [saleId]);
      final items = itemRows.map((row) {
        final product = Product(
            id: row['product_id'] as int,
            name: row['product_name'] as String);
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
            quantity: row['quantity'] as int);
      }).toList();
      sales.add(Sale(
        id: saleId,
        items: items,
        totalAmount: (saleRow['total_amount'] as num).toDouble(),
        createdAt: DateTime.parse(saleRow['created_at'] as String),
        paymentType: 'baki',
        customerId: customerId,
        customerName: saleRow['customer_name'] as String?,
      ));
    }
    return sales;
  }

  Future<List<CustomerBakiSummary>> getCustomerBakiSummaries() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT
        c.id, c.name, c.phone, c.created_at,
        COALESCE((SELECT SUM(total_amount) FROM sales
                  WHERE customer_id = c.id AND payment_type = 'baki'), 0) AS total_baki,
        COALESCE((SELECT SUM(amount) FROM baki_payments
                  WHERE customer_id = c.id), 0) AS total_paid,
        (SELECT MAX(created_at) FROM sales
         WHERE customer_id = c.id AND payment_type = 'baki') AS last_sale
      FROM customers c
      ORDER BY c.name ASC
    ''');

    final summaries = rows
        .map((r) => CustomerBakiSummary(
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
            ))
        .where((s) => s.outstanding > 0)
        .toList();

    summaries.sort((a, b) => b.outstanding.compareTo(a.outstanding));
    return summaries;
  }

  // ── Analytics ─────────────────────────────────────────────────────────────

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

    final todayStr =
        DateTime(now.year, now.month, now.day).toIso8601String();
    final weekDay = now.subtract(Duration(days: now.weekday - 1));
    final weekStr =
        DateTime(weekDay.year, weekDay.month, weekDay.day).toIso8601String();
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
        .map((r) => BestSellerItem(
              productName: r['product_name'] as String,
              variantName: r['variant_name'] as String? ?? '',
              quantitySold: r['qty'] as int,
              revenue: (r['rev'] as num).toDouble(),
            ))
        .toList();

    final last7 = <DailyRevenue>[];
    for (int i = 6; i >= 0; i--) {
      final day = now.subtract(Duration(days: i));
      final start =
          DateTime(day.year, day.month, day.day).toIso8601String();
      final end = DateTime(day.year, day.month, day.day, 23, 59, 59)
          .toIso8601String();
      final rows = await db.rawQuery(
        'SELECT COALESCE(SUM(total_amount),0) AS rev, COUNT(*) AS cnt FROM sales WHERE created_at >= ? AND created_at <= ?',
        [start, end],
      );
      last7.add(DailyRevenue(
        date: day,
        amount: (rows.first['rev'] as num).toDouble(),
        salesCount: rows.first['cnt'] as int,
      ));
    }

    final allProducts = await getAllProducts();
    final lowStock = allProducts
        .where((p) => p.totalStock <= p.lowStockAlert)
        .toList()
      ..sort((a, b) => a.totalStock.compareTo(b.totalStock));

    final productCount =
        (await db.rawQuery('SELECT COUNT(*) AS c FROM products'))
            .first['c'] as int;
    final variantCount =
        (await db.rawQuery('SELECT COUNT(*) AS c FROM product_variants'))
            .first['c'] as int;

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
