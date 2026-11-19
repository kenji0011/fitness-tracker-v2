import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../models/local_profile.dart';
import '../services/active_profile_provider.dart';
import '../services/tempo_rust_db.dart';
import '../theme/app_colors.dart';
import '../widgets/liquid_glass_surface.dart';
import '../widgets/oval_activity_rings.dart';
import '../widgets/tempo_sliver_header.dart';
import 'add_data_screen.dart';
import 'calories_info_screen.dart';
import 'detail_screen.dart';
import 'moving_info_screen.dart';
import 'sleep_info_screen.dart';
import 'steps_info_screen.dart';
import 'waist_measurement_info_screen.dart';

/// Shared model kept for compatibility with detail screens.
class DailyActivity {
  final DateTime date;
  final int steps;
  final int calories;
  final int minutes;
  final int workoutsCount;

  const DailyActivity({
    required this.date,
    required this.steps,
    required this.calories,
    required this.minutes,
    required this.workoutsCount,
  });

  factory DailyActivity.fromLocal(LocalDailyActivity item) => DailyActivity(
        date: item.date,
        steps: item.steps,
        calories: item.calories,
        minutes: item.minutes,
        workoutsCount: item.workoutsCount,
      );
}

class HealthDashboard extends StatefulWidget {
  final int refreshVersion;
  final VoidCallback? onSwitchToWorkouts;
  final VoidCallback? onSwitchToProgress;
  final VoidCallback? onDoubleTapProfileSwitcher;

  const HealthDashboard({
    super.key,
    this.refreshVersion = 0,
    this.onSwitchToWorkouts,
    this.onSwitchToProgress,
    this.onDoubleTapProfileSwitcher,
  });

  @override
  State<HealthDashboard> createState() => _HealthDashboardState();
}

class _HealthDashboardState extends State<HealthDashboard> {
  final TempoRustDb _db = TempoRustDb.instance;

  LocalDashboardSummary? _summary;
  DateTime _lastUpdated = DateTime.now();
  bool _isLoading = true;
  bool _pedometerActive = false;
  int? _pedometerBaseline;
  int _initialStoredSteps = 0;
  int? _highlightedRing;
  StreamSubscription<StepCount>? _stepSub;

  @override
  void initState() {
    super.initState();
    _loadDashboard();
    _initPedometer();
  }

