import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/workout_model.dart';
import '../services/active_profile_provider.dart';
import '../services/journey_progress_service.dart';
import '../services/live_workout_service.dart';
import '../services/tempo_rust_db.dart';
import '../theme/app_colors.dart';
import '../widgets/liquid_glass_surface.dart';
import '../widgets/tempo_sliver_header.dart';
import 'exercise_detail_screen.dart';

class WorkoutDetailScreen extends StatefulWidget {
  final Workout workout;

  const WorkoutDetailScreen({super.key, required this.workout});

  @override
  State<WorkoutDetailScreen> createState() => _WorkoutDetailScreenState();
}

class _WorkoutDetailScreenState extends State<WorkoutDetailScreen> {
  final Set<int> _checkedExercises = {};
  Timer? _timer;
  int _accumulatedSeconds = 0;
  DateTime? _runStartedAt;
  bool _isRunning = false;
  bool _isCountingDown = false;
  bool _isSaving = false;

  int get _elapsedSeconds {
    if (_isRunning && _runStartedAt != null) {
      return _accumulatedSeconds +
          DateTime.now().difference(_runStartedAt!).inSeconds;
    }
    return _accumulatedSeconds;
  }

  @override
  void dispose() {
    _timer?.cancel();
    LiveWorkoutService.instance.stop();
    super.dispose();
  }

  String get _categoryLabel => (widget.workout.journeyName != null &&
          widget.workout.journeyName!.isNotEmpty)
      ? widget.workout.journeyName!
      : widget.workout.bodyFocus;

  void _syncLiveUpdate({required bool isPaused}) {
    LiveWorkoutService.instance.startOrUpdate(
      workoutTitle: widget.workout.title,
      category: _categoryLabel,
      elapsedSeconds: _elapsedSeconds,
      completedExercises: _checkedExercises.length,
      totalExercises: widget.workout.exerciseList.length,
      isPaused: isPaused,
    );
  }

