import 'package:flutter_test/flutter_test.dart';
import 'package:m_pos/db/database_helper.dart';
import 'package:m_pos/models/baki_payment.dart';
import 'package:m_pos/models/cart_item.dart';
import 'package:m_pos/models/customer.dart';
import 'package:m_pos/models/daily_cash_close.dart';
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

  test('daily close reconciles drawer and preserves previous closes', () async {
    final db = DatabaseHelper();
    await db.insertProduct(
      Product(
        name: 'Oil',
        variants: [
          const ProductVariant(
            name: 'Bottle',
            barcode: '',
            price: 100,
            stock: 5,
          ),
        ],
      ),
    );
    final product = (await db.getAllProducts()).single;
    final customerId = await db.insertCustomer(
      Customer(name: 'Rupa', createdAt: DateTime(2026, 9, 1)),
    );
    await db.insertSale(
      Sale(
        items: [
          CartItem(
            product: product,
            variant: product.variants.single,
            quantity: 2,
          ),
        ],
        totalAmount: 200,
        createdAt: DateTime(2026, 9, 1, 10),
        customerId: customerId,
        customerName: 'Rupa',
        payments: const [
          SalePayment(method: 'cash', amount: 150),
          SalePayment(method: 'baki', amount: 50),
        ],
      ),
    );
    final sale = (await db.getAllSales()).single;
    await db.createSaleReturn(
      saleId: sale.id!,
      quantitiesBySaleItemId: {sale.items.single.saleItemId!: 1},
      reason: 'Bottle leaked',
      refundMethod: 'cash',
      createdAt: DateTime(2026, 9, 1, 16),
    );
    await db.insertBakiPayment(
      BakiPayment(
        customerId: customerId,
        amount: 10,
        note: 'Paid in cash',
        paidAt: DateTime(2026, 9, 1, 17),
      ),
    );

    final report = await db.getSalesReportData(
      ReportRange(from: DateTime(2026, 9, 1), through: DateTime(2026, 9, 1)),
    );
    expect(report.paymentTotals['cash'], 50);
    expect(report.bakiIssued, 50);
    expect(report.bakiCollected, 10);
    final firstId = await db.recordDailyClose(
      DailyCashClose(
        businessDate: DateTime(2026, 9, 1),
        expectedCash: 60,
        countedCash: 60,
        cashReceipts: report.paymentTotals['cash']!,
        bakiIssued: report.bakiIssued,
        bakiCollected: report.bakiCollected,
        refundsTotal: report.returns,
        paymentTotals: report.paymentTotals,
        note: 'Drawer reconciled',
        closedAt: DateTime(2026, 9, 1, 18),
      ),
    );
    await db.recordDailyClose(
      DailyCashClose(
        businessDate: DateTime(2026, 9, 1),
        expectedCash: 60,
        countedCash: 70,
        cashReceipts: report.paymentTotals['cash']!,
        bakiIssued: report.bakiIssued,
        bakiCollected: report.bakiCollected,
        refundsTotal: report.returns,
        paymentTotals: report.paymentTotals,
        note: 'Second shift close',
        closedAt: DateTime(2026, 9, 1, 22),
      ),
    );

    final closes = await db.getDailyCloses(businessDate: DateTime(2026, 9, 1));
    expect(closes, hasLength(2));
    expect(closes.first.id, isNot(firstId));
    expect(closes.first.difference, 10);
    expect(closes.first.paymentTotals['cash'], 50);
    expect(closes.last.note, 'Drawer reconciled');
  });
}
