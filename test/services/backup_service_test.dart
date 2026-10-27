import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:m_pos/db/database_helper.dart';
import 'package:m_pos/models/baki_payment.dart';
import 'package:m_pos/models/cart_item.dart';
import 'package:m_pos/models/customer.dart';
import 'package:m_pos/models/daily_cash_close.dart';
import 'package:m_pos/models/product.dart';
import 'package:m_pos/models/product_variant.dart';
import 'package:m_pos/models/sale.dart';
import 'package:m_pos/models/purchase.dart';
import 'package:m_pos/models/supplier.dart';
import 'package:m_pos/models/sales_report.dart';
import 'package:m_pos/services/backup_service.dart';
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

  test('backup restores inventory, sales, baki, and settings', () async {
    final db = DatabaseHelper();
    final service = BackupService(db: db);
    final productId = await db.insertProduct(
      Product(
        name: 'Rice',
        costPrice: 40,
        variants: [
          const ProductVariant(
            name: '1 kg',
            barcode: 'rice-1kg',
            price: 55,
            stock: 10,
          ),
        ],
      ),
    );
    final product = (await db.getAllProducts()).single;
    final variant = product.variants.single;
    final customerId = await db.insertCustomer(
      Customer(
        name: 'Rahim',
        phone: '01700000000',
        createdAt: DateTime(2026, 5, 1),
      ),
    );
    await db.insertSale(
      Sale(
        items: [CartItem(product: product, variant: variant, quantity: 2)],
        totalAmount: 110,
        createdAt: DateTime(2026, 5, 2, 10),
        paymentType: 'baki',
        customerId: customerId,
        customerName: 'Rahim',
      ),
    );
    await db.stockIn(variant.id!, 4, costPrice: 42, supplier: 'Rice supplier');
    final supplierId = await db.saveSupplier(
      const Supplier(name: 'Main supplier', phone: '01711111111'),
    );
    final supplier = (await db.getSuppliers()).single;
    await db.recordPurchase(
      supplier: supplier,
      items: [
        PurchaseLine(
          variantId: variant.id!,
          productName: 'Rice',
          variantName: '1 kg',
          quantity: 2,
          costPrice: 41,
        ),
      ],
      note: 'Backup sample purchase',
      createdAt: DateTime(2026, 5, 2, 9),
    );
    await db.insertBakiPayment(
      BakiPayment(
        customerId: customerId,
        amount: 25,
        note: 'Part payment',
        paidAt: DateTime(2026, 5, 3),
      ),
    );
    await db.saveAppSettings({
      'currency_symbol': '৳',
      'shop_name': 'Karbar Store',
      'setup_complete': 'true',
    });
    await db.recordDailyClose(
      DailyCashClose(
        businessDate: DateTime(2026, 5, 3),
        expectedCash: 80,
        countedCash: 78,
        cashReceipts: 80,
        bakiIssued: 0,
        bakiCollected: 25,
        refundsTotal: 0,
        paymentTotals: const {'cash': 80, 'baki': 0},
        note: 'Close note',
        closedAt: DateTime(2026, 5, 3, 22),
      ),
    );

    final backup = service.decodeBackupJson(await service.createBackupJson());
    expect(backup.productCount, 1);
    expect(backup.saleCount, 1);
    expect(backup.customerCount, 1);

    await db.insertProduct(
      Product(
        name: 'Temporary product',
        variants: [
          const ProductVariant(
            name: 'Default',
            barcode: '',
            price: 1,
            stock: 1,
          ),
        ],
      ),
    );
    await db.clearAllSales();

    await service.restoreBackup(backup);

    final restoredProducts = await db.getAllProducts();
    expect(restoredProducts.map((item) => item.name), ['Rice']);
    expect(restoredProducts.single.id, productId);
    expect(restoredProducts.single.variants.single.stock, 14);
    expect((await db.getAllSales()).single.totalAmount, 110);
    expect((await db.getAllCustomers()).single.name, 'Rahim');
    expect((await db.getBakiPaymentsForCustomer(customerId)).single.amount, 25);
    expect((await db.getAppSettings())['shop_name'], 'Karbar Store');
    expect((await db.getSuppliers()).single.id, supplierId);
    expect((await db.getPurchases()).single.totalAmount, 82);
    expect((await db.getDailyCloses()).single.difference, -2);
  });

  test(
    'invalid backup rows roll back replacement and preserve local data',
    () async {
      final db = DatabaseHelper();
      final service = BackupService(db: db);
      await db.insertProduct(
        Product(
          name: 'Keep this product',
          variants: [
            const ProductVariant(
              name: 'Default',
              barcode: '',
              price: 10,
              stock: 3,
            ),
          ],
        ),
      );
      final root = jsonDecode(await service.createBackupJson()) as Map;
      final tables = root['tables'] as Map<String, dynamic>;
      final products = tables['products'] as List<dynamic>;
      (products.single as Map<String, dynamic>)['not_a_column'] = 'invalid';
      final invalidRows = service.decodeBackupJson(jsonEncode(root));

      await expectLater(
        service.restoreBackup(invalidRows),
        throwsA(isA<Exception>()),
      );

      expect((await db.getAllProducts()).single.name, 'Keep this product');
    },
  );

  test(
    'unsupported backup is rejected before touching local records',
    () async {
      final db = DatabaseHelper();
      final service = BackupService(db: db);
      await db.insertProduct(
        Product(
          name: 'Keep this product',
          variants: [
            const ProductVariant(
              name: 'Default',
              barcode: '',
              price: 10,
              stock: 3,
            ),
          ],
        ),
      );

      expect(
        () => service.decodeBackupJson('{"format":"other","version":1}'),
        throwsFormatException,
      );
      expect((await db.getAllProducts()).single.name, 'Keep this product');
    },
  );

  test(
    'version 12 backup remains readable without purchase origin metadata',
    () async {
      final service = BackupService(db: DatabaseHelper());
      final legacy =
          jsonDecode(await service.createBackupJson()) as Map<String, dynamic>;
      legacy['version'] = 12;
      final tables = legacy['tables'] as Map<String, dynamic>;
      for (final row in tables['purchases'] as List) {
        (row as Map<String, dynamic>)
          ..remove('origin_shop_id')
          ..remove('origin_event_id');
      }
      final archive = service.decodeBackupJson(jsonEncode(legacy));
      expect(archive.tables['purchases'], isEmpty);
    },
  );

  test(
    'version 1 backup remains readable without payment allocations',
    () async {
      final service = BackupService(db: DatabaseHelper());
      final legacy =
          jsonDecode(await service.createBackupJson()) as Map<String, dynamic>;
      legacy['version'] = 1;
      final tables = legacy['tables'] as Map<String, dynamic>;
      tables.remove('sale_payments');
      tables.remove('sale_returns');
      tables.remove('sale_return_items');
      tables.remove('suppliers');
      tables.remove('purchases');
      tables.remove('purchase_items');
      tables.remove('daily_closes');
      tables.remove('staff_users');
      tables.remove('sync_outbox');

      final archive = service.decodeBackupJson(jsonEncode(legacy));

      expect(archive.tables['sale_payments'], isEmpty);
      expect(archive.tables['sale_returns'], isEmpty);
      expect(archive.tables['sale_return_items'], isEmpty);
      expect(archive.tables['suppliers'], isEmpty);
    },
  );

  test('version 2 backup remains readable without return records', () async {
    final service = BackupService(db: DatabaseHelper());
    final legacy =
        jsonDecode(await service.createBackupJson()) as Map<String, dynamic>;
    legacy['version'] = 2;
    final tables = legacy['tables'] as Map<String, dynamic>;
    tables.remove('sale_returns');
    tables.remove('sale_return_items');
    tables.remove('suppliers');
    tables.remove('purchases');
    tables.remove('purchase_items');
    tables.remove('daily_closes');
    tables.remove('staff_users');
    tables.remove('sync_outbox');

    final archive = service.decodeBackupJson(jsonEncode(legacy));

    expect(archive.tables['sale_returns'], isEmpty);
    expect(archive.tables['sale_return_items'], isEmpty);
  });

  test('version 3 backup remains readable without purchase records', () async {
    final service = BackupService(db: DatabaseHelper());
    final legacy =
        jsonDecode(await service.createBackupJson()) as Map<String, dynamic>;
    legacy['version'] = 3;
    final tables = legacy['tables'] as Map<String, dynamic>;
    tables.remove('suppliers');
    tables.remove('purchases');
    tables.remove('purchase_items');
    tables.remove('daily_closes');
    tables.remove('staff_users');
    tables.remove('sync_outbox');

    final archive = service.decodeBackupJson(jsonEncode(legacy));

    expect(archive.tables['suppliers'], isEmpty);
    expect(archive.tables['purchases'], isEmpty);
  });

  test('version 4 backup defaults quantity precision to whole units', () async {
    final db = DatabaseHelper();
    final service = BackupService(db: db);
    await db.insertProduct(
      Product(
        name: 'Flour',
        unit: 'kg',
        quantityPrecision: 3,
        variants: [
          const ProductVariant(name: 'Bag', barcode: '', price: 80, stock: 2),
        ],
      ),
    );
    final legacy =
        jsonDecode(await service.createBackupJson()) as Map<String, dynamic>;
    legacy['version'] = 4;
    final tables = legacy['tables'] as Map<String, dynamic>;
    tables.remove('daily_closes');
    tables.remove('staff_users');
    tables.remove('sync_outbox');
    final products = tables['products'] as List<dynamic>;
    (products.single as Map<String, dynamic>).remove('quantity_precision');
    final archive = service.decodeBackupJson(jsonEncode(legacy));

    await service.restoreBackup(archive);

    expect((await db.getAllProducts()).single.quantityPrecision, 0);
  });

  test('version 5 backup remains readable without daily closes', () async {
    final service = BackupService(db: DatabaseHelper());
    final legacy =
        jsonDecode(await service.createBackupJson()) as Map<String, dynamic>;
    legacy['version'] = 5;
    (legacy['tables'] as Map<String, dynamic>).remove('daily_closes');
    (legacy['tables'] as Map<String, dynamic>).remove('staff_users');
    (legacy['tables'] as Map<String, dynamic>).remove('sync_outbox');

    final archive = service.decodeBackupJson(jsonEncode(legacy));

    expect(archive.tables['daily_closes'], isEmpty);
  });

  test(
    'version 6 sale rows restore without a historical cost snapshot',
    () async {
      final db = DatabaseHelper();
      final service = BackupService(db: db);
      await db.insertProduct(
        Product(
          name: 'Soap',
          costPrice: 5,
          variants: [
            const ProductVariant(name: 'Bar', barcode: '', price: 10, stock: 2),
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
          createdAt: DateTime(2026, 9, 1),
        ),
      );
      final legacy =
          jsonDecode(await service.createBackupJson()) as Map<String, dynamic>;
      legacy['version'] = 6;
      final tables = legacy['tables'] as Map<String, dynamic>;
      tables.remove('staff_users');
      tables.remove('sync_outbox');
      final saleItems = tables['sale_items'] as List<dynamic>;
      (saleItems.single as Map<String, dynamic>).remove('cost_price_snapshot');
      await service.restoreBackup(service.decodeBackupJson(jsonEncode(legacy)));

      final report = await db.getSalesReportData(
        ReportRange(from: DateTime(2026, 9, 1), through: DateTime(2026, 9, 1)),
      );
      expect(report.estimatedProfit, 0);
      expect(report.linesWithoutCost, 1);
    },
  );

  test('version 7 backups restore without staff accounts', () async {
    final db = DatabaseHelper();
    final service = BackupService(db: db);
    final legacy =
        jsonDecode(await service.createBackupJson()) as Map<String, dynamic>;
    legacy['version'] = 7;
    (legacy['tables'] as Map<String, dynamic>).remove('staff_users');
    (legacy['tables'] as Map<String, dynamic>).remove('sync_outbox');

    await service.restoreBackup(service.decodeBackupJson(jsonEncode(legacy)));

    expect(await db.getStaffUsers(), isEmpty);
  });

  test('version 8 backups restore without a sync outbox', () async {
    final db = DatabaseHelper();
    final service = BackupService(db: db);
    await StaffAccess(db: db).create(name: 'Owner', role: 'owner', pin: '4826');
    final legacy =
        jsonDecode(await service.createBackupJson()) as Map<String, dynamic>;
    legacy['version'] = 8;
    (legacy['tables'] as Map<String, dynamic>).remove('sync_outbox');

    await service.restoreBackup(service.decodeBackupJson(jsonEncode(legacy)));

    expect(await db.getPendingSyncEventCount(), 0);
    expect((await db.getStaffUsers()).single.isOwner, isTrue);
  });

  test('backup restores staff PIN hashes and role access', () async {
    final db = DatabaseHelper();
    final service = BackupService(db: db);
    final access = StaffAccess(db: db);
    final ownerId = await access.create(
      name: 'Owner',
      role: 'owner',
      pin: '4826',
    );
    final archive = service.decodeBackupJson(await service.createBackupJson());

    await service.restoreBackup(archive);

    final restoredOwner = await StaffAccess(
      db: db,
    ).authenticate(ownerId, '4826');
    expect(restoredOwner?.isOwner, isTrue);
  });

  test(
    'product images are portable and restored into app-owned files',
    () async {
      final db = DatabaseHelper();
      final tempDirectory = await Directory.systemTemp.createTemp(
        'karbar-backup',
      );
      addTearDown(() => tempDirectory.delete(recursive: true));
      final sourceImage = File('${tempDirectory.path}/original.png');
      final imageBytes = [137, 80, 78, 71, 1, 2, 3];
      await sourceImage.writeAsBytes(imageBytes);
      final service = BackupService(
        db: db,
        documentsDirectoryProvider: () async => tempDirectory,
      );
      await db.insertProduct(
        Product(
          name: 'Image item',
          imagePath: sourceImage.path,
          variants: [
            const ProductVariant(
              name: 'Default',
              barcode: '',
              price: 10,
              stock: 3,
            ),
          ],
        ),
      );

      final backup = service.decodeBackupJson(await service.createBackupJson());
      expect(backup.productImages.length, 1);
      expect(backup.tables['products']!.single['image_path'], '');
      await service.restoreBackup(backup);

      final restoredProduct = (await db.getAllProducts()).single;
      expect(restoredProduct.imagePath, isNot(sourceImage.path));
      expect(await File(restoredProduct.imagePath).readAsBytes(), imageBytes);
    },
  );
}
