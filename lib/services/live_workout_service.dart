import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

class LiveUpdateStatus {
  final bool supported;
  final bool notificationsEnabled;
  final bool canPostPromoted;
  final int sdkInt;

  const LiveUpdateStatus({
    required this.supported,
    required this.notificationsEnabled,
    required this.canPostPromoted,
    required this.sdkInt,
  });

  static const LiveUpdateStatus unsupported = LiveUpdateStatus(
    supported: false,
    notificationsEnabled: false,
    canPostPromoted: false,
    sdkInt: 0,
  );
}

/// Bridge to Android 16+ Live Updates (Promoted Ongoing Notifications) for
/// HyperOS 3 HyperIsland and stock Android status-bar Live Update capsules.
class LiveWorkoutService {
  LiveWorkoutService._() {
    _channel.setMethodCallHandler(_handleNativeCall);
  }
  static final LiveWorkoutService instance = LiveWorkoutService._();

  static const MethodChannel _channel =
      MethodChannel('com.tempo.fitness/live_updates');

  VoidCallback? onRemoteTogglePause;

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (call.method == 'onTogglePause') {
      onRemoteTogglePause?.call();
    }
    return null;
  }

  bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  Future<bool> ensureNotificationPermission() async {
    if (!_isAndroid) return false;
    try {
      final status = await Permission.notification.status;
      if (status.isGranted) return true;
      final requested = await Permission.notification.request();
      return requested.isGranted;
    } catch (_) {
      return false;
    }
  }

  Future<LiveUpdateStatus> getStatus() async {
    if (!_isAndroid) return LiveUpdateStatus.unsupported;
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>('getStatus');
      if (raw == null) return LiveUpdateStatus.unsupported;
      return LiveUpdateStatus(
        supported: raw['supported'] == true,
        notificationsEnabled: raw['notificationsEnabled'] == true,
        canPostPromoted: raw['canPostPromoted'] == true,
        sdkInt: (raw['sdkInt'] as num?)?.toInt() ?? 0,
      );
    } on MissingPluginException {
      return LiveUpdateStatus.unsupported;
    } catch (_) {
      return LiveUpdateStatus.unsupported;
    }
  }

  Future<void> startOrUpdate({
    required String workoutTitle,
    required String category,
    String currentExercise = '',
    double kcalPerMin = 7.5,
    required int elapsedSeconds,
    required int completedExercises,
    required int totalExercises,
    required bool isPaused,
  }) async {
    if (!_isAndroid) return;
    final mins = (elapsedSeconds ~/ 60).toString().padLeft(2, '0');
    final secs = (elapsedSeconds % 60).toString().padLeft(2, '0');
    final formattedTime = '$mins:$secs';
    final shortText = isPaused ? 'Paused' : formattedTime;
    final progressText = totalExercises > 0
        ? '$completedExercises/$totalExercises exercises'
        : 'Active session';
    final subtitle = isPaused
        ? 'Paused · $formattedTime · $progressText'
        : (category.isNotEmpty ? '$progressText · $category' : progressText);

    try {
      await _channel.invokeMethod<dynamic>('startOrUpdate', {
        'title': workoutTitle,
        'subtitle': subtitle,
        'category': category,
        'currentExercise': currentExercise,
        'kcalPerMin': kcalPerMin,
        'elapsedSeconds': elapsedSeconds,
        'completedExercises': completedExercises,
        'totalExercises': totalExercises,
        'isPaused': isPaused,
        'shortText': shortText,
      });
    } on MissingPluginException {
      // No-op in widget tests or non-Android hosts
    } catch (e) {
      debugPrint('LiveWorkoutService.startOrUpdate error: $e');
    }
  }

  Future<void> stop() async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod<dynamic>('stop');
    } on MissingPluginException {
      // No-op in widget tests
    } catch (_) {}
  }

  Future<bool> openLiveUpdatesSettings() async {
    if (!_isAndroid) return false;
    try {
      return (await _channel.invokeMethod<bool>('openLiveUpdatesSettings')) ??
          false;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
  }
}
