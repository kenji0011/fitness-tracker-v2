import 'dart:io';
import 'dart:ui';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/local_profile.dart';
import '../services/active_profile_provider.dart';
import '../services/progress_tracking_service.dart';
import '../services/tempo_rust_db.dart';
import '../services/workout_history_service.dart';
import '../theme/app_colors.dart';
import '../widgets/liquid_glass_surface.dart';
import '../widgets/tempo_sliver_header.dart';
import 'progress_album_screen.dart';

class ProgressTrackingScreen extends StatefulWidget {
  final bool embedded;
  final int refreshVersion;

  const ProgressTrackingScreen({
    super.key,
    this.embedded = false,
    this.refreshVersion = 0,
  });

  @override
  State<ProgressTrackingScreen> createState() => _ProgressTrackingScreenState();
}

class _ProgressTrackingScreenState extends State<ProgressTrackingScreen>
    with SingleTickerProviderStateMixin {
  String _selectedCategory = 'All';
  int _selectedSegment = 0; // 0 = Exercise PRs, 1 = Sessions
  int _rangeIndex = 0; // 0 = 7D, 1 = 14D, 2 = 30D
  int? _touchedBarIndex;
  int? _expandedCardIndex;
  bool _loading = true;

  int _currentStreak = 0;
  int _longestStreak = 0;
  int _photoCount = 0;
  String? _latestPhotoPath;
  ExerciseRecord? _highestWeight;
  List<ExerciseRecord> _records = [];
  List<WorkoutHistory> _workoutHistory = [];
  List<LocalDailyActivity> _dailyHistory = [];
  Set<String> _workoutDayKeys = {};

  late final AnimationController _entranceController;

  static const _categories = [
    'All',
    'Chest',
    'Back',
    'Shoulders',
    'Arms',
    'Abs',
    'Legs',
  ];

  static const _rangeDays = [7, 14, 30];
  static const _rangeLabels = ['7D', '14D', '30D'];

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 780),
    );
    _load();
  }

  @override
  void didUpdateWidget(covariant ProgressTrackingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshVersion != oldWidget.refreshVersion) {
      _load();
    }
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final pid = context.read<ActiveProfileProvider>().activeProfileId;
    if (pid == null) return;

    final progressService = ProgressTrackingService(profileId: pid);
    final historyService = WorkoutHistoryService(profileId: pid);
    final db = TempoRustDb.instance;

    final results = await Future.wait([
      progressService.getCurrentStreak(),
      progressService.getLongestStreak(),
      progressService.getHighestWeightRecord(),
      progressService.getExerciseRecordsByCategory(_selectedCategory),
      historyService.getWorkoutHistory(),
      db.listProgressPhotos(pid),
      db.getDailyActivityHistory(pid, limit: 30),
    ]);

    if (!mounted) return;
    final photos = results[5] as List<LocalProgressPhoto>;
    final workouts = results[4] as List<WorkoutHistory>;
    final dayKeys = workouts
        .where((w) => !w.isCheated)
        .map((w) => DateFormat('yyyy-MM-dd').format(w.completedAt.toLocal()))
        .toSet();

    setState(() {
      _currentStreak = results[0] as int;
      _longestStreak = results[1] as int;
      _highestWeight = results[2] as ExerciseRecord?;
      _records = results[3] as List<ExerciseRecord>;
      _workoutHistory = workouts;
      _photoCount = photos.length;
      _latestPhotoPath = photos.isNotEmpty ? photos.first.filePath : null;
      _dailyHistory = results[6] as List<LocalDailyActivity>;
      _workoutDayKeys = dayKeys;
      _loading = false;
    });
    _entranceController.forward(from: 0);
  }

  List<_ChartDay> _buildRangeSeries() {
    final days = _rangeDays[_rangeIndex];
    final now = DateTime.now();
    final byDate = {for (final d in _dailyHistory) d.dateKey: d};
    return List.generate(days, (i) {
      final dt = now.subtract(Duration(days: days - 1 - i));
      final key = DateFormat('yyyy-MM-dd').format(dt);
      final entry = byDate[key];
      return _ChartDay(
        date: dt,
        calories: entry?.calories ?? 0,
        minutes: entry?.minutes ?? 0,
        steps: entry?.steps ?? 0,
        workouts: entry?.workoutsCount ?? 0,
      );
    });
  }

  Widget _stagger(int slot, Widget child) {
    final start = (slot * 0.10).clamp(0.0, 0.55);
    final end = (start + 0.45).clamp(0.0, 1.0);
    final anim = CurvedAnimation(
      parent: _entranceController,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: anim,
      builder: (context, c) => Opacity(
        opacity: anim.value,
        child: Transform.translate(
          offset: Offset(0, 18 * (1.0 - anim.value)),
          child: c,
        ),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final series = _buildRangeSeries();
    final totalRangeKcal = series.fold<int>(0, (s, d) => s + d.calories);
    final totalRangeMins = series.fold<int>(0, (s, d) => s + d.minutes);

    return Scaffold(
      backgroundColor: c.scaffold,
      body: _loading
          ? Center(child: CupertinoActivityIndicator(color: c.accent))
          : RefreshIndicator(
              color: c.accent,
              edgeOffset: MediaQuery.paddingOf(context).top + 56,
              onRefresh: _load,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  TempoSliverHeader(
                    title: 'Progress',
                    showBackButton: !widget.embedded,
                    actions: [
                      TempoHeaderAction(
                        tooltip: 'Progress Album',
                        icon: Icon(
                          CupertinoIcons.photo_on_rectangle,
                          size: 20,
                          color: c.textPrimary,
                        ),
                        onPressed: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ProgressAlbumScreen(),
                            ),
                          );
                          if (mounted) _load();
                        },
                      ),
                    ],
                  ),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      18,
                      8,
                      18,
                      widget.embedded ? 124 : 36,
                    ),
                    sliver: SliverList.list(
                      children: [
                        // 1. Hero Momentum & Weekly Consistency Card
                        _stagger(
                          0,
                          _MomentumHeroCard(
                            currentStreak: _currentStreak,
                            longestStreak: _longestStreak,
                            totalWorkouts: _workoutHistory
                                .where((w) => !w.isCheated)
                                .length,
                            workoutDayKeys: _workoutDayKeys,
                          ),
                        ),
                        const SizedBox(height: 14),

                        // 2. Interactive Animated Activity Trend Card (7D / 14D / 30D)
                        _stagger(
                          1,
                          _ActivityTrendCard(
                            series: series,
                            rangeIndex: _rangeIndex,
                            rangeLabels: _rangeLabels,
                            totalKcal: totalRangeKcal,
                            totalMins: totalRangeMins,
                            touchedIndex: _touchedBarIndex,
                            onRangeChanged: (idx) {
                              HapticFeedback.selectionClick();
                              setState(() {
                                _rangeIndex = idx;
                                _touchedBarIndex = null;
                              });
                            },
                            onTouchBar: (idx) {
                              if (idx != _touchedBarIndex && idx != null) {
                                HapticFeedback.selectionClick();
                              }
                              setState(() => _touchedBarIndex = idx);
                            },
                          ),
                        ),
                        const SizedBox(height: 14),

                        // 3. 2-Column Bento Highlights (Top Lift PR + Private Photo Album Preview)
                        _stagger(
                          2,
                          Row(
                            children: [
                              Expanded(
                                child: _TopLiftBentoCard(
                                  highestWeight: _highestWeight,
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    setState(() => _selectedSegment = 0);
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _PhotoAlbumBentoCard(
                                  photoCount: _photoCount,
                                  latestPhotoPath: _latestPhotoPath,
                                  onTap: () async {
                                    HapticFeedback.selectionClick();
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const ProgressAlbumScreen(),
                                      ),
                                    );
                                    if (mounted) _load();
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 22),

                        // 4. iOS 27 Liquid Glass Sliding Segmented Control
                        _stagger(
                          3,
                          _LiquidGlassSegmentBar(
                            selectedIndex: _selectedSegment,
                            labels: [
                              'Exercise PRs (${_records.length})',
                              'Sessions (${_workoutHistory.length})',
                            ],
                            onChanged: (idx) {
                              HapticFeedback.selectionClick();
                              setState(() {
                                _selectedSegment = idx;
                                _expandedCardIndex = null;
                              });
                            },
                          ),
                        ),
                        const SizedBox(height: 14),

                        // 5. Animated Tab Body (Exercise PRs or Session Timeline)
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 280),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (child, anim) => FadeTransition(
                            opacity: anim,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0, 0.04),
                                end: Offset.zero,
                              ).animate(anim),
                              child: child,
                            ),
                          ),
                          child: _selectedSegment == 0
                              ? _buildExerciseSection(c)
                              : _buildSessionsSection(c),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildExerciseSection(AppColors c) {
    final maxWeight = _records.isEmpty
        ? 1.0
        : _records
            .map((r) => r.weightUsed)
            .reduce((a, b) => a > b ? a : b)
            .clamp(1.0, double.infinity);

    return Column(
      key: const ValueKey('segment_exercises'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Category filter pills
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _categories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, idx) {
              final cat = _categories[idx];
              final selected = cat == _selectedCategory;
              return _AnimatedFilterChip(
                label: cat,
                selected: selected,
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _selectedCategory = cat;
                    _expandedCardIndex = null;
                  });
                  _load();
                },
              );
            },
          ),
        ),
        const SizedBox(height: 14),
        if (_records.isEmpty)
          _EmptyProgressCard(
            icon: CupertinoIcons.chart_bar,
            title: 'No Exercise Records Yet',
            subtitle:
                'Open any workout, tap an exercise, and log your sets, reps, and weight to track personal records here.',
          )
        else
          ..._records.asMap().entries.map((entry) {
            final idx = entry.key;
            final r = entry.value;
            final isTopPr = _highestWeight != null &&
                r.exerciseName == _highestWeight!.exerciseName &&
                r.weightUsed == _highestWeight!.weightUsed &&
                r.weightUsed > 0;
            final isExpanded = _expandedCardIndex == idx;

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ExpandableExerciseCard(
                record: r,
                maxWeight: maxWeight,
                isTopPr: isTopPr,
                isExpanded: isExpanded,
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _expandedCardIndex = isExpanded ? null : idx;
                  });
                },
              ),
            );
          }),
      ],
    );
  }

  Widget _buildSessionsSection(AppColors c) {
    if (_workoutHistory.isEmpty) {
      return const _EmptyProgressCard(
        key: ValueKey('segment_sessions_empty'),
        icon: CupertinoIcons.flame,
        title: 'No Completed Sessions Yet',
        subtitle:
            'Complete a guided workout in the Workout tab to build your streak and training timeline.',
      );
    }

    return Column(
      key: const ValueKey('segment_sessions'),
      children: _workoutHistory.asMap().entries.map((entry) {
        final idx = entry.key;
        final item = entry.value;
        final isExpanded = _expandedCardIndex == idx;

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _ExpandableSessionCard(
            item: item,
            isExpanded: isExpanded,
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() {
                _expandedCardIndex = isExpanded ? null : idx;
              });
            },
          ),
        );
      }).toList(),
    );
  }
}

