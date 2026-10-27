import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/app_strings.dart';
import '../../providers/baki_provider.dart';
import '../../providers/dashboard_provider.dart';
import '../../providers/sales_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/staff_provider.dart';
import '../../providers/warehouse_provider.dart';
import '../../services/backup_service.dart';

class BackupRestoreScreen extends ConsumerStatefulWidget {
  const BackupRestoreScreen({super.key});

  @override
  ConsumerState<BackupRestoreScreen> createState() =>
      _BackupRestoreScreenState();
}

class _BackupRestoreScreenState extends ConsumerState<BackupRestoreScreen> {
  final _backupService = BackupService();
  bool _busy = false;

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _exportBackup(AppStrings s) async {
    setState(() => _busy = true);
    try {
      final contents = await _backupService.createBackupJson();
      final filename =
          'karbar_backup_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.json';

      if (Platform.isAndroid || Platform.isIOS) {
        final directory = await getTemporaryDirectory();
        final file = File(p.join(directory.path, filename));
        await file.writeAsString(contents, flush: true);
        await SharePlus.instance.share(
          ShareParams(
            title: s.backupFileTitle,
            files: [XFile(file.path, mimeType: 'application/json')],
            fileNameOverrides: [filename],
          ),
        );
        _showMessage(s.backupShareOpened);
      } else {
        final location = await getSaveLocation(
          suggestedName: filename,
          acceptedTypeGroups: const [
            XTypeGroup(
              label: 'Karbar backup',
              extensions: ['json'],
              mimeTypes: ['application/json'],
              uniformTypeIdentifiers: ['public.json'],
            ),
          ],
        );
        if (location == null) return;
        await XFile.fromData(
          Uint8List.fromList(utf8.encode(contents)),
          name: filename,
          mimeType: 'application/json',
        ).saveTo(location.path);
        _showMessage(s.backupSaved);
      }
    } catch (_) {
      _showMessage(s.backupFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importBackup(AppStrings s) async {
    try {
      final selected = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'Karbar backup',
            extensions: ['json'],
            mimeTypes: ['application/json'],
            uniformTypeIdentifiers: ['public.json'],
          ),
        ],
      );
      if (selected == null || !mounted) return;

      final archive = _backupService.decodeBackupJson(
        await selected.readAsString(),
      );
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(s.restoreBackupTitle),
          content: Text(
            s.restoreBackupBody(
              DateFormat.yMMMd().add_jm().format(archive.createdAt.toLocal()),
              archive.productCount,
              archive.saleCount,
              archive.customerCount,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(s.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(s.restoreAndReplace),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;

      setState(() => _busy = true);
      await _backupService.restoreBackup(archive);
      await ref.read(settingsProvider.notifier).load();
      await ref.read(salesProvider.notifier).loadSales();
      await ref.read(warehouseProvider.notifier).loadProducts();
      ref.read(bakiRefreshProvider.notifier).state++;
      ref.invalidate(bakiSummaryProvider);
      ref.invalidate(dashboardProvider);
      _showMessage(s.restoreBackupSuccess);
      ref.read(activeStaffProvider.notifier).state = null;
      if (mounted) context.go('/');
    } on FormatException catch (error) {
      _showMessage(error.message.toString());
    } catch (_) {
      _showMessage(s.restoreBackupFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1E293B) : Colors.white;

    return Scaffold(
      appBar: AppBar(title: Text(s.backupAndRestore)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: cardColor,
            child: ListTile(
              key: const Key('export-backup-tile'),
              leading: const Icon(Icons.upload_file_rounded),
              title: Text(s.createBackup),
              subtitle: Text(s.createBackupDescription),
              trailing: _busy
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chevron_right_rounded),
              onTap: _busy ? null : () => _exportBackup(s),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            color: cardColor,
            child: ListTile(
              key: const Key('restore-backup-tile'),
              leading: const Icon(Icons.restore_rounded),
              title: Text(s.restoreBackup),
              subtitle: Text(s.restoreBackupDescription),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: _busy ? null : () => _importBackup(s),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              s.restoreReplacesDataNote,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
