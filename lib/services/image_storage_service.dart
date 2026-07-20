import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Copies picked product photos into the app's own documents directory (so
/// they survive even if the original picked file is temporary/cache-only),
/// and cleans up files that are no longer referenced by any product.
class ImageStorageService {
  ImageStorageService._();

  /// Whether [path] is non-empty and actually exists on disk right now.
  /// Used before rendering a stored photo, since a product's `imagePath`
  /// can go stale (e.g. the file was moved/deleted outside the app).
  static bool exists(String? path) => path != null && path.isNotEmpty && File(path).existsSync();

  static Future<Directory> _imagesDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final imagesDir = Directory(p.join(dir.path, 'product_images'));
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }
    return imagesDir;
  }

  /// Copies the picked file at [sourcePath] into local app storage and
  /// returns the new absolute path.
  static Future<String> saveImage(String sourcePath) async {
    final imagesDir = await _imagesDir();
    final ext = p.extension(sourcePath);
    final filename = '${const Uuid().v4()}$ext';
    final destPath = p.join(imagesDir.path, filename);
    await File(sourcePath).copy(destPath);
    return destPath;
  }

  /// Deletes a previously saved product image, if it exists. Safe to call
  /// with paths that aren't managed by this service (e.g. it silently
  /// no-ops on failure) so it can be used defensively when replacing/
  /// removing a product's photo.
  static Future<void> deleteImage(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Best-effort cleanup; ignore failures (e.g. file already gone).
    }
  }
}
