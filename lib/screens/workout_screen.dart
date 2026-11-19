import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/exercise_data2.dart';
import '../data/fitness_journey_workouts.dart';
import '../models/local_profile.dart';
import '../models/workout_model.dart';
import '../services/active_profile_provider.dart';
import '../services/tempo_rust_db.dart';
import '../theme/app_colors.dart';
import '../widgets/ios_stretch_sheet.dart';
import '../widgets/liquid_glass_surface.dart';
import '../widgets/tempo_sliver_header.dart';
import 'fitness_journey_detail_screen.dart';
import 'workout_detail_screen.dart';

class _QuickWorkoutMeta {
  final String journeyId;
  final String shortLabel;
  final String journeyName;
  final String subtitle;
  final String thumb;
  final Color color;
  final IconData icon;

  const _QuickWorkoutMeta({
    required this.journeyId,
    required this.shortLabel,
    required this.journeyName,
    required this.subtitle,
    required this.thumb,
    required this.color,
    required this.icon,
  });
}

class WorkoutScreen extends StatefulWidget {
  final bool showChatbot;
  final int refreshVersion;
  final VoidCallback? onOpenHistory;

  const WorkoutScreen({
    super.key,
    this.showChatbot = false,
    this.refreshVersion = 0,
    this.onOpenHistory,
  });

  @override
  State<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen>
    with SingleTickerProviderStateMixin {
  final TempoRustDb _db = TempoRustDb.instance;
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  late final AnimationController _searchAnimCtrl;
  late final Animation<double> _searchSizeAnim;
  late final Animation<double> _searchFadeAnim;

  String _selectedCategory = 'All';
  String _searchQuery = '';
  bool _showSearch = false;

  Map<String, LocalJourneyProgress> _journeyProgress = {};
  List<LocalCompletedWorkout> _completedWorkouts = [];
  Set<String> _completedWorkoutIds = {};

  static const List<_QuickWorkoutMeta> _quickWorkouts = [
    _QuickWorkoutMeta(
      journeyId: weightLossJourneyId,
      shortLabel: 'HIIT Burn',
      journeyName: 'Weight Loss',
      subtitle: 'High-burn HIIT & metabolic conditioning',
      thumb: 'assets/thumbnails/Journeys/journey_weight_loss_thumb.png',
      color: Color(0xFF4AD95A),
      icon: Icons.directions_run_rounded,
    ),
    _QuickWorkoutMeta(
      journeyId: strengthPowerJourneyId,
      shortLabel: 'Strength',
      journeyName: 'Strength & Power',
      subtitle: 'Compound lifts & explosive power',
      thumb: 'assets/thumbnails/Journeys/journey_strength_power_thumb.png',
      color: Color(0xFF8FE032),
      icon: Icons.fitness_center_rounded,
    ),
    _QuickWorkoutMeta(
      journeyId: cardioJourneyId,
      shortLabel: 'Cardio',
      journeyName: 'Cardio',
      subtitle: 'Intervals, steady-state & endurance',
      thumb: 'assets/thumbnails/Journeys/journey_cardio_thumb.png',
      color: Color(0xFF54A4FF),
      icon: Icons.directions_bike_rounded,
    ),
    _QuickWorkoutMeta(
      journeyId: muscularEnduranceJourneyId,
      shortLabel: 'Endurance',
      journeyName: 'Muscular Endurance',
      subtitle: 'High-rep stamina & core resilience',
      thumb: 'assets/thumbnails/Journeys/journey_muscular_endurance_thumb.png',
      color: Color(0xFFF7C23C),
      icon: Icons.directions_walk_rounded,
    ),
    _QuickWorkoutMeta(
      journeyId: healthWellnessJourneyId,
      shortLabel: 'Mobility',
      journeyName: 'General Health',
      subtitle: 'Mobility, core stability & active recovery',
      thumb: 'assets/thumbnails/Journeys/journey_health_wellness_thumb.png',
      color: Color(0xFFF7C23C),
      icon: Icons.accessibility_new_rounded,
    ),
  ];

  static const List<String> _categories = [
    'All',
    'Chest',
    'Back',
    'Shoulders',
    'Arms',
    'Abs',
    'Legs',
  ];

  @override
  void initState() {
    super.initState();
    _searchAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      reverseDuration: const Duration(milliseconds: 220),
    );
    _searchSizeAnim = CurvedAnimation(
      parent: _searchAnimCtrl,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _searchFadeAnim = CurvedAnimation(
      parent: _searchAnimCtrl,
      curve: const Interval(0.12, 1.0, curve: Curves.easeOutCubic),
      reverseCurve: const Interval(0.0, 0.78, curve: Curves.easeIn),
    );
    _loadProgress();
  }

  @override
  void didUpdateWidget(covariant WorkoutScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshVersion != oldWidget.refreshVersion) {
      _loadProgress();
    }
  }

