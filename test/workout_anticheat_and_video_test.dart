import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tempo_fitness/models/workout_model.dart';
import 'package:tempo_fitness/screens/exercise_detail_screen.dart';
import 'package:tempo_fitness/screens/progress_tracking_screen.dart';
import 'package:tempo_fitness/screens/workout_detail_screen.dart';
import 'package:tempo_fitness/services/active_profile_provider.dart';
import 'package:tempo_fitness/services/goal_completion_service.dart';
import 'package:tempo_fitness/services/tempo_rust_db.dart';
import 'package:tempo_fitness/services/workout_anticheat_service.dart';
import 'package:tempo_fitness/theme/theme_provider.dart';
import 'package:tempo_fitness/widgets/tempo_liquid_video_player.dart';

Workout _sampleWorkout() {
  return Workout(
    id: 'chest_power_test',
    title: 'Chest Power Training',
    duration: '12 mins',
    exercises: '3 Exercises',
    level: 'Easy',
    bodyFocus: 'Chest',
    videoAsset: '',
    thumbnailAsset: '',
    description: 'Guided upper-body pressing circuit.',
    exerciseList: [
      Exercise(
        name: 'Barbell Bench Press',
        baseCaloriesPerMinute: 8,
        duration: 120,
        description: 'Lower barbell with control and press smoothly.',
      ),
      Exercise(
        name: 'Incline Dumbbell Press',
        baseCaloriesPerMinute: 8,
        duration: 120,
        description: 'Press dumbbells upward on an incline bench.',
      ),
      Exercise(
        name: 'Push-Up',
        baseCaloriesPerMinute: 7,
        duration: 120,
        description: 'Bodyweight pressing reps with braced core.',
      ),
    ],
  );
}

