import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:m_pos/db/database_helper.dart';
import 'package:m_pos/models/cart_item.dart';
import 'package:m_pos/models/baki_payment.dart';
import 'package:m_pos/models/customer.dart';
import 'package:m_pos/models/cloud_catalog.dart';
import 'package:m_pos/models/product.dart';
import 'package:m_pos/models/product_variant.dart';
import 'package:m_pos/models/purchase.dart';
import 'package:m_pos/models/sale.dart';
import 'package:m_pos/models/sync_outbox_event.dart';
import 'package:m_pos/models/supplier.dart';
import 'package:m_pos/models/remote_sync_event.dart';
import 'package:m_pos/services/backup_service.dart';
import 'package:m_pos/services/sync_service.dart';
import 'package:m_pos/services/product_image_storage.dart';
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

  test(
    'sale is atomically queued and retries keep one idempotency key',
    () async {
      final db = DatabaseHelper();
      await db.insertProduct(
        Product(
          name: 'Rice',
          costPrice: 25,
          variants: [
            const ProductVariant(name: 'Bag', barcode: '', price: 35, stock: 2),
          ],
        ),
      );
      final product = (await db.getAllProducts()).single;
      final saleId = await db.insertSale(
        Sale(
          items: [
            CartItem(
              product: product,
              variant: product.variants.single,
              quantity: 1,
            ),
          ],
          totalAmount: 35,
          createdAt: DateTime(2026, 10, 26, 10),
        ),
      );

      final queued = await db.getPendingSyncEvents();
      expect(queued, hasLength(1));
      expect(queued.single.entityId, saleId);
      expect(queued.single.eventType, 'sale.created');
      expect(
        queued.single.idempotencyKey,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
      final payload =
          jsonDecode(queued.single.payloadJson) as Map<String, dynamic>;
      expect(payload['idempotencyKey'], queued.single.idempotencyKey);
      expect(payload['items'].single['costPrice'], 25);
      expect(payload['items'].single['productSyncId'], isNotEmpty);
      expect(payload['items'].single['variantSyncId'], isNotEmpty);

      final backup = BackupService(db: db);
      final archive = backup.decodeBackupJson(await backup.createBackupJson());
      await backup.restoreBackup(archive);
      final restored = (await db.getPendingSyncEvents()).single;
      expect(restored.idempotencyKey, queued.single.idempotencyKey);

      await db.markSyncEventFailed(restored.idempotencyKey, 'temporary outage');
      final retry = (await db.getPendingSyncEvents()).single;
      expect(retry.idempotencyKey, queued.single.idempotencyKey);
      expect(retry.attempts, 1);
      expect(retry.lastError, 'temporary outage');

      await db.markSyncEventSent(retry.idempotencyKey);
      await db.markSyncEventSent(retry.idempotencyKey);
      expect(await db.getPendingSyncEventCount(), 0);
    },
  );

  test(
    'remote purchase history retries dependencies and does not receive stock twice',
    () async {
      final db = DatabaseHelper();
      const productSyncId = '44444444-4444-4444-8444-444444444444';
      const variantSyncId = '55555555-5555-4555-8555-555555555555';
      const supplierSyncId = '66666666-6666-4666-8666-666666666666';
      final event = RemoteSyncEvent(
        cursor: 1,
        eventId: 'remote-purchase-1',
        eventType: 'purchase.recorded',
        entityId: 11,
        createdAt: DateTime.utc(2026, 10, 26),
        payload: {
          'supplierSyncId': supplierSyncId,
          'supplierName': 'City Wholesale',
          'totalAmount': 100,
          'createdAt': '2026-10-26T10:00:00.000Z',
          'note': 'Restock',
          'items': [
            {
              'productSyncId': productSyncId,
              'variantSyncId': variantSyncId,
              'productName': 'Rice',
              'variantName': 'Bag',
              'quantity': 4,
              'costPrice': 25,
            },
          ],
        },
      );
      await db.saveRemoteSyncEvents(
        remoteShopId: 'shop-a',
        nextCursor: 1,
        events: [event],
      );
      final staged = await db.applyPendingRemoteSyncEvents('shop-a');
      expect(staged.applied, 0);
      expect(staged.errors, 1);

      await db.insertProduct(
        Product(
          name: 'Rice',
          syncId: productSyncId,
          variants: [
            ProductVariant(
              name: 'Bag',
              barcode: '',
              price: 30,
              stock: 7,
              syncId: variantSyncId,
            ),
          ],
        ),
      );
      await db.saveSupplier(
        Supplier(name: 'City Wholesale', syncId: supplierSyncId),
      );
      final applied = await db.applyPendingRemoteSyncEvents('shop-a');
      expect(applied.applied, 1);
      expect(applied.pending, 0);
      expect((await db.getPurchases()).single.items.single.quantity, 4);
      expect((await db.getAllProducts()).single.variants.single.stock, 7);
      expect(await db.getPendingSyncEventCount(), 0);
      final rawDb = await db.database;
      final originRows = await rawDb.query('purchases');
      expect(originRows.single['origin_shop_id'], 'shop-a');
      expect(originRows.single['origin_event_id'], 'remote-purchase-1');
      await rawDb.delete('sync_inbox');
      await rawDb.delete('sync_state');
      await db.saveRemoteSyncEvents(
        remoteShopId: 'shop-a',
        nextCursor: 1,
        events: [event],
      );
      await db.applyPendingRemoteSyncEvents('shop-a');
      expect(await db.getPurchases(), hasLength(1));
      expect((await db.getAllProducts()).single.variants.single.stock, 7);
    },
  );

  test(
    'remote sale history applies once without changing catalog stock',
    () async {
      final db = DatabaseHelper();
      await db.insertProduct(
        Product(
          name: 'Rice',
          costPrice: 20,
          variants: [
            const ProductVariant(name: 'Bag', barcode: '', price: 30, stock: 8),
          ],
        ),
      );
      final product = (await db.getAllProducts()).single;
      final variant = product.variants.single;
      final event = RemoteSyncEvent(
        cursor: 1,
        eventId: 'remote-sale-1',
        eventType: 'sale.created',
        entityId: 1,
        createdAt: DateTime.utc(2026, 10, 26),
        payload: {
          'idempotencyKey': 'remote-sale-1',
          'totalAmount': 60,
          'createdAt': '2026-10-26T10:00:00.000Z',
          'paymentType': 'split',
          'discountAmount': 0,
          'discountType': 'flat',
          'taxAmount': 0,
          'items': [
            {
              'productSyncId': product.syncId,
              'variantSyncId': variant.syncId,
              'productName': 'Rice',
              'variantName': 'Bag',
              'unitPrice': 30,
              'costPrice': 20,
              'quantity': 2,
              'discountAmount': 0,
            },
          ],
          'payments': [
            {'method': 'cash', 'amount': 60, 'note': ''},
          ],
        },
      );
      await db.saveRemoteSyncEvents(
        remoteShopId: 'shop-a',
        nextCursor: 1,
        events: [event],
      );

      final result = await db.applyPendingRemoteSyncEvents('shop-a');
      expect(result.applied, 1);
      expect(result.pending, 0);
      expect((await db.getAllSales()), hasLength(1));
      expect((await db.getAllProducts()).single.variants.single.stock, 8);
      expect(await db.getPendingSyncEventCount(), 0);

      final rawDb = await db.database;
      await rawDb.delete('sync_inbox');
      await rawDb.delete('sync_state');
      await db.saveRemoteSyncEvents(
        remoteShopId: 'shop-a',
        nextCursor: 1,
        events: [event],
      );
      final duplicateResult = await db.applyPendingRemoteSyncEvents('shop-a');
      expect(duplicateResult.applied, 1);
      expect((await db.getAllSales()), hasLength(1));

      const customerSyncId = '33333333-3333-4333-8333-333333333333';
      await db.insertCustomer(
        Customer(
          name: 'Nila',
          syncId: customerSyncId,
          createdAt: DateTime.utc(2026, 10, 26),
        ),
      );
      await db.saveRemoteSyncEvents(
        remoteShopId: 'shop-a',
        nextCursor: 3,
        events: [
          RemoteSyncEvent(
            cursor: 2,
            eventId: 'remote-return-1',
            eventType: 'sale.returned',
            entityId: 2,
            createdAt: DateTime.utc(2026, 10, 26, 11),
            payload: {
              'saleEventId': 'remote-sale-1',
              'refundAmount': 30,
              'refundMethod': 'cash',
              'reason': 'Damaged',
              'lines': [
                {
                  'productSyncId': product.syncId,
                  'variantSyncId': variant.syncId,
                  'productName': 'Rice',
                  'variantName': 'Bag',
                  'quantity': 1,
                  'amount': 30,
                },
              ],
            },
          ),
          RemoteSyncEvent(
            cursor: 3,
            eventId: 'remote-payment-1',
            eventType: 'baki.payment_recorded',
            entityId: 3,
            createdAt: DateTime.utc(2026, 10, 26, 12),
            payload: {
              'customerSyncId': customerSyncId,
              'amount': 5,
              'note': 'Collection',
              'paidAt': '2026-10-26T12:00:00.000Z',
            },
          ),
        ],
      );
      final transactions = await db.applyPendingRemoteSyncEvents('shop-a');
      expect(transactions.applied, 2);
      expect(transactions.pending, 0);
      final rawRows = await (await db.database).query('sale_returns');
      expect(rawRows.single['origin_event_id'], 'remote-return-1');
      final paymentRows = await (await db.database).query('baki_payments');
      expect(paymentRows.single['origin_event_id'], 'remote-payment-1');
      expect((await db.getAllProducts()).single.variants.single.stock, 8);
    },
  );

  test(
    'remote events with missing catalog data stay staged and retry',
    () async {
      final db = DatabaseHelper();
      const productId = '11111111-1111-4111-8111-111111111111';
      const variantId = '22222222-2222-4222-8222-222222222222';
      final event = RemoteSyncEvent(
        cursor: 1,
        eventId: 'remote-sale-waiting',
        eventType: 'sale.created',
        entityId: 1,
        createdAt: DateTime.utc(2026, 10, 26),
        payload: {
          'idempotencyKey': 'remote-sale-waiting',
          'totalAmount': 10,
          'createdAt': '2026-10-26T10:00:00.000Z',
          'paymentType': 'cash',
          'items': [
            {
              'productSyncId': productId,
              'variantSyncId': variantId,
              'productName': 'Tea',
              'variantName': 'Box',
              'unitPrice': 10,
              'quantity': 1,
              'discountAmount': 0,
            },
          ],
          'payments': [],
        },
      );
      await db.saveRemoteSyncEvents(
        remoteShopId: 'shop-a',
        nextCursor: 1,
        events: [event],
      );
      final first = await db.applyPendingRemoteSyncEvents('shop-a');
      expect(first.pending, 1);
      expect(first.errors, 1);
      expect(await db.getAllSales(), isEmpty);

      await db.insertProduct(
        Product(
          name: 'Tea',
          syncId: productId,
          variants: [
            ProductVariant(
              name: 'Box',
              syncId: variantId,
              barcode: '',
              price: 10,
              stock: 4,
            ),
          ],
        ),
      );
      final retry = await db.applyPendingRemoteSyncEvents('shop-a');
      expect(retry.applied, 1);
      expect(retry.pending, 0);
      expect((await db.getAllSales()), hasLength(1));
    },
  );

  test(
    'catalog mutations persist until acknowledged and track product deletes',
    () async {
      final db = DatabaseHelper();
      await db.insertProduct(
        Product(
          name: 'Rice',
          variants: [
            const ProductVariant(
              name: 'Bag',
              barcode: '123',
              price: 30,
              stock: 4,
            ),
          ],
        ),
      );
      await db.insertCustomer(
        Customer(
          name: 'Nila',
          phone: '01700000000',
          createdAt: DateTime(2026, 10, 26),
        ),
      );

      final first = await db.prepareCloudCatalogMutations('shop-a');
      expect(first, hasLength(2));
      expect(first.map((mutation) => mutation.entityType).toSet(), {
        'product',
        'customer',
      });
      final retry = await db.prepareCloudCatalogMutations('shop-a');
      expect(
        retry.map((mutation) => mutation.mutationId),
        first.map((mutation) => mutation.mutationId),
      );
      expect(
        retry.map((mutation) => mutation.payload),
        first.map((mutation) => mutation.payload),
      );

      for (final mutation in first) {
        await db.acknowledgeCloudCatalogMutation(
          'shop-a',
          mutation.mutationId,
          1,
        );
      }
      expect(await db.prepareCloudCatalogMutations('shop-a'), isEmpty);

      final product = (await db.getAllProducts()).single;
      final productSyncId = product.syncId!;
      await db.deleteProduct(product.id!);
      final deletion = await db.prepareCloudCatalogMutations('shop-a');
      expect(deletion, hasLength(1));
      expect(deletion.single.entityId, productSyncId);
      expect(deletion.single.baseRevision, 1);
      expect(deletion.single.deleted, isTrue);
      await db.acknowledgeCloudCatalogMutation(
        'shop-a',
        deletion.single.mutationId,
        2,
      );
      expect(await db.prepareCloudCatalogMutations('shop-a'), isEmpty);
    },
  );

  test(
    'catalog edits during a pending mutation are queued after its acknowledgement',
    () async {
      final db = DatabaseHelper();
      await db.insertProduct(
        Product(
          name: 'Tea',
          variants: [
            const ProductVariant(
              name: 'Pack',
              barcode: '',
              price: 10,
              stock: 2,
            ),
          ],
        ),
      );
      final product = (await db.getAllProducts()).single;
      final first = (await db.prepareCloudCatalogMutations('shop-a')).single;
      final changed = product.copyWith(name: 'Green tea');
      await db.updateProduct(changed);
      await db.acknowledgeCloudCatalogMutation('shop-a', first.mutationId, 1);

      final next = (await db.prepareCloudCatalogMutations('shop-a')).single;
      expect(next.entityId, first.entityId);
      expect(next.baseRevision, 1);
      expect(next.mutationId, isNot(first.mutationId));
      expect(next.payload['name'], 'Green tea');
    },
  );

  test(
    'remote catalog pages stage idempotently with an account cursor',
    () async {
      final db = DatabaseHelper();
      final change = CloudCatalogChange(
        cursor: 2,
        entityType: 'product',
        entityId: '11111111-1111-4111-8111-111111111111',
        mutationId: '22222222-2222-4222-8222-222222222222',
        baseRevision: 0,
        revision: 1,
        payload: const {
          'syncId': '11111111-1111-4111-8111-111111111111',
          'name': 'Rice',
        },
        deleted: false,
        changedAt: DateTime.utc(2026, 10, 26),
      );
      final page = CloudCatalogPage(cursor: 2, changes: [change]);

      expect(
        await db.saveRemoteCloudCatalogChanges(
          remoteShopId: 'shop-a',
          page: page,
        ),
        1,
      );
      expect(
        await db.saveRemoteCloudCatalogChanges(
          remoteShopId: 'shop-a',
          page: page,
        ),
        0,
      );
      expect(await db.getCloudCatalogCursor('shop-a'), 2);
      expect(await db.getCloudCatalogCursor('shop-b'), 0);
      expect(await db.getUnappliedCloudCatalogChangeCount('shop-a'), 1);
      await expectLater(
        db.saveRemoteCloudCatalogChanges(
          remoteShopId: 'shop-a',
          page: const CloudCatalogPage(cursor: 1, changes: []),
        ),
        throwsStateError,
      );
    },
  );

  test(
    'staff accounts sync profiles and retain offline PIN authentication',
    () async {
      final db = DatabaseHelper();
      final access = StaffAccess(db: db);
      await access.create(name: 'Asha', role: 'owner', pin: '1234');
      final initial = (await db.prepareCloudCatalogMutations(
        'shop-a',
      )).singleWhere((mutation) => mutation.entityType == 'staff');
      expect(initial.payload['role'], 'owner');
      expect(initial.payload['pinSalt'], hasLength(32));
      expect(initial.payload['pinHash'], hasLength(64));

      const remoteId = '77777777-7777-4777-8777-777777777777';
      await db.saveRemoteCloudCatalogChanges(
        remoteShopId: 'shop-a',
        page: CloudCatalogPage(
          cursor: 1,
          changes: [
            CloudCatalogChange(
              cursor: 1,
              entityType: 'staff',
              entityId: remoteId,
              mutationId: '88888888-8888-4888-8888-888888888888',
              baseRevision: 0,
              revision: 1,
              payload: {
                ...initial.payload,
                'syncId': remoteId,
                'name': 'Rafi',
                'role': 'cashier',
                'active': true,
              },
              deleted: false,
              changedAt: DateTime.utc(2026, 10, 27),
            ),
          ],
        ),
      );
      final applied = await db.applyPendingCloudCatalogChanges('shop-a');
      expect(applied.applied, 1);
      final remoteUser = (await access.list()).singleWhere(
        (staff) => staff.syncId == remoteId,
      );
      expect(remoteUser.role, 'cashier');
      expect(await access.authenticate(remoteUser.id!, '1234'), isNotNull);

      await db.insertProduct(
        Product(
          name: 'Tea',
          variants: [
            const ProductVariant(name: 'Box', barcode: '', price: 12, stock: 8),
          ],
        ),
      );
      final product = (await db.getAllProducts()).single;
      const saleEventId = '99999999-9999-4999-8999-999999999999';
      await db.saveRemoteSyncEvents(
        remoteShopId: 'shop-a',
        nextCursor: 1,
        events: [
          RemoteSyncEvent(
            cursor: 1,
            eventId: saleEventId,
            eventType: 'sale.created',
            entityId: 81,
            createdAt: DateTime.utc(2026, 10, 27),
            payload: {
              'idempotencyKey': saleEventId,
              'totalAmount': 12,
              'createdAt': '2026-10-27T00:00:00.000Z',
              'staffSyncId': remoteId,
              'items': [
                {
                  'productSyncId': product.syncId,
                  'variantSyncId': product.variants.single.syncId,
                  'productName': 'Tea',
                  'variantName': 'Box',
                  'unitPrice': 12,
                  'quantity': 1,
                },
              ],
            },
          ),
        ],
      );
      await db.applyPendingRemoteSyncEvents('shop-a');
      final importedSale = (await db.getAllSales()).single;
      expect(importedSale.staffId, remoteUser.id);
    },
  );

  test(
    'product images travel with catalog revisions and stay as local files',
    () async {
      final root = await Directory.systemTemp.createTemp('karbar-images');
      addTearDown(() async {
        ProductImageStorage.testDirectoryProvider = null;
        await root.delete(recursive: true);
      });
      ProductImageStorage.testDirectoryProvider = () async => root;
      final localImage = File('${root.path}/local.png');
      await localImage.writeAsBytes(
        img.encodePng(img.Image(width: 2, height: 2)),
      );
      final db = DatabaseHelper();
      await db.insertProduct(
        Product(
          name: 'Tea',
          imagePath: localImage.path,
          variants: [
            const ProductVariant(name: 'Box', barcode: '', price: 12, stock: 4),
          ],
        ),
      );
      final localProduct = (await db.prepareCloudCatalogMutations(
        'shop-a',
      )).singleWhere((mutation) => mutation.entityType == 'product');
      expect(localProduct.payload['imageData'], isA<String>());

      const productSyncId = 'abababab-abab-4bab-8bab-abababababab';
      const variantSyncId = 'cdcdcdcd-cdcd-4dcd-8dcd-cdcdcdcdcdcd';
      final payload = <String, Object?>{
        ...localProduct.payload,
        'syncId': productSyncId,
        'name': 'Remote tea',
        'variants': [
          {
            ...(localProduct.payload['variants'] as List).first
                as Map<String, Object?>,
            'syncId': variantSyncId,
          },
        ],
      };
      await db.saveRemoteCloudCatalogChanges(
        remoteShopId: 'shop-a',
        page: CloudCatalogPage(
          cursor: 1,
          changes: [
            CloudCatalogChange(
              cursor: 1,
              entityType: 'product',
              entityId: productSyncId,
              mutationId: 'efefefef-efef-4fef-8fef-efefefefefef',
              baseRevision: 0,
              revision: 1,
              payload: payload,
              deleted: false,
              changedAt: DateTime.utc(2026, 10, 27),
            ),
          ],
        ),
      );
      expect((await db.applyPendingCloudCatalogChanges('shop-a')).applied, 1);
      final remoteProduct = (await db.getAllProducts()).singleWhere(
        (product) => product.syncId == productSyncId,
      );
      expect(remoteProduct.name, 'Remote tea');
      expect(await File(remoteProduct.imagePath).exists(), isTrue);
      expect(
        img.decodeImage(await File(remoteProduct.imagePath).readAsBytes()),
        isNotNull,
      );
    },
  );

  test(
    'remote catalog creates product and variants without queuing an echo',
    () async {
      final db = DatabaseHelper();
      const productId = '11111111-1111-4111-8111-111111111111';
      const variantId = '33333333-3333-4333-8333-333333333333';
      final payload = <String, dynamic>{
        'syncId': productId,
        'name': 'Rice',
        'description': 'Local rice',
        'category': 'Grains',
        'brand': 'Farm',
        'sku': 'R-1',
        'unit': 'kg',
        'costPrice': 20.0,
        'lowStockAlert': 4,
        'quantityPrecision': 3,
        'createdAt': '2026-10-26T00:00:00.000Z',
        'variants': [
          {
            'syncId': variantId,
            'name': 'Loose',
            'barcode': '123',
            'price': 30.0,
            'stock': 5.0,
          },
        ],
      };
      await db.saveRemoteCloudCatalogChanges(
        remoteShopId: 'shop-a',
        page: CloudCatalogPage(
          cursor: 1,
          changes: [
            CloudCatalogChange(
              cursor: 1,
              entityType: 'product',
              entityId: productId,
              mutationId: '22222222-2222-4222-8222-222222222222',
              baseRevision: 0,
              revision: 1,
              payload: payload,
              deleted: false,
              changedAt: DateTime.utc(2026, 10, 26),
            ),
          ],
        ),
      );

      final result = await db.applyPendingCloudCatalogChanges('shop-a');

      expect(result.applied, 1);
      expect(result.conflicts, 0);
      final product = (await db.getAllProducts()).single;
      expect(product.syncId, productId);
      expect(product.variants.single.syncId, variantId);
      expect(product.variants.single.stock, 5);
      expect(await db.prepareCloudCatalogMutations('shop-a'), isEmpty);
      expect(await db.getUnappliedCloudCatalogChangeCount('shop-a'), 0);
    },
  );

  test(
    'shop settings sync as a conflict-aware shared catalog entity',
    () async {
      final db = DatabaseHelper();
      await db.saveAppSettings({
        'currency_symbol': '৳',
        'currency_locale': 'en_BD',
        'tax_rate': '5.0',
        'show_tax': 'true',
        'shop_name': 'Corner shop',
        'shop_phone': '01700000000',
        'shop_address': 'Dhaka',
        'setup_complete': 'true',
        'theme_mode': 'dark',
        'language': 'Bangla',
      });

      final outgoing = await db.prepareCloudCatalogMutations('shop-a');
      expect(outgoing, hasLength(1));
      expect(outgoing.single.entityType, 'settings');
      expect(outgoing.single.entityId, DatabaseHelper.cloudSettingsSyncId);
      expect(outgoing.single.payload['shopName'], 'Corner shop');
      expect(outgoing.single.payload['taxRate'], 5.0);
      expect(outgoing.single.payload.containsKey('theme_mode'), isFalse);
      expect(outgoing.single.payload.containsKey('language'), isFalse);

      final rawDb = await db.database;
      await rawDb.delete('app_settings');
      await rawDb.delete(
        'cloud_catalog_outbox',
        where: 'remote_shop_id = ?',
        whereArgs: ['shop-a'],
      );
      final payload = Map<String, Object?>.from(outgoing.single.payload);
      await db.saveRemoteCloudCatalogChanges(
        remoteShopId: 'shop-a',
        page: CloudCatalogPage(
          cursor: 1,
          changes: [
            CloudCatalogChange(
              cursor: 1,
              entityType: 'settings',
              entityId: DatabaseHelper.cloudSettingsSyncId,
              mutationId: '44444444-4444-4444-8444-444444444444',
              baseRevision: 0,
              revision: 1,
              payload: payload.cast<String, dynamic>(),
              deleted: false,
              changedAt: DateTime.utc(2026, 10, 27),
            ),
          ],
        ),
      );
      final applied = await db.applyPendingCloudCatalogChanges('shop-a');
      expect(applied.applied, 1);
      expect(applied.conflicts, 0);
      final settings = await db.getAppSettings();
      expect(settings['currency_symbol'], '৳');
      expect(settings['tax_rate'], '5.0');
      expect(settings['shop_name'], 'Corner shop');
      expect(settings['theme_mode'], isNull);
      expect(settings['language'], isNull);
      expect(await db.prepareCloudCatalogMutations('shop-a'), isEmpty);
    },
  );

  test(
    'supplier identities sync and history prevents remote deletion',
    () async {
      final db = DatabaseHelper();
      await db.saveSupplier(
        const Supplier(
          name: 'Local supplier',
          phone: '01700000000',
          address: 'Dhaka',
          notes: 'Weekly delivery',
        ),
      );
      final supplier = (await db.getSuppliers()).single;
      expect(supplier.syncId, isNotEmpty);
      final mutations = await db.prepareCloudCatalogMutations('shop-a');
      expect(mutations, hasLength(1));
      expect(mutations.single.entityType, 'supplier');
      expect(mutations.single.entityId, supplier.syncId);

      final rawDb = await db.database;
      await rawDb.delete('cloud_catalog_outbox');
      await rawDb.delete('suppliers');
      final supplierPayload = <String, Object?>{
        'syncId': supplier.syncId,
        'name': supplier.name,
        'phone': supplier.phone,
        'address': supplier.address,
        'notes': supplier.notes,
      };
      await db.saveRemoteCloudCatalogChanges(
        remoteShopId: 'shop-a',
        page: CloudCatalogPage(
          cursor: 1,
          changes: [
            CloudCatalogChange(
              cursor: 1,
              entityType: 'supplier',
              entityId: supplier.syncId!,
              mutationId: '55555555-5555-4555-8555-555555555555',
              baseRevision: 0,
              revision: 1,
              payload: supplierPayload.cast<String, dynamic>(),
              deleted: false,
              changedAt: DateTime.utc(2026, 10, 27),
            ),
          ],
        ),
      );
      final created = await db.applyPendingCloudCatalogChanges('shop-a');
      expect(created.applied, 1);
      final restoredSupplier = (await db.getSuppliers()).single;
      expect(restoredSupplier.syncId, supplier.syncId);
      expect(await db.prepareCloudCatalogMutations('shop-a'), isEmpty);

      await db.insertProduct(
        Product(
          name: 'Rice',
          variants: [
            const ProductVariant(name: 'Bag', barcode: '', price: 20, stock: 1),
          ],
        ),
      );
      final product = (await db.getAllProducts()).single;
      await db.recordPurchase(
        supplier: restoredSupplier,
        items: [
          PurchaseLine(
            variantId: product.variants.single.id!,
            productName: 'Rice',
            variantName: 'Bag',
            quantity: 1,
            costPrice: 10,
          ),
        ],
      );
      await db.saveRemoteCloudCatalogChanges(
        remoteShopId: 'shop-a',
        page: CloudCatalogPage(
          cursor: 2,
          changes: [
            CloudCatalogChange(
              cursor: 2,
              entityType: 'supplier',
              entityId: supplier.syncId!,
              mutationId: '66666666-6666-4666-8666-666666666666',
              baseRevision: 1,
              revision: 2,
              payload: supplierPayload.cast<String, dynamic>(),
              deleted: true,
              changedAt: DateTime.utc(2026, 10, 28),
            ),
          ],
        ),
      );
      final deletion = await db.applyPendingCloudCatalogChanges('shop-a');
      expect(deletion.applied, 0);
      expect(deletion.conflicts, 1);
      expect((await db.getSuppliers()).single.name, 'Local supplier');
    },
  );

  test(
    'remote catalog update conflicts with local edits instead of overwriting',
    () async {
      final db = DatabaseHelper();
      await db.insertProduct(
        Product(
          name: 'Tea',
          variants: [
            const ProductVariant(
              name: 'Pack',
              barcode: '',
              price: 10,
              stock: 4,
            ),
          ],
        ),
      );
      final product = (await db.getAllProducts()).single;
      final initial = (await db.prepareCloudCatalogMutations('shop-a')).single;
      await db.acknowledgeCloudCatalogMutation('shop-a', initial.mutationId, 1);
      await db.updateProduct(product.copyWith(name: 'Local tea'));
      final localAfterEdit = (await db.getAllProducts()).single;
      final remotePayload = Map<String, Object?>.from(initial.payload);
      remotePayload['name'] = 'Cloud tea';
      await db.saveRemoteCloudCatalogChanges(
        remoteShopId: 'shop-a',
        page: CloudCatalogPage(
          cursor: 1,
          changes: [
            CloudCatalogChange(
              cursor: 1,
              entityType: 'product',
              entityId: initial.entityId,
              mutationId: '44444444-4444-4444-8444-444444444444',
              baseRevision: 1,
              revision: 2,
              payload: remotePayload,
              deleted: false,
              changedAt: DateTime.utc(2026, 10, 27),
            ),
          ],
        ),
      );

      final result = await db.applyPendingCloudCatalogChanges('shop-a');

      expect(result.applied, 0);
      expect(result.conflicts, 1);
      expect((await db.getAllProducts()).single.name, localAfterEdit.name);
      expect(await db.getCloudCatalogConflictCount('shop-a'), 1);

      await db.resolveCloudCatalogConflict(
        remoteShopId: 'shop-a',
        cursor: 1,
        useRemote: false,
      );
      final rebased = (await db.prepareCloudCatalogMutations('shop-a')).single;
      expect(rebased.baseRevision, 2);
      expect(rebased.payload['name'], 'Local tea');
      expect(await db.getCloudCatalogConflictCount('shop-a'), 0);
    },
  );

  test('owner resolution can explicitly apply the cloud version', () async {
    final db = DatabaseHelper();
    await db.insertCustomer(
      Customer(
        name: 'Local name',
        phone: '01700000000',
        createdAt: DateTime(2026, 10, 26),
      ),
    );
    final customer = (await db.getAllCustomers()).single;
    final initial = (await db.prepareCloudCatalogMutations('shop-a')).single;
    await db.acknowledgeCloudCatalogMutation('shop-a', initial.mutationId, 1);
    final rawDb = await db.database;
    await rawDb.update(
      'customers',
      {'name': 'Unsynced edit'},
      where: 'id = ?',
      whereArgs: [customer.id],
    );
    final remotePayload = Map<String, Object?>.from(initial.payload)
      ..['name'] = 'Cloud name';
    await db.saveRemoteCloudCatalogChanges(
      remoteShopId: 'shop-a',
      page: CloudCatalogPage(
        cursor: 1,
        changes: [
          CloudCatalogChange(
            cursor: 1,
            entityType: 'customer',
            entityId: initial.entityId,
            mutationId: '55555555-5555-4555-8555-555555555555',
            baseRevision: 1,
            revision: 2,
            payload: remotePayload,
            deleted: false,
            changedAt: DateTime.utc(2026, 10, 27),
          ),
        ],
      ),
    );
    await db.applyPendingCloudCatalogChanges('shop-a');
    expect(await db.getCloudCatalogConflictCount('shop-a'), 1);

    await db.resolveCloudCatalogConflict(
      remoteShopId: 'shop-a',
      cursor: 1,
      useRemote: true,
    );

    expect((await db.getAllCustomers()).single.name, 'Cloud name');
    expect(await db.prepareCloudCatalogMutations('shop-a'), isEmpty);
    expect(await db.getCloudCatalogConflictCount('shop-a'), 0);
  });

  test(
    'remote product tombstone cannot erase product data used by sales',
    () async {
      final db = DatabaseHelper();
      await db.insertProduct(
        Product(
          name: 'Coffee',
          variants: [
            const ProductVariant(name: 'Jar', barcode: '', price: 90, stock: 2),
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
          totalAmount: 90,
          createdAt: DateTime(2026, 10, 26, 10),
        ),
      );
      final accepted = (await db.prepareCloudCatalogMutations('shop-a')).single;
      await db.acknowledgeCloudCatalogMutation(
        'shop-a',
        accepted.mutationId,
        1,
      );
      await db.saveRemoteCloudCatalogChanges(
        remoteShopId: 'shop-a',
        page: CloudCatalogPage(
          cursor: 1,
          changes: [
            CloudCatalogChange(
              cursor: 1,
              entityType: 'product',
              entityId: accepted.entityId,
              mutationId: '66666666-6666-4666-8666-666666666666',
              baseRevision: 1,
              revision: 2,
              payload: accepted.payload,
              deleted: true,
              changedAt: DateTime.utc(2026, 10, 27),
            ),
          ],
        ),
      );

      final result = await db.applyPendingCloudCatalogChanges('shop-a');

      expect(result.applied, 0);
      expect(result.conflicts, 1);
      expect((await db.getAllProducts()).single.syncId, accepted.entityId);
      expect((await db.getAllSales()), hasLength(1));
    },
  );

  test(
    'deleting a product with an unacknowledged create queues its tombstone next',
    () async {
      final db = DatabaseHelper();
      await db.insertProduct(
        Product(
          name: 'Milk',
          variants: [
            const ProductVariant(
              name: 'Bottle',
              barcode: '',
              price: 25,
              stock: 1,
            ),
          ],
        ),
      );
      final product = (await db.getAllProducts()).single;
      final create = (await db.prepareCloudCatalogMutations('shop-a')).single;
      await db.deleteProduct(product.id!);

      final stillPending = await db.prepareCloudCatalogMutations('shop-a');
      expect(stillPending, hasLength(1));
      expect(stillPending.single.mutationId, create.mutationId);
      expect(stillPending.single.deleted, isFalse);
      await db.acknowledgeCloudCatalogMutation('shop-a', create.mutationId, 1);
      final deletion = (await db.prepareCloudCatalogMutations('shop-a')).single;
      expect(deletion.deleted, isTrue);
      expect(deletion.baseRevision, 1);
    },
  );

  test(
    'sync sends in order, stops at failure, and retries idempotently',
    () async {
      final db = DatabaseHelper();
      await db.insertProduct(
        Product(
          name: 'Rice',
          variants: [
            const ProductVariant(name: 'Bag', barcode: '', price: 35, stock: 4),
          ],
        ),
      );
      final product = (await db.getAllProducts()).single;
      for (var index = 0; index < 2; index++) {
        await db.insertSale(
          Sale(
            items: [
              CartItem(
                product: product,
                variant: product.variants.single,
                quantity: 1,
              ),
            ],
            totalAmount: 35,
            createdAt: DateTime(2026, 10, 26, 10 + index),
          ),
        );
      }
      final transport = _FakeTransport()..failOnCall = 2;
      final sync = SyncService(db: db, transport: transport);

      final firstAttempt = await sync.syncPending(
        baseUrl: 'https://sync.example.test',
        accessToken: 'test-token',
      );

      expect(firstAttempt.sent, 1);
      expect(firstAttempt.pending, 1);
      expect(firstAttempt.error, contains('network unavailable'));
      final failedKey = (await db.getPendingSyncEvents()).single.idempotencyKey;
      transport.failOnCall = null;
      final retry = await sync.syncPending(
        baseUrl: 'https://sync.example.test',
        accessToken: 'test-token',
      );

      expect(retry.sent, 1);
      expect(retry.pending, 0);
      expect(transport.events.last.idempotencyKey, failedKey);
      expect(
        transport.events.where((event) => event.idempotencyKey == failedKey),
        hasLength(2),
      );
      expect(
        transport.endpoints.every((uri) => uri.path == '/v1/sync/events'),
        isTrue,
      );
      expect(transport.tokens, everyElement('test-token'));
    },
  );

  test('sync rejects insecure remote URLs and missing credentials', () async {
    final sync = SyncService(db: DatabaseHelper(), transport: _FakeTransport());
    await expectLater(
      sync.syncPending(
        baseUrl: 'http://sync.example.test',
        accessToken: 'token',
      ),
      throwsArgumentError,
    );
    await expectLater(
      sync.syncPending(baseUrl: 'https://sync.example.test', accessToken: ' '),
      throwsArgumentError,
    );
  });

  test(
    'baki collections and sale returns are queued with their transactions',
    () async {
      final db = DatabaseHelper();
      final customerId = await db.insertCustomer(
        Customer(name: 'Nila', createdAt: DateTime(2026, 10, 26)),
      );
      await db.insertProduct(
        Product(
          name: 'Soap',
          variants: [
            const ProductVariant(name: 'Bar', barcode: '', price: 10, stock: 2),
          ],
        ),
      );
      final product = (await db.getAllProducts()).single;
      final saleId = await db.insertSale(
        Sale(
          items: [
            CartItem(
              product: product,
              variant: product.variants.single,
              quantity: 2,
            ),
          ],
          totalAmount: 20,
          createdAt: DateTime(2026, 10, 26, 9),
          paymentType: 'baki',
          customerId: customerId,
          customerName: 'Nila',
        ),
      );
      final saleItemId =
          (await db.getAllSales()).single.items.single.saleItemId!;
      await db.createSaleReturn(
        saleId: saleId,
        quantitiesBySaleItemId: {saleItemId: 1},
        reason: 'Damaged',
        refundMethod: 'baki',
      );
      await db.insertBakiPayment(
        BakiPayment(
          customerId: customerId,
          amount: 10,
          paidAt: DateTime(2026, 10, 26, 11),
        ),
      );

      final eventTypes = (await db.getPendingSyncEvents())
          .map((event) => event.eventType)
          .toSet();
      expect(
        eventTypes,
        containsAll({'sale.created', 'sale.returned', 'baki.payment_recorded'}),
      );
      final queued = await db.getPendingSyncEvents();
      final returned =
          jsonDecode(
                queued
                    .singleWhere((event) => event.eventType == 'sale.returned')
                    .payloadJson,
              )
              as Map<String, dynamic>;
      final collection =
          jsonDecode(
                queued
                    .singleWhere(
                      (event) => event.eventType == 'baki.payment_recorded',
                    )
                    .payloadJson,
              )
              as Map<String, dynamic>;
      expect(returned['saleEventId'], isNotEmpty);
      expect(returned['lines'].single['productSyncId'], isNotEmpty);
      expect(returned['lines'].single['variantSyncId'], isNotEmpty);
      expect(collection['customerSyncId'], isNotEmpty);
    },
  );

  test(
    'remote events persist with an account-scoped cursor and dedupe',
    () async {
      final db = DatabaseHelper();
      final first = RemoteSyncEvent(
        cursor: 1,
        eventId: 'event-1',
        eventType: 'sale.created',
        entityId: 12,
        createdAt: DateTime.utc(2026, 10, 26),
        payload: {
          'totalAmount': 42,
          'items': [
            {'productName': 'Tea'},
          ],
        },
      );
      expect(await db.getRemoteSyncCursor('shop-a'), 0);

      expect(
        await db.saveRemoteSyncEvents(
          remoteShopId: 'shop-a',
          nextCursor: 1,
          events: [first],
        ),
        1,
      );
      expect(await db.getRemoteSyncCursor('shop-a'), 1);
      expect(await db.getRemoteSyncCursor('shop-b'), 0);
      final staged = await db.getUnappliedRemoteEvents('shop-a');
      expect(staged, hasLength(1));
      expect(staged.single['event_id'], 'event-1');
      expect(staged.single['payload_json'], contains('Tea'));

      expect(
        await db.saveRemoteSyncEvents(
          remoteShopId: 'shop-a',
          nextCursor: 1,
          events: [first],
        ),
        0,
      );
      await expectLater(
        db.saveRemoteSyncEvents(
          remoteShopId: 'shop-a',
          nextCursor: 0,
          events: const [],
        ),
        throwsStateError,
      );
    },
  );

  test('catalog records keep stable sync IDs across edits', () async {
    final db = DatabaseHelper();
    await db.insertProduct(
      Product(
        name: 'Oil',
        variants: [
          const ProductVariant(
            name: 'Bottle',
            barcode: 'OIL-1',
            price: 70,
            stock: 4,
          ),
        ],
      ),
    );
    final before = (await db.getAllProducts()).single;
    final productSyncId = before.syncId;
    final variantSyncId = before.variants.single.syncId;

    await db.updateProduct(
      Product(
        id: before.id,
        name: 'Cooking oil',
        variants: [
          ProductVariant(
            id: before.variants.single.id,
            name: 'Bottle',
            barcode: 'OIL-1',
            price: 72,
            stock: 4,
          ),
        ],
      ),
    );
    final after = (await db.getAllProducts()).single;
    expect(after.syncId, productSyncId);
    expect(after.variants.single.syncId, variantSyncId);

    final customerId = await db.insertCustomer(
      Customer(name: 'Nila', createdAt: DateTime(2026, 10, 26)),
    );
    final customer = (await db.getAllCustomers()).single;
    expect(customer.id, customerId);
    expect(customer.syncId, matches(RegExp(r'^[0-9a-f-]{36}$')));
  });

  test('version 9 backup restores catalog rows with new stable IDs', () async {
    final db = DatabaseHelper();
    await db.insertProduct(
      Product(
        name: 'Flour',
        variants: [
          const ProductVariant(name: 'Kg', barcode: 'F-1', price: 50, stock: 2),
        ],
      ),
    );
    await db.insertCustomer(
      Customer(name: 'Rafi', createdAt: DateTime(2026, 10, 26)),
    );
    await db.saveSupplier(const Supplier(name: 'Flour supplier'));
    final backup = BackupService(db: db);
    final legacy =
        jsonDecode(await backup.createBackupJson()) as Map<String, dynamic>;
    legacy['version'] = 9;
    final tables = legacy['tables'] as Map<String, dynamic>;
    for (final table in [
      'products',
      'product_variants',
      'customers',
      'suppliers',
    ]) {
      for (final row in tables[table] as List) {
        (row as Map<String, dynamic>).remove('sync_id');
      }
    }

    final archive = backup.decodeBackupJson(jsonEncode(legacy));
    await backup.restoreBackup(archive);

    expect((await db.getAllProducts()).single.syncId, isNotEmpty);
    expect(
      (await db.getAllProducts()).single.variants.single.syncId,
      isNotEmpty,
    );
    expect((await db.getAllCustomers()).single.syncId, isNotEmpty);
    expect((await db.getSuppliers()).single.syncId, isNotEmpty);
  });

  test('version 15 database upgrades to the inbox without losing rows', () async {
    final directory = await Directory.systemTemp.createTemp('karbar-sync-v15');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/legacy.db';
    final legacy = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 15,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE products (id INTEGER PRIMARY KEY, name TEXT)',
          );
          await db.execute(
            'CREATE TABLE product_variants (id INTEGER PRIMARY KEY, product_id INTEGER)',
          );
          await db.execute(
            'CREATE TABLE customers (id INTEGER PRIMARY KEY, name TEXT)',
          );
          await db.execute(
            'CREATE TABLE keep_me (id INTEGER PRIMARY KEY, value TEXT)',
          );
          await db.insert('products', {'id': 2, 'name': 'Legacy product'});
          await db.insert('product_variants', {'id': 3, 'product_id': 2});
          await db.insert('customers', {'id': 4, 'name': 'Legacy customer'});
          await db.insert('keep_me', {'id': 1, 'value': 'existing sale data'});
        },
      ),
    );
    await legacy.close();
    DatabaseHelper.setTestPath(path);
    await DatabaseHelper.resetForTesting();

    final upgraded = DatabaseHelper();
    expect(await upgraded.getRemoteSyncCursor('shop-a'), 0);
    final rows = await (await upgraded.database).query('keep_me');
    expect(rows.single['value'], 'existing sale data');
    final product = (await (await upgraded.database).query('products')).single;
    final variant = (await (await upgraded.database).query(
      'product_variants',
    )).single;
    final customer = (await (await upgraded.database).query(
      'customers',
    )).single;
    expect(product['sync_id'], isNotEmpty);
    expect(variant['sync_id'], isNotEmpty);
    expect(customer['sync_id'], isNotEmpty);
  });

  test(
    'version 23 database adds stable staff IDs without losing accounts',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'karbar-staff-v23',
      );
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}/legacy.db';
      final legacy = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 23,
          onCreate: (db, _) async {
            await db.execute('''CREATE TABLE staff_users (
              id INTEGER PRIMARY KEY, name TEXT NOT NULL, role TEXT NOT NULL,
              pin_salt TEXT NOT NULL, pin_hash TEXT NOT NULL, active INTEGER NOT NULL,
              created_at TEXT NOT NULL
            )''');
            await db.insert('staff_users', {
              'id': 3,
              'name': 'Existing owner',
              'role': 'owner',
              'pin_salt': 'a' * 32,
              'pin_hash': 'b' * 64,
              'active': 1,
              'created_at': '2026-01-01T00:00:00.000',
            });
          },
        ),
      );
      await legacy.close();
      DatabaseHelper.setTestPath(path);
      await DatabaseHelper.resetForTesting();
      final staff = (await DatabaseHelper().getStaffUsers()).single;
      expect(staff.id, 3);
      expect(staff.name, 'Existing owner');
      expect(staff.syncId, isNotEmpty);
    },
  );

  test(
    'version 22 database adds purchase origin IDs without losing history',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'karbar-purchase-v22',
      );
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}/legacy.db';
      final legacy = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 22,
          onCreate: (db, _) async {
            await db.execute('''CREATE TABLE purchases (
              id INTEGER PRIMARY KEY, supplier_id INTEGER, supplier_name TEXT NOT NULL,
              total_amount REAL NOT NULL, note TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL
            )''');
            await db.insert('purchases', {
              'id': 9,
              'supplier_name': 'Old supplier',
              'total_amount': 32,
              'note': 'legacy',
              'created_at': '2026-01-01T00:00:00.000',
            });
          },
        ),
      );
      await legacy.close();
      DatabaseHelper.setTestPath(path);
      await DatabaseHelper.resetForTesting();
      final rows = await (await DatabaseHelper().database).query('purchases');
      expect(rows, hasLength(1));
      expect(rows.single['id'], 9);
      expect(rows.single['origin_shop_id'], isNull);
      expect(rows.single['origin_event_id'], isNull);
    },
  );

  test(
    'version 21 database adds supplier sync IDs without losing suppliers',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'karbar-supplier-v21',
      );
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}/legacy.db';
      final legacy = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 21,
          onCreate: (db, _) async {
            await db.execute('''
            CREATE TABLE suppliers (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              phone TEXT NOT NULL DEFAULT '',
              address TEXT NOT NULL DEFAULT '',
              notes TEXT NOT NULL DEFAULT ''
            )
          ''');
            await db.insert('suppliers', {
              'id': 4,
              'name': 'Existing supplier',
              'phone': '01700000000',
            });
          },
        ),
      );
      await legacy.close();
      DatabaseHelper.setTestPath(path);
      await DatabaseHelper.resetForTesting();

      final suppliers = await DatabaseHelper().getSuppliers();
      expect(suppliers, hasLength(1));
      expect(suppliers.single.id, 4);
      expect(suppliers.single.name, 'Existing supplier');
      expect(suppliers.single.syncId, isNotEmpty);
    },
  );

  test('restoring business data resets device-specific pull state', () async {
    final db = DatabaseHelper();
    await db.saveRemoteCloudCatalogChanges(
      remoteShopId: 'shop-a',
      page: CloudCatalogPage(
        cursor: 1,
        changes: [
          CloudCatalogChange(
            cursor: 1,
            entityType: 'product',
            entityId: '11111111-1111-4111-8111-111111111111',
            mutationId: '22222222-2222-4222-8222-222222222222',
            baseRevision: 0,
            revision: 1,
            payload: const {
              'syncId': '11111111-1111-4111-8111-111111111111',
              'name': 'Rice',
            },
            deleted: false,
            changedAt: DateTime.utc(2026, 10, 26),
          ),
        ],
      ),
    );
    await db.saveRemoteSyncEvents(
      remoteShopId: 'shop-a',
      nextCursor: 1,
      events: [
        RemoteSyncEvent(
          cursor: 1,
          eventId: 'event-restore',
          eventType: 'sale.created',
          entityId: 1,
          createdAt: DateTime.utc(2026, 10, 26),
          payload: const {},
        ),
      ],
    );
    final backup = BackupService(db: db);
    final archive = backup.decodeBackupJson(await backup.createBackupJson());
    await backup.restoreBackup(archive);

    expect(await db.getRemoteSyncCursor('shop-a'), 0);
    expect(await db.getUnappliedRemoteEventCount('shop-a'), 0);
    expect(await db.getCloudCatalogCursor('shop-a'), 0);
    expect(await db.getUnappliedCloudCatalogChangeCount('shop-a'), 0);
  });
}

class _FakeTransport implements SyncTransport {
  final List<SyncOutboxEvent> events = [];
  final List<Uri> endpoints = [];
  final List<String> tokens = [];
  int? failOnCall;

  @override
  Future<void> send({
    required Uri endpoint,
    required String accessToken,
    required SyncOutboxEvent event,
  }) async {
    events.add(event);
    endpoints.add(endpoint);
    tokens.add(accessToken);
    if (failOnCall == events.length) throw Exception('network unavailable');
  }
}