  @override
  void dispose() {
    _searchAnimCtrl.dispose();
    _searchFocus.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    HapticFeedback.selectionClick();
    final opening = !_showSearch;
    setState(() {
      _showSearch = opening;
      if (!opening) {
        _searchFocus.unfocus();
        _searchCtrl.clear();
        _searchQuery = '';
      }
    });
    if (opening) {
      _searchAnimCtrl.forward().then((_) {
        if (mounted && _showSearch) _searchFocus.requestFocus();
      });
    } else {
      _searchAnimCtrl.reverse();
    }
  }

  Future<void> _loadProgress() async {
    final pid = context.read<ActiveProfileProvider>().activeProfileId;
    if (pid == null) return;
    final results = await Future.wait([
      _db.getJourneyProgress(pid),
      _db.getCompletedWorkouts(pid, limit: 200),
    ]);
    if (!mounted) return;
    final jList = results[0] as List<LocalJourneyProgress>;
    final completed = (results[1] as List<LocalCompletedWorkout>)
        .where((c) => !c.isCheated)
        .toList();

    setState(() {
      _journeyProgress = {for (final j in jList) j.journeyId: j};
      _completedWorkouts = completed;
      _completedWorkoutIds = completed.map((c) => c.workoutId).toSet();
    });
  }

  bool _matchesCategory(Workout w, String cat) {
    if (cat == 'All') return true;
    final focus = w.bodyFocus.toLowerCase();
    final c = cat.toLowerCase();
    if (c == 'arms') {
      return focus.contains('arm') ||
          focus.contains('bicep') ||
          focus.contains('tricep') ||
          focus.contains('forearm');
    }
    if (c == 'legs') {
      return focus.contains('leg') ||
          focus.contains('quad') ||
          focus.contains('glute') ||
          focus.contains('hamstring') ||
          focus.contains('calv');
    }
    if (c == 'abs') {
      return focus.contains('abs') || focus.contains('core');
    }
    return focus.contains(c);
  }

  List<Workout> get _filteredWorkouts {
    final q = _searchQuery.trim().toLowerCase();
    return exerciseWorkouts.where((w) {
      if (!_matchesCategory(w, _selectedCategory)) return false;
      if (q.isEmpty) return true;
      return w.title.toLowerCase().contains(q) ||
          w.bodyFocus.toLowerCase().contains(q) ||
          w.level.toLowerCase().contains(q);
    }).toList();
  }

  String _formatDuration(int totalSec) {
    if (totalSec <= 0) return '0 mins';
    final mins = totalSec ~/ 60;
    final secs = totalSec % 60;
    if (mins == 0) return '$secs secs';
    if (secs == 0) return '$mins mins';
    return '$mins mins $secs secs';
  }