  void _startTimerTicking() {
    _timer?.cancel();
    setState(() {
      _isCountingDown = false;
      _isRunning = true;
      _runStartedAt = DateTime.now();
    });
    _syncLiveUpdate(isPaused: false);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  void _toggleTimer() {
    if (_isCountingDown) return;
    HapticFeedback.selectionClick();
    if (_isRunning) {
      _timer?.cancel();
      final totalNow = _elapsedSeconds;
      setState(() {
        _accumulatedSeconds = totalNow;
        _runStartedAt = null;
        _isRunning = false;
      });
      _syncLiveUpdate(isPaused: true);
    } else if (_elapsedSeconds == 0) {
      // Request notification permission quietly (non-blocking) for HyperIsland Live Updates
      LiveWorkoutService.instance.ensureNotificationPermission();
      // Fresh start -> launch the 3-2-1 countdown animation!
      setState(() => _isCountingDown = true);
    } else {
      // Resume directly when paused mid-session
      _startTimerTicking();
    }
  }

  void _resetTimer() {
    HapticFeedback.selectionClick();
    _timer?.cancel();
    LiveWorkoutService.instance.stop();
    setState(() {
      _isRunning = false;
      _accumulatedSeconds = 0;
      _runStartedAt = null;
    });
  }

  String _formatTime(int sec) {
    final m = (sec ~/ 60).toString().padLeft(2, '0');
    final s = (sec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  int _estimateCalories() {
    if (widget.workout.exerciseList.isEmpty) {
      return ((_elapsedSeconds / 60.0) * 7).round().clamp(30, 800);
    }
    double total = 0;
    for (int i = 0; i < widget.workout.exerciseList.length; i++) {
      final ex = widget.workout.exerciseList[i];
      total += ex.getCaloriesBurned(sets: 3, reps: 10);
    }
    return total.round().clamp(45, 950);
  }

  Future<void> _completeWorkout() async {
    final profileProvider = context.read<ActiveProfileProvider>();
    final profileId = profileProvider.activeProfileId;
    if (profileId == null) return;

    _timer?.cancel();
    LiveWorkoutService.instance.stop();
    final totalElapsed = _elapsedSeconds;
    setState(() {
      _accumulatedSeconds = totalElapsed;
      _runStartedAt = null;
      _isRunning = false;
      _isCountingDown = false;
      _isSaving = true;
    });

    try {
      final expectedSec = widget.workout.exerciseList
          .fold<int>(0, (sum, e) => sum + e.duration);
      final actualSec = _elapsedSeconds > 0
          ? _elapsedSeconds
          : (expectedSec > 0 ? expectedSec : 1200);
      final calories = _estimateCalories();

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
      await showCupertinoDialog<void>(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('Workout Completed'),
          content: Text(
            '${widget.workout.title}\n\nDuration: ${_formatTime(actualSec)}\nEstimated Burn: $calories kcal',
          ),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving workout: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final exercises = widget.workout.exerciseList;
    final categoryText = (widget.workout.journeyName != null &&
            widget.workout.journeyName!.isNotEmpty)
        ? widget.workout.journeyName!
        : widget.workout.bodyFocus;

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
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                      sliver: SliverList.list(
                        children: [
                          // 1. Minimal Overview & Session Timer Card
                          AppleCard(
                            borderRadius: 24,
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Minimal category & workout name/level indicators
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        categoryText,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: c.textSecondary,
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2.5,
                                      ),
                                      decoration: BoxDecoration(
                                        border: Border.all(color: c.cardBorder),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        widget.workout.level,
                                        style: TextStyle(
                                          color: c.textSecondary,
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                // Clean hairline-separated summary metrics
                                Row(
                                  children: [
                                    Expanded(
                                      child: _OverviewMetric(
                                        label: 'Duration',
                                        value: widget.workout.duration,
                                      ),
                                    ),
                                    Container(
                                      width: 1,
                                      height: 28,
                                      color: c.divider,
                                    ),
                                    Expanded(
                                      child: _OverviewMetric(
                                        label: 'Exercises',
                                        value: '${exercises.length}',
                                      ),
                                    ),
                                    Container(
                                      width: 1,
                                      height: 28,
                                      color: c.divider,
                                    ),
                                    Expanded(
                                      child: _OverviewMetric(
                                        label: 'Est. burn',
                                        value: '${_estimateCalories()} kcal',
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 18),
                                Divider(height: 1, color: c.divider),
                                const SizedBox(height: 16),

                                // Session Timer Row
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              AnimatedContainer(
                                                duration: const Duration(
                                                  milliseconds: 250,
                                                ),
                                                width: 7,
                                                height: 7,
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  color: _isRunning
                                                      ? c.accent
                                                      : c.textTertiary
                                                          .withValues(
                                                              alpha: 0.45),
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                _isRunning
                                                    ? 'In progress'
                                                    : 'Session timer',
                                                style: TextStyle(
                                                  color: _isRunning
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
                                            _formatTime(_elapsedSeconds),
                                            style: TextStyle(
                                              color: c.textPrimary,
                                              fontSize: 34,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: -1.0,
                                              fontFeatures: const [
                                                FontFeature.tabularFigures(),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (!_isRunning && _elapsedSeconds > 0) ...[
                                      GestureDetector(
                                        onTap: _resetTimer,
                                        child: Container(
                                          width: 40,
                                          height: 40,
                                          margin:
                                              const EdgeInsets.only(right: 8),
                                          decoration: BoxDecoration(
                                            color: c.searchBg,
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(
                                            CupertinoIcons.refresh,
                                            size: 17,
                                            color: c.textSecondary,
                                          ),
                                        ),
                                      ),
                                    ],
                                    _SessionActionButton(
                                      isRunning: _isRunning,
                                      hasStarted: _elapsedSeconds > 0,
                                      onTap: _toggleTimer,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),

                          // 2. Exercises Section Header
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              children: [
                                Text(
                                  'Exercises',
                                  style: TextStyle(
                                    color: c.textPrimary,
                                    fontSize: 19,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  '${_checkedExercises.length}/${exercises.length} done',
                                  style: TextStyle(
                                    color: c.textTertiary,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w500,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // 3. Clean Grouped Exercises Card
                          AppleCard(
                            borderRadius: 24,
                            padding: EdgeInsets.zero,
                            child: Column(
                              children: List.generate(exercises.length, (idx) {
                                final ex = exercises[idx];
                                final checked = _checkedExercises.contains(idx);
                                final isLast = idx == exercises.length - 1;
                                return Column(
                                  children: [
                                    InkWell(
                                      onTap: () async {
                                        HapticFeedback.selectionClick();
                                        final logged =
                                            await Navigator.push<bool>(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                ExerciseDetailScreen(
                                              exercise: ex,
                                              workout: widget.workout,
                                            ),
                                          ),
                                        );
                                        if (logged == true && mounted) {
                                          setState(
                                            () => _checkedExercises.add(idx),
                                          );
                                          if (_isRunning || _elapsedSeconds > 0) {
                                            _syncLiveUpdate(
                                              isPaused: !_isRunning,
                                            );
                                          }
                                        }
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 15,
                                        ),
                                        child: Row(
                                          children: [
                                            GestureDetector(
                                              behavior: HitTestBehavior.opaque,
                                              onTap: () {
                                                HapticFeedback.selectionClick();
                                                setState(() {
                                                  if (checked) {
                                                    _checkedExercises
                                                        .remove(idx);
                                                  } else {
                                                    _checkedExercises.add(idx);
                                                  }
                                                });
                                                if (_isRunning ||
                                                    _elapsedSeconds > 0) {
                                                  _syncLiveUpdate(
                                                    isPaused: !_isRunning,
                                                  );
                                                }
                                              },
                                              child: Padding(
                                                padding: const EdgeInsets.all(4),
                                                child: AnimatedContainer(
                                                  duration: const Duration(
                                                    milliseconds: 200,
                                                  ),
                                                  curve: Curves.easeOutCubic,
                                                  width: 24,
                                                  height: 24,
                                                  decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    color: checked
                                                        ? c.textPrimary
                                                        : Colors.transparent,
                                                    border: Border.all(
                                                      color: checked
                                                          ? c.textPrimary
                                                          : c.textTertiary
                                                              .withValues(
                                                                  alpha: 0.6),
                                                      width: 1.6,
                                                    ),
                                                  ),
                                                  child: checked
                                                      ? Icon(
                                                          CupertinoIcons
                                                              .checkmark_alt,
                                                          size: 14,
                                                          color: c.isDark
                                                              ? Colors.black
                                                              : Colors.white,
                                                        )
                                                      : null,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    ex.name,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      color: checked
                                                          ? c.textSecondary
                                                          : c.textPrimary,
                                                      fontSize: 15.5,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      decoration: checked
                                                          ? TextDecoration
                                                              .lineThrough
                                                          : null,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    ex.description,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      color: c.textSecondary,
                                                      fontSize: 12.5,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Icon(
                                              CupertinoIcons.play_circle,
                                              color: c.textTertiary,
                                              size: 22,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    if (!isLast)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(left: 56),
                                        child: Divider(
                                          height: 1,
                                          color: c.divider,
                                        ),
                                      ),
                                  ],
                                );
                              }),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Unified Signature Primary Button
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: c.accent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: _isSaving ? null : _completeWorkout,
                      child: _isSaving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              'Complete Workout (${_checkedExercises.length}/${exercises.length})',
                              style: const TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),

          // Full-screen iOS 27 Frosted 3 · 2 · 1 · GO Countdown Overlay
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
            fontSize: 15.5,
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

class _SessionActionButton extends StatefulWidget {
  final bool isRunning;
  final bool hasStarted;
  final VoidCallback onTap;

  const _SessionActionButton({
    required this.isRunning,
    required this.hasStarted,
    required this.onTap,
  });

  @override
  State<_SessionActionButton> createState() => _SessionActionButtonState();
}

class _SessionActionButtonState extends State<_SessionActionButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final bg = widget.isRunning ? c.searchBg : c.accent;
    final fg = widget.isRunning ? c.textPrimary : Colors.white;
    final label = widget.isRunning
        ? 'Pause'
        : (widget.hasStarted ? 'Resume' : 'Start');

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(99),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.isRunning
                    ? CupertinoIcons.pause_fill
                    : CupertinoIcons.play_fill,
                color: fg,
                size: 15,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Frosted-glass Apple Fitness-inspired 3 · 2 · 1 · GO countdown overlay with
/// radial sweep ring, spring-pop numerals, and progressive haptics.
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
  late final AnimationController _fadeController;

  /// Steps: 3 -> 2 -> 1 -> 0 ("GO")
  int _step = 3;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..forward();

    _beatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 920),
    )..addStatusListener(_onBeatStatus);

    HapticFeedback.mediumImpact();
    _beatController.forward(from: 0);
  }

  void _onBeatStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted || _finished) return;

    if (_step > 1) {
      setState(() => _step--);
      HapticFeedback.mediumImpact();
      _beatController.forward(from: 0);
    } else if (_step == 1) {
      setState(() => _step = 0); // "GO"
      HapticFeedback.heavyImpact();
      _beatController.duration = const Duration(milliseconds: 520);
      _beatController.forward(from: 0);
    } else {
      _complete();
    }
  }

  Future<void> _complete() async {
    if (_finished) return;
    _finished = true;
    await _fadeController.reverse();
    if (mounted) widget.onComplete();
  }

  Future<void> _cancel() async {
    if (_finished) return;
    _finished = true;
    HapticFeedback.selectionClick();
    await _fadeController.reverse();
    if (mounted) widget.onCancel();
  }

  @override
  void dispose() {
    _beatController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final label = _step > 0 ? '$_step' : 'GO';

    return FadeTransition(
      opacity: CurvedAnimation(
        parent: _fadeController,
        curve: Curves.easeOutCubic,
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          color: c.isDark
              ? Colors.black.withValues(alpha: 0.72)
              : Colors.white.withValues(alpha: 0.78),
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
                // Animated sweeping radial ring + spring pop numeral
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
                    final opacity = (t / 0.14).clamp(0.0, 1.0) *
                        (1.0 - exitT * 0.85);
                    final ringProgress = _step > 0 ? (1.0 - t) : 1.0;

                    return SizedBox(
                      width: 196,
                      height: 196,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Subtle ambient glow ring
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
                    TextButton(
                      onPressed: _cancel,
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          color: c.textSecondary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 24),
                    TextButton(
                      onPressed: _complete,
                      child: Text(
                        'Skip',
                        style: TextStyle(
                          color: c.accent,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
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
