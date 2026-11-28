import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:jiggicons/jiggicons.dart';
import 'package:provider/provider.dart';

import '../models/workout_model.dart';
import '../services/active_profile_provider.dart';
import '../services/appearance_service.dart';
import '../services/goal_completion_service.dart';
import '../services/journey_progress_service.dart';
import '../services/live_workout_service.dart';
import '../services/tempo_rust_db.dart';
import '../services/workout_anticheat_service.dart';
import '../services/workout_sound_service.dart';
import '../theme/app_colors.dart';
import '../widgets/ios_popover_menu.dart';
import '../widgets/ios_stretch_sheet.dart';
import '../widgets/liquid_glass_surface.dart';
import '../widgets/tempo_jigg_icon.dart';
import '../widgets/tempo_morph_route.dart';
import '../widgets/tempo_sliver_header.dart';
import '../widgets/tempo_spotlight_tour.dart';
import '../widgets/tempo_toast.dart';
import 'exercise_detail_screen.dart';

class WorkoutDetailScreen extends StatefulWidget {
  final Workout workout;

  /// Optional injectable engine for deterministic widget tests.
  final WorkoutAntiCheatEngine? engineOverride;

  const WorkoutDetailScreen({
    super.key,
    required this.workout,
    this.engineOverride,
  });

  @override
  State<WorkoutDetailScreen> createState() => _WorkoutDetailScreenState();
}

class _WorkoutDetailScreenState extends State<WorkoutDetailScreen> {
  static const int _defaultRestSeconds = 45;

  late final WorkoutAntiCheatEngine _engine;
  final GlobalKey _menuButtonKey = GlobalKey();
  final GlobalKey _sessionDeckKey = GlobalKey();
  final GlobalKey _spotlightCardKey = GlobalKey();
  final GlobalKey _exerciseQueueKey = GlobalKey();
  final GlobalKey _bottomCtaKey = GlobalKey();

  Timer? _tickTimer;
  bool _isCountingDown = false;
  bool _isSaving = false;

  // Optional auto-appearing quick rest countdown between verified exercises
  int _restRemainingSeconds = 0;

