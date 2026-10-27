import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Converts device-local product photos to compact, portable catalog assets.
class ProductImageStorage {
  static const maxCloudImageBytes = 280 * 1024;
  static Future<Directory> Function()? testDirectoryProvider;

  final Map<String, ({DateTime modified, int length, String data})> _cache = {};

  Future<String?> encodeForCloud(String imagePath) async {
    if (imagePath.isEmpty) return null;
    final file = File(imagePath);
    if (!await file.exists()) return null;
    final stat = await file.stat();
    final cached = _cache[imagePath];
    if (cached != null &&
        cached.modified == stat.modified &&
        cached.length == stat.size) {
      return cached.data;
    }
    final source = img.decodeImage(await file.readAsBytes());
    if (source == null) {
      throw const FormatException('Product image is invalid.');
    }
    final resized = (source.width > 640 || source.height > 640)
        ? img.copyResize(
            source,
            width: source.width >= source.height ? 640 : null,
            height: source.height > source.width ? 640 : null,
          )
        : source;
    for (final quality in [80, 65, 50, 35]) {
      final bytes = img.encodeJpg(resized, quality: quality);
      if (bytes.length <= maxCloudImageBytes) {
        final encoded = base64Encode(bytes);
        _cache[imagePath] = (
          modified: stat.modified,
          length: stat.size,
          data: encoded,
        );
        return encoded;
      }
    }
    throw StateError('Product image is too large to sync after compression.');
  }

  Future<String> saveCloudImage(String productSyncId, String encoded) async {
    if (!RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(productSyncId)) {
      throw const FormatException('Product image identity is invalid.');
    }
    final bytes = base64Decode(encoded);
    if (bytes.isEmpty ||
        bytes.length > maxCloudImageBytes ||
        img.decodeImage(bytes) == null) {
      throw const FormatException('Synced product image is invalid.');
    }
    final root =
        await (testDirectoryProvider?.call() ??
            getApplicationDocumentsDirectory());
    final directory = Directory(p.join(root.path, 'cloud_product_images'));
    await directory.create(recursive: true);
    final destination = File(p.join(directory.path, '$productSyncId.jpg'));
    final temporary = File('${destination.path}.tmp');
    await temporary.writeAsBytes(bytes, flush: true);
    if (await destination.exists()) await destination.delete();
    await temporary.rename(destination.path);
    return destination.path;
  }

  void clearCache() => _cache.clear();
}
