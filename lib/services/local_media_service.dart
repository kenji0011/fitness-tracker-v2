import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Stores profile avatars and progress photos privately inside the device's
/// local application documents directory (replaces Supabase Storage buckets).
class LocalMediaService {
  static const _uuid = Uuid();

  static Future<String> saveProfileAvatar({
    required String profileId,
    required String sourcePath,
  }) async {
    if (kIsWeb) return sourcePath;
    final dir = await _ensureDir(p.join('tempo_media', profileId, 'avatars'));
    final ext = p.extension(sourcePath).isEmpty ? '.jpg' : p.extension(sourcePath);
    final destPath = p.join(dir.path, 'avatar_${DateTime.now().millisecondsSinceEpoch}$ext');
    await File(sourcePath).copy(destPath);
    return destPath;
  }

  static Future<String> saveProgressPhotoBytes({
    required String profileId,
    required Uint8List bytes,
    String extension = '.jpg',
  }) async {
    final dir = await _ensureDir(p.join('tempo_media', profileId, 'progress'));
    final fileName = 'progress_${_uuid.v4()}$extension';
    final destPath = p.join(dir.path, fileName);
    await File(destPath).writeAsBytes(bytes, flush: true);
    return destPath;
  }

  static Future<String> saveProgressPhotoFile({
    required String profileId,
    required String sourcePath,
  }) async {
    if (kIsWeb) return sourcePath;
    final dir = await _ensureDir(p.join('tempo_media', profileId, 'progress'));
    final ext = p.extension(sourcePath).isEmpty ? '.jpg' : p.extension(sourcePath);
    final destPath = p.join(dir.path, 'progress_${_uuid.v4()}$ext');
    await File(sourcePath).copy(destPath);
    return destPath;
  }

  static Future<void> deleteLocalFile(String filePath) async {
    if (kIsWeb || filePath.trim().isEmpty) return;
    try {
      final f = File(filePath);
      if (await f.exists()) {
        await f.delete();
      }
    } catch (_) {}
  }

  static Future<Directory> _ensureDir(String relativePath) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, relativePath));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }
}
