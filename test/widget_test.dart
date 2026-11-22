import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tempo_fitness/config/app_version.dart';
import 'package:tempo_fitness/data/fitness_journey_workouts.dart';
import 'package:tempo_fitness/screens/about_app_screen.dart';
import 'package:tempo_fitness/screens/add_data_screen.dart';
import 'package:tempo_fitness/screens/avatar_crop_screen.dart';
import 'package:tempo_fitness/screens/custom_workout_builder_screen.dart';
import 'package:tempo_fitness/screens/fitness_journey_detail_screen.dart';
import 'package:tempo_fitness/screens/health_dashboard.dart';
import 'package:tempo_fitness/screens/intro_walkthrough_screen.dart';
import 'package:tempo_fitness/screens/manage_summary_features_screen.dart';
import 'package:tempo_fitness/screens/metric_detail_screen.dart';
import 'package:tempo_fitness/screens/my_profile.dart';
import 'package:tempo_fitness/screens/photo_compare_screen.dart';
import 'package:tempo_fitness/screens/photo_editing_screen.dart';
import 'package:tempo_fitness/screens/profile_switcher_screen.dart';
import 'package:tempo_fitness/screens/progress_album_screen.dart';
import 'package:tempo_fitness/screens/progress_tracking_screen.dart';
import 'package:tempo_fitness/screens/sleep_detail_screen.dart';
import 'package:tempo_fitness/screens/tempo_shell_screen.dart';
import 'package:tempo_fitness/screens/terms_and_conditions_screen.dart';
import 'package:tempo_fitness/screens/water_detail_screen.dart';
import 'package:tempo_fitness/screens/weight_detail_screen.dart';
import 'package:tempo_fitness/screens/workout_detail_screen.dart';
import 'package:tempo_fitness/screens/workout_screen.dart';
import 'package:tempo_fitness/models/local_profile.dart';
import 'package:tempo_fitness/services/active_profile_provider.dart';
import 'package:tempo_fitness/services/step_counter_sync.dart';
import 'package:tempo_fitness/services/tempo_rust_db.dart';
import 'package:tempo_fitness/theme/theme_provider.dart';
import 'package:tempo_fitness/widgets/ios_stretch_sheet.dart';
import 'package:tempo_fitness/widgets/liquid_glass_nav_bar.dart';
import 'package:tempo_fitness/widgets/oval_activity_rings.dart';
import 'package:tempo_fitness/widgets/reorderable_summary_grid.dart';
import 'package:tempo_fitness/widgets/streak_heatmap_card.dart';
import 'package:tempo_fitness/widgets/tempo_sliver_header.dart';
import 'package:tempo_fitness/widgets/tempo_spotlight_tour.dart';

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

    // Minimized scroll mode collapses labels smoothly into icons-only capsule
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ThemeProvider(),
        child: MaterialApp(
          home: Scaffold(
            bottomNavigationBar: LiquidGlassNavBar(
              currentIndex: 0,
              minimized: true,
              onTap: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Summary'), findsNothing);
    expect(find.text('Workout'), findsNothing);
    expect(tester.takeException(), isNull);
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

    // Scroll down to reveal heatmap, bento cards, segment switcher & PR list
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -520));
    await tester.pumpAndSettle();
    expect(find.text('Activity heatmap'), findsOneWidget);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -320));
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
    expect(find.text('Live step counter'), findsOneWidget);
    expect(find.text('Switch profile'), findsNothing);
    expect(find.text('Add profile'), findsNothing);
    expect(find.text('Competition'), findsNothing);
    expect(find.byIcon(CupertinoIcons.add), findsNothing);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -440));
    await tester.pumpAndSettle();
    expect(find.text(kTempoDisplayVersion), findsOneWidget);
    expect(kTempoDisplayVersion.endsWith(' - R'), isTrue);

    // App version row is non-clickable (does not navigate to About Tempo)
    await tester.tap(find.text('App version'));
    await tester.pumpAndSettle();
    expect(find.byType(AboutAppScreen), findsNothing);

    // Privacy & Terms has no bullet points or 100% text
    await tester.tap(find.text('Privacy & terms'));
    await tester.pumpAndSettle();
    expect(find.byType(TermsAndConditionsScreen), findsOneWidget);
    expect(find.text('On-Device Privacy'), findsOneWidget);
    expect(find.textContaining('100%'), findsNothing);
    expect(find.textContaining('•'), findsNothing);
    await tester.tap(find.byType(TempoBackChevron));
    await tester.pumpAndSettle();

    // About Tempo has no Rust Native text
    await tester.tap(find.text('About Tempo'));
    await tester.pumpAndSettle();
    expect(find.byType(AboutAppScreen), findsOneWidget);
    expect(find.textContaining('Rust Native'), findsNothing);
    expect(find.textContaining(kTempoDisplayVersion), findsOneWidget);
    await tester.tap(find.byType(TempoBackChevron));
    await tester.pumpAndSettle();

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

  testWidgets('WeightDetailScreen renders cards, tabs, body composition, and add weight sheet', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final db = TempoRustDb.instance;
    await db.init();
    final profile = await db.createProfile(
      displayName: 'Kenji',
      pin: '1234',
      heightCm: 173,
      weightKg: 61.75,
    );
    await db.logBodyMetric(
      profileId: profile.id,
      metricType: 'weight',
      value: 61.55,
      recordedAt: DateTime.now().subtract(const Duration(days: 28)),
    );
    await db.logBodyMetric(
      profileId: profile.id,
      metricType: 'weight',
      value: 61.75,
      recordedAt: DateTime.now(),
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
          home: WeightDetailScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Weight'), findsOneWidget);
    expect(find.text('Latest'), findsOneWidget);
    expect(find.text('Week'), findsOneWidget);
    expect(find.text('Weight management'), findsOneWidget);
    expect(find.text('61.75'), findsOneWidget);
    expect(find.text('+0.20 kg'), findsOneWidget);
    expect(find.text('Body composition'), findsOneWidget);
    expect(find.text('Data source'), findsOneWidget);
    expect(find.text('Add data'), findsOneWidget);

    // Switch to M tab -> shows trend chart cleanly
    await tester.tap(find.text('M'));
    await tester.pumpAndSettle();

    // Scroll down to reveal Add data card below expanded chart
    await tester.drag(find.byType(ListView), const Offset(0, -260));
    await tester.pumpAndSettle();

    // Open Add data sheet -> save a new weight entry
    await tester.tap(find.text('Add data'));
    await tester.pumpAndSettle();
    expect(find.text('Add weight'), findsOneWidget);
    await tester.tap(find.text('Save weight'));
    await tester.pumpAndSettle();

    // Tap the top date to open the History Calendar screen
    await tester.tap(find.byIcon(Icons.arrow_drop_down_rounded));
    await tester.pumpAndSettle();
    expect(find.text('History'), findsOneWidget);
    expect(find.text('Day'), findsOneWidget);
    expect(find.text('Week'), findsOneWidget);
    expect(find.text('Month'), findsOneWidget);
    expect(find.text('Year'), findsOneWidget);

    // Switch to Month view & pick current month to return
    await tester.tap(find.text('Month'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Year'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('${DateTime.now().year}').last);
    await tester.pumpAndSettle();
    expect(find.text('Weight'), findsOneWidget);

    // Tap three-dots button -> iOS popover shows All data, Add data, Unit
    await tester.tap(find.byIcon(CupertinoIcons.ellipsis_vertical));
    await tester.pumpAndSettle();
    expect(find.text('All data'), findsOneWidget);
    expect(find.text('Add data'), findsWidgets);
    expect(find.text('Unit'), findsOneWidget);

    // Open Unit page -> switch from kg to lb
    await tester.tap(find.text('Unit'));
    await tester.pumpAndSettle();
    expect(find.text('Unit'), findsOneWidget);
    expect(find.text('kg'), findsOneWidget);
    expect(find.text('lb'), findsOneWidget);
    expect(
      find.text(
        'After switching units, slight discrepancies may result from the rounding of decimal places.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('lb'));
    await tester.pumpAndSettle();

    // Back on Weight screen with lb displayed
    expect(find.text('Weight'), findsOneWidget);
    expect(find.text('lb'), findsWidgets);
    expect(find.text('136.14'), findsOneWidget);

    // Tap Body composition card -> opens clean BMI popup with spectrum bar (no BMI trend graph)
    await tester.tap(find.text('Body composition'));
    await tester.pumpAndSettle();
    expect(find.text('Level'), findsOneWidget);
    expect(find.text('Normal'), findsWidgets);
    expect(find.text('18.5'), findsOneWidget);
    expect(find.text('24'), findsOneWidget);
    expect(find.text('28'), findsOneWidget);
    expect(find.text('BMI trend'), findsNothing);
    expect(find.text('Collapse'), findsOneWidget);

    // Dismiss via Collapse button
    await tester.tap(find.text('Collapse'));
    await tester.pumpAndSettle();
    expect(find.text('Collapse'), findsNothing);

    await themeProvider.toggleTheme(true);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await db.deleteProfile(profile.id);
  });

  testWidgets('ManageSummaryFeaturesScreen toggles cards and saves selection', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final themeProvider = ThemeProvider();
    List<String>? savedResult;

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: themeProvider,
        child: MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    savedResult = await Navigator.push<List<String>>(
                      ctx,
                      MaterialPageRoute(
                        builder: (_) => ManageSummaryFeaturesScreen(
                          initialSelectedIds: kDefaultSummaryFeatureIds,
                        ),
                      ),
                    );
                  },
                  child: const Text('Open Manage'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Manage'));
    await tester.pumpAndSettle();

    expect(find.text('Manage health features'), findsOneWidget);
    expect(find.text('Frequently used'), findsOneWidget);
    expect(find.text('More features'), findsOneWidget);
    expect(find.text('Sleep'), findsOneWidget);
    expect(find.text('Weight'), findsOneWidget);

    // Toggle Sleep off -> moves from Frequently used to More features
    await tester.tap(find.text('Sleep'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('off_sleep')), findsOneWidget);

    // Toggle Dark Mode cleanly
    await themeProvider.toggleTheme(true);
    await tester.pumpAndSettle();

    // Tap checkmark to save
    await tester.tap(find.byIcon(CupertinoIcons.checkmark_alt));
    await tester.pumpAndSettle();

    expect(savedResult, isNotNull);
    expect(savedResult!.contains('sleep'), isFalse);
    expect(savedResult!.contains('weight'), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('SleepDetailScreen mirrors Weight layout with calendar and popover', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final db = TempoRustDb.instance;
    await db.init();
    final profile = await db.createProfile(
      displayName: 'Kenji',
      pin: '1234',
      heightCm: 173,
      weightKg: 61.75,
    );
    await db.logBodyMetric(
      profileId: profile.id,
      metricType: 'sleep',
      value: 7.0,
      recordedAt: DateTime.now().subtract(const Duration(days: 2)),
    );
    await db.logBodyMetric(
      profileId: profile.id,
      metricType: 'sleep',
      value: 7.5,
      recordedAt: DateTime.now(),
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
          home: SleepDetailScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sleep'), findsOneWidget);
    expect(find.text('Sleep duration'), findsOneWidget);
    expect(find.text('7.5'), findsOneWidget);
    expect(find.text('Sleep quality'), findsOneWidget);
    expect(find.text('Optimal'), findsOneWidget);
    expect(find.text('Data source'), findsOneWidget);
    expect(find.text('Add data'), findsOneWidget);

    // Open History Calendar via top date tap
    await tester.tap(find.byIcon(Icons.arrow_drop_down_rounded));
    await tester.pumpAndSettle();
    expect(find.text('History'), findsOneWidget);
    await tester.tap(find.byType(TempoBackChevron));
    await tester.pumpAndSettle();

    // Open iOS popover menu on three dots
    await tester.tap(find.byIcon(CupertinoIcons.ellipsis_vertical));
    await tester.pumpAndSettle();
    expect(find.text('All data'), findsOneWidget);
    expect(find.text('Sleep goal'), findsOneWidget);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    await themeProvider.toggleTheme(true);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await db.deleteProfile(profile.id);
  });

  testWidgets('AddDataScreen renders redesigned metric picker, steppers, and presets', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final db = TempoRustDb.instance;
    await db.init();
    final profile = await db.createProfile(
      displayName: 'Kenji',
      pin: '1234',
      heightCm: 173,
      weightKg: 61.75,
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
          home: AddDataScreen(initialMetric: 'sleep'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Log Health Data'), findsOneWidget);
    expect(find.text('Save sleep'), findsOneWidget);
    expect(find.text('Date'), findsOneWidget);
    // Sleep uses HyperOS-style drum wheels for hrs : min
    expect(find.text('hrs'), findsOneWidget);
    expect(find.text('min'), findsOneWidget);

    // Switch metric to Steps -> hides Date, shows always-visible 'steps' wheel unit
    await tester.tap(find.text('Steps'));
    await tester.pumpAndSettle();
    expect(find.text('Save steps'), findsOneWidget);
    expect(find.text('steps'), findsOneWidget);
    expect(find.text('Date'), findsNothing);

    // Switch metric to Activity -> shows hrs : min drum wheels
    await tester.tap(find.text('Activity'));
    await tester.pumpAndSettle();
    expect(find.text('Save activity'), findsOneWidget);
    expect(find.text('hrs'), findsOneWidget);
    expect(find.text('min'), findsOneWidget);

    await themeProvider.toggleTheme(true);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await db.deleteProfile(profile.id);
  });

  testWidgets('ProgressAlbumScreen uses Android bottom sheet, full-screen viewer, and upgraded Save Photo UI', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final db = TempoRustDb.instance;
    await db.init();
    final profile = await db.createProfile(
      displayName: 'Kenji',
      pin: '1234',
      heightCm: 173,
      weightKg: 61.75,
    );

    final activeProfileProvider = ActiveProfileProvider();
    await activeProfileProvider.initialize();
    await activeProfileProvider.switchProfileWithPin(profile.id, '1234');
    final themeProvider = ThemeProvider();

    // 1. Empty state + Android bottom sheet on Add First Photo and + button
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: themeProvider),
          ChangeNotifierProvider.value(value: activeProfileProvider),
        ],
        child: const MaterialApp(
          home: ProgressAlbumScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Progress Album'), findsOneWidget);
    expect(find.text('Add First Photo'), findsOneWidget);

    await tester.tap(find.text('Add First Photo'));
    await tester.pumpAndSettle();
    expect(find.text('Add progress photo'), findsOneWidget);
    expect(find.text('Take photo'), findsOneWidget);
    expect(find.text('Choose from gallery'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // Top-right + button opens the same Android bottom sheet
    await tester.tap(find.byIcon(CupertinoIcons.add));
    await tester.pumpAndSettle();
    expect(find.text('Add progress photo'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // 2. PhotoEditingScreen (Save Photo) redesigned preview & buttons
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: themeProvider),
          ChangeNotifierProvider.value(value: activeProfileProvider),
        ],
        child: const MaterialApp(
          home: PhotoEditingScreen(sourceImagePath: ''),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Save Photo'), findsOneWidget);
    expect(find.text('Fit'), findsOneWidget);
    expect(find.text('Front'), findsWidgets);
    expect(find.text('Side'), findsOneWidget);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -350));
    await tester.pumpAndSettle();
    expect(find.text('Discard'), findsOneWidget);
    expect(find.text('Save photo'), findsOneWidget);

    // 3. With a saved photo, tapping opens the full-screen viewer
    await db.addProgressPhoto(
      profileId: profile.id,
      filePath: '',
      caption: 'Week 4 check-in',
      category: 'Front',
      weightKg: 61.75,
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: themeProvider),
          ChangeNotifierProvider.value(value: activeProfileProvider),
        ],
        child: const MaterialApp(
          home: ProgressAlbumScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Week 4 check-in'));
    await tester.pumpAndSettle();
    expect(find.text('61.8 kg'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.trash), findsOneWidget);

    await themeProvider.toggleTheme(true);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await db.deleteProfile(profile.id);
  });

  testWidgets('MetricDetailScreen renders unified Weight-style layout for Steps', (tester) async {
    SharedPreferences.setMockInitialValues({});
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
        child: const MaterialApp(
          home: MetricDetailScreen(kind: TempoMetricKind.steps),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Steps'), findsWidgets);
    expect(find.text('Latest'), findsOneWidget);
    expect(find.text('Week'), findsOneWidget);
    expect(find.text('Live step counter'), findsOneWidget);
    expect(find.text('Add data'), findsOneWidget);

    await tester.tap(find.byIcon(CupertinoIcons.ellipsis_vertical));
    await tester.pumpAndSettle();
    expect(find.text('Daily goal'), findsOneWidget);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    await themeProvider.toggleTheme(true);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await db.deleteProfile(profile.id);
  });

  testWidgets('WaterDetailScreen logs quick hydration and supports Dark Mode', (tester) async {
    SharedPreferences.setMockInitialValues({});
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
        child: const MaterialApp(
          home: WaterDetailScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Water'), findsOneWidget);
    expect(find.text('+250 ml'), findsOneWidget);
    await tester.tap(find.text('+250 ml'));
    await tester.pumpAndSettle();
    expect(find.text('250'), findsOneWidget);

    await themeProvider.toggleTheme(true);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await db.deleteProfile(profile.id);
  });

  testWidgets('PhotoCompareScreen, StreakHeatmapCard, and CustomWorkoutBuilderScreen render cleanly', (tester) async {
    SharedPreferences.setMockInitialValues({});
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

    final pBefore = LocalProgressPhoto(
      id: 'b1',
      profileId: profile.id,
      filePath: '',
      caption: 'Day 1',
      category: 'Front',
      weightKg: 65,
      takenAt: DateTime.now().subtract(const Duration(days: 30)),
    );
    final pAfter = LocalProgressPhoto(
      id: 'a1',
      profileId: profile.id,
      filePath: '',
      caption: 'Day 30',
      category: 'Front',
      weightKg: 62,
      takenAt: DateTime.now(),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: themeProvider,
        child: MaterialApp(
          home: PhotoCompareScreen(
            photos: [pAfter, pBefore],
            weightUnit: 'kg',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Compare'), findsOneWidget);
    expect(find.text('Split'), findsOneWidget);
    await tester.tap(find.text('Split'));
    await tester.pumpAndSettle();
    expect(find.text('Slider'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // StreakHeatmapCard
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: themeProvider,
        child: const MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: EdgeInsets.all(16),
              child: StreakHeatmapCard(
                dailyHistory: [],
                workoutDayKeys: {},
                currentStreak: 3,
                longestStreak: 7,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Activity heatmap'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // CustomWorkoutBuilderScreen
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: themeProvider),
          ChangeNotifierProvider.value(value: activeProfileProvider),
        ],
        child: const MaterialApp(
          home: CustomWorkoutBuilderScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Custom Workout'), findsWidgets);
    expect(find.text('Routine name'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.checkmark_alt), findsOneWidget);
    expect(tester.takeException(), isNull);

    await db.deleteProfile(profile.id);
  });

  testWidgets('TempoShellScreen switches away from Profile back to Summary and Workout without freezing', (tester) async {
    SharedPreferences.setMockInitialValues({});
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
        child: const MaterialApp(
          home: TempoShellScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Navigate to Profile (last child in Stack)
    await tester.tap(find.text('Profile').last);
    await tester.pumpAndSettle();
    expect(find.text('Dark mode'), findsOneWidget);

    // Navigate back to Summary -> Profile AnimatedOpacity AND its FadeTransition must reach 0.0
    await tester.tap(find.text('Summary').last);
    await tester.pumpAndSettle();

    final summaryPane = find.ancestor(
      of: find.byType(HealthDashboard),
      matching: find.byType(AnimatedOpacity),
    );
    final profilePane = find.ancestor(
      of: find.byType(MyProfile),
      matching: find.byType(AnimatedOpacity),
    );
    final summaryFade = tester.widget<FadeTransition>(
      find.descendant(of: summaryPane, matching: find.byType(FadeTransition)).first,
    );
    final profileFade = tester.widget<FadeTransition>(
      find.descendant(of: profilePane, matching: find.byType(FadeTransition)).first,
    );
    expect(summaryFade.opacity.value, 1.0);
    expect(profileFade.opacity.value, 0.0);

    // Navigate to Workout -> Workout active (1.0), Summary & Profile faded to 0.0
    await tester.tap(find.text('Workout').last);
    await tester.pumpAndSettle();
    final workoutPane = find.ancestor(
      of: find.byType(WorkoutScreen),
      matching: find.byType(AnimatedOpacity),
    );
    final workoutFade = tester.widget<FadeTransition>(
      find.descendant(of: workoutPane, matching: find.byType(FadeTransition)).first,
    );
    expect(summaryFade.opacity.value, 0.0);
    expect(workoutFade.opacity.value, 1.0);
    expect(profileFade.opacity.value, 0.0);
    expect(tester.takeException(), isNull);

    await db.deleteProfile(profile.id);
  });

  testWidgets('AvatarCropScreen renders circular crop controls and ReorderableSummaryGrid reorders on long-press drag', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final themeProvider = ThemeProvider();

    // 1. AvatarCropScreen
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: themeProvider,
        child: const MaterialApp(
          home: AvatarCropScreen(imagePath: ''),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Move and Scale'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Choose'), findsOneWidget);
    await tester.tap(find.byIcon(CupertinoIcons.rotate_right));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // 2. ReorderableSummaryGrid hold-and-drag reorder
    List<String> order = ['sleep', 'weight', 'waist', 'water'];
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: themeProvider,
        child: MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: StatefulBuilder(
                builder: (ctx, setState) => ReorderableSummaryGrid(
                  itemIds: order,
                  itemBuilder: (_, id, __) => Container(
                    alignment: Alignment.center,
                    color: Colors.grey.shade200,
                    child: Text(id),
                  ),
                  onReorder: (next) => setState(() => order = next),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final sleepCenter = tester.getCenter(find.text('sleep'));
    final weightCenter = tester.getCenter(find.text('weight'));
    final gesture = await tester.startGesture(sleepCenter);
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveTo(weightCenter);
    await tester.pump(const Duration(milliseconds: 260));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(order[0], 'weight');
    expect(order[1], 'sleep');
    expect(tester.takeException(), isNull);
  });

  testWidgets('TempoSpotlightTour highlights targets step-by-step and remembers seen state', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final db = TempoRustDb.instance;
    await db.init();
    final profile = await db.createProfile(
      displayName: 'Kenji',
      pin: '1234',
      heightCm: 173,
      weightKg: 62,
    );
    final themeProvider = ThemeProvider();
    final k1 = GlobalKey();
    final k2 = GlobalKey();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: themeProvider,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(key: k1, width: 120, height: 48, color: Colors.orange),
                  const SizedBox(height: 24),
                  Container(key: k2, width: 140, height: 48, color: Colors.blue),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () {
                      TempoSpotlightTour.showIfNeeded(
                        context: ctx,
                        profileId: profile.id,
                        screenId: 'test_screen',
                        delay: Duration.zero,
                        ignoreTestGuard: true,
                        steps: [
                          TempoSpotlightStep(
                            targetKey: k1,
                            title: 'First Feature',
                            description: 'Tap here to try the first feature.',
                          ),
                          TempoSpotlightStep(
                            targetKey: k2,
                            title: 'Second Feature',
                            description: 'Hold here to customize layout.',
                          ),
                        ],
                      );
                    },
                    child: const Text('Start Tour'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Start Tour'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('Tip 1 of 2'), findsOneWidget);
    expect(find.text('First Feature'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('Tip 2 of 2'), findsOneWidget);
    expect(find.text('Second Feature'), findsOneWidget);
    expect(find.text('Got it'), findsOneWidget);

    await tester.tap(find.text('Got it'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Second Feature'), findsNothing);

    // Second trigger is a no-op because screenId was persisted as seen
    await tester.tap(find.text('Start Tour'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('First Feature'), findsNothing);
    expect(tester.takeException(), isNull);

    await db.deleteProfile(profile.id);
  });

  test('StepCounterSync counts 1:1 live, catches up after close, and survives reboots', () async {
    SharedPreferences.setMockInitialValues({});
    final db = TempoRustDb.instance;
    await db.init();
    final profile = await db.createProfile(
      displayName: 'Walker',
      pin: '1234',
      heightCm: 173,
      weightKg: 62,
    );
    final today = TempoRustDb.todayKey();
    final t0 = DateTime(2026, 11, 22, 10, 0, 0).millisecondsSinceEpoch;

    // 0. Live toggle defaults false and persists ON/OFF cleanly
    expect(await StepCounterSync.isLiveEnabled(profile.id), false);
    await StepCounterSync.setLiveEnabled(profile.id, true);
    expect(await StepCounterSync.isLiveEnabled(profile.id), true);

    // 1. First reading sets today's baseline (delta 0, does not add boot lifetime steps)
    final r1 = await StepCounterSync.ingestHardwareSteps(
      db: db,
      profileId: profile.id,
      sensorSteps: 10000,
      todayKeyOverride: today,
      nowMsOverride: t0,
    );
    expect(r1, isNull);

    // 2. Live 1:1 steps (zero double-counting!)
    expect(
      await StepCounterSync.ingestHardwareSteps(
        db: db,
        profileId: profile.id,
        sensorSteps: 10001,
        todayKeyOverride: today,
        nowMsOverride: t0 + 1000,
      ),
      1,
    );
    expect(
      await StepCounterSync.ingestHardwareSteps(
        db: db,
        profileId: profile.id,
        sensorSteps: 10002,
        todayKeyOverride: today,
        nowMsOverride: t0 + 2000,
      ),
      2,
    );

    // 2B. Stationary desk-pickup jitter (+1 step within 500ms while stopped) is ignored
    expect(
      await StepCounterSync.ingestHardwareSteps(
        db: db,
        profileId: profile.id,
        sensorSteps: 10003,
        todayKeyOverride: today,
        nowMsOverride: t0 + 2500,
        isStationary: true,
      ),
      isNull,
    );

    // 2C. Impossible glitch spike (+5000 steps in 1 second) is safely rejected
    expect(
      await StepCounterSync.ingestHardwareSteps(
        db: db,
        profileId: profile.id,
        sensorSteps: 15003,
        todayKeyOverride: today,
        nowMsOverride: t0 + 3500,
      ),
      isNull,
    );

    // 3. App closed in pocket for 15 mins, user walks +1500 steps -> catches up cleanly
    expect(
      await StepCounterSync.ingestHardwareSteps(
        db: db,
        profileId: profile.id,
        sensorSteps: 16503,
        todayKeyOverride: today,
        nowMsOverride: t0 + 15 * 60 * 1000,
      ),
      1502,
    );

    // 4. Phone reboots mid-day 5 mins later (sensor resets to 0, walks 250 steps) -> preserves 1502 + adds 250
    expect(
      await StepCounterSync.ingestHardwareSteps(
        db: db,
        profileId: profile.id,
        sensorSteps: 250,
        todayKeyOverride: today,
        nowMsOverride: t0 + 20 * 60 * 1000,
      ),
      1752,
    );

    await db.deleteProfile(profile.id);
  });
}
