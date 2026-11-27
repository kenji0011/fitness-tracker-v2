import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:tempo_fitness/services/animation_speed_service.dart';
import 'package:tempo_fitness/theme/app_colors.dart';
import 'package:tempo_fitness/theme/theme_provider.dart';
import 'package:tempo_fitness/widgets/hyperos_dropdown_menu.dart';
import 'package:tempo_fitness/widgets/ios_popover_menu.dart';
import 'package:tempo_fitness/widgets/ios_stretch_sheet.dart';
import 'package:tempo_fitness/widgets/tempo_morph_route.dart';
import 'package:tempo_fitness/widgets/tempo_spring_physics.dart';

class _LifecycleProbePage extends StatefulWidget {
  final VoidCallback onInit;
  final VoidCallback onDeactivate;

  const _LifecycleProbePage({
    required this.onInit,
    required this.onDeactivate,
  });

  @override
  State<_LifecycleProbePage> createState() => _LifecycleProbePageState();
}

class _LifecycleProbePageState extends State<_LifecycleProbePage> {
  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  void deactivate() {
    widget.onDeactivate();
    super.deactivate();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      backgroundColor: c.scaffold,
      body: Center(
        child: ElevatedButton(
          onPressed: () => Navigator.of(context).pop<String>('done'),
          child: const Text('Close Probe'),
        ),
      ),
    );
  }
}

Widget _wrapApp(Widget home) {
  return ChangeNotifierProvider<ThemeProvider>(
    create: (_) => ThemeProvider(),
    child: MaterialApp(home: home),
  );
}

