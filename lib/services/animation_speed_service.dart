import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User-configurable in-app animation pacing modeled after HyperOS's
/// Relaxed / Balanced / Fast speed preference.
enum TempoAnimationSpeed {
  relaxed('relaxed', 'Relaxed', 1.32),
  balanced('balanced', 'Balanced', 1.00),
  fast('fast', 'Fast', 0.65);

  final String storageKey;
  final String label;
  final double multiplier;

  const TempoAnimationSpeed(this.storageKey, this.label, this.multiplier);

  static TempoAnimationSpeed fromStorageKey(String? key) {
    for (final v in TempoAnimationSpeed.values) {
      if (v.storageKey == key) return v;
    }
    return TempoAnimationSpeed.balanced;
  }
}

/// Global singleton storing Tempo's active animation pacing with instant
/// synchronous reads (zero Provider/BuildContext lookup cost inside routes)
/// and local `SharedPreferences` persistence.
class TempoAnimationSpeedService {
  static const String _prefKey = 'tempo_animation_speed_v1';

  static final TempoAnimationSpeedService instance =
      TempoAnimationSpeedService._();

  TempoAnimationSpeedService._();

  final ValueNotifier<TempoAnimationSpeed> notifier =
      ValueNotifier<TempoAnimationSpeed>(TempoAnimationSpeed.balanced);

  bool _loaded = false;

  TempoAnimationSpeed get speed => notifier.value;

  double get multiplier => notifier.value.multiplier;

  /// Scales [base] duration according to the selected speed preset while
  /// preserving exact curve shapes and spring damping ratios.
  Duration scale(Duration base, {int minMs = 70, int maxMs = 2000}) {
    final scaledMs =
        (base.inMilliseconds * multiplier).round().clamp(minMs, maxMs);
    return Duration(milliseconds: scaledMs);
  }

  Future<void> initialize({bool forceReload = false}) async {
    if (_loaded && !forceReload) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefKey);
      final parsed = TempoAnimationSpeed.fromStorageKey(saved);
      if (notifier.value != parsed) {
        notifier.value = parsed;
      }
    } catch (_) {}
  }

  Future<void> setSpeed(TempoAnimationSpeed next) async {
    if (notifier.value != next) {
      notifier.value = next;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, next.storageKey);
    } catch (_) {}
  }

  /// Resets in-memory state for deterministic unit/widget tests.
  @visibleForTesting
  void resetForTest([TempoAnimationSpeed initial = TempoAnimationSpeed.balanced]) {
    _loaded = false;
    notifier.value = initial;
  }
}
