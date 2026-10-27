import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../db/database_helper.dart';

class BackupArchive {
  final DateTime createdAt;
  final Map<String, List<Map<String, Object?>>> tables;
  final Map<int, ProductImageAsset> productImages;

  const BackupArchive({
    required this.createdAt,
    required this.tables,
    required this.productImages,
  });

  int get productCount => tables['products']!.length;
  int get saleCount => tables['sales']!.length;
  int get customerCount => tables['customers']!.length;
}

class ProductImageAsset {
  final String extension;
  final Uint8List bytes;

  const ProductImageAsset({required this.extension, required this.bytes});
}

class BackupService {
  static const formatName = 'karbar-pos-backup';
  static const formatVersion = 13;

  final DatabaseHelper _db;
  final Future<Directory> Function()? documentsDirectoryProvider;

  BackupService({DatabaseHelper? db, this.documentsDirectoryProvider})
    : _db = db ?? DatabaseHelper();

  Future<String> createBackupJson() async {
    final tables = await _db.exportBackupTables();
    final images = <String, Map<String, String>>{};
    for (final row in tables['products']!) {
      final imagePath = row['image_path'] as String? ?? '';
      row['image_path'] = '';
      final id = row['id'];
      if (imagePath.isEmpty || id is! int) continue;
      try {
        final file = File(imagePath);
        if (!await file.exists()) continue;
        images['$id'] = {
          'extension': p.extension(imagePath),
          'data': base64Encode(await file.readAsBytes()),
        };
      } on FileSystemException {
        // Keep the product in the backup even if its optional image is missing.
      }
    }
    return jsonEncode({
      'format': formatName,
      'version': formatVersion,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'tables': tables,
      'assets': {'productImages': images},
    });
  }

  BackupArchive decodeBackupJson(String contents) {
    final Object? decoded;
    try {
      decoded = jsonDecode(contents);
    } on FormatException {
      throw const FormatException('The selected file is not valid JSON.');
    }
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != formatName ||
        (decoded['version'] != 1 &&
            decoded['version'] != 2 &&
            decoded['version'] != 3 &&
            decoded['version'] != 4 &&
            decoded['version'] != 5 &&
            decoded['version'] != 6 &&
            decoded['version'] != 7 &&
            decoded['version'] != 8 &&
            decoded['version'] != 9 &&
            decoded['version'] != 10 &&
            decoded['version'] != 11 &&
            decoded['version'] != 12 &&
            decoded['version'] != formatVersion)) {
      throw const FormatException(
        'This file is not a supported Karbar backup.',
      );
    }

    final createdAtValue = decoded['createdAt'];
    final createdAt = createdAtValue is String
        ? DateTime.tryParse(createdAtValue)
        : null;
    if (createdAt == null) {
      throw const FormatException('The backup date is missing or invalid.');
    }

    final rawTables = decoded['tables'];
    if (rawTables is! Map<String, dynamic>) {
      throw const FormatException('The backup data is missing.');
    }
    final expected = DatabaseHelper.backupTableNames.toSet();
    final backupVersion = decoded['version'] as int;
    if (backupVersion == 1) {
      expected.removeAll({
        'sale_payments',
        'sale_returns',
        'sale_return_items',
        'suppliers',
        'purchases',
        'purchase_items',
      });
    } else if (backupVersion == 2) {
      expected.removeAll({
        'sale_returns',
        'sale_return_items',
        'suppliers',
        'purchases',
        'purchase_items',
      });
    } else if (backupVersion == 3) {
      expected.removeAll({'suppliers', 'purchases', 'purchase_items'});
    }
    if (backupVersion < 6) expected.remove('daily_closes');
    if (backupVersion < 8) expected.remove('staff_users');
    if (backupVersion < 9) expected.remove('sync_outbox');
    if (rawTables.keys.toSet().difference(expected).isNotEmpty ||
        expected.difference(rawTables.keys.toSet()).isNotEmpty) {
      throw const FormatException(
        'The backup does not contain the required Karbar data tables.',
      );
    }

