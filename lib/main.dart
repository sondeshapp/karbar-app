import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'providers/settings_provider.dart';
import 'services/cloud_sync_coordinator.dart';
import 'services/background_sync.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await initializeBackgroundSync();
  } catch (error) {
    debugPrint('Background sync scheduling unavailable: $error');
  }
  final container = ProviderContainer();
  await container.read(settingsProvider.notifier).load();
  CloudSyncCoordinator.instance.resultChanges.addListener(() {
    if ((CloudSyncCoordinator
                .instance
                .resultChanges
                .value
                ?.catalogPull
                ?.applied ??
            0) >
        0) {
      unawaited(container.read(settingsProvider.notifier).load());
    }
  });
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const CloudSyncLifecycle(child: MyApp()),
    ),
  );
}
