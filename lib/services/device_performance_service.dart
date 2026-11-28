import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'appearance_service.dart';

/// Performance tier calibrated for Tempo's Liquid Glass shaders, progressive
/// blur passes, and backdrop filter complexity.
enum DevicePerformanceTier {
  flagship(
    label: 'Flagship',
    summary: 'Full Liquid Glass refraction and progressive blur enabled',
  ),
  balanced(
    label: 'Balanced',
    summary: 'Frosted Liquid Glass enabled with lighter GPU shader load',
  ),
  lite(
    label: 'Lite',
    summary: 'Dynamic blur reduced for smoother frame pacing and battery life',
  );

  final String label;
  final String summary;

  const DevicePerformanceTier({
    required this.label,
    required this.summary,
  });
}

/// Snapshot of the physical device chipset and memory capacity reported by
/// `DeviceHardwareHelper.kt` (Android) or platform defaults.
@immutable
class DeviceHardwareProfile {
  final String socModel;
  final String socManufacturer;
  final String boardPlatform;
  final String chipname;
  final String hardware;
  final String board;
  final String deviceModel;
  final String manufacturer;
  final int totalRamMb;
  final bool isLowRamDevice;
  final int cpuCores;
  final int sdkInt;
  final double maxRefreshRateHz;

  const DeviceHardwareProfile({
    this.socModel = '',
    this.socManufacturer = '',
    this.boardPlatform = '',
    this.chipname = '',
    this.hardware = '',
    this.board = '',
    this.deviceModel = '',
    this.manufacturer = '',
    this.totalRamMb = 0,
    this.isLowRamDevice = false,
    this.cpuCores = 0,
    this.sdkInt = 0,
    this.maxRefreshRateHz = 60.0,
  });

  factory DeviceHardwareProfile.fromMap(Map<Object?, Object?> raw) {
    String str(String key) => (raw[key]?.toString() ?? '').trim();
    int integer(String key) {
      final v = raw[key];
      if (v is int) return v;
      if (v is num) return v.round();
      return int.tryParse(v?.toString() ?? '') ?? 0;
    }

    double dbl(String key, double fallback) {
      final v = raw[key];
      if (v is double) return v;
      if (v is num) return v.toDouble();
      return double.tryParse(v?.toString() ?? '') ?? fallback;
    }

    return DeviceHardwareProfile(
      socModel: str('socModel'),
      socManufacturer: str('socManufacturer'),
      boardPlatform: str('boardPlatform'),
      chipname: str('chipname'),
      hardware: str('hardware'),
      board: str('board'),
      deviceModel: str('deviceModel'),
      manufacturer: str('manufacturer'),
      totalRamMb: integer('totalRamMb'),
      isLowRamDevice: raw['isLowRamDevice'] == true,
      cpuCores: integer('cpuCores'),
      sdkInt: integer('sdkInt'),
      maxRefreshRateHz: dbl('maxRefreshRateHz', 60.0),
    );
  }

  /// Rounded RAM label matching how mobile devices advertise memory
  /// (e.g., `11350 MB` -> `12 GB RAM`).
  String get ramLabel {
    if (totalRamMb <= 0) return '';
    final gb = totalRamMb / 1024.0;
    const buckets = [2, 3, 4, 6, 8, 12, 16, 24];
    for (final b in buckets) {
      if (gb <= b + 0.35) {
        return '$b GB RAM';
      }
    }
    return '${gb.ceil()} GB RAM';
  }

  /// Primary raw chipset token available on this device.
  String get primaryChipToken {
    for (final candidate in [socModel, chipname, boardPlatform, hardware, board]) {
      final cleaned = candidate.trim();
      if (cleaned.isNotEmpty &&
          cleaned.toLowerCase() != 'unknown' &&
          cleaned.toLowerCase() != 'qcom') {
        return cleaned;
      }
    }
    return '';
  }

  String get combinedSearchKey =>
      '$socModel $chipname $boardPlatform $hardware $board $socManufacturer'
          .toUpperCase();
}

/// Complete classification outcome used by `TempoAppearanceService` and
/// `AppearanceSettingsScreen`.
@immutable
class DevicePerformanceRecommendation {
  final DevicePerformanceTier tier;
  final String chipsetDisplayName;
  final DeviceHardwareProfile profile;
  final TempoAppearanceSettings recommendedSettings;
  final bool isDetectedFromHardware;