  @override
  void initState() {
    super.initState();
    _engine = widget.engineOverride ??
        WorkoutAntiCheatEngine(workout: widget.workout);
    LiveWorkoutService.instance.onRemoteTogglePause = () {
      if (mounted && !_isCountingDown) {
        _toggleTimer();
      }
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeShowWorkoutTour();
    });
  }

  Future<void> _maybeShowWorkoutTour({bool forceShow = false}) async {
    final pid = context.read<ActiveProfileProvider>().activeProfileId;
    if (pid == null || pid.isEmpty) return;
    await TempoSpotlightTour.showIfNeeded(
      context: context,
      profileId: pid,
      screenId: 'workout_detail',
      forceShow: forceShow,
      delay: forceShow
          ? const Duration(milliseconds: 180)
          : const Duration(milliseconds: 520),
      steps: [
        TempoSpotlightStep(
          targetKey: _sessionDeckKey,
          title: 'Start your session timer',
          description:
              'Tap Start to run the live workout timer. Tempo tracks your active effort automatically so each verified exercise counts toward streaks and Journey progress.',
          borderRadius: 28,
        ),
        if (widget.workout.exerciseList.isNotEmpty)
          TempoSpotlightStep(
            targetKey: _spotlightCardKey,
            title: 'Follow the active exercise',
            description:
                'Tap Watch & Log to view the form video and record weight, sets, and reps, or tap Mark Done once your active effort unlocks verification.',
            borderRadius: 26,
          ),
        TempoSpotlightStep(
          targetKey: _exerciseQueueKey,
          title: 'Navigate the exercise list',
          description:
              'Tap any exercise row or play button to jump straight to its video and set logger, or tap its numbered badge to verify progress as you finish.',
          borderRadius: 24,
        ),
        TempoSpotlightStep(
          targetKey: _bottomCtaKey,
          title: 'Complete or end early',
          description:
              'Complete Workout unlocks once all exercises are verified and minimum active time is met. Open the top-right menu anytime to replay this guide, reset, or end early.',
          borderRadius: 999,
        ),
      ],
    );
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    LiveWorkoutService.instance.onRemoteTogglePause = null;
    LiveWorkoutService.instance.stop();
    super.dispose();
  }

  String get _categoryLabel => (widget.workout.journeyName != null &&
          widget.workout.journeyName!.isNotEmpty)
      ? widget.workout.journeyName!
      : widget.workout.bodyFocus;

  String get _activeExerciseName {
    final list = widget.workout.exerciseList;
    final idx = _engine.activeExerciseIndex;
    if (idx != null && idx < list.length) {
      return list[idx].name;
    }
    return list.isNotEmpty ? list.last.name : '';
  }

  double get _avgKcalPerMin {
    final list = widget.workout.exerciseList;
    if (list.isEmpty) return 7.5;
    final total = list.fold<int>(0, (s, e) => s + e.baseCaloriesPerMinute);
    return (total / list.length).clamp(4.0, 16.0);
  }

  void _syncLiveUpdate({required bool isPaused}) {
    LiveWorkoutService.instance.startOrUpdate(
      workoutTitle: widget.workout.title,
      category: _categoryLabel,
      currentExercise: _activeExerciseName,
      kcalPerMin: _avgKcalPerMin,
      elapsedSeconds: _engine.elapsedSeconds,
      completedExercises: _engine.verifiedCount,
      totalExercises: _engine.totalExercises,
      isPaused: isPaused,
    );
  }

  void _ensureTickTimer() {
    _tickTimer?.cancel();
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_restRemainingSeconds > 0 && _engine.isRunning) {
        _restRemainingSeconds = math.max(0, _restRemainingSeconds - 1);
        if (_restRemainingSeconds == 0) {
          HapticFeedback.mediumImpact();
        }
      }
      setState(() {});
    });
  }

  void _startTimerTicking() {
    _engine.resume();
    setState(() => _isCountingDown = false);
    _syncLiveUpdate(isPaused: false);
    _ensureTickTimer();
  }

  void _toggleTimer() {
    if (_isCountingDown) return;
    HapticFeedback.selectionClick();
    if (_engine.isRunning) {
      _tickTimer?.cancel();
      _engine.pause();
      setState(() {});
      _syncLiveUpdate(isPaused: true);
    } else if (!_engine.hasStarted) {
      LiveWorkoutService.instance.ensureNotificationPermission();
      setState(() => _isCountingDown = true);
    } else {
      _startTimerTicking();
    }
  }

  void _resetSession() {
    HapticFeedback.selectionClick();
    _tickTimer?.cancel();
    LiveWorkoutService.instance.stop();
    _engine.reset();
    setState(() {
      _isCountingDown = false;
      _restRemainingSeconds = 0;
    });
  }

  void _handleExerciseToggle(int index) {
    HapticFeedback.selectionClick();
    if (_engine.isExerciseVerified(index)) {
      setState(() {
        _engine.unverifyExercise(index);
      });
      if (_engine.hasStarted) {
        _syncLiveUpdate(isPaused: !_engine.isRunning);
      }
      return;
    }

    final gate = _engine.tryVerifyExercise(index);
    if (!gate.allowed) {
      HapticFeedback.heavyImpact();
      showTempoToast(context, gate.guidanceText(), showIcon: false);
      return;
    }

    HapticFeedback.mediumImpact();
    final hasRemaining = _engine.activeExerciseIndex != null;
    setState(() {
      _restRemainingSeconds = hasRemaining ? _defaultRestSeconds : 0;
    });
    _syncLiveUpdate(isPaused: !_engine.isRunning);
  }

  Future<void> _openExerciseDetail(
    BuildContext sourceContext,
    int index,
    Exercise exercise,
  ) async {
    HapticFeedback.selectionClick();
    final logged = await pushTempoMorphRoute<bool>(
      context: context,
      sourceContext: sourceContext,
      sourceBorderRadius: 20,
      builder: (_) => ExerciseDetailScreen(
        exercise: exercise,
        workout: widget.workout,
      ),
    );
    if (!mounted) return;
    if (logged == true && !_engine.isExerciseVerified(index)) {
      final gate = _engine.tryVerifyExercise(index);
      if (gate.allowed) {
        final hasRemaining = _engine.activeExerciseIndex != null;
        setState(() {
          _restRemainingSeconds = hasRemaining ? _defaultRestSeconds : 0;
        });
        _syncLiveUpdate(isPaused: !_engine.isRunning);
      } else {
        showTempoToast(
          context,
          'Set saved. ${gate.guidanceText()} to verify this exercise.',
          showIcon: false,
        );
      }
    }
  }

  void _openHeaderMenu() {
    final c = AppColors.of(context, listen: false);
    final actions = <TempoPopoverAction>[
      TempoPopoverAction(
        label: 'Workout guide',
        onTap: () => _maybeShowWorkoutTour(forceShow: true),
      ),
      TempoPopoverAction(
        label: 'Reset session',
        onTap: () {
          _resetSession();
          showTempoToast(context, 'Session reset', showIcon: false);
        },
      ),
      if (_engine.hasStarted)
        TempoPopoverAction(
          label: 'End early',
          textColor: c.moveRed,
          onTap: _confirmEndEarly,
        ),
    ];

    showTempoPopoverMenu(
      context: context,
      anchorKey: _menuButtonKey,
      actions: actions,
    );
  }

  Future<void> _confirmEndEarly() async {
    final c = AppColors.of(context, listen: false);
    final proportionalKcal = _engine.estimateVerifiedCalories(
      kcalPerMin: _avgKcalPerMin,
    );
    final confirmed = await showTempoSheet<bool>(
      context: context,
      backgroundColor: c.card,
      borderRadius: 28,
      showDragHandle: true,
      builder: (ctx) {
        final mc = AppColors.of(ctx);
        return Padding(
          padding: EdgeInsets.fromLTRB(
            22,
            10,
            22,
            MediaQuery.paddingOf(ctx).bottom + 22,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: mc.moveRed.withValues(alpha: mc.isDark ? 0.20 : 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    CupertinoIcons.flag_slash_fill,
                    color: mc.moveRed,
                    size: 24,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'End Workout Early?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: mc.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.35,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Ending early saves only your proportional active burn ($proportionalKcal kcal) for ${_engine.verifiedCount} of ${_engine.totalExercises} verified exercises. It will not mark this workout completed or advance Journey progress.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: mc.textSecondary,
                  fontSize: 13.5,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: TempoLiquidButton(
                      primary: false,
                      height: 50,
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: const Text('Keep going'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TempoBouncyButton(
                      height: 50,
                      backgroundColor: mc.moveRed,
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: const Text('End early'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );

    if (confirmed == true && mounted) {
      await _saveEarlyExit(proportionalKcal);
    }
  }

  Future<void> _saveEarlyExit(int proportionalKcal) async {
    final profileProvider = context.read<ActiveProfileProvider>();
    final profileId = profileProvider.activeProfileId;
    if (profileId == null) return;

    _tickTimer?.cancel();
    _engine.pause();
    LiveWorkoutService.instance.stop();
    setState(() => _isSaving = true);

    try {
      final elapsed = math.max(1, _engine.elapsedSeconds);
      await TempoRustDb.instance.logCompletedWorkout(
        profileId: profileId,
        workoutId: widget.workout.id,
        title: widget.workout.title,
        durationLabel: widget.workout.duration,
        exercisesLabel: widget.workout.exercises,
        level: widget.workout.level,
        bodyFocus: widget.workout.bodyFocus,
        journeyId: widget.workout.journeyId ?? '',
        journeyName: widget.workout.journeyName ?? '',
        actualDurationSec: elapsed,
        expectedDurationSec: _engine.expectedTotalSeconds,
        caloriesBurned: proportionalKcal,
        isCheated: true, // Marks early/partial exit so Streak & Journey ignore it
      );
      profileProvider.notifyDataChanged();
      if (mounted) {
        showTempoToast(
          context,
          'Ended early, logged $proportionalKcal kcal active burn',
        );
        Navigator.of(context).pop(false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        showTempoToast(context, 'Could not save session: $e', isError: true);
      }
    }
  }

  Future<void> _completeWorkout() async {
    final gate = _engine.evaluateCompletion();
    if (!gate.canComplete) {
      HapticFeedback.heavyImpact();
      showTempoToast(context, gate.statusLabel(), showIcon: false);
      return;
    }

    final profileProvider = context.read<ActiveProfileProvider>();
    final profileId = profileProvider.activeProfileId;
    if (profileId == null) return;

    _tickTimer?.cancel();
    _engine.pause();
    LiveWorkoutService.instance.stop();
    setState(() {
      _isCountingDown = false;
      _restRemainingSeconds = 0;
      _isSaving = true;
    });

    try {
      final expectedSec = _engine.expectedTotalSeconds;
      final actualSec = math.max(1, _engine.elapsedSeconds);
      final calories = _engine.estimateVerifiedCalories(
        kcalPerMin: _avgKcalPerMin,
      );

      await TempoRustDb.instance.logCompletedWorkout(
        profileId: profileId,
        workoutId: widget.workout.id,
        title: widget.workout.title,
        durationLabel: widget.workout.duration,
        exercisesLabel: widget.workout.exercises,
        level: widget.workout.level,
        bodyFocus: widget.workout.bodyFocus,
        journeyId: widget.workout.journeyId ?? '',
        journeyName: widget.workout.journeyName ?? '',
        actualDurationSec: actualSec,
        expectedDurationSec: expectedSec,
        caloriesBurned: calories,
        isCheated: false,
      );

      if (widget.workout.journeyId != null &&
          widget.workout.journeyId!.isNotEmpty) {
        await JourneyProgressService.syncJourneyProgressForProfile(
          profileId: profileId,
          journeyId: widget.workout.journeyId!,
          journeyName: widget.workout.journeyName ?? widget.workout.bodyFocus,
          isSelected: true,
          markStarted: true,
        );
      }

      profileProvider.notifyDataChanged();

      if (!mounted) return;
      HapticFeedback.heavyImpact();
      final c = AppColors.of(context, listen: false);
      await showTempoSheet<void>(
        context: context,
        backgroundColor: c.card,
        borderRadius: 28,
        showDragHandle: true,
        builder: (ctx) {
          final mc = AppColors.of(ctx);
          return Padding(
            padding: EdgeInsets.fromLTRB(
              22,
              10,
              22,
              MediaQuery.paddingOf(ctx).bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TempoJiggIcon(
                        'confetti',
                        variant: JiggIconVariant.duotone,
                        color: mc.accent,
                        size: 28,
                        trigger: JiggIconTrigger.appear,
                        fallbackIcon: CupertinoIcons.sparkles,
                      ),
                      const SizedBox(width: 12),
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: mc.accent
                              .withValues(alpha: mc.isDark ? 0.22 : 0.13),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: TempoJiggIcon(
                            'trophy',
                            variant: JiggIconVariant.solid,
                            color: mc.accent,
                            size: 30,
                            trigger: JiggIconTrigger.appear,
                            fallbackIcon: CupertinoIcons.checkmark_alt,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Transform.flip(
                        flipX: true,
                        child: TempoJiggIcon(
                          'confetti',
                          variant: JiggIconVariant.duotone,
                          color: mc.accent,
                          size: 28,
                          trigger: JiggIconTrigger.appear,
                          fallbackIcon: CupertinoIcons.sparkles,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Workout Completed',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: mc.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.workout.title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: mc.textSecondary,
                    fontSize: 14.5,
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: mc.searchBg,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              _formatTime(actualSec),
                              style: TextStyle(
                                color: mc.textPrimary,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Active Time',
                              style: TextStyle(
                                color: mc.textTertiary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(width: 1, height: 32, color: mc.divider),
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              '$calories kcal',
                              style: TextStyle(
                                color: mc.textPrimary,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Verified Burn',
                              style: TextStyle(
                                color: mc.textTertiary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                TempoBouncyButton(
                  height: 52,
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    Navigator.of(ctx).pop();
                  },
                  child: const Text('Done'),
                ),
              ],
            ),
          );
        },
      );
      if (mounted) {
        await GoalCompletionService.instance.checkAndCelebrate(
          context,
          profileId: profileId,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        showTempoToast(context, 'Error saving workout: $e', isError: true);
      }
    }
  }

  String _formatTime(int sec) {
    final safe = sec.clamp(0, 86400);
    final m = (safe ~/ 60).toString().padLeft(2, '0');
    final s = (safe % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _formatDurationCompact(int sec) {
    final m = sec ~/ 60;
    final s = sec % 60;
    if (m == 0) return '${s}s';
    if (s == 0) return '${m}m';
    return '${m}m ${s}s';
  }

  int _estimatedFullPreviewKcal() {
    final expectedMin = _engine.expectedTotalSeconds / 60.0;
    return (expectedMin * _avgKcalPerMin).round().clamp(35, 950);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final exercises = widget.workout.exerciseList;
    final completionGate = _engine.evaluateCompletion();
    final activeIdx = _engine.activeExerciseIndex;
    final liveKcal = _engine.hasStarted
        ? _engine.estimateVerifiedCalories(kcalPerMin: _avgKcalPerMin)
        : _estimatedFullPreviewKcal();

    return Scaffold(
      backgroundColor: c.scaffold,
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    TempoSliverHeader(
                      title: widget.workout.title,
                      showBackButton: true,
                      actions: [
                        TempoHeaderAction(
                          buttonKey: _menuButtonKey,
                          tooltip: 'Session options',
                          icon: Icon(
                            CupertinoIcons.ellipsis_vertical,
                            color: c.textPrimary,
                            size: 19,
                          ),
                          onPressed: _openHeaderMenu,
                        ),
                      ],
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
                      sliver: SliverList.list(
                        children: [
                          // 1. Liquid Glass Session Command Deck
                          _buildSessionCommandDeck(
                            c: c,
                            liveKcal: liveKcal,
                            completionGate: completionGate,
                          ),
                          const SizedBox(height: 16),

                          // 2. Active Exercise Focus Spotlight Card
                          if (exercises.isNotEmpty) ...[
                            _buildActiveSpotlightCard(
                              c: c,
                              activeIdx: activeIdx,
                              exercises: exercises,
                              completionGate: completionGate,
                            ),
                            const SizedBox(height: 22),
                          ],

                          // 3. Exercise Queue Section Header
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                            child: Row(
                              children: [
                                Text(
                                  'Exercises',
                                  style: TextStyle(
                                    color: c.textPrimary,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  '${_engine.verifiedCount} of ${exercises.length} verified',
                                  style: TextStyle(
                                    color: c.textSecondary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // 4. Refined Exercise Queue
                          _buildExerciseQueue(
                            c: c,
                            exercises: exercises,
                            activeIdx: activeIdx,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // 5. Anti-Cheat Smart Bottom CTA Bar
              _buildBottomCtaBar(c: c, gate: completionGate),
            ],
          ),

          // Full-screen Impeller-Safe 3-2-1-GO Countdown Overlay
          if (_isCountingDown)
            Positioned.fill(
              child: _SessionCountdownOverlay(
                workoutTitle: widget.workout.title,
                onComplete: _startTimerTicking,
                onCancel: () => setState(() => _isCountingDown = false),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSessionCommandDeck({
    required AppColors c,
    required int liveKcal,
    required WorkoutCompletionGate completionGate,
  }) {
    final statusText = _engine.isRunning
        ? 'In progress'
        : (_engine.hasStarted ? 'Paused' : 'Session timer');

    return LiquidGlassSurface(
      key: _sessionDeckKey,
      borderRadius: 28,
      blurEnabled: false,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Metadata Row
          Row(
            children: [
              Expanded(
                child: Text(
                  _categoryLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.textSecondary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: c.accent.withValues(alpha: c.isDark ? 0.22 : 0.12),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  widget.workout.level,
                  style: TextStyle(
                    color: c.accent,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (widget.workout.description != null &&
              widget.workout.description!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              widget.workout.description!.trim(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.textTertiary,
                fontSize: 13,
                height: 1.38,
              ),
            ),
          ],
          const SizedBox(height: 14),

          // Recessed Metrics Trio
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: c.isDark
                  ? Colors.white.withValues(alpha: 0.055)
                  : Colors.black.withValues(alpha: 0.035),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _OverviewMetric(
                    label: 'Duration',
                    value: widget.workout.duration,
                  ),
                ),
                Container(width: 1, height: 26, color: c.divider),
                Expanded(
                  child: _OverviewMetric(
                    label: 'Verified',
                    value:
                        '${completionGate.verifiedCount}/${completionGate.totalExercises}',
                  ),
                ),
                Container(width: 1, height: 26, color: c.divider),
                Expanded(
                  child: _OverviewMetric(
                    label: _engine.hasStarted ? 'Live Burn' : 'Est. Burn',
                    value: '$liveKcal kcal',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Live Session Timer + Action Row
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _engine.isRunning
                                ? const Color(0xFF34C759)
                                : (_engine.hasStarted
                                    ? c.accent
                                    : c.textTertiary),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          statusText,
                          style: TextStyle(
                            color: _engine.isRunning
                                ? c.accent
                                : c.textSecondary,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatTime(_engine.elapsedSeconds),
                      style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1.1,
                        height: 1.08,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              if (!_engine.isRunning && _engine.hasStarted) ...[
                TempoGlassCircleButton(
                  size: 42,
                  tooltip: 'Reset session',
                  enableBlur: false,
                  icon: Icon(
                    CupertinoIcons.arrow_counterclockwise,
                    color: c.textPrimary,
                    size: 17,
                  ),
                  onPressed: _resetSession,
                ),
                const SizedBox(width: 10),
              ],
              _engine.isRunning
                  ? TempoLiquidButton(
                      primary: false,
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      onPressed: _toggleTimer,
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(CupertinoIcons.pause_fill, size: 15),
                          SizedBox(width: 6),
                          Text('Pause', style: TextStyle(fontSize: 14.5)),
                        ],
                      ),
                    )
                  : TempoBouncyButton(
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      onPressed: _toggleTimer,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            CupertinoIcons.play_fill,
                            color: Colors.white,
                            size: 15,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _engine.hasStarted ? 'Resume' : 'Start',
                            style: const TextStyle(fontSize: 14.5),
                          ),
                        ],
                      ),
                    ),
            ],
          ),

          // Auto-Appearing Liquid Glass Rest Banner
          AnimatedSize(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            child: _restRemainingSeconds > 0
                ? Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: c.accent.withValues(
                          alpha: c.isDark ? 0.16 : 0.09,
                        ),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: c.accent.withValues(alpha: 0.30),
                          width: 0.9,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            CupertinoIcons.timer,
                            color: c.accent,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Rest ${_formatTime(_restRemainingSeconds)}',
                              style: TextStyle(
                                color: c.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                          TempoLiquidButton(
                            primary: false,
                            height: 32,
                            padding: const EdgeInsets.symmetric(horizontal: 11),
                            onPressed: () {
                              HapticFeedback.selectionClick();
                              setState(() {
                                _restRemainingSeconds =
                                    (_restRemainingSeconds + 15).clamp(0, 300);
                              });
                            },
                            child: const Text(
                              '+15s',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                          const SizedBox(width: 6),
                          TempoLiquidButton(
                            primary: false,
                            height: 32,
                            padding: const EdgeInsets.symmetric(horizontal: 11),
                            onPressed: () {
                              HapticFeedback.selectionClick();
                              setState(() => _restRemainingSeconds = 0);
                            },
                            child: const Text(
                              'Skip',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveSpotlightCard({
    required AppColors c,
    required int? activeIdx,
    required List<Exercise> exercises,
    required WorkoutCompletionGate completionGate,
  }) {
    if (activeIdx == null) {
      return LiquidGlassSurface(
        key: _spotlightCardKey,
        borderRadius: 26,
        blurEnabled: false,
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c.accent.withValues(alpha: c.isDark ? 0.22 : 0.13),
              ),
              child: Icon(
                CupertinoIcons.checkmark_seal_fill,
                color: c.accent,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'All Exercises Verified',
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    completionGate.canComplete
                        ? 'Tap Complete Workout below to log your session'
                        : completionGate.statusLabel(),
                    style: TextStyle(
                      color: c.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final ex = exercises[activeIdx];
    final gate = _engine.canCheckExercise(activeIdx);

    return LiquidGlassSurface(
      key: _spotlightCardKey,
      borderRadius: 26,
      blurEnabled: false,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: c.accent.withValues(alpha: c.isDark ? 0.22 : 0.12),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  'UP NEXT  ${activeIdx + 1}/${exercises.length}',
                  style: TextStyle(
                    color: c.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const Spacer(),
              Text(
                _formatDurationCompact(ex.duration),
                style: TextStyle(
                  color: c.textSecondary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            ex.name,
            style: TextStyle(
              color: c.textPrimary,
              fontSize: 19,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.35,
            ),
          ),
          if (ex.description.trim().isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              ex.description.trim(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 13.5,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 14),

          // Live Anti-Cheat Effort Verification Meter
          Text(
            gate.guidanceText(),
            style: TextStyle(
              color: gate.allowed ? c.textPrimary : c.textSecondary,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: gate.progress,
              minHeight: 5,
              backgroundColor: c.divider,
              valueColor: AlwaysStoppedAnimation<Color>(
                gate.allowed ? const Color(0xFF34C759) : c.accent,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Effortless 1-Tap Controls (Watch & Log + Mark Done)
          Row(
            children: [
              Expanded(
                child: Builder(
                  builder: (btnCtx) => TempoLiquidButton(
                    primary: false,
                    height: 46,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    onPressed: () => _openExerciseDetail(btnCtx, activeIdx, ex),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(CupertinoIcons.play_circle, size: 17),
                        SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Watch & Log',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: gate.allowed
                    ? TempoBouncyButton(
                        height: 46,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        onPressed: () => _handleExerciseToggle(activeIdx),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              CupertinoIcons.checkmark_alt,
                              color: Colors.white,
                              size: 17,
                            ),
                            SizedBox(width: 6),
                            Text('Mark Done', style: TextStyle(fontSize: 14)),
                          ],
                        ),
                      )
                    : TempoLiquidButton(
                        primary: false,
                        height: 46,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        onPressed: () => _handleExerciseToggle(activeIdx),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              CupertinoIcons.lock_fill,
                              size: 14,
                              color: c.textTertiary,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                _engine.hasStarted
                                    ? 'Wait ${gate.remainingSeconds}s'
                                    : 'Mark Done',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: c.textSecondary,
                                  fontSize: 14,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildExerciseQueue({
    required AppColors c,
    required List<Exercise> exercises,
    required int? activeIdx,
  }) {
    return AppleCard(
      key: _exerciseQueueKey,
      borderRadius: 24,
      padding: EdgeInsets.zero,
      child: Column(
        children: List.generate(exercises.length, (idx) {
          final ex = exercises[idx];
          final verified = _engine.isExerciseVerified(idx);
          final isCurrent = activeIdx == idx;
          final isLast = idx == exercises.length - 1;

          return Column(
            children: [
              Builder(
                builder: (rowCtx) => TempoTouchLightEffect(
                  borderRadius: 20,
                  emitLight: true,
                  receiveScatter: true,
                  cancelOnScroll: true,
                  intensity: 0.65,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => _openExerciseDetail(rowCtx, idx, ex),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 13,
                      ),
                      decoration: isCurrent
                          ? BoxDecoration(
                              color: c.accent.withValues(
                                alpha: c.isDark ? 0.10 : 0.055,
                              ),
                              borderRadius: BorderRadius.circular(20),
                            )
                          : null,
                      child: Row(
                        children: [
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _handleExerciseToggle(idx),
                            child: Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOutCubic,
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: verified
                                      ? c.accent
                                      : (isCurrent
                                          ? c.accent.withValues(
                                              alpha: c.isDark ? 0.22 : 0.14,
                                            )
                                          : c.searchBg),
                                  border: Border.all(
                                    color: verified || isCurrent
                                        ? c.accent
                                        : c.cardBorder,
                                    width: 1.2,
                                  ),
                                ),
                                child: Center(
                                  child: verified
                                      ? const Icon(
                                          CupertinoIcons.checkmark_alt,
                                          color: Colors.white,
                                          size: 15,
                                        )
                                      : Text(
                                          '${idx + 1}',
                                          style: TextStyle(
                                            color: isCurrent
                                                ? c.accent
                                                : c.textSecondary,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            fontFeatures: const [
                                              FontFeature.tabularFigures(),
                                            ],
                                          ),
                                        ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  ex.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: verified
                                        ? c.textTertiary
                                        : c.textPrimary,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    decoration: verified
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Row(
                                  children: [
                                    Text(
                                      _formatDurationCompact(ex.duration),
                                      style: TextStyle(
                                        color: c.textSecondary,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      verified
                                          ? 'Verified'
                                          : (isCurrent
                                              ? 'Current exercise'
                                              : 'Tap for video & log'),
                                      style: TextStyle(
                                        color: verified
                                            ? const Color(0xFF34C759)
                                            : (isCurrent
                                                ? c.accent
                                                : c.textTertiary),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          TempoGlassCircleButton(
                            size: 36,
                            enableBlur: false,
                            tooltip: 'Watch form video',
                            icon: Icon(
                              CupertinoIcons.play_fill,
                              color: isCurrent ? c.accent : c.textPrimary,
                              size: 14,
                            ),
                            onPressed: () =>
                                _openExerciseDetail(rowCtx, idx, ex),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (!isLast)
                Padding(
                  padding: const EdgeInsets.only(left: 54, right: 16),
                  child: Divider(height: 1, color: c.divider),
                ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildBottomCtaBar({
    required AppColors c,
    required WorkoutCompletionGate gate,
  }) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
        child: KeyedSubtree(
          key: _bottomCtaKey,
          child: gate.canComplete
              ? TempoBouncyButton(
                  key: const ValueKey('workout_complete_cta'),
                  height: 54,
                  onPressed: _isSaving ? null : _completeWorkout,
                  child: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          gate.statusLabel(),
                          style: const TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                )
              : LiquidGlassSurface(
                  key: const ValueKey('workout_locked_cta'),
                  borderRadius: 999,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 13,
                  ),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    showTempoToast(
                      context,
                      gate.statusLabel(),
                      showIcon: false,
                    );
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        gate.statusLabel(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [
                            FontFeature.tabularFigures(),
                          ],
                        ),
                      ),
                      const SizedBox(height: 7),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: gate.overallProgress,
                          minHeight: 3.5,
                          backgroundColor: c.divider,
                          valueColor: AlwaysStoppedAnimation<Color>(c.accent),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class _OverviewMetric extends StatelessWidget {
  final String label;
  final String value;

  const _OverviewMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: c.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: c.textTertiary,
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

/// Impeller-safe frosted 3-2-1-GO countdown overlay (never wraps BackdropFilter
/// inside FadeTransition/Opacity).
class _SessionCountdownOverlay extends StatefulWidget {
  final String workoutTitle;
  final VoidCallback onComplete;
  final VoidCallback onCancel;

  const _SessionCountdownOverlay({
    required this.workoutTitle,
    required this.onComplete,
    required this.onCancel,
  });

  @override
  State<_SessionCountdownOverlay> createState() =>
      _SessionCountdownOverlayState();
}

class _SessionCountdownOverlayState extends State<_SessionCountdownOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _beatController;
  late final AnimationController _revealController;

  /// Steps: 3 -> 2 -> 1 -> 0 ("GO")
  int _step = 3;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _revealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..forward();

    _beatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 920),
    )..addStatusListener(_onBeatStatus);

    HapticFeedback.mediumImpact();
    WorkoutSoundService.instance.playCountdownTick();
    _beatController.forward(from: 0);
  }

  void _onBeatStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted || _finished) return;

    if (_step > 1) {
      setState(() => _step--);
      HapticFeedback.mediumImpact();
      WorkoutSoundService.instance.playCountdownTick();
      _beatController.forward(from: 0);
    } else if (_step == 1) {
      setState(() => _step = 0); // "GO"
      HapticFeedback.heavyImpact();
      WorkoutSoundService.instance.playCountdownGo();
      _beatController.duration = const Duration(milliseconds: 520);
      _beatController.forward(from: 0);
    } else {
      _complete();
    }
  }

  Future<void> _complete() async {
    if (_finished) return;
    _finished = true;
    await _revealController.reverse();
    if (mounted) widget.onComplete();
  }

  Future<void> _cancel() async {
    if (_finished) return;
    _finished = true;
    HapticFeedback.selectionClick();
    WorkoutSoundService.instance.stop();
    await _revealController.reverse();
    if (mounted) widget.onCancel();
  }

  @override
  void dispose() {
    WorkoutSoundService.instance.stop();
    _beatController.dispose();
    _revealController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final allowBlur = TempoAppearanceService.instance.value.allowDynamicBlur;
    final label = _step > 0 ? '$_step' : 'GO';

    final body = AnimatedBuilder(
      animation: _revealController,
      builder: (context, child) {
        final v = Curves.easeOutCubic.transform(_revealController.value);
        final scrimAlpha = (c.isDark ? 0.78 : 0.84) * v;
        return Container(
          color: (c.isDark ? Colors.black : Colors.white)
              .withValues(alpha: scrimAlpha),
          child: Opacity(opacity: v, child: child),
        );
      },
      child: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),
            Text(
              'Get ready',
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                widget.workoutTitle,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                ),
              ),
            ),
            const SizedBox(height: 44),
            AnimatedBuilder(
              animation: _beatController,
              builder: (_, __) {
                final t = _beatController.value;
                final popCurve = Curves.easeOutBack.transform(
                  (t / 0.35).clamp(0.0, 1.0),
                );
                final exitT = ((t - 0.78) / 0.22).clamp(0.0, 1.0);
                final scale = _step > 0
                    ? (1.38 - 0.38 * popCurve) * (1.0 - 0.14 * exitT)
                    : (0.72 + 0.34 * popCurve);
                final opacity =
                    (t / 0.14).clamp(0.0, 1.0) * (1.0 - exitT * 0.85);
                final ringProgress = _step > 0 ? (1.0 - t) : 1.0;

                return SizedBox(
                  width: 196,
                  height: 196,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 196,
                        height: 196,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: c.accent.withValues(
                            alpha: c.isDark ? 0.08 : 0.06,
                          ),
                        ),
                      ),
                      CustomPaint(
                        size: const Size(184, 184),
                        painter: _CountdownRingPainter(
                          progress: ringProgress,
                          trackColor: c.divider,
                          activeColor: c.accent,
                        ),
                      ),
                      Opacity(
                        opacity: opacity.clamp(0.0, 1.0),
                        child: Transform.scale(
                          scale: scale.clamp(0.5, 1.6),
                          child: Text(
                            label,
                            style: TextStyle(
                              color: _step == 0 ? c.accent : c.textPrimary,
                              fontSize: _step > 0 ? 78 : 56,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -2.0,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const Spacer(flex: 3),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TempoLiquidButton(
                  primary: false,
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  onPressed: _cancel,
                  child: const Text('Cancel', style: TextStyle(fontSize: 14.5)),
                ),
                const SizedBox(width: 14),
                TempoBouncyButton(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 26),
                  onPressed: _complete,
                  child: const Text('Skip', style: TextStyle(fontSize: 14.5)),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );

    if (!allowBlur) return body;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: body,
      ),
    );
  }
}

class _CountdownRingPainter extends CustomPainter {
  final double progress;
  final Color trackColor;
  final Color activeColor;

  const _CountdownRingPainter({
    required this.progress,
    required this.trackColor,
    required this.activeColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const strokeWidth = 7.0;
    final radius = (size.width - strokeWidth) / 2;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );

    final sweep = 2 * math.pi * progress.clamp(0.0, 1.0);
    if (sweep > 0.001) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        sweep,
        false,
        Paint()
          ..color = activeColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CountdownRingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.activeColor != activeColor;
}
