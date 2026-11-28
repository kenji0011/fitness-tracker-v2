import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../data/fitness_journey_workouts.dart';
import '../models/workout_model.dart';
import '../services/active_profile_provider.dart';
import '../services/animation_speed_service.dart';
import '../services/appearance_service.dart';
import '../services/journey_progress_service.dart';
import '../services/tempo_rust_db.dart';
import '../theme/app_colors.dart';
import '../widgets/liquid_glass_surface.dart';
import '../widgets/tempo_morph_route.dart';
import '../widgets/tempo_sliver_header.dart';
import 'workout_detail_screen.dart';

class FitnessJourneyDetailScreen extends StatefulWidget {
  final String journeyId;
  final String journeyName;
  final String journeySubtitle;
  final String thumbnailAsset;
  final Color? accentColor;

  const FitnessJourneyDetailScreen({
    super.key,
    required this.journeyId,
    required this.journeyName,
    this.journeySubtitle = '',
    this.thumbnailAsset =
        'assets/thumbnails/Journeys/journey_weight_loss_thumb.png',
    this.accentColor,
  });

  @override
  State<FitnessJourneyDetailScreen> createState() =>
      _FitnessJourneyDetailScreenState();
}

class _FitnessJourneyDetailScreenState
    extends State<FitnessJourneyDetailScreen> {
  final GlobalKey _ctaButtonKey = GlobalKey();

  JourneyProgressSnapshot? _snapshot;
  Set<String> _completedIds = {};
  bool _loading = true;

  List<Workout> get _workouts => getJourneyWorkouts(widget.journeyId);

  int get _totalEstimatedMinutes {
    int total = 0;
    for (final w in _workouts) {
      final match = RegExp(r'\d+').firstMatch(w.duration);
      if (match != null) {
        total += int.tryParse(match.group(0) ?? '0') ?? 0;
      }
    }
    return total;
  }

  int get _totalExerciseCount =>
      _workouts.fold<int>(0, (sum, w) => sum + w.exerciseList.length);

  Color _resolveAccent(AppColors c) {
    if (widget.accentColor != null) return widget.accentColor!;
    return switch (widget.journeyId) {
      weightLossJourneyId => c.accent,
      cardioJourneyId => c.moveRed,
      strengthPowerJourneyId => const Color(0xFF7A6FF0),
      muscularEnduranceJourneyId => c.exerciseGreen,
      healthWellnessJourneyId => c.bodyCyan,
      _ => c.accent,
    };
  }

  IconData _resolveJourneyIcon() {
    return switch (widget.journeyId) {
      weightLossJourneyId => CupertinoIcons.flame_fill,
      cardioJourneyId => CupertinoIcons.heart_fill,
      strengthPowerJourneyId => CupertinoIcons.bolt_fill,
      muscularEnduranceJourneyId => CupertinoIcons.timer,
      healthWellnessJourneyId => CupertinoIcons.sparkles,
      _ => CupertinoIcons.flame_fill,
    };
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final pid = context.read<ActiveProfileProvider>().activeProfileId;
    if (pid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    final snapshot = await JourneyProgressService.syncJourneyProgressForProfile(
      profileId: pid,
      journeyId: widget.journeyId,
      journeyName: widget.journeyName,
      isSelected: false,
    );
    final completed =
        await TempoRustDb.instance.getCompletedWorkouts(pid, limit: 300);

    if (!mounted) return;
    setState(() {
      _snapshot = snapshot;
      _completedIds = completed
          .where((c) => !c.isCheated)
          .map((c) => c.workoutId)
          .toSet();
      _loading = false;
    });
  }

  Future<void> _startOrSelectJourney() async {
    HapticFeedback.mediumImpact();
    final pid = context.read<ActiveProfileProvider>().activeProfileId;
    if (pid == null) return;

    final snapshot = await JourneyProgressService.syncJourneyProgressForProfile(
      profileId: pid,
      journeyId: widget.journeyId,
      journeyName: widget.journeyName,
      isSelected: true,
      markStarted: true,
    );
    if (!mounted) return;
    context.read<ActiveProfileProvider>().notifyDataChanged();
    setState(() => _snapshot = snapshot);

    if (_workouts.isEmpty) return;
    final nextWorkout = _workouts.firstWhere(
      (w) => w.id == snapshot.nextWorkoutId,
      orElse: () => _workouts.first,
    );
    await pushTempoMorphRoute<void>(
      context: context,
      sourceKey: _ctaButtonKey,
      sourceBorderRadius: 999,
      builder: (_) => WorkoutDetailScreen(workout: nextWorkout),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final accent = _resolveAccent(c);
    final journeyIcon = _resolveJourneyIcon();
    final workouts = _workouts;
    final pct = (_snapshot?.progressPercent ?? 0).clamp(0.0, 100.0);
    final completedCount = _snapshot?.completedWorkoutsCount ?? 0;
    final totalMins = _totalEstimatedMinutes;
    final totalExercises = _totalExerciseCount;
    final nextId = _snapshot?.nextWorkoutId;
    final hasStarted = _snapshot?.hasStarted ?? false;
    final isComplete =
        workouts.isNotEmpty && completedCount >= workouts.length;

    final reduced = TempoAppearanceService.instance.reduceAnimation ||
        MediaQuery.disableAnimationsOf(context);
    final progressDur = reduced
        ? Duration.zero
        : TempoAnimationSpeedService.instance.scale(
            const Duration(milliseconds: 520),
          );

    final statusLabel = isComplete
        ? 'Journey completed'
        : (hasStarted ? 'Active journey' : 'Ready to start');

    final ctaLabel = isComplete
        ? 'Repeat Next Session'
        : (hasStarted ? 'Continue Journey' : 'Start Journey');

    return Scaffold(
      backgroundColor: c.scaffold,
      body: RefreshIndicator(
        color: accent,
        edgeOffset: MediaQuery.paddingOf(context).top + 56,
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            TempoSliverHeader(
              title: widget.journeyName,
              showBackButton: true,
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 42),
              sliver: SliverList.list(
                children: [
                  // 1. Liquid Glass Journey Hero Deck (renders populated on Frame 0)
                  LiquidGlassSurface(
                    borderRadius: 28,
                    blurEnabled: false,
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: accent.withValues(
                                  alpha: c.isDark ? 0.22 : 0.14,
                                ),
                              ),
                              child: Icon(
                                journeyIcon,
                                color: accent,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 9,
                                      vertical: 3.5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: accent.withValues(
                                        alpha: c.isDark ? 0.20 : 0.12,
                                      ),
                                      borderRadius: BorderRadius.circular(99),
                                    ),
                                    child: Text(
                                      statusLabel,
                                      style: TextStyle(
                                        color: accent,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  if (widget.journeySubtitle.isNotEmpty) ...[
                                    const SizedBox(height: 5),
                                    Text(
                                      widget.journeySubtitle,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: c.textSecondary,
                                        fontSize: 13,
                                        height: 1.35,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Animated Circular Progress Ring
                            TweenAnimationBuilder<double>(
                              tween: Tween<double>(
                                begin: 0,
                                end: (pct / 100.0).clamp(0.0, 1.0),
                              ),
                              duration: progressDur,
                              curve: Curves.easeOutCubic,
                              builder: (_, v, __) => SizedBox(
                                width: 62,
                                height: 62,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    CustomPaint(
                                      size: const Size.square(62),
                                      painter: _JourneyProgressRingPainter(
                                        progress: v,
                                        trackColor: c.divider,
                                        activeColor: accent,
                                      ),
                                    ),
                                    Text(
                                      '${(v * 100).round()}%',
                                      style: TextStyle(
                                        color: c.textPrimary,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -0.4,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Recessed Metrics Trio Bar
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: c.isDark
                                ? Colors.white.withValues(alpha: 0.055)
                                : Colors.black.withValues(alpha: 0.035),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: _JourneyStatCell(
                                  label: 'Completed',
                                  value: '$completedCount/${workouts.length}',
                                ),
                              ),
                              Container(width: 1, height: 26, color: c.divider),
                              Expanded(
                                child: _JourneyStatCell(
                                  label: 'Duration',
                                  value: '$totalMins min',
                                ),
                              ),
                              Container(width: 1, height: 26, color: c.divider),
                              Expanded(
                                child: _JourneyStatCell(
                                  label: 'Exercises',
                                  value: '$totalExercises',
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Smooth Progress Bar
                        ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: TweenAnimationBuilder<double>(
                            tween: Tween<double>(
                              begin: 0,
                              end: (pct / 100.0).clamp(0.0, 1.0),
                            ),
                            duration: progressDur,
                            curve: Curves.easeOutCubic,
                            builder: (_, v, __) => LinearProgressIndicator(
                              value: v,
                              minHeight: 5.5,
                              backgroundColor: c.divider,
                              valueColor: AlwaysStoppedAnimation<Color>(accent),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Morph-Anchored Bouncy Primary CTA
                        KeyedSubtree(
                          key: _ctaButtonKey,
                          child: TempoBouncyButton(
                            height: 52,
                            backgroundColor: accent,
                            onPressed: _loading ? null : _startOrSelectJourney,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  CupertinoIcons.play_fill,
                                  color: Colors.white,
                                  size: 15,
                                ),
                                const SizedBox(width: 8),
                                Text(ctaLabel),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 2. Workouts Section Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                    child: Row(
                      children: [
                        Text(
                          'Workouts',
                          style: TextStyle(
                            color: c.textPrimary,
                            fontSize: 18.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: accent.withValues(
                              alpha: c.isDark ? 0.18 : 0.11,
                            ),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            '${workouts.length} ${workouts.length == 1 ? 'session' : 'sessions'}',
                            style: TextStyle(
                              color: accent,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 3. Individual Liquid Glass Workout Session Cards (1:1 morph)
                  ...List.generate(workouts.length, (idx) {
                    final w = workouts[idx];
                    final done = _completedIds.contains(w.id);
                    final isNext =
                        (hasStarted && nextId == w.id && !done) ||
                        (!hasStarted && idx == 0 && !done);

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Builder(
                        builder: (cardCtx) => _JourneyWorkoutCard(
                          index: idx + 1,
                          workout: w,
                          accent: accent,
                          isCompleted: done,
                          isNext: isNext,
                          onTap: () async {
                            HapticFeedback.selectionClick();
                            await pushTempoMorphRoute<void>(
                              context: context,
                              sourceContext: cardCtx,
                              sourceBorderRadius: 24,
                              builder: (_) => WorkoutDetailScreen(workout: w),
                            );
                            if (mounted) _load();
                          },
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _JourneyStatCell extends StatelessWidget {
  final String label;
  final String value;

  const _JourneyStatCell({
    required this.label,
    required this.value,
  });

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

class _JourneyWorkoutCard extends StatelessWidget {
  final int index;
  final Workout workout;
  final Color accent;
  final bool isCompleted;
  final bool isNext;
  final VoidCallback onTap;

  const _JourneyWorkoutCard({
    required this.index,
    required this.workout,
    required this.accent,
    required this.isCompleted,
    required this.isNext,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final numStr = index.toString().padLeft(2, '0');

    return LiquidGlassSurface(
      borderRadius: 24,
      blurEnabled: false,
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
      onTap: onTap,
      child: Row(
        children: [
          // Circular Step / Checkmark Medallion
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isCompleted
                  ? accent
                  : (isNext
                      ? accent.withValues(alpha: c.isDark ? 0.22 : 0.14)
                      : (c.isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.black.withValues(alpha: 0.05))),
              border: isNext && !isCompleted
                  ? Border.all(color: accent.withValues(alpha: 0.50), width: 1.2)
                  : null,
            ),
            child: Center(
              child: isCompleted
                  ? const Icon(
                      CupertinoIcons.checkmark_alt,
                      color: Colors.white,
                      size: 18,
                    )
                  : Text(
                      numStr,
                      style: TextStyle(
                        color: isNext ? accent : c.textSecondary,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 13),

          // Title & Clean Meta Tags (zero bullets)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        workout.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.25,
                        ),
                      ),
                    ),
                    if (isNext || isCompleted) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7.5,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: accent.withValues(
                            alpha: c.isDark ? 0.22 : 0.13,
                          ),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          isCompleted ? 'Done' : 'Up Next',
                          style: TextStyle(
                            color: accent,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _SessionTag(label: workout.duration, c: c),
                    _SessionTag(
                      label: '${workout.exerciseList.length} exercises',
                      c: c,
                    ),
                    _SessionTag(label: workout.level, c: c),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),

          // Circular Liquid Glass Action Indicator
          TempoGlassCircleButton(
            size: 36,
            enableBlur: false,
            tooltip: 'Open ${workout.title}',
            icon: Icon(
              isNext ? CupertinoIcons.play_fill : CupertinoIcons.chevron_right,
              size: isNext ? 14 : 15,
              color: isNext ? accent : c.textSecondary,
            ),
            onPressed: onTap,
          ),
        ],
      ),
    );
  }
}

class _SessionTag extends StatelessWidget {
  final String label;
  final AppColors c;

  const _SessionTag({required this.label, required this.c});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.isDark
            ? Colors.white.withValues(alpha: 0.065)
            : Colors.black.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: c.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _JourneyProgressRingPainter extends CustomPainter {
  final double progress;
  final Color trackColor;
  final Color activeColor;

  const _JourneyProgressRingPainter({
    required this.progress,
    required this.trackColor,
    required this.activeColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.5, size.height * 0.5);
    const stroke = 5.5;
    final radius = (size.width - stroke) * 0.5;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
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
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _JourneyProgressRingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.activeColor != activeColor;
}
