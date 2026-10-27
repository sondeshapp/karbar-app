import 'package:flutter_test/flutter_test.dart';
import 'package:m_pos/db/database_helper.dart';
import 'package:m_pos/models/baki_payment.dart';
import 'package:m_pos/models/cart_item.dart';
import 'package:m_pos/models/customer.dart';
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

  test(
    'report range totals sales, discounts, tax, baki, and estimated profit',
    () async {
      final db = DatabaseHelper();
      await db.insertProduct(
        Product(
          name: 'Tea',
          costPrice: 30,
          lowStockAlert: 10,
          variants: [
            const ProductVariant(
              name: 'Pack',
              barcode: '',
              price: 50,
              stock: 10,
            ),
          ],
        ),
      );
      final product = (await db.getAllProducts()).single;
      final variant = product.variants.single;
      await db.insertSale(
        Sale(
          items: [
            CartItem(
              product: product,
              variant: variant,
              quantity: 2,
              discountAmount: 5,
            ),
          ],
          totalAmount: 88,
          createdAt: DateTime(2026, 6, 1, 10),
          paymentType: 'baki',
          discountAmount: 10,
          taxAmount: 8,
        ),
      );
      await db.insertSale(
        Sale(
          items: [CartItem(product: product, variant: variant, quantity: 1)],
          totalAmount: 50,
          createdAt: DateTime(2026, 6, 2, 10),
        ),
      );
      final afterSaleProduct = (await db.getAllProducts()).single;
      await db.updateProduct(afterSaleProduct.copyWith(costPrice: 99));
      final storedBakiSale = (await db.getAllSales()).firstWhere(
        (sale) => sale.paymentType == 'baki',
      );
      expect(storedBakiSale.taxAmount, 8);

      final report = await db.getSalesReportData(
        ReportRange(from: DateTime(2026, 6, 1), through: DateTime(2026, 6, 1)),
      );

      expect(report.saleCount, 1);
      expect(report.grossSales, 100);
      expect(report.discounts, 20);
      expect(report.netSales, 80);
      expect(report.taxCollected, 8);
      expect(report.totalReceivable, 88);
      expect(report.averageSale, 88);
      expect(report.estimatedProfit, 20);
      expect(report.linesWithoutCost, 0);
      expect(report.bakiIssued, 88);
      expect(report.paymentTotals['baki'], 88);
      expect(report.topProducts.single.name, 'Tea');
      expect(report.topProducts.single.netSales, 80);
      expect(report.lowStockProducts.map((p) => p.name), ['Tea']);
    },
  );

  test(
    'reports include payments on start date and exclude next-day payments',
    () async {
      final db = DatabaseHelper();
      final customerId = await db.insertCustomer(
        Customer(name: 'Nila', createdAt: DateTime(2026, 6, 1)),
      );
      await db.insertBakiPayment(
        BakiPayment(
          customerId: customerId,
          amount: 25,
          paidAt: DateTime(2026, 6, 1, 23, 59),
        ),
      );
      await db.insertBakiPayment(
        BakiPayment(
          customerId: customerId,
          amount: 70,
          paidAt: DateTime(2026, 6, 2),
        ),
      );

      final report = await db.getSalesReportData(
        ReportRange(from: DateTime(2026, 6, 1), through: DateTime(2026, 6, 1)),
      );

      expect(report.bakiCollected, 25);
    },
  );
}
