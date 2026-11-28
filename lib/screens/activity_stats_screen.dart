import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/local_profile.dart';
import '../services/active_profile_provider.dart';
import '../services/tempo_rust_db.dart';
import '../theme/app_colors.dart';
import '../widgets/ios_popover_menu.dart';
import '../widgets/ios_stretch_sheet.dart';
import '../widgets/liquid_glass_surface.dart';
import '../widgets/oval_activity_rings.dart';
import '../widgets/tempo_morph_route.dart';
import '../widgets/tempo_sliver_header.dart';
import '../widgets/tempo_toast.dart';
import 'add_data_screen.dart';
import 'history_calendar_screen.dart';
import 'metric_detail_screen.dart';
import 'progress_share_screen.dart';

/// Full daily & weekly Activity Stats screen opened when tapping the diagonal
/// Oval Activity Rings tracker on the Summary dashboard:
/// - Top Stats bar with calendar date picker, Share Studio button, and ⋮ menu
/// - Interactive Mon-Sun mini oval ring strip
/// - Hero tilted Oval Activity Rings card with Calories / Steps / Activity readouts
/// - Weekly rounded bar charts with dashed goal line, last-week daily average,
///   day-by-day goal checkmarks / progress rings, and live goal coaching callouts.
class ActivityStatsScreen extends StatefulWidget {
  final DateTime? initialDate;

  const ActivityStatsScreen({super.key, this.initialDate});

  @override
  State<ActivityStatsScreen> createState() => _ActivityStatsScreenState();
}

class _ActivityStatsScreenState extends State<ActivityStatsScreen> {
  static const Color _calColor = Color(0xFFF36432);
  static const Color _stepColor = Color(0xFFA6EB3C);
  static const Color _minColor = Color(0xFF56B7FF);

  final TempoRustDb _db = TempoRustDb.instance;
  final GlobalKey _moreButtonKey = GlobalKey();
  final GlobalKey _shareButtonKey = GlobalKey();
  final GlobalKey _dateButtonKey = GlobalKey();

