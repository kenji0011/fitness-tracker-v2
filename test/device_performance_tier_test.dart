import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tempo_fitness/screens/appearance_settings_screen.dart';
import 'package:tempo_fitness/services/appearance_service.dart';
import 'package:tempo_fitness/services/device_performance_service.dart';
import 'package:tempo_fitness/theme/theme_provider.dart';

void main() {
  tearDown(() {
    DevicePerformanceService.instance.resetForTest();
    TempoAppearanceService.instance.resetForTest();
  });

  group('DeviceChipsetClassifier', () {
    test('classifies flagship Qualcomm, MediaTek, Exynos, and Tensor SoCs', () {
      final sm8850 = DeviceChipsetClassifier.classify(
        const DeviceHardwareProfile(
          socModel: 'SM8850',
          socManufacturer: 'QTI',
          boardPlatform: 'canoe',
          totalRamMb: 11350,
          sdkInt: 37,
          maxRefreshRateHz: 120.0,
        ),
      );
      expect(sm8850.tier, DevicePerformanceTier.flagship);
      expect(sm8850.chipsetDisplayName, 'Snapdragon 8 Elite Gen 5');
      expect(sm8850.recommendedSettings.liquidGlass, isTrue);
      expect(sm8850.recommendedSettings.betterGlassPerformance, isFalse);
      expect(sm8850.recommendedSettings.progressiveBlur, isTrue);
      expect(sm8850.recommendedSettings.reduceDynamicBlur, isFalse);

      final dimensity9400 = DeviceChipsetClassifier.classify(
        const DeviceHardwareProfile(
          socModel: 'MT6991',
          totalRamMb: 12288,
          sdkInt: 35,
        ),
      );
      expect(dimensity9400.tier, DevicePerformanceTier.flagship);
      expect(dimensity9400.chipsetDisplayName, 'Dimensity 9400');

      final exynos2400 = DeviceChipsetClassifier.classify(
        const DeviceHardwareProfile(
          socModel: 'S5E9945',
          totalRamMb: 8192,
          sdkInt: 34,
        ),
      );
      expect(exynos2400.tier, DevicePerformanceTier.flagship);
      expect(exynos2400.chipsetDisplayName, 'Exynos 2400');
    });

    test('classifies mid-range SoCs into balanced frosted glass tier', () {
      final sd7Gen3 = DeviceChipsetClassifier.classify(
        const DeviceHardwareProfile(
          socModel: 'SM7550',
          totalRamMb: 8192,
          sdkInt: 34,
        ),
      );
      expect(sd7Gen3.tier, DevicePerformanceTier.balanced);
      expect(sd7Gen3.chipsetDisplayName, 'Snapdragon 7 Gen 3');
      expect(sd7Gen3.recommendedSettings.liquidGlass, isTrue);
      expect(sd7Gen3.recommendedSettings.betterGlassPerformance, isTrue);
      expect(sd7Gen3.recommendedSettings.progressiveBlur, isFalse);
      expect(sd7Gen3.recommendedSettings.reduceDynamicBlur, isFalse);

      final dimensity7200 = DeviceChipsetClassifier.classify(
        const DeviceHardwareProfile(
          socModel: 'MT6886',
          totalRamMb: 8192,
          sdkInt: 34,
        ),
      );
      expect(dimensity7200.tier, DevicePerformanceTier.balanced);

      final unknown6Gb = DeviceChipsetClassifier.classify(
        const DeviceHardwareProfile(
          socModel: 'CUSTOM_MID_99',
          totalRamMb: 6000,
          sdkInt: 33,
        ),
      );
      expect(unknown6Gb.tier, DevicePerformanceTier.balanced);
    });

    test('classifies entry-level SoCs and low-RAM devices into lite tier', () {
      final sd680 = DeviceChipsetClassifier.classify(
        const DeviceHardwareProfile(
          socModel: 'SM6225',
          totalRamMb: 6144,
          sdkInt: 33,
        ),
      );
      expect(sd680.tier, DevicePerformanceTier.lite);
      expect(sd680.recommendedSettings.reduceDynamicBlur, isTrue);
      expect(sd680.recommendedSettings.liquidGlass, isFalse);

      final helioG99 = DeviceChipsetClassifier.classify(
        const DeviceHardwareProfile(
          socModel: 'MT6789',
          totalRamMb: 8192,
          sdkInt: 34,
        ),
      );
      expect(helioG99.tier, DevicePerformanceTier.lite);

      final unisoc = DeviceChipsetClassifier.classify(
        const DeviceHardwareProfile(
          socModel: 'T612',
          totalRamMb: 6144,
          sdkInt: 33,
        ),
      );
      expect(unisoc.tier, DevicePerformanceTier.lite);

      // Low RAM overrides even a flagship SoC code safely
      final lowRamGuard = DeviceChipsetClassifier.classify(
        const DeviceHardwareProfile(
          socModel: 'SM8650',
          totalRamMb: 3800,
          isLowRamDevice: true,
          sdkInt: 34,
        ),
      );
      expect(lowRamGuard.tier, DevicePerformanceTier.lite);
    });
  });

  group('TempoAppearanceService chipset defaults & user overrides', () {
    test('uses balanced defaults on clean install and honors manual overrides',
        () async {
      SharedPreferences.setMockInitialValues({});
      final balancedRec = DeviceChipsetClassifier.classify(
        const DeviceHardwareProfile(
          socModel: 'SM7550',
          totalRamMb: 8192,
          sdkInt: 34,
        ),
      );
      DevicePerformanceService.instance.setRecommendationForTest(balancedRec);

      await TempoAppearanceService.instance.initialize(forceReload: true);
      expect(TempoAppearanceService.instance.liquidGlass, isTrue);
      expect(TempoAppearanceService.instance.betterGlassPerformance, isTrue);
      expect(TempoAppearanceService.instance.progressiveBlur, isFalse);
      expect(TempoAppearanceService.instance.isUsingRecommendedDefaults, isTrue);

      // User manually enables Progressive Blur -> preserved across reload
      await TempoAppearanceService.instance.setProgressiveBlur(true);
      expect(TempoAppearanceService.instance.isUsingRecommendedDefaults, isFalse);

      await TempoAppearanceService.instance.initialize(forceReload: true);
      expect(TempoAppearanceService.instance.progressiveBlur, isTrue);

      // Restore recommended defaults -> resets back cleanly
      await TempoAppearanceService.instance.resetToDeviceDefaults();
      expect(TempoAppearanceService.instance.progressiveBlur, isFalse);
      expect(TempoAppearanceService.instance.isUsingRecommendedDefaults, isTrue);
    });
  });

  testWidgets(
    'AppearanceSettingsScreen displays chipset Device Profile and Restore Recommended',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final flagshipRec = DeviceChipsetClassifier.classify(
        const DeviceHardwareProfile(
          socModel: 'SM8850',
          socManufacturer: 'QTI',
          totalRamMb: 11350,
          sdkInt: 37,
          maxRefreshRateHz: 120.0,
        ),
      );
      DevicePerformanceService.instance.setRecommendationForTest(flagshipRec);
      await TempoAppearanceService.instance.initialize(forceReload: true);
      await TempoAppearanceService.instance.setProgressiveBlur(false);

      final themeProvider = ThemeProvider(autoLoad: false);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: themeProvider,
          child: const MaterialApp(
            home: AppearanceSettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -680));
      await tester.pumpAndSettle();

      expect(find.text('DEVICE PROFILE'), findsOneWidget);
      expect(find.text('Snapdragon 8 Elite Gen 5'), findsOneWidget);
      expect(find.text('Flagship'), findsOneWidget);
      expect(find.text('Restore Recommended'), findsOneWidget);

      await tester.ensureVisible(find.text('Restore Recommended'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restore Recommended'));
      await tester.pumpAndSettle();

      expect(TempoAppearanceService.instance.progressiveBlur, isTrue);
      expect(find.text('Restore Recommended'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
