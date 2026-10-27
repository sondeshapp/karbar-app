import 'dart:async';

import 'package:flutter/material.dart';

import 'cloud_account_service.dart';
import 'sync_service.dart';

class CloudSyncRunResult {
  final bool skipped;
  final SyncResult? transactionUpload;
  final CatalogSyncResult? catalogUpload;
  final CatalogPullResult? catalogPull;
  final RemotePullResult? transactionPull;
  final List<String> errors;

  const CloudSyncRunResult({
    this.skipped = false,
    this.transactionUpload,
    this.catalogUpload,
    this.catalogPull,
    this.transactionPull,
    this.errors = const [],
  });

  bool get hasError => errors.isNotEmpty || transactionUpload?.error != null;
}

class CloudSyncCoordinator {
  static final CloudSyncCoordinator instance = CloudSyncCoordinator._(
    CloudAccountService(),
  );

  final CloudAccountService service;
  Future<CloudSyncRunResult>? _activeRun;
  CloudSyncRunResult? lastResult;
  final ValueNotifier<CloudSyncRunResult?> resultChanges = ValueNotifier(null);

  CloudSyncCoordinator({required this.service});

  CloudSyncCoordinator._(this.service);

  Future<CloudSyncRunResult> runOnce() {
    final active = _activeRun;
    if (active != null) return active;
    late final Future<CloudSyncRunResult> run;
    run = _run().whenComplete(() {
      if (identical(_activeRun, run)) _activeRun = null;
    });
    _activeRun = run;
    return run;
  }

  Future<CloudSyncRunResult> _run() async {
    final errors = <String>[];
    try {
      final session = await service.currentSession();
      if (session == null) {
        const result = CloudSyncRunResult(skipped: true);
        _publish(result);
        return result;
      }
      if (session.remoteShopId.isEmpty) {
        const result = CloudSyncRunResult(
          errors: ['Sign in again to finish setting up cloud sync.'],
        );
        _publish(result);
        return result;
      }
    } catch (error) {
      final result = CloudSyncRunResult(errors: [error.toString()]);
      _publish(result);
      return result;
    }
    SyncResult? transactionUpload;
    CatalogSyncResult? catalogUpload;
    CatalogPullResult? catalogPull;
    RemotePullResult? transactionPull;

    try {
      transactionUpload = await service.syncPending();
      if (transactionUpload.error != null) errors.add(transactionUpload.error!);
    } catch (error) {
      errors.add(error.toString());
    }
    try {
      catalogUpload = await service.syncCatalog();
    } catch (error) {
      errors.add(error.toString());
    }
    try {
      catalogPull = await service.pullRemoteCatalog();
    } catch (error) {
      errors.add(error.toString());
    }
    try {
      transactionPull = await service.pullRemoteEvents();
    } catch (error) {
      errors.add(error.toString());
    }
    final result = CloudSyncRunResult(
      transactionUpload: transactionUpload,
      catalogUpload: catalogUpload,
      catalogPull: catalogPull,
      transactionPull: transactionPull,
      errors: List.unmodifiable(errors),
    );
    _publish(result);
    return result;
  }

  void _publish(CloudSyncRunResult result) {
    lastResult = result;
    resultChanges.value = result;
  }
}

class CloudSyncLifecycle extends StatefulWidget {
  final Widget child;
  final CloudSyncCoordinator? coordinator;
  final Duration interval;

  const CloudSyncLifecycle({
    super.key,
    required this.child,
    this.coordinator,
    this.interval = const Duration(minutes: 5),
  });

  @override
  State<CloudSyncLifecycle> createState() => _CloudSyncLifecycleState();
}

class _CloudSyncLifecycleState extends State<CloudSyncLifecycle>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _foreground = false;

  CloudSyncCoordinator get _coordinator =>
      widget.coordinator ?? CloudSyncCoordinator.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    unawaited(_coordinator.runOnce());
    _timer = Timer.periodic(widget.interval, (_) {
      if (_foreground) unawaited(_coordinator.runOnce());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) unawaited(_coordinator.runOnce());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