  @override
  void didUpdateWidget(covariant HealthDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshVersion != oldWidget.refreshVersion) {
      _loadDashboard();
    }
  }

  @override
  void dispose() {
    _stepSub?.cancel();
    super.dispose();
  }

  Future<void> _loadDashboard() async {
    final profileId = context.read<ActiveProfileProvider>().activeProfileId;
    if (profileId == null || profileId.isEmpty) return;

    try {
      final summary = await _db.getDashboardSummary(profileId);
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _initialStoredSteps = summary.today.steps;
        _lastUpdated = DateTime.now();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Failed to load dashboard from Rust DB: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _initPedometer() async {
    if (kIsWeb) return;
    try {
      final status = await Permission.activityRecognition.status;
      if (!status.isGranted) return;

      _stepSub = Pedometer.stepCountStream.listen(
        (event) async {
          final profileId = mounted
              ? context.read<ActiveProfileProvider>().activeProfileId
              : null;
          if (profileId == null) return;

          _pedometerBaseline ??= event.steps;
          final delta = (event.steps - _pedometerBaseline!).clamp(0, 100000);
          final totalSteps = _initialStoredSteps + delta;

          await _db.upsertDailyActivity(
            profileId: profileId,
            steps: totalSteps,
          );
          if (mounted) {
            setState(() => _pedometerActive = true);
            _loadDashboard();
          }
        },
        onError: (_) {},
      );
    } catch (_) {}
  }

  Future<void> _enableStepsTracking() async {
    if (kIsWeb) return;
    final res = await Permission.activityRecognition.request();
    if (res.isGranted) {
      await _initPedometer();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Live step counter enabled')),
        );
      }
    } else if (mounted) {
      _openAddData(initialMetric: 'steps');
    }
  }

  Future<void> _openAddData({String? initialMetric}) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddDataScreen(initialMetric: initialMetric),
      ),
    );
    if (changed == true && mounted) {
      context.read<ActiveProfileProvider>().notifyDataChanged();
      _loadDashboard();
    }
  }

  Future<void> _openMetricDetail({
    required String title,
    required String metricType,
    required String unit,
    required Color accentColor,
    Widget? infoScreen,
  }) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DetailScreen(
          title: title,
          metricType: metricType,
          unit: unit,
          accentColor: accentColor,
          infoScreen: infoScreen,
        ),
      ),
    );
    if (mounted) _loadDashboard();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final profileProvider = context.watch<ActiveProfileProvider>();
    final profile = _summary?.profile ?? profileProvider.activeProfile;

    final today = _summary?.today ??
        LocalDailyActivity(dateKey: TempoRustDb.todayKey());
    final dailyHistory = _summary?.dailyHistory ?? const [];
    final weightPts = _summary?.weightHistory ?? const [];
    final waistPts = _summary?.waistHistory ?? const [];
    final sleepPts = _summary?.sleepHistory ?? const [];

    final calGoal = (profile?.dailyCaloriesGoal ?? 600).clamp(100, 10000);
    final stepGoal = (profile?.dailyStepsGoal ?? 7000).clamp(500, 100000);
    final minGoal = (profile?.dailyMinutesGoal ?? 60).clamp(10, 600);

    final calProgress = (today.calories / calGoal).clamp(0.0, 1.0);
    final stepProgress = (today.steps / stepGoal).clamp(0.0, 1.0);
    final minProgress = (today.minutes / minGoal).clamp(0.0, 1.0);

    // Compute health summary status pills dynamically from local data
    int goalsNeedingAttention = 0;
    int goalsGood = 0;
    if (calProgress < 0.7) {
      goalsNeedingAttention++;
    } else {
      goalsGood++;
    }
    if (stepProgress < 0.7) {
      goalsNeedingAttention++;
    } else {
      goalsGood++;
    }
    if (minProgress < 0.7) {
      goalsNeedingAttention++;
    } else {
      goalsGood++;
    }
    if ((profile?.sleepHours ?? 0) < 7.0) {
      goalsNeedingAttention++;
    } else {
      goalsGood++;
    }
    if ((profile?.bmi ?? 0) >= 18.5 && (profile?.bmi ?? 0) <= 24.9) {
      goalsGood++;
    } else if ((profile?.bmi ?? 0) > 0) {
      goalsNeedingAttention++;
    }

    final updatedStr = DateFormat('HH:mm').format(_lastUpdated);

    return Scaffold(
      backgroundColor: c.scaffold,
      body: _isLoading && _summary == null
          ? Center(child: CupertinoActivityIndicator(color: c.accent))
          : RefreshIndicator(
              color: c.accent,
              edgeOffset: MediaQuery.paddingOf(context).top + 56,
              onRefresh: _loadDashboard,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  TempoSliverHeader(
                    title: 'Summary',
                    actions: [
                      TempoHeaderAction(
                        tooltip: 'Log Health Data',
                        onPressed: () => _openAddData(),
                        icon: Icon(
                          CupertinoIcons.add,
                          size: 22,
                          color: c.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(18, 6, 18, 124),
                    sliver: SliverList.list(
                      children: [
                        // --- Hero Tilted Concentric Oval Activity Rings ---
                        Center(
                          child: OvalActivityRings(
                            size: 256,
                            caloriesProgress: calProgress,
                            stepsProgress: stepProgress,
                            minutesProgress: minProgress,
                            highlightedRing: _highlightedRing,
                            onRingTap: (ringIdx) {
                              setState(() {
                                _highlightedRing =
                                    _highlightedRing == ringIdx ? null : ringIdx;
                              });
                            },
                          ),
                        ),
                        const SizedBox(height: 12),

                    // --- Minimal Tempo Daily Activity Snapshot Card ---
                    AppleCard(
                      borderRadius: 24,
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _RingMetricColumn(
                                  accentColor: const Color(0xFFF36432),
                                  title: 'Calories',
                                  value: NumberFormat('#,###')
                                      .format(today.calories),
                                  goalText:
                                      '${NumberFormat('#,###').format(calGoal)} kcal',
                                  progress: calProgress,
                                  isHighlighted: _highlightedRing == 0,
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const CaloriesInfoScreen(),
                                    ),
                                  ),
                                ),
                              ),
                              Container(
                                width: 1,
                                height: 54,
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 6),
                                color: c.divider,
                              ),
                              Expanded(
                                child: _RingMetricColumn(
                                  accentColor: const Color(0xFF93DC2A),
                                  title: 'Steps',
                                  value:
                                      NumberFormat('#,###').format(today.steps),
                                  goalText: NumberFormat('#,###')
                                      .format(stepGoal),
                                  progress: stepProgress,
                                  isHighlighted: _highlightedRing == 1,
                                  onTap: () => _pedometerActive
                                      ? Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const StepsInfoScreen(),
                                          ),
                                        )
                                      : _enableStepsTracking(),
                                ),
                              ),
                              Container(
                                width: 1,
                                height: 54,
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 6),
                                color: c.divider,
                              ),
                              Expanded(
                                child: _RingMetricColumn(
                                  accentColor: const Color(0xFF56B7FF),
                                  title: 'Activity',
                                  value: '${today.minutes}',
                                  goalText: '$minGoal min',
                                  progress: minProgress,
                                  isHighlighted: _highlightedRing == 2,
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const MovingInfoScreen(),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            child: Divider(height: 1, color: c.divider),
                          ),
                          // Clean minimal daily insight footer (replaces Mi Fitness chips card)
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: widget.onSwitchToProgress,
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${_summary?.currentStreak ?? 0}d streak · ${today.workoutsCount} ${today.workoutsCount == 1 ? 'workout' : 'workouts'} today',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: c.textPrimary,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: -0.1,
                                          fontFeatures: const [
                                            FontFeature.tabularFigures(),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        goalsNeedingAttention == 0
                                            ? 'All daily targets on track'
                                            : '$goalsGood of ${goalsGood + goalsNeedingAttention} daily goals on track',
                                        style: TextStyle(
                                          color: c.textTertiary,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  updatedStr,
                                  style: TextStyle(
                                    color: c.textTertiary,
                                    fontSize: 12,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(
                                  CupertinoIcons.chevron_right,
                                  size: 14,
                                  color: c.textTertiary,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // --- 2-Column Rich Health Metric Grid (matching Screenshots 1 & 2) ---
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.86,
                      children: [
                        // 1. Sleep Card
                        _HealthGridTile(
                          badgeIcon: CupertinoIcons.bed_double_fill,
                          badgeColor: const Color(0xFF6B63F6),
                          title: 'Sleep',
                          trailingPill: 'Log',
                          onTrailingPillTap: () =>
                              _openAddData(initialMetric: 'sleep'),
                          primaryValue: (profile?.sleepHours ?? 0) > 0
                              ? '${profile!.sleepHours.toStringAsFixed(1)} hrs'
                              : null,
                          subtitle: (profile?.sleepHours ?? 0) > 0
                              ? _latestTimeLabel(sleepPts)
                              : 'Log nightly sleep to track recovery',
                          chart: _VerticalTickVisualizer(
                            values: sleepPts.map((e) => e.value).toList(),
                            activeColor: const Color(0xFF6B63F6),
                            leftLabel: '00:00',
                            rightLabel: '24:00',
                          ),
                          onTap: () => _openMetricDetail(
                            title: 'Sleep',
                            metricType: 'sleep',
                            unit: 'hrs',
                            accentColor: const Color(0xFF6B63F6),
                            infoScreen: const SleepInfoScreen(),
                          ),
                        ),

                        // 2. Weight Card (with green smooth trend line like Screenshot 2!)
                        _HealthGridTile(
                          badgeIcon: CupertinoIcons.gauge,
                          badgeColor: const Color(0xFF4CD964),
                          title: 'Weight',
                          primaryValue: (profile?.weightKg ?? 0) > 0
                              ? '${profile!.weightKg.toStringAsFixed(2)} kg'
                              : null,
                          subtitle: (profile?.weightKg ?? 0) > 0
                              ? _latestTimeLabel(weightPts)
                              : 'Tap to record your weight',
                          chart: _SmoothAreaSparkline(
                            points: weightPts,
                            lineColor: const Color(0xFF4CD964),
                          ),
                          onTap: () => _openMetricDetail(
                            title: 'Weight',
                            metricType: 'weight',
                            unit: 'kg',
                            accentColor: const Color(0xFF4CD964),
                          ),
                        ),

                        // 3. BMI / Heart Health Card
                        _HealthGridTile(
                          badgeIcon: CupertinoIcons.heart_fill,
                          badgeColor: const Color(0xFFE84A4A),
                          title: 'BMI Index',
                          primaryValue: (profile?.bmi ?? 0) > 0
                              ? profile!.bmi.toStringAsFixed(1)
                              : null,
                          subtitle: (profile?.bmi ?? 0) > 0
                              ? '${_bmiLabel(profile!.bmi)} • ${(profile.heightCm).toStringAsFixed(0)} cm'
                              : 'Add height & weight to calculate',
                          chart: _VerticalTickVisualizer(
                            values: weightPts
                                .where((_) => (profile?.heightCm ?? 0) > 0)
                                .map((e) {
                                  final hm = profile!.heightCm / 100.0;
                                  return e.value / (hm * hm);
                                })
                                .toList(),
                            activeColor: const Color(0xFFE84A4A),
                            leftLabel: '18.5',
                            rightLabel: '25.0',
                          ),
                          onTap: () => _openMetricDetail(
                            title: 'BMI',
                            metricType: 'weight',
                            unit: 'kg/m²',
                            accentColor: const Color(0xFFE84A4A),
                          ),
                        ),

                        // 4. Waist Measurement Card
                        _HealthGridTile(
                          badgeIcon: CupertinoIcons.resize_h,
                          badgeColor: const Color(0xFF3CC29E),
                          title: 'Waist',
                          primaryValue: (profile?.waistCm ?? 0) > 0
                              ? '${profile!.waistCm.toStringAsFixed(1)} cm'
                              : null,
                          subtitle: (profile?.waistCm ?? 0) > 0
                              ? _latestTimeLabel(waistPts)
                              : 'Tap to track waist size',
                          chart: _SmoothAreaSparkline(
                            points: waistPts,
                            lineColor: const Color(0xFF3CC29E),
                          ),
                          onTap: () => _openMetricDetail(
                            title: 'Waist',
                            metricType: 'waist',
                            unit: 'cm',
                            accentColor: const Color(0xFF3CC29E),
                            infoScreen: const WaistMeasurementInfoScreen(),
                          ),
                        ),

                        // 5. 7-Day Activity Energy Card
                        _HealthGridTile(
                          badgeIcon: CupertinoIcons.bolt_fill,
                          badgeColor: const Color(0xFFF39C2E),
                          title: '7-Day Burn',
                          primaryValue:
                              '${dailyHistory.take(7).fold<int>(0, (s, d) => s + d.calories)} kcal',
                          subtitle: 'Last 7 days total',
                          chart: _VerticalTickVisualizer(
                            values: _last7DaysCalories(dailyHistory),
                            activeColor: const Color(0xFFF39C2E),
                            leftLabel: '7d ago',
                            rightLabel: 'Today',
                          ),
                          onTap: () => _openMetricDetail(
                            title: 'Daily Activity',
                            metricType: 'activity',
                            unit: 'kcal',
                            accentColor: const Color(0xFFF39C2E),
                          ),
                        ),

                        // 6. Workouts Completed Card
                        _HealthGridTile(
                          badgeIcon: CupertinoIcons.flame_fill,
                          badgeColor: const Color(0xFFE8527A),
                          title: 'Workouts',
                          primaryValue: '${_summary?.totalWorkouts ?? 0} total',
                          subtitle: (_summary?.recentWorkouts.isNotEmpty ?? false)
                              ? _summary!.recentWorkouts.first.title
                              : 'Tap to start training',
                          chart: _VerticalTickVisualizer(
                            values: _last7DaysWorkouts(dailyHistory),
                            activeColor: const Color(0xFFE8527A),
                            leftLabel: 'Mon',
                            rightLabel: 'Sun',
                          ),
                          onTap: () => widget.onSwitchToWorkouts?.call(),
                        ),
                      ],
                    ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  List<double> _last7DaysCalories(List<LocalDailyActivity> history) {
    final now = DateTime.now();
    final map = {for (final h in history) h.dateKey: h.calories.toDouble()};
    return List.generate(7, (i) {
      final d = now.subtract(Duration(days: 6 - i));
      return map[DateFormat('yyyy-MM-dd').format(d)] ?? 0.0;
    });
  }

  List<double> _last7DaysWorkouts(List<LocalDailyActivity> history) {
    final now = DateTime.now();
    final map = {
      for (final h in history) h.dateKey: h.workoutsCount.toDouble(),
    };
    return List.generate(7, (i) {
      final d = now.subtract(Duration(days: 6 - i));
      return map[DateFormat('yyyy-MM-dd').format(d)] ?? 0.0;
    });
  }

  String _latestTimeLabel(List<BodyMetricPoint> pts) {
    if (pts.isEmpty) return 'Logged locally';
    return DateFormat('MM/dd HH:mm').format(pts.last.recordedAt.toLocal());
  }

  String _bmiLabel(double bmi) {
    if (bmi <= 0) return 'N/A';
    if (bmi < 18.5) return 'Underweight';
    if (bmi < 25) return 'Normal';
    if (bmi < 30) return 'Overweight';
    return 'High';
  }
}

class _RingMetricColumn extends StatelessWidget {
  final Color accentColor;
  final String title;
  final String value;
  final String goalText;
  final double progress;
  final bool isHighlighted;
  final VoidCallback onTap;

  const _RingMetricColumn({
    required this.accentColor,
    required this.title,
    required this.value,
    required this.goalText,
    required this.progress,
    required this.isHighlighted,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: isHighlighted
              ? accentColor.withValues(alpha: c.isDark ? 0.14 : 0.10)
              : Colors.transparent,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: accentColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.textSecondary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.6,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: progress.clamp(0.0, 1.0)),
                duration: const Duration(milliseconds: 520),
                curve: Curves.easeOutCubic,
                builder: (_, v, __) => LinearProgressIndicator(
                  value: v,
                  minHeight: 3,
                  backgroundColor: c.divider,
                  valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                ),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              goalText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.textTertiary,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HealthGridTile extends StatelessWidget {
  final IconData badgeIcon;
  final Color badgeColor;
  final String title;
  final String? trailingPill;
  final VoidCallback? onTrailingPillTap;
  final String? primaryValue;
  final String subtitle;
  final Widget chart;
  final VoidCallback onTap;

  const _HealthGridTile({
    required this.badgeIcon,
    required this.badgeColor,
    required this.title,
    this.trailingPill,
    this.onTrailingPillTap,
    this.primaryValue,
    required this.subtitle,
    required this.chart,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return AppleCard(
      borderRadius: 22,
      padding: const EdgeInsets.all(15),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: badgeColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(badgeIcon, color: Colors.white, size: 15),
              ),
              const Spacer(),
              if (trailingPill != null)
                GestureDetector(
                  onTap: onTrailingPillTap,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: badgeColor.withValues(
                        alpha: c.isDark ? 0.22 : 0.12,
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          trailingPill!,
                          style: TextStyle(
                            color: badgeColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(
                          CupertinoIcons.chevron_right,
                          size: 10,
                          color: badgeColor,
                        ),
                      ],
                    ),
                  ),
                )
              else
                Icon(
                  CupertinoIcons.chevron_right,
                  size: 14,
                  color: c.textTertiary,
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: c.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 3),
          if (primaryValue != null) ...[
            Text(
              primaryValue!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 1),
          ],
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: c.textTertiary,
              fontSize: 12,
              height: 1.25,
            ),
          ),
          const Spacer(),
          chart,
        ],
      ),
    );
  }
}

/// Vertical striped-bar mini visualizer matching the Mi Fitness cards in Screenshot 2.
class _VerticalTickVisualizer extends StatelessWidget {
  final List<double> values;
  final Color activeColor;
  final String leftLabel;
  final String rightLabel;

  const _VerticalTickVisualizer({
    required this.values,
    required this.activeColor,
    required this.leftLabel,
    required this.rightLabel,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    const barCount = 20;
    final maxVal = values.isEmpty
        ? 1.0
        : values.reduce((a, b) => a > b ? a : b).clamp(1.0, double.infinity);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 36,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(barCount, (i) {
              double frac = 0.0;
              if (values.isNotEmpty) {
                final srcIdx =
                    ((i / barCount) * values.length).floor().clamp(0, values.length - 1);
                frac = (values[srcIdx] / maxVal).clamp(0.0, 1.0);
              }
              final hasValue = frac > 0.02;
              return Container(
                width: 3,
                height: hasValue ? (10 + frac * 26) : 34,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  color: hasValue
                      ? activeColor
                      : (c.isDark
                          ? Colors.white.withValues(alpha: 0.11)
                          : Colors.black.withValues(alpha: 0.08)),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              leftLabel,
              style: TextStyle(color: c.textTertiary, fontSize: 10),
            ),
            Text(
              rightLabel,
              style: TextStyle(color: c.textTertiary, fontSize: 10),
            ),
          ],
        ),
      ],
    );
  }
}

/// Smooth gradient area line sparkline matching the Weight card in Screenshot 2.
class _SmoothAreaSparkline extends StatelessWidget {
  final List<BodyMetricPoint> points;
  final Color lineColor;

  const _SmoothAreaSparkline({
    required this.points,
    required this.lineColor,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final hasData = points.isNotEmpty;
    final spots = hasData
        ? (points.length == 1
            ? [FlSpot(0, points.first.value), FlSpot(1, points.first.value)]
            : List.generate(
                points.length,
                (i) => FlSpot(i.toDouble(), points[i].value),
              ))
        : const [FlSpot(0, 1), FlSpot(1, 1)];

    final minY = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b) - 1;
    final maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b) + 1;

    final startLabel = hasData
        ? DateFormat('M/d').format(points.first.recordedAt.toLocal())
        : '--';
    final endLabel = hasData
        ? DateFormat('M/d').format(points.last.recordedAt.toLocal())
        : 'Today';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 38,
          child: LineChart(
            LineChartData(
              minY: minY,
              maxY: maxY,
              gridData: const FlGridData(show: false),
              titlesData: const FlTitlesData(show: false),
              borderData: FlBorderData(show: false),
              lineTouchData: const LineTouchData(enabled: false),
              lineBarsData: [
                LineChartBarData(
                  isCurved: true,
                  color: hasData
                      ? lineColor
                      : (c.isDark
                          ? Colors.white.withValues(alpha: 0.14)
                          : Colors.black.withValues(alpha: 0.10)),
                  barWidth: 2.2,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        (hasData ? lineColor : c.textTertiary)
                            .withValues(alpha: 0.28),
                        (hasData ? lineColor : c.textTertiary)
                            .withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                  spots: spots,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              startLabel,
              style: TextStyle(color: c.textTertiary, fontSize: 10),
            ),
            Text(
              endLabel,
              style: TextStyle(color: c.textTertiary, fontSize: 10),
            ),
          ],
        ),
      ],
    );
  }
}
