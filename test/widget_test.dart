import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tempo_fitness/data/fitness_journey_workouts.dart';
import 'package:tempo_fitness/screens/fitness_journey_detail_screen.dart';
import 'package:tempo_fitness/screens/intro_walkthrough_screen.dart';
import 'package:tempo_fitness/screens/my_profile.dart';
import 'package:tempo_fitness/screens/profile_switcher_screen.dart';
import 'package:tempo_fitness/screens/progress_tracking_screen.dart';
import 'package:tempo_fitness/screens/workout_detail_screen.dart';
import 'package:tempo_fitness/screens/workout_screen.dart';
import 'package:tempo_fitness/services/active_profile_provider.dart';
import 'package:tempo_fitness/services/tempo_rust_db.dart';
import 'package:tempo_fitness/theme/theme_provider.dart';
import 'package:tempo_fitness/widgets/ios_stretch_sheet.dart';
import 'package:tempo_fitness/widgets/liquid_glass_nav_bar.dart';
import 'package:tempo_fitness/widgets/oval_activity_rings.dart';
import 'package:tempo_fitness/widgets/tempo_sliver_header.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ThemeProvider defaults to Light Mode and toggles to Dark Mode', () async {
    SharedPreferences.setMockInitialValues({});
    final provider = ThemeProvider();
    expect(provider.themeMode, ThemeMode.light);
    expect(provider.isDarkMode, false);

    await provider.toggleTheme(true);
    expect(provider.themeMode, ThemeMode.dark);
    expect(provider.isDarkMode, true);
  });

  test('Multi-profile local DB isolates data and enforces 4-digit PIN', () async {
    SharedPreferences.setMockInitialValues({});
    final db = TempoRustDb.instance;
    await db.init();

    final p1 = await db.createProfile(
      displayName: 'Alex',
      pin: '1234',
      heightCm: 175,
      weightKg: 70,
    );
    final p2 = await db.createProfile(
      displayName: 'Jordan',
      pin: '5678',
      heightCm: 165,
      weightKg: 60,
    );

    expect(await db.verifyPin(p1.id, '1234'), true);
    expect(await db.verifyPin(p1.id, '0000'), false);
    expect(await db.verifyPin(p2.id, '5678'), true);

    await db.logCompletedWorkout(
      profileId: p1.id,
      workoutId: 'w1',
      title: 'HIIT Circuit',
      actualDurationSec: 1200,
      caloriesBurned: 280,
    );

    final sum1 = await db.getDashboardSummary(p1.id);
    final sum2 = await db.getDashboardSummary(p2.id);

    expect(sum1.today.calories, 280);
    expect(sum1.totalWorkouts, 1);
    expect(sum2.today.calories, 0);
    expect(sum2.totalWorkouts, 0);

    expect(await db.deleteProfile(p1.id), true);
    expect(await db.deleteProfile(p2.id), true);
  });

  testWidgets('LiquidGlassNavBar renders 4 tabs and handles double-tap on Profile', (tester) async {
    SharedPreferences.setMockInitialValues({});
    int selected = 0;
    bool profileDoubleTapped = false;

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ThemeProvider(),
        child: MaterialApp(
          home: Scaffold(
            bottomNavigationBar: StatefulBuilder(
              builder: (context, setState) => LiquidGlassNavBar(
                currentIndex: selected,
                onTap: (i) => setState(() => selected = i),
                onProfileDoubleTap: () => profileDoubleTapped = true,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Summary'), findsOneWidget);
    expect(find.text('Workout'), findsOneWidget);
    expect(find.text('Progress'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);

    await tester.tap(find.text('Workout'));
    await tester.pumpAndSettle();
    expect(selected, 1);

    // Drag-scrub horizontally from Workout across to Progress
    final workoutCenter = tester.getCenter(find.text('Workout'));
    final progressCenter = tester.getCenter(find.text('Progress'));
    final dragGesture = await tester.startGesture(workoutCenter);
    await tester.pump(const Duration(milliseconds: 80));
    await dragGesture.moveTo(progressCenter);
    await tester.pump(const Duration(milliseconds: 120));
    await dragGesture.up();
    await tester.pumpAndSettle();
    expect(selected, 2);

    // Double-tap Profile tab
    await tester.tap(find.text('Profile'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(profileDoubleTapped, true);
  });

  testWidgets('OvalActivityRings animates and responds to ring taps in Light & Dark mode', (tester) async {
    SharedPreferences.setMockInitialValues({});
    int? tappedRing;

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ThemeProvider(),
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: OvalActivityRings(
                caloriesProgress: 0.35,
                stepsProgress: 0.62,
                minutesProgress: 0.0,
                onRingTap: (ring) => tappedRing = ring,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.byType(OvalActivityRings));
    await tester.pump();
    expect(tappedRing, isNotNull);
  });

  testWidgets('TempoSliverHeader collapses title to center and shows glass buttons on scroll', (tester) async {
    SharedPreferences.setMockInitialValues({});
    bool backed = false;

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ThemeProvider(),
        child: MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                TempoSliverHeader(
                  title: 'Summary',
                  showBackButton: true,
                  onBack: () => backed = true,
                ),
                SliverList.builder(
                  itemCount: 30,
                  itemBuilder: (_, i) => ListTile(title: Text('Row $i')),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // Expanded state: large title is visible on the left
    final expandedLeft = tester.getTopLeft(find.text('Summary').first).dx;
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
    await tester.pumpAndSettle();
    // Collapsed state: faded-in compact title is centered horizontally
    final collapsedLeft = tester.getTopLeft(find.text('Summary').first).dx;

    expect(collapsedLeft, greaterThan(expandedLeft));

    await tester.tap(find.byType(TempoBackChevron));
    await tester.pump();
    expect(backed, true);
  });

  testWidgets('ProgressTrackingScreen renders iOS 27 cards, timeframe toggle, and segment switcher cleanly', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final db = TempoRustDb.instance;
    await db.init();
    final profile = await db.createProfile(
      displayName: 'Kenji',
      pin: '1234',
      heightCm: 173,
      weightKg: 61,
    );
    await db.logCompletedWorkout(
      profileId: profile.id,
      workoutId: 'upper_1',
      title: 'Upper Power',
      actualDurationSec: 1800,
      caloriesBurned: 320,
    );
    await db.logExerciseRecord(
      profileId: profile.id,
      exerciseName: 'Bench Press',
      bodyFocus: 'Chest',
      setsPerformed: 4,
      repsPerformed: 8,
      weightUsed: 80,
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
        child: const MaterialApp(
          home: ProgressTrackingScreen(embedded: true),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Progress'), findsWidgets);
    expect(find.text('7D'), findsOneWidget);
    expect(find.text('14D'), findsOneWidget);
    expect(find.text('30D'), findsOneWidget);

    // Switch chart timeframe to 14D
    await tester.tap(find.text('14D'));
    await tester.pumpAndSettle();

    // Scroll down to reveal bento cards, segment switcher & PR list
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -440));
    await tester.pumpAndSettle();

    expect(find.text('Bench Press'), findsAtLeastNWidgets(1));

    // Expand Exercise PR card
    await tester.tap(find.text('Bench Press').last);
    await tester.pumpAndSettle();

    // Switch sliding segment bar to Sessions (1)
    await tester.tap(find.text('Sessions (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Upper Power'), findsOneWidget);

    // Verify Dark Mode compatibility without overflow
    await themeProvider.toggleTheme(true);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await db.deleteProfile(profile.id);
  });

  testWidgets('WorkoutScreen renders squircle launchers, History card, and Training indices cleanly', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final db = TempoRustDb.instance;
    await db.init();
    final profile = await db.createProfile(
      displayName: 'Kenji',
      pin: '1234',
      heightCm: 173,
      weightKg: 61,
    );
    await db.logCompletedWorkout(
      profileId: profile.id,
      workoutId: 'walk_1',
      title: 'Walking',
      durationLabel: '22 min',
      bodyFocus: 'Cardio',
      actualDurationSec: 1372,
      caloriesBurned: 124,
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
        child: const MaterialApp(
          home: WorkoutScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Workout'), findsWidgets);
    expect(find.text('HIIT Burn'), findsOneWidget);
    expect(find.text('Strength'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    expect(find.text('Workouts'), findsOneWidget);
    expect(find.text('Training indices'), findsNothing);

    await themeProvider.toggleTheme(true);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await db.deleteProfile(profile.id);
  });

  testWidgets('ProfileGateScreen hides dark/light toggle and 4-digit PIN lock clutter', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final db = TempoRustDb.instance;
    await db.init();
    final profile = await db.createProfile(
      displayName: 'kenji',
      pin: '1234',
      heightCm: 173,
      weightKg: 61,
    );

    final activeProfileProvider = ActiveProfileProvider();
    await activeProfileProvider.initialize();
    final themeProvider = ThemeProvider();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: themeProvider),
          ChangeNotifierProvider.value(value: activeProfileProvider),
        ],
        child: const MaterialApp(
          home: ProfileGateScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Choose Your Profile'), findsOneWidget);
    expect(find.text('kenji'), findsOneWidget);
    expect(find.text('Add Profile'), findsOneWidget);
    expect(find.text('4-digit PIN'), findsNothing);
    expect(find.byIcon(CupertinoIcons.lock_fill), findsNothing);
    expect(find.byIcon(CupertinoIcons.sun_max_fill), findsNothing);
    expect(find.byIcon(CupertinoIcons.moon_fill), findsNothing);
    expect(tester.takeException(), isNull);

    await db.deleteProfile(profile.id);
  });

  testWidgets('showTempoSheet opens with iOS spring, stretches upward, and dismisses on pull down', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ThemeProvider(),
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => Center(
                child: ElevatedButton(
                  onPressed: () {
                    showTempoSheet<void>(
                      context: ctx,
                      backgroundColor: Colors.white,
                      showDragHandle: true,
                      builder: (_) => const SizedBox(
                        height: 260,
                        child: Center(child: Text('Stretch Sheet Body')),
                      ),
                    );
                  },
                  child: const Text('Open Sheet'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();
    expect(find.text('Stretch Sheet Body'), findsOneWidget);

    // Pull upward to engage rubber-band stretch, then release to spring back
    final bodyCenter = tester.getCenter(find.text('Stretch Sheet Body'));
    final stretchGesture = await tester.startGesture(bodyCenter);
    await stretchGesture.moveBy(const Offset(0, -120));
    await tester.pump(const Duration(milliseconds: 60));
    await stretchGesture.up();
    await tester.pumpAndSettle();
    expect(find.text('Stretch Sheet Body'), findsOneWidget);

    // Drag downward past threshold to dismiss
    await tester.drag(find.text('Stretch Sheet Body'), const Offset(0, 260));
    await tester.pumpAndSettle();
    expect(find.text('Stretch Sheet Body'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('FitnessJourneyDetailScreen uses TempoSliverHeader without hero image', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final db = TempoRustDb.instance;
    await db.init();
    final profile = await db.createProfile(
      displayName: 'Kenji',
      pin: '1234',
      heightCm: 173,
      weightKg: 61,
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
        child: const MaterialApp(
          home: FitnessJourneyDetailScreen(
            journeyId: weightLossJourneyId,
            journeyName: 'Weight Loss',
            journeySubtitle: 'High-burn HIIT & metabolic conditioning',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TempoSliverHeader), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(find.text('Weight Loss'), findsWidgets);
    expect(find.text('Start Journey'), findsOneWidget);
    expect(find.text('Workouts'), findsOneWidget);

    await themeProvider.toggleTheme(true);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await db.deleteProfile(profile.id);
  });

  testWidgets('MyProfile renders clean identity row and single unified settings card', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final db = TempoRustDb.instance;
    await db.init();
    final profile = await db.createProfile(
      displayName: 'Ken ji',
      pin: '1234',
      gender: 'Male',
      age: 21,
      heightCm: 173,
      weightKg: 61,
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
        child: const MaterialApp(
          home: MyProfile(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ken ji'), findsOneWidget);
    expect(find.text('Male | 173cm | 61.0kg | 21'), findsOneWidget);
    expect(find.text('Dark mode'), findsOneWidget);
    expect(find.text('Switch profile'), findsOneWidget);
    expect(find.text('Competition'), findsNothing);
    expect(find.byIcon(CupertinoIcons.add), findsNothing);

    await themeProvider.toggleTheme(true);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await db.deleteProfile(profile.id);
  });

  testWidgets('WorkoutDetailScreen renders minimal card and launches 3-2-1 countdown overlay', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final db = TempoRustDb.instance;
    await db.init();
    final profile = await db.createProfile(
      displayName: 'Kenji',
      pin: '1234',
      heightCm: 173,
      weightKg: 61,
    );

    final activeProfileProvider = ActiveProfileProvider();
    await activeProfileProvider.initialize();
    await activeProfileProvider.switchProfileWithPin(profile.id, '1234');
    final themeProvider = ThemeProvider();
    final workout = getJourneyWorkouts(weightLossJourneyId).first;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: themeProvider),
          ChangeNotifierProvider.value(value: activeProfileProvider),
        ],
        child: MaterialApp(
          home: WorkoutDetailScreen(workout: workout),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsNothing);
    expect(find.text('Session timer'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);

    // Tap Start -> 3-2-1 countdown overlay appears
    await tester.tap(find.text('Start'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Get ready'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);

    // Skip countdown -> live timer starts running
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(find.text('In progress'), findsOneWidget);
    expect(find.text('Pause'), findsOneWidget);

    // Pause before teardown so no pending timers remain
    await tester.tap(find.text('Pause'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await db.deleteProfile(profile.id);
  });

  testWidgets('IntroWalkthroughScreen supports animated Next/Back navigation and completes cleanly', (tester) async {
    SharedPreferences.setMockInitialValues({});
    bool completed = false;
    final themeProvider = ThemeProvider();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: themeProvider,
        child: MaterialApp(
          home: IntroWalkthroughScreen(
            onComplete: () => completed = true,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Your daily rhythm'), findsOneWidget);
    expect(find.text('Back'), findsNothing);
    expect(find.text('Next'), findsOneWidget);

    // Go to Slide 2
    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Train with focus'), findsOneWidget);
    expect(find.text('Back'), findsOneWidget);

    // Go Back to Slide 1
    await tester.tap(find.text('Back'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Your daily rhythm'), findsOneWidget);

    // Advance all the way to Slide 4
    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('See your momentum'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Built for privacy'), findsOneWidget);
    expect(find.text('Get Started'), findsOneWidget);

    await tester.tap(find.text('Get Started'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 520));
    expect(find.text('Welcome to Tempo'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 900));
    expect(completed, true);
    expect(tester.takeException(), isNull);
  });
}