void main() {
  group('WorkoutAntiCheatEngine', () {
    test('blocks checking off exercises before start and during cooldown', () {
      int fakeElapsed = 0;
      final workout = _sampleWorkout();
      final engine = WorkoutAntiCheatEngine(
        workout: workout,
        elapsedSecondsProvider: () => fakeElapsed,
      );

      // Before start -> blocked with notStarted
      final beforeStart = engine.canCheckExercise(0);
      expect(beforeStart.allowed, isFalse);
      expect(beforeStart.reason, ExerciseLockReason.notStarted);

      final compBefore = engine.evaluateCompletion();
      expect(compBefore.canComplete, isFalse);
      expect(compBefore.hasStarted, isFalse);

      // Start session -> 25% of 120s = 30s per exercise required
      engine.start();
      fakeElapsed = 12;
      final tooFast = engine.tryVerifyExercise(0);
      expect(tooFast.allowed, isFalse);
      expect(tooFast.reason, ExerciseLockReason.cooldownRemaining);
      expect(tooFast.remainingSeconds, 18);
      expect(engine.verifiedCount, 0);

      // Reach 30s -> Exercise 0 unlocks and verifies cleanly
      fakeElapsed = 30;
      final ok0 = engine.tryVerifyExercise(0);
      expect(ok0.allowed, isTrue);
      expect(engine.verifiedCount, 1);

      // Rapid checkbox spam immediately at 35s -> Exercise 1 blocked (25s left)
      fakeElapsed = 35;
      final spam1 = engine.tryVerifyExercise(1);
      expect(spam1.allowed, isFalse);
      expect(spam1.remainingSeconds, 25);

      // Verify Exercise 1 at 65s and Exercise 2 at 100s
      fakeElapsed = 65;
      expect(engine.tryVerifyExercise(1).allowed, isTrue);
      fakeElapsed = 100;
      expect(engine.tryVerifyExercise(2).allowed, isTrue);

      // All 3 exercises verified, but minWorkoutSeconds = 35% of 360s = 126s
      final waitingTotal = engine.evaluateCompletion();
      expect(waitingTotal.canComplete, isFalse);
      expect(waitingTotal.missingExercises, 0);
      expect(waitingTotal.remainingTotalSeconds, 26);

      // At 126s -> completion unlocks!
      fakeElapsed = 126;
      final unlocked = engine.evaluateCompletion();
      expect(unlocked.canComplete, isTrue);
      expect(unlocked.statusLabel(), 'Complete Workout (3/3)');
    });

    test('calculates proportional verified calories fairly', () {
      int fakeElapsed = 0;
      final engine = WorkoutAntiCheatEngine(
        workout: _sampleWorkout(),
        elapsedSecondsProvider: () => fakeElapsed,
      );

      expect(engine.estimateVerifiedCalories(kcalPerMin: 8.0), 0);

      engine.start();
      fakeElapsed = 40;
      final earlyUnverified = engine.estimateVerifiedCalories(kcalPerMin: 8.0);
      expect(earlyUnverified, lessThan(10));

      engine.tryVerifyExercise(0);
      final oneVerified = engine.estimateVerifiedCalories(kcalPerMin: 8.0);

      fakeElapsed = 180;
      engine.tryVerifyExercise(1);
      fakeElapsed = 240;
      engine.tryVerifyExercise(2);
      final allVerified = engine.estimateVerifiedCalories(kcalPerMin: 8.0);
      expect(allVerified, greaterThan(oneVerified));
    });
  });

  testWidgets(
    'WorkoutDetailScreen enforces anti-cheat lock, shows rest banner, and unlocks CTA',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final db = TempoRustDb.instance;
      await db.init();
      final profile = await db.createProfile(
        displayName: 'Liam',
        pin: '1234',
        heightCm: 175,
        weightKg: 72,
      );
      final activeProfileProvider = ActiveProfileProvider();
      await activeProfileProvider.initialize();
      await activeProfileProvider.switchProfileWithPin(profile.id, '1234');
      final themeProvider = ThemeProvider(autoLoad: false);

      int fakeElapsed = 0;
      final workout = _sampleWorkout();
      final engine = WorkoutAntiCheatEngine(
        workout: workout,
        elapsedSecondsProvider: () => fakeElapsed,
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: themeProvider),
            ChangeNotifierProvider.value(value: activeProfileProvider),
          ],
          child: MaterialApp(
            home: WorkoutDetailScreen(
              workout: workout,
              engineOverride: engine,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Locked completion pill visible before starting
      expect(find.byKey(const ValueKey('workout_locked_cta')), findsOneWidget);
      expect(find.byKey(const ValueKey('workout_complete_cta')), findsNothing);
      expect(find.text('Start session to unlock completion'), findsOneWidget);

      // Start session & skip 3-2-1 countdown
      await tester.tap(find.text('Start'));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      // Advance fake monotonic time so Exercise 0 unlocks
      fakeElapsed = 35;
      await tester.pump(const Duration(seconds: 1));
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -180));
      await tester.pump();
      expect(find.text('Mark Done'), findsOneWidget);

      await tester.tap(find.text('Mark Done'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 240));
      await tester.pump(const Duration(milliseconds: 300));
      // Auto-appearing Liquid Glass rest banner appears
      expect(find.textContaining('Rest '), findsOneWidget);
      expect(find.text('+15s'), findsOneWidget);

      // Skip rest banner & pause cleanly before teardown
      await tester.tap(find.text('Skip'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('+15s'), findsNothing);

      await tester.tap(find.text('Pause'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await db.deleteProfile(profile.id);
    },
  );

  testWidgets(
    'ExerciseDetailScreen renders TempoLiquidVideoPlayer and Liquid Glass steppers',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final db = TempoRustDb.instance;
      await db.init();
      final profile = await db.createProfile(
        displayName: 'Maya',
        pin: '1234',
        heightCm: 165,
        weightKg: 58,
      );
      final activeProfileProvider = ActiveProfileProvider();
      await activeProfileProvider.initialize();
      await activeProfileProvider.switchProfileWithPin(profile.id, '1234');
      final themeProvider = ThemeProvider(autoLoad: false);
      final workout = _sampleWorkout();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: themeProvider),
            ChangeNotifierProvider.value(value: activeProfileProvider),
          ],
          child: MaterialApp(
            theme: ThemeData.dark(),
            home: ExerciseDetailScreen(
              exercise: workout.exerciseList.first,
              workout: workout,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TempoLiquidVideoPlayer), findsOneWidget);
      expect(find.text('Form video preview unavailable'), findsOneWidget);
      expect(find.text('Log Set & Mark Done'), findsOneWidget);

      // Step Sets from 3 -> 4 and Reps from 10 -> 11
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -450));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('step_reps_plus')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('step_sets_plus')));
      await tester.tap(find.byKey(const ValueKey('step_reps_plus')));
      await tester.pumpAndSettle();

      expect(find.text('4'), findsOneWidget);
      expect(find.text('11'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await db.deleteProfile(profile.id);
    },
  );

  testWidgets(
    'ProgressTrackingScreen preserves Streak/Energy/Heatmap and renders overhauled Liquid Glass hub',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final db = TempoRustDb.instance;
      await db.init();
      final profile = await db.createProfile(
        displayName: 'Noah',
        pin: '1234',
        heightCm: 178,
        weightKg: 75,
      );
      await db.logExerciseRecord(
        profileId: profile.id,
        exerciseName: 'Bench Press',
        workoutId: 'chest_power_test',
        weightUsed: 85.0,
        repsPerformed: 8,
        setsPerformed: 4,
        bodyFocus: 'Chest',
        level: 'Hard',
      );
      await db.logCompletedWorkout(
        profileId: profile.id,
        workoutId: 'chest_power_test',
        title: 'Chest Power Training',
        durationLabel: '21 mins',
        exercisesLabel: '7 Exercises',
        level: 'Hard',
        bodyFocus: 'Chest',
        actualDurationSec: 900,
        expectedDurationSec: 1260,
        caloriesBurned: 145,
        isCheated: false,
      );

      final activeProfileProvider = ActiveProfileProvider();
      await activeProfileProvider.initialize();
      await activeProfileProvider.switchProfileWithPin(profile.id, '1234');
      final themeProvider = ThemeProvider(autoLoad: false);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: themeProvider),
            ChangeNotifierProvider.value(value: activeProfileProvider),
          ],
          child: const MaterialApp(
            home: ProgressTrackingScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Preserved sections
      expect(find.text('Energy Burned'), findsOneWidget);
      expect(find.text('7D'), findsOneWidget);
      expect(find.text('Activity heatmap'), findsOneWidget);

      // Scroll to overhauled Bento + Training Records hub
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -680));
      await tester.pumpAndSettle();

      expect(find.text('Top Lift'), findsOneWidget);
      expect(find.text('Training Records'), findsOneWidget);
      expect(find.text('TOP PR'), findsOneWidget);
      expect(find.text('Bench Press'), findsWidgets);

      // Switch to Sessions tab -> shows Verified anti-cheat status pill
      await tester.ensureVisible(find.text('Sessions (1)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sessions (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Chest Power Training'), findsOneWidget);
      expect(find.text('Verified'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await db.deleteProfile(profile.id);
    },
  );

  testWidgets(
    'GoalCompletionService detects newly hit goals once per day and shows celebration sheet',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final db = TempoRustDb.instance;
      await db.init();
      final profile = await db.createProfile(
        displayName: 'Ava',
        pin: '1234',
        heightCm: 168,
        weightKg: 60,
        dailyCaloriesGoal: 500,
      );
      await db.upsertDailyActivity(
        profileId: profile.id,
        dateKey: TempoRustDb.todayKey(),
        calories: 550,
      );

      final firstHit = await GoalCompletionService.instance
          .evaluateNewCompletions(profileId: profile.id);
      expect(firstHit.length, 1);
      expect(firstHit.first.kind, DailyGoalKind.calories);
      expect(firstHit.first.percent, 110);

      // Deduplicated on subsequent evaluation the same day
      final secondHit = await GoalCompletionService.instance
          .evaluateNewCompletions(profileId: profile.id);
      expect(secondHit, isEmpty);

      // Render celebration modal cleanly
      final themeProvider = ThemeProvider(autoLoad: false);
      late BuildContext hostCtx;
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: themeProvider,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) {
                  hostCtx = ctx;
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      );

      final future = GoalCompletionService.instance.showCelebrationSheet(
        hostCtx,
        events: firstHit,
      );
      await tester.pumpAndSettle();

      expect(find.text('Calories Goal Reached'), findsOneWidget);
      expect(find.text('550 kcal'), findsOneWidget);
      expect(find.text('500 kcal'), findsOneWidget);
      expect(find.text('110%'), findsOneWidget);

      await tester.tap(find.text('Awesome'));
      await tester.pumpAndSettle();
      await future;
      expect(tester.takeException(), isNull);

      await db.deleteProfile(profile.id);
    },
  );
}
