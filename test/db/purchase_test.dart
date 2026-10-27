import 'package:flutter_test/flutter_test.dart';
import 'package:m_pos/db/database_helper.dart';
import 'package:m_pos/models/product.dart';
import 'package:m_pos/models/product_variant.dart';
import 'package:m_pos/models/purchase.dart';
import 'package:m_pos/models/supplier.dart';
import 'package:m_pos/models/sales_report.dart';
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

  test('purchase records all lines and receives stock exactly once', () async {
    final db = DatabaseHelper();
    final firstId = await db.insertProduct(
      Product(
        name: 'Tea',
        variants: [
          const ProductVariant(name: 'Box', barcode: '', price: 80, stock: 5),
        ],
      ),
    );
    final secondId = await db.insertProduct(
      Product(
        name: 'Sugar',
        variants: [
          const ProductVariant(name: 'Bag', barcode: '', price: 60, stock: 3),
        ],
      ),
    );
    final products = await db.getAllProducts();
    final tea = products.singleWhere((product) => product.id == firstId);
    final sugar = products.singleWhere((product) => product.id == secondId);
    final supplierId = await db.saveSupplier(
      const Supplier(name: 'City Wholesale', phone: '0123'),
    );
    final supplier = (await db.getSuppliers()).single;
    expect(supplier.id, supplierId);

    await db.recordPurchase(
      supplier: supplier,
      items: [
        PurchaseLine(
          variantId: tea.variants.single.id!,
          productName: tea.name,
          variantName: 'Box',
          quantity: 4,
          costPrice: 50,
        ),
        PurchaseLine(
          variantId: sugar.variants.single.id!,
          productName: sugar.name,
          variantName: 'Bag',
          quantity: 2,
          costPrice: 35,
        ),
      ],
      note: 'Weekly restock',
      createdAt: DateTime(2026, 8, 1),
    );

    final queued = await db.getPendingSyncEvents();
    expect(queued, hasLength(1));
    expect(queued.single.eventType, 'purchase.recorded');
    expect(queued.single.entityId, greaterThan(0));
    expect(queued.single.payloadJson, contains('supplierSyncId'));
    expect(queued.single.payloadJson, contains('productSyncId'));

    final updated = await db.getAllProducts();
    expect(updated.singleWhere((p) => p.id == firstId).totalStock, 9);
    expect(updated.singleWhere((p) => p.id == secondId).totalStock, 5);
    final purchase = (await db.getPurchases()).single;
    expect(purchase.supplierName, 'City Wholesale');
    expect(purchase.totalAmount, 270);
    expect(purchase.items, hasLength(2));
    expect(purchase.note, 'Weekly restock');
    final report = await db.getSalesReportData(
      ReportRange(from: DateTime(2026, 8, 1), through: DateTime(2026, 8, 1)),
    );
    expect(report.purchaseCosts, 270);
    expect(report.supplierPurchaseTotals['City Wholesale'], 270);
    final movements = await (await db.database).query(
      'stock_movements',
      where: 'supplier = ?',
      whereArgs: ['City Wholesale'],
    );
    expect(movements, hasLength(2));
    expect(
      movements.fold<double>(
        0,
        (sum, row) => sum + (row['quantity'] as num).toDouble(),
      ),
      6,
    );
  });

  test(
    'invalid purchase rolls back its header and earlier stock lines',
    () async {
      final db = DatabaseHelper();
      await db.insertProduct(
        Product(
          name: 'Soap',
          variants: [
            const ProductVariant(name: 'Bar', barcode: '', price: 10, stock: 2),
          ],
        ),
      );
      final product = (await db.getAllProducts()).single;
      final supplierId = await db.saveSupplier(
        const Supplier(name: 'Supplier'),
      );
      final supplier = Supplier(id: supplierId, name: 'Supplier');

      await expectLater(
        db.recordPurchase(
          supplier: supplier,
          items: [
            PurchaseLine(
              variantId: product.variants.single.id!,
              productName: 'Soap',
              variantName: 'Bar',
              quantity: 5,
              costPrice: 4,
            ),
            const PurchaseLine(
              variantId: 999999,
              productName: 'Missing',
              variantName: 'Missing',
              quantity: 1,
              costPrice: 1,
            ),
          ],
        ),
        throwsArgumentError,
      );
      expect(await db.getPendingSyncEventCount(), 0);

      expect((await db.getAllProducts()).single.totalStock, 2);
      expect(await db.getPurchases(), isEmpty);
      expect(await (await db.database).query('stock_movements'), isEmpty);
    },
  );
}
