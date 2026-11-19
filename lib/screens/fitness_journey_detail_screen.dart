import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../data/fitness_journey_workouts.dart';
import '../models/workout_model.dart';
import '../services/active_profile_provider.dart';
import '../services/journey_progress_service.dart';
import '../services/tempo_rust_db.dart';
import '../theme/app_colors.dart';
import '../widgets/liquid_glass_surface.dart';
import '../widgets/tempo_sliver_header.dart';
import 'workout_detail_screen.dart';

class FitnessJourneyDetailScreen extends StatefulWidget {
  final String journeyId;
  final String journeyName;
  final String journeySubtitle;
  final String thumbnailAsset;

  const FitnessJourneyDetailScreen({
    super.key,
    required this.journeyId,
    required this.journeyName,
    this.journeySubtitle = '',
    this.thumbnailAsset =
        'assets/thumbnails/Journeys/journey_weight_loss_thumb.png',
  });

  @override
  State<FitnessJourneyDetailScreen> createState() =>
      _FitnessJourneyDetailScreenState();
}

class _FitnessJourneyDetailScreenState extends State<FitnessJourneyDetailScreen>
    with SingleTickerProviderStateMixin {
  JourneyProgressSnapshot? _snapshot;
  Set<String> _completedIds = {};
  bool _loading = true;
  late final AnimationController _entranceController;

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

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _load();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final pid = context.read<ActiveProfileProvider>().activeProfileId;
    if (pid == null) return;

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
    _entranceController.forward(from: 0);
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

    final nextWorkout = _workouts.firstWhere(
      (w) => w.id == snapshot.nextWorkoutId,
      orElse: () => _workouts.first,
    );
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WorkoutDetailScreen(workout: nextWorkout),
      ),
    );
    if (mounted) _load();
  }

  Widget _stagger(int index, Widget child) {
    final start = (index * 0.14).clamp(0.0, 0.5);
    final end = (start + 0.5).clamp(0.0, 1.0);
    final anim = CurvedAnimation(
      parent: _entranceController,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: anim,
      builder: (_, c) => Opacity(
        opacity: anim.value,
        child: Transform.translate(
          offset: Offset(0, 14 * (1 - anim.value)),
          child: c,
        ),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final workouts = _workouts;
    final pct = (_snapshot?.progressPercent ?? 0).clamp(0.0, 100.0);
    final completedCount = _snapshot?.completedWorkoutsCount ?? 0;
    final totalMins = _totalEstimatedMinutes;
    final nextId = _snapshot?.nextWorkoutId;

    return Scaffold(
      backgroundColor: c.scaffold,
      body: RefreshIndicator(
        color: c.accent,
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
              padding: const EdgeInsets.fromLTRB(20, 2, 20, 40),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.journeySubtitle.isNotEmpty) ...[
                      Text(
                        widget.journeySubtitle,
                        style: TextStyle(
                          color: c.textSecondary,
                          fontSize: 14.5,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 18),
                    ],

                    // 1. Clean iOS 27 Journey Progress Card
                    _stagger(
                      0,
                      AppleCard(
                        borderRadius: 24,
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Progress',
                                        style: TextStyle(
                                          color: c.textSecondary,
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      TweenAnimationBuilder<double>(
                                        tween:
                                            Tween<double>(begin: 0, end: pct),
                                        duration:
                                            const Duration(milliseconds: 620),
                                        curve: Curves.easeOutCubic,
                                        builder: (_, val, __) => Text(
                                          '${val.round()}%',
                                          style: TextStyle(
                                            color: c.textPrimary,
                                            fontSize: 32,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: -1.0,
                                            fontFeatures: const [
                                              FontFeature.tabularFigures(),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _StatItem(
                                      label: 'Completed',
                                      value: '$completedCount/${workouts.length}',
                                    ),
                                    if (totalMins > 0) ...[
                                      Container(
                                        width: 1,
                                        height: 28,
                                        margin: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                        ),
                                        color: c.divider,
                                      ),
                                      _StatItem(
                                        label: 'Duration',
                                        value: '$totalMins min',
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(99),
                              child: TweenAnimationBuilder<double>(
                                tween: Tween<double>(
                                  begin: 0,
                                  end: (pct / 100).clamp(0.0, 1.0),
                                ),
                                duration: const Duration(milliseconds: 620),
                                curve: Curves.easeOutCubic,
                                builder: (_, v, __) => LinearProgressIndicator(
                                  value: v,
                                  minHeight: 5,
                                  backgroundColor: c.divider,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    c.textPrimary,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            _TactilePrimaryButton(
                              label: (_snapshot?.hasStarted ?? false)
                                  ? 'Continue Journey'
                                  : 'Start Journey',
                              enabled: !_loading,
                              onTap: _startOrSelectJourney,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // 2. Section Header
                    _stagger(
                      1,
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          children: [
                            Text(
                              'Workouts',
                              style: TextStyle(
                                color: c.textPrimary,
                                fontSize: 19,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '${workouts.length} ${workouts.length == 1 ? 'session' : 'sessions'}',
                              style: TextStyle(
                                color: c.textTertiary,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // 3. Clean Grouped Workouts Card (matching Profile / Progress rows)
                    _stagger(
                      2,
                      AppleCard(
                        borderRadius: 24,
                        padding: EdgeInsets.zero,
                        child: Column(
                          children: List.generate(workouts.length, (idx) {
                            final w = workouts[idx];
                            final done = _completedIds.contains(w.id);
                            final isNext = (_snapshot?.hasStarted ?? false) &&
                                nextId == w.id &&
                                !done;
                            final isLast = idx == workouts.length - 1;

                            return Column(
                              children: [
                                _JourneyWorkoutRow(
                                  index: idx + 1,
                                  workout: w,
                                  isCompleted: done,
                                  isNext: isNext,
                                  onTap: () async {
                                    HapticFeedback.selectionClick();
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            WorkoutDetailScreen(workout: w),
                                      ),
                                    );
                                    if (mounted) _load();
                                  },
                                ),
                                if (!isLast)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 62),
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
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;

  const _StatItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          label,
          style: TextStyle(
            color: c.textTertiary,
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: c.textPrimary,
            fontSize: 15.5,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _TactilePrimaryButton extends StatefulWidget {
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  const _TactilePrimaryButton({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  @override
  State<_TactilePrimaryButton> createState() => _TactilePrimaryButtonState();
}

class _TactilePrimaryButtonState extends State<_TactilePrimaryButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return GestureDetector(
      onTapDown: widget.enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: widget.enabled
          ? (_) {
              setState(() => _pressed = false);
              widget.onTap();
            }
          : null,
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: Container(
          height: 50,
          decoration: BoxDecoration(
            color: widget.enabled
                ? c.accent
                : c.accent.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(16),
          ),
          alignment: Alignment.center,
          child: Text(
            widget.label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15.5,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.1,
            ),
          ),
        ),
      ),
    );
  }
}

class _JourneyWorkoutRow extends StatelessWidget {
  final int index;
  final Workout workout;
  final bool isCompleted;
  final bool isNext;
  final VoidCallback onTap;

  const _JourneyWorkoutRow({
    required this.index,
    required this.workout,
    required this.isCompleted,
    required this.isNext,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final numStr = index.toString().padLeft(2, '0');

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Center(
                child: isCompleted
                    ? Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: c.textPrimary,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          CupertinoIcons.checkmark_alt,
                          color: c.isDark ? Colors.black : Colors.white,
                          size: 13,
                        ),
                      )
                    : Text(
                        numStr,
                        style: TextStyle(
                          color: isNext ? c.textPrimary : c.textTertiary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
              ),
            ),
            Container(
              width: 1,
              height: 26,
              margin: const EdgeInsets.symmetric(horizontal: 14),
              color: c.divider,
            ),
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
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      if (isNext) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: c.textPrimary.withValues(alpha: 0.28),
                            ),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            'Next',
                            style: TextStyle(
                              color: c.textPrimary,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${workout.duration} · ${workout.exerciseList.length} exercises · ${workout.level}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.textSecondary,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              CupertinoIcons.chevron_right,
              size: 15,
              color: c.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}
