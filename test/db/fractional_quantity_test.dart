import 'package:flutter_test/flutter_test.dart';
import 'package:m_pos/db/database_helper.dart';
import 'package:m_pos/models/cart_item.dart';
import 'package:m_pos/models/product.dart';
import 'package:m_pos/models/product_variant.dart';
import 'package:m_pos/models/sale.dart';
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

  test('fractional stock, sale, return, and report retain precision', () async {
    final db = DatabaseHelper();
    final productId = await db.insertProduct(
      Product(
        name: 'Rice',
        unit: 'kg',
        quantityPrecision: 3,
        costPrice: 2,
        variants: [
          const ProductVariant(
            name: 'Loose',
            barcode: '',
            price: 4,
            stock: 2.75,
          ),
        ],
      ),
    );
    var product = (await db.getAllProducts()).single;
    expect(product.id, productId);
    expect(product.totalStock, 2.75);
    expect(product.quantityPrecision, 3);
    final variant = product.variants.single;

    await db.stockIn(variant.id!, 0.25, costPrice: 2, supplier: 'Mill');
    product = (await db.getAllProducts()).single;
    expect(product.totalStock, 3.0);

    final saleId = await db.insertSale(
      Sale(
        items: [
          CartItem(
            product: product,
            variant: product.variants.single,
            quantity: 0.75,
          ),
        ],
        totalAmount: 3,
        createdAt: DateTime(2026, 9, 1, 10),
      ),
    );
    final sale = (await db.getAllSales()).single;
    expect(sale.id, saleId);
    expect(sale.items.single.quantity, 0.75);
    expect((await db.getAllProducts()).single.totalStock, 2.25);

    await db.createSaleReturn(
      saleId: saleId,
      quantitiesBySaleItemId: {sale.items.single.saleItemId!: 0.25},
      reason: 'Return part of bag',
      refundMethod: 'cash',
      createdAt: DateTime(2026, 9, 2, 10),
    );
    expect((await db.getAllProducts()).single.totalStock, 2.5);
    final report = await db.getSalesReportData(
      ReportRange(from: DateTime(2026, 9, 1), through: DateTime(2026, 9, 2)),
    );
    expect(report.netSales, 2);
    expect(report.returns, 1);
    expect(report.estimatedProfit, 1);
    expect(report.topProducts.single.quantity, 0.5);
    expect(report.topProducts.single.netSales, 2);
  });

  test('whole unit products reject fractional sale quantities', () async {
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

    await expectLater(
      db.insertSale(
        Sale(
          items: [
            CartItem(
              product: product,
              variant: product.variants.single,
              quantity: 0.5,
            ),
          ],
          totalAmount: 5,
          createdAt: DateTime(2026, 9, 1),
        ),
      ),
      throwsArgumentError,
    );
    expect((await db.getAllProducts()).single.totalStock, 2);
  });
}
