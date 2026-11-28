import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:jiggicons/jiggicons.dart';

import '../theme/app_colors.dart';
import '../widgets/ios_stretch_sheet.dart';
import '../widgets/liquid_glass_surface.dart';
import '../widgets/tempo_jigg_icon.dart';
import '../widgets/tempo_startup_splash.dart';
import 'tempo_rust_db.dart';

/// Daily trackable health goals supported by Tempo's goal completion engine.
enum DailyGoalKind {
  calories,
  steps,
  minutes,
  water,
  sleep,
}

/// Snapshot of a newly reached daily goal ready for celebration UI.
@immutable
class GoalCompletionEvent {
  final DailyGoalKind kind;
  final double achieved;
  final double target;

  const GoalCompletionEvent({
    required this.kind,
    required this.achieved,
    required this.target,
  });

  int get percent =>
      target <= 0 ? 100 : ((achieved / target) * 100).round().clamp(100, 999);

  String get metricLabel => switch (kind) {
        DailyGoalKind.calories => 'Calories',
        DailyGoalKind.steps => 'Steps',
        DailyGoalKind.minutes => 'Activity',
        DailyGoalKind.water => 'Hydration',
        DailyGoalKind.sleep => 'Sleep',
      };

  String get headline => '$metricLabel Goal Reached';

  String get achievedFormatted {
    final fmt = NumberFormat('#,###');
    return switch (kind) {
      DailyGoalKind.calories => '${fmt.format(achieved.round())} kcal',
      DailyGoalKind.steps => '${fmt.format(achieved.round())} steps',
      DailyGoalKind.minutes => '${achieved.round()} min',
      DailyGoalKind.water => '${fmt.format(achieved.round())} ml',
      DailyGoalKind.sleep => '${achieved.toStringAsFixed(1)} hrs',
    };
  }

  String get targetFormatted {
    final fmt = NumberFormat('#,###');
    return switch (kind) {
      DailyGoalKind.calories => '${fmt.format(target.round())} kcal',
      DailyGoalKind.steps => '${fmt.format(target.round())} steps',
      DailyGoalKind.minutes => '${target.round()} min',
      DailyGoalKind.water => '${fmt.format(target.round())} ml',
      DailyGoalKind.sleep => '${target.toStringAsFixed(1)} hrs',
    };
  }

  IconData get icon => switch (kind) {
        DailyGoalKind.calories => CupertinoIcons.flame_fill,
        DailyGoalKind.steps => CupertinoIcons.bolt_fill,
        DailyGoalKind.minutes => CupertinoIcons.timer,
        DailyGoalKind.water => CupertinoIcons.drop_fill,
        DailyGoalKind.sleep => CupertinoIcons.moon_fill,
      };

  Color accentColor(AppColors c) => switch (kind) {
        DailyGoalKind.calories => const Color(0xFFF36432),
        DailyGoalKind.steps => const Color(0xFF93DC2A),
        DailyGoalKind.minutes => const Color(0xFF56B7FF),
        DailyGoalKind.water => c.bodyCyan,
        DailyGoalKind.sleep => c.sleepPurple,
      };
}

/// Evaluates all 5 daily goals (Calories, Steps, Activity, Hydration, Sleep)
/// against today's totals, deduplicates celebrations once per goal per day per
/// profile in SQLite, and presents a unified Liquid Glass completion sheet.
class GoalCompletionService {
  static final GoalCompletionService instance = GoalCompletionService._();

  GoalCompletionService._();

  bool _isShowing = false;

  static String _seenKey(String dateKey, DailyGoalKind kind, String profileId) =>
      'goal_hit_${dateKey}_${kind.name}_$profileId';

  static bool _isRunningInTest() {
    return WidgetsBinding.instance.runtimeType.toString().contains('Test');
  }

