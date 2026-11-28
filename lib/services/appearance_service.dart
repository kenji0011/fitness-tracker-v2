import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'device_performance_service.dart';

/// Immutable snapshot of Tempo's user-configurable Appearance & Liquid Glass
/// visual preferences (modeled after BitChord's Appearance settings).
@immutable
class TempoAppearanceSettings {
  final bool reduceAnimation;
  final bool reduceDynamicBlur;
  final bool liquidGlass;
  final bool betterGlassPerformance;
  final bool progressiveBlur;

  const TempoAppearanceSettings({
    this.reduceAnimation = false,
    this.reduceDynamicBlur = false,
    this.liquidGlass = true,
    this.betterGlassPerformance = false,
    this.progressiveBlur = true,
  });

  /// True when live GPU backdrop blurs are allowed.
  bool get allowDynamicBlur => !reduceDynamicBlur;

  /// True when optical Liquid Glass surfaces are enabled and dynamic blur is on.
  bool get useLiquidGlass => liquidGlass && !reduceDynamicBlur;

  /// True when live GPU refraction lens shaders (`shaders/liquid_glass_lens.frag`)
  /// should run across the navbar, difficulty sliders, and dragged summary cards
  /// (disabled under Better Performance for Glass, Liquid Glass OFF, or Reduce
  /// Dynamic Blur).
  bool get useGlassRefraction =>
      useLiquidGlass && !betterGlassPerformance;

  /// True when top sliver headers render progressive blurred fade scrims.
  bool get useProgressiveBlur =>
      progressiveBlur && !reduceDynamicBlur && liquidGlass;

  TempoAppearanceSettings copyWith({
    bool? reduceAnimation,
    bool? reduceDynamicBlur,
    bool? liquidGlass,
    bool? betterGlassPerformance,
    bool? progressiveBlur,
  }) {
    return TempoAppearanceSettings(
      reduceAnimation: reduceAnimation ?? this.reduceAnimation,
      reduceDynamicBlur: reduceDynamicBlur ?? this.reduceDynamicBlur,
      liquidGlass: liquidGlass ?? this.liquidGlass,
      betterGlassPerformance:
          betterGlassPerformance ?? this.betterGlassPerformance,
      progressiveBlur: progressiveBlur ?? this.progressiveBlur,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TempoAppearanceSettings &&
          other.reduceAnimation == reduceAnimation &&
          other.reduceDynamicBlur == reduceDynamicBlur &&
          other.liquidGlass == liquidGlass &&
          other.betterGlassPerformance == betterGlassPerformance &&
          other.progressiveBlur == progressiveBlur;

  @override
  int get hashCode => Object.hash(
        reduceAnimation,
        reduceDynamicBlur,
        liquidGlass,
        betterGlassPerformance,
        progressiveBlur,
      );
}

/// Global singleton persisting and broadcasting Tempo's Appearance preferences
/// with instant synchronous reads (zero BuildContext cost inside routes &
/// RenderObjects) and `SharedPreferences` storage.
class TempoAppearanceService {
  static const String _kReduceAnimation = 'tempo_reduce_animation_v1';
  static const String _kReduceDynamicBlur = 'tempo_reduce_dynamic_blur_v1';
  static const String _kLiquidGlass = 'tempo_liquid_glass_v1';
  static const String _kBetterGlassPerf = 'tempo_glass_performance_v1';
  static const String _kProgressiveBlur = 'tempo_progressive_blur_v1';

  static final TempoAppearanceService instance = TempoAppearanceService._();

  TempoAppearanceService._();

  final ValueNotifier<TempoAppearanceSettings> notifier =
      ValueNotifier<TempoAppearanceSettings>(const TempoAppearanceSettings());

  bool _loaded = false;

  TempoAppearanceSettings get value => notifier.value;

  bool get reduceAnimation => value.reduceAnimation;
  bool get reduceDynamicBlur => value.reduceDynamicBlur;
  bool get liquidGlass => value.liquidGlass;
  bool get betterGlassPerformance => value.betterGlassPerformance;
  bool get progressiveBlur => value.progressiveBlur;

  /// True when the active appearance toggles match the chipset's recommended
  /// defaults from [DevicePerformanceService].
  bool get isUsingRecommendedDefaults =>
      value == DevicePerformanceService.instance.recommendedSettings;

  Future<void> initialize({bool forceReload = false}) async {
    if (_loaded && !forceReload) return;
    _loaded = true;
    final defaults = DevicePerformanceService.instance.recommendedSettings;
    try {
      final prefs = await SharedPreferences.getInstance();
      final next = TempoAppearanceSettings(
        reduceAnimation:
            prefs.getBool(_kReduceAnimation) ?? defaults.reduceAnimation,
        reduceDynamicBlur:
            prefs.getBool(_kReduceDynamicBlur) ?? defaults.reduceDynamicBlur,
        liquidGlass: prefs.getBool(_kLiquidGlass) ?? defaults.liquidGlass,
        betterGlassPerformance: prefs.getBool(_kBetterGlassPerf) ??
            defaults.betterGlassPerformance,
        progressiveBlur:
            prefs.getBool(_kProgressiveBlur) ?? defaults.progressiveBlur,
      );
      if (notifier.value != next) {
        notifier.value = next;
      }
    } catch (_) {
      if (notifier.value != defaults) {
        notifier.value = defaults;
      }
    }
  }

  /// Restores the chipset-recommended default configuration and clears manual
  /// overrides so future launches continue following the device profile.
  Future<void> resetToDeviceDefaults() async {
    final defaults = DevicePerformanceService.instance.recommendedSettings;
    if (notifier.value != defaults) {
      notifier.value = defaults;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await Future.wait([
        prefs.remove(_kReduceAnimation),
        prefs.remove(_kReduceDynamicBlur),
        prefs.remove(_kLiquidGlass),
        prefs.remove(_kBetterGlassPerf),
        prefs.remove(_kProgressiveBlur),
      ]);
    } catch (_) {}
  }

  Future<void> setReduceAnimation(bool enabled) async {
    if (value.reduceAnimation == enabled) return;
    notifier.value = value.copyWith(reduceAnimation: enabled);
    await _persistBool(_kReduceAnimation, enabled);
  }

  Future<void> setReduceDynamicBlur(bool enabled) async {
    if (value.reduceDynamicBlur == enabled) return;
    notifier.value = value.copyWith(reduceDynamicBlur: enabled);
    await _persistBool(_kReduceDynamicBlur, enabled);
  }

  Future<void> setLiquidGlass(bool enabled) async {
    if (value.liquidGlass == enabled) return;
    notifier.value = value.copyWith(liquidGlass: enabled);
    await _persistBool(_kLiquidGlass, enabled);
  }

  Future<void> setBetterGlassPerformance(bool enabled) async {
    if (value.betterGlassPerformance == enabled) return;
    notifier.value = value.copyWith(betterGlassPerformance: enabled);
    await _persistBool(_kBetterGlassPerf, enabled);
  }

  Future<void> setProgressiveBlur(bool enabled) async {
    if (value.progressiveBlur == enabled) return;
    notifier.value = value.copyWith(progressiveBlur: enabled);
    await _persistBool(_kProgressiveBlur, enabled);
  }

  Future<void> _persistBool(String key, bool val) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, val);
    } catch (_) {}
  }

  @visibleForTesting
  void resetForTest([
    TempoAppearanceSettings initial = const TempoAppearanceSettings(),
  ]) {
    _loaded = false;
    notifier.value = initial;
  }
}