  late DateTime _selectedDate;
  LocalProfile? _profile;
  Map<String, LocalDailyActivity> _activityByDay = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final now = widget.initialDate ?? DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);
    _load();
  }

  String _dayKey(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  DateTime get _todayDate {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  Future<void> _load({bool showSpinner = true}) async {
    final pid = context.read<ActiveProfileProvider>().activeProfileId;
    if (pid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (showSpinner && _profile == null) {
      setState(() => _loading = true);
    }

    try {
      final results = await Future.wait([
        _db.getDashboardSummary(pid),
        _db.getDailyActivityHistory(pid, limit: 400),
      ]);
      if (!mounted) return;
      final summary = results[0] as LocalDashboardSummary;
      final history = results[1] as List<LocalDailyActivity>;

      final map = <String, LocalDailyActivity>{};
      for (final a in history) {
        map[a.dateKey] = a;
      }
      map.putIfAbsent(summary.today.dateKey, () => summary.today);

      setState(() {
        _profile = summary.profile;
        _activityByDay = map;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Failed to load ActivityStatsScreen: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  int get _calGoal => (_profile?.dailyCaloriesGoal ?? 600).clamp(100, 10000);
  int get _stepGoal => (_profile?.dailyStepsGoal ?? 7000).clamp(500, 100000);
  int get _minGoal => (_profile?.dailyMinutesGoal ?? 60).clamp(10, 600);

  /// Monday..Sunday 7-day window containing `_selectedDate`.
  List<DateTime> get _weekDays {
    final mondayOffset = _selectedDate.weekday - DateTime.monday;
    final monday = _selectedDate.subtract(Duration(days: mondayOffset));
    return List.generate(7, (i) => monday.add(Duration(days: i)));
  }

  LocalDailyActivity _activityFor(DateTime date) {
    final key = _dayKey(date);
    return _activityByDay[key] ?? LocalDailyActivity(dateKey: key);
  }

  int _lastWeekDailyAvg(int Function(LocalDailyActivity) selector) {
    final prevMonday = _weekDays.first.subtract(const Duration(days: 7));
    int sum = 0;
    for (int i = 0; i < 7; i++) {
      sum += selector(_activityFor(prevMonday.add(Duration(days: i))));
    }
    return (sum / 7).round();
  }

  void _selectDate(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    if (normalized.isAfter(_todayDate)) return;
    if (_dayKey(normalized) == _dayKey(_selectedDate)) return;
    HapticFeedback.selectionClick();
    setState(() => _selectedDate = normalized);
  }

  Future<void> _pickCalendarDate() async {
    HapticFeedback.selectionClick();
    final recordedKeys = _activityByDay.entries
        .where(
          (e) =>
              e.value.calories > 0 || e.value.steps > 0 || e.value.minutes > 0,
        )
        .map((e) => e.key)
        .toSet();
    final result = await pushTempoMorphRoute<HistoryCalendarSelection>(
      context: context,
      sourceKey: _dateButtonKey,
      sourceBorderRadius: 14,
      builder: (_) => HistoryCalendarScreen(
        initialDate: _selectedDate,
        initialModeIndex: 0,
        recordedDateKeys: recordedKeys,
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _selectedDate = DateTime(
          result.date.year,
          result.date.month,
          result.date.day,
        );
      });
    }
  }

  Future<void> _openShareStudio() async {
    HapticFeedback.selectionClick();
    await pushTempoMorphRoute<void>(
      context: context,
      sourceKey: _shareButtonKey,
      sourceBorderRadius: 999,
      builder: (_) => ProgressShareScreen(initialDate: _selectedDate),
    );
  }

  Future<void> _openMetricDetail(
    TempoMetricKind kind, {
    BuildContext? sourceContext,
    double borderRadius = 24.0,
  }) async {
    await pushTempoMorphRoute<void>(
      context: context,
      sourceContext: sourceContext,
      sourceBorderRadius: borderRadius,
      builder: (_) => MetricDetailScreen(
        kind: kind,
        initialDate: _selectedDate,
      ),
    );
    if (mounted) _load(showSpinner: false);
  }

  Future<void> _openLogActivity({String? initialMetric}) async {
    final changed = await pushTempoMorphRoute<bool>(
      context: context,
      sourceKey: _moreButtonKey,
      sourceBorderRadius: 999,
      builder: (_) => AddDataScreen(initialMetric: initialMetric ?? 'calories'),
    );
    if (changed == true && mounted) {
      context.read<ActiveProfileProvider>().notifyDataChanged();
      await _load(showSpinner: false);
    }
  }

  Future<void> _openEditGoalsSheet() async {
    final profileProvider = context.read<ActiveProfileProvider>();
    final pid = profileProvider.activeProfileId;
    if (pid == null) return;

    int tempCal = _calGoal;
    int tempSteps = _stepGoal;
    int tempMin = _minGoal;

    final saved = await showTempoSheet<({int cal, int steps, int mins})>(
      context: context,
      backgroundColor: AppColors.of(context, listen: false).card,
      borderRadius: 28,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
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
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: mc.accent.withValues(
                          alpha: mc.isDark ? 0.22 : 0.13,
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        CupertinoIcons.flame_fill,
                        color: mc.accent,
                        size: 19,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Daily Activity Goals',
                            style: TextStyle(
                              color: mc.textPrimary,
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.35,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Set daily targets for your rings',
                            style: TextStyle(
                              color: mc.textSecondary,
                              fontSize: 12.8,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TempoGlassCircleButton(
                      size: 34,
                      enableBlur: false,
                      enableRefraction: false,
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: Icon(
                        CupertinoIcons.xmark,
                        size: 15,
                        color: mc.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _GoalSliderRow(
                  icon: CupertinoIcons.flame_fill,
                  label: 'Calories',
                  valueText: '${NumberFormat('#,###').format(tempCal)} kcal',
                  value: tempCal.toDouble().clamp(200, 3000),
                  min: 200,
                  max: 3000,
                  divisions: 56,
                  color: _calColor,
                  onChanged: (v) {
                    setModalState(() => tempCal = (v / 50).round() * 50);
                  },
                ),
                const SizedBox(height: 10),
                _GoalSliderRow(
                  icon: Icons.directions_walk_rounded,
                  label: 'Steps',
                  valueText: '${NumberFormat('#,###').format(tempSteps)} steps',
                  value: tempSteps.toDouble().clamp(2000, 25000),
                  min: 2000,
                  max: 25000,
                  divisions: 46,
                  color: _stepColor,
                  onChanged: (v) {
                    setModalState(() => tempSteps = (v / 500).round() * 500);
                  },
                ),
                const SizedBox(height: 10),
                _GoalSliderRow(
                  icon: CupertinoIcons.clock_fill,
                  label: 'Activity time',
                  valueText: '$tempMin min',
                  value: tempMin.toDouble().clamp(15, 180),
                  min: 15,
                  max: 180,
                  divisions: 33,
                  color: _minColor,
                  onChanged: (v) {
                    setModalState(() => tempMin = (v / 5).round() * 5);
                  },
                ),
                const SizedBox(height: 20),
                TempoBouncyButton(
                  height: 52,
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    Navigator.of(ctx).pop(
                      (cal: tempCal, steps: tempSteps, mins: tempMin),
                    );
                  },
                  child: const Text('Save goals'),
                ),
              ],
            ),
          );
        },
      ),
    );

    if (saved == null || !mounted) return;
    await _db.updateProfile(
      id: pid,
      dailyCaloriesGoal: saved.cal,
      dailyStepsGoal: saved.steps,
      dailyMinutesGoal: saved.mins,
    );
    await profileProvider.refreshProfiles();
    await _load(showSpinner: false);
    if (mounted) showTempoToast(context, 'Daily goals updated');
  }

  void _openMoreMenu() {
    HapticFeedback.selectionClick();
    final isToday = _dayKey(_selectedDate) == _dayKey(_todayDate);
    showTempoPopoverMenu(
      context: context,
      anchorKey: _moreButtonKey,
      actions: [
        TempoPopoverAction(
          label: 'Edit daily goals',
          onTap: _openEditGoalsSheet,
        ),
        TempoPopoverAction(
          label: 'Log activity',
          onTap: _openLogActivity,
        ),
        if (!isToday)
          TempoPopoverAction(
            label: 'Jump to today',
            onTap: () => _selectDate(_todayDate),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final weekDays = _weekDays;
    final selectedAct = _activityFor(_selectedDate);
    final isSelectedToday = _dayKey(_selectedDate) == _dayKey(_todayDate);
    final dayRef = isSelectedToday ? "today's" : "this day's";

    final calProgress = (selectedAct.calories / _calGoal).clamp(0.0, 1.0);
    final stepProgress = (selectedAct.steps / _stepGoal).clamp(0.0, 1.0);
    final minProgress = (selectedAct.minutes / _minGoal).clamp(0.0, 1.0);

    final calWeekValues =
        weekDays.map((d) => _activityFor(d).calories).toList();
    final stepWeekValues = weekDays.map((d) => _activityFor(d).steps).toList();
    final minWeekValues = weekDays.map((d) => _activityFor(d).minutes).toList();

    final lastWeekCalAvg = _lastWeekDailyAvg((a) => a.calories);
    final lastWeekStepAvg = _lastWeekDailyAvg((a) => a.steps);
    final lastWeekMinAvg = _lastWeekDailyAvg((a) => a.minutes);

    final calRemaining = (_calGoal - selectedAct.calories).clamp(0, _calGoal);
    final stepRemaining = (_stepGoal - selectedAct.steps).clamp(0, _stepGoal);
    final minRemaining = (_minGoal - selectedAct.minutes).clamp(0, _minGoal);

    return Scaffold(
      backgroundColor: c.scaffold,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Top Bar: Back | Dead-Center Stats + Date Picker | Share + More
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TempoGlassCircleButton(
                        icon: TempoBackChevron(color: c.textPrimary, size: 22),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 98),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Stats',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: c.textPrimary,
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 1),
                          GestureDetector(
                            key: _dateButtonKey,
                            behavior: HitTestBehavior.opaque,
                            onTap: _pickCalendarDate,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    DateFormat('MMMM d, yyyy')
                                        .format(_selectedDate),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: c.textSecondary,
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 2),
                                Icon(
                                  Icons.arrow_drop_down_rounded,
                                  size: 18,
                                  color: c.textSecondary,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TempoGlassCircleButton(
                            key: _shareButtonKey,
                            tooltip: 'Share progress',
                            icon: Icon(
                              CupertinoIcons.share,
                              size: 19,
                              color: c.textPrimary,
                            ),
                            onPressed: _openShareStudio,
                          ),
                          const SizedBox(width: 8),
                          TempoGlassCircleButton(
                            key: _moreButtonKey,
                            tooltip: 'More options',
                            icon: Icon(
                              CupertinoIcons.ellipsis_vertical,
                              size: 19,
                              color: c.textPrimary,
                            ),
                            onPressed: _openMoreMenu,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 7-Day Mini Oval Strip (Mon - Sun)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
              child: Row(
                children: List.generate(7, (i) {
                  final day = weekDays[i];
                  final act = _activityFor(day);
                  final isSelected = _dayKey(day) == _dayKey(_selectedDate);
                  final isFuture = day.isAfter(_todayDate);
                  const letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

                  return Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: isFuture ? null : () => _selectDate(day),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            letters[i],
                            style: TextStyle(
                              color: isSelected
                                  ? c.textPrimary
                                  : c.textTertiary,
                              fontSize: 12,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 6),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.all(2.5),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected
                                    ? c.accent.withValues(alpha: 0.55)
                                    : Colors.transparent,
                                width: 1.5,
                              ),
                            ),
                            child: MiniOvalActivityRings(
                              size: 30,
                              caloriesProgress: act.calories / _calGoal,
                              stepsProgress: act.steps / _stepGoal,
                              minutesProgress: act.minutes / _minGoal,
                              muted: isFuture,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            '${day.day}',
                            style: TextStyle(
                              color: isSelected
                                  ? c.accent
                                  : (isFuture
                                      ? c.textTertiary.withValues(alpha: 0.55)
                                      : c.textPrimary),
                              fontSize: 13,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),

            // Scrollable Cards Body
            Expanded(
              child: _loading
                  ? Center(child: CupertinoActivityIndicator(color: c.accent))
                  : RefreshIndicator(
                      color: c.accent,
                      onRefresh: () => _load(showSpinner: false),
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(
                          parent: BouncingScrollPhysics(),
                        ),
                        padding: EdgeInsets.fromLTRB(
                          16,
                          2,
                          16,
                          MediaQuery.paddingOf(context).bottom + 28,
                        ),
                        children: [
                          // Hero Oval Activity Rings Card
                          AppleCard(
                            borderRadius: 24,
                            padding: const EdgeInsets.fromLTRB(16, 22, 16, 20),
                            child: Column(
                              children: [
                                Center(
                                  child: RepaintBoundary(
                                    child: OvalActivityRings(
                                      size: 230,
                                      caloriesProgress: calProgress,
                                      stepsProgress: stepProgress,
                                      minutesProgress: minProgress,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 20),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Builder(
                                        builder: (colCtx) => _HeroMetricSummary(
                                          icon: CupertinoIcons.flame_fill,
                                          color: _calColor,
                                          label: 'Calories (kcal)',
                                          value: NumberFormat('#,###')
                                              .format(selectedAct.calories),
                                          goal: '/$_calGoal',
                                          onTap: () => _openMetricDetail(
                                            TempoMetricKind.calories,
                                            sourceContext: colCtx,
                                            borderRadius: 16,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Builder(
                                        builder: (colCtx) => _HeroMetricSummary(
                                          icon: Icons.directions_walk_rounded,
                                          color: _stepColor,
                                          label: 'Steps',
                                          value: NumberFormat('#,###')
                                              .format(selectedAct.steps),
                                          goal: '/$_stepGoal',
                                          onTap: () => _openMetricDetail(
                                            TempoMetricKind.steps,
                                            sourceContext: colCtx,
                                            borderRadius: 16,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Builder(
                                        builder: (colCtx) => _HeroMetricSummary(
                                          icon: CupertinoIcons.clock_fill,
                                          color: _minColor,
                                          label: 'Activity (min)',
                                          value: '${selectedAct.minutes}',
                                          goal: '/$_minGoal',
                                          onTap: () => _openMetricDetail(
                                            TempoMetricKind.minutes,
                                            sourceContext: colCtx,
                                            borderRadius: 16,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Card 1: Calories (kcal) Weekly Breakdown
                          Builder(
                            builder: (cardCtx) => _WeeklyMetricCard(
                              icon: CupertinoIcons.flame_fill,
                              color: _calColor,
                              title: 'Calories (kcal)',
                              currentValue: NumberFormat('#,###')
                                  .format(selectedAct.calories),
                              currentSubtitle: 'Current kcal',
                              lastWeekAvg:
                                  NumberFormat('#,###').format(lastWeekCalAvg),
                              weekDays: weekDays,
                              values: calWeekValues,
                              goal: _calGoal,
                              selectedDayIndex:
                                  _selectedDate.weekday - DateTime.monday,
                              todayDate: _todayDate,
                              calloutText: calRemaining > 0
                                  ? 'Burn ${NumberFormat('#,###').format(calRemaining)} more calories to reach $dayRef goal'
                                  : "Goal reached! You hit $dayRef calorie target.",
                              onHeaderTap: () => _openMetricDetail(
                                TempoMetricKind.calories,
                                sourceContext: cardCtx,
                              ),
                              onDayTap: _selectDate,
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Card 2: Steps Weekly Breakdown
                          Builder(
                            builder: (cardCtx) => _WeeklyMetricCard(
                              icon: Icons.directions_walk_rounded,
                              color: _stepColor,
                              title: 'Steps',
                              currentValue: NumberFormat('#,###')
                                  .format(selectedAct.steps),
                              currentSubtitle: 'Current steps',
                              lastWeekAvg:
                                  NumberFormat('#,###').format(lastWeekStepAvg),
                              weekDays: weekDays,
                              values: stepWeekValues,
                              goal: _stepGoal,
                              selectedDayIndex:
                                  _selectedDate.weekday - DateTime.monday,
                              todayDate: _todayDate,
                              calloutText: stepRemaining > 0
                                  ? 'Take ${NumberFormat('#,###').format(stepRemaining)} more steps to reach $dayRef goal'
                                  : "Goal reached! You hit $dayRef step target.",
                              onHeaderTap: () => _openMetricDetail(
                                TempoMetricKind.steps,
                                sourceContext: cardCtx,
                              ),
                              onDayTap: _selectDate,
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Card 3: Activity Time (mins) Weekly Breakdown
                          Builder(
                            builder: (cardCtx) => _WeeklyMetricCard(
                              icon: CupertinoIcons.clock_fill,
                              color: _minColor,
                              title: 'Activity time (mins)',
                              currentValue: '${selectedAct.minutes}',
                              currentSubtitle: 'Current mins',
                              lastWeekAvg: '$lastWeekMinAvg',
                              weekDays: weekDays,
                              values: minWeekValues,
                              goal: _minGoal,
                              selectedDayIndex:
                                  _selectedDate.weekday - DateTime.monday,
                              todayDate: _todayDate,
                              calloutText: minRemaining > 0
                                  ? 'Stay active $minRemaining more mins to reach $dayRef goal'
                                  : "Goal reached! You hit $dayRef activity target.",
                              onHeaderTap: () => _openMetricDetail(
                                TempoMetricKind.minutes,
                                sourceContext: cardCtx,
                              ),
                              onDayTap: _selectDate,
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

class _HeroMetricSummary extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final String goal;
  final VoidCallback onTap;

  const _HeroMetricSummary({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.goal,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 13.5),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.textSecondary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  goal,
                  style: TextStyle(
                    color: c.textTertiary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WeeklyMetricCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String currentValue;
  final String currentSubtitle;
  final String lastWeekAvg;
  final List<DateTime> weekDays;
  final List<int> values;
  final int goal;
  final int selectedDayIndex;
  final DateTime todayDate;
  final String calloutText;
  final VoidCallback onHeaderTap;
  final ValueChanged<DateTime> onDayTap;

  const _WeeklyMetricCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.currentValue,
    required this.currentSubtitle,
    required this.lastWeekAvg,
    required this.weekDays,
    required this.values,
    required this.goal,
    required this.selectedDayIndex,
    required this.todayDate,
    required this.calloutText,
    required this.onHeaderTap,
    required this.onDayTap,
  });

  double _computeNiceAxisMax() {
    final peakVal = values.fold<int>(goal, (m, v) => v > m ? v : m);
    final raw = math.max(peakVal.toDouble(), goal.toDouble()) * 1.25;
    if (raw <= 100) return ((raw / 20).ceil() * 20).clamp(40, 120).toDouble();
    if (raw <= 1000) return ((raw / 200).ceil() * 200).toDouble();
    if (raw <= 10000) return ((raw / 2500).ceil() * 2500).toDouble();
    return ((raw / 5000).ceil() * 5000).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final axisMax = _computeNiceAxisMax();
    const dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final tickCount = 4;
    final ticks = List.generate(
      tickCount + 1,
      (i) => (axisMax * (tickCount - i) / tickCount).round(),
    );

    return RepaintBoundary(
      child: AppleCard(
        borderRadius: 24,
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onHeaderTap,
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: Colors.white, size: 17),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 16.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                Icon(
                  CupertinoIcons.chevron_right,
                  size: 16,
                  color: c.textTertiary,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Current Value vs Last Week Daily Average
          Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    Text(
                      currentValue,
                      style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      currentSubtitle,
                      style: TextStyle(
                        color: c.textSecondary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      lastWeekAvg,
                      style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Daily avg last week',
                      style: TextStyle(
                        color: c.textSecondary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Weekly Bar Chart + Right Y-Axis
          SizedBox(
            height: 166,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (_, constraints) {
                      return Stack(
                        children: [
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _WeeklyGoalGridPainter(
                                axisMax: axisMax,
                                goal: goal.toDouble(),
                                goalColor: color,
                                gridColor: c.divider,
                                borderColor: c.cardBorder,
                              ),
                            ),
                          ),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: List.generate(7, (i) {
                              final v = values[i];
                              final frac =
                                  (v / axisMax).clamp(0.0, 1.0);
                              final barH = v > 0
                                  ? math.max(
                                      6.0,
                                      constraints.maxHeight * frac,
                                    )
                                  : 0.0;
                              final isFuture = weekDays[i].isAfter(todayDate);
                              return Expanded(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: isFuture
                                      ? null
                                      : () => onDayTap(weekDays[i]),
                                  child: Align(
                                    alignment: Alignment.bottomCenter,
                                    child: AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 320),
                                      curve: Curves.easeOutCubic,
                                      width: 10,
                                      height: barH,
                                      decoration: BoxDecoration(
                                        color: color,
                                        borderRadius:
                                            const BorderRadius.vertical(
                                          top: Radius.circular(6),
                                          bottom: Radius.circular(3),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 44,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final t in ticks)
                        Text(
                          NumberFormat('#,###').format(t),
                          style: TextStyle(
                            color: c.textTertiary,
                            fontSize: 10.5,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Mon-Sun Labels & Circular Goal Checkmark / Progress Badges
          Padding(
            padding: const EdgeInsets.only(right: 52),
            child: Row(
              children: List.generate(7, (i) {
                final day = weekDays[i];
                final v = values[i];
                final progress = goal > 0 ? (v / goal).clamp(0.0, 1.0) : 0.0;
                final metGoal = v >= goal && goal > 0;
                final isSelected = i == selectedDayIndex;
                final isFuture = day.isAfter(todayDate);

                return Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: isFuture ? null : () => onDayTap(day),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected ? color : Colors.transparent,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            dayLabels[i],
                            style: TextStyle(
                              color: isSelected
                                  ? Colors.white
                                  : c.textTertiary,
                              fontSize: 10.5,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        _DayGoalBadge(
                          dayNumber: day.day,
                          progress: progress,
                          metGoal: metGoal,
                          color: color,
                          isFuture: isFuture,
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),

          const SizedBox(height: 16),

          // Goal Coaching Callout Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: c.searchBg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              calloutText,
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }
}

class _DayGoalBadge extends StatelessWidget {
  final int dayNumber;
  final double progress;
  final bool metGoal;
  final Color color;
  final bool isFuture;

  const _DayGoalBadge({
    required this.dayNumber,
    required this.progress,
    required this.metGoal,
    required this.color,
    required this.isFuture,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    if (metGoal) {
      return Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
        child: const Icon(
          CupertinoIcons.checkmark_alt,
          color: Colors.white,
          size: 16,
        ),
      );
    }

    return SizedBox(
      width: 26,
      height: 26,
      child: CustomPaint(
        painter: _DayProgressRingPainter(
          progress: progress,
          color: color,
          trackColor: c.isDark
              ? Colors.white.withValues(alpha: 0.14)
              : Colors.black.withValues(alpha: 0.10),
        ),
        child: Center(
          child: Text(
            '$dayNumber',
            style: TextStyle(
              color: isFuture
                  ? c.textTertiary.withValues(alpha: 0.5)
                  : c.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }
}

class _DayProgressRingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color trackColor;

  const _DayProgressRingPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 1.5;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..isAntiAlias = true,
    );

    if (progress > 0.01) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        2 * math.pi * progress.clamp(0.0, 1.0),
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..strokeCap = StrokeCap.round
          ..isAntiAlias = true,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DayProgressRingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.trackColor != trackColor;
}

class _WeeklyGoalGridPainter extends CustomPainter {
  final double axisMax;
  final double goal;
  final Color goalColor;
  final Color gridColor;
  final Color borderColor;

  const _WeeklyGoalGridPainter({
    required this.axisMax,
    required this.goal,
    required this.goalColor,
    required this.gridColor,
    required this.borderColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Subtle outer frame
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );

    // 3 interior dotted horizontal grid lines
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.9;
    for (int i = 1; i <= 3; i++) {
      final y = size.height * (i / 4);
      _drawDashedLine(canvas, y, size.width, gridPaint, dash: 3, gap: 4);
    }

    // Colored dashed horizontal Goal Line
    final goalFrac = (goal / axisMax).clamp(0.0, 1.0);
    final goalY = size.height * (1.0 - goalFrac);
    final goalPaint = Paint()
      ..color = goalColor.withValues(alpha: 0.78)
      ..strokeWidth = 1.25;
    _drawDashedLine(canvas, goalY, size.width, goalPaint, dash: 5, gap: 3.5);
  }

  void _drawDashedLine(
    Canvas canvas,
    double y,
    double width,
    Paint paint, {
    required double dash,
    required double gap,
  }) {
    double x = 0;
    while (x < width) {
      final end = math.min(x + dash, width);
      canvas.drawLine(Offset(x, y), Offset(end, y), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _WeeklyGoalGridPainter oldDelegate) =>
      oldDelegate.axisMax != axisMax ||
      oldDelegate.goal != goal ||
      oldDelegate.goalColor != goalColor ||
      oldDelegate.gridColor != gridColor;
}

class _GoalSliderRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String valueText;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final Color color;
  final ValueChanged<double> onChanged;

  const _GoalSliderRow({
    required this.icon,
    required this.label,
    required this.valueText,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      decoration: BoxDecoration(
        color: c.searchBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: c.isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.045),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.white, size: 14),
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: c.isDark ? 0.22 : 0.13),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  valueText,
                  style: TextStyle(
                    color: color,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
              activeTrackColor: color,
              inactiveTrackColor: c.divider,
              thumbColor: color,
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: (v) {
                HapticFeedback.selectionClick();
                onChanged(v);
              },
            ),
          ),
        ],
      ),
    );
  }
}
