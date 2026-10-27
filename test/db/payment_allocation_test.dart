import 'package:flutter_test/flutter_test.dart';
import 'package:m_pos/db/database_helper.dart';
import 'package:m_pos/models/baki_payment.dart';
import 'package:m_pos/models/cart_item.dart';
import 'package:m_pos/models/customer.dart';
import 'package:m_pos/models/product.dart';
import 'package:m_pos/models/product_variant.dart';
import 'package:m_pos/models/sale.dart';
import 'package:m_pos/models/sale_payment.dart';
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

  test(
    'split tender persists allocations and only baki amount becomes debt',
    () async {
      final db = DatabaseHelper();
      final product = Product(
        name: 'Milk',
        costPrice: 50,
        variants: [
          const ProductVariant(
            name: 'Bottle',
            barcode: '',
            price: 100,
            stock: 10,
          ),
        ],
      );
      await db.insertProduct(product);
      final loadedProduct = (await db.getAllProducts()).single;
      final variant = loadedProduct.variants.single;
      final customerId = await db.insertCustomer(
        Customer(name: 'Sumi', createdAt: DateTime(2026, 7, 1)),
      );

      await db.insertSale(
        Sale(
          items: [
            CartItem(product: loadedProduct, variant: variant, quantity: 1),
          ],
          totalAmount: 100,
          createdAt: DateTime(2026, 7, 1, 12),
          customerId: customerId,
          customerName: 'Sumi',
          payments: const [
            SalePayment(method: 'cash', amount: 30),
            SalePayment(method: 'bkash', amount: 20),
            SalePayment(method: 'baki', amount: 50),
          ],
        ),
      );
      await db.insertBakiPayment(
        BakiPayment(
          customerId: customerId,
          amount: 10,
          note: 'Received later',
          paidAt: DateTime(2026, 7, 2),
        ),
      );

      final sale = (await db.getAllSales()).single;
      expect(sale.paymentType, 'baki');
      expect(sale.payments.map((payment) => payment.method), [
        'cash',
        'bkash',
        'baki',
      ]);
      expect(sale.bakiAmount, 50);
      final summary = (await db.getCustomerBakiSummaries()).single;
      expect(summary.totalBaki, 50);
      expect(summary.totalPaid, 10);
      expect(summary.outstanding, 40);
      expect(
        (await db.getBakiSalesForCustomer(customerId)).single.bakiAmount,
        50,
      );

      final report = await db.getSalesReportData(
        ReportRange(from: DateTime(2026, 7, 1), through: DateTime(2026, 7, 2)),
      );
      expect(report.paymentTotals['cash'], 30);
      expect(report.paymentTotals['bkash'], 20);
      expect(report.paymentTotals['baki'], 50);
      expect(report.bakiIssued, 50);
      expect(report.bakiCollected, 10);
    },
  );

  test('rejects incomplete allocations and baki without a customer', () async {
    final db = DatabaseHelper();
    final product = Product(
      name: 'Soap',
      variants: [
        const ProductVariant(
          name: 'Default',
          barcode: '',
          price: 100,
          stock: 4,
        ),
      ],
    );
    await db.insertProduct(product);
    final loadedProduct = (await db.getAllProducts()).single;
    final item = CartItem(
      product: loadedProduct,
      variant: loadedProduct.variants.single,
      quantity: 1,
    );

    await expectLater(
      db.insertSale(
        Sale(
          items: [item],
          totalAmount: 100,
          createdAt: DateTime(2026, 7, 1),
          payments: const [SalePayment(method: 'cash', amount: 40)],
        ),
      ),
      throwsArgumentError,
    );
    await expectLater(
      db.insertSale(
        Sale(
          items: [item],
          totalAmount: 100,
          createdAt: DateTime(2026, 7, 1),
          payments: const [SalePayment(method: 'baki', amount: 100)],
        ),
      ),
      throwsArgumentError,
    );
    expect(await db.getAllSales(), isEmpty);
  });

  test(
    'partial return restores stock, reduces baki, and appears in reports',
    () async {
      final db = DatabaseHelper();
      final product = Product(
        name: 'Rice',
        costPrice: 40,
        variants: [
          const ProductVariant(name: 'Kg', barcode: '', price: 100, stock: 10),
        ],
      );
      await db.insertProduct(product);
      final loadedProduct = (await db.getAllProducts()).single;
      final variant = loadedProduct.variants.single;
      final customerId = await db.insertCustomer(
        Customer(name: 'Mina', createdAt: DateTime(2026, 7, 1)),
      );
      final saleId = await db.insertSale(
        Sale(
          items: [
            CartItem(product: loadedProduct, variant: variant, quantity: 2),
          ],
          totalAmount: 200,
          createdAt: DateTime(2026, 7, 1, 12),
          customerId: customerId,
          customerName: 'Mina',
          payments: const [
            SalePayment(method: 'cash', amount: 100),
            SalePayment(method: 'baki', amount: 100),
          ],
        ),
      );
      final saleItemId =
          (await db.getAllSales()).single.items.single.saleItemId!;

      final returned = await db.createSaleReturn(
        saleId: saleId,
        quantitiesBySaleItemId: {saleItemId: 1},
        reason: 'Customer changed mind',
        refundMethod: 'baki',
        createdAt: DateTime(2026, 7, 2, 12),
      );

      expect(returned.amount, 100);
      expect((await db.getAllProducts()).single.totalStock, 9);
      final updatedSale = (await db.getAllSales()).single;
      expect(updatedSale.items.single.returnedQuantity, 1);
      expect(updatedSale.returnedBakiAmount, 100);
      expect(updatedSale.bakiAmount, 0);
      expect(await db.getCustomerBakiSummaries(), isEmpty);
      await expectLater(
        db.createSaleReturn(
          saleId: saleId,
          quantitiesBySaleItemId: {saleItemId: 2},
          reason: 'Too many',
          refundMethod: 'baki',
          createdAt: DateTime(2026, 7, 3),
        ),
        throwsArgumentError,
      );

      final report = await db.getSalesReportData(
        ReportRange(from: DateTime(2026, 7, 2), through: DateTime(2026, 7, 2)),
      );
      expect(report.returns, 100);
      expect(report.netSales, -100);
      expect(report.totalReceivable, -100);
      expect(report.paymentTotals['baki'], -100);
    },
  );

  test(
    'a cash sale cannot be refunded against unrelated customer baki',
    () async {
      final db = DatabaseHelper();
      await db.insertProduct(
        Product(
          name: 'Coffee',
          variants: [
            const ProductVariant(name: 'Jar', barcode: '', price: 80, stock: 3),
          ],
        ),
      );
      final product = (await db.getAllProducts()).single;
      final customerId = await db.insertCustomer(
        Customer(name: 'Nila', createdAt: DateTime(2026, 7, 1)),
      );
      final saleId = await db.insertSale(
        Sale(
          items: [
            CartItem(
              product: product,
              variant: product.variants.single,
              quantity: 1,
            ),
          ],
          totalAmount: 80,
          createdAt: DateTime(2026, 7, 1),
          customerId: customerId,
          customerName: 'Nila',
        ),
      );
      final saleItemId =
          (await db.getAllSales()).single.items.single.saleItemId!;

      await expectLater(
        db.createSaleReturn(
          saleId: saleId,
          quantitiesBySaleItemId: {saleItemId: 1},
          reason: 'Wrong refund type',
          refundMethod: 'baki',
        ),
        throwsArgumentError,
      );
      expect((await db.getAllProducts()).single.totalStock, 2);
      expect((await db.getAllSales()).single.returnedAmount, 0);
    },
  );
}