  const DevicePerformanceRecommendation({
    required this.tier,
    required this.chipsetDisplayName,
    required this.profile,
    required this.recommendedSettings,
    required this.isDetectedFromHardware,
  });

  static const DevicePerformanceRecommendation defaultFlagship =
      DevicePerformanceRecommendation(
    tier: DevicePerformanceTier.flagship,
    chipsetDisplayName: 'Standard Device',
    profile: DeviceHardwareProfile(),
    recommendedSettings: TempoAppearanceSettings(
      reduceAnimation: false,
      reduceDynamicBlur: false,
      liquidGlass: true,
      betterGlassPerformance: false,
      progressiveBlur: true,
    ),
    isDetectedFromHardware: false,
  );
}

/// Pure-Dart deterministic chipset classifier mapping Android SoCs, RAM, and
/// OS capabilities to Tempo's recommended Liquid Glass settings.
class DeviceChipsetClassifier {
  DeviceChipsetClassifier._();

  static const TempoAppearanceSettings flagshipSettings =
      TempoAppearanceSettings(
    reduceAnimation: false,
    reduceDynamicBlur: false,
    liquidGlass: true,
    betterGlassPerformance: false,
    progressiveBlur: true,
  );

  static const TempoAppearanceSettings balancedSettings =
      TempoAppearanceSettings(
    reduceAnimation: false,
    reduceDynamicBlur: false,
    liquidGlass: true,
    betterGlassPerformance: true,
    progressiveBlur: false,
  );

  static const TempoAppearanceSettings liteSettings = TempoAppearanceSettings(
    reduceAnimation: false,
    reduceDynamicBlur: true,
    liquidGlass: false,
    betterGlassPerformance: true,
    progressiveBlur: false,
  );

  static TempoAppearanceSettings settingsForTier(DevicePerformanceTier tier) {
    return switch (tier) {
      DevicePerformanceTier.flagship => flagshipSettings,
      DevicePerformanceTier.balanced => balancedSettings,
      DevicePerformanceTier.lite => liteSettings,
    };
  }