  void _openHistorySheet() {
    HapticFeedback.selectionClick();
    if (widget.onOpenHistory != null && _completedWorkouts.isEmpty) {
      widget.onOpenHistory!();
      return;
    }
    showTempoSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final mc = AppColors.of(ctx);
        final sheetH = MediaQuery.sizeOf(ctx).height * 0.68;
        return Container(
          height: sheetH,
          decoration: BoxDecoration(
            color: mc.card,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: mc.cardBorder),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: mc.divider,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Row(
                  children: [
                    Text(
                      'Workout History',
                      style: TextStyle(
                        color: mc.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${_completedWorkouts.length} total',
                      style: TextStyle(
                        color: mc.textSecondary,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: mc.divider),
              Expanded(
                child: _completedWorkouts.isEmpty
                    ? Center(
                        child: Text(
                          'No completed workouts yet.',
                          style: TextStyle(
                            color: mc.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(20),
                        itemCount: _completedWorkouts.length,
                        separatorBuilder: (_, __) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Divider(height: 1, color: mc.divider),
                        ),
                        itemBuilder: (_, i) {
                          final item = _completedWorkouts[i];
                          return _HistoryRowContent(
                            item: item,
                            formattedDuration:
                                _formatDuration(item.actualDurationSec),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final workouts = _filteredWorkouts;
    final latestWorkout =
        _completedWorkouts.isNotEmpty ? _completedWorkouts.first : null;

    return Scaffold(
      backgroundColor: c.scaffold,
      body: RefreshIndicator(
        color: c.accent,
        edgeOffset: MediaQuery.paddingOf(context).top + 56,
        onRefresh: _loadProgress,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            const TempoSliverHeader(title: 'Workout'),

            // 1. Quick-Start Activity Squircles (Mi Fitness / HyperOS 3 top row)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _quickWorkouts.map((q) {
                    final isActive =
                        _journeyProgress[q.journeyId]?.isSelected == true;
                    return Expanded(
                      child: _QuickWorkoutTile(
                        meta: q,
                        isActive: isActive,
                        onTap: () async {
                          HapticFeedback.selectionClick();
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => FitnessJourneyDetailScreen(
                                journeyId: q.journeyId,
                                journeyName: q.journeyName,
                                journeySubtitle: q.subtitle,
                                thumbnailAsset: q.thumb,
                              ),
                            ),
                          );
                          if (mounted) _loadProgress();
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

            // 2. History Card
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              sliver: SliverToBoxAdapter(
                child: AppleCard(
                  borderRadius: 24,
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _openHistorySheet,
                        child: Row(
                          children: [
                            Text(
                              'History',
                              style: TextStyle(
                                color: c.textPrimary,
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.2,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              'All',
                              style: TextStyle(
                                color: c.textSecondary,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 2),
                            Icon(
                              CupertinoIcons.chevron_right,
                              size: 14,
                              color: c.textTertiary,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Divider(height: 1, color: c.divider),
                      const SizedBox(height: 16),
                      if (latestWorkout != null)
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _openHistorySheet,
                          child: _HistoryRowContent(
                            item: latestWorkout,
                            formattedDuration: _formatDuration(
                              latestWorkout.actualDurationSec,
                            ),
                          ),
                        )
                      else
                        Row(
                          children: [
                            Container(
                              width: 46,
                              height: 46,
                              decoration: const BoxDecoration(
                                color: Color(0xFFF7C23C),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.directions_walk_rounded,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'No workouts recorded yet',
                                    style: TextStyle(
                                      color: c.textPrimary,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'Complete a guided session below to track your history',
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
                    ],
                  ),
                ),
              ),
            ),

            // 3. Exercise Library Header + Collapsible Search + Clean Monochrome Chips
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
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
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _toggleSearch,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _showSearch
                                  ? c.accent.withValues(
                                      alpha: c.isDark ? 0.22 : 0.12,
                                    )
                                  : Colors.transparent,
                            ),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              switchInCurve: Curves.easeOutBack,
                              switchOutCurve: Curves.easeIn,
                              transitionBuilder: (child, anim) =>
                                  RotationTransition(
                                turns: Tween<double>(begin: 0.78, end: 1.0)
                                    .animate(anim),
                                child: ScaleTransition(
                                  scale: anim,
                                  child: FadeTransition(
                                    opacity: anim,
                                    child: child,
                                  ),
                                ),
                              ),
                              child: Icon(
                                _showSearch
                                    ? CupertinoIcons.xmark
                                    : CupertinoIcons.search,
                                key: ValueKey(_showSearch),
                                size: _showSearch ? 16 : 19,
                                color: _showSearch
                                    ? c.accent
                                    : c.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    ClipRect(
                      child: SizeTransition(
                        sizeFactor: _searchSizeAnim,
                        axisAlignment: -1.0,
                        child: FadeTransition(
                          opacity: _searchFadeAnim,
                          child: ScaleTransition(
                            scale: Tween<double>(begin: 0.94, end: 1.0)
                                .animate(_searchSizeAnim),
                            alignment: Alignment.topRight,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: Container(
                                height: 44,
                                decoration: BoxDecoration(
                                  color: c.searchBg,
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: c.isDark
                                        ? Colors.white.withValues(alpha: 0.08)
                                        : Colors.black.withValues(alpha: 0.06),
                                  ),
                                ),
                                child: TextField(
                                  controller: _searchCtrl,
                                  focusNode: _searchFocus,
                                  onChanged: (v) =>
                                      setState(() => _searchQuery = v),
                                  textAlignVertical: TextAlignVertical.center,
                                  style: TextStyle(
                                    color: c.textPrimary,
                                    fontSize: 15,
                                  ),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    filled: false,
                                    border: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    prefixIcon: Icon(
                                      CupertinoIcons.search,
                                      color: c.textTertiary,
                                      size: 17,
                                    ),
                                    suffixIcon: _searchQuery.isNotEmpty
                                        ? GestureDetector(
                                            behavior: HitTestBehavior.opaque,
                                            onTap: () {
                                              HapticFeedback.selectionClick();
                                              _searchCtrl.clear();
                                              setState(() => _searchQuery = '');
                                            },
                                            child: Icon(
                                              CupertinoIcons.xmark_circle_fill,
                                              color: c.textTertiary,
                                              size: 17,
                                            ),
                                          )
                                        : null,
                                    hintText: 'Search workouts or muscles...',
                                    hintStyle: TextStyle(
                                      color: c.textTertiary,
                                      fontSize: 14.5,
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 11,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 36,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _categories.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (_, idx) {
                          final cat = _categories[idx];
                          final selected = cat == _selectedCategory;
                          return GestureDetector(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() => _selectedCategory = cat);
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 15,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: selected ? c.textPrimary : c.card,
                                borderRadius: BorderRadius.circular(99),
                                border: Border.all(
                                  color: selected
                                      ? c.textPrimary
                                      : c.cardBorder,
                                ),
                              ),
                              child: Text(
                                cat,
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
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 5. Guided Workout Cards List
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
              sliver: workouts.isEmpty
                  ? SliverToBoxAdapter(
                      child: AppleCard(
                        borderRadius: 22,
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              'No workouts match your filter.',
                              style: TextStyle(color: c.textSecondary),
                            ),
                          ),
                        ),
                      ),
                    )
                  : SliverList.separated(
                      itemCount: workouts.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (ctx, i) {
                        final w = workouts[i];
                        final isDone = _completedWorkoutIds.contains(w.id);
                        return _WorkoutLibraryCard(
                          workout: w,
                          isCompleted: isDone,
                          onTap: () async {
                            HapticFeedback.selectionClick();
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => WorkoutDetailScreen(workout: w),
                              ),
                            );
                            if (mounted) _loadProgress();
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tactile vibrant squircle activity launcher matching the Mi Fitness top bar.
class _QuickWorkoutTile extends StatefulWidget {
  final _QuickWorkoutMeta meta;
  final bool isActive;
  final VoidCallback onTap;

  const _QuickWorkoutTile({
    required this.meta,
    required this.isActive,
    required this.onTap,
  });

  @override
  State<_QuickWorkoutTile> createState() => _QuickWorkoutTileState();
}

class _QuickWorkoutTileState extends State<_QuickWorkoutTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.92 : 1.0,
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOutCubic,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: widget.meta.color,
                borderRadius: BorderRadius.circular(18),
                border: widget.isActive
                    ? Border.all(color: c.textPrimary, width: 2)
                    : null,
              ),
              child: Icon(
                widget.meta.icon,
                color: Colors.white,
                size: 28,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                widget.meta.shortLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 12,
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

class _HistoryRowContent extends StatelessWidget {
  final LocalCompletedWorkout item;
  final String formattedDuration;

  const _HistoryRowContent({
    required this.item,
    required this.formattedDuration,
  });

  IconData _iconFor(String focus, String title) {
    final lower = '${focus.toLowerCase()} ${title.toLowerCase()}';
    if (lower.contains('walk')) return Icons.directions_walk_rounded;
    if (lower.contains('bike') || lower.contains('cycl')) {
      return Icons.directions_bike_rounded;
    }
    if (lower.contains('run') || lower.contains('cardio') || lower.contains('hiit')) {
      return Icons.directions_run_rounded;
    }
    if (lower.contains('mobil') || lower.contains('yoga') || lower.contains('stretch')) {
      return Icons.accessibility_new_rounded;
    }
    return Icons.fitness_center_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final dateLabel = DateFormat('MMMM d').format(item.completedAt.toLocal());
    final mins = (item.actualDurationSec / 60).ceil().clamp(1, 360);
    final headline = item.durationLabel.isNotEmpty
        ? '${item.title} | ${item.durationLabel}'
        : '${item.title} | $mins min';
    final sub = [
      formattedDuration,
      if (item.caloriesBurned > 0) '${item.caloriesBurned} kcal',
      dateLabel,
    ].join(' · ');
    final source = item.bodyFocus.isNotEmpty
        ? 'Tempo · ${item.bodyFocus}'
        : 'Recorded on Tempo';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: const BoxDecoration(
            color: Color(0xFFF7C23C),
            shape: BoxShape.circle,
          ),
          child: Icon(
            _iconFor(item.bodyFocus, item.title),
            color: Colors.white,
            size: 23,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                headline,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 16.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: c.textSecondary,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                source,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: c.textTertiary,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WorkoutLibraryCard extends StatelessWidget {
  final Workout workout;
  final bool isCompleted;
  final VoidCallback onTap;

  const _WorkoutLibraryCard({
    required this.workout,
    required this.isCompleted,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);

    return AppleCard(
      borderRadius: 20,
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.asset(
              workout.thumbnailAsset,
              width: 68,
              height: 68,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 68,
                height: 68,
                color: c.searchBg,
                child: Icon(
                  Icons.directions_run_rounded,
                  color: c.textSecondary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
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
                    if (isCompleted) ...[
                      const SizedBox(width: 6),
                      Icon(
                        CupertinoIcons.checkmark_alt,
                        color: c.textPrimary,
                        size: 16,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${workout.level} · ${workout.bodyFocus}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.textSecondary,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${workout.duration} · ${workout.exerciseList.length} exercises',
                  style: TextStyle(
                    color: c.textTertiary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Icon(
            CupertinoIcons.chevron_right,
            color: c.textTertiary,
            size: 16,
          ),
        ],
      ),
    );
  }
}
