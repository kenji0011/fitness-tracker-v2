import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiggicons/jiggicons.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tempo_fitness/config/app_version.dart';
import 'package:tempo_fitness/data/fitness_journey_workouts.dart';
import 'package:tempo_fitness/screens/about_app_screen.dart';
import 'package:tempo_fitness/screens/activity_stats_screen.dart';
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
import 'package:tempo_fitness/screens/progress_share_screen.dart';
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
import 'package:tempo_fitness/services/animation_speed_service.dart';
import 'package:tempo_fitness/services/app_update_service.dart';
import 'package:tempo_fitness/services/share_template_service.dart';
import 'package:tempo_fitness/services/step_counter_sync.dart';
import 'package:tempo_fitness/services/tempo_rust_db.dart';
import 'package:tempo_fitness/theme/theme_provider.dart';
import 'package:tempo_fitness/widgets/ios_popover_menu.dart';
import 'package:tempo_fitness/widgets/ios_stretch_sheet.dart';
import 'package:tempo_fitness/widgets/liquid_glass_nav_bar.dart';
import 'package:tempo_fitness/widgets/liquid_glass_surface.dart';
import 'package:tempo_fitness/widgets/oval_activity_rings.dart';
import 'package:tempo_fitness/widgets/reorderable_summary_grid.dart';
import 'package:tempo_fitness/widgets/step_accuracy_warning_sheet.dart';
import 'package:tempo_fitness/widgets/streak_heatmap_card.dart';
import 'package:tempo_fitness/widgets/tempo_jigg_icon.dart';
import 'package:tempo_fitness/widgets/tempo_sliver_header.dart';
import 'package:tempo_fitness/widgets/tempo_morph_route.dart';
import 'package:tempo_fitness/widgets/tempo_spotlight_tour.dart';
import 'package:tempo_fitness/widgets/tempo_startup_splash.dart';
import 'package:tempo_fitness/widgets/tempo_update_sheet.dart';

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

  testWidgets('MyProfile renders clean identity row and organized grouped settings sections', (tester) async {
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
    expect(find.text('PREFERENCES'), findsOneWidget);
    expect(find.text('DATA & MEDIA'), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Dark mode'), findsNothing);
    expect(find.text('Live step counter'), findsOneWidget);
    expect(find.text('Clean light appearance active'), findsNothing);
    expect(find.text('Private on-device album & comparison'), findsNothing);
    expect(find.text('Export or import local JSON snapshots'), findsNothing);
    expect(find.text('Switch profile'), findsNothing);
    expect(find.text('Add profile'), findsNothing);
    expect(find.text('Competition'), findsNothing);
    expect(find.byIcon(CupertinoIcons.add), findsNothing);

    await tester.scrollUntilVisible(
      find.text('SECURITY & PRIVACY'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('SECURITY & PRIVACY'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Privacy & terms'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    // Privacy & Terms has no bullet points or 100% text
    await tester.tap(find.text('Privacy & terms'));
    await tester.pumpAndSettle();
    expect(find.byType(TermsAndConditionsScreen), findsOneWidget);
    expect(find.text('On-Device Privacy'), findsOneWidget);
    expect(find.text('Permissions & Network Access'), findsOneWidget);
    expect(find.textContaining('100%'), findsNothing);
    expect(find.textContaining('•'), findsNothing);
    await tester.tap(find.byType(TempoBackChevron));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('UPDATES & SUPPORT'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('UPDATES & SUPPORT'), findsOneWidget);
    expect(find.text('Auto-updates'), findsOneWidget);
    expect(find.text('Checks GitHub releases on launch'), findsNothing);
    expect(find.text('Permanently erase data for this profile'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('About Tempo'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text(kTempoDisplayVersion), findsOneWidget);
    expect(kTempoDisplayVersion.endsWith(' - R'), isTrue);

    // About Tempo has no Rust Native text
    await tester.tap(find.text('About Tempo'));
    await tester.pumpAndSettle();
    expect(find.byType(AboutAppScreen), findsOneWidget);
    expect(find.text('Tempo'), findsNothing); // no redundant Tempo heading below About Tempo
    expect(find.text('Your personal offline fitness companion'), findsOneWidget);
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

    // Tap Start -> 3-2-1 countdown overlay appears and plays countdown beats cleanly
    await tester.tap(find.text('Start'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Get ready'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);

    // Advance one beat to verify 2 appears cleanly with sound trigger
    await tester.pump(const Duration(milliseconds: 950));
    expect(find.text('2'), findsOneWidget);

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
    expect(find.text('Add data'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('About'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('About'), findsOneWidget);

    // Data source sheet should not show "Local on-device"
    await tester.tap(find.text('Data source'));
    await tester.pumpAndSettle();
    expect(find.text('Local on-device'), findsNothing);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    // Switch to M tab -> shows trend chart cleanly
    await tester.tap(find.text('M'));
    await tester.pumpAndSettle();

    // Open + popover -> shows Add data and Unit (no All data)
    await tester.tap(find.byIcon(CupertinoIcons.add));
    await tester.pumpAndSettle();
    expect(find.text('All data'), findsNothing);
    expect(find.text('Add data'), findsOneWidget);
    expect(find.text('Unit'), findsOneWidget);

    // Open Add data sheet from + popover -> save a new weight entry
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

    // Tap + button -> open Unit page -> switch from kg to lb
    await tester.tap(find.byIcon(CupertinoIcons.add));
    await tester.pumpAndSettle();
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
    expect(find.text('Add data'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('About'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('About'), findsOneWidget);

    // Open History Calendar via top date tap
    await tester.tap(find.byIcon(Icons.arrow_drop_down_rounded));
    await tester.pumpAndSettle();
    expect(find.text('History'), findsOneWidget);
    await tester.tap(find.byType(TempoBackChevron));
    await tester.pumpAndSettle();

    // Open iOS popover menu on + button (no All data)
    await tester.tap(find.byIcon(CupertinoIcons.add));
    await tester.pumpAndSettle();
    expect(find.text('All data'), findsNothing);
    expect(find.text('Add data'), findsOneWidget);
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
    // Sleep uses 3D cylindrical drum wheels for HRS : MIN
    expect(find.text('HRS'), findsOneWidget);
    expect(find.text('MIN'), findsOneWidget);

    // Switch metric to Steps -> keeps unified morphing Date pill & shows 'steps' unit
    await tester.tap(find.text('Steps'));
    await tester.pumpAndSettle();
    expect(find.text('Save steps'), findsOneWidget);
    expect(find.text('steps'), findsAtLeastNWidgets(1));
    expect(find.text('Date'), findsOneWidget);

    // Switch metric to Activity -> shows HRS : MIN 3D drum wheels
    await tester.tap(find.text('Activity'));
    await tester.pumpAndSettle();
    expect(find.text('Save activity'), findsOneWidget);
    expect(find.text('HRS'), findsOneWidget);
    expect(find.text('MIN'), findsOneWidget);

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
    // Sample mid-flight open morph frames
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 160));
    await tester.pumpAndSettle();
    expect(find.text('61.8 kg'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.trash), findsOneWidget);

    // Close viewer and sample mid-flight closing morph frames back to the tile
    await tester.tap(find.byType(TempoBackChevron).last);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 140));
    await tester.pumpAndSettle();
    expect(find.text('Week 4 check-in'), findsOneWidget);
    // Ensure grid tile is fully visible (never stuck at Opacity 0.0 after dismiss!)
    final tileOpacity = tester.widget<Opacity>(
      find.ancestor(
        of: find.text('Week 4 check-in'),
        matching: find.byType(Opacity),
      ).first,
    );
    expect(tileOpacity.opacity, 1.0);

    await themeProvider.toggleTheme(true);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await db.deleteProfile(profile.id);
  });

  testWidgets('MetricDetailScreen renders unified layout and bottom About row for Steps, Calories, and Activity', (tester) async {
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
    expect(find.text('Data source'), findsOneWidget);
    expect(find.text('Local on-device history'), findsNothing);
    expect(find.text('Add data'), findsNothing);
    expect(find.text('About Steps'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('About'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('About'), findsOneWidget);

    // Popover menu on + button holds Add data & Daily goal (no All data or About).
    await tester.tap(find.byIcon(CupertinoIcons.add));
    await tester.pumpAndSettle();
    expect(find.text('All data'), findsNothing);
    expect(find.text('Add data'), findsOneWidget);
    expect(find.text('Daily goal'), findsWidgets);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    // Tapping About opens the minimal About sheet explaining what Steps is.
    await tester.tap(find.text('About'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Steps count the total strides'),
      findsOneWidget,
    );
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    // Verify Calories and Activity pages also render separate minimal About cards cleanly.
    for (final entry in const [
      (
        kind: TempoMetricKind.calories,
        snippet: 'Active calories measure the energy',
      ),
      (
        kind: TempoMetricKind.minutes,
        snippet: 'Activity time measures the minutes',
      ),
    ]) {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: themeProvider),
            ChangeNotifierProvider.value(value: activeProfileProvider),
          ],
          child: MaterialApp(
            home: MetricDetailScreen(kind: entry.kind),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Local on-device history'), findsNothing);
      expect(find.text('Add data'), findsNothing);
      expect(find.text('About Calories'), findsNothing);
      expect(find.text('About Activity'), findsNothing);

      await tester.scrollUntilVisible(
        find.text('About'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('About'), findsOneWidget);
      await tester.tap(find.text('About'));
      await tester.pumpAndSettle();
      expect(find.textContaining(entry.snippet), findsOneWidget);
      expect(find.text('Active vs. resting burn'), findsNothing);
      expect(find.text('Flexible daily goal'), findsNothing);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
    }

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

    await tester.tap(find.text('+500 ml'));
    await tester.pumpAndSettle();
    expect(find.text('750'), findsOneWidget);

    // Verify unified Water UI: + popover without All data, separate Data source & About cards
    await tester.tap(find.byIcon(CupertinoIcons.add));
    await tester.pumpAndSettle();
    expect(find.text('All data'), findsNothing);
    expect(find.text('Add data'), findsOneWidget);
    expect(find.text('Daily goal'), findsWidgets);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('About'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('About'), findsOneWidget);
    expect(find.text('Data source'), findsOneWidget);

    // Unsupported metric types stay rejected in parity with Rust SQLite
    await expectLater(
      () => db.logBodyMetric(
        profileId: profile.id,
        metricType: 'unknown_metric',
        value: 10,
      ),
      throwsException,
    );

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
    expect(find.text('Appearance'), findsOneWidget);

    // Navigate back to Summary -> Profile AnimatedOpacity reaches 0.0 AND moves Offstage
    await tester.tap(find.text('Summary').last);
    await tester.pumpAndSettle();

    final summaryPane = find.ancestor(
      of: find.byType(HealthDashboard, skipOffstage: false),
      matching: find.byType(AnimatedOpacity, skipOffstage: false),
    );
    final profilePane = find.ancestor(
      of: find.byType(MyProfile, skipOffstage: false),
      matching: find.byType(AnimatedOpacity, skipOffstage: false),
    );
    final summaryFade = tester.widget<FadeTransition>(
      find.descendant(of: summaryPane, matching: find.byType(FadeTransition, skipOffstage: false), skipOffstage: false).first,
    );
    final profileFade = tester.widget<FadeTransition>(
      find.descendant(of: profilePane, matching: find.byType(FadeTransition, skipOffstage: false), skipOffstage: false).first,
    );
    final summaryOffstage = tester.widget<Offstage>(
      find.ancestor(of: summaryPane, matching: find.byType(Offstage, skipOffstage: false)).first,
    );
    final profileOffstage = tester.widget<Offstage>(
      find.ancestor(of: profilePane, matching: find.byType(Offstage, skipOffstage: false)).first,
    );
    expect(summaryFade.opacity.value, 1.0);
    expect(summaryOffstage.offstage, isFalse);
    expect(profileFade.opacity.value, 0.0);
    expect(profileOffstage.offstage, isTrue);

    // Navigate to Workout -> Workout active (1.0, onstage), Summary & Profile faded to 0.0 & offstage
    await tester.tap(find.text('Workout').last);
    await tester.pumpAndSettle();
    final workoutPane = find.ancestor(
      of: find.byType(WorkoutScreen, skipOffstage: false),
      matching: find.byType(AnimatedOpacity, skipOffstage: false),
    );
    final workoutFade = tester.widget<FadeTransition>(
      find.descendant(of: workoutPane, matching: find.byType(FadeTransition, skipOffstage: false), skipOffstage: false).first,
    );
    final workoutOffstage = tester.widget<Offstage>(
      find.ancestor(of: workoutPane, matching: find.byType(Offstage, skipOffstage: false)).first,
    );
    final summaryOffstageAfter = tester.widget<Offstage>(
      find.ancestor(of: summaryPane, matching: find.byType(Offstage, skipOffstage: false)).first,
    );
    expect(summaryFade.opacity.value, 0.0);
    expect(summaryOffstageAfter.offstage, isTrue);
    expect(workoutFade.opacity.value, 1.0);
    expect(workoutOffstage.offstage, isFalse);
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

  testWidgets(
      'TempoStartupSplash plays X-style anticipation dip, portal zoom-through, preserves child state, and unmounts cleanly',
      (tester) async {
    bool completed = false;
    int taps = 0;
    int childInitCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: TempoStartupSplash(
          onCompleted: () => completed = true,
          child: _InitCountProbe(
            onInit: () => childInitCount++,
            child: Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => taps++,
                  child: const Text('Dashboard Ready'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // Frame 0: Splash overlay is active and underlying content is initialized once
    expect(find.byKey(TempoStartupSplash.overlayKey), findsOneWidget);
    expect(find.text('Dashboard Ready'), findsOneWidget);
    expect(childInitCount, 1);
    expect(completed, false);

    // Gate future stays pending while splash is running
    bool gateResolved = false;
    final gateFuture =
        TempoStartupSplash.waitForCompletion().then((_) => gateResolved = true);

    // Mid-anticipation dip (~180ms)
    await tester.pump(const Duration(milliseconds: 180));
    expect(find.byKey(TempoStartupSplash.overlayKey), findsOneWidget);
    expect(completed, false);
    expect(gateResolved, false);

    // Mid-zoom-through portal expansion (~600ms)
    await tester.pump(const Duration(milliseconds: 420));
    expect(find.byKey(TempoStartupSplash.overlayKey), findsOneWidget);
    expect(completed, false);

    // Complete full 840ms choreography -> overlay unmounts WITHOUT remounting child!
    await tester.pumpAndSettle();
    await gateFuture;
    expect(completed, true);
    expect(gateResolved, true);
    expect(childInitCount, 1);
    expect(find.byKey(TempoStartupSplash.overlayKey), findsNothing);

    // Underlying interactive content is completely unobstructed after unmount
    await tester.tap(find.text('Dashboard Ready'));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('TempoStartupSplash respects reduced motion and enabled flag',
      (tester) async {
    bool reducedCompleted = false;

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          theme: ThemeData.dark(),
          home: TempoStartupSplash(
            onCompleted: () => reducedCompleted = true,
            child: const Scaffold(body: Text('Dark Ready')),
          ),
        ),
      ),
    );

    expect(find.byKey(TempoStartupSplash.overlayKey), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 240));
    await tester.pump();
    expect(reducedCompleted, true);
    expect(find.byKey(TempoStartupSplash.overlayKey), findsNothing);
    expect(find.text('Dark Ready'), findsOneWidget);

    // Disabled splash bypasses overlay immediately
    await tester.pumpWidget(
      const MaterialApp(
        home: TempoStartupSplash(
          enabled: false,
          child: Scaffold(body: Text('Instant Content')),
        ),
      ),
    );
    expect(find.byKey(TempoStartupSplash.overlayKey), findsNothing);
    expect(find.text('Instant Content'), findsOneWidget);
  });

  testWidgets(
      'TempoJiggIcon prewarms and plays spring motion cleanly across navbar and screens',
      (tester) async {
    await tester.runAsync(() => TempoJiggicons.prewarm());
    expect(TempoJiggicons.cached('heart'), isNotNull);
    expect(TempoJiggicons.cached('dumbbell'), isNotNull);
    expect(TempoJiggicons.cached('trophy'), isNotNull);
    expect(TempoJiggicons.cached('drop'), isNotNull);
    expect(TempoJiggicons.cached('weather-moon'), isNotNull);
    expect(TempoJiggicons.cached('confetti'), isNotNull);

    final ctrl = JiggIconController();
    addTearDown(ctrl.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: TempoJiggIcon(
              'dumbbell',
              variant: JiggIconVariant.solid,
              size: 28,
              color: const Color(0xFFFF6A24),
              controller: ctrl,
              trigger: JiggIconTrigger.none,
              fallbackIcon: CupertinoIcons.bolt_fill,
            ),
          ),
        ),
      ),
    );

    expect(find.byType(JiggIconFrame), findsOneWidget);
    ctrl.play();
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pumpAndSettle();
    expect(find.byType(JiggIconFrame), findsOneWidget);
  });

  testWidgets(
      'Optical Liquid Glass navbar pill and TempoGlassCircleButton render cleanly in Light & Dark Mode',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final themeProvider = ThemeProvider();
    int plusTaps = 0;
    int selectedTab = 0;

    Widget buildHarness({required bool minimized}) {
      return ChangeNotifierProvider.value(
        value: themeProvider,
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: TempoGlassCircleButton(
                tooltip: 'Add',
                onPressed: () => plusTaps++,
                icon: const Icon(CupertinoIcons.add, size: 22),
              ),
            ),
            bottomNavigationBar: LiquidGlassNavBar(
              currentIndex: selectedTab,
              minimized: minimized,
              onTap: (i) => selectedTab = i,
            ),
          ),
        ),
      );
    }

    // Light Mode expanded + tap glass button
    await tester.pumpWidget(buildHarness(minimized: false));
    await tester.pumpAndSettle();
    expect(find.byType(TempoGlassCircleButton), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is CustomPaint && w.foregroundPainter is LiquidGlassRimPainter,
      ),
      findsAtLeastNWidgets(2), // frosted outer dock + circle button
    );
    expect(find.byType(BackdropFilter), findsAtLeastNWidgets(2));
    await tester.tap(find.byType(TempoGlassCircleButton));
    await tester.pumpAndSettle();
    expect(plusTaps, 1);

    // Dark Mode + minimized navbar glass capsule
    await themeProvider.toggleTheme(true);
    await tester.pumpWidget(buildHarness(minimized: true));
    await tester.pumpAndSettle();
    expect(find.byType(LiquidGlassNavBar), findsOneWidget);
    expect(find.byType(TempoGlassCircleButton), findsOneWidget);
  });

  test('AppUpdateService parses GitHub releases, compares semver, and defaults Auto-updates ON',
      () async {
    SharedPreferences.setMockInitialValues({});
    AppUpdateService.availableRelease.value = null;

    // Auto-updates defaults to ON and persists toggle cleanly
    expect(await AppUpdateService.isAutoUpdateEnabled(), true);
    await AppUpdateService.setAutoUpdateEnabled(false);
    expect(await AppUpdateService.isAutoUpdateEnabled(), false);
    await AppUpdateService.setAutoUpdateEnabled(true);
    expect(await AppUpdateService.isAutoUpdateEnabled(), true);

    // Semver parsing & comparisons
    expect(AppUpdateService.isRemoteNewer('v2.0.18', '2.0.17'), true);
    expect(AppUpdateService.isRemoteNewer('V2.1.0 - R', '2.0.99'), true);
    expect(AppUpdateService.isRemoteNewer('v2.0.17', '2.0.17'), false);
    expect(AppUpdateService.isRemoteNewer('v2.0.12', '2.0.17'), false);

    // GitHub release JSON parsing prefers Tempo.apk and extracts sha256 digest
    final mockPayload = <String, dynamic>{
      'tag_name': 'v2.1.0',
      'name': 'Tempo V2.1.0 - R',
      'body': '## Highlights\n- Faster splash\n- Liquid Glass pill',
      'draft': false,
      'prerelease': false,
      'published_at': '2026-11-26T08:00:00Z',
      'html_url': 'https://github.com/kenji0011/fitness-tracker-v2/releases/tag/v2.1.0',
      'assets': [
        {
          'name': 'notes.txt',
          'size': 512,
          'browser_download_url': 'https://example.com/notes.txt',
        },
        {
          'name': 'Tempo.apk',
          'size': 203948032,
          'digest':
              'sha256:88e4d38f8a4193b7abe666f5a30123456789abcdef0123456789abcdef012345',
          'browser_download_url':
              'https://github.com/kenji0011/fitness-tracker-v2/releases/download/v2.1.0/Tempo.apk',
        },
      ],
    };

    final parsed = AppUpdateService.parseReleaseJson(mockPayload);
    expect(parsed, isNotNull);
    expect(parsed!.version, '2.1.0');
    expect(parsed.displayVersion, 'V2.1.0 - R');
    expect(parsed.apkName, 'Tempo.apk');
    expect(parsed.sha256Digest,
        '88e4d38f8a4193b7abe666f5a30123456789abcdef0123456789abcdef012345');

    // Mocked checkForUpdate returns updateAvailable when remote > current
    final res = await AppUpdateService.checkForUpdate(
      manual: false,
      currentVersionOverride: '2.0.17',
      releaseFetcherOverride: () async => mockPayload,
      nowMsOverride: 100000000,
    );
    expect(res.status, TempoUpdateCheckStatus.updateAvailable);
    expect(res.release?.version, '2.1.0');

    // Skipped version is respected on automatic check, but still shown on manual check
    await AppUpdateService.skipVersion('2.1.0');
    final skippedRes = await AppUpdateService.checkForUpdate(
      manual: false,
      currentVersionOverride: '2.0.17',
      releaseFetcherOverride: () async => mockPayload,
      nowMsOverride: 100000000 + 7 * 60 * 60 * 1000,
    );
    expect(skippedRes.status, TempoUpdateCheckStatus.skipped);

    final manualRes = await AppUpdateService.checkForUpdate(
      manual: true,
      currentVersionOverride: '2.0.17',
      releaseFetcherOverride: () async => mockPayload,
    );
    expect(manualRes.status, TempoUpdateCheckStatus.updateAvailable);
    AppUpdateService.availableRelease.value = null;
  });

  testWidgets(
      'showTempoUpdateSheet renders floating bottom modal with navbar clearance in Light & Dark Mode',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final themeProvider = ThemeProvider();
    const release = TempoReleaseInfo(
      version: '2.1.0',
      tagName: 'v2.1.0',
      title: 'Tempo V2.1.0 - R',
      releaseNotes: '- Smooth Liquid Glass navbar\n- In-app GitHub updates',
      apkUrl: 'https://example.com/Tempo.apk',
      apkName: 'Tempo.apk',
      apkSizeBytes: 204472320,
      htmlUrl: 'https://github.com/kenji0011/fitness-tracker-v2/releases/tag/v2.1.0',
    );

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: themeProvider,
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(400, 860),
              viewPadding: EdgeInsets.only(bottom: 34),
            ),
            child: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => showTempoUpdateSheet(context, release),
                    child: const Text('Open Update'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Update'));
    await tester.pumpAndSettle();

    expect(find.text('Update Available'), findsOneWidget);
    expect(find.textContaining('V2.1.0 - R'), findsOneWidget);
    expect(find.text('Update now'), findsOneWidget);
    expect(find.text('Later'), findsOneWidget);
    expect(find.text('Skip version'), findsOneWidget);

    // Dismiss via Later button
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(find.text('Update Available'), findsNothing);
  });

  testWidgets(
      'StepCounterSync accuracy warning shows daily and respects "Don\'t show again today"',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final db = TempoRustDb.instance;
    await db.init();
    final profile = await db.createProfile(
      displayName: 'StepNoticeUser',
      pin: '2222',
    );

    // Shown by default today, suppressed after dismissing for today, resets tomorrow
    expect(
      await StepCounterSync.shouldShowAccuracyWarning(
        profile.id,
        todayKeyOverride: '2026-11-26',
      ),
      true,
    );
    await StepCounterSync.dismissAccuracyWarningForToday(
      profile.id,
      todayKeyOverride: '2026-11-26',
    );
    expect(
      await StepCounterSync.shouldShowAccuracyWarning(
        profile.id,
        todayKeyOverride: '2026-11-26',
      ),
      false,
    );
    expect(
      await StepCounterSync.shouldShowAccuracyWarning(
        profile.id,
        todayKeyOverride: '2026-11-27',
      ),
      true,
    );

    // Floating modal renders warning copy and returns suppressForToday on tap
    final themeProvider = ThemeProvider();
    StepAccuracyWarningResult? result;
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: themeProvider,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    result = await showStepAccuracyWarningSheet(context);
                  },
                  child: const Text('Trigger Notice'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Trigger Notice'));
    await tester.pumpAndSettle();
    expect(find.text('Step Counter Accuracy'), findsOneWidget);
    expect(find.text('Offline motion sensor estimate'), findsNothing);
    expect(find.byIcon(CupertinoIcons.xmark), findsNothing);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Enable'), findsOneWidget);
    expect(find.text("Don't show again today"), findsOneWidget);

    // Toggle circular "Don't show again today" then tap flat Enable on the right
    await tester.tap(find.text("Don't show again today"));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enable'));
    await tester.pumpAndSettle();
    expect(result?.proceed, true);
    expect(result?.suppressForToday, true);

    await db.deleteProfile(profile.id);
  });

  testWidgets(
      'ActivityStatsScreen renders weekly rings, charts, and opens ProgressShareScreen',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final db = TempoRustDb.instance;
    await db.init();
    final profile = await db.createProfile(
      displayName: 'Kenji',
      pin: '1234',
      dailyCaloriesGoal: 600,
      dailyStepsGoal: 7000,
      dailyMinutesGoal: 60,
    );
    await db.upsertDailyActivity(
      profileId: profile.id,
      calories: 320,
      steps: 4500,
      minutes: 35,
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
          home: ActivityStatsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Stats'), findsOneWidget);
    expect(find.byType(OvalActivityRings), findsOneWidget);
    expect(find.byType(MiniOvalActivityRings), findsNWidgets(7));
    expect(find.text('Calories (kcal)'), findsAtLeastNWidgets(1));
    expect(find.text('Steps'), findsAtLeastNWidgets(1));
    expect(find.text('320'), findsAtLeastNWidgets(1));

    // Scroll down to reveal Steps and Activity time cards
    await tester.scrollUntilVisible(
      find.text('Current steps'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('4,500'), findsAtLeastNWidgets(1));

    // Tap Share icon at top right to open ProgressShareScreen
    await tester.tap(find.byIcon(CupertinoIcons.share));
    await tester.pumpAndSettle();
    expect(find.byType(ProgressShareScreen), findsOneWidget);
    expect(find.text('Share'), findsAtLeastNWidgets(1));
    expect(find.text('Day'), findsOneWidget);
    expect(find.text('Month'), findsOneWidget);

    await themeProvider.toggleTheme(true);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await db.deleteProfile(profile.id);
  });

  testWidgets(
      'ProgressShareScreen switches Day/Month, customizes metrics, and saves local templates',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final db = TempoRustDb.instance;
    await db.init();
    final profile = await db.createProfile(
      displayName: 'Kenji',
      pin: '1234',
      dailyCaloriesGoal: 600,
      dailyStepsGoal: 7000,
      dailyMinutesGoal: 60,
    );
    await db.upsertDailyActivity(
      profileId: profile.id,
      calories: 410,
      steps: 6120,
      minutes: 42,
    );
    await db.logBodyMetric(
      profileId: profile.id,
      metricType: 'water',
      value: 750,
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
          home: ProgressShareScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('410'), findsOneWidget);
    expect(find.text('6,120'), findsOneWidget);

    // Switch to Month view and verify monthly ring calendar renders
    await tester.tap(find.text('Month'));
    await tester.pumpAndSettle();
    expect(find.text('Goals met'), findsOneWidget);
    expect(find.byType(MiniOvalActivityRings), findsAtLeastNWidgets(28));

    // Switch back to Day and customize metrics (add Water) + layout (Centered)
    await tester.tap(find.text('Day'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Customize'));
    await tester.pumpAndSettle();
    expect(find.text('Customize Template'), findsOneWidget);

    final expandedSheetTop = tester.getTopLeft(find.text('Customize Template')).dy;

    // Tapping a Layout Style lowers the sheet into Layout Preview Peek so the
    // live poster above stays unobstructed while comparing layouts.
    await tester.tap(find.text('Centered'));
    await tester.pumpAndSettle();
    final peekingSheetTop = tester.getTopLeft(find.text('Customize Template')).dy;
    expect(peekingSheetTop, greaterThan(expandedSheetTop + 80));
    expect(find.text('Classic'), findsOneWidget);
    expect(find.text('Minimal'), findsOneWidget);

    // Expanding back (via the header chevron or peeking METRICS SHOWN bar)
    // restores full customization controls.
    await tester.tap(find.byTooltip('Expand options'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Customize Template')).dy,
      lessThan(peekingSheetTop - 80),
    );

    await tester.tap(find.text('Water'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    // Save custom template locally and verify persistence via ShareTemplateService
    await tester.tap(find.text('Template'));
    await tester.pumpAndSettle();
    expect(find.text('Save Template Locally'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Morning Run');
    await tester.tap(find.text('Save template'));
    await tester.pumpAndSettle();

    final stored = await ShareTemplateService.loadTemplates(profile.id);
    expect(stored.length, 1);
    expect(stored.first.name, 'Morning Run');
    expect(stored.first.layout, 'centered');
    expect(stored.first.metrics, contains('water'));

    await tester.scrollUntilVisible(
      find.text('Morning Run'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Morning Run'), findsOneWidget);

    await db.deleteProfile(profile.id);
  });

  testWidgets('TempoMorphPageRoute morphs smoothly open and closed with card snapshot', (tester) async {
    final themeProvider = ThemeProvider();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: themeProvider,
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                child: Builder(
                  builder: (cardCtx) => GestureDetector(
                    onTap: () => pushTempoMorphRoute<void>(
                      context: cardCtx,
                      sourceContext: cardCtx,
                      sourceBorderRadius: 20,
                      builder: (pageCtx) => Scaffold(
                        body: Center(
                          child: TextButton(
                            onPressed: () => Navigator.of(pageCtx).pop(),
                            child: const Text('Close Morph Page'),
                          ),
                        ),
                      ),
                    ),
                    child: Container(
                      width: 160,
                      height: 160,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(CupertinoIcons.gauge, color: Color(0xFF4CD964)),
                          SizedBox(height: 8),
                          Text('Open Weight Card'),
                          Text('61.5 kg'),
                        ],
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
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open Weight Card'));
    // Sample early lift + mid-flight open morph frames
    await tester.pump(const Duration(milliseconds: 30));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();
    expect(find.text('Close Morph Page'), findsOneWidget);

    // Sample Stage 1 (page -> card snapshot) + Stage 2 (pure card snapshot landing)
    await tester.tap(find.text('Close Morph Page'));
    await tester.pump(const Duration(milliseconds: 30));
    await tester.pump(const Duration(milliseconds: 140));
    await tester.pump(const Duration(milliseconds: 140));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(find.text('Open Weight Card'), findsOneWidget);
    expect(find.text('Close Morph Page'), findsNothing);

    // Repeat in Dark Mode to verify themed snapshot capture and clean disposal
    await themeProvider.toggleTheme(true);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open Weight Card'));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close Morph Page'));
    await tester.pump(const Duration(milliseconds: 220));
    await tester.pumpAndSettle();
    expect(find.text('Open Weight Card'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('showTempoPopoverMenu plays HyperOS 4 decoupled 2-spring detached arc and blur morph', (tester) async {
    final themeProvider = ThemeProvider();
    final anchorKey = GlobalKey();
    var selectedAction = '';

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: themeProvider,
        child: MaterialApp(
          home: Scaffold(
            body: SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Builder(
                    builder: (btnCtx) => TempoGlassCircleButton(
                      key: anchorKey,
                      icon: const Icon(CupertinoIcons.ellipsis_vertical, size: 20),
                      onPressed: () => showTempoPopoverMenu(
                        context: btnCtx,
                        anchorKey: anchorKey,
                        actions: [
                          TempoPopoverAction(
                            label: 'Add data',
                            onTap: () => selectedAction = 'add',
                          ),
                          TempoPopoverAction(
                            label: 'Daily goal',
                            onTap: () => selectedAction = 'goal',
                          ),
                        ],
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
    await tester.pumpAndSettle();
    expect(activeTempoPopoverAnchorKey.value, isNull);

    // Open popover -> verify anchor glyph suppresses immediately & mid-flight frames stay clean
    await tester.tap(find.byKey(anchorKey));
    await tester.pump(const Duration(milliseconds: 20));
    expect(activeTempoPopoverAnchorKey.value, same(anchorKey));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pump(const Duration(milliseconds: 140));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pumpAndSettle();
    expect(find.text('Add data'), findsOneWidget);
    expect(find.text('Daily goal'), findsOneWidget);

    // Tap an action -> verify close droplet glide & synchronous anchor restoration
    await tester.tap(find.text('Add data'));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(selectedAction, 'add');
    expect(activeTempoPopoverAnchorKey.value, isNull);

    // Repeat in Dark Mode and dismiss via barrier tap
    await themeProvider.toggleTheme(true);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(anchorKey));
    await tester.pump(const Duration(milliseconds: 110));
    await tester.pumpAndSettle();
    expect(find.text('Daily goal'), findsOneWidget);
    await tester.tapAt(const Offset(20, 400));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(activeTempoPopoverAnchorKey.value, isNull);
    expect(find.text('Daily goal'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Circular header TempoMorphPageRoute hides anchor and closes as a true circle', (tester) async {
    final themeProvider = ThemeProvider();
    final circleKey = GlobalKey();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: themeProvider,
        child: MaterialApp(
          home: Scaffold(
            body: SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Builder(
                    builder: (btnCtx) => TempoGlassCircleButton(
                      key: circleKey,
                      icon: const Icon(CupertinoIcons.add, size: 22),
                      onPressed: () => pushTempoMorphRoute<void>(
                        context: btnCtx,
                        sourceKey: circleKey,
                        sourceBorderRadius: 999,
                        builder: (pageCtx) => Scaffold(
                          body: Center(
                            child: TextButton(
                              onPressed: () => Navigator.of(pageCtx).pop(),
                              child: const Text('Close Circular Morph'),
                            ),
                          ),
                        ),
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
    await tester.pumpAndSettle();
    expect(activeTempoMorphAnchorKey.value, isNull);

    // Open from 42x42 circle button -> underlying anchor suppresses cleanly (zero ghost circle)
    await tester.tap(find.byKey(circleKey));
    await tester.pump(const Duration(milliseconds: 80));
    expect(activeTempoMorphAnchorKey.value, same(circleKey));
    await tester.pumpAndSettle();
    expect(activeTempoMorphAnchorKey.value, isNull);
    expect(find.text('Close Circular Morph'), findsOneWidget);

    // Close -> verify anchor suppresses during flight and morph container becomes a 1:1 circle
    final poppedRoute = ModalRoute.of(
      tester.element(find.text('Close Circular Morph')),
    )! as TempoMorphPageRoute<void>;
    await tester.tap(find.text('Close Circular Morph'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 280));
    expect(activeTempoMorphAnchorKey.value, same(circleKey));
    final circleRect = poppedRoute.debugLastMorphRect;
    expect(circleRect, isNotNull);
    expect(circleRect!.width, inInclusiveRange(34.0, 200.0));
    expect((circleRect.width - circleRect.height).abs(), lessThan(2.0));

    await tester.pumpAndSettle();
    expect(activeTempoMorphAnchorKey.value, isNull);
    expect(find.byKey(circleKey), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Animation speed preference uses HyperOS dropdown and scales durations across Relaxed, Balanced, Fast', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final speedService = TempoAnimationSpeedService.instance;
    speedService.resetForTest();
    await speedService.initialize();

    // Verify default Balanced (1.0x) and scaling math
    expect(speedService.speed, TempoAnimationSpeed.balanced);
    expect(speedService.scale(const Duration(milliseconds: 500)).inMilliseconds, 500);

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
          home: MyProfile(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Animation speed now lives inside Appearance (moved out of Profile Preferences)
    expect(find.text('Animation speed'), findsNothing);
    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();

    expect(find.text('Animation speed'), findsOneWidget);
    expect(find.text('Balanced'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.chevron_up_chevron_down), findsOneWidget);

    // Open HyperOS dropdown -> select Relaxed
    await tester.tap(find.text('Animation speed'));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pumpAndSettle();
    expect(find.text('Relaxed'), findsOneWidget);
    expect(find.text('Fast'), findsOneWidget);

    await tester.tap(find.text('Relaxed'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(speedService.speed, TempoAnimationSpeed.relaxed);
    expect(find.text('Relaxed'), findsOneWidget);
    expect(speedService.scale(const Duration(milliseconds: 500)).inMilliseconds, 660);

    // Switch to Dark Mode, reopen dropdown -> select Fast
    await themeProvider.toggleTheme(true);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Animation speed'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fast'));
    await tester.pumpAndSettle();
    expect(speedService.speed, TempoAnimationSpeed.fast);
    expect(find.text('Fast'), findsOneWidget);
    expect(speedService.scale(const Duration(milliseconds: 500)).inMilliseconds, 325);

    // Verify persistence on reload
    speedService.resetForTest();
    await speedService.initialize(forceReload: true);
    expect(speedService.speed, TempoAnimationSpeed.fast);
    speedService.resetForTest();

    expect(tester.takeException(), isNull);
    await db.deleteProfile(profile.id);
  });
}

class _InitCountProbe extends StatefulWidget {
  final VoidCallback onInit;
  final Widget child;

  const _InitCountProbe({required this.onInit, required this.child});

  @override
  State<_InitCountProbe> createState() => _InitCountProbeState();
}

class _InitCountProbeState extends State<_InitCountProbe> {
  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
