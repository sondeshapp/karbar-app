import 'package:flutter/material.dart';

import '../../models/cloud_catalog.dart';
import '../../services/cloud_account_service.dart';

class CloudCatalogConflictsScreen extends StatefulWidget {
  final CloudAccountService service;

  const CloudCatalogConflictsScreen({super.key, required this.service});

  @override
  State<CloudCatalogConflictsScreen> createState() =>
      _CloudCatalogConflictsScreenState();
}

class _CloudCatalogConflictsScreenState
    extends State<CloudCatalogConflictsScreen> {
  List<CloudCatalogConflict> _conflicts = const [];
  bool _loading = true;
  int? _workingCursor;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final conflicts = await widget.service.getCatalogConflicts();
      if (!mounted) return;
      setState(() => _conflicts = conflicts);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resolve(
    CloudCatalogConflict conflict, {
    required bool useRemote,
  }) async {
    if (useRemote) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Use the downloaded version?'),
          content: const Text(
            'This replaces the local record with the cloud version. Historical records are kept. Products, customers, or suppliers referenced by history cannot be deleted automatically.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Use cloud version'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    setState(() => _workingCursor = conflict.cursor);
    try {
      await widget.service.resolveCatalogConflict(
        cursor: conflict.cursor,
        useRemote: useRemote,
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              useRemote
                  ? 'Cloud version applied.'
                  : 'Local version queued against the latest cloud revision.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _workingCursor = null);
    }
  }

  String _summary(Map<String, dynamic>? payload, String entityType) {
    if (payload == null) return 'Record is not on this device.';
    final name = payload['name'] as String? ?? 'Unnamed record';
    if (entityType == 'settings') {
      final shop = payload['shopName'] as String? ?? '';
      final currency = payload['currencySymbol'] as String? ?? '';
      final locale = payload['currencyLocale'] as String? ?? '';
      return [
        if (shop.isNotEmpty) shop,
        if (currency.isNotEmpty) '$currency ($locale)',
        'Tax ${payload['taxRate'] ?? 0}%',
      ].join(' · ');
    }
    if (entityType == 'supplier') {
      final phone = payload['phone'] as String? ?? '';
      return phone.isEmpty ? name : '$name · $phone';
    }
    if (entityType == 'staff') {
      final role = payload['role'] as String? ?? 'staff';
      final active = payload['active'] == true ? 'active' : 'inactive';
      return '$name · $role · $active';
    }
    if (entityType == 'product') {
      final variants = payload['variants'];
      final count = variants is List ? variants.length : 0;
      return '$name · $count variants';
    }
    final phone = payload['phone'] as String? ?? '';
    return phone.isEmpty ? name : '$name · $phone';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Cloud sync conflicts')),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_error!, textAlign: TextAlign.center),
            ),
          )
        : _conflicts.isEmpty
        ? const Center(child: Text('No catalog conflicts need review.'))
        : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _conflicts.length,
            itemBuilder: (context, index) {
              final conflict = _conflicts[index];
              final name =
                  conflict.payload['name'] as String? ?? conflict.entityId;
              final cloudSummary = conflict.deleted
                  ? 'Deleted'
                  : _summary(conflict.payload, conflict.entityType);
              final busy = _workingCursor == conflict.cursor;
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${switch (conflict.entityType) {
                          'product' => 'Product',
                          'customer' => 'Customer',
                          'supplier' => 'Supplier',
                          'staff' => 'Staff account',
                          _ => 'Shop settings',
                        }}: $name',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(conflict.reason),
                      const SizedBox(height: 4),
                      Text(
                        'This device: ${_summary(conflict.localPayload, conflict.entityType)}',
                      ),
                      Text(
                        'Cloud (revision ${conflict.revision}): $cloudSummary',
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton(
                            onPressed: busy
                                ? null
                                : () => _resolve(conflict, useRemote: false),
                            child: const Text('Keep this device'),
                          ),
                          FilledButton(
                            onPressed: busy
                                ? null
                                : () => _resolve(conflict, useRemote: true),
                            child: const Text('Use cloud version'),
                          ),
                        ],
                      ),
                      if (busy) const LinearProgressIndicator(),
                    ],
                  ),
                ),
              );
            },
          ),
  );
}
