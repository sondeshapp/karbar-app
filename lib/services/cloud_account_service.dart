import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../db/database_helper.dart';
import '../models/cloud_catalog.dart';
import '../models/remote_sync_event.dart';
import 'sync_service.dart';

class CloudSession {
  final String baseUrl;
  final String accessToken;
  final String refreshToken;
  final String remoteShopId;

  const CloudSession({
    required this.baseUrl,
    required this.accessToken,
    required this.refreshToken,
    this.remoteShopId = '',
  });

  CloudSession copyWith({
    String? accessToken,
    String? refreshToken,
    String? remoteShopId,
  }) => CloudSession(
    baseUrl: baseUrl,
    accessToken: accessToken ?? this.accessToken,
    refreshToken: refreshToken ?? this.refreshToken,
    remoteShopId: remoteShopId ?? this.remoteShopId,
  );
}

abstract interface class CloudTokenStore {
  Future<CloudSession?> read();
  Future<void> write(CloudSession session);
  Future<void> clear();
}

class SecureCloudTokenStore implements CloudTokenStore {
  final FlutterSecureStorage _storage;

  SecureCloudTokenStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _urlKey = 'karbar_cloud_url';
  static const _accessKey = 'karbar_cloud_access_token';
  static const _refreshKey = 'karbar_cloud_refresh_token';
  static const _shopKey = 'karbar_cloud_shop_id';

  @override
  Future<CloudSession?> read() async {
    final values = await Future.wait([
      _storage.read(key: _urlKey),
      _storage.read(key: _accessKey),
      _storage.read(key: _refreshKey),
      _storage.read(key: _shopKey),
    ]);
    if (values.take(3).any((value) => value == null || value.isEmpty)) {
      return null;
    }
    return CloudSession(
      baseUrl: values[0]!,
      accessToken: values[1]!,
      refreshToken: values[2]!,
      remoteShopId: values[3] ?? '',
    );
  }

  @override
  Future<void> write(CloudSession session) async {
    await Future.wait([
      _storage.write(key: _urlKey, value: session.baseUrl),
      _storage.write(key: _accessKey, value: session.accessToken),
      _storage.write(key: _refreshKey, value: session.refreshToken),
      _storage.write(key: _shopKey, value: session.remoteShopId),
    ]);
  }

  @override
  Future<void> clear() async {
    await Future.wait([
      _storage.delete(key: _urlKey),
      _storage.delete(key: _accessKey),
      _storage.delete(key: _refreshKey),
      _storage.delete(key: _shopKey),
    ]);
  }
}

abstract interface class CloudAuthApi {
  Future<CloudSession> login({
    required String baseUrl,
    required String phone,
    required String password,
  });

  Future<CloudSession> register({
    required String baseUrl,
    required String registrationCode,
    required String shopName,
    required String name,
    required String phone,
    required String password,
  });

  Future<CloudSession> refresh(CloudSession session);
  Future<void> logout(CloudSession session);
  Future<RemoteSyncPage> fetchEvents({
    required String baseUrl,
    required String accessToken,
    required int after,
  });
  Future<CatalogMutationResult> putCatalogEntity({
    required String baseUrl,
    required String accessToken,
    required String entityType,
    required String entityId,
    required String mutationId,
    required int baseRevision,
    required Map<String, Object?> payload,
    required bool deleted,
  });
  Future<CloudCatalogPage> fetchCatalogChanges({
    required String baseUrl,
    required String accessToken,
    required int after,
  });
}

class CloudApiException implements Exception {
  final int statusCode;
  final String message;
  final Map<String, dynamic> details;

  const CloudApiException(
    this.statusCode,
    this.message, [
    this.details = const {},
  ]);

  @override
  String toString() => message;
}

class IoCloudAuthApi implements CloudAuthApi {
  final HttpClient Function() _clientFactory;

  IoCloudAuthApi({HttpClient Function()? clientFactory})
    : _clientFactory = clientFactory ?? HttpClient.new;

  @override
  Future<CloudSession> login({
    required String baseUrl,
    required String phone,
    required String password,
  }) => _requestSession(
    baseUrl: baseUrl,
    path: '/v1/auth/login',
    body: {'phone': phone, 'password': password},
  );

  @override
  Future<CloudSession> register({
    required String baseUrl,
    required String registrationCode,
    required String shopName,
    required String name,
    required String phone,
    required String password,
  }) => _requestSession(
    baseUrl: baseUrl,
    path: '/v1/auth/register',
    body: {
      'shopName': shopName,
      'name': name,
      'phone': phone,
      'password': password,
    },
    headers: {'X-Registration-Code': registrationCode},
  );

