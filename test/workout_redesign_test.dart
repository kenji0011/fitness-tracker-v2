import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tempo_fitness/data/exercise_data2.dart';
import 'package:tempo_fitness/screens/workout_detail_screen.dart';
import 'package:tempo_fitness/screens/workout_screen.dart';
import 'package:tempo_fitness/services/active_profile_provider.dart';
import 'package:tempo_fitness/services/tempo_rust_db.dart';
import 'package:tempo_fitness/theme/theme_provider.dart';
import 'package:tempo_fitness/widgets/workout_program_card.dart';

void main() {
  group('Workout program grouping & calorie math', () {
    test('collapses all 31 exerciseWorkouts into 13 clean muscle programs sorted Easy -> Med -> Hard', () {
      final groups = groupExerciseWorkouts(exerciseWorkouts);
      expect(exerciseWorkouts.length, equals(31));
      expect(groups.length, equals(13));

      final chest = groups.firstWhere((g) => g.title == 'Chest Power');
      expect(chest.variants.map((v) => v.level).toList(), equals(['Easy', 'Medium', 'Hard']));
      expect(chest.resolveVariant().level, equals('Medium'));
      expect(chest.resolveVariant(selectedLevel: 'Hard').id, equals('chest_001'));

      for (final g in groups) {
        expect(g.title, isNot(contains('HARD')));
        expect(g.title, isNot(contains('MEDIUM')));
        expect(g.title, isNot(contains('EASY')));
        for (final v in g.variants) {
          expect(estimateWorkoutKcal(v), greaterThan(0));
        }
      }
    });
  });

  group('Redesigned WorkoutScreen Workouts & History sections', () {
    testWidgets(
      'colors finished difficulty green with zero bullets/checkmarks, renders upgraded History card & sheet, switches levels inline, maps Traps, and searches exercises',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 2.5;
        addTearDown(tester.view.reset);

        SharedPreferences.setMockInitialValues({});
        final db = TempoRustDb.instance;
        await db.init();
        final profile = await db.createProfile(
          displayName: 'Kenji',
          pin: '1234',
          heightCm: 173,
          weightKg: 62,
        );
        // Log Hard Chest Power as finished so we can verify both green difficulty
        // state on the card AND the upgraded History card + sheet!
        await db.logCompletedWorkout(
          profileId: profile.id,
          workoutId: 'chest_001',
          title: 'Chest Power Training HARD',
          durationLabel: '30 min',
          exercisesLabel: '5 exercises',
          level: 'Hard',
          bodyFocus: 'Chest',
          actualDurationSec: 1500,
          expectedDurationSec: 1800,
          caloriesBurned: 210,
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
            child: const MaterialApp(home: WorkoutScreen()),
          ),
        );
        await tester.pumpAndSettle();

        // Minimal History card displays clean latest session + relative date + session count (no icon clutter)
        expect(find.text('History'), findsOneWidget);
        expect(find.text('25m · 210 kcal'), findsOneWidget);
        expect(find.text('1 session'), findsOneWidget);
        expect(find.text('Today'), findsOneWidget);

        // Open History bottom sheet & verify minimal summary row + clean row layout + dismissal
        await tester.tap(find.text('All').first);
        await tester.pumpAndSettle();
        expect(find.text('Workout History'), findsOneWidget);
        expect(find.text('Sessions'), findsOneWidget);
        expect(find.text('Time'), findsOneWidget);
        expect(find.text('kcal'), findsOneWidget);
        expect(find.text('25m · 210 kcal · Hard'), findsOneWidget);
        await tester.tap(find.byIcon(CupertinoIcons.xmark));
        await tester.pumpAndSettle();
        expect(find.text('Workout History'), findsNothing);

        // 13 grouped programs badge + Chest Power card (default Medium = 25 min)
        expect(find.text('13'), findsOneWidget);
        final chestCard = find.ancestor(
          of: find.text('Chest Power'),
          matching: find.byType(WorkoutProgramCard),
        );
        expect(chestCard, findsOneWidget);
        await tester.ensureVisible(chestCard);
        await tester.pumpAndSettle();

        // Zero thumbnail checkmark, flame icon, list-bullet icon, or redundant 'Medium' pill
        expect(
          find.descendant(
            of: chestCard,
            matching: find.byIcon(CupertinoIcons.checkmark_alt),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: chestCard,
            matching: find.byIcon(CupertinoIcons.flame_fill),
          ),
          findsNothing,
        );
        expect(
          find.descendant(of: chestCard, matching: find.text('Medium')),
          findsNothing,
        );
        expect(
          find.descendant(of: chestCard, matching: find.textContaining('25 min')),
          findsOneWidget,
        );

        // Finished difficulty ('Hard') is emerald green; unfinished ('Easy'/'Med') are NOT green
        final lightGreen = completedDifficultyColor(isDark: false);
        final hardTextLight = tester.widget<Text>(
          find.descendant(of: chestCard, matching: find.text('Hard')),
        );
        final easyTextLight = tester.widget<Text>(
          find.descendant(of: chestCard, matching: find.text('Easy')),
        );
        expect(hardTextLight.style?.color, equals(lightGreen));
        expect(easyTextLight.style?.color, isNot(equals(lightGreen)));

        // Tap 'Hard' inline on Chest Power -> updates to 30 min & stays on WorkoutScreen!
        await tester.tap(
          find.descendant(of: chestCard, matching: find.text('Hard')),
        );
        await tester.pumpAndSettle();
        expect(find.byType(WorkoutDetailScreen), findsNothing);
        expect(
          find.descendant(of: chestCard, matching: find.textContaining('30 min')),
          findsOneWidget,
        );

        // Slide smoothly horizontally across the BitChord Liquid Glass difficulty slider
        // from 'Hard' back to 'Easy' -> updates live to 20 min & stays on WorkoutScreen!
        final hardCenter = tester.getCenter(
          find.descendant(of: chestCard, matching: find.text('Hard')),
        );
        final easyCenter = tester.getCenter(
          find.descendant(of: chestCard, matching: find.text('Easy')),
        );
        final slideGesture = await tester.startGesture(hardCenter);
        await tester.pump(const Duration(milliseconds: 24));
        await slideGesture.moveTo(
          Offset((hardCenter.dx + easyCenter.dx) * 0.5, hardCenter.dy),
        );
        await tester.pump(const Duration(milliseconds: 24));
        await slideGesture.moveTo(easyCenter);
        await tester.pump(const Duration(milliseconds: 24));
        await slideGesture.up();
        await tester.pumpAndSettle();
        expect(find.byType(WorkoutDetailScreen), findsNothing);
        expect(
          find.descendant(of: chestCard, matching: find.textContaining('20 min')),
          findsOneWidget,
        );

        // Slide back to 'Hard' so detail-screen navigation test below opens Hard variant
        final backGesture = await tester.startGesture(easyCenter);
        await tester.pump(const Duration(milliseconds: 24));
        await backGesture.moveTo(hardCenter);
        await tester.pump(const Duration(milliseconds: 24));
        await backGesture.up();
        await tester.pumpAndSettle();
        expect(
          find.descendant(of: chestCard, matching: find.textContaining('30 min')),
          findsOneWidget,
        );

        // Scroll back up so category chips sit cleanly below the pinned header,
        // then filter 'Back' -> Traps must appear (previously orphaned!)
        await tester.drag(find.byType(CustomScrollView), const Offset(0, 360));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Back').first);
        await tester.pumpAndSettle();
        expect(find.text('Traps'), findsOneWidget);
        expect(find.text('Back Lats'), findsOneWidget);

        // Scroll horizontal chip bar to reveal 'Shoulders' -> Traps also appears
        await tester.drag(find.text('Back').first, const Offset(-140, 0));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Shoulders').first);
        await tester.pumpAndSettle();
        expect(find.text('Shoulders'), findsWidgets);
        expect(find.text('Traps'), findsOneWidget);

        // Scroll chip bar back left, return to 'All', open search, search an exercise name
        await tester.drag(find.text('Shoulders').first, const Offset(220, 0));
        await tester.pumpAndSettle();
        await tester.tap(find.text('All').last);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Search workouts'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Barbell Bench Press');
        await tester.pumpAndSettle();
        expect(chestCard, findsOneWidget);

        // Tap Chest Power card -> launches WorkoutDetailScreen for the Hard variant!
        await tester.tap(
          find.descendant(of: chestCard, matching: find.text('Chest Power')),
        );
        await tester.pumpAndSettle();
        expect(find.byType(WorkoutDetailScreen), findsOneWidget);
        expect(find.text('Chest Power Training'), findsOneWidget);

        // Verify Dark Mode renders with zero errors & dark emerald finished color
        Navigator.of(tester.element(find.byType(WorkoutDetailScreen))).pop();
        await tester.pumpAndSettle();
        await themeProvider.toggleTheme(true);
        await tester.pumpAndSettle();
        final hardTextDark = tester.widget<Text>(
          find.descendant(of: chestCard, matching: find.text('Hard')),
        );
        expect(
          hardTextDark.style?.color,
          equals(completedDifficultyColor(isDark: true)),
        );
        expect(tester.takeException(), isNull);

        await db.deleteProfile(profile.id);
      },
    );
  });
}