void main() {
  setUp(() {
    TempoAnimationSpeedService.instance
        .resetForTest(TempoAnimationSpeed.balanced);
    activeTempoMorphAnchorKey.value = null;
    activeTempoPopoverAnchorKey.value = null;
  });

  group('TempoSpringCurves physics invariants', () {
    test('exact endpoints 0.0 -> 0.0 and 1.0 -> 1.0 across all presets', () {
      final allCurves = <String, TempoSpringCurve>{
        'morphOpen': TempoSpringCurves.morphOpen,
        'morphClose': TempoSpringCurves.morphClose,
        'dropletOpenSize': TempoSpringCurves.dropletOpenSize,
        'dropletOpenCenter': TempoSpringCurves.dropletOpenCenter,
        'dropletCloseSize': TempoSpringCurves.dropletCloseSize,
        'dropletCloseCenter': TempoSpringCurves.dropletCloseCenter,
        'popoverOpenCenter': TempoSpringCurves.popoverOpenCenter,
        'popoverOpenSize': TempoSpringCurves.popoverOpenSize,
        'popoverCloseSize': TempoSpringCurves.popoverCloseSize,
        'popoverCloseCenter': TempoSpringCurves.popoverCloseCenter,
        'dropdownUnfold': TempoSpringCurves.dropdownUnfold,
        'dropdownFoldClose': TempoSpringCurves.dropdownFoldClose,
        'sheetOpen': TempoSpringCurves.sheetOpen,
        'sheetClose': TempoSpringCurves.sheetClose,
        'photoOpen': TempoSpringCurves.photoOpen,
        'photoClose': TempoSpringCurves.photoClose,
      };

      for (final entry in allCurves.entries) {
        final curve = entry.value;
        expect(curve.transform(0.0), equals(0.0), reason: '${entry.key} start');
        expect(curve.transform(1.0), equals(1.0), reason: '${entry.key} end');
        for (int i = 1; i < 100; i++) {
          final v = curve.transform(i / 100.0);
          expect(v.isFinite, isTrue, reason: '${entry.key} finite at $i%');
          expect(v, greaterThanOrEqualTo(0.0));
          expect(v, lessThanOrEqualTo(curve.maxClamp));
        }
      }
    });

    test('open curves stay monotonic and close curves deliver tasteful dock bounce with bounded 120Hz step', () {
      final monotonicOpenCurves = <String, TempoSpringCurve>{
        'morphOpen': TempoSpringCurves.morphOpen,
        'dropletOpenSize': TempoSpringCurves.dropletOpenSize,
        'dropletOpenCenter': TempoSpringCurves.dropletOpenCenter,
        'photoOpen': TempoSpringCurves.photoOpen,
        'photoClose': TempoSpringCurves.photoClose,
      };

      // 50 steps simulates 120Hz over ~420ms (~8.33ms per tick).
      const steps = 50;
      for (final entry in monotonicOpenCurves.entries) {
        double prev = 0.0;
        double maxDelta = 0.0;
        for (int i = 1; i <= steps; i++) {
          final cur = entry.value.transform(i / steps);
          expect(
            cur,
            greaterThanOrEqualTo(prev - 1e-6),
            reason: '${entry.key} must not dip backward at step $i',
          );
          final delta = cur - prev;
          if (delta > maxDelta) maxDelta = delta;
          prev = cur;
        }
        expect(
          maxDelta,
          lessThan(0.085),
          reason: '${entry.key} 120Hz single-frame jump too steep ($maxDelta)',
        );
      }

      // Close dock-bounce springs should exhibit real tasteful overshoot (> 1.02, < 1.15)
      // while remaining velocity-bounded at 120Hz and settling cleanly to exact 1.0.
      final dockBounceCurves = <String, TempoSpringCurve>{
        'morphClose': TempoSpringCurves.morphClose,
        'dropletCloseSize': TempoSpringCurves.dropletCloseSize,
        'dropletCloseCenter': TempoSpringCurves.dropletCloseCenter,
        'popoverCloseSize': TempoSpringCurves.popoverCloseSize,
        'popoverCloseCenter': TempoSpringCurves.popoverCloseCenter,
        'dropdownFoldClose': TempoSpringCurves.dropdownFoldClose,
      };
      for (final entry in dockBounceCurves.entries) {
        double prev = 0.0;
        double peak = 0.0;
        double maxDelta = 0.0;
        for (int i = 1; i <= steps; i++) {
          final cur = entry.value.transform(i / steps);
          if (cur > peak) peak = cur;
          final delta = (cur - prev).abs();
          if (delta > maxDelta) maxDelta = delta;
          prev = cur;
        }
        expect(
          peak,
          inInclusiveRange(1.02, 1.15),
          reason: '${entry.key} should produce subtle elastic dock bounce ($peak)',
        );
        expect(
          maxDelta,
          lessThan(0.095),
          reason: '${entry.key} 120Hz single-frame step too steep ($maxDelta)',
        );
      }
    });
  });

  group('TempoMorphPageRoute zero-reparent & deferred close guarantees', () {
    testWidgets(
      'preserves child State with ZERO deactivate calls across open -> settled -> close',
      (tester) async {
        int initCount = 0;
        int deactivateCount = 0;
        final anchorKey = GlobalKey();
        String? routeResult;
        bool futureResolved = false;

        await tester.pumpWidget(
          _wrapApp(
            Scaffold(
              body: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Builder(
                    builder: (ctx) => GestureDetector(
                      key: anchorKey,
                      onTap: () async {
                        final res = await pushTempoMorphRoute<String>(
                          context: ctx,
                          sourceKey: anchorKey,
                          sourceBorderRadius: 999,
                          builder: (_) => _LifecycleProbePage(
                            onInit: () => initCount++,
                            onDeactivate: () => deactivateCount++,
                          ),
                        );
                        routeResult = res;
                        futureResolved = true;
                      },
                      child: const SizedBox.square(
                        dimension: 42,
                        child: ColoredBox(color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        // Trigger circular morph open.
        await tester.tap(find.byKey(anchorKey));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(initCount, equals(1));
        expect(deactivateCount, equals(0));
        expect(identical(activeTempoMorphAnchorKey.value, anchorKey), isTrue);

        // Settle open transition.
        await tester.pumpAndSettle();
        expect(initCount, equals(1));
        expect(
          deactivateCount,
          equals(0),
          reason: 'Settling at t=1.0 must NOT reparent child or call deactivate',
        );
        expect(activeTempoMorphAnchorKey.value, isNull);

        // Trigger close via button tap.
        await tester.tap(find.text('Close Probe'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 40));

        // Frame 0-3 of close: child stays invariant (zero deactivate!), anchor
        // is suppressed while droplet flies, and caller Future waits for landing!
        expect(
          deactivateCount,
          equals(0),
          reason: 'Starting close transition must NOT reparent child',
        );
        expect(identical(activeTempoMorphAnchorKey.value, anchorKey), isTrue);
        expect(
          futureResolved,
          isFalse,
          reason: 'waitForCloseAnimation=true must defer caller reload until close finishes',
        );

        // Complete close animation.
        await tester.pumpAndSettle();
        expect(futureResolved, isTrue);
        expect(routeResult, equals('done'));
        expect(activeTempoMorphAnchorKey.value, isNull);
        // Only the final route removal on dispose deactivates the popped page once.
        expect(deactivateCount, equals(1));
      },
    );

    testWidgets(
      '56x56 squircle app icon suppresses anchor cleanly and closes 1:1 like Workout launchers',
      (tester) async {
        final squircleKey = GlobalKey();
        await tester.pumpWidget(
          _wrapApp(
            Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Builder(
                    builder: (ctx) => GestureDetector(
                      onTap: () => pushTempoMorphRoute<void>(
                        context: ctx,
                        sourceKey: squircleKey,
                        sourceBorderRadius: 18,
                        sourceColor: const Color(0xFF4AD95A),
                        builder: (_) => _LifecycleProbePage(
                          onInit: () {},
                          onDeactivate: () {},
                        ),
                      ),
                      child: RepaintBoundary(
                        key: squircleKey,
                        child: Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: const Color(0xFF4AD95A),
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.byKey(squircleKey));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        expect(identical(activeTempoMorphAnchorKey.value, squircleKey), isTrue);

        await tester.pumpAndSettle();
        expect(activeTempoMorphAnchorKey.value, isNull);

        final route = ModalRoute.of(
          tester.element(find.text('Close Probe')),
        )! as TempoMorphPageRoute<void>;
        await tester.tap(find.text('Close Probe'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 280));
        expect(identical(activeTempoMorphAnchorKey.value, squircleKey), isTrue);
        final rect = route.debugLastMorphRect;
        expect(rect, isNotNull);
        expect((rect!.width - rect.height).abs(), lessThan(2.0));

        await tester.pumpAndSettle();
        expect(activeTempoMorphAnchorKey.value, isNull);
      },
    );

    testWidgets(
      'waitForCloseAnimation: false resolves immediately on Navigator.pop()',
      (tester) async {
        bool resolved = false;
        await tester.pumpWidget(
          _wrapApp(
            Scaffold(
              body: Builder(
                builder: (ctx) => ElevatedButton(
                  onPressed: () async {
                    await pushTempoMorphRoute<String>(
                      context: ctx,
                      waitForCloseAnimation: false,
                      builder: (_) => _LifecycleProbePage(
                        onInit: () {},
                        onDeactivate: () {},
                      ),
                    );
                    resolved = true;
                  },
                  child: const Text('Open Immediate'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Immediate'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Close Probe'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));

        expect(resolved, isTrue);
        await tester.pumpAndSettle();
      },
    );
  });

  group('Popover, Dropdown, and Bottom Sheet smooth transitions', () {
    testWidgets('popover, dropdown, and sheet open & dismiss cleanly without errors', (tester) async {
      final anchorKey = GlobalKey();
      final rowKey = GlobalKey();
      String? pickedDropdown;

      await tester.pumpWidget(
        _wrapApp(
          Scaffold(
            body: Column(
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: Builder(
                    builder: (ctx) => GestureDetector(
                      key: anchorKey,
                      behavior: HitTestBehavior.opaque,
                      onTap: () => showTempoPopoverMenu(
                        context: ctx,
                        anchorKey: anchorKey,
                        actions: [
                          TempoPopoverAction(label: 'Action One', onTap: () {}),
                        ],
                      ),
                      child: const SizedBox.square(
                        dimension: 42,
                        child: ColoredBox(color: Colors.white),
                      ),
                    ),
                  ),
                ),
                Builder(
                  builder: (ctx) => GestureDetector(
                    key: rowKey,
                    onTap: () async {
                      pickedDropdown = await showHyperOsDropdownMenu<String>(
                        context: ctx,
                        rowKey: rowKey,
                        selectedValue: 'balanced',
                        options: const [
                          HyperOsDropdownOption(value: 'relaxed', label: 'Relaxed'),
                          HyperOsDropdownOption(value: 'balanced', label: 'Balanced'),
                          HyperOsDropdownOption(value: 'fast', label: 'Fast'),
                        ],
                      );
                    },
                    child: const SizedBox(
                      width: 240,
                      height: 48,
                      child: Text('Speed Row'),
                    ),
                  ),
                ),
                Builder(
                  builder: (ctx) => ElevatedButton(
                    onPressed: () => showTempoSheet<void>(
                      context: ctx,
                      showDragHandle: true,
                      builder: (_) => const SizedBox(
                        height: 220,
                        child: Center(child: Text('Sheet Body')),
                      ),
                    ),
                    child: const Text('Open Sheet'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      // 1. Popover open & close
      await tester.tap(find.byKey(anchorKey));
      await tester.pumpAndSettle();
      expect(find.text('Action One'), findsOneWidget);
      await tester.tap(find.text('Action One'));
      await tester.pumpAndSettle();
      expect(activeTempoPopoverAnchorKey.value, isNull);

      // 2. Dropdown open & select
      await tester.tap(find.text('Speed Row'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fast'));
      await tester.pumpAndSettle();
      expect(pickedDropdown, equals('fast'));

      // 3. Bottom sheet open & dismiss
      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();
      expect(find.text('Sheet Body'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.text('Sheet Body'), findsNothing);
    });

    testWidgets(
      'rapid single-tap re-opens popover and morph route immediately mid-close with 0ms delay',
      (tester) async {
        final popKey = GlobalKey();
        final morphKey = GlobalKey();
        int morphOpenCount = 0;
        int popoverOpenCount = 0;

        await tester.pumpWidget(
          _wrapApp(
            Scaffold(
              body: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Builder(
                    builder: (ctx) => GestureDetector(
                      key: morphKey,
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        morphOpenCount++;
                        pushTempoMorphRoute<void>(
                          context: ctx,
                          sourceKey: morphKey,
                          sourceBorderRadius: 999,
                          builder: (_) => _LifecycleProbePage(
                            onInit: () {},
                            onDeactivate: () {},
                          ),
                        );
                      },
                      child: const SizedBox.square(
                        dimension: 42,
                        child: ColoredBox(color: Colors.blue),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Builder(
                    builder: (ctx) => GestureDetector(
                      key: popKey,
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        popoverOpenCount++;
                        showTempoPopoverMenu(
                          context: ctx,
                          anchorKey: popKey,
                          actions: [
                            TempoPopoverAction(label: 'Quick Item', onTap: () {}),
                          ],
                        );
                      },
                      child: const SizedBox.square(
                        dimension: 42,
                        child: ColoredBox(color: Colors.green),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

        // 1. Popover: open -> tap outside to close -> ONLY 80ms later single-tap again!
        await tester.tap(find.byKey(popKey));
        await tester.pumpAndSettle();
        expect(popoverOpenCount, equals(1));
        await tester.tapAt(const Offset(20, 300)); // dismiss popover
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 80)); // mid-close!

        await tester.tap(find.byKey(popKey)); // single tap — MUST NOT be blocked!
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 120));
        expect(
          popoverOpenCount,
          equals(2),
          reason: 'Closing popover barrier must not eat taps mid-close',
        );
        await tester.pumpAndSettle();
        expect(find.text('Quick Item'), findsOneWidget);
        await tester.tapAt(const Offset(20, 300));
        await tester.pumpAndSettle();

        // 2. Morph route: open -> pop -> ONLY 80ms later single-tap again!
        await tester.tap(find.byKey(morphKey));
        await tester.pumpAndSettle();
        expect(morphOpenCount, equals(1));
        await tester.tap(find.text('Close Probe'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 80)); // mid-close!

        await tester.tap(find.byKey(morphKey)); // single tap — MUST NOT be blocked!
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 120));
        expect(
          morphOpenCount,
          equals(2),
          reason: 'Closing morph route barrier must not eat taps mid-close',
        );
        await tester.pumpAndSettle();
        expect(find.text('Close Probe'), findsOneWidget);
      },
    );
  });
}
