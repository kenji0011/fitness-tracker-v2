import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import 'tempo_rust_db.dart';

/// Accurate, reboot-safe, closed-app catch-up step counter sync engine backed by
/// the phone's hardware `TYPE_STEP_COUNTER` (cumulative steps since device boot).
///
/// Features:
/// - Explicit per-profile user opt-in toggle (`live_steps_enabled_<profileId>`).
/// - 1:1 live step accuracy with zero double-counting.
/// - Realistic human cadence spike guard (filters impossible hardware glitches
///   while preserving full closed-app / pocket walking catch-up).
/// - Desk-pickup jitter suppression when pedestrian status is stationary.
/// - Mid-day phone reboot resilience and manual entry preservation.
class StepCounterSync {
  static String _checkpointKey(String profileId) => 'step_sync_v1_$profileId';
  static String _enabledKey(String profileId) =>
      'live_steps_enabled_$profileId';

  static Future<bool> isLiveEnabled(String profileId) async {
    if (profileId.isEmpty) return false;
    final raw = await TempoRustDb.instance.getSetting(_enabledKey(profileId));
    return raw == '1';
  }

  static Future<void> setLiveEnabled(String profileId, bool enabled) async {
    if (profileId.isEmpty) return;
    await TempoRustDb.instance.setSetting(
      _enabledKey(profileId),
      enabled ? '1' : '0',
    );
  }

  /// Handles user toggle ON/OFF cleanly, requesting `ACTIVITY_RECOGNITION`
  /// permission when enabling on mobile.
  static Future<({bool enabled, bool deniedPermanently})>
      requestAndToggleLiveSteps(String profileId, bool wantEnabled) async {
    if (!wantEnabled) {
      await setLiveEnabled(profileId, false);
      return (enabled: false, deniedPermanently: false);
    }

    if (kIsWeb) {
      await setLiveEnabled(profileId, true);
      return (enabled: true, deniedPermanently: false);
    }

    try {
      var status = await Permission.activityRecognition.status;
      if (!status.isGranted) {
        status = await Permission.activityRecognition.request();
      }
      if (status.isGranted) {
        await setLiveEnabled(profileId, true);
        return (enabled: true, deniedPermanently: false);
      }
      await setLiveEnabled(profileId, false);
      return (
        enabled: false,
        deniedPermanently: status.isPermanentlyDenied,
      );
    } catch (_) {
      // Fallback for desktop/test environments without native permission channel
      await setLiveEnabled(profileId, true);
      return (enabled: true, deniedPermanently: false);
    }
  }

  /// Pure computation returning `(deltaToAdd, nextLastSensor)`.
  static ({int delta, int nextLastSensor}) computeDelta({
    required String todayKey,
    required int sensorSteps,
    required String? savedDateKey,
    required int? savedLastSensor,
    int? savedUpdatedMs,
    int? nowMs,
    bool isStationary = false,
  }) {
    if (sensorSteps < 0) {
      return (delta: 0, nextLastSensor: savedLastSensor ?? 0);
    }

    // First reading ever, or first reading on a brand-new calendar day:
    // establish today's baseline without crediting prior boot-lifetime steps.
    if (savedDateKey != todayKey || savedLastSensor == null) {
      return (delta: 0, nextLastSensor: sensorSteps);
    }

    int rawDelta;
    if (sensorSteps >= savedLastSensor) {
      rawDelta = sensorSteps - savedLastSensor;
    } else {
      // Device rebooted mid-day (hardware counter reset to 0): credit all steps
      // walked since reboot on top of today's already-stored steps.
      rawDelta = sensorSteps;
    }

    if (rawDelta <= 0) {
      return (delta: 0, nextLastSensor: sensorSteps);
    }

    // Filter tiny 1-2 step desk-pickup jitter when the phone reports stationary
    // over a short burst (< 2 seconds).
    final elapsedMs = (savedUpdatedMs != null && nowMs != null)
        ? (nowMs - savedUpdatedMs).clamp(0, 86400000)
        : null;
    if (isStationary && rawDelta <= 2 && elapsedMs != null && elapsedMs < 2000) {
      return (delta: 0, nextLastSensor: sensorSteps);
    }

    // Realistic human cadence guard: max ~4.5 steps/sec (fast sprint) plus a
    // generous burst allowance of 25 steps for hardware batch delivery.
    int maxPlausibleDelta = 100000;
    if (elapsedMs != null && elapsedMs > 0) {
      final elapsedSec = elapsedMs / 1000.0;
      maxPlausibleDelta = ((elapsedSec * 4.5).ceil() + 25).clamp(25, 100000);
    }

    if (rawDelta > maxPlausibleDelta) {
      // Reject impossible hardware glitch spike while re-syncing checkpoint
      return (delta: 0, nextLastSensor: sensorSteps);
    }

    return (delta: rawDelta, nextLastSensor: sensorSteps);
  }

  /// Processes a live [sensorSteps] reading for [profileId], persisting both
  /// the updated checkpoint and any newly walked step delta into [TempoRustDb].
  /// Returns the updated total daily steps if steps changed, or `null` if unchanged.
  static Future<int?> ingestHardwareSteps({
    required TempoRustDb db,
    required String profileId,
    required int sensorSteps,
    String? todayKeyOverride,
    int? nowMsOverride,
    bool isStationary = false,
  }) async {
    final todayKey = todayKeyOverride ?? TempoRustDb.todayKey();
    final nowMs = nowMsOverride ?? DateTime.now().millisecondsSinceEpoch;
    final raw = await db.getSetting(_checkpointKey(profileId));

    String? savedDateKey;
    int? savedLastSensor;
    int? savedUpdatedMs;
    if (raw != null && raw.isNotEmpty) {
      try {
        final map = jsonDecode(raw);
        if (map is Map) {
          savedDateKey = map['dateKey']?.toString();
          savedLastSensor = (map['lastSensor'] as num?)?.toInt();
          savedUpdatedMs = (map['updatedMs'] as num?)?.toInt();
        }
      } catch (_) {}
    }

    final result = computeDelta(
      todayKey: todayKey,
      sensorSteps: sensorSteps,
      savedDateKey: savedDateKey,
      savedLastSensor: savedLastSensor,
      savedUpdatedMs: savedUpdatedMs,
      nowMs: nowMs,
      isStationary: isStationary,
    );

    await db.setSetting(
      _checkpointKey(profileId),
      jsonEncode({
        'dateKey': todayKey,
        'lastSensor': result.nextLastSensor,
        'updatedMs': nowMs,
      }),
    );

    if (result.delta <= 0) return null;

    final summary = await db.getDashboardSummary(profileId);
    final updatedTotal = (summary.today.steps + result.delta).clamp(0, 200000);
    await db.upsertDailyActivity(
      profileId: profileId,
      dateKey: todayKey,
      steps: updatedTotal,
    );
    return updatedTotal;
  }
}
