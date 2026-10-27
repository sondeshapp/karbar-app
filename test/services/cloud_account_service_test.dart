import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:m_pos/db/database_helper.dart';
import 'package:m_pos/models/cart_item.dart';
import 'package:m_pos/models/cloud_catalog.dart';
import 'package:m_pos/models/product.dart';
import 'package:m_pos/models/product_variant.dart';
import 'package:m_pos/models/sale.dart';
import 'package:m_pos/models/sync_outbox_event.dart';
import 'package:m_pos/models/supplier.dart';
import 'package:m_pos/models/remote_sync_event.dart';
import 'package:m_pos/services/cloud_account_service.dart';
import 'package:m_pos/services/cloud_sync_coordinator.dart';
import 'package:m_pos/services/sync_service.dart';
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

  test('login persists session and logout clears local credentials', () async {
    final tokens = _MemoryTokens();
    final api = _FakeAuthApi();
    final service = CloudAccountService(
      api: api,
      tokens: tokens,
      sync: SyncService(db: DatabaseHelper(), transport: _FakeTransport()),
    );

    await service.login(
      baseUrl: 'https://sync.example.test',
      phone: '01700000000',
      password: 'long-enough-password',
    );
    expect((await service.currentSession())?.refreshToken, 'refresh-1');

    await service.logout();
    expect(await service.currentSession(), isNull);
    expect(api.logoutCalls, 1);
  });

  test(
    'automatic sync is single-flight and applies catalog before events',
    () async {
      final db = DatabaseHelper();
      final tokens = _MemoryTokens()
        ..session = const CloudSession(
          baseUrl: 'https://sync.example.test',
          accessToken: 'access-1',
          refreshToken: 'refresh-1',
          remoteShopId: 'shop-a',
        );
      final api = _FakeAuthApi();
      final service = CloudAccountService(api: api, tokens: tokens, db: db);
      final coordinator = CloudSyncCoordinator(service: service);

      final first = coordinator.runOnce();
      final concurrent = coordinator.runOnce();
      expect(identical(first, concurrent), isTrue);
      final result = await first;

      expect(result.hasError, isFalse);
      expect(result.catalogPull?.received, 0);
      expect(result.transactionPull?.received, 0);
      expect(api.callOrder, ['catalog.pull', 'events.pull']);
      expect(coordinator.lastResult, same(result));
    },
  );

  test(
    '401 refresh retries the same queued event with rotated credentials',
    () async {
      final db = DatabaseHelper();
      await db.insertProduct(
        Product(
          name: 'Tea',
          variants: [
            const ProductVariant(
              name: 'Pack',
              barcode: '',
              price: 20,
              stock: 2,
            ),
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
          totalAmount: 20,
          createdAt: DateTime(2026, 10, 26, 10),
        ),
      );
      final tokens = _MemoryTokens()
        ..session = const CloudSession(
          baseUrl: 'https://sync.example.test',
          accessToken: 'expired',
          refreshToken: 'refresh-1',
        );
      final transport = _FakeTransport()..unauthorizedFirstCall = true;
      final api = _FakeAuthApi();
      final service = CloudAccountService(
        api: api,
        tokens: tokens,
        sync: SyncService(db: db, transport: transport),
      );

      final result = await service.syncPending();

      expect(result.sent, 1);
      expect(result.pending, 0);
      expect(transport.tokens, ['expired', 'access-2']);
      expect(
        transport.events[0].idempotencyKey,
        transport.events[1].idempotencyKey,
      );
      expect((await service.currentSession())?.refreshToken, 'refresh-2');
    },
  );

  test('production auth client rejects remote HTTP endpoints', () async {
    final api = IoCloudAuthApi();
    await expectLater(
      api.login(
        baseUrl: 'http://sync.example.test',
        phone: '01700000000',
        password: 'long-enough-password',
      ),
      throwsArgumentError,
    );
  });

  test('catalog feed accepts a shared settings change', () {
    final change = CloudCatalogChange.fromJson({
      'cursor': 1,
      'entityType': 'settings',
      'entityId': DatabaseHelper.cloudSettingsSyncId,
      'mutationId': '11111111-1111-4111-8111-111111111111',
      'baseRevision': 0,
      'revision': 1,
      'payload': {
        'syncId': DatabaseHelper.cloudSettingsSyncId,
        'name': 'Shop settings',
        'currencySymbol': '৳',
        'currencyLocale': 'en_BD',
        'taxRate': 0,
        'showTax': false,
        'shopName': 'Corner shop',
        'shopPhone': '',
        'shopAddress': '',
        'setupComplete': true,
      },
      'deleted': false,
      'changedAt': '2026-10-26T10:00:00Z',
    });
    expect(change.entityType, 'settings');
  });

  test(
    'HTTP feed client sends authenticated cursor request and parses page',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final captured = <HttpRequest>[];
      final subscription = server.listen((request) async {
        captured.add(request);
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'cursor': 4,
              'events': [
                {
                  'cursor': 4,
                  'eventId': 'event-4',
                  'eventType': 'sale.created',
                  'entityId': 44,
                  'createdAt': '2026-10-26T10:00:00Z',
                  'payload': {'totalAmount': 20},
                },
              ],
            }),
          );
        await request.response.close();
      });
      addTearDown(() async {
        await subscription.cancel();
        await server.close(force: true);
      });

      final page = await IoCloudAuthApi().fetchEvents(
        baseUrl: 'http://127.0.0.1:${server.port}',
        accessToken: 'access-token',
        after: 3,
      );

      expect(captured, hasLength(1));
      expect(captured.single.method, 'GET');
      expect(captured.single.uri.path, '/v1/sync/events');
      expect(captured.single.uri.queryParameters['after'], '3');
      expect(
        captured.single.headers.value(HttpHeaders.authorizationHeader),
        'Bearer access-token',
      );
      expect(page.cursor, 4);
      expect(page.events.single.eventId, 'event-4');
    },
  );

  test(
    'HTTP catalog client submits mutation and reads revisioned changes',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requests = <HttpRequest>[];
      final subscription = server.listen((request) async {
        requests.add(request);
        if (request.method == 'PUT') {
          final body = jsonDecode(await utf8.decoder.bind(request).join());
          expect(body['baseRevision'], 0);
          expect(body['entityType'], 'product');
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'accepted': true,
                'duplicate': false,
                'cursor': 1,
                'revision': 1,
              }),
            );
        } else {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'cursor': 1,
                'changes': [
                  {
                    'cursor': 1,
                    'entityType': 'product',
                    'entityId': '11111111-1111-4111-8111-111111111111',
                    'mutationId': '22222222-2222-4222-8222-222222222222',
                    'baseRevision': 0,
                    'revision': 1,
                    'payload': {
                      'syncId': '11111111-1111-4111-8111-111111111111',
                      'name': 'Tea',
                    },
                    'deleted': false,
                    'changedAt': '2026-10-26T10:00:00Z',
                  },
                ],
              }),
            );
        }
        await request.response.close();
      });
      addTearDown(() async {
        await subscription.cancel();
        await server.close(force: true);
      });
      final api = IoCloudAuthApi();
      final baseUrl = 'http://127.0.0.1:${server.port}';
      final mutation = await api.putCatalogEntity(
        baseUrl: baseUrl,
        accessToken: 'catalog-token',
        entityType: 'product',
        entityId: '11111111-1111-4111-8111-111111111111',
        mutationId: '22222222-2222-4222-8222-222222222222',
        baseRevision: 0,
        payload: const {
          'syncId': '11111111-1111-4111-8111-111111111111',
          'name': 'Tea',
        },
        deleted: false,
      );
      final page = await api.fetchCatalogChanges(
        baseUrl: baseUrl,
        accessToken: 'catalog-token',
        after: 0,
      );

      expect(mutation.revision, 1);
      expect(requests.map((request) => request.method), ['PUT', 'GET']);
      expect(requests.first.uri.path, '/v1/sync/catalog');
      expect(requests.last.uri.queryParameters['after'], '0');
      expect(
        requests.every(
          (request) =>
              request.headers.value(HttpHeaders.authorizationHeader) ==
              'Bearer catalog-token',
        ),
        isTrue,
      );
      expect(page.changes.single.payload['name'], 'Tea');
    },
  );

  test('catalog revision conflict details are retained', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen((request) async {
      request.response
        ..statusCode = HttpStatus.conflict
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'message': 'catalog revision conflict',
            'currentRevision': 3,
            'currentPayload': {'name': 'Updated'},
            'deleted': false,
          }),
        );
      await request.response.close();
    });
    addTearDown(() async {
      await subscription.cancel();
      await server.close(force: true);
    });
    try {
      await IoCloudAuthApi().putCatalogEntity(
        baseUrl: 'http://127.0.0.1:${server.port}',
        accessToken: 'token',
        entityType: 'product',
        entityId: '11111111-1111-4111-8111-111111111111',
        mutationId: '22222222-2222-4222-8222-222222222222',
        baseRevision: 1,
        payload: const {'name': 'Local'},
        deleted: false,
      );
      fail('Expected revision conflict');
    } on CloudApiException catch (error) {
      expect(error.statusCode, 409);
      expect(
        CatalogRevisionConflict.fromJson(error.details).currentRevision,
        3,
      );
      expect(error.details['currentPayload']['name'], 'Updated');
    }
  });

  test(
    'catalog upload refreshes once and retries with rotated token',
    () async {
      final tokens = _MemoryTokens()
        ..session = const CloudSession(
          baseUrl: 'https://sync.example.test',
          accessToken: 'expired',
          refreshToken: 'refresh-1',
        );
      final api = _FakeAuthApi()..unauthorizedFirstCatalogWrite = true;
      final service = CloudAccountService(api: api, tokens: tokens);

      final result = await service.putCatalogEntity(
        entityType: 'product',
        entityId: '11111111-1111-4111-8111-111111111111',
        mutationId: '22222222-2222-4222-8222-222222222222',
        baseRevision: 0,
        payload: const {
          'syncId': '11111111-1111-4111-8111-111111111111',
          'name': 'Tea',
        },
        deleted: false,
      );

      expect(result.revision, 1);
      expect(api.catalogTokens, ['expired', 'access-2']);
      expect((await tokens.read())?.refreshToken, 'refresh-2');
    },
  );

  test(
    'catalog sync uploads local products and acknowledges durable mutations',
    () async {
      final db = DatabaseHelper();
      await db.insertProduct(
        Product(
          name: 'Coffee',
          variants: [
            const ProductVariant(
              name: 'Jar',
              barcode: '555',
              price: 90,
              stock: 3,
            ),
          ],
        ),
      );
      final tokens = _MemoryTokens()
        ..session = const CloudSession(
          baseUrl: 'https://sync.example.test',
          accessToken: 'access-1',
          refreshToken: 'refresh-1',
          remoteShopId: 'shop-a',
        );
      final api = _FakeAuthApi();
      final service = CloudAccountService(api: api, tokens: tokens, db: db);

      final result = await service.syncCatalog();

      expect(result.sent, 1);
      expect(result.pending, 0);
      expect(api.catalogTokens, ['access-1']);
      expect(await db.prepareCloudCatalogMutations('shop-a'), isEmpty);
    },
  );

  test(
    'catalog sync uploads shared shop settings but not device preferences',
    () async {
      final db = DatabaseHelper();
      await db.saveAppSettings({
        'currency_symbol': '৳',
        'currency_locale': 'en_BD',
        'tax_rate': '5',
        'show_tax': 'true',
        'shop_name': 'Corner shop',
        'setup_complete': 'true',
        'theme_mode': 'dark',
        'language': 'Bangla',
      });
      final tokens = _MemoryTokens()
        ..session = const CloudSession(
          baseUrl: 'https://sync.example.test',
          accessToken: 'access-1',
          refreshToken: 'refresh-1',
          remoteShopId: 'shop-a',
        );
      final api = _FakeAuthApi();
      final service = CloudAccountService(api: api, tokens: tokens, db: db);

      final result = await service.syncCatalog();

      expect(result.sent, 1);
      expect(api.catalogEntityTypes, ['settings']);
      expect(await db.prepareCloudCatalogMutations('shop-a'), isEmpty);
    },
  );

  test('catalog sync uploads supplier records', () async {
    final db = DatabaseHelper();
    await db.saveSupplier(
      const Supplier(
        name: 'Rice wholesaler',
        phone: '01700000000',
        address: 'Dhaka',
        notes: 'Weekly delivery',
      ),
    );
    final tokens = _MemoryTokens()
      ..session = const CloudSession(
        baseUrl: 'https://sync.example.test',
        accessToken: 'access-1',
        refreshToken: 'refresh-1',
        remoteShopId: 'shop-a',
      );
    final api = _FakeAuthApi();
    final service = CloudAccountService(api: api, tokens: tokens, db: db);

    final result = await service.syncCatalog();

    expect(result.sent, 1);
    expect(api.catalogEntityTypes, ['supplier']);
    expect(await db.prepareCloudCatalogMutations('shop-a'), isEmpty);
  });

  test(
    '409 catalog writes persist a reviewable conflict and local choice rebases',
    () async {
      final db = DatabaseHelper();
      await db.insertProduct(
        Product(
          name: 'Coffee',
          variants: [
            const ProductVariant(name: 'Jar', barcode: '', price: 90, stock: 3),
          ],
        ),
      );
      final tokens = _MemoryTokens()
        ..session = const CloudSession(
          baseUrl: 'https://sync.example.test',
          accessToken: 'access-1',
          refreshToken: 'refresh-1',
          remoteShopId: 'shop-a',
        );
      final api = _FakeAuthApi()
        ..catalogWriteConflict = true
        ..catalogConflictDetails = {
          'message': 'A newer product revision exists.',
          'currentRevision': 1,
          'currentPayload': {
            'syncId': (await db.getAllProducts()).single.syncId,
            'name': 'Cloud coffee',
            'description': '',
            'category': '',
            'brand': '',
            'sku': '',
            'unit': 'pcs',
            'costPrice': 0,
            'lowStockAlert': 5,
            'quantityPrecision': 0,
            'createdAt': (await db.getAllProducts()).single.createdAt
                .toIso8601String(),
            'variants': [
              {
                'syncId':
                    (await db.getAllProducts()).single.variants.single.syncId,
                'name': 'Jar',
                'barcode': '',
                'price': 90,
                'stock': 3,
              },
            ],
          },
          'deleted': false,
        };
      final service = CloudAccountService(api: api, tokens: tokens, db: db);

      await expectLater(
        service.syncCatalog(),
        throwsA(isA<CloudApiException>()),
      );
      final conflicts = await service.getCatalogConflicts();
      expect(conflicts, hasLength(1));
      expect(conflicts.single.reason, 'A newer product revision exists.');

      await service.resolveCatalogConflict(
        cursor: conflicts.single.cursor,
        useRemote: false,
      );
      final rebased = (await db.prepareCloudCatalogMutations('shop-a')).single;
      expect(rebased.baseRevision, 1);
      expect(rebased.payload['name'], 'Coffee');
      expect(await db.getCloudCatalogConflictCount('shop-a'), 0);
    },
  );

  test('pull refreshes once then durably stages remote events', () async {
    final tokens = _MemoryTokens()
      ..session = const CloudSession(
        baseUrl: 'https://sync.example.test',
        accessToken: 'expired',
        refreshToken: 'refresh-1',
        remoteShopId: 'shop-a',
      );
    final api = _FakeAuthApi()
      ..unauthorizedFirstPull = true
      ..remotePage = RemoteSyncPage(
        cursor: 3,
        events: [
          RemoteSyncEvent(
            cursor: 3,
            eventId: 'remote-event-3',
            eventType: 'sale.created',
            entityId: 88,
            createdAt: DateTime.utc(2026, 10, 26),
            payload: const {'totalAmount': 55},
          ),
        ],
      );
    final service = CloudAccountService(
      api: api,
      tokens: tokens,
      db: DatabaseHelper(),
    );

    final pulled = await service.pullRemoteEvents();

    expect(api.pullTokens, ['expired', 'access-2']);
    expect(pulled.received, 1);
    expect(pulled.pending, 1);
    expect(pulled.cursor, 3);
    expect(await DatabaseHelper().getRemoteSyncCursor('shop-a'), 3);
  });

  test(
    'catalog pull refreshes once and stages changes with a durable cursor',
    () async {
      final tokens = _MemoryTokens()
        ..session = const CloudSession(
          baseUrl: 'https://sync.example.test',
          accessToken: 'expired',
          refreshToken: 'refresh-1',
          remoteShopId: 'shop-a',
        );
      final api = _FakeAuthApi()
        ..unauthorizedFirstCatalogPull = true
        ..catalogPage = CloudCatalogPage(
          cursor: 2,
          changes: [
            CloudCatalogChange(
              cursor: 2,
              entityType: 'customer',
              entityId: '11111111-1111-4111-8111-111111111111',
              mutationId: '22222222-2222-4222-8222-222222222222',
              baseRevision: 0,
              revision: 1,
              payload: const {
                'syncId': '11111111-1111-4111-8111-111111111111',
                'name': 'Nila',
                'phone': '01700000000',
                'createdAt': '2026-10-26T00:00:00.000Z',
              },
              deleted: false,
              changedAt: DateTime.utc(2026, 10, 26),
            ),
          ],
        );
      final service = CloudAccountService(
        api: api,
        tokens: tokens,
        db: DatabaseHelper(),
      );

      final pulled = await service.pullRemoteCatalog();

      expect(api.catalogPullTokens, ['expired', 'access-2']);
      expect(pulled.received, 1);
      expect(pulled.pending, 0);
      expect(pulled.applied, 1);
      expect(pulled.conflicts, 0);
      expect(pulled.cursor, 2);
      expect(await DatabaseHelper().getCloudCatalogCursor('shop-a'), 2);
      expect((await DatabaseHelper().getAllCustomers()).single.name, 'Nila');
    },
  );
}