    final tables = <String, List<Map<String, Object?>>>{};
    for (final table in DatabaseHelper.backupTableNames) {
      const tablesAddedInV3 = {'sale_returns', 'sale_return_items'};
      const tablesAddedInV4 = {'suppliers', 'purchases', 'purchase_items'};
      const tablesAddedInV6 = {'daily_closes'};
      const tablesAddedInV8 = {'staff_users'};
      const tablesAddedInV9 = {'sync_outbox'};
      final rows =
          rawTables[table] ??
          ((backupVersion == 1 && table == 'sale_payments') ||
                  (backupVersion < 3 && tablesAddedInV3.contains(table)) ||
                  (backupVersion < 4 && tablesAddedInV4.contains(table)) ||
                  (backupVersion < 6 && tablesAddedInV6.contains(table)) ||
                  (backupVersion < 8 && tablesAddedInV8.contains(table)) ||
                  (backupVersion < 9 && tablesAddedInV9.contains(table))
              ? <dynamic>[]
              : null);
      if (rows is! List) {
        throw FormatException('The $table backup section is invalid.');
      }
      final decodedRows = <Map<String, Object?>>[];
      for (final row in rows) {
        if (row is! Map || row.keys.any((key) => key is! String)) {
          throw FormatException('A row in the $table section is invalid.');
        }
        final values = Map<String, Object?>.from(row);
        if (values.values.any(
          (value) => value is bool || value is Map || value is List,
        )) {
          throw FormatException('A value in the $table section is invalid.');
        }
        decodedRows.add(values);
      }
      tables[table] = decodedRows;
    }
    final rawAssets = decoded['assets'];
    final rawImages = rawAssets is Map<String, dynamic>
        ? rawAssets['productImages']
        : null;
    if (rawImages is! Map<String, dynamic>) {
      throw const FormatException('The backup image section is invalid.');
    }
    final productIds = tables['products']!
        .map((row) => row['id'])
        .whereType<int>()
        .toSet();
    final productImages = <int, ProductImageAsset>{};
    for (final entry in rawImages.entries) {
      final productId = int.tryParse(entry.key);
      final value = entry.value;
      if (productId == null ||
          !productIds.contains(productId) ||
          value is! Map<String, dynamic>) {
        throw const FormatException('A product image entry is invalid.');
      }
      final extension = value['extension'];
      final encoded = value['data'];
      if (extension is! String ||
          !RegExp(r'^\.[a-zA-Z0-9]{1,8}$').hasMatch(extension) ||
          encoded is! String) {
        throw const FormatException('A product image entry is invalid.');
      }
      try {
        productImages[productId] = ProductImageAsset(
          extension: extension.toLowerCase(),
          bytes: base64Decode(encoded),
        );
      } on FormatException {
        throw const FormatException(
          'A product image is not valid base64 data.',
        );
      }
    }
    return BackupArchive(
      createdAt: createdAt,
      tables: tables,
      productImages: productImages,
    );
  }

  Future<void> restoreBackup(BackupArchive archive) async {
    final tables = {
      for (final entry in archive.tables.entries)
        entry.key: entry.value
            .map((row) => Map<String, Object?>.from(row))
            .toList(),
    };
    Directory? imageDirectory;
    try {
      if (archive.productImages.isNotEmpty) {
        final root = await _getDocumentsDirectory();
        imageDirectory = Directory(
          p.join(
            root.path,
            'restored_product_images',
            DateTime.now().microsecondsSinceEpoch.toString(),
          ),
        );
        await imageDirectory.create(recursive: true);
        final products = tables['products']!;
        for (final entry in archive.productImages.entries) {
          final file = File(
            p.join(
              imageDirectory.path,
              'product_${entry.key}${entry.value.extension}',
            ),
          );
          await file.writeAsBytes(entry.value.bytes, flush: true);
          for (final row in products) {
            if (row['id'] == entry.key) row['image_path'] = file.path;
          }
        }
      }
      // Never trust a device-specific image path supplied by a backup file.
      for (final row in tables['products']!) {
        if (!archive.productImages.containsKey(row['id'])) {
          row['image_path'] = '';
        }
      }
      await _db.restoreBackupTables(tables);
    } catch (_) {
      if (imageDirectory != null && await imageDirectory.exists()) {
        await imageDirectory.delete(recursive: true);
      }
      rethrow;
    }
  }

  Future<Directory> _getDocumentsDirectory() =>
      documentsDirectoryProvider?.call() ?? getApplicationDocumentsDirectory();
}