  @override
  Future<CloudSession> refresh(CloudSession session) => _requestSession(
    baseUrl: session.baseUrl,
    path: '/v1/auth/refresh',
    body: {'refreshToken': session.refreshToken},
  );

  @override
  Future<void> logout(CloudSession session) async {
    await _request(
      baseUrl: session.baseUrl,
      path: '/v1/auth/logout',
      body: {'refreshToken': session.refreshToken},
    );
  }

  @override
  Future<RemoteSyncPage> fetchEvents({
    required String baseUrl,
    required String accessToken,
    required int after,
  }) async {
    final json = await _request(
      baseUrl: baseUrl,
      path: '/v1/sync/events',
      body: const {},
      method: 'GET',
      query: {'after': '$after'},
      bearer: accessToken,
    );
    return RemoteSyncPage.fromJson(json);
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
    final json = await _request(
      baseUrl: baseUrl,
      path: '/v1/sync/catalog',
      method: 'PUT',
      body: {
        'entityType': entityType,
        'entityId': entityId,
        'mutationId': mutationId,
        'baseRevision': baseRevision,
        'payload': payload,
        'deleted': deleted,
      },
      bearer: accessToken,
    );
    return CatalogMutationResult.fromJson(json);
  }

  @override
  Future<CloudCatalogPage> fetchCatalogChanges({
    required String baseUrl,
    required String accessToken,
    required int after,
  }) async {
    final json = await _request(
      baseUrl: baseUrl,
      path: '/v1/sync/catalog',
      body: const {},
      method: 'GET',
      query: {'after': '$after'},
      bearer: accessToken,
    );
    return CloudCatalogPage.fromJson(json);
  }

  Future<CloudSession> _requestSession({
    required String baseUrl,
    required String path,
    required Map<String, Object?> body,
    Map<String, String> headers = const {},
  }) async {
    final json = await _request(
      baseUrl: baseUrl,
      path: path,
      body: body,
      headers: headers,
    );
    final access = json['accessToken'];
    final refresh = json['refreshToken'];
    final user = json['user'];
    if (access is! String ||
        access.isEmpty ||
        refresh is! String ||
        refresh.isEmpty) {
      throw const FormatException('The server returned an invalid session.');
    }
    return CloudSession(
      baseUrl: _validatedBaseUrl(baseUrl).toString(),
      accessToken: access,
      refreshToken: refresh,
      remoteShopId: user is Map<String, dynamic>
          ? user['shopId'] as String? ?? ''
          : '',
    );
  }

  Future<Map<String, dynamic>> _request({
    required String baseUrl,
    required String path,
    required Map<String, Object?> body,
    Map<String, String> headers = const {},
    String method = 'POST',
    Map<String, String> query = const {},
    String? bearer,
  }) async {
    final base = _validatedBaseUrl(baseUrl);
    final client = _clientFactory();
    try {
      final endpoint = base.replace(
        path: path,
        queryParameters: query.isEmpty ? null : query,
      );
      final request = await (switch (method) {
        'GET' => client.getUrl(endpoint),
        'PUT' => client.putUrl(endpoint),
        'POST' => client.postUrl(endpoint),
        _ => throw ArgumentError.value(method, 'method'),
      }).timeout(const Duration(seconds: 15));
      if (method != 'GET') request.headers.contentType = ContentType.json;
      request.followRedirects = false;
      headers.forEach(request.headers.set);
      if (bearer != null) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearer');
      }
      if (method != 'GET') request.write(jsonEncode(body));
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      final contents = await utf8.decoder.bind(response).join();
      Map<String, dynamic> decoded = const {};
      if (contents.isNotEmpty) {
        final data = jsonDecode(contents);
        if (data is Map<String, dynamic>) decoded = data;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message =
            (decoded['message'] as String?) ??
            'Cloud server returned HTTP ${response.statusCode}.';
        throw CloudApiException(response.statusCode, message, decoded);
      }
      return decoded;
    } finally {
      client.close(force: true);
    }
  }
}

Uri _validatedBaseUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    throw ArgumentError('Enter a valid cloud server URL.');
  }
  final local =
      uri.host == 'localhost' || uri.host == '127.0.0.1' || uri.host == '::1';
  if (uri.scheme != 'https' && !(uri.scheme == 'http' && local)) {
    throw ArgumentError(
      'Cloud sync requires HTTPS except for localhost testing.',
    );
  }
  return uri.replace(path: '', query: null, fragment: null);
}

class CloudAccountService {
  final CloudAuthApi _api;
  final CloudTokenStore _tokens;
  final SyncService _sync;
  final DatabaseHelper _db;