class _MemoryTokens implements CloudTokenStore {
  CloudSession? session;

  @override
  Future<void> clear() async => session = null;

  @override
  Future<CloudSession?> read() async => session;

  @override
  Future<void> write(CloudSession value) async => session = value;
}

class _FakeAuthApi implements CloudAuthApi {
  int logoutCalls = 0;
  bool unauthorizedFirstPull = false;
  bool unauthorizedFirstCatalogWrite = false;
  bool unauthorizedFirstCatalogPull = false;
  bool catalogWriteConflict = false;
  Map<String, dynamic> catalogConflictDetails = const {};
  RemoteSyncPage remotePage = const RemoteSyncPage(cursor: 0, events: []);
  CloudCatalogPage catalogPage = const CloudCatalogPage(cursor: 0, changes: []);
  final List<String> pullTokens = [];
  final List<String> catalogTokens = [];
  final List<String> catalogEntityTypes = [];
  final List<String> catalogPullTokens = [];
  final List<String> callOrder = [];

  @override
  Future<CloudSession> login({
    required String baseUrl,
    required String phone,
    required String password,
  }) async => CloudSession(
    baseUrl: baseUrl,
    accessToken: 'access-1',
    refreshToken: 'refresh-1',
  );

  @override
  Future<CloudSession> refresh(CloudSession session) async => CloudSession(
    baseUrl: 'https://sync.example.test',
    accessToken: 'access-2',
    refreshToken: 'refresh-2',
    remoteShopId: session.remoteShopId,
  );

