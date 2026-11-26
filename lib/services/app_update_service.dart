import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_version.dart';

/// Parsed metadata for a Tempo GitHub Release with an Android APK asset.
class TempoReleaseInfo {
  final String version;
  final String tagName;
  final String title;
  final String releaseNotes;
  final String apkUrl;
  final String apkName;
  final int apkSizeBytes;
  final String? sha256Digest;
  final DateTime? publishedAt;
  final String htmlUrl;

  const TempoReleaseInfo({
    required this.version,
    required this.tagName,
    required this.title,
    required this.releaseNotes,
    required this.apkUrl,
    required this.apkName,
    required this.apkSizeBytes,
    this.sha256Digest,
    this.publishedAt,
    required this.htmlUrl,
  });

  String get displayVersion => 'V$version - R';

  String get formattedSize {
    if (apkSizeBytes <= 0) return 'Unknown size';
    final mb = apkSizeBytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }
}

enum TempoUpdateCheckStatus {
  updateAvailable,
  upToDate,
  offlineOrError,
  skipped,
  throttled,
}

class TempoUpdateCheckResult {
  final TempoUpdateCheckStatus status;
  final TempoReleaseInfo? release;
  final String? errorMessage;

  const TempoUpdateCheckResult({
    required this.status,
    this.release,
    this.errorMessage,
  });
}

class TempoInstallResult {
  final bool ok;
  final String? reason;
  final String? message;

  const TempoInstallResult({
    required this.ok,
    this.reason,
    this.message,
  });

  bool get needsPermission => reason == 'permission_required';
}

/// Cancellation handle for an active in-app APK download.
class TempoDownloadCancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

class TempoDownloadCancelledException implements Exception {
  const TempoDownloadCancelledException();
}

/// Offline-safe in-app updater backed by GitHub Releases for Tempo
/// (`kenji0011/fitness-tracker-v2`) + native Android `FileProvider` handoff.
class AppUpdateService {
  AppUpdateService._();

  static const String repoOwner = 'kenji0011';
  static const String repoName = 'fitness-tracker-v2';
  static const String latestReleaseEndpoint =
      'https://api.github.com/repos/$repoOwner/$repoName/releases/latest';

  static const String _prefAutoUpdateEnabled = 'tempo_auto_update_enabled';
  static const String _prefLastCheckMs = 'tempo_auto_update_last_check_ms';
  static const String _prefSkippedVersion = 'tempo_skipped_update_version';

  static const Duration autoCheckThrottle = Duration(hours: 6);
  static const Duration _apiTimeout = Duration(seconds: 8);

  static const MethodChannel _channel =
      MethodChannel('com.tempo.fitness/app_updater');

  /// Most recently discovered newer release in this session (drives Profile dot badge).
  static final ValueNotifier<TempoReleaseInfo?> availableRelease =
      ValueNotifier<TempoReleaseInfo?>(null);

  static bool _isRunningInTest() {
    try {
      return WidgetsBinding.instance.runtimeType.toString().contains('Test');
    } catch (_) {
      return false;
    }
  }