  CloudAccountService({
    CloudAuthApi? api,
    CloudTokenStore? tokens,
    SyncService? sync,
    DatabaseHelper? db,
  }) : _api = api ?? IoCloudAuthApi(),
       _tokens = tokens ?? SecureCloudTokenStore(),
       _sync = sync ?? SyncService(),
       _db = db ?? DatabaseHelper();

  Future<CloudSession?> currentSession() => _tokens.read();

  Future<void> login({
    required String baseUrl,
    required String phone,
    required String password,
  }) async {
    final session = await _api.login(
      baseUrl: baseUrl,
      phone: phone,
      password: password,
    );
    await _tokens.write(session);
  }

  Future<void> register({
    required String baseUrl,
    required String registrationCode,
    required String shopName,
    required String name,
    required String phone,
    required String password,
  }) async {
    final session = await _api.register(
      baseUrl: baseUrl,
      registrationCode: registrationCode,
      shopName: shopName,
      name: name,
      phone: phone,
      password: password,
    );
    await _tokens.write(session);
  }

  Future<SyncResult> syncPending() async {
    final currentSession = await _tokens.read();
    if (currentSession == null) throw StateError('Sign in before syncing.');
    var session = currentSession;
    return _sync.syncPending(
      baseUrl: session.baseUrl,
      accessToken: session.accessToken,
      refreshAccessToken: () async {
        session = await _api.refresh(session);
        await _tokens.write(session);
        return session.accessToken;
      },
    );
  }

  Future<CatalogSyncResult> syncCatalog() async {
    final currentSession = await _tokens.read();
    if (currentSession == null) throw StateError('Sign in before syncing.');
    var session = currentSession;
    if (session.remoteShopId.isEmpty) {
      throw StateError('Sign in again to sync this shop catalog.');
    }
    var sent = 0;
    while (sent < 500) {
      final mutations = await _db.prepareCloudCatalogMutations(
        session.remoteShopId,
      );
      if (mutations.isEmpty) break;
      for (final mutation in mutations) {
        Future<CatalogMutationResult> send() => _api.putCatalogEntity(
          baseUrl: session.baseUrl,
          accessToken: session.accessToken,
          entityType: mutation.entityType,
          entityId: mutation.entityId,
          mutationId: mutation.mutationId,
          baseRevision: mutation.baseRevision,
          payload: mutation.payload,
          deleted: mutation.deleted,
        );
        Future<CatalogMutationResult> sendWithRefresh() async {
          try {
            return await send();
          } on CloudApiException catch (error) {
            if (error.statusCode != 401) rethrow;
            session = await _api.refresh(session);
            await _tokens.write(session);
            return send();
          }
        }

        CatalogMutationResult accepted;
        try {
          accepted = await sendWithRefresh();
        } on CloudApiException catch (error) {
          if (error.statusCode == 409) {
            await _db.recordCloudCatalogWriteConflict(
              remoteShopId: session.remoteShopId,
              mutation: mutation,
              details: error.details,
            );
          }
          rethrow;
        }
        await _db.acknowledgeCloudCatalogMutation(
          session.remoteShopId,
          mutation.mutationId,
          accepted.revision,
        );
        sent++;
        if (sent >= 500) break;
      }
    }
    return CatalogSyncResult(
      sent: sent,
      pending: await _db.getPendingCloudCatalogMutationCount(
        session.remoteShopId,
      ),
    );
  }

  Future<RemotePullResult> pullRemoteEvents() async {
    final currentSession = await _tokens.read();
    if (currentSession == null) throw StateError('Sign in before syncing.');
    var session = currentSession;
    if (session.remoteShopId.isEmpty) {
      throw StateError('Sign in again to download shop updates.');
    }
    final after = await _db.getRemoteSyncCursor(session.remoteShopId);
    Future<RemoteSyncPage> fetch() => _api.fetchEvents(
      baseUrl: session.baseUrl,
      accessToken: session.accessToken,
      after: after,
    );
    late RemoteSyncPage page;
    try {
      page = await fetch();
    } on CloudApiException catch (error) {
      if (error.statusCode != 401) rethrow;
      session = await _api.refresh(session);
      await _tokens.write(session);
      page = await fetch();
    }
    final received = await _db.saveRemoteSyncEvents(
      remoteShopId: session.remoteShopId,
      nextCursor: page.cursor,
      events: page.events,
    );
    final application = await _db.applyPendingRemoteSyncEvents(
      session.remoteShopId,
    );
    return RemotePullResult(
      received: received,
      applied: application.applied,
      pending: application.pending,
      errors: application.errors,
      cursor: page.cursor,
      hasMore: page.events.length == 500,
    );
  }