  static const Map<String, String> _friendlyChipNames = {
    // Qualcomm Snapdragon Flagship
    'SM8850': 'Snapdragon 8 Elite Gen 5',
    'CANOE': 'Snapdragon 8 Elite Gen 5',
    'SM8750': 'Snapdragon 8 Elite',
    'SUN': 'Snapdragon 8 Elite',
    'SM8735': 'Snapdragon 8s Gen 4',
    'SM8650': 'Snapdragon 8 Gen 3',
    'PINEAPPLE': 'Snapdragon 8 Gen 3',
    'SM8635': 'Snapdragon 8s Gen 3',
    'SM8550': 'Snapdragon 8 Gen 2',
    'KALAMA': 'Snapdragon 8 Gen 2',
    'SM8475': 'Snapdragon 8+ Gen 1',
    'SM8450': 'Snapdragon 8 Gen 1',
    'TARO': 'Snapdragon 8 Gen 1',
    'SM8350': 'Snapdragon 888',
    'LAHAINA': 'Snapdragon 888',
    'SM7675': 'Snapdragon 7+ Gen 3',
    'SM7475': 'Snapdragon 7+ Gen 2',
    // Qualcomm Snapdragon Mid-Range
    'SM8250': 'Snapdragon 870 / 865',
    'KONA': 'Snapdragon 865',
    'SM7550': 'Snapdragon 7 Gen 3',
    'SM7635': 'Snapdragon 7s Gen 3',
    'SM7450': 'Snapdragon 7 Gen 1',
    'SM7435': 'Snapdragon 7s Gen 2',
    'SM7325': 'Snapdragon 778G',
    'SM6450': 'Snapdragon 6 Gen 1',
    'SM6475': 'Snapdragon 6 Gen 3',
    // Qualcomm Entry / Budget
    'SM6375': 'Snapdragon 695',
    'SM6225': 'Snapdragon 680 / 685',
    'SM6115': 'Snapdragon 662',
    'SM4450': 'Snapdragon 4 Gen 2',
    'SM4375': 'Snapdragon 4 Gen 1',
    'SM4350': 'Snapdragon 480',
    'BENGAL': 'Snapdragon 662 / 460',
    'HOLI': 'Snapdragon 480',
    // MediaTek Dimensity Flagship
    'MT6993': 'Dimensity 9500',
    'MT6991': 'Dimensity 9400',
    'MT6989': 'Dimensity 9300',
    'MT6985': 'Dimensity 9200',
    'MT6983': 'Dimensity 9000',
    'MT6899': 'Dimensity 8400',
    'MT6897': 'Dimensity 8300',
    'MT6896': 'Dimensity 8200',
    // MediaTek Mid-Range
    'MT6895': 'Dimensity 8100',
    'MT6893': 'Dimensity 1200 / 8050',
    'MT6886': 'Dimensity 7200',
    'MT6878': 'Dimensity 7300',
    'MT6877': 'Dimensity 1080 / 7050',
    // MediaTek Entry / Helio
    'MT6855': 'Dimensity 7020',
    'MT6853': 'Dimensity 720 / 800U',
    'MT6835': 'Dimensity 6100+ / 6300',
    'MT6833': 'Dimensity 700 / 6020',
    'MT6789': 'Helio G99 / G100',
    'MT6781': 'Helio G96',
    'MT6769': 'Helio G85 / G80',
    'MT6768': 'Helio G88 / G85',
    'MT6765': 'Helio P35 / G37',
    // Samsung Exynos
    'S5E9965': 'Exynos 2600',
    'S5E9955': 'Exynos 2500',
    'S5E9945': 'Exynos 2400',
    'S5E9925': 'Exynos 2200',
    'S5E9840': 'Exynos 2100',
    'S5E8855': 'Exynos 1580',
    'S5E8845': 'Exynos 1480',
    'S5E8835': 'Exynos 1380',
    'S5E8825': 'Exynos 1280',
    'S5E3830': 'Exynos 850',
    // Google Tensor
    'GS501': 'Google Tensor G5',
    'LAGUNA': 'Google Tensor G5',
    'GS401': 'Google Tensor G4',
    'ZUMA PRO': 'Google Tensor G4',
    'ZUMAPRO': 'Google Tensor G4',
    'ZUMA': 'Google Tensor G3',
    'GS301': 'Google Tensor G3',
    'GS201': 'Google Tensor G2',
    'GS101': 'Google Tensor G1',
    // HiSilicon Kirin
    'KIRIN9020': 'Kirin 9020',
    'KIRIN9010': 'Kirin 9010',
    'KIRIN9000S': 'Kirin 9000S',
    'KIRIN9000': 'Kirin 9000',
  };

  static final List<RegExp> _flagshipPatterns = [
    // Qualcomm 8-series modern & 7+ Gen 2/3
    RegExp(r'\bSM8[3-9]\d{2}\b'),
    RegExp(r'\bSM7(475|675)\b'),
    RegExp(r'\b(CANOE|SUN|PINEAPPLE|KALAMA|TARO|LAHAINA)\b'),
    RegExp(r'SNAPDRAGON\s*8\s*(ELITE|GEN|S\s*GEN|88)'),
    // MediaTek Dimensity 9000+ & 8200+
    RegExp(r'\bMT69\d{2}\b'),
    RegExp(r'\bMT689[6-9]\b'),
    RegExp(r'DIMENSITY\s*(9\d{3}|8[2-9]\d{2})'),
    // Samsung Exynos 2200+
    RegExp(r'\bS5E99\d{2}\b'),
    RegExp(r'\bEXYNOS\s*2[2-9]\d{2}\b'),
    // Google Tensor G4 / G5
    RegExp(r'\b(GS401|GS501|ZUMAPRO|ZUMA\s+PRO|LAGUNA)\b'),
    RegExp(r'TENSOR\s*G[4-9]\b'),
    // HiSilicon Kirin 9000+
    RegExp(r'KIRIN\s*90\d{2}'),
  ];