  /// Auto-updates preference (global across profiles). **ON (`true`) by default.**
  static Future<bool> isAutoUpdateEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefAutoUpdateEnabled) ?? true;
  }

  static Future<void> setAutoUpdateEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefAutoUpdateEnabled, enabled);
  }

  static Future<String?> getSkippedVersion() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_prefSkippedVersion);
    return (v != null && v.trim().isNotEmpty) ? v.trim() : null;
  }

  static Future<void> skipVersion(String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefSkippedVersion, normalizeVersion(version));
  }

  static Future<void> clearSkippedVersion() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefSkippedVersion);
  }

  /// Extracts a clean `major.minor.patch` tuple from tags like `v2.0.17`,
  /// `V2.0.17 - R`, or `2.0.17+25`.
  static List<int>? parseSemver(String raw) {
    final match = RegExp(r'(\d+)\.(\d+)\.(\d+)').firstMatch(raw.trim());
    if (match == null) return null;
    return [
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    ];
  }

  static String normalizeVersion(String raw) {
    final parts = parseSemver(raw);
    if (parts == null) return raw.trim();
    return '${parts[0]}.${parts[1]}.${parts[2]}';
  }

  /// Returns `true` strictly when [remoteTag] has a higher semantic version
  /// than [currentVersion].
  static bool isRemoteNewer(String remoteTag, String currentVersion) {
    final remote = parseSemver(remoteTag);
    final current = parseSemver(currentVersion);
    if (remote == null || current == null) return false;
    for (int i = 0; i < 3; i++) {
      if (remote[i] != current[i]) {
        return remote[i] > current[i];
      }
    }
    return false;
  }

  /// Parses a GitHub `/releases/latest` payload into a [TempoReleaseInfo].
  /// Returns `null` if the release is a draft/prerelease, has no valid semver,
  /// or does not contain a `.apk` download asset.
  static TempoReleaseInfo? parseReleaseJson(Map<String, dynamic> json) {
    if (json['draft'] == true || json['prerelease'] == true) return null;

    final tagName = (json['tag_name'] as String?)?.trim() ?? '';
    final name = (json['name'] as String?)?.trim() ?? tagName;
    final normalized = parseSemver(tagName) != null
        ? normalizeVersion(tagName)
        : (parseSemver(name) != null ? normalizeVersion(name) : null);
    if (normalized == null) return null;

    final rawAssets = json['assets'];
    if (rawAssets is! List) return null;

    Map<String, dynamic>? chosenApk;
    for (final item in rawAssets) {
      if (item is! Map) continue;
      final asset = Map<String, dynamic>.from(item);
      final assetName = (asset['name'] as String?)?.trim() ?? '';
      final downloadUrl = (asset['browser_download_url'] as String?)?.trim() ?? '';
      if (!assetName.toLowerCase().endsWith('.apk') || downloadUrl.isEmpty) {
        continue;
      }
      if (assetName.toLowerCase() == 'tempo.apk') {
        chosenApk = asset;
        break;
      }
      chosenApk ??= asset;
    }
    if (chosenApk == null) return null;

    String? sha256Hex;
    final rawDigest = (chosenApk['digest'] as String?)?.trim();
    if (rawDigest != null && rawDigest.toLowerCase().startsWith('sha256:')) {
      final candidate = rawDigest.substring(7).trim().toLowerCase();
      if (RegExp(r'^[0-9a-f]{64}$').hasMatch(candidate)) {
        sha256Hex = candidate;
      }
    }

    final publishedRaw = json['published_at'] as String?;
    return TempoReleaseInfo(
      version: normalized,
      tagName: tagName.isNotEmpty ? tagName : 'v$normalized',
      title: name.isNotEmpty ? name : 'Tempo V$normalized - R',
      releaseNotes: ((json['body'] as String?) ?? '').trim(),
      apkUrl: (chosenApk['browser_download_url'] as String).trim(),
      apkName: (chosenApk['name'] as String).trim(),
      apkSizeBytes: (chosenApk['size'] as num?)?.toInt() ?? 0,
      sha256Digest: sha256Hex,
      publishedAt: publishedRaw != null ? DateTime.tryParse(publishedRaw) : null,
      htmlUrl: (json['html_url'] as String?)?.trim() ??
          'https://github.com/$repoOwner/$repoName/releases',
    );
  }

  /// Checks GitHub Releases for a newer Tempo build.
  ///
  /// When [manual] is `false`:
  /// - Skips cleanly in widget tests, non-Android platforms (unless overridden),
  ///   or when the 6-hour throttle window has not elapsed.
  /// - Respects user's skipped version choice.
  /// - Swallows all offline/network errors silently.
  static Future<TempoUpdateCheckResult> checkForUpdate({
    bool manual = false,
    String currentVersionOverride = kTempoVersionNumber,
    Future<Map<String, dynamic>?> Function()? releaseFetcherOverride,
    int? nowMsOverride,
  }) async {
    if (!manual && releaseFetcherOverride == null) {
      if (_isRunningInTest()) {
        return const TempoUpdateCheckResult(
          status: TempoUpdateCheckStatus.throttled,
        );
      }
      if (!await isAutoUpdateEnabled()) {
        return const TempoUpdateCheckResult(
          status: TempoUpdateCheckStatus.throttled,
        );
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final nowMs = nowMsOverride ?? DateTime.now().millisecondsSinceEpoch;
    if (!manual) {
      final lastCheck = prefs.getInt(_prefLastCheckMs) ?? 0;
      if (lastCheck > 0 &&
          (nowMs - lastCheck) < autoCheckThrottle.inMilliseconds) {
        return const TempoUpdateCheckResult(
          status: TempoUpdateCheckStatus.throttled,
        );
      }
    }

    Map<String, dynamic>? payload;
    try {
      payload = releaseFetcherOverride != null
          ? await releaseFetcherOverride()
          : await _fetchLatestReleaseJson();
    } catch (e) {
      return TempoUpdateCheckResult(
        status: TempoUpdateCheckStatus.offlineOrError,
        errorMessage: e.toString(),
      );
    }

    if (payload == null) {
      return const TempoUpdateCheckResult(
        status: TempoUpdateCheckStatus.offlineOrError,
        errorMessage: 'Could not reach GitHub Releases.',
      );
    }

    await prefs.setInt(_prefLastCheckMs, nowMs);

    final release = parseReleaseJson(payload);
    if (release == null ||
        !isRemoteNewer(release.version, currentVersionOverride)) {
      availableRelease.value = null;
      return const TempoUpdateCheckResult(
        status: TempoUpdateCheckStatus.upToDate,
      );
    }

    availableRelease.value = release;

    if (!manual) {
      final skipped = await getSkippedVersion();
      if (skipped != null && skipped == release.version) {
        return TempoUpdateCheckResult(
          status: TempoUpdateCheckStatus.skipped,
          release: release,
        );
      }
    }

    return TempoUpdateCheckResult(
      status: TempoUpdateCheckStatus.updateAvailable,
      release: release,
    );
  }

  static Future<Map<String, dynamic>?> _fetchLatestReleaseJson() async {
    final client = HttpClient()..connectionTimeout = _apiTimeout;
    try {
      final req = await client
          .getUrl(Uri.parse(latestReleaseEndpoint))
          .timeout(_apiTimeout);
      req.headers.set('Accept', 'application/vnd.github+json');
      req.headers.set('User-Agent', 'Tempo-Fitness/$kTempoVersionNumber');
      final res = await req.close().timeout(_apiTimeout);
      if (res.statusCode != HttpStatus.ok) {
        await res.drain<void>();
        return null;
      }
      final body = await res.transform(utf8.decoder).join().timeout(_apiTimeout);
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Streams [release]'s APK directly into `<cache>/updates/` with byte-level
  /// progress callbacks, cancellation support, and optional SHA-256 verification.
  static Future<String> downloadApk(
    TempoReleaseInfo release, {
    required void Function(int receivedBytes, int totalBytes) onProgress,
    TempoDownloadCancelToken? cancelToken,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final updatesDir = Directory('${tempDir.path}${Platform.pathSeparator}updates');
    if (!await updatesDir.exists()) {
      await updatesDir.create(recursive: true);
    }

    final finalFile = File(
      '${updatesDir.path}${Platform.pathSeparator}Tempo-${release.version}.apk',
    );
    final partFile = File('${finalFile.path}.part');

    // Reuse an already-verified cached APK if the user cancelled/returned from settings
    if (await finalFile.exists()) {
      final len = await finalFile.length();
      final sizeMatches =
          release.apkSizeBytes <= 0 || len == release.apkSizeBytes;
      if (sizeMatches && len > 1024 * 1024) {
        if (release.sha256Digest == null ||
            await _verifySha256(finalFile, release.sha256Digest!)) {
          onProgress(len, len);
          return finalFile.path;
        }
      }
      try {
        await finalFile.delete();
      } catch (_) {}
    }

    if (await partFile.exists()) {
      try {
        await partFile.delete();
      } catch (_) {}
    }

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    IOSink? sink;
    try {
      final req = await client.getUrl(Uri.parse(release.apkUrl));
      req.followRedirects = true;
      req.maxRedirects = 6;
      req.headers.set('User-Agent', 'Tempo-Fitness/$kTempoVersionNumber');

      final res = await req.close();
      if (res.statusCode != HttpStatus.ok) {
        throw HttpException('Download failed (HTTP ${res.statusCode})');
      }

      final totalBytes = res.contentLength > 0
          ? res.contentLength
          : release.apkSizeBytes;
      int received = 0;
      sink = partFile.openWrite();

      await for (final chunk in res) {
        if (cancelToken?.isCancelled == true) {
          throw const TempoDownloadCancelledException();
        }
        sink.add(chunk);
        received += chunk.length;
        onProgress(received, totalBytes);
      }

      await sink.flush();
      await sink.close();
      sink = null;

      if (cancelToken?.isCancelled == true) {
        throw const TempoDownloadCancelledException();
      }

      if (release.apkSizeBytes > 0 && received != release.apkSizeBytes) {
        throw const FileSystemException(
          'Downloaded APK is incomplete. Please try again.',
        );
      }

      if (release.sha256Digest != null) {
        final valid = await _verifySha256(partFile, release.sha256Digest!);
        if (!valid) {
          throw const FileSystemException(
            'APK integrity check failed (SHA-256 mismatch).',
          );
        }
      }

      await partFile.rename(finalFile.path);
      return finalFile.path;
    } catch (_) {
      try {
        await sink?.close();
      } catch (_) {}
      try {
        if (await partFile.exists()) await partFile.delete();
      } catch (_) {}
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  static Future<bool> _verifySha256(File file, String expectedHex) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString().toLowerCase() == expectedHex.toLowerCase();
  }

  /// Cleans up leftover cached APKs from previous updates so storage stays lean.
  static Future<void> cleanupStaleApks() async {
    if (_isRunningInTest()) return;
    try {
      final tempDir = await getTemporaryDirectory();
      final updatesDir =
          Directory('${tempDir.path}${Platform.pathSeparator}updates');
      if (!await updatesDir.exists()) return;
      await for (final entity in updatesDir.list()) {
        if (entity is File) {
          try {
            await entity.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  /// Checks Android's `canRequestPackageInstalls()` permission.
  static Future<bool> canInstallPackages() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('canInstallPackages');
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Opens Android's per-app "Install unknown apps" settings screen for Tempo.
  static Future<bool> openInstallPermissionSettings() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final ok =
          await _channel.invokeMethod<bool>('openInstallPermissionSettings');
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Hands a downloaded `.apk` to Android's native Package Installer via
  /// Tempo's scoped `FileProvider`.
  static Future<TempoInstallResult> installApk(String filePath) async {
    if (kIsWeb || !Platform.isAndroid) {
      return const TempoInstallResult(
        ok: false,
        reason: 'unsupported_platform',
        message: 'In-app APK updates are supported on Android devices.',
      );
    }
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'installApk',
        {'filePath': filePath},
      );
      if (raw == null) {
        return const TempoInstallResult(
          ok: false,
          reason: 'unknown',
          message: 'Could not start Android installer.',
        );
      }
      return TempoInstallResult(
        ok: raw['ok'] == true,
        reason: raw['reason'] as String?,
        message: raw['message'] as String?,
      );
    } catch (e) {
      return TempoInstallResult(
        ok: false,
        reason: 'channel_error',
        message: e.toString(),
      );
    }
  }
}
