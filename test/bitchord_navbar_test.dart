import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tempo_fitness/screens/appearance_settings_screen.dart';
import 'package:tempo_fitness/screens/my_profile.dart';
import 'package:tempo_fitness/services/active_profile_provider.dart';
import 'package:tempo_fitness/services/appearance_service.dart';
import 'package:tempo_fitness/services/tempo_rust_db.dart';
import 'package:tempo_fitness/theme/app_theme.dart';
import 'package:tempo_fitness/theme/theme_provider.dart';
import 'package:tempo_fitness/widgets/bitchord_glass_lens.dart';
import 'package:tempo_fitness/widgets/bitchord_pill_motion.dart';
import 'package:tempo_fitness/widgets/bitchord_segmented_slider.dart';
import 'package:tempo_fitness/widgets/liquid_glass_nav_bar.dart';
import 'package:tempo_fitness/widgets/liquid_glass_surface.dart';
import 'package:tempo_fitness/widgets/reorderable_summary_grid.dart';
import 'package:tempo_fitness/widgets/tempo_sliver_header.dart';

void main() {
  group('BitChordPillMotion 120Hz spring & squash physics', () {
    test('tap lifts crystal glass with underdamped X overshoot, acceleration squash, and clean flat landing', () {
      final motion = BitChordPillMotion(
        vsync: const TestVSync(),
        initialIndex: 0,
      )..stepDp = 96.0;

      expect(motion.isFlat, isTrue);
      motion.animateTo(2);
      expect(motion.isFlat, isFalse);

      double maxLiftX = 0.0;
      double maxMaterial = 0.0;
      double maxAbsDeviation = 0.0;
      bool settled = false;

      // Simulate 120Hz frames (1/120 s) for up to 2.5 seconds
      double t = 0.0;
      const dt = 1.0 / 120.0;
      for (int i = 0; i < 300; i++) {
        t += dt;
        final keepGoing = motion.stepFrame(dt, t);
        if (motion.liftX > maxLiftX) maxLiftX = motion.liftX;
        if (motion.material > maxMaterial) maxMaterial = motion.material;
        if (motion.deviation.abs() > maxAbsDeviation) {
          maxAbsDeviation = motion.deviation.abs();
        }
        if (!keepGoing) {
          settled = true;
          break;
        }
      }

      expect(settled, isTrue);
      expect(motion.isFlat, isTrue);
      expect(motion.position, closeTo(2.0, 0.005));
      // Decoupled X lift spring (zeta = 0.60) overshoots > 1.0 like BitChord
      expect(maxLiftX, greaterThan(1.02));
      // Fast material spring engages fully
      expect(maxMaterial, greaterThan(0.95));
      // 2nd-derivative acceleration squash engages cleanly within ±12%
      expect(maxAbsDeviation, greaterThan(0.005));
      expect(maxAbsDeviation, lessThanOrEqualTo(0.1201));

      motion.dispose();
    });

    test('exponential finger chase glides smoothly with edge rubber-band and respects reduceMotion', () {
      final motion = BitChordPillMotion(
        vsync: const TestVSync(),
        initialIndex: 0,
      )..stepDp = 90.0;

      motion.startDrag(initialPosition: 0.0);
      motion.dragTo(2.4, itemCount: 4);

      // Single 8.33ms frame chases smoothly without teleporting
      motion.stepFrame(1.0 / 120.0, 1.0 / 120.0);
      expect(motion.position, greaterThan(0.0));
      expect(motion.position, lessThan(1.0));

      // Edge rubber-band beyond last tab resists smoothly within +0.22
      motion.dragTo(4.8, itemCount: 4);
      double t = 1.0 / 120.0;
      for (int i = 0; i < 60; i++) {
        t += 1.0 / 120.0;
        motion.stepFrame(1.0 / 120.0, t);
      }
      expect(motion.position, greaterThan(3.0));
      expect(motion.position, lessThan(3.25));

      // Release snaps back onto valid tab 3
      motion.release(3);
      for (int i = 0; i < 240; i++) {
        t += 1.0 / 120.0;
        if (!motion.stepFrame(1.0 / 120.0, t)) break;
      }
      expect(motion.isFlat, isTrue);
      expect(motion.position, closeTo(3.0, 0.005));

      // Reduce animation snaps immediately with zero lift
      motion.reduceMotion = true;
      motion.animateTo(1);
      expect(motion.isFlat, isTrue);
      expect(motion.position, equals(1.0));
      expect(motion.material, equals(0.0));

      motion.dispose();
    });
  });

  group('BitChord LiquidGlassNavBar zero-slop scrub, hover, and Appearance modes', () {
    testWidgets(
      'scrubs smoothly across tabs, lifts on tap, handles mouse hover, and respects Appearance toggles',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        TempoAppearanceService.instance.resetForTest();
        final themeProvider = ThemeProvider();
        int current = 0;

        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: themeProvider,
            child: StatefulBuilder(
              builder: (context, setState) => MaterialApp(
                home: Scaffold(
                  bottomNavigationBar: LiquidGlassNavBar(
                    currentIndex: current,
                    onTap: (idx) => setState(() => current = idx),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Tap tab 2 -> lifts lens & switches tab cleanly
        await tester.tap(find.text('Progress'));
        await tester.pump(const Duration(milliseconds: 60));
        await tester.pumpAndSettle();
        expect(current, equals(2));

        // 2. Smooth horizontal finger scrub across the interactive capsule from Progress -> Summary
        final capsuleRect = tester.getRect(
          find.descendant(
            of: find.byType(LiquidGlassNavBar),
            matching: find.byType(MouseRegion),
          ),
        );
        final gesture = await tester.startGesture(
          Offset(capsuleRect.left + capsuleRect.width * 0.62, capsuleRect.center.dy),
        );
        await tester.pump(const Duration(milliseconds: 16));
        await gesture.moveTo(
          Offset(capsuleRect.left + capsuleRect.width * 0.35, capsuleRect.center.dy),
        );
        await tester.pump(const Duration(milliseconds: 16));
        await gesture.moveTo(
          Offset(capsuleRect.left + capsuleRect.width * 0.12, capsuleRect.center.dy),
        );
        await tester.pump(const Duration(milliseconds: 16));
        await gesture.up();
        await tester.pumpAndSettle();
        expect(current, equals(0));

        // 3. Mouse hover sweeps smoothly and releases cleanly on exit
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        await tester.pump();
        await mouse.moveTo(
          Offset(capsuleRect.left + capsuleRect.width * 0.38, capsuleRect.center.dy),
        );
        await tester.pump(const Duration(milliseconds: 60));
        await mouse.moveTo(const Offset(5, 5));
        await tester.pumpAndSettle();
        await mouse.removePointer();

        // 4. Toggle Better Performance for Glass, Liquid Glass OFF, Reduce Dynamic Blur, Dark Mode
        final svc = TempoAppearanceService.instance;
        await svc.setBetterGlassPerformance(true);
        await tester.pumpAndSettle();
        await svc.setLiquidGlass(false);
        await tester.pumpAndSettle();
        await svc.setReduceDynamicBlur(true);
        await tester.pumpAndSettle();
        await themeProvider.toggleTheme(true);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        svc.resetForTest();
      },
    );
  });

  group('Appearance Settings screen & persistence', () {
    testWidgets(
      'accessible from Profile and toggles Theme (System/Light/Dark) + all 5 visual settings',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final appearance = TempoAppearanceService.instance;
        appearance.resetForTest();
        await appearance.initialize();

        final db = TempoRustDb.instance;
        await db.init();
        final profile = await db.createProfile(
          displayName: 'Kenji',
          pin: '1234',
          heightCm: 173,
          weightKg: 62,
        );
        final activeProfileProvider = ActiveProfileProvider();
        await activeProfileProvider.initialize();
        await activeProfileProvider.switchProfileWithPin(profile.id, '1234');
        final themeProvider = ThemeProvider();

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: themeProvider),
              ChangeNotifierProvider.value(value: activeProfileProvider),
            ],
            child: const MaterialApp(home: MyProfile()),
          ),
        );
        await tester.pumpAndSettle();

        // Tap 'Appearance' under Preferences (and verify redundant 'Dark mode' is removed!)
        expect(find.text('Appearance'), findsOneWidget);
        expect(find.text('Dark mode'), findsNothing);
        await tester.tap(find.text('Appearance'));
        await tester.pumpAndSettle();
        expect(find.byType(AppearanceSettingsScreen), findsOneWidget);

        // Verify all 6 requested Appearance controls + icons on Glass & Effects sub-rows
        expect(find.text('Theme'), findsOneWidget);
        expect(find.text('System'), findsOneWidget);
        expect(find.text('Light'), findsOneWidget);
        expect(find.text('Dark'), findsOneWidget);
        expect(find.text('Reduce animation'), findsOneWidget);
        expect(find.text('Reduce Dynamic Blur'), findsOneWidget);
        expect(find.text('Liquid Glass'), findsOneWidget);
        expect(find.text('Better Performance for Glass'), findsOneWidget);
        expect(find.text('Progressive Blur'), findsOneWidget);
        expect(find.byIcon(CupertinoIcons.speedometer), findsOneWidget);
        expect(find.byIcon(CupertinoIcons.layers_alt_fill), findsOneWidget);

        // Switch Theme -> Dark -> System
        await tester.tap(find.text('Dark'));
        await tester.pumpAndSettle();
        expect(themeProvider.themeMode, equals(ThemeMode.dark));
        await tester.tap(find.text('System'));
        await tester.pumpAndSettle();
        expect(themeProvider.themeMode, equals(ThemeMode.system));

        // Toggle visual switches & verify persistence state
        await tester.ensureVisible(find.text('Reduce animation'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Reduce animation'));
        await tester.pumpAndSettle();
        expect(appearance.reduceAnimation, isTrue);

        await tester.ensureVisible(find.text('Better Performance for Glass'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Better Performance for Glass'));
        await tester.pumpAndSettle();
        expect(appearance.betterGlassPerformance, isTrue);

        await tester.ensureVisible(find.text('Progressive Blur'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Progressive Blur'));
        await tester.pumpAndSettle();
        expect(appearance.progressiveBlur, isFalse);

        await tester.ensureVisible(find.text('Liquid Glass'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Liquid Glass'));
        await tester.pumpAndSettle();
        expect(appearance.liquidGlass, isFalse);

        await tester.ensureVisible(find.text('Reduce Dynamic Blur'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Reduce Dynamic Blur'));
        await tester.pumpAndSettle();
        expect(appearance.reduceDynamicBlur, isTrue);
        expect(tester.takeException(), isNull);

        appearance.resetForTest();
        await db.deleteProfile(profile.id);
      },
    );
  });

  group('Faded Frosted Header Blur & Dragged Summary Card Liquid Glass', () {
    testWidgets(
      'TempoSliverHeader mounts borderless FrostedFadeBlurBackdrop on scroll and ReorderableSummaryGrid lifts with BitChordGlassLensBox',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final appearance = TempoAppearanceService.instance;
        appearance.resetForTest();
        final themeProvider = ThemeProvider();
        List<String> order = ['sleep', 'weight', 'bmi', 'water'];

        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: themeProvider,
            child: StatefulBuilder(
              builder: (context, setState) => MaterialApp(
                home: Scaffold(
                  body: CustomScrollView(
                    slivers: [
                      const TempoSliverHeader(title: 'Progress'),
                      SliverPadding(
                        padding: const EdgeInsets.all(16),
                        sliver: SliverToBoxAdapter(
                          child: Column(
                            children: [
                              ReorderableSummaryGrid(
                                itemIds: order,
                                itemBuilder: (_, id, isDragging) => Container(
                                  color: isDragging
                                      ? Colors.transparent
                                      : Colors.white,
                                  alignment: Alignment.center,
                                  child: Text('Card $id'),
                                ),
                                onReorder: (next) =>
                                    setState(() => order = next),
                              ),
                              const SizedBox(height: 600),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Scroll up to engage TempoSliverHeader's borderless FrostedFadeBlurBackdrop
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -180));
        await tester.pumpAndSettle();
        expect(find.byType(FrostedFadeBlurBackdrop), findsOneWidget);

        // Turning off Progressive Blur toggles enableFrostedBlur cleanly to false
        await appearance.setProgressiveBlur(false);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<FrostedFadeBlurBackdrop>(
                find.byType(FrostedFadeBlurBackdrop),
              )
              .enableFrostedBlur,
          isFalse,
        );
        await appearance.setProgressiveBlur(true);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<FrostedFadeBlurBackdrop>(
                find.byType(FrostedFadeBlurBackdrop),
              )
              .enableFrostedBlur,
          isTrue,
        );

        // Scroll back to top and long-press drag Card sleep across Card weight
        await tester.drag(find.byType(CustomScrollView), const Offset(0, 180));
        await tester.pumpAndSettle();

        final sleepCenter = tester.getCenter(find.text('Card sleep'));
        final weightCenter = tester.getCenter(find.text('Card weight'));
        final drag = await tester.startGesture(sleepCenter);
        await tester.pump(const Duration(milliseconds: 650));
        expect(find.byType(BitChordGlassLensBox), findsOneWidget);
        await drag.moveTo(weightCenter);
        await tester.pump(const Duration(milliseconds: 60));
        await drag.up();
        await tester.pumpAndSettle();

        // Glass lens detaches cleanly at rest (0% GPU cost) and order updated!
        expect(find.byType(BitChordGlassLensBox), findsNothing);
        expect(order.first, equals('weight'));

        // Verify Dark Mode + Better Performance for Glass render cleanly
        await themeProvider.toggleTheme(true);
        await appearance.setBetterGlassPerformance(true);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        appearance.resetForTest();
      },
    );

    testWidgets(
      'BitChordSegmentedSlider slides smoothly across Latest | Week | M | Y and responds to taps in Light & Dark Mode',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final appearance = TempoAppearanceService.instance;
        appearance.resetForTest();
        final themeProvider = ThemeProvider();
        int selected = 0;

        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: themeProvider,
            child: StatefulBuilder(
              builder: (context, setState) => MaterialApp(
                home: Scaffold(
                  body: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: BitChordSegmentedSlider(
                        labels: const ['Latest', 'Week', 'M', 'Y'],
                        selectedIndex: selected,
                        onChanged: (idx) => setState(() => selected = idx),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Tap 'M' -> lifts crystal glass lens & selects index 2
        await tester.tap(find.text('M'));
        await tester.pump(const Duration(milliseconds: 60));
        await tester.pumpAndSettle();
        expect(selected, equals(2));

        // Slide smoothly horizontally from 'M' -> 'Y' -> 'Latest'
        final mCenter = tester.getCenter(find.text('M'));
        final yCenter = tester.getCenter(find.text('Y'));
        final latestCenter = tester.getCenter(find.text('Latest'));

        final drag = await tester.startGesture(mCenter);
        await tester.pump(const Duration(milliseconds: 24));
        await drag.moveTo(yCenter);
        await tester.pump(const Duration(milliseconds: 24));
        expect(selected, equals(3));
        await drag.moveTo(latestCenter);
        await tester.pump(const Duration(milliseconds: 24));
        await drag.up();
        await tester.pumpAndSettle();
        expect(selected, equals(0));

        await themeProvider.toggleTheme(true);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        appearance.resetForTest();
      },
    );

    testWidgets(
      'TempoBouncyButton compresses and rebounds cleanly on tap without errors',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final themeProvider = ThemeProvider();
        int taps = 0;

        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: themeProvider,
            child: MaterialApp(
              home: Scaffold(
                body: Center(
                  child: TempoBouncyButton(
                    onPressed: () => taps++,
                    child: const Text('Save goal'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final gesture = await tester.startGesture(
          tester.getCenter(find.text('Save goal')),
        );
        await tester.pump(const Duration(milliseconds: 60));
        await gesture.up();
        await tester.pump(const Duration(milliseconds: 120));
        await tester.pumpAndSettle();
        expect(find.byType(TempoTouchLightEffect), findsOneWidget);
        expect(taps, equals(1));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'TempoTouchLightSplashFactory and TempoGlassCircleButton bloom and settle cleanly in Light & Dark Mode',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final appearance = TempoAppearanceService.instance;
        appearance.resetForTest();
        final themeProvider = ThemeProvider();
        int filledTaps = 0;
        int circleTaps = 0;

        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: themeProvider,
            child: Consumer<ThemeProvider>(
              builder: (_, tp, __) => MaterialApp(
                theme: AppTheme.lightTheme,
                darkTheme: AppTheme.darkTheme,
                themeMode: tp.themeMode,
                home: Scaffold(
                  body: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FilledButton(
                          onPressed: () => filledTaps++,
                          child: const Text('Start Workout'),
                        ),
                        const SizedBox(height: 16),
                        TempoGlassCircleButton(
                          icon: const Icon(CupertinoIcons.add, size: 20),
                          onPressed: () => circleTaps++,
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

        expect(
          AppTheme.lightTheme.splashFactory,
          isA<TempoTouchLightSplashFactory>(),
        );
        expect(
          AppTheme.darkTheme.splashFactory,
          isA<TempoTouchLightSplashFactory>(),
        );

        // Quick tap on FilledButton (triggers TempoTouchLightSplashFactory)
        await tester.tap(find.text('Start Workout'));
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pumpAndSettle();
        expect(filledTaps, equals(1));

        // Hold + move finger slightly + release on circular glass button
        final cCenter = tester.getCenter(find.byType(TempoGlassCircleButton));
        final g = await tester.startGesture(cCenter);
        await tester.pump(const Duration(milliseconds: 60));
        await g.moveTo(cCenter + const Offset(6, -4));
        await tester.pump(const Duration(milliseconds: 50));
        await g.up();
        await tester.pumpAndSettle();
        expect(circleTaps, equals(1));

        // Repeat in Dark Mode
        await themeProvider.toggleTheme(true);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Start Workout'));
        await tester.pumpAndSettle();
        expect(filledTaps, equals(2));
        expect(tester.takeException(), isNull);

        appearance.resetForTest();
      },
    );
  });
}