  @override
  Future<void> logout(CloudSession session) async => logoutCalls++;

  @override
  Future<RemoteSyncPage> fetchEvents({
    required String baseUrl,
    required String accessToken,
    required int after,
  }) async {
    callOrder.add('events.pull');
    pullTokens.add(accessToken);
    if (unauthorizedFirstPull && pullTokens.length == 1) {
      throw const CloudApiException(401, 'expired');
    }
    return remotePage;
  }

  @override
  Future<CatalogMutationResult> putCatalogEntity({
    required String baseUrl,
    required String accessToken,
    required String entityType,
    required String entityId,
    required String mutationId,
    required int baseRevision,
    required Map<String, Object?> payload,
    required bool deleted,
  }) async {
    catalogEntityTypes.add(entityType);
    catalogTokens.add(accessToken);
    if (catalogWriteConflict) {
      throw CloudApiException(
        409,
        catalogConflictDetails['message'] as String? ?? 'catalog conflict',
        catalogConflictDetails,
      );
    }
    if (unauthorizedFirstCatalogWrite && catalogTokens.length == 1) {
      throw const CloudApiException(401, 'expired');
    }
    return const CatalogMutationResult(
      duplicate: false,
      cursor: 1,
      revision: 1,
    );
  }

  @override
  Future<CloudCatalogPage> fetchCatalogChanges({
    required String baseUrl,
    required String accessToken,
    required int after,
  }) async {
    callOrder.add('catalog.pull');
    catalogPullTokens.add(accessToken);
    if (unauthorizedFirstCatalogPull && catalogPullTokens.length == 1) {
      throw const CloudApiException(401, 'expired');
    }
    return catalogPage;
  }

  @override
  Future<CloudSession> register({
    required String baseUrl,
    required String registrationCode,
    required String shopName,
    required String name,
    required String phone,
    required String password,
  }) async => CloudSession(
    baseUrl: baseUrl,
    accessToken: 'access-1',
    refreshToken: 'refresh-1',
  );
}

class _FakeTransport implements SyncTransport {
  final List<SyncOutboxEvent> events = [];
  final List<String> tokens = [];
  bool unauthorizedFirstCall = false;

  @override
  Future<void> send({
    required Uri endpoint,
    required String accessToken,
    required SyncOutboxEvent event,
  }) async {
    events.add(event);
    tokens.add(accessToken);
    if (unauthorizedFirstCall && events.length == 1) {
      throw const SyncHttpException(401);
    }
  }
}