class _ChartDay {
  final DateTime date;
  final int calories;
  final int minutes;
  final int steps;
  final int workouts;

  const _ChartDay({
    required this.date,
    required this.calories,
    required this.minutes,
    required this.steps,
    required this.workouts,
  });
}

/// Hero consistency card with animated count-up streak + 7-day calendar strip.
class _MomentumHeroCard extends StatelessWidget {
  final int currentStreak;
  final int longestStreak;
  final int totalWorkouts;
  final Set<String> workoutDayKeys;

  const _MomentumHeroCard({
    required this.currentStreak,
    required this.longestStreak,
    required this.totalWorkouts,
    required this.workoutDayKeys,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final now = DateTime.now();
    // Monday..Sunday of current week
    final monday = now.subtract(Duration(days: now.weekday - 1));

    return AppleCard(
      borderRadius: 24,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          CupertinoIcons.flame,
                          size: 15,
                          color: currentStreak > 0
                              ? c.textPrimary
                              : c.textSecondary,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'Streak',
                          style: TextStyle(
                            color: c.textSecondary,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.1,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    TweenAnimationBuilder<double>(
                      tween: Tween<double>(
                        begin: 0,
                        end: currentStreak.toDouble(),
                      ),
                      duration: const Duration(milliseconds: 650),
                      curve: Curves.easeOutCubic,
                      builder: (_, val, __) => Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            '${val.round()}',
                            style: TextStyle(
                              color: c.textPrimary,
                              fontSize: 34,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -1.1,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            val.round() == 1 ? 'day' : 'days',
                            style: TextStyle(
                              color: c.textSecondary,
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Clean typographic stat pair with hairline divider
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _MinimalStatColumn(
                    label: 'Best',
                    value: '${longestStreak}d',
                  ),
                  Container(
                    width: 1,
                    height: 28,
                    margin: const EdgeInsets.symmetric(horizontal: 14),
                    color: c.divider,
                  ),
                  _MinimalStatColumn(
                    label: 'Total',
                    value: '$totalWorkouts',
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(height: 1, color: c.divider),
          const SizedBox(height: 14),
          // 7-day consistency indicator strip (Mon - Sun)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(7, (i) {
              final day = monday.add(Duration(days: i));
              final key = DateFormat('yyyy-MM-dd').format(day);
              final isToday = DateFormat('yyyy-MM-dd').format(now) == key;
              final done = workoutDayKeys.contains(key);
              final dayLetter = DateFormat('E').format(day).substring(0, 1);

              return Column(
                children: [
                  AnimatedContainer(
                    duration: Duration(milliseconds: 260 + i * 45),
                    curve: Curves.easeOutCubic,
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: done
                          ? c.textPrimary
                          : (c.isDark
                              ? Colors.white.withValues(alpha: 0.055)
                              : Colors.black.withValues(alpha: 0.04)),
                      border: Border.all(
                        color: done
                            ? c.textPrimary
                            : (isToday
                                ? c.textPrimary.withValues(alpha: 0.72)
                                : Colors.transparent),
                        width: 1.4,
                      ),
                    ),
                    child: Center(
                      child: done
                          ? Icon(
                              CupertinoIcons.checkmark_alt,
                              color: c.isDark ? Colors.black : Colors.white,
                              size: 16,
                            )
                          : Text(
                              '${day.day}',
                              style: TextStyle(
                                color: isToday ? c.textPrimary : c.textTertiary,
                                fontSize: 12,
                                fontWeight:
                                    isToday ? FontWeight.w700 : FontWeight.w600,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    dayLetter,
                    style: TextStyle(
                      color: isToday ? c.textPrimary : c.textTertiary,
                      fontSize: 11,
                      fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _MinimalStatColumn extends StatelessWidget {
  final String label;
  final String value;

  const _MinimalStatColumn({
    required this.label,
    required this.value,
  });

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
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// Interactive bar chart card with animated 7D / 14D / 30D glass switcher & touch scrub readout.
class _ActivityTrendCard extends StatelessWidget {
  final List<_ChartDay> series;
  final int rangeIndex;
  final List<String> rangeLabels;
  final int totalKcal;
  final int totalMins;
  final int? touchedIndex;
  final ValueChanged<int> onRangeChanged;
  final ValueChanged<int?> onTouchBar;

  const _ActivityTrendCard({
    required this.series,
    required this.rangeIndex,
    required this.rangeLabels,
    required this.totalKcal,
    required this.totalMins,
    required this.touchedIndex,
    required this.onRangeChanged,
    required this.onTouchBar,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final selectedDay = (touchedIndex != null &&
            touchedIndex! >= 0 &&
            touchedIndex! < series.length)
        ? series[touchedIndex!]
        : null;

    final maxVal = series
        .map((e) => e.calories.toDouble())
        .fold<double>(250, (a, b) => a > b ? a : b) *
        1.2;

    return AppleCard(
      borderRadius: 24,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      selectedDay != null
                          ? DateFormat('EEE, MMM d').format(selectedDay.date)
                          : 'Energy Burned',
                      style: TextStyle(
                        color: selectedDay != null
                            ? c.textPrimary
                            : c.textSecondary,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.1,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          NumberFormat('#,###').format(
                            selectedDay?.calories ?? totalKcal,
                          ),
                          style: TextStyle(
                            color: c.textPrimary,
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.8,
                            fontFeatures: const [
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'kcal · ${selectedDay?.minutes ?? totalMins} min',
                          style: TextStyle(
                            color: c.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Compact sliding timeframe pill (7D / 14D / 30D)
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: c.searchBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(rangeLabels.length, (i) {
                    final sel = i == rangeIndex;
                    return GestureDetector(
                      onTap: () => onRangeChanged(i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: sel ? c.card : Colors.transparent,
                          borderRadius: BorderRadius.circular(9),
                          boxShadow: sel && !c.isDark
                              ? [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.06),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : null,
                        ),
                        child: Text(
                          rangeLabels[i],
                          style: TextStyle(
                            color: sel ? c.textPrimary : c.textTertiary,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 138,
            child: BarChart(
              swapAnimationDuration: const Duration(milliseconds: 380),
              swapAnimationCurve: Curves.easeOutCubic,
              BarChartData(
                maxY: maxVal,
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => Colors.transparent,
                    tooltipPadding: EdgeInsets.zero,
                    getTooltipItem: (_, __, ___, ____) => null,
                  ),
                  touchCallback: (event, response) {
                    if (!event.isInterestedForInteractions ||
                        response == null ||
                        response.spot == null) {
                      if (event is FlTapUpEvent || event is FlPanEndEvent) {
                        onTouchBar(null);
                      }
                      return;
                    }
                    onTouchBar(response.spot!.touchedBarGroupIndex);
                  },
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: maxVal / 3,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: c.divider,
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      getTitlesWidget: (val, _) {
                        final idx = val.toInt();
                        if (idx < 0 || idx >= series.length) {
                          return const SizedBox.shrink();
                        }
                        // Show clean non-crowded date labels
                        final step = series.length <= 7
                            ? 1
                            : (series.length <= 14 ? 3 : 7);
                        if (idx != series.length - 1 && idx % step != 0) {
                          return const SizedBox.shrink();
                        }
                        final label = series.length <= 7
                            ? DateFormat('E')
                                .format(series[idx].date)
                                .substring(0, 1)
                            : DateFormat('M/d').format(series[idx].date);
                        final isHighlighted =
                            idx == touchedIndex || idx == series.length - 1;
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            label,
                            style: TextStyle(
                              color:
                                  isHighlighted ? c.textPrimary : c.textTertiary,
                              fontSize: 11,
                              fontWeight: isHighlighted
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: List.generate(series.length, (i) {
                  final v = series[i].calories.toDouble();
                  final isTouched = i == touchedIndex;
                  final barWidth = series.length <= 7
                      ? 18.0
                      : (series.length <= 14 ? 10.0 : 5.5);
                  return BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: v > 0 ? v : maxVal * 0.016,
                        width: barWidth,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(5),
                          bottom: Radius.circular(2),
                        ),
                        color: v > 0
                            ? (isTouched
                                ? c.textPrimary
                                : c.accent)
                            : c.divider,
                      ),
                    ],
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tactile press-scaling wrapper for iOS 27 bento tiles.
class _TactileScaleCard extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const _TactileScaleCard({required this.child, required this.onTap});

  @override
  State<_TactileScaleCard> createState() => _TactileScaleCardState();
}

class _TactileScaleCardState extends State<_TactileScaleCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

class _TopLiftBentoCard extends StatelessWidget {
  final ExerciseRecord? highestWeight;
  final VoidCallback onTap;

  const _TopLiftBentoCard({
    required this.highestWeight,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final weight = highestWeight?.weightUsed ?? 0.0;

    return _TactileScaleCard(
      onTap: onTap,
      child: AppleCard(
        borderRadius: 24,
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          height: 112,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    CupertinoIcons.chart_bar,
                    color: c.textPrimary,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Top Lift',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: c.textSecondary,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.1,
                      ),
                    ),
                  ),
                  Icon(
                    CupertinoIcons.chevron_right,
                    size: 13,
                    color: c.textTertiary,
                  ),
                ],
              ),
              const Spacer(),
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: weight),
                duration: const Duration(milliseconds: 650),
                curve: Curves.easeOutCubic,
                builder: (_, val, __) => Text(
                  weight > 0 ? '${val.toStringAsFixed(1)} kg' : '-- kg',
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.7,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                highestWeight != null && weight > 0
                    ? highestWeight!.exerciseName
                    : 'Log weighted sets',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: c.textTertiary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoAlbumBentoCard extends StatelessWidget {
  final int photoCount;
  final String? latestPhotoPath;
  final VoidCallback onTap;

  const _PhotoAlbumBentoCard({
    required this.photoCount,
    required this.latestPhotoPath,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final hasThumb = !kIsWeb &&
        latestPhotoPath != null &&
        latestPhotoPath!.isNotEmpty &&
        File(latestPhotoPath!).existsSync();

    return _TactileScaleCard(
      onTap: onTap,
      child: hasThumb
          ? Container(
              height: 144,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: c.cardBorder),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(File(latestPhotoPath!), fit: BoxFit.cover),
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.05),
                            Colors.black.withValues(alpha: 0.72),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 14,
                      right: 14,
                      bottom: 14,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Photo Album',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            '$photoCount private ${photoCount == 1 ? 'photo' : 'photos'}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            )
          : AppleCard(
              borderRadius: 24,
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                height: 112,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          CupertinoIcons.photo_on_rectangle,
                          color: c.textPrimary,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Photos',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: c.textSecondary,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.1,
                            ),
                          ),
                        ),
                        Icon(
                          CupertinoIcons.chevron_right,
                          size: 13,
                          color: c.textTertiary,
                        ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      '$photoCount ${photoCount == 1 ? 'photo' : 'photos'}',
                      style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.7,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'On-device album',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: c.textTertiary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// iOS 27 Liquid Glass sliding segmented control with spring-gliding glass pill.
class _LiquidGlassSegmentBar extends StatelessWidget {
  final int selectedIndex;
  final List<String> labels;
  final ValueChanged<int> onChanged;

  const _LiquidGlassSegmentBar({
    required this.selectedIndex,
    required this.labels,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      height: 46,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.isDark
            ? const Color(0xFF1C1C1E)
            : Colors.black.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.cardBorder),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final segW = constraints.maxWidth / labels.length;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                left: selectedIndex * segW,
                top: 0,
                bottom: 0,
                width: segW,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                    child: Container(
                      decoration: BoxDecoration(
                        color: c.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: c.isDark
                              ? Colors.white.withValues(alpha: 0.14)
                              : Colors.white,
                        ),
                        boxShadow: c.isDark
                            ? null
                            : [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.07),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                      ),
                    ),
                  ),
                ),
              ),
              Row(
                children: List.generate(labels.length, (i) {
                  final sel = i == selectedIndex;
                  return Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onChanged(i),
                      child: Center(
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 200),
                          style: TextStyle(
                            color: sel ? c.textPrimary : c.textSecondary,
                            fontSize: 13.5,
                            fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                          ),
                          child: Text(labels[i]),
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
    );
  }
}

class _AnimatedFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _AnimatedFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? c.textPrimary : c.card,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: selected ? c.textPrimary : c.cardBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected
                ? (c.isDark ? Colors.black : Colors.white)
                : c.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _ExpandableExerciseCard extends StatelessWidget {
  final ExerciseRecord record;
  final double maxWeight;
  final bool isTopPr;
  final bool isExpanded;
  final VoidCallback onTap;

  const _ExpandableExerciseCard({
    required this.record,
    required this.maxWeight,
    required this.isTopPr,
    required this.isExpanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final ratio = record.weightUsed > 0
        ? (record.weightUsed / maxWeight).clamp(0.12, 1.0)
        : 0.35;
    final estVolume =
        record.weightUsed * record.setsPerformed * record.repsPerformed;

    return AppleCard(
      borderRadius: 20,
      padding: const EdgeInsets.all(15),
      onTap: onTap,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              record.exerciseName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: c.textPrimary,
                                fontSize: 15.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (isTopPr) ...[
                            const SizedBox(width: 7),
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
                                'PR',
                                style: TextStyle(
                                  color: c.textPrimary,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${record.bodyFocus.isNotEmpty ? record.bodyFocus : 'Workout'} · ${record.setsPerformed} × ${record.repsPerformed} reps',
                        style: TextStyle(
                          color: c.textSecondary,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  record.weightUsed > 0
                      ? '${record.weightUsed.toStringAsFixed(1)} kg'
                      : 'Bodyweight',
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 6),
                AnimatedRotation(
                  turns: isExpanded ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 220),
                  child: Icon(
                    CupertinoIcons.chevron_down,
                    size: 14,
                    color: c.textTertiary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: ratio),
                duration: const Duration(milliseconds: 520),
                curve: Curves.easeOutCubic,
                builder: (_, v, __) => LinearProgressIndicator(
                  value: v,
                  minHeight: 3.5,
                  backgroundColor: c.divider,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isTopPr ? c.textPrimary : c.accent,
                  ),
                ),
              ),
            ),
            if (isExpanded) ...[
              const SizedBox(height: 12),
              Divider(height: 1, color: c.divider),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _detailPair(
                    'Date',
                    record.timestamp != null
                        ? DateFormat('MMM d, h:mm a')
                            .format(record.timestamp!.toLocal())
                        : 'Recent',
                    c,
                  ),
                  _detailPair(
                    'Volume',
                    estVolume > 0
                        ? '${estVolume.toStringAsFixed(0)} kg'
                        : '${record.setsPerformed * record.repsPerformed} reps',
                    c,
                  ),
                  _detailPair(
                    'Level',
                    record.level.isNotEmpty ? record.level : 'Standard',
                    c,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _detailPair(String label, String val, AppColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: c.textTertiary, fontSize: 11),
        ),
        const SizedBox(height: 2),
        Text(
          val,
          style: TextStyle(
            color: c.textPrimary,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _ExpandableSessionCard extends StatelessWidget {
  final WorkoutHistory item;
  final bool isExpanded;
  final VoidCallback onTap;

  const _ExpandableSessionCard({
    required this.item,
    required this.isExpanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final mins = (item.actualDuration / 60).ceil().clamp(1, 300);

    return AppleCard(
      borderRadius: 20,
      padding: const EdgeInsets.all(15),
      onTap: onTap,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: Column(
          children: [
            Row(
              children: [
                SizedBox(
                  width: 38,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        DateFormat('MMM')
                            .format(item.completedAt.toLocal())
                            .toUpperCase(),
                        style: TextStyle(
                          color: c.textTertiary,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.4,
                        ),
                      ),
                      Text(
                        DateFormat('d').format(item.completedAt.toLocal()),
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          height: 1.15,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 1,
                  height: 30,
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  color: c.divider,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.workout.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$mins min · ${DateFormat('h:mm a').format(item.completedAt.toLocal())}',
                        style: TextStyle(
                          color: c.textSecondary,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                AnimatedRotation(
                  turns: isExpanded ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 220),
                  child: Icon(
                    CupertinoIcons.chevron_down,
                    size: 14,
                    color: c.textTertiary,
                  ),
                ),
              ],
            ),
            if (isExpanded) ...[
              const SizedBox(height: 12),
              Divider(height: 1, color: c.divider),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Focus: ${item.workout.bodyFocus}',
                    style: TextStyle(
                      color: c.textSecondary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'Level: ${item.workout.level}',
                    style: TextStyle(
                      color: c.accent,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyProgressCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptyProgressCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return AppleCard(
      borderRadius: 24,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 26),
      child: Column(
        children: [
          Icon(icon, color: c.textTertiary, size: 28),
          const SizedBox(height: 10),
          Text(
            title,
            style: TextStyle(
              color: c.textPrimary,
              fontSize: 15.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: c.textSecondary,
              fontSize: 13,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}
