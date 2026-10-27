import 'package:flutter_test/flutter_test.dart';
import 'package:m_pos/services/background_sync.dart';
import 'package:m_pos/services/cloud_account_service.dart';
import 'package:m_pos/services/cloud_sync_coordinator.dart';

void main() {
  test('scheduled sync succeeds when no cloud account is configured', () async {
    final coordinator = CloudSyncCoordinator(
      service: CloudAccountService(tokens: _TokenStore()),
    );

    expect(await runScheduledCloudSync(coordinator), isTrue);
  });

  test('scheduled sync reports failures so Android can retry', () async {
    final coordinator = CloudSyncCoordinator(
      service: CloudAccountService(tokens: _FailingTokenStore()),
    );

    expect(await runScheduledCloudSync(coordinator), isFalse);
  });
}

class _TokenStore implements CloudTokenStore {
  @override
  Future<CloudSession?> read() async => null;

  @override
  Future<void> write(CloudSession session) async {}

  @override
  Future<void> clear() async {}
}

class _FailingTokenStore extends _TokenStore {
  @override
  Future<CloudSession?> read() async => throw StateError('storage unavailable');
}
