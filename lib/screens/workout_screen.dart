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
import '../services/animation_speed_service.dart';
import '../services/tempo_rust_db.dart';
import '../theme/app_colors.dart';
import '../widgets/ios_stretch_sheet.dart';
import '../widgets/liquid_glass_surface.dart';
import '../widgets/tempo_morph_route.dart';
import '../widgets/tempo_sliver_header.dart';
import '../widgets/tempo_spotlight_tour.dart';
import '../widgets/tempo_spring_physics.dart';
import '../widgets/tempo_toast.dart';
import '../widgets/workout_program_card.dart';
import 'custom_workout_builder_screen.dart';
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
  List<Workout> _customWorkouts = [];
  bool _wasTickerEnabled = false;
  bool _needsRefresh = false;

  final GlobalKey _journeysHintKey = GlobalKey();
  final GlobalKey _customWorkoutHintKey = GlobalKey();
  late final List<WorkoutProgramGroup> _builtInPrograms =
      groupExerciseWorkouts(exerciseWorkouts);
  final Map<String, String> _selectedLevelByGroup = {};
  late final Map<String, GlobalKey> _quickIconKeys = {
    for (final q in _quickWorkouts) q.journeyId: GlobalKey(),
  };

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
    'Custom',
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
      duration: TempoAnimationSpeedService.instance.scale(
        const Duration(milliseconds: 320),
      ),
      reverseDuration: TempoAnimationSpeedService.instance.scale(
        const Duration(milliseconds: 240),
      ),
    );
    _searchSizeAnim = CurvedAnimation(
      parent: _searchAnimCtrl,
      curve: TempoSpringCurves.morphOpen,
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    final enabled = TickerMode.of(context);
    if (enabled && !_wasTickerEnabled) {
      if (_needsRefresh) {
        _needsRefresh = false;
        _loadProgress();
      }
      _maybeShowSpotlight();
    }
    _wasTickerEnabled = enabled;
  }

  void _maybeShowSpotlight() {
    final pid = context.read<ActiveProfileProvider>().activeProfileId;
    if (pid == null || pid.isEmpty) return;
    TempoSpotlightTour.showIfNeeded(
      context: context,
      profileId: pid,
      screenId: 'workout',
      steps: [
        TempoSpotlightStep(
          targetKey: _journeysHintKey,
          title: 'Guided training journeys',
          description:
              'Pick a structured program like HIIT Burn, Strength, or Cardio with offline video demos.',
          borderRadius: 20,
        ),
        TempoSpotlightStep(
          targetKey: _customWorkoutHintKey,
          title: 'Build custom routines',
          description:
              'Tap + Custom to combine your favorite exercises from Tempo’s offline library.',
          borderRadius: 999,
          padding: const EdgeInsets.all(6),
        ),
      ],
    );
  }

  @override
  void didUpdateWidget(covariant WorkoutScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshVersion != oldWidget.refreshVersion) {
      if (TickerMode.of(context)) {
        _needsRefresh = false;
        _loadProgress();
      } else {
        _needsRefresh = true;
      }
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
    _searchAnimCtrl.duration = TempoAnimationSpeedService.instance.scale(
      const Duration(milliseconds: 320),
    );
    _searchAnimCtrl.reverseDuration = TempoAnimationSpeedService.instance.scale(
      const Duration(milliseconds: 240),
    );
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
      CustomWorkoutsStore.load(pid),
    ]);
    if (!mounted) return;
    final jList = results[0] as List<LocalJourneyProgress>;
    final completed = (results[1] as List<LocalCompletedWorkout>)
        .where((c) => !c.isCheated)
        .toList();
    final custom = results[2] as List<Workout>;

    setState(() {
      _journeyProgress = {for (final j in jList) j.journeyId: j};
      _completedWorkouts = completed;
      _completedWorkoutIds = completed.map((c) => c.workoutId).toSet();
      _customWorkouts = custom;
    });
  }

  Future<void> _openCustomBuilder({
    Workout? existing,
    BuildContext? sourceContext,
    double sourceBorderRadius = 24,
  }) async {
    HapticFeedback.selectionClick();
    final saved = await pushTempoMorphRoute<bool>(
      context: context,
      sourceContext: sourceContext,
      sourceBorderRadius: sourceBorderRadius,
      builder: (_) => CustomWorkoutBuilderScreen(existing: existing),
    );
    if (saved == true && mounted) {
      _loadProgress();
    }
  }

  Future<void> _showCustomWorkoutActions(Workout workout) async {
    HapticFeedback.selectionClick();
    final c = AppColors.of(context, listen: false);
    final action = await showTempoSheet<String>(
      context: context,
      backgroundColor: c.card,
      borderRadius: 28,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              workout.title,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${workout.duration} · ${workout.exerciseList.length} exercises',
              style: TextStyle(color: c.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 48,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: c.accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () => Navigator.of(ctx).pop('edit'),
                child: const Text(
                  'Edit routine',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 48,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: c.moveRed,
                  side: BorderSide(color: c.moveRed.withValues(alpha: 0.35)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () => Navigator.of(ctx).pop('delete'),
                child: const Text(
                  'Delete routine',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (!mounted || action == null) return;
    if (action == 'edit') {
      await _openCustomBuilder(existing: workout);
    } else if (action == 'delete') {
      final pid = context.read<ActiveProfileProvider>().activeProfileId;
      if (pid == null) return;
      final remaining = _customWorkouts
          .where((item) => item.id != workout.id)
          .toList();
      await CustomWorkoutsStore.save(pid, remaining);
      if (mounted) {
        setState(() => _customWorkouts = remaining);
        showTempoToast(context, 'Deleted "${workout.title}"');
      }
    }
  }

  bool _matchesCategory(WorkoutProgramGroup group, String cat) {
    if (cat == 'All') return true;
    if (cat == 'Custom') return group.isCustom;
    final focus = group.bodyFocus.toLowerCase();
    final c = cat.toLowerCase();
    if (c == 'back') {
      return focus.contains('back') || focus.contains('trap');
    }
    if (c == 'shoulders') {
      return focus.contains('shoulder') || focus.contains('trap');
    }
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

  List<({WorkoutProgramGroup group, String? matchedLevel})>
      get _filteredPrograms {
    final q = _searchQuery.trim().toLowerCase();
    final combined = <WorkoutProgramGroup>[
      ..._customWorkouts.map(WorkoutProgramGroup.custom),
      ..._builtInPrograms,
    ];

    final results = <({WorkoutProgramGroup group, String? matchedLevel})>[];
    for (final group in combined) {
      if (!_matchesCategory(group, _selectedCategory)) continue;
      if (q.isEmpty) {
        results.add((group: group, matchedLevel: null));
        continue;
      }

      // Check direct level match or individual exercise name match so cards
      // automatically surface the matching difficulty variant!
      String? levelMatch;
      for (final v in group.variants) {
        if (v.level.toLowerCase().contains(q) ||
            v.exerciseList.any((ex) => ex.name.toLowerCase().contains(q))) {
          levelMatch = v.level;
          break;
        }
      }

      final metaMatch = group.title.toLowerCase().contains(q) ||
          group.bodyFocus.toLowerCase().contains(q) ||
          group.variants.any((v) => v.title.toLowerCase().contains(q));

      if (metaMatch || levelMatch != null) {
        results.add((group: group, matchedLevel: levelMatch));
      }
    }
    return results;
  }

  String _formatCompactDuration(int totalSec) {
    if (totalSec <= 0) return '0m';
    if (totalSec < 60) return '${totalSec}s';
    final totalMins = (totalSec / 60).round();
    if (totalMins < 60) return '${totalMins}m';
    final hrs = totalMins ~/ 60;
    final rem = totalMins % 60;
    return rem == 0 ? '${hrs}h' : '${hrs}h ${rem}m';
  }

  void _openHistorySheet() {
    HapticFeedback.selectionClick();
    if (widget.onOpenHistory != null && _completedWorkouts.isEmpty) {
      widget.onOpenHistory!();
      return;
    }
    final totalSec = _completedWorkouts.fold<int>(
      0,
      (sum, w) => sum + w.actualDurationSec,
    );
    final totalKcal = _completedWorkouts.fold<int>(
      0,
      (sum, w) => sum + w.caloriesBurned,
    );
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
              const SizedBox(height: 10),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: mc.divider,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Workout History',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: mc.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.35,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => Navigator.of(ctx).pop(),
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: mc.searchBg,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          CupertinoIcons.xmark,
                          color: mc.textSecondary,
                          size: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_completedWorkouts.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                  child: _HistorySummaryRow(
                    sessions: _completedWorkouts.length,
                    formattedTime: _formatCompactDuration(totalSec),
                    totalKcal: totalKcal,
                  ),
                ),
              Divider(height: 1, color: mc.divider),
              Expanded(
                child: _completedWorkouts.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'No workouts yet',
                                style: TextStyle(
                                  color: mc.textPrimary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Completed sessions will appear here.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: mc.textSecondary,
                                  fontSize: 13.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
                        itemCount: _completedWorkouts.length,
                        separatorBuilder: (_, __) =>
                            Divider(height: 1, color: mc.divider),
                        itemBuilder: (_, i) {
                          final item = _completedWorkouts[i];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            child: _HistoryRowContent(
                              item: item,
                              formattedDuration:
                                  _formatCompactDuration(item.actualDurationSec),
                              showLevelTag: true,
                            ),
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
    final programs = _filteredPrograms;
    final latestWorkout =
        _completedWorkouts.isNotEmpty ? _completedWorkouts.first : null;
    final countLabel = '${programs.length}';

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
                key: _journeysHintKey,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _quickWorkouts.map((q) {
                    final isActive =
                        _journeyProgress[q.journeyId]?.isSelected == true;
                    final iconKey = _quickIconKeys[q.journeyId]!;
                    return Expanded(
                      child: _QuickWorkoutTile(
                        meta: q,
                        iconKey: iconKey,
                        isActive: isActive,
                        onTap: () async {
                          HapticFeedback.selectionClick();
                          await pushTempoMorphRoute<void>(
                            context: context,
                            sourceKey: iconKey,
                            sourceBorderRadius: 18,
                            sourceColor: q.color,
                            builder: (_) => FitnessJourneyDetailScreen(
                              journeyId: q.journeyId,
                              journeyName: q.journeyName,
                              journeySubtitle: q.subtitle,
                              thumbnailAsset: q.thumb,
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

            // 2. Compact & Minimal History Card
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              sliver: SliverToBoxAdapter(
                child: RepaintBoundary(
                  child: AppleCard(
                    borderRadius: 22,
                    onTap: _openHistorySheet,
                    padding: const EdgeInsets.fromLTRB(16, 13, 16, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'History',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: c.textPrimary,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.25,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'All',
                              style: TextStyle(
                                color: c.textSecondary,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 2),
                            Icon(
                              CupertinoIcons.chevron_right,
                              size: 13,
                              color: c.textTertiary,
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (latestWorkout != null)
                          _HistoryRowContent(
                            item: latestWorkout,
                            formattedDuration: _formatCompactDuration(
                              latestWorkout.actualDurationSec,
                            ),
                            trailingMeta: _completedWorkouts.length == 1
                                ? '1 session'
                                : '${_completedWorkouts.length} sessions',
                          )
                        else
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'No workouts yet',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: c.textPrimary,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Complete a session below to start logging',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: c.textSecondary,
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // 3. Redesigned Workouts Header + Collapsible Search + Tempo Orange Category Chips
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  'Workouts',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: c.textPrimary,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: -0.35,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 7),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2.5,
                                ),
                                decoration: BoxDecoration(
                                  color: c.searchBg,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  countLabel,
                                  style: TextStyle(
                                    color: c.textSecondary,
                                    fontSize: 12,
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
                        const SizedBox(width: 8),
                        Builder(
                          builder: (btnCtx) => TempoLiquidButton(
                            key: _customWorkoutHintKey,
                            primary: false,
                            height: 36,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 13,
                              vertical: 0,
                            ),
                            onPressed: () => _openCustomBuilder(
                              sourceContext: btnCtx,
                              sourceBorderRadius: 999,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  CupertinoIcons.add,
                                  size: 14,
                                  color: c.accent,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  'Custom',
                                  style: TextStyle(
                                    color: c.textPrimary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        TempoGlassCircleButton(
                          size: 38,
                          tooltip:
                              _showSearch ? 'Close search' : 'Search workouts',
                          tintColor: _showSearch ? c.accent : null,
                          onPressed: _toggleSearch,
                          icon: AnimatedSwitcher(
                            duration: TempoAnimationSpeedService.instance.scale(
                              const Duration(milliseconds: 180),
                            ),
                            transitionBuilder: (child, anim) => ScaleTransition(
                              scale: anim,
                              child: FadeTransition(
                                opacity: anim,
                                child: child,
                              ),
                            ),
                            child: Icon(
                              _showSearch
                                  ? CupertinoIcons.xmark
                                  : CupertinoIcons.search,
                              key: ValueKey<bool>(_showSearch),
                              size: 17,
                              color: _showSearch ? c.accent : c.textPrimary,
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
                                    hintText: 'Search muscles, exercises, or level...',
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
                          final showCustomCount =
                              cat == 'Custom' && _customWorkouts.isNotEmpty;
                          return GestureDetector(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() => _selectedCategory = cat);
                            },
                            child: AnimatedContainer(
                              duration: TempoAnimationSpeedService.instance.scale(
                                const Duration(milliseconds: 190),
                              ),
                              curve: Curves.easeOutCubic,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 15,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: selected ? c.accent : c.card,
                                borderRadius: BorderRadius.circular(99),
                                border: Border.all(
                                  color: selected ? c.accent : c.cardBorder,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    cat,
                                    style: TextStyle(
                                      color: selected
                                          ? Colors.white
                                          : c.textPrimary,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (showCustomCount) ...[
                                    const SizedBox(width: 5),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5.5,
                                        vertical: 1,
                                      ),
                                      decoration: BoxDecoration(
                                        color: selected
                                            ? Colors.white.withValues(alpha: 0.24)
                                            : c.accent.withValues(
                                                alpha: c.isDark ? 0.22 : 0.14,
                                              ),
                                        borderRadius: BorderRadius.circular(99),
                                      ),
                                      child: Text(
                                        '${_customWorkouts.length}',
                                        style: TextStyle(
                                          color: selected
                                              ? Colors.white
                                              : c.accent,
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w700,
                                          fontFeatures: const [
                                            FontFeature.tabularFigures(),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
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

            // 4. Grouped Editorial Workout Program Cards List
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
              sliver: programs.isEmpty
                  ? SliverToBoxAdapter(
                      child: AppleCard(
                        borderRadius: 22,
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _selectedCategory == 'Custom'
                                      ? 'No custom routines yet.'
                                      : 'No workouts match your filter.',
                                  style: TextStyle(color: c.textSecondary),
                                ),
                                if (_selectedCategory == 'Custom') ...[
                                  const SizedBox(height: 10),
                                  FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: c.accent,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(999),
                                      ),
                                    ),
                                    onPressed: () => _openCustomBuilder(),
                                    icon: const Icon(CupertinoIcons.add, size: 16),
                                    label: const Text(
                                      'Create custom workout',
                                      style: TextStyle(fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    )
                  : SliverList.separated(
                      itemCount: programs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (ctx, i) {
                        final entry = programs[i];
                        final group = entry.group;
                        final activeWorkout = group.resolveVariant(
                          selectedLevel: _selectedLevelByGroup[group.groupId],
                          preferredLevelOverride: entry.matchedLevel,
                        );
                        return Builder(
                          builder: (cardCtx) => WorkoutProgramCard(
                            key: ValueKey<String>(group.groupId),
                            group: group,
                            activeWorkout: activeWorkout,
                            completedWorkoutIds: _completedWorkoutIds,
                            onSelectLevel: (level) {
                              setState(() {
                                _selectedLevelByGroup[group.groupId] = level;
                              });
                            },
                            onManageCustom: group.isCustom
                                ? () => _showCustomWorkoutActions(activeWorkout)
                                : null,
                            onTap: () async {
                              HapticFeedback.selectionClick();
                              await pushTempoMorphRoute<void>(
                                context: context,
                                sourceContext: cardCtx,
                                sourceBorderRadius: 20,
                                builder: (_) =>
                                    WorkoutDetailScreen(workout: activeWorkout),
                              );
                              if (mounted) _loadProgress();
                            },
                          ),
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

/// Tactile vibrant squircle activity launcher matching the Mi Fitness top bar,
/// engineered with a dedicated full-size 56×56 `RepaintBoundary` anchor and
/// `activeTempoMorphAnchorKey` zero-ghosting suppression so tapping HIIT Burn,
/// Strength, Cardio, Endurance, or Mobility launches and docks like a native
/// HyperOS 4 / iOS 26 app icon.
class _QuickWorkoutTile extends StatefulWidget {
  final _QuickWorkoutMeta meta;
  final GlobalKey iconKey;
  final bool isActive;
  final VoidCallback onTap;

  const _QuickWorkoutTile({
    required this.meta,
    required this.iconKey,
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
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Dedicated unscaled 56×56 squircle slot: keeps exact resting bounds
          // for crisp GPU snapshots and hides cleanly during morph flight (zero ghost).
          SizedBox.square(
            dimension: 56,
            child: AnimatedBuilder(
              animation: activeTempoMorphAnchorKey,
              builder: (_, __) {
                final isFlying = identical(
                  activeTempoMorphAnchorKey.value,
                  widget.iconKey,
                );
                if (isFlying) {
                  return const SizedBox.square(dimension: 56);
                }
                return RepaintBoundary(
                  key: widget.iconKey,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 110),
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: _pressed
                          ? Color.lerp(widget.meta.color, Colors.black, 0.10)
                          : widget.meta.color,
                      borderRadius: BorderRadius.circular(18),
                      border: widget.isActive
                          ? Border.all(color: c.textPrimary, width: 2)
                          : null,
                    ),
                    child: AnimatedScale(
                      scale: _pressed ? 0.88 : 1.0,
                      duration: const Duration(milliseconds: 110),
                      curve: Curves.easeOutCubic,
                      child: Icon(
                        widget.meta.icon,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),
                );
              },
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
    );
  }
}

/// Minimal typographic 3-figure summary row inside the Workout History sheet
/// (zero icons, zero extra container chrome, tabular numerals).
class _HistorySummaryRow extends StatelessWidget {
  final int sessions;
  final String formattedTime;
  final int totalKcal;

  const _HistorySummaryRow({
    required this.sessions,
    required this.formattedTime,
    required this.totalKcal,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Row(
      children: [
        Expanded(
          child: _SummaryFigure(value: '$sessions', label: 'Sessions'),
        ),
        Container(width: 1, height: 26, color: c.divider),
        Expanded(
          child: _SummaryFigure(value: formattedTime, label: 'Time'),
        ),
        Container(width: 1, height: 26, color: c.divider),
        Expanded(
          child: _SummaryFigure(value: '$totalKcal', label: 'kcal'),
        ),
      ],
    );
  }
}

class _SummaryFigure extends StatelessWidget {
  final String value;
  final String label;

  const _SummaryFigure({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: c.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: c.textSecondary,
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// Minimal typography-first workout history row (zero icons or boxy badges).
class _HistoryRowContent extends StatelessWidget {
  final LocalCompletedWorkout item;
  final String formattedDuration;
  final String? trailingMeta;
  final bool showLevelTag;

  const _HistoryRowContent({
    required this.item,
    required this.formattedDuration,
    this.trailingMeta,
    this.showLevelTag = false,
  });

  String _formatRelativeDate(DateTime completedAt) {
    final local = completedAt.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(local.year, local.month, local.day);
    final diffDays = today.difference(date).inDays;
    if (diffDays == 0) return 'Today';
    if (diffDays == 1) return 'Yesterday';
    if (diffDays > 1 && diffDays < 7) {
      return DateFormat('EEE').format(local);
    }
    return DateFormat('MMM d').format(local);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final cleanTitle = cleanProgramTitle(item.title);
    final displayTitle = cleanTitle.isNotEmpty ? cleanTitle : item.title;
    final dateLabel = _formatRelativeDate(item.completedAt);

    final metaParts = <String>[
      formattedDuration,
      if (item.caloriesBurned > 0) '${item.caloriesBurned} kcal',
      if (showLevelTag && item.level.trim().isNotEmpty)
        shortDifficultyLabel(item.level)
      else if (showLevelTag && item.bodyFocus.trim().isNotEmpty)
        item.bodyFocus.trim(),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                displayTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              dateLabel,
              style: TextStyle(
                color: c.textTertiary,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                metaParts.join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: c.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            if (trailingMeta != null) ...[
              const SizedBox(width: 10),
              Text(
                trailingMeta!,
                style: TextStyle(
                  color: c.textTertiary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
