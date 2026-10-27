import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m_pos/models/cloud_catalog.dart';
import 'package:m_pos/models/remote_sync_event.dart';
import 'package:m_pos/services/cloud_account_service.dart';
import 'package:m_pos/services/cloud_sync_coordinator.dart';

void main() {
  testWidgets('auto sync runs on launch, resume, and foreground interval', (
    tester,
  ) async {
    final tokens = _CountingTokens();
    final coordinator = CloudSyncCoordinator(
      service: CloudAccountService(api: _UnusedApi(), tokens: tokens),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CloudSyncLifecycle(
          coordinator: coordinator,
          interval: const Duration(seconds: 1),
          child: const SizedBox(),
        ),
      ),
    );
    await tester.pump();
    expect(tokens.readCalls, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    final pausedCount = tokens.readCalls;
    await tester.pump(const Duration(seconds: 1));
    expect(tokens.readCalls, pausedCount);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(tokens.readCalls, greaterThan(pausedCount));
    final resumedCount = tokens.readCalls;
    await tester.pump(const Duration(seconds: 1));
    expect(tokens.readCalls, greaterThan(resumedCount));

    await tester.pumpWidget(const SizedBox());
  });
}

class _CountingTokens implements CloudTokenStore {
  int readCalls = 0;

  @override
  Future<void> clear() async {}

  @override
  Future<CloudSession?> read() async {
    readCalls++;
    return null;
  }

  @override
  Future<void> write(CloudSession session) async {}
}

class _UnusedApi implements CloudAuthApi {
  @override
  Future<RemoteSyncPage> fetchEvents({
    required String baseUrl,
    required String accessToken,
    required int after,
  }) => throw UnimplementedError();

  @override
  Future<CloudCatalogPage> fetchCatalogChanges({
    required String baseUrl,
    required String accessToken,
    required int after,
  }) => throw UnimplementedError();

  @override
  Future<CloudSession> login({
    required String baseUrl,
    required String phone,
    required String password,
  }) => throw UnimplementedError();

  @override
  Future<void> logout(CloudSession session) => throw UnimplementedError();

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
  }) => throw UnimplementedError();

  @override
  Future<CloudSession> refresh(CloudSession session) =>
      throw UnimplementedError();

  @override
  Future<CloudSession> register({
    required String baseUrl,
    required String registrationCode,
    required String shopName,
    required String name,
    required String phone,
    required String password,
  }) => throw UnimplementedError();
}