  Future<CatalogPullResult> pullRemoteCatalog() async {
    final currentSession = await _tokens.read();
    if (currentSession == null) throw StateError('Sign in before syncing.');
    var session = currentSession;
    if (session.remoteShopId.isEmpty) {
      throw StateError('Sign in again to download shop catalog updates.');
    }
    final after = await _db.getCloudCatalogCursor(session.remoteShopId);
    Future<CloudCatalogPage> fetch() => _api.fetchCatalogChanges(
      baseUrl: session.baseUrl,
      accessToken: session.accessToken,
      after: after,
    );
    late CloudCatalogPage page;
    try {
      page = await fetch();
    } on CloudApiException catch (error) {
      if (error.statusCode != 401) rethrow;
      session = await _api.refresh(session);
      await _tokens.write(session);
      page = await fetch();
    }
    final received = await _db.saveRemoteCloudCatalogChanges(
      remoteShopId: session.remoteShopId,
      page: page,
    );
    final applied = await _db.applyPendingCloudCatalogChanges(
      session.remoteShopId,
    );
    return CatalogPullResult(
      received: received,
      pending: await _db.getUnappliedCloudCatalogChangeCount(
        session.remoteShopId,
      ),
      applied: applied.applied,
      conflicts: await _db.getCloudCatalogConflictCount(session.remoteShopId),
      cursor: page.cursor,
      hasMore: page.changes.length == 500,
    );
  }

  Future<List<CloudCatalogConflict>> getCatalogConflicts() async {
    final session = await _tokens.read();
    if (session == null || session.remoteShopId.isEmpty) {
      throw StateError('Sign in before reviewing catalog conflicts.');
    }
    return _db.getCloudCatalogConflicts(session.remoteShopId);
  }

  Future<void> resolveCatalogConflict({
    required int cursor,
    required bool useRemote,
  }) async {
    final session = await _tokens.read();
    if (session == null || session.remoteShopId.isEmpty) {
      throw StateError('Sign in before resolving catalog conflicts.');
    }
    await _db.resolveCloudCatalogConflict(
      remoteShopId: session.remoteShopId,
      cursor: cursor,
      useRemote: useRemote,
    );
  }

  Future<CatalogMutationResult> putCatalogEntity({
    required String entityType,
    required String entityId,
    required String mutationId,
    required int baseRevision,
    required Map<String, Object?> payload,
    required bool deleted,
  }) async {
    final currentSession = await _tokens.read();
    if (currentSession == null) throw StateError('Sign in before syncing.');
    var session = currentSession;
    Future<CatalogMutationResult> send() => _api.putCatalogEntity(
      baseUrl: session.baseUrl,
      accessToken: session.accessToken,
      entityType: entityType,
      entityId: entityId,
      mutationId: mutationId,
      baseRevision: baseRevision,
      payload: payload,
      deleted: deleted,
    );
    try {
      return await send();
    } on CloudApiException catch (error) {
      if (error.statusCode != 401) rethrow;
      session = await _api.refresh(session);
      await _tokens.write(session);
      return send();
    }
  }

  Future<CloudCatalogPage> fetchCatalogChanges({required int after}) async {
    final currentSession = await _tokens.read();
    if (currentSession == null) throw StateError('Sign in before syncing.');
    var session = currentSession;
    Future<CloudCatalogPage> fetch() => _api.fetchCatalogChanges(
      baseUrl: session.baseUrl,
      accessToken: session.accessToken,
      after: after,
    );
    try {
      return await fetch();
    } on CloudApiException catch (error) {
      if (error.statusCode != 401) rethrow;
      session = await _api.refresh(session);
      await _tokens.write(session);
      return fetch();
    }
  }

  Future<void> logout() async {
    final session = await _tokens.read();
    if (session == null) return;
    try {
      await _api.logout(session);
    } finally {
      await _tokens.clear();
    }
  }
}

class CatalogSyncResult {
  final int sent;
  final int pending;

  const CatalogSyncResult({required this.sent, required this.pending});
}

class CatalogPullResult {
  final int received;
  final int pending;
  final int applied;
  final int conflicts;
  final int cursor;
  final bool hasMore;

  const CatalogPullResult({
    required this.received,
    required this.pending,
    required this.applied,
    required this.conflicts,
    required this.cursor,
    required this.hasMore,
  });
}

class RemotePullResult {
  final int received;
  final int applied;
  final int pending;
  final int errors;
  final int cursor;
  final bool hasMore;

  const RemotePullResult({
    required this.received,
    required this.applied,
    required this.pending,
    required this.errors,
    required this.cursor,
    required this.hasMore,
  });
}
