import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../db/database_helper.dart';
import '../../providers/staff_provider.dart';
import '../../services/cloud_account_service.dart';
import '../../services/cloud_sync_coordinator.dart';
import 'cloud_catalog_conflicts_screen.dart';

class CloudSyncScreen extends ConsumerStatefulWidget {
  const CloudSyncScreen({super.key});

  @override
  ConsumerState<CloudSyncScreen> createState() => _CloudSyncScreenState();
}

class _CloudSyncScreenState extends ConsumerState<CloudSyncScreen> {
  final _formKey = GlobalKey<FormState>();
  final _url = TextEditingController(text: 'https://');
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _shopName = TextEditingController();
  final _name = TextEditingController();
  final _registrationCode = TextEditingController();
  final _service = CloudAccountService();
  bool _registering = false;
  bool _busy = false;
  CloudSession? _session;
  int _pending = 0;
  int _catalogPending = 0;
  int _remotePending = 0;
  int _remoteApplyErrors = 0;
  int _remoteCatalogPending = 0;
  int _remoteCatalogConflicts = 0;
  String? _status;
  bool _statusIsError = false;

  @override
  void initState() {
    super.initState();
    CloudSyncCoordinator.instance.resultChanges.addListener(
      _onSyncResultChanged,
    );
    _load();
  }

  void _onSyncResultChanged() {
    final result = CloudSyncCoordinator.instance.resultChanges.value;
    if (!mounted || result == null || result.skipped) return;
    setState(() {
      if (result.transactionUpload != null) {
        _pending = result.transactionUpload!.pending;
      }
      if (result.catalogUpload != null) {
        _catalogPending = result.catalogUpload!.pending;
      }
      if (result.transactionPull != null) {
        _remotePending = result.transactionPull!.pending;
        _remoteApplyErrors = result.transactionPull!.errors;
      }
      if (result.catalogPull != null) {
        _remoteCatalogPending = result.catalogPull!.pending;
        _remoteCatalogConflicts = result.catalogPull!.conflicts;
      }
      if (result.hasError) {
        _status = 'Cloud sync had an error: ${result.errors.join(' ')}';
        _statusIsError = true;
      } else {
        _status = 'Cloud sync completed.';
        _statusIsError = false;
      }
    });
  }

