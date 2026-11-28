import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tempo_fitness/screens/add_data_screen.dart';
import 'package:tempo_fitness/services/active_profile_provider.dart';
import 'package:tempo_fitness/services/appearance_service.dart';
import 'package:tempo_fitness/theme/app_theme.dart';
import 'package:tempo_fitness/theme/theme_provider.dart';
import 'package:tempo_fitness/widgets/liquid_glass_surface.dart';
import 'package:tempo_fitness/widgets/tempo_morph_calendar.dart';
import 'package:tempo_fitness/widgets/tempo_sliver_header.dart';
import 'package:tempo_fitness/widgets/tempo_wheel_picker.dart';

void main() {
  group('3D Cylindrical Wheel, Unified Morph Calendar & HyperOS Light Scatter', () {
    testWidgets(
      'TempoWheelColumn 3D drum scrolls, taps neighbor to center, and animates external preset changes',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final appearance = TempoAppearanceService.instance;
        appearance.resetForTest();
        final themeProvider = ThemeProvider();
        int selected = 2;

        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: themeProvider,
            child: StatefulBuilder(
              builder: (context, setState) => MaterialApp(
                theme: AppTheme.lightTheme,
                darkTheme: AppTheme.darkTheme,
                builder: (_, child) => TempoGlobalTouchLightHost(
                  child: child ?? const SizedBox.shrink(),
                ),
                home: Scaffold(
                  body: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TempoWheelStage(
                          children: [
                            TempoWheelColumn(
                              headerLabel: 'HRS',
                              items: const ['05', '06', '07', '08', '09', '10'],
                              initialIndex: selected,
                              offAxisFraction: -0.14,
                              onSelectedIndexChanged: (i) =>
                                  setState(() => selected = i),
                            ),
                          ],
                        ),
                        ElevatedButton(
                          onPressed: () => setState(() => selected = 4),
                          child: const Text('Jump 09'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Tap visible neighbor '08' -> smoothly spins to index 3
        await tester.tap(find.text('08'));
        await tester.pumpAndSettle();
        expect(selected, equals(3));

        // External preset jump -> spins smoothly to index 4 ('09')
        await tester.tap(find.text('Jump 09'));
        await tester.pumpAndSettle();
        expect(selected, equals(4));

        // Dark mode verification
        await themeProvider.toggleTheme(true);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        TempoGlobalTouchLight.instance.resetForTest();
        appearance.resetForTest();
      },
    );

    testWidgets(
      'showTempoMorphCalendar morphs from anchor pill, toggles month grid, and returns selected date',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final appearance = TempoAppearanceService.instance;
        appearance.resetForTest();
        final themeProvider = ThemeProvider();
        final pillKey = GlobalKey();
        DateTime? picked;
        final initial = DateTime(2026, 3, 15);

        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: themeProvider,
            child: Consumer<ThemeProvider>(
              builder: (_, tp, __) => MaterialApp(
                theme: AppTheme.lightTheme,
                darkTheme: AppTheme.darkTheme,
                themeMode: tp.themeMode,
                builder: (_, child) => TempoGlobalTouchLightHost(
                  child: child ?? const SizedBox.shrink(),
                ),
                home: Scaffold(
                  body: Center(
                    child: Builder(
                      builder: (ctx) => TempoLiquidButton(
                        key: pillKey,
                        primary: false,
                        borderRadius: 18,
                        onPressed: () async {
                          picked = await showTempoMorphCalendar(
                            context: ctx,
                            anchorKey: pillKey,
                            initialDate: initial,
                            firstDate: DateTime(2024, 1, 1),
                            lastDate: DateTime(2026, 12, 31),
                          );
                        },
                        child: const Text('Open Calendar'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Open morphing Liquid Glass calendar
        await tester.tap(find.text('Open Calendar'));
        await tester.pump(const Duration(milliseconds: 120));
        await tester.pumpAndSettle();
        expect(find.text('March 2026'), findsOneWidget);

        // Toggle inline Month/Year quick-jump grid and switch to February
        await tester.tap(find.text('March 2026'));
        await tester.pumpAndSettle();
        expect(find.text('Feb'), findsOneWidget);

        await tester.tap(find.text('Feb'));
        await tester.pumpAndSettle();
        expect(find.text('February 2026'), findsOneWidget);

        // Pick day 10 -> morphs smoothly back and returns DateTime(2026, 2, 10)
        await tester.tap(find.text('10'));
        await tester.pumpAndSettle();
        expect(picked, equals(DateTime(2026, 2, 10)));
        expect(activeTempoCalendarAnchorKey.value, isNull);
        expect(tester.takeException(), isNull);

        TempoGlobalTouchLight.instance.resetForTest();
        appearance.resetForTest();
      },
    );

    testWidgets(
      'Redesigned AddDataScreen switches horizontal metric rail, applies presets, and opens morph calendar for Steps too',
      (tester) async {
        tester.view.physicalSize = const Size(412 * 3, 892 * 3);
        tester.view.devicePixelRatio = 3.0;
        addTearDown(tester.view.reset);

        SharedPreferences.setMockInitialValues({});
        final appearance = TempoAppearanceService.instance;
        appearance.resetForTest();
        final themeProvider = ThemeProvider();
        final profileProvider = ActiveProfileProvider();

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: themeProvider),
              ChangeNotifierProvider.value(value: profileProvider),
            ],
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              darkTheme: AppTheme.darkTheme,
              builder: (_, child) => TempoGlobalTouchLightHost(
                child: child ?? const SizedBox.shrink(),
              ),
              home: const AddDataScreen(initialMetric: 'sleep'),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Sleep presets visible & interactive
        expect(find.text('8h'), findsOneWidget);
        await tester.tap(find.text('8h'));
        await tester.pumpAndSettle();
        expect(find.text('8h 00m'), findsOneWidget);

        // Switch to Steps on the horizontal glass pill rail — Date pill stays available!
        await tester.tap(find.text('Steps'));
        await tester.pumpAndSettle();
        expect(find.text('10k'), findsOneWidget);
        expect(find.text('Date'), findsOneWidget);

        await tester.tap(find.text('10k'));
        await tester.pumpAndSettle();
        expect(find.text('10,000'), findsOneWidget);

        // Open morph calendar from Date pill
        await tester.tap(find.text('Date'));
        await tester.pumpAndSettle();
        expect(find.text('MON'), findsOneWidget);

        // Dismiss calendar by tapping barrier corner
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        TempoGlobalTouchLight.instance.resetForTest();
        appearance.resetForTest();
      },
    );

    testWidgets(
      'HyperOS TempoGlobalTouchLight scatters live proximity light to adjacent glass surfaces and settles to 0',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final appearance = TempoAppearanceService.instance;
        appearance.resetForTest();
        final themeProvider = ThemeProvider();
        final light = TempoGlobalTouchLight.instance;
        light.resetForTest();

        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: themeProvider,
            child: MaterialApp(
              theme: AppTheme.darkTheme,
              builder: (_, child) => TempoGlobalTouchLightHost(
                child: child ?? const SizedBox.shrink(),
              ),
              home: Scaffold(
                body: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const LiquidGlassSurface(
                        borderRadius: 22,
                        child: SizedBox(width: 220, height: 52),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TempoGlassCircleButton(
                            key: const ValueKey('btn_left'),
                            icon: const Icon(CupertinoIcons.minus, size: 20),
                            onPressed: () {},
                          ),
                          const SizedBox(width: 18),
                          TempoGlassCircleButton(
                            key: const ValueKey('btn_right'),
                            icon: const Icon(CupertinoIcons.add, size: 20),
                            onPressed: () {},
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(light.hasHost, isTrue);
        expect(light.intensity, equals(0.0));

        // Press and hold right glass circle -> activates global point light
        final rightCenter = tester.getCenter(find.byKey(const ValueKey('btn_right')));
        final gesture = await tester.startGesture(rightCenter);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 90));
        expect(light.intensity, greaterThan(0.5));
        expect(light.activeSourceId, isNotNull);
        expect((light.globalPosition - rightCenter).distance, lessThan(2.0));

        // Drag finger slightly -> global point light tracks live for neighboring glass rims
        final moved = rightCenter + const Offset(-10, -6);
        await gesture.moveTo(moved);
        await tester.pump(const Duration(milliseconds: 16));
        expect((light.globalPosition - moved).distance, lessThan(2.0));

        // Release -> finishes smooth fade back to 0.0 & clears activeSourceId
        await gesture.up();
        await tester.pumpAndSettle();
        expect(light.intensity, equals(0.0));
        expect(light.activeSourceId, isNull);

        // Reduce animation disables global light cleanly
        await appearance.setReduceAnimation(true);
        await tester.pumpAndSettle();
        final g2 = await tester.startGesture(rightCenter);
        await tester.pump(const Duration(milliseconds: 90));
        expect(light.intensity, equals(0.0));
        await g2.up();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        light.resetForTest();
        appearance.resetForTest();
      },
    );
  });
}
