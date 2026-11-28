import 'dart:io';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:jiggicons/jiggicons.dart';
import 'package:provider/provider.dart';

import '../models/local_profile.dart';
import '../services/active_profile_provider.dart';
import '../services/progress_tracking_service.dart';
import '../services/tempo_rust_db.dart';
import '../services/weight_unit_helper.dart';
import '../services/workout_history_service.dart';
import '../theme/app_colors.dart';
import '../widgets/bitchord_segmented_slider.dart';
import '../widgets/liquid_glass_surface.dart';
import '../widgets/streak_heatmap_card.dart';
import '../widgets/tempo_jigg_icon.dart';
import '../widgets/tempo_morph_route.dart';
import '../widgets/tempo_sliver_header.dart';
import '../widgets/tempo_spotlight_tour.dart';
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
  String _weightUnit = 'kg';
  ExerciseRecord? _highestWeight;
  List<ExerciseRecord> _records = [];
  List<WorkoutHistory> _workoutHistory = [];
  List<LocalDailyActivity> _dailyHistory = [];
  Set<String> _workoutDayKeys = {};

  late final AnimationController _entranceController;
  bool _wasTickerEnabled = false;
  bool _needsRefresh = false;
  bool _hasPlayedEntrance = false;
  final GlobalKey _albumHintKey = GlobalKey();
  final GlobalKey _trendCardHintKey = GlobalKey();

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
  void didChangeDependencies() {
    super.didChangeDependencies();
    final enabled = TickerMode.of(context);
    if (enabled && !_wasTickerEnabled) {
      if (_needsRefresh) {
        _needsRefresh = false;
        _load();
      } else if (!_loading) {
        _maybeShowSpotlight();
      }
    }
    _wasTickerEnabled = enabled;
  }

  void _maybeShowSpotlight() {
    final pid = context.read<ActiveProfileProvider>().activeProfileId;
    if (pid == null || pid.isEmpty) return;
    TempoSpotlightTour.showIfNeeded(
      context: context,
      profileId: pid,
      screenId: 'progress',
      steps: [
        TempoSpotlightStep(
          targetKey: _albumHintKey,
          title: 'Progress photos & compare',
          description:
              'Save private check-in photos and compare Before & After with an interactive slider.',
          borderRadius: 999,
          padding: const EdgeInsets.all(6),
        ),
        TempoSpotlightStep(
          targetKey: _trendCardHintKey,
          title: 'Trends & streak heatmap',
          description:
              'Switch 7D, 14D, or 30D to inspect calories, your 12-week activity heatmap, and exercise PRs.',
          borderRadius: 24,
        ),
      ],
    );
  }

  @override
  void didUpdateWidget(covariant ProgressTrackingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshVersion != oldWidget.refreshVersion) {
      if (TickerMode.of(context)) {
        _needsRefresh = false;
        _load();
      } else {
        _needsRefresh = true;
      }
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
      db.getDailyActivityHistory(pid, limit: 90),
      WeightUnitHelper.loadUnit(pid),
    ]);

    if (!mounted) return;
    final photos = results[5] as List<LocalProgressPhoto>;
    final workouts = results[4] as List<WorkoutHistory>;
    final unit = results[7] as String;
    final dayKeys = workouts
        .where((w) => !w.isCheated)
        .map((w) => DateFormat('yyyy-MM-dd').format(w.completedAt.toLocal()))
        .toSet();

    setState(() {
      _weightUnit = unit;
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
    if (!_hasPlayedEntrance) {
      _hasPlayedEntrance = true;
      _entranceController.forward(from: 0);
    }
    if (mounted && TickerMode.of(context)) {
      _maybeShowSpotlight();
    }
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
      builder: (context, c) {
        if (anim.value >= 0.999) return c!;
        return Opacity(
          opacity: anim.value,
          child: Transform.translate(
            offset: Offset(0, 18 * (1.0 - anim.value)),
            child: c,
          ),
        );
      },
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
                        buttonKey: _albumHintKey,
                        tooltip: 'Progress Album',
                        icon: TempoJiggIcon(
                          'camera',
                          variant: JiggIconVariant.outline,
                          size: 20,
                          color: c.textPrimary,
                          trigger: JiggIconTrigger.none,
                          fallbackIcon: CupertinoIcons.photo_on_rectangle,
                        ),
                        onPressed: () async {
                          await pushTempoMorphRoute<void>(
                            context: context,
                            sourceKey: _albumHintKey,
                            sourceBorderRadius: 999,
                            builder: (_) => const ProgressAlbumScreen(),
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
                          SizedBox(
                            key: _trendCardHintKey,
                            child: _ActivityTrendCard(
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
                        ),
                        const SizedBox(height: 14),

                        // 2B. 12-Week Activity & Streak Heatmap Calendar
                        _stagger(
                          1,
                          StreakHeatmapCard(
                            dailyHistory: _dailyHistory,
                            workoutDayKeys: _workoutDayKeys,
                            currentStreak: _currentStreak,
                            longestStreak: _longestStreak,
                          ),
                        ),
                        const SizedBox(height: 14),

                        // 3. Overhauled 2-Column Liquid Glass Bento Highlights
                        _stagger(
                          2,
                          Row(
                            children: [
                              Expanded(
                                child: _TopLiftBentoCard(
                                  highestWeight: _highestWeight,
                                  weightUnit: _weightUnit,
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    setState(() => _selectedSegment = 0);
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Builder(
                                  builder: (cardCtx) => _PhotoAlbumBentoCard(
                                    photoCount: _photoCount,
                                    latestPhotoPath: _latestPhotoPath,
                                    onTap: () async {
                                      HapticFeedback.selectionClick();
                                      await pushTempoMorphRoute<void>(
                                        context: context,
                                        sourceContext: cardCtx,
                                        sourceBorderRadius: 26,
                                        builder: (_) =>
                                            const ProgressAlbumScreen(),
                                      );
                                      if (mounted) _load();
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // 4. Training Records Hub Header & Liquid Glass Segmented Slider
                        _stagger(
                          3,
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                                child: Row(
                                  children: [
                                    Text(
                                      'Training Records',
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
                                        color: c.accent.withValues(
                                          alpha: c.isDark ? 0.18 : 0.11,
                                        ),
                                        borderRadius: BorderRadius.circular(99),
                                      ),
                                      child: Text(
                                        _selectedSegment == 0
                                            ? '${_records.length} ${_records.length == 1 ? 'record' : 'records'}'
                                            : '${_workoutHistory.where((w) => !w.isCheated).length} verified',
                                        style: TextStyle(
                                          color: c.accent,
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
                              BitChordSegmentedSlider(
                                height: 46,
                                showTrackBorder: true,
                                selectedIndex: _selectedSegment,
                                labels: [
                                  'Exercise PRs (${_records.length})',
                                  'Sessions (${_workoutHistory.length})',
                                ],
                                onChanged: (idx) {
                                  setState(() {
                                    _selectedSegment = idx;
                                    _expandedCardIndex = null;
                                  });
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),

                        // 5. Animated Tab Body (Exercise PRs or Verified Session Timeline)
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 240),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (child, anim) => SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, 0.03),
                              end: Offset.zero,
                            ).animate(anim),
                            child: FadeTransition(
                              opacity: anim,
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
                weightUnit: _weightUnit,
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
              // Compact BitChord Liquid Glass timeframe slider (7D / 14D / 30D)
              SizedBox(
                width: 126,
                child: BitChordSegmentedSlider(
                  height: 30,
                  fontSize: 11.5,
                  labels: rangeLabels,
                  selectedIndex: rangeIndex,
                  trackColor: c.searchBg,
                  thumbColor: c.isDark ? const Color(0xFF2E3038) : c.card,
                  onChanged: onRangeChanged,
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
  final String weightUnit;
  final VoidCallback onTap;

  const _TopLiftBentoCard({
    required this.highestWeight,
    required this.weightUnit,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final weightKg = highestWeight?.weightUsed ?? 0.0;
    final displayWeight = WeightUnitHelper.toDisplay(weightKg, weightUnit);

    return LiquidGlassSurface(
      borderRadius: 26,
      blurEnabled: false,
      padding: const EdgeInsets.all(16),
      onTap: onTap,
      child: SizedBox(
        height: 128,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.accent.withValues(alpha: c.isDark ? 0.22 : 0.13),
                  ),
                  child: Icon(
                    CupertinoIcons.rosette,
                    color: c.accent,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 8),
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
              tween: Tween<double>(begin: 0, end: displayWeight),
              duration: const Duration(milliseconds: 650),
              curve: Curves.easeOutCubic,
              builder: (_, val, __) => Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Flexible(
                    child: Text(
                      weightKg > 0 ? val.toStringAsFixed(1) : '--',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 27,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.9,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    weightUnit,
                    style: TextStyle(
                      color: c.textSecondary,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 5),
            Text(
              highestWeight != null && weightKg > 0
                  ? highestWeight!.exerciseName
                  : 'Log weighted sets',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.textTertiary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
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

    if (hasThumb) {
      return _TactileScaleCard(
        onTap: onTap,
        child: TempoTouchLightEffect(
          borderRadius: 26,
          emitLight: true,
          receiveScatter: true,
          intensity: 0.9,
          child: Container(
            height: 160,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: c.isDark ? 0.34 : 0.10),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(26),
              child: CustomPaint(
                foregroundPainter: LiquidGlassRimPainter(
                  borderRadius: 26,
                  isDark: true,
                  intensity: 0.95,
                  strokeWidth: 1.2,
                  showTopMeniscus: false,
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(File(latestPhotoPath!), fit: BoxFit.cover),
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.52),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.24),
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          '$photoCount ${photoCount == 1 ? 'photo' : 'photos'}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 10,
                      right: 10,
                      bottom: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.56),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.22),
                            width: 0.8,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Photo Album',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'Private on-device album',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.78),
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return LiquidGlassSurface(
      borderRadius: 26,
      blurEnabled: false,
      padding: const EdgeInsets.all(16),
      onTap: onTap,
      child: SizedBox(
        height: 128,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF56B7FF)
                        .withValues(alpha: c.isDark ? 0.22 : 0.14),
                  ),
                  child: const Icon(
                    CupertinoIcons.photo_on_rectangle,
                    color: Color(0xFF56B7FF),
                    size: 15,
                  ),
                ),
                const SizedBox(width: 8),
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '$photoCount',
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 27,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.9,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  photoCount == 1 ? 'photo' : 'photos',
                  style: TextStyle(
                    color: c.textSecondary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              'Private on-device album',
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
    );
  }
}

class _AnimatedFilterChip extends StatefulWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _AnimatedFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_AnimatedFilterChip> createState() => _AnimatedFilterChipState();
}

class _AnimatedFilterChipState extends State<_AnimatedFilterChip> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        child: TempoTouchLightEffect(
          borderRadius: 999,
          isAccentSurface: widget.selected,
          emitLight: true,
          receiveScatter: true,
          cancelOnScroll: true,
          intensity: 0.92,
          child: CustomPaint(
            foregroundPainter: LiquidGlassRimPainter(
              borderRadius: 999,
              isDark: c.isDark,
              intensity: widget.selected ? 1.05 : 0.78,
              strokeWidth: 1.0,
              showTopMeniscus: false,
              tintColor: widget.selected ? c.accent : null,
            ),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
              decoration: BoxDecoration(
                color: widget.selected
                    ? c.accent
                    : (c.isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.white.withValues(alpha: 0.82)),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                widget.label,
                style: TextStyle(
                  color: widget.selected ? Colors.white : c.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ExpandableExerciseCard extends StatelessWidget {
  final ExerciseRecord record;
  final double maxWeight;
  final String weightUnit;
  final bool isTopPr;
  final bool isExpanded;
  final VoidCallback onTap;

  const _ExpandableExerciseCard({
    required this.record,
    required this.maxWeight,
    required this.weightUnit,
    required this.isTopPr,
    required this.isExpanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final ratio = record.weightUsed > 0
        ? (record.weightUsed / maxWeight).clamp(0.14, 1.0)
        : 0.35;
    final estVolumeKg =
        record.weightUsed * record.setsPerformed * record.repsPerformed;
    final estVolumeDisplay =
        WeightUnitHelper.toDisplay(estVolumeKg, weightUnit);
    final focusText =
        record.bodyFocus.isNotEmpty ? record.bodyFocus : 'Workout';

    return LiquidGlassSurface(
      borderRadius: 22,
      blurEnabled: false,
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
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isTopPr
                        ? c.accent.withValues(alpha: c.isDark ? 0.24 : 0.14)
                        : (c.isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.black.withValues(alpha: 0.05)),
                  ),
                  child: Icon(
                    isTopPr ? CupertinoIcons.rosette : CupertinoIcons.bolt_fill,
                    color: isTopPr ? c.accent : c.textSecondary,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
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
                                letterSpacing: -0.2,
                              ),
                            ),
                          ),
                          if (isTopPr) ...[
                            const SizedBox(width: 7),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: c.accent.withValues(
                                  alpha: c.isDark ? 0.24 : 0.14,
                                ),
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: Text(
                                'TOP PR',
                                style: TextStyle(
                                  color: c.accent,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            focusText,
                            style: TextStyle(
                              color: c.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color: c.isDark
                                  ? Colors.white.withValues(alpha: 0.07)
                                  : Colors.black.withValues(alpha: 0.045),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              '${record.setsPerformed} × ${record.repsPerformed} reps',
                              style: TextStyle(
                                color: c.textSecondary,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      record.weightUsed > 0
                          ? WeightUnitHelper.format(
                              record.weightUsed,
                              weightUnit,
                            )
                          : 'Bodyweight',
                      style: TextStyle(
                        color: isTopPr ? c.accent : c.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 3),
                    AnimatedRotation(
                      turns: isExpanded ? 0.5 : 0.0,
                      duration: const Duration(milliseconds: 220),
                      child: Icon(
                        CupertinoIcons.chevron_down,
                        size: 13,
                        color: c.textTertiary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 11),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: ratio),
                duration: const Duration(milliseconds: 520),
                curve: Curves.easeOutCubic,
                builder: (_, v, __) => LinearProgressIndicator(
                  value: v,
                  minHeight: 4.5,
                  backgroundColor: c.divider,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isTopPr ? c.accent : c.accent.withValues(alpha: 0.65),
                  ),
                ),
              ),
            ),
            if (isExpanded) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _RecessedStatTile(
                      label: 'Date',
                      value: record.timestamp != null
                          ? DateFormat('MMM d')
                              .format(record.timestamp!.toLocal())
                          : 'Recent',
                      c: c,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _RecessedStatTile(
                      label: 'Volume',
                      value: estVolumeKg > 0
                          ? '${estVolumeDisplay.toStringAsFixed(0)} $weightUnit'
                          : '${record.setsPerformed * record.repsPerformed} reps',
                      c: c,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _RecessedStatTile(
                      label: 'Level',
                      value:
                          record.level.isNotEmpty ? record.level : 'Standard',
                      c: c,
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
    final isVerified = !item.isCheated;
    final statusColor =
        isVerified ? const Color(0xFF34C759) : c.textSecondary;

    return LiquidGlassSurface(
      borderRadius: 22,
      blurEnabled: false,
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 46,
                  decoration: BoxDecoration(
                    color: isVerified
                        ? c.accent.withValues(alpha: c.isDark ? 0.20 : 0.11)
                        : (c.isDark
                            ? Colors.white.withValues(alpha: 0.07)
                            : Colors.black.withValues(alpha: 0.045)),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        DateFormat('MMM')
                            .format(item.completedAt.toLocal())
                            .toUpperCase(),
                        style: TextStyle(
                          color: isVerified ? c.accent : c.textTertiary,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                        ),
                      ),
                      Text(
                        DateFormat('d').format(item.completedAt.toLocal()),
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 16.5,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
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
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(
                                alpha: c.isDark ? 0.20 : 0.12,
                              ),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              isVerified ? 'Verified' : 'Ended early',
                              style: TextStyle(
                                color: statusColor,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '$mins min',
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
                          Flexible(
                            child: Text(
                              DateFormat('h:mm a')
                                  .format(item.completedAt.toLocal()),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: c.textTertiary,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                AnimatedRotation(
                  turns: isExpanded ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 220),
                  child: Icon(
                    CupertinoIcons.chevron_down,
                    size: 13.5,
                    color: c.textTertiary,
                  ),
                ),
              ],
            ),
            if (isExpanded) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _RecessedStatTile(
                      label: 'Focus',
                      value: item.workout.bodyFocus,
                      c: c,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _RecessedStatTile(
                      label: 'Level',
                      value: item.workout.level,
                      accent: true,
                      c: c,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _RecessedStatTile(
                      label: 'Status',
                      value: isVerified ? 'Verified' : 'Partial',
                      c: c,
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

class _RecessedStatTile extends StatelessWidget {
  final String label;
  final String value;
  final bool accent;
  final AppColors c;

  const _RecessedStatTile({
    required this.label,
    required this.value,
    required this.c,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: c.isDark
            ? Colors.white.withValues(alpha: 0.055)
            : Colors.black.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: c.textTertiary,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: accent ? c.accent : c.textPrimary,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
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
    return LiquidGlassSurface(
      borderRadius: 26,
      blurEnabled: false,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 28),
      child: Column(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.accent.withValues(alpha: c.isDark ? 0.18 : 0.11),
            ),
            child: Icon(icon, color: c.accent, size: 24),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(
              color: c.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 6),
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
