import 'dart:convert';
import 'dart:io';

import '../db/database_helper.dart';
import '../models/sync_outbox_event.dart';

abstract interface class SyncTransport {
  Future<void> send({
    required Uri endpoint,
    required String accessToken,
    required SyncOutboxEvent event,
  });
}

class SyncHttpException implements Exception {
  final int statusCode;

  const SyncHttpException(this.statusCode);

  @override
  String toString() => 'Sync server returned HTTP $statusCode.';
}

class IoSyncTransport implements SyncTransport {
  final HttpClient Function() _clientFactory;

  IoSyncTransport({HttpClient Function()? clientFactory})
    : _clientFactory = clientFactory ?? HttpClient.new;

  @override
  Future<void> send({
    required Uri endpoint,
    required String accessToken,
    required SyncOutboxEvent event,
  }) async {
    final client = _clientFactory();
    try {
      final request = await client
          .postUrl(endpoint)
          .timeout(const Duration(seconds: 15));
      request.headers.contentType = ContentType.json;
      request.followRedirects = false;
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $accessToken',
      );
      request.headers.set('Idempotency-Key', event.idempotencyKey);
      request.write(
        jsonEncode({
          'eventId': event.idempotencyKey,
          'eventType': event.eventType,
          'entityId': event.entityId,
          'createdAt': event.createdAt.toUtc().toIso8601String(),
          'payload': jsonDecode(event.payloadJson),
        }),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      await response.drain<void>();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw SyncHttpException(response.statusCode);
      }
    } finally {
      client.close(force: true);
    }
  }
}

class SyncResult {
  final int sent;
  final int pending;
  final String? error;

  const SyncResult({required this.sent, required this.pending, this.error});
}

class SyncService {
  final DatabaseHelper _db;
  final SyncTransport _transport;

  SyncService({DatabaseHelper? db, SyncTransport? transport})
    : _db = db ?? DatabaseHelper(),
      _transport = transport ?? IoSyncTransport();

  Future<SyncResult> syncPending({
    required String baseUrl,
    required String accessToken,
    Future<String> Function()? refreshAccessToken,
    int batchSize = 100,
  }) async {
    final token = accessToken.trim();
    if (token.isEmpty) throw ArgumentError('An access token is required.');
    if (batchSize < 1 || batchSize > 1000) {
      throw ArgumentError.value(batchSize, 'batchSize');
    }
    final endpoint = _endpoint(baseUrl);
    final events = await _db.getPendingSyncEvents(limit: batchSize);
    var sent = 0;
    String? error;
    for (final event in events) {
      try {
        var eventToken = token;
        try {
          await _transport.send(
            endpoint: endpoint,
            accessToken: eventToken,
            event: event,
          );
        } on SyncHttpException catch (caught) {
          if (caught.statusCode != 401 || refreshAccessToken == null) rethrow;
          eventToken = await refreshAccessToken();
          if (eventToken.trim().isEmpty) {
            throw StateError('The sync session could not be refreshed.');
          }
          await _transport.send(
            endpoint: endpoint,
            accessToken: eventToken,
            event: event,
          );
        }
        await _db.markSyncEventSent(event.idempotencyKey);
        sent++;
      } catch (caught) {
        error = caught.toString();
        await _db.markSyncEventFailed(event.idempotencyKey, error);
        break; // Preserve event order and retry from the first failure.
      }
    }
    return SyncResult(
      sent: sent,
      pending: await _db.getPendingSyncEventCount(),
      error: error,
    );
  }

  static Uri _endpoint(String baseUrl) {
    final base = Uri.tryParse(baseUrl.trim());
    if (base == null ||
        !base.hasAuthority ||
        base.host.isEmpty ||
        base.userInfo.isNotEmpty) {
      throw ArgumentError('Enter a valid sync server URL.');
    }
    final isLocalhost =
        base.host == 'localhost' ||
        base.host == '127.0.0.1' ||
        base.host == '::1';
    if (base.scheme != 'https' && !(base.scheme == 'http' && isLocalhost)) {
      throw ArgumentError('Sync requires HTTPS except for localhost testing.');
    }
    return base.replace(path: '/v1/sync/events', query: null, fragment: null);
  }
}