  /// Evaluates today's metrics for [profileId], marks newly reached goals as
  /// celebrated for today, and returns the list of newly hit goals.
  Future<List<GoalCompletionEvent>> evaluateNewCompletions({
    required String profileId,
    String? dateKeyOverride,
  }) async {
    if (profileId.isEmpty) return const [];
    final db = TempoRustDb.instance;
    final todayKey = dateKeyOverride ?? TempoRustDb.todayKey();

    final results = await Future.wait([
      db.getDashboardSummary(profileId),
      db.getBodyMetricHistory(profileId, 'water', limit: 200),
      db.getSetting('water_goal_ml_$profileId'),
      db.getSetting('sleep_goal_hrs_$profileId'),
    ]);

    final summary = results[0] as dynamic;
    final profile = summary.profile;
    final today = summary.today;
    final sleepPts = summary.sleepHistory as List<dynamic>;
    final waterPts = results[1] as List<dynamic>;
    final savedWaterGoal = int.tryParse((results[2] as String?) ?? '');
    final savedSleepGoal = double.tryParse((results[3] as String?) ?? '');

    final calGoal = (profile?.dailyCaloriesGoal as int? ?? 600).clamp(100, 10000);
    final stepGoal = (profile?.dailyStepsGoal as int? ?? 7000).clamp(500, 100000);
    final minGoal = (profile?.dailyMinutesGoal as int? ?? 60).clamp(10, 600);
    final waterGoal =
        (savedWaterGoal != null && savedWaterGoal >= 500) ? savedWaterGoal : 2500;
    final sleepGoal =
        (savedSleepGoal != null && savedSleepGoal >= 3.0) ? savedSleepGoal : 8.0;

    final dayFmt = DateFormat('yyyy-MM-dd');
    double waterTodayMl = 0.0;
    for (final pt in waterPts) {
      if (dayFmt.format((pt.recordedAt as DateTime).toLocal()) == todayKey) {
        waterTodayMl += (pt.value as num).toDouble();
      }
    }

    double sleepTodayHrs = 0.0;
    for (final pt in sleepPts) {
      if (dayFmt.format((pt.recordedAt as DateTime).toLocal()) == todayKey) {
        final v = (pt.value as num).toDouble();
        if (v > sleepTodayHrs) sleepTodayHrs = v;
      }
    }

    final candidates = <GoalCompletionEvent>[
      if ((today.calories as int) >= calGoal)
        GoalCompletionEvent(
          kind: DailyGoalKind.calories,
          achieved: (today.calories as int).toDouble(),
          target: calGoal.toDouble(),
        ),
      if ((today.steps as int) >= stepGoal)
        GoalCompletionEvent(
          kind: DailyGoalKind.steps,
          achieved: (today.steps as int).toDouble(),
          target: stepGoal.toDouble(),
        ),
      if ((today.minutes as int) >= minGoal)
        GoalCompletionEvent(
          kind: DailyGoalKind.minutes,
          achieved: (today.minutes as int).toDouble(),
          target: minGoal.toDouble(),
        ),
      if (waterTodayMl >= waterGoal)
        GoalCompletionEvent(
          kind: DailyGoalKind.water,
          achieved: waterTodayMl,
          target: waterGoal.toDouble(),
        ),
      if (sleepTodayHrs >= sleepGoal)
        GoalCompletionEvent(
          kind: DailyGoalKind.sleep,
          achieved: sleepTodayHrs,
          target: sleepGoal,
        ),
    ];

    if (candidates.isEmpty) return const [];

    final newlyHit = <GoalCompletionEvent>[];
    for (final ev in candidates) {
      final key = _seenKey(todayKey, ev.kind, profileId);
      final seen = await db.getSetting(key);
      if (seen != '1') {
        await db.setSetting(key, '1');
        newlyHit.add(ev);
      }
    }
    return newlyHit;
  }

  /// Checks for newly reached daily goals and opens a unified Liquid Glass
  /// completion celebration sheet if any goal was just achieved today.
  Future<List<GoalCompletionEvent>> checkAndCelebrate(
    BuildContext context, {
    required String profileId,
    bool ignoreTestGuard = false,
  }) async {
    if (profileId.isEmpty) return const [];
    if (!ignoreTestGuard && _isRunningInTest()) return const [];
    if (_isShowing) return const [];

    final newlyHit = await evaluateNewCompletions(profileId: profileId);
    if (newlyHit.isEmpty || !context.mounted) return newlyHit;

    await TempoStartupSplash.waitForCompletion();
    if (!context.mounted || _isShowing) return newlyHit;

    _isShowing = true;
    try {
      await showCelebrationSheet(context, events: newlyHit);
    } finally {
      _isShowing = false;
    }
    return newlyHit;
  }