  static final List<RegExp> _balancedPatterns = [
    // Qualcomm 7-series, 865/870, 6 Gen 1/3
    RegExp(r'\bSM8250\b'),
    RegExp(r'\bKONA\b'),
    RegExp(r'\bSM7[2-9]\d{2}\b'),
    RegExp(r'\bSM64\d{2}\b'),
    RegExp(r'SNAPDRAGON\s*(7|870|865|6\s*GEN)'),
    // MediaTek Dimensity 7000–8100 / 1080–1200
    RegExp(r'\bMT689[0-5]\b'),
    RegExp(r'\bMT688\d\b'),
    RegExp(r'\bMT687[7-9]\b'),
    RegExp(r'DIMENSITY\s*(8[01]\d{2}|7\d{3}|1[0-3]\d{2})'),
    // Samsung Exynos 1380–1580, 2100
    RegExp(r'\bS5E88[3-9]\d\b'),
    RegExp(r'\bS5E9840\b'),
    RegExp(r'\bEXYNOS\s*(1[3-9]\d{2}|2100)\b'),
    // Google Tensor G1–G3
    RegExp(r'\b(GS101|GS201|GS301|ZUMA)\b'),
    RegExp(r'TENSOR\s*G[1-3]\b'),
  ];

  static final List<RegExp> _litePatterns = [
    // Qualcomm entry 680/685/695/662/4-series
    RegExp(r'\bSM6[1-3]\d{2}\b'),
    RegExp(r'\bSM4\d{3}\b'),
    RegExp(r'\b(BENGAL|HOLI|TRINKET|BENGAL_515)\b'),
    RegExp(r'SNAPDRAGON\s*(4|680|685|695|662|665)'),
    // MediaTek Helio & Dimensity 6000 / 700 / 800
    RegExp(r'\bMT67\d{2}\b'),
    RegExp(r'\bMT68[35]\d\b'),
    RegExp(r'HELIO\s*[GPA]\d+'),
    RegExp(r'DIMENSITY\s*(6\d{3}|[78]\d{2})\b'),
    // Samsung Exynos 1280 / 850 / 9611
    RegExp(r'\bS5E8825\b'),
    RegExp(r'\bS5E38\d{2}\b'),
    RegExp(r'\bEXYNOS\s*(1280|850|9611)\b'),
    // Unisoc / Spreadtrum
    RegExp(r'\b(T6\d{2}|T7\d{2}|SC98\d{2}|UMS\d{3,4}|UNISOC|SPRD)\b'),
  ];

  /// Classifies [profile] deterministically into Flagship / Balanced / Lite.
  static DevicePerformanceRecommendation classify(
    DeviceHardwareProfile profile,
  ) {
    final search = profile.combinedSearchKey;
    final hasAnyHardwareInfo =
        search.trim().isNotEmpty || profile.totalRamMb > 0 || profile.sdkInt > 0;

    if (!hasAnyHardwareInfo) {
      return DevicePerformanceRecommendation.defaultFlagship;
    }

    final displayName = resolveDisplayName(profile);

    // Hard memory & OS safety guardrails override chipset marketing tier.
    if (profile.isLowRamDevice ||
        (profile.totalRamMb > 0 && profile.totalRamMb < 4500) ||
        (profile.sdkInt > 0 && profile.sdkInt < 29)) {
      return DevicePerformanceRecommendation(
        tier: DevicePerformanceTier.lite,
        chipsetDisplayName: displayName,
        profile: profile,
        recommendedSettings: liteSettings,
        isDetectedFromHardware: true,
      );
    }

    // 1. Check explicit Flagship SoCs (require >= 6.5 GB RAM class when RAM is known)
    if (_matchesAny(search, _flagshipPatterns)) {
      final hasFlagshipRam =
          profile.totalRamMb == 0 || profile.totalRamMb >= 6500;
      final tier = hasFlagshipRam
          ? DevicePerformanceTier.flagship
          : DevicePerformanceTier.balanced;
      return DevicePerformanceRecommendation(
        tier: tier,
        chipsetDisplayName: displayName,
        profile: profile,
        recommendedSettings: settingsForTier(tier),
        isDetectedFromHardware: true,
      );
    }

    // 2. Check explicit Entry / Lite SoCs before Balanced to prevent overlap
    if (_matchesAny(search, _litePatterns)) {
      return DevicePerformanceRecommendation(
        tier: DevicePerformanceTier.lite,
        chipsetDisplayName: displayName,
        profile: profile,
        recommendedSettings: liteSettings,
        isDetectedFromHardware: true,
      );
    }

    // 3. Check explicit Mid-Range / Balanced SoCs
    if (_matchesAny(search, _balancedPatterns)) {
      return DevicePerformanceRecommendation(
        tier: DevicePerformanceTier.balanced,
        chipsetDisplayName: displayName,
        profile: profile,
        recommendedSettings: balancedSettings,
        isDetectedFromHardware: true,
      );
    }

    // 4. Unknown SoC heuristic based on RAM + Android API level + refresh rate
    final DevicePerformanceTier fallbackTier;
    if (profile.totalRamMb >= 10500 &&
        profile.sdkInt >= 33 &&
        profile.maxRefreshRateHz >= 115) {
      fallbackTier = DevicePerformanceTier.flagship;
    } else if (profile.totalRamMb >= 5500 || profile.totalRamMb == 0) {
      fallbackTier = DevicePerformanceTier.balanced;
    } else {
      fallbackTier = DevicePerformanceTier.lite;
    }

    return DevicePerformanceRecommendation(
      tier: fallbackTier,
      chipsetDisplayName: displayName,
      profile: profile,
      recommendedSettings: settingsForTier(fallbackTier),
      isDetectedFromHardware: true,
    );
  }

