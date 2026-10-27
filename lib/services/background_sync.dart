import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import 'cloud_sync_coordinator.dart';

const backgroundSyncTaskName = 'com.karbar.pos.cloud_sync';
const backgroundSyncFrequency = Duration(hours: 12);

Future<bool> runScheduledCloudSync(CloudSyncCoordinator coordinator) async {
  try {
    final result = await coordinator.runOnce();
    return result.skipped || !result.hasError;
  } catch (error) {
    debugPrint('Background cloud sync failed: $error');
    return false;
  }
}

@pragma('vm:entry-point')
void backgroundSyncDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName != backgroundSyncTaskName &&
        taskName != Workmanager.iOSBackgroundTask) {
      return true;
    }
    return runScheduledCloudSync(CloudSyncCoordinator.instance);
  });
}

Future<void> initializeBackgroundSync() async {
  await Workmanager().initialize(backgroundSyncDispatcher);
  await Workmanager().registerPeriodicTask(
    backgroundSyncTaskName,
    backgroundSyncTaskName,
    frequency: backgroundSyncFrequency,
    existingWorkPolicy: ExistingWorkPolicy.keep,
    constraints: Constraints(networkType: NetworkType.connected),
  );
}