  /// Presents the Liquid Glass goal completion sheet for one or more goals.
  Future<void> showCelebrationSheet(
    BuildContext context, {
    required List<GoalCompletionEvent> events,
  }) async {
    if (events.isEmpty || !context.mounted) return;
    HapticFeedback.heavyImpact();

    final c = AppColors.of(context, listen: false);
    final isSingle = events.length == 1;
    final primary = events.first;
    final hasAllThreeRings = events.any((e) => e.kind == DailyGoalKind.calories) &&
        events.any((e) => e.kind == DailyGoalKind.steps) &&
        events.any((e) => e.kind == DailyGoalKind.minutes);

    final heroColor = isSingle ? primary.accentColor(c) : c.accent;
    final title = hasAllThreeRings
        ? 'All Daily Rings Closed'
        : (isSingle ? primary.headline : 'Daily Goals Reached');
    final subtitle = isSingle
        ? 'You hit your ${primary.metricLabel.toLowerCase()} target for today'
        : '${events.length} daily targets reached today';

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
              // Animated Confetti + Semantic Goal Medallion
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TempoJiggIcon(
                      'confetti',
                      variant: JiggIconVariant.duotone,
                      color: heroColor,
                      size: 28,
                      trigger: JiggIconTrigger.appear,
                      fallbackIcon: CupertinoIcons.sparkles,
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 62,
                      height: 62,
                      decoration: BoxDecoration(
                        color: heroColor.withValues(
                          alpha: mc.isDark ? 0.22 : 0.14,
                        ),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: heroColor.withValues(alpha: 0.35),
                          width: 1.2,
                        ),
                      ),
                      child: Center(
                        child: isSingle
                            ? Icon(primary.icon, color: heroColor, size: 28)
                            : TempoJiggIcon(
                                'trophy',
                                variant: JiggIconVariant.solid,
                                color: heroColor,
                                size: 30,
                                trigger: JiggIconTrigger.appear,
                                fallbackIcon: CupertinoIcons.rosette,
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Transform.flip(
                      flipX: true,
                      child: TempoJiggIcon(
                        'confetti',
                        variant: JiggIconVariant.duotone,
                        color: heroColor,
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
                title,
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
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: mc.textSecondary,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 18),

              // Stats Breakdown
              if (isSingle)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: mc.searchBg,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _GoalStatCell(
                          label: 'Achieved',
                          value: primary.achievedFormatted,
                          valueColor: heroColor,
                          c: mc,
                        ),
                      ),
                      Container(width: 1, height: 30, color: mc.divider),
                      Expanded(
                        child: _GoalStatCell(
                          label: 'Target',
                          value: primary.targetFormatted,
                          c: mc,
                        ),
                      ),
                      Container(width: 1, height: 30, color: mc.divider),
                      Expanded(
                        child: _GoalStatCell(
                          label: 'Progress',
                          value: '${primary.percent}%',
                          c: mc,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Column(
                  children: events.map((ev) {
                    final evColor = ev.accentColor(mc);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 11,
                        ),
                        decoration: BoxDecoration(
                          color: mc.searchBg,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: evColor.withValues(
                                  alpha: mc.isDark ? 0.22 : 0.14,
                                ),
                              ),
                              child: Icon(ev.icon, color: evColor, size: 17),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    ev.metricLabel,
                                    style: TextStyle(
                                      color: mc.textPrimary,
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    'Target ${ev.targetFormatted}',
                                    style: TextStyle(
                                      color: mc.textTertiary,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              ev.achievedFormatted,
                              style: TextStyle(
                                color: evColor,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),

              const SizedBox(height: 18),
              TempoBouncyButton(
                height: 52,
                backgroundColor: heroColor,
                onPressed: () {
                  HapticFeedback.lightImpact();
                  Navigator.of(ctx).pop();
                },
                child: const Text('Awesome'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _GoalStatCell extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final AppColors c;

  const _GoalStatCell({
    required this.label,
    required this.value,
    required this.c,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: valueColor ?? c.textPrimary,
            fontSize: 15.5,
            fontWeight: FontWeight.w700,
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