  @override
  void dispose() {
    CloudSyncCoordinator.instance.resultChanges.removeListener(
      _onSyncResultChanged,
    );
    _url.dispose();
    _phone.dispose();
    _password.dispose();
    _shopName.dispose();
    _name.dispose();
    _registrationCode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final session = await _service.currentSession();
      final pending = await DatabaseHelper().getPendingSyncEventCount();
      var catalogPending = 0;
      if (session != null && session.remoteShopId.isNotEmpty) {
        await DatabaseHelper().prepareCloudCatalogMutations(
          session.remoteShopId,
        );
        catalogPending = await DatabaseHelper()
            .getPendingCloudCatalogMutationCount(session.remoteShopId);
      }
      final remotePending = session == null || session.remoteShopId.isEmpty
          ? 0
          : await DatabaseHelper().getUnappliedRemoteEventCount(
              session.remoteShopId,
            );
      final remoteApplyErrors = session == null || session.remoteShopId.isEmpty
          ? 0
          : await DatabaseHelper().getRemoteSyncApplyErrorCount(
              session.remoteShopId,
            );
      final remoteCatalogPending =
          session == null || session.remoteShopId.isEmpty
          ? 0
          : await DatabaseHelper().getUnappliedCloudCatalogChangeCount(
              session.remoteShopId,
            );
      final remoteCatalogConflicts =
          session == null || session.remoteShopId.isEmpty
          ? 0
          : await DatabaseHelper().getCloudCatalogConflictCount(
              session.remoteShopId,
            );
      if (!mounted) return;
      setState(() {
        _session = session;
        _pending = pending;
        _catalogPending = catalogPending;
        _remotePending = remotePending;
        _remoteApplyErrors = remoteApplyErrors;
        _remoteCatalogPending = remoteCatalogPending;
        _remoteCatalogConflicts = remoteCatalogConflicts;
        if (session != null) _url.text = session.baseUrl;
      });
      final lastSync = CloudSyncCoordinator.instance.lastResult;
      if (lastSync?.hasError == true) {
        _setStatus(
          'Last cloud sync had an error: ${lastSync!.errors.join(' ')}',
          error: true,
        );
      }
    } catch (error) {
      _setStatus('Could not load cloud sync status: $error', error: true);
    }
  }

  Future<void> _connect() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      if (_registering) {
        await _service.register(
          baseUrl: _url.text,
          registrationCode: _registrationCode.text.trim(),
          shopName: _shopName.text.trim(),
          name: _name.text.trim(),
          phone: _phone.text.trim(),
          password: _password.text,
        );
      } else {
        await _service.login(
          baseUrl: _url.text,
          phone: _phone.text.trim(),
          password: _password.text,
        );
      }
      await _load();
      _setStatus('Signed in. Local sales remain available offline.');
      unawaited(CloudSyncCoordinator.instance.runOnce());
    } catch (error) {
      _setStatus(_readableError(error), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _syncNow() async {
    setState(() => _busy = true);
    try {
      final result = await CloudSyncCoordinator.instance.runOnce();
      if (!mounted) return;
      final upload = result.transactionUpload;
      final catalog = result.catalogUpload;
      final catalogPulled = result.catalogPull;
      final pulled = result.transactionPull;
      if (upload != null) setState(() => _pending = upload.pending);
      if (pulled != null) {
        setState(() {
          _remotePending = pulled.pending;
          _remoteApplyErrors = pulled.errors;
        });
      }
      if (catalog != null) setState(() => _catalogPending = catalog.pending);
      if (catalogPulled != null) {
        setState(() => _remoteCatalogPending = catalogPulled.pending);
        setState(() => _remoteCatalogConflicts = catalogPulled.conflicts);
      }
      if (result.skipped) {
        _setStatus('Sign in to sync this device with the shop.');
      } else if (result.hasError) {
        _setStatus(
          'Sync partially completed. ${result.errors.join(' ')}',
          error: true,
        );
      } else if ((pulled?.pending ?? 0) > 0 ||
          (catalogPulled?.pending ?? 0) > 0 ||
          (upload?.pending ?? 0) > 0 ||
          (catalog?.pending ?? 0) > 0) {
        _setStatus(
          'Sent ${upload?.sent ?? 0} transaction updates and synced ${catalog?.sent ?? 0} catalog records; '
          'downloaded ${pulled?.received ?? 0} transaction updates and '
          '${catalogPulled?.received ?? 0} catalog updates. '
          'Applied ${pulled?.applied ?? 0} transaction updates and '
          '${catalogPulled?.applied ?? 0} safe catalog updates. '
          '${catalogPulled?.conflicts ?? 0} catalog conflicts need review; '
          '${pulled?.errors ?? 0} transaction events need attention; '
          'other remote changes remain staged.',
        );
      } else {
        _setStatus(
          'Cloud sync is up to date. Sent ${upload?.sent ?? 0} transaction updates and '
          'synced ${catalog?.sent ?? 0} catalog records.',
        );
      }
    } catch (error) {
      _setStatus(_readableError(error), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    setState(() => _busy = true);
    try {
      await _service.logout();
      if (!mounted) return;
      setState(() => _session = null);
      _setStatus('Signed out. Unsent events remain on this device.');
    } catch (error) {
      await _load();
      _setStatus(_readableError(error), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _setStatus(String message, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _status = message;
      _statusIsError = error;
    });
  }

  String _readableError(Object error) =>
      error.toString().replaceFirst('Exception: ', '');

  @override
  Widget build(BuildContext context) {
    final isOwner = ref.watch(activeStaffProvider)?.isOwner == true;
    if (!isOwner) {
      return Scaffold(
        appBar: AppBar(title: const Text('Cloud sync')),
        body: const Center(child: Text('Owner access is required.')),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Cloud sync')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Keep this shop working offline. Cloud sync sends catalog changes, sales, returns, and baki collections when you connect.',
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Queued on this device: $_pending',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text('Catalog records queued: $_catalogPending'),
                  if (_session != null &&
                      _session!.remoteShopId.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text('Remote updates staged, not applied: $_remotePending'),
                    if (_remoteApplyErrors > 0)
                      Text(
                        'Remote updates with apply errors: $_remoteApplyErrors',
                      ),
                    Text(
                      'Catalog updates staged, not applied: $_remoteCatalogPending',
                    ),
                    if (_remoteCatalogConflicts > 0)
                      Text(
                        'Catalog conflicts needing review: $_remoteCatalogConflicts',
                      ),
                    if (_remoteCatalogConflicts > 0) ...[
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () => Navigator.of(context)
                                  .push(
                                    MaterialPageRoute<void>(
                                      builder: (_) =>
                                          CloudCatalogConflictsScreen(
                                            service: _service,
                                          ),
                                    ),
                                  )
                                  .then((_) => _load()),
                        icon: const Icon(Icons.rule),
                        label: const Text('Review conflicts'),
                      ),
                    ],
                  ],
                  const SizedBox(height: 6),
                  const Text(
                    'Queued data is not a cloud backup until the server accepts it. Safe catalog updates apply automatically; conflicts wait for review.',
                  ),
                  if (_session != null) ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _syncNow,
                        icon: const Icon(Icons.sync),
                        label: const Text('Sync now'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _status!,
                style: TextStyle(
                  color: _statusIsError
                      ? Theme.of(context).colorScheme.error
                      : null,
                ),
              ),
            ),
          if (_session == null)
            _buildConnectForm(context)
          else
            _buildAccountCard(context),
          if (_busy) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
          ],
        ],
      ),
    );
  }

  Widget _buildConnectForm(BuildContext context) => Form(
    key: _formKey,
    child: Column(
      children: [
        TextFormField(
          controller: _url,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(labelText: 'Cloud server URL'),
          validator: (value) => (value == null || value.trim().isEmpty)
              ? 'Enter the cloud server URL'
              : null,
        ),
        const SizedBox(height: 12),
        if (_registering) ...[
          TextFormField(
            controller: _shopName,
            decoration: const InputDecoration(labelText: 'Shop name'),
            validator: _required,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Owner name'),
            validator: _required,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _registrationCode,
            decoration: const InputDecoration(labelText: 'Registration code'),
            validator: _required,
          ),
          const SizedBox(height: 12),
        ],
        TextFormField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Phone number'),
          validator: _required,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _password,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Password (10+ characters)',
          ),
          validator: (value) => (value == null || value.length < 10)
              ? 'Use at least 10 characters'
              : null,
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _busy ? null : _connect,
            child: Text(_registering ? 'Create cloud account' : 'Sign in'),
          ),
        ),
        TextButton(
          onPressed: _busy
              ? null
              : () => setState(() => _registering = !_registering),
          child: Text(
            _registering
                ? 'I already have an account'
                : 'Create a cloud account',
          ),
        ),
      ],
    ),
  );

  Widget _buildAccountCard(BuildContext context) => Card(
    child: ListTile(
      leading: const Icon(Icons.cloud_done_outlined),
      title: const Text('Cloud account connected'),
      subtitle: Text(_session!.baseUrl),
      trailing: TextButton(
        onPressed: _busy ? null : _disconnect,
        child: const Text('Sign out'),
      ),
    ),
  );

  String? _required(String? value) =>
      (value == null || value.trim().isEmpty) ? 'Required' : null;
}
