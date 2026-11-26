import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'tempo_rust_db.dart';

/// Supported layout styles for Day / Month share posters.
enum SharePosterLayout { classic, centered, minimal }

/// Supported metric keys that users can toggle onto their custom share poster.
class ShareMetricOption {
  final String key;
  final String label;

  const ShareMetricOption(this.key, this.label);

  static const List<ShareMetricOption> all = [
    ShareMetricOption('calories', 'Calories'),
    ShareMetricOption('steps', 'Steps'),
    ShareMetricOption('minutes', 'Activity time'),
    ShareMetricOption('water', 'Water'),
    ShareMetricOption('sleep', 'Sleep'),
    ShareMetricOption('weight', 'Weight'),
    ShareMetricOption('streak', 'Streak'),
  ];

  static const List<String> defaultMetrics = [
    'calories',
    'steps',
    'minutes',
  ];
}

/// Reusable local share template storing both design and chosen metrics.
class ProgressShareTemplate {
  final String id;
  final String name;
  final String mode; // 'day' | 'month'
  final String backgroundId; // built-in preset id or 'custom_photo'
  final String? customPhotoPath;
  final String layout; // 'classic' | 'centered' | 'minimal'
  final List<String> metrics;
  final bool showRings;
  final bool showProfile;
  final bool showDate;
  final bool showBrandBadge;
  final String caption;
  final int accentColorValue;
  final DateTime updatedAt;

  const ProgressShareTemplate({
    required this.id,
    required this.name,
    this.mode = 'day',
    this.backgroundId = 'track_sunset',
    this.customPhotoPath,
    this.layout = 'classic',
    this.metrics = ShareMetricOption.defaultMetrics,
    this.showRings = true,
    this.showProfile = true,
    this.showDate = true,
    this.showBrandBadge = true,
    this.caption = '',
    this.accentColorValue = 0xFFFF6A24,
    required this.updatedAt,
  });

  ProgressShareTemplate copyWith({
    String? id,
    String? name,
    String? mode,
    String? backgroundId,
    String? customPhotoPath,
    bool clearCustomPhoto = false,
    String? layout,
    List<String>? metrics,
    bool? showRings,
    bool? showProfile,
    bool? showDate,
    bool? showBrandBadge,
    String? caption,
    int? accentColorValue,
    DateTime? updatedAt,
  }) {
    return ProgressShareTemplate(
      id: id ?? this.id,
      name: name ?? this.name,
      mode: mode ?? this.mode,
      backgroundId: backgroundId ?? this.backgroundId,
      customPhotoPath:
          clearCustomPhoto ? null : (customPhotoPath ?? this.customPhotoPath),
      layout: layout ?? this.layout,
      metrics: metrics ?? this.metrics,
      showRings: showRings ?? this.showRings,
      showProfile: showProfile ?? this.showProfile,
      showDate: showDate ?? this.showDate,
      showBrandBadge: showBrandBadge ?? this.showBrandBadge,
      caption: caption ?? this.caption,
      accentColorValue: accentColorValue ?? this.accentColorValue,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'mode': mode,
        'backgroundId': backgroundId,
        'customPhotoPath': customPhotoPath,
        'layout': layout,
        'metrics': metrics,
        'showRings': showRings,
        'showProfile': showProfile,
        'showDate': showDate,
        'showBrandBadge': showBrandBadge,
        'caption': caption,
        'accentColorValue': accentColorValue,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory ProgressShareTemplate.fromJson(Map<String, dynamic> json) {
    final rawMetrics = (json['metrics'] as List?)
            ?.map((e) => e.toString())
            .where((k) => ShareMetricOption.all.any((m) => m.key == k))
            .toList() ??
        const <String>[];
    return ProgressShareTemplate(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? 'Custom Template').toString(),
      mode: json['mode'] == 'month' ? 'month' : 'day',
      backgroundId: (json['backgroundId'] ?? 'track_sunset').toString(),
      customPhotoPath: (json['customPhotoPath'] as String?)?.isNotEmpty == true
          ? json['customPhotoPath'] as String
          : null,
      layout: ['classic', 'centered', 'minimal'].contains(json['layout'])
          ? json['layout'].toString()
          : 'classic',
      metrics: rawMetrics.isEmpty
          ? ShareMetricOption.defaultMetrics
          : rawMetrics,
      showRings: json['showRings'] != false,
      showProfile: json['showProfile'] != false,
      showDate: json['showDate'] != false,
      showBrandBadge: json['showBrandBadge'] != false,
      caption: (json['caption'] ?? '').toString(),
      accentColorValue:
          (json['accentColorValue'] as num?)?.toInt() ?? 0xFFFF6A24,
      updatedAt: DateTime.tryParse((json['updatedAt'] ?? '').toString()) ??
          DateTime.now(),
    );
  }
}

/// Manages local share template persistence (per profile in `TempoRustDb`),
/// poster PNG file export, gallery saving, and native Android sharing.
class ShareTemplateService {
  static const MethodChannel _channel =
      MethodChannel('com.tempo.fitness/progress_share');
  static const Uuid _uuid = Uuid();

  static String _storageKey(String profileId) =>
      'share_templates_v1_$profileId';