  static bool _matchesAny(String haystack, List<RegExp> patterns) {
    for (final p in patterns) {
      if (p.hasMatch(haystack)) return true;
    }
    return false;
  }

  /// Resolves a clean human-readable chipset name (e.g., `SM8850` ->
  /// `Snapdragon 8 Elite Gen 5`), falling back gracefully to raw SoC tokens.
  static String resolveDisplayName(DeviceHardwareProfile profile) {
    final candidates = [
      profile.socModel,
      profile.chipname,
      profile.boardPlatform,
      profile.hardware,
      profile.board,
    ];
    for (final raw in candidates) {
      final upper = raw.trim().toUpperCase();
      if (upper.isEmpty) continue;
      if (_friendlyChipNames.containsKey(upper)) {
        return _friendlyChipNames[upper]!;
      }
      for (final entry in _friendlyChipNames.entries) {
        if (upper.contains(entry.key)) {
          return entry.value;
        }
      }
    }

    final primary = profile.primaryChipToken;
    if (primary.isNotEmpty) {
      if (profile.socManufacturer.isNotEmpty &&
          !primary.toUpperCase().contains(
                profile.socManufacturer.toUpperCase(),
              ) &&
          profile.socManufacturer.toUpperCase() != 'QTI') {
        return '${profile.socManufacturer} $primary';
      }
      return primary;
    }

    if (profile.deviceModel.isNotEmpty) {
      return profile.deviceModel;
    }
    return 'Standard Device';
  }
}

/// Global singleton querying native Android hardware specs once at startup and
/// exposing chipset-calibrated defaults for `TempoAppearanceService`.
class DevicePerformanceService {
  static const MethodChannel _channel =
      MethodChannel('com.tempo.fitness/device_hardware');

  static final DevicePerformanceService instance = DevicePerformanceService._();

  DevicePerformanceService._();

  final ValueNotifier<DevicePerformanceRecommendation> notifier =
      ValueNotifier<DevicePerformanceRecommendation>(
    DevicePerformanceRecommendation.defaultFlagship,
  );

  bool _loaded = false;

  DevicePerformanceRecommendation get recommendation => notifier.value;
  DevicePerformanceTier get tier => notifier.value.tier;
  DeviceHardwareProfile get profile => notifier.value.profile;
  TempoAppearanceSettings get recommendedSettings =>
      notifier.value.recommendedSettings;

  Future<void> initialize({bool forceReload = false}) async {
    if (_loaded && !forceReload) return;
    _loaded = true;

    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      notifier.value = DevicePerformanceRecommendation.defaultFlagship;
      return;
    }

    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        'getHardwareProfile',
      );
      if (raw != null) {
        final hw = DeviceHardwareProfile.fromMap(raw);
        notifier.value = DeviceChipsetClassifier.classify(hw);
      }
    } catch (_) {
      // Headless tests or older embeds without native channel: keep safe default.
      notifier.value = DevicePerformanceRecommendation.defaultFlagship;
    }
  }

  @visibleForTesting
  void setRecommendationForTest(DevicePerformanceRecommendation rec) {
    _loaded = true;
    notifier.value = rec;
  }

  @visibleForTesting
  void resetForTest() {
    _loaded = false;
    notifier.value = DevicePerformanceRecommendation.defaultFlagship;
  }
}