  static Future<List<ProgressShareTemplate>> loadTemplates(
    String profileId,
  ) async {
    final raw = await TempoRustDb.instance.getSetting(_storageKey(profileId));
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map(
            (m) => ProgressShareTemplate.fromJson(Map<String, dynamic>.from(m)),
          )
          .where((t) => t.id.isNotEmpty)
          .toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } catch (e) {
      debugPrint('Failed to decode saved share templates: $e');
      return const [];
    }
  }

  static Future<List<ProgressShareTemplate>> saveTemplate({
    required String profileId,
    required ProgressShareTemplate template,
  }) async {
    final existing = await loadTemplates(profileId);
    final resolvedId = template.id.isEmpty ? _uuid.v4() : template.id;
    final cleanName = template.name.trim().isEmpty
        ? 'Template ${existing.length + 1}'
        : template.name.trim();
    final updated = template.copyWith(
      id: resolvedId,
      name: cleanName,
      updatedAt: DateTime.now(),
    );

    final next = [
      updated,
      ...existing.where((t) => t.id != resolvedId),
    ];
    await TempoRustDb.instance.setSetting(
      _storageKey(profileId),
      jsonEncode(next.map((t) => t.toJson()).toList()),
    );
    return next;
  }

  static Future<List<ProgressShareTemplate>> deleteTemplate({
    required String profileId,
    required String templateId,
  }) async {
    final existing = await loadTemplates(profileId);
    final next = existing.where((t) => t.id != templateId).toList();
    await TempoRustDb.instance.setSetting(
      _storageKey(profileId),
      jsonEncode(next.map((t) => t.toJson()).toList()),
    );
    return next;
  }

  /// Copies a user-picked background photo into Tempo's persistent local
  /// documents folder so saved templates remain valid even if the OS clears temp cache.
  static Future<String> persistTemplateBackgroundPhoto(
    String sourcePath,
    String profileId,
  ) async {
    if (kIsWeb) return sourcePath;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'tempo_share_bgs', profileId));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final ext = p.extension(sourcePath).isNotEmpty
        ? p.extension(sourcePath)
        : '.jpg';
    final destPath = p.join(
      dir.path,
      'bg_${DateTime.now().millisecondsSinceEpoch}$ext',
    );
    await File(sourcePath).copy(destPath);
    return destPath;
  }

  /// Writes captured PNG bytes to Tempo's scoped FileProvider cache directory.
  static Future<File> writeSharePosterPng(Uint8List pngBytes, String prefix) async {
    final cacheDir = await getTemporaryDirectory();
    final sharesDir = Directory(p.join(cacheDir.path, 'shares'));
    if (!await sharesDir.exists()) {
      await sharesDir.create(recursive: true);
    }
    final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final file = File(p.join(sharesDir.path, '${prefix}_$stamp.png'));
    await file.writeAsBytes(pngBytes, flush: true);
    return file;
  }

  /// Saves rendered poster PNG to the phone's Pictures/Tempo gallery album.
  static Future<({bool ok, String message})> savePosterToGallery(
    Uint8List pngBytes, {
    String prefix = 'Tempo_Stats',
  }) async {
    if (kIsWeb) {
      return (ok: false, message: 'Gallery save is supported on mobile');
    }
    try {
      final file = await writeSharePosterPng(pngBytes, prefix);
      if (Platform.isAndroid) {
        final raw = await _channel.invokeMapMethod<String, dynamic>(
          'saveToGallery',
          {
            'filePath': file.path,
            'displayName': p.basename(file.path),
          },
        );
        if (raw != null && raw['ok'] == true) {
          return (
            ok: true,
            message: 'Saved to Pictures/Tempo',
          );
        }
        return (
          ok: false,
          message: (raw?['error'] ?? 'Could not save image').toString(),
        );
      }

      // Desktop/other local fallback: save under app documents/tempo_exports
      final docs = await getApplicationDocumentsDirectory();
      final exportDir = Directory(p.join(docs.path, 'tempo_exports'));
      if (!await exportDir.exists()) await exportDir.create(recursive: true);
      final dest = File(p.join(exportDir.path, p.basename(file.path)));
      await file.copy(dest.path);
      return (ok: true, message: 'Saved poster locally');
    } catch (e) {
      debugPrint('savePosterToGallery error: $e');
      return (ok: false, message: 'Could not save image');
    }
  }

  /// Opens Android's native Share Sheet with the rendered PNG poster.
  static Future<({bool ok, String message})> sharePoster(
    Uint8List pngBytes, {
    String prefix = 'Tempo_Stats',
    String? shareText,
  }) async {
    if (kIsWeb) {
      return (ok: false, message: 'Sharing is supported on mobile');
    }
    try {
      final file = await writeSharePosterPng(pngBytes, prefix);
      if (Platform.isAndroid) {
        final raw = await _channel.invokeMapMethod<String, dynamic>(
          'shareImage',
          {
            'filePath': file.path,
            if (shareText != null) 'text': shareText,
          },
        );
        if (raw != null && raw['ok'] == true) {
          return (ok: true, message: 'Share sheet opened');
        }
        return (
          ok: false,
          message: (raw?['error'] ?? 'Could not open share sheet').toString(),
        );
      }
      return (ok: true, message: 'Poster ready at ${file.path}');
    } catch (e) {
      debugPrint('sharePoster error: $e');
      return (ok: false, message: 'Could not open share sheet');
    }
  }
}
