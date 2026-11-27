import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/workout_model.dart';
import '../services/animation_speed_service.dart';
import '../services/appearance_service.dart';
import '../theme/app_colors.dart';
import 'bitchord_glass_lens.dart';
import 'bitchord_pill_motion.dart';
import 'liquid_glass_surface.dart';

/// Ordered canonical difficulty sort priority for grouped workout variants.
int _difficultyRank(String level) {
  switch (level.trim().toLowerCase()) {
    case 'easy':
      return 0;
    case 'medium':
      return 1;
    case 'hard':
      return 2;
    default:
      return 3;
  }
}

/// Short segmented label for the inline difficulty pill switcher.
String shortDifficultyLabel(String level) {
  switch (level.trim().toLowerCase()) {
    case 'easy':
      return 'Easy';
    case 'medium':
      return 'Med';
    case 'hard':
      return 'Hard';
    default:
      return level;
  }
}

/// Semantic emerald green reserved exclusively for completed workout levels
/// (high contrast on both Light & Dark segmented pill surfaces).
Color completedDifficultyColor({required bool isDark}) =>
    isDark ? const Color(0xFF34D399) : const Color(0xFF16A34A);

/// Strips repetitive ALL-CAPS difficulty suffixes and redundant "Training"
/// boilerplate to yield crisp editorial program names (e.g.
/// `"Chest Power Training MEDIUM"` -> `"Chest Power"`).
String cleanProgramTitle(String rawTitle) {
  var title = rawTitle.trim();
  title = title.replaceFirst(
    RegExp(r'\s+(HARD|MEDIUM|EASY)$', caseSensitive: false),
    '',
  );
  title = title.replaceFirst(
    RegExp(r'\s+Training$', caseSensitive: false),
    '',
  );
  return title.trim();
}

/// Returns a clean, non-redundant muscle focus tag for the card metadata row
/// (e.g. avoids repeating "Traps" directly under the title "Traps").
String editorialFocusTag(WorkoutProgramGroup group) {
  if (group.title.trim().toLowerCase() != group.bodyFocus.trim().toLowerCase()) {
    return group.bodyFocus;
  }
  switch (group.bodyFocus.trim().toLowerCase()) {
    case 'traps':
      return 'Upper Back';
    case 'shoulders':
      return 'Delts & Upper';
    case 'biceps':
    case 'triceps':
    case 'forearms':
      return 'Arms';
    case 'abs':
      return 'Core';
    default:
      return 'Targeted';
  }
}

/// Computes estimated session calorie burn from the routine's exercise catalog.
int estimateWorkoutKcal(Workout workout) {
  double total = 0.0;
  for (final ex in workout.exerciseList) {
    total += ex.baseCaloriesPerMinute * (ex.duration / 60.0);
  }
  return total.round();
}

/// Grouped muscle-program entry consolidating Easy / Medium / Hard variants of
/// the same workout under one clean card while keeping every underlying
/// [Workout.id] untouched for SQLite history compatibility.
class WorkoutProgramGroup {
  final String groupId;
  final String title;
  final String bodyFocus;
  final bool isCustom;
  final List<Workout> variants;

  const WorkoutProgramGroup({
    required this.groupId,
    required this.title,
    required this.bodyFocus,
    required this.isCustom,
    required this.variants,
  });

  /// Picks the active variant given a remembered [selectedLevel] (or optional
  /// [preferredLevelOverride] from search), defaulting to Medium when present.
  Workout resolveVariant({
    String? selectedLevel,
    String? preferredLevelOverride,
  }) {
    if (variants.length == 1) return variants.first;

    if (preferredLevelOverride != null) {
      final target = preferredLevelOverride.toLowerCase();
      for (final v in variants) {
        if (v.level.toLowerCase() == target) return v;
      }
    }

    if (selectedLevel != null) {
      final target = selectedLevel.toLowerCase();
      for (final v in variants) {
        if (v.level.toLowerCase() == target) return v;
      }
    }

    for (final v in variants) {
      if (v.level.toLowerCase() == 'medium') return v;
    }
    return variants.first;
  }

  /// Creates a single-variant group wrapper for a user's custom workout.
  factory WorkoutProgramGroup.custom(Workout workout) {
    return WorkoutProgramGroup(
      groupId: 'custom_${workout.id}',
      title: workout.title,
      bodyFocus: workout.bodyFocus,
      isCustom: true,
      variants: [workout],
    );
  }
}

/// Collapses flat built-in workouts (e.g. 31 entries) into clean muscle-group
/// programs (13 entries) preserving catalog order and sorting each program's
/// variants Easy -> Medium -> Hard.
List<WorkoutProgramGroup> groupExerciseWorkouts(List<Workout> rawWorkouts) {
  final orderedKeys = <String>[];
  final buckets = <String, List<Workout>>{};
  final displayTitles = <String, String>{};

  for (final w in rawWorkouts) {
    final title = cleanProgramTitle(w.title);
    final key = '${w.bodyFocus.toLowerCase()}::${title.toLowerCase()}';
    if (!buckets.containsKey(key)) {
      orderedKeys.add(key);
      buckets[key] = <Workout>[];
      displayTitles[key] = title;
    }
    buckets[key]!.add(w);
  }

  return orderedKeys.map((key) {
    final list = List<Workout>.from(buckets[key]!)
      ..sort((a, b) => _difficultyRank(a.level).compareTo(_difficultyRank(b.level)));
    return WorkoutProgramGroup(
      groupId: key,
      title: displayTitles[key]!,
      bodyFocus: list.first.bodyFocus,
      isCustom: false,
      variants: list,
    );
  }).toList();
}

/// Compact, minimal editorial workout card matching the calm typography-first
/// History card:
/// - Clean edge-to-edge `92×72` offline exercise photo (zero overlays, zero
///   vignette badges, zero `BackdropFilter` inside scrolling lists)
/// - Crisp title + bare trailing chevron, single-line tabular metadata
///   (`25 min · 5 exercises · 185 kcal`, zero flame icon clutter)
/// - Slim inline spring-sliding `Easy | Med | Hard` switcher seated directly
///   beside the photo where finished levels glow emerald green
/// - Permanent `RepaintBoundary` for locked-120Hz scrolling & crisp GPU morph snapshots.
class WorkoutProgramCard extends StatelessWidget {
  final WorkoutProgramGroup group;
  final Workout activeWorkout;
  final Set<String> completedWorkoutIds;
  final ValueChanged<String> onSelectLevel;
  final VoidCallback onTap;
  final VoidCallback? onManageCustom;

  const WorkoutProgramCard({
    super.key,
    required this.group,
    required this.activeWorkout,
    required this.completedWorkoutIds,
    required this.onSelectLevel,
    required this.onTap,
    this.onManageCustom,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final thumbCachePx = (92 * dpr).round().clamp(160, 360);
    final estKcal = estimateWorkoutKcal(activeWorkout);
    final switchDur = TempoAnimationSpeedService.instance.scale(
      const Duration(milliseconds: 220),
    );
    final metaLine = [
      activeWorkout.duration,
      '${activeWorkout.exerciseList.length} exercises',
      if (estKcal > 0) '$estKcal kcal',
    ].join(' · ');

    return RepaintBoundary(
      child: AppleCard(
        borderRadius: 20,
        onTap: onTap,
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _MinimalArtworkThumb(
              workout: activeWorkout,
              isCustom: group.isCustom,
              cacheWidth: thumbCachePx,
              switchDuration: switchDur,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Line 1: Clean title + bare trailing chevron / custom ellipsis
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          group.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: c.textPrimary,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.25,
                            height: 1.2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      if (group.isCustom && onManageCustom != null)
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: onManageCustom,
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              CupertinoIcons.ellipsis,
                              color: c.textSecondary,
                              size: 16,
                            ),
                          ),
                        )
                      else
                        Icon(
                          CupertinoIcons.chevron_right,
                          color: c.textTertiary,
                          size: 13,
                        ),
                    ],
                  ),
                  const SizedBox(height: 2.5),

                  // Line 2: Clean tabular metadata (no icons)
                  AnimatedSwitcher(
                    duration: switchDur,
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    layoutBuilder: (currentChild, previousChildren) => Stack(
                      alignment: Alignment.centerLeft,
                      children: [
                        ...previousChildren,
                        if (currentChild != null) currentChild,
                      ],
                    ),
                    child: Text(
                      metaLine,
                      key: ValueKey<String>(activeWorkout.id),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: c.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const SizedBox(height: 7),

                  // Line 3: Slim inline Easy / Med / Hard switcher OR quiet exercise preview
                  if (group.variants.length > 1)
                    _InlineDifficultySwitcher(
                      variants: group.variants,
                      activeLevel: activeWorkout.level,
                      completedWorkoutIds: completedWorkoutIds,
                      onSelectLevel: onSelectLevel,
                    )
                  else
                    _MinimalExerciseSubtitle(
                      group: group,
                      workout: activeWorkout,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Clean edge-to-edge `92×72` offline exercise photo with subtle hairline rim
/// and zero overlaid badges or vignettes.
class _MinimalArtworkThumb extends StatelessWidget {
  final Workout workout;
  final bool isCustom;
  final int cacheWidth;
  final Duration switchDuration;

  const _MinimalArtworkThumb({
    required this.workout,
    required this.isCustom,
    required this.cacheWidth,
    required this.switchDuration,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 92,
        height: 72,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (isCustom)
              Container(
                color: c.accent.withValues(alpha: c.isDark ? 0.18 : 0.11),
                child: Center(
                  child: Icon(
                    CupertinoIcons.flame_fill,
                    color: c.accent,
                    size: 24,
                  ),
                ),
              )
            else
              AnimatedSwitcher(
                duration: switchDuration,
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: Image.asset(
                  workout.thumbnailAsset,
                  key: ValueKey<String>(workout.thumbnailAsset),
                  width: 92,
                  height: 72,
                  cacheWidth: cacheWidth,
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.medium,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: c.searchBg,
                    child: Icon(
                      Icons.directions_run_rounded,
                      color: c.textSecondary,
                      size: 22,
                    ),
                  ),
                ),
              ),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: c.isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.black.withValues(alpha: 0.06),
                      width: 0.6,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// BitChord-calibrated sliding Liquid Glass pill switcher for Easy / Med / Hard
/// variants seated inline inside each grouped muscle card:
/// - **Tap OR slide smoothly** across `Easy | Med | Hard` with BitChord's 120Hz
///   coupled lift/travel/squash springs and 7-band chromatic dispersion glass lens.
/// - **Zero GPU cost at rest:** When settled, the `BackdropFilterLayer` detaches
///   completely (`0` backdrop passes while scrolling the Workouts list).
/// - **Completed difficulties** render in crisp emerald green (zero bullets/dots).
class _InlineDifficultySwitcher extends StatefulWidget {
  final List<Workout> variants;
  final String activeLevel;
  final Set<String> completedWorkoutIds;
  final ValueChanged<String> onSelectLevel;

  const _InlineDifficultySwitcher({
    required this.variants,
    required this.activeLevel,
    required this.completedWorkoutIds,
    required this.onSelectLevel,
  });

  @override
  State<_InlineDifficultySwitcher> createState() =>
      _InlineDifficultySwitcherState();
}

class _InlineDifficultySwitcherState extends State<_InlineDifficultySwitcher>
    with TickerProviderStateMixin {
  static const double _trackHeight = 28.0;

  ui.FragmentProgram? _program;
  late final BitChordPillMotion _motion;
  late final ValueNotifier<int> _visualIndex;

  Timer? _holdLiftTimer;
  int? _activePointerId;
  Offset _pointerDownLocal = Offset.zero;
  bool _isScrubbing = false;
  bool _scrollRejected = false;
  bool _isHovering = false;
  double _currentTrackWidth = 0.0;
  int _lastHapticIndex = 0;

  int _resolveActiveIndex([List<Workout>? list, String? level]) {
    final variants = list ?? widget.variants;
    if (variants.isEmpty) return 0;
    final target = (level ?? widget.activeLevel).toLowerCase();
    return variants
        .indexWhere((v) => v.level.toLowerCase() == target)
        .clamp(0, variants.length - 1);
  }

  @override
  void initState() {
    super.initState();
    final initial = _resolveActiveIndex();
    _lastHapticIndex = initial;
    _visualIndex = ValueNotifier<int>(initial);
    _motion = BitChordPillMotion(
      vsync: this,
      initialIndex: initial,
    )..reduceMotion = TempoAppearanceService.instance.reduceAnimation;
    _loadShader();
    TempoAppearanceService.instance.notifier.addListener(_syncAppearance);
  }

  void _syncAppearance() {
    if (!mounted) return;
    _motion.reduceMotion = TempoAppearanceService.instance.reduceAnimation ||
        MediaQuery.disableAnimationsOf(context);
  }

  Future<void> _loadShader() async {
    final existing = TempoLiquidShaderCache.program;
    if (existing != null) {
      _program = existing;
      return;
    }
    final loaded = await TempoLiquidShaderCache.load();
    if (loaded != null && mounted) {
      setState(() => _program = loaded);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motion.reduceMotion = TempoAppearanceService.instance.reduceAnimation ||
        MediaQuery.disableAnimationsOf(context);
  }

  @override
  void didUpdateWidget(covariant _InlineDifficultySwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextIdx = _resolveActiveIndex();
    if (!_isScrubbing && !_isHovering && nextIdx != _motion.index) {
      _lastHapticIndex = nextIdx;
      _visualIndex.value = nextIdx;
      _motion.animateTo(nextIdx);
    }
  }

  @override
  void dispose() {
    TempoAppearanceService.instance.notifier.removeListener(_syncAppearance);
    _holdLiftTimer?.cancel();
    _motion.dispose();
    _visualIndex.dispose();
    super.dispose();
  }

  double _dxToUnclampedPos(double localDx, double trackWidth) {
    if (trackWidth <= 0 || widget.variants.isEmpty) return 0.0;
    final segW = trackWidth / widget.variants.length;
    return (localDx - segW * 0.5) / segW;
  }

  int _posToIndex(double pos) =>
      pos.round().clamp(0, widget.variants.length - 1);

  void _enterScrubMode(double localDx, double trackWidth) {
    if (_isScrubbing || _scrollRejected) return;
    _holdLiftTimer?.cancel();
    _isScrubbing = true;
    final rawPos = _dxToUnclampedPos(localDx, trackWidth);
    final nearest = _posToIndex(rawPos);
    _lastHapticIndex = nearest;
    _visualIndex.value = nearest;
    _motion.startDrag();
    _motion.dragTo(rawPos, itemCount: widget.variants.length);
    HapticFeedback.lightImpact();
    final level = widget.variants[nearest].level;
    if (level.toLowerCase() != widget.activeLevel.toLowerCase()) {
      widget.onSelectLevel(level);
    }
  }

  void _handlePointerDown(PointerDownEvent event, double trackWidth) {
    if (_activePointerId != null) return;
    if (event.kind == PointerDeviceKind.mouse &&
        event.buttons != kPrimaryButton) {
      return;
    }
    _activePointerId = event.pointer;
    _pointerDownLocal = event.localPosition;
    _isScrubbing = false;
    _scrollRejected = false;
    _holdLiftTimer?.cancel();

    _holdLiftTimer = Timer(const Duration(milliseconds: 110), () {
      if (!mounted ||
          _activePointerId != event.pointer ||
          _isScrubbing ||
          _scrollRejected) {
        return;
      }
      _enterScrubMode(_pointerDownLocal.dx, _currentTrackWidth);
    });
  }

  void _handlePointerMove(PointerMoveEvent event, double trackWidth) {
    if (event.pointer != _activePointerId) return;
    final dx = (event.localPosition.dx - _pointerDownLocal.dx).abs();
    final dy = (event.localPosition.dy - _pointerDownLocal.dy).abs();

    if (!_isScrubbing) {
      if (_scrollRejected) return;
      if (dx >= 6.0 && dx >= dy * 0.9) {
        _enterScrubMode(event.localPosition.dx, trackWidth);
      } else if (dy > 12.0 && dy > dx) {
        _scrollRejected = true;
        _holdLiftTimer?.cancel();
      }
      return;
    }

    final rawPos = _dxToUnclampedPos(event.localPosition.dx, trackWidth);
    _motion.dragTo(rawPos, itemCount: widget.variants.length);

    final nearest = _posToIndex(rawPos);
    if (nearest != _lastHapticIndex) {
      _lastHapticIndex = nearest;
      _visualIndex.value = nearest;
      HapticFeedback.selectionClick();
      widget.onSelectLevel(widget.variants[nearest].level);
    }
  }

  void _handlePointerUp(PointerUpEvent event, double trackWidth) {
    if (event.pointer != _activePointerId) return;
    _holdLiftTimer?.cancel();
    _activePointerId = null;

    if (_isScrubbing) {
      _isScrubbing = false;
      final targetIdx =
          _posToIndex(_dxToUnclampedPos(event.localPosition.dx, trackWidth));
      _visualIndex.value = targetIdx;
      _motion.release(targetIdx);
      final targetLevel = widget.variants[targetIdx].level;
      if (targetLevel.toLowerCase() != widget.activeLevel.toLowerCase()) {
        widget.onSelectLevel(targetLevel);
      }
      return;
    }

    if (_scrollRejected) {
      _scrollRejected = false;
      return;
    }

    // Crisp tap: lift crystal lens & glide to selected difficulty!
    final targetIdx =
        _posToIndex(_dxToUnclampedPos(event.localPosition.dx, trackWidth));
    final targetLevel = widget.variants[targetIdx].level;
    _visualIndex.value = targetIdx;
    if (targetIdx != _motion.index ||
        targetLevel.toLowerCase() != widget.activeLevel.toLowerCase()) {
      HapticFeedback.selectionClick();
      _motion.animateTo(targetIdx);
      widget.onSelectLevel(targetLevel);
    }
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (event.pointer != _activePointerId) return;
    _holdLiftTimer?.cancel();
    _activePointerId = null;
    _scrollRejected = false;
    if (_isScrubbing) {
      _isScrubbing = false;
      final active = _resolveActiveIndex();
      _visualIndex.value = active;
      _motion.release(active);
    }
  }

  bool _isPointerHoverDevice(PointerEvent event) =>
      event.kind != PointerDeviceKind.touch;

  void _handleHoverEnter(PointerEnterEvent event, double trackWidth) {
    if (!_isPointerHoverDevice(event) || _isScrubbing) return;
    _isHovering = true;
    final rawPos = _dxToUnclampedPos(event.localPosition.dx, trackWidth);
    _motion.startDrag();
    _motion.dragTo(rawPos, itemCount: widget.variants.length);
    _visualIndex.value = _posToIndex(rawPos);
  }

  void _handleHoverMove(PointerHoverEvent event, double trackWidth) {
    if (!_isPointerHoverDevice(event) || _isScrubbing) return;
    _isHovering = true;
    final rawPos = _dxToUnclampedPos(event.localPosition.dx, trackWidth);
    _motion.dragTo(rawPos, itemCount: widget.variants.length);
    _visualIndex.value = _posToIndex(rawPos);
  }

  void _handleHoverExit(PointerExitEvent event) {
    if (!_isHovering) return;
    _isHovering = false;
    if (!_isScrubbing) {
      final active = _resolveActiveIndex();
      _visualIndex.value = active;
      _motion.release(active);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final isDark = c.isDark;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final completedGreen = completedDifficultyColor(isDark: isDark);

    return ValueListenableBuilder<TempoAppearanceSettings>(
      valueListenable: TempoAppearanceService.instance.notifier,
      builder: (context, appearance, _) {
        _motion.reduceMotion = appearance.reduceAnimation ||
            MediaQuery.disableAnimationsOf(context);
        final showLiftedGlass =
            appearance.useLiquidGlass && !appearance.reduceAnimation;

        // Absorb taps & horizontal drags inside the switcher so sliding
        // `Easy | Med | Hard` never triggers parent AppleCard tap navigation,
        // while vertical scrolls still pass through to CustomScrollView!
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {},
          onHorizontalDragStart: (_) {},
          onHorizontalDragUpdate: (_) {},
          onHorizontalDragEnd: (_) {},
          child: SizedBox(
            height: _trackHeight,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final trackWidth = constraints.maxWidth;
                _currentTrackWidth = trackWidth;
                final count = widget.variants.length;
                final segWidth = count > 0 ? trackWidth / count : trackWidth;
                _motion.stepDp = segWidth;

                final restSize = Size(
                  (segWidth - 5.0).clamp(28.0, 140.0),
                  _trackHeight - 5.0,
                );
                final liftedSize = Size(
                  (segWidth + 5.0).clamp(36.0, 152.0),
                  _trackHeight + 7.0,
                );

                return MouseRegion(
                  onEnter: (e) => _handleHoverEnter(e, trackWidth),
                  onHover: (e) => _handleHoverMove(e, trackWidth),
                  onExit: _handleHoverExit,
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (e) => _handlePointerDown(e, trackWidth),
                    onPointerMove: (e) => _handlePointerMove(e, trackWidth),
                    onPointerUp: (e) => _handlePointerUp(e, trackWidth),
                    onPointerCancel: _handlePointerCancel,
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.center,
                      children: [
                        // Layer 1: Quiet rounded pill track
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: c.searchBg,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),

                        // Layer 2: Paint-only resting thumb (fades out cleanly
                        // as the crystal refraction lens lifts!)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: ValueListenableBuilder<int>(
                              valueListenable: _visualIndex,
                              builder: (_, visIdx, __) {
                                final clamped = visIdx.clamp(0, count - 1);
                                final activeDone = widget.completedWorkoutIds
                                    .contains(widget.variants[clamped].id);
                                return CustomPaint(
                                  painter: _DifficultyRestThumbPainter(
                                    motion: _motion,
                                    segWidth: segWidth,
                                    trackHeight: _trackHeight,
                                    restSize: restSize,
                                    liftedSize: liftedSize,
                                    isDark: isDark,
                                    activeDone: activeDone,
                                    completedGreen: completedGreen,
                                    clearWhileLifted:
                                        appearance.useGlassRefraction &&
                                            showLiftedGlass,
                                  ),
                                );
                              },
                            ),
                          ),
                        ),

                        // Layer 3: Easy | Med | Hard labels (emerald green when finished)
                        Positioned.fill(
                          child: ValueListenableBuilder<int>(
                            valueListenable: _visualIndex,
                            builder: (_, visIdx, __) {
                              return Row(
                                children: List.generate(count, (i) {
                                  final v = widget.variants[i];
                                  final selected = i == visIdx;
                                  final done = widget.completedWorkoutIds
                                      .contains(v.id);
                                  final labelColor = done
                                      ? completedGreen
                                      : (selected
                                          ? c.textPrimary
                                          : c.textSecondary);
                                  final fontWeight = selected
                                      ? FontWeight.w700
                                      : (done
                                          ? FontWeight.w600
                                          : FontWeight.w500);
                                  return Expanded(
                                    child: Center(
                                      child: Text(
                                        shortDifficultyLabel(v.level),
                                        style: TextStyle(
                                          color: labelColor,
                                          fontSize: 11.5,
                                          fontWeight: fontWeight,
                                          letterSpacing: -0.1,
                                        ),
                                      ),
                                    ),
                                  );
                                }),
                              );
                            },
                          ),
                        ),

                        // Layer 4 (TOP, ZERO-ALLOCATION GPU LENS):
                        // BitChord crystal lens refracting labels while sliding/tapping,
                        // detached completely at rest (`0%` GPU cost while scrolling!).
                        if (showLiftedGlass)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: BitChordGlassLensBox(
                                program: _program,
                                repaint: _motion,
                                isDark: isDark,
                                dpr: dpr,
                                useRefractionShader:
                                    appearance.useGlassRefraction,
                                frameBuilder: (_) {
                                  if (_motion.isFlat || segWidth <= 0) {
                                    return BitChordLensFrame.inactive;
                                  }
                                  final liveSize = _motion.liveSize(
                                    restSize,
                                    liftedSize,
                                  );
                                  final cx =
                                      (_motion.position + 0.5) * segWidth;
                                  final cy = _trackHeight * 0.5;
                                  final localRect = Rect.fromCenter(
                                    center: Offset(cx, cy),
                                    width: liveSize.width,
                                    height: liveSize.height,
                                  );
                                  final presence = _motion.glassPresence;
                                  final material = _motion.material;
                                  final rimAlpha =
                                      (material * _motion.rimFactor)
                                          .clamp(0.0, 1.0);
                                  return BitChordLensFrame(
                                    active: true,
                                    rect: localRect,
                                    borderRadius: liveSize.height * 0.5,
                                    refractionHeightDp: 7.5 * presence,
                                    refractionAmountDp: 10.5 * material,
                                    depthEffect: 0.45,
                                    aberration: 1.0,
                                    rimAlpha: rimAlpha,
                                    shadowAlpha: rimAlpha,
                                    material: material,
                                  );
                                },
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _DifficultyRestThumbPainter extends CustomPainter {
  final BitChordPillMotion motion;
  final double segWidth;
  final double trackHeight;
  final Size restSize;
  final Size liftedSize;
  final bool isDark;
  final bool activeDone;
  final Color completedGreen;
  final bool clearWhileLifted;

  _DifficultyRestThumbPainter({
    required this.motion,
    required this.segWidth,
    required this.trackHeight,
    required this.restSize,
    required this.liftedSize,
    required this.isDark,
    required this.activeDone,
    required this.completedGreen,
    required this.clearWhileLifted,
  }) : super(repaint: motion);

  @override
  void paint(Canvas canvas, Size size) {
    final alphaFactor =
        clearWhileLifted ? (1.0 - motion.material).clamp(0.0, 1.0) : 1.0;
    if (alphaFactor <= 0.004 || segWidth <= 0) return;

    final liveSize = motion.liveSize(restSize, liftedSize);
    final cx = (motion.position + 0.5) * segWidth;
    final cy = trackHeight * 0.5;
    final rect = Rect.fromCenter(
      center: Offset(cx, cy),
      width: liveSize.width,
      height: liveSize.height,
    );
    final rrect = RRect.fromRectAndRadius(
      rect,
      Radius.circular(liveSize.height * 0.5),
    );

    final shadowPaint = Paint()
      ..color = Colors.black.withValues(
        alpha: (isDark ? 0.22 : 0.055) * alphaFactor,
      )
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
    canvas.drawRRect(rrect.shift(const Offset(0, 1.0)), shadowPaint);

    final fillPaint = Paint()
      ..color = (isDark ? const Color(0xFF2C2C34) : Colors.white)
          .withValues(alpha: alphaFactor);
    canvas.drawRRect(rrect, fillPaint);

    final borderColor = activeDone
        ? completedGreen.withValues(
            alpha: (isDark ? 0.42 : 0.32) * alphaFactor,
          )
        : (isDark
            ? Colors.white.withValues(alpha: 0.08 * alphaFactor)
            : Colors.black.withValues(alpha: 0.05 * alphaFactor));
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = borderColor;
    canvas.drawRRect(rrect, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _DifficultyRestThumbPainter oldDelegate) =>
      oldDelegate.segWidth != segWidth ||
      oldDelegate.trackHeight != trackHeight ||
      oldDelegate.restSize != restSize ||
      oldDelegate.liftedSize != liftedSize ||
      oldDelegate.isDark != isDark ||
      oldDelegate.activeDone != activeDone ||
      oldDelegate.completedGreen != completedGreen ||
      oldDelegate.clearWhileLifted != clearWhileLifted;
}

/// Quiet 1-line exercise preview for single-level built-in and Custom routines
/// (zero box containers, zero icons).
class _MinimalExerciseSubtitle extends StatelessWidget {
  final WorkoutProgramGroup group;
  final Workout workout;

  const _MinimalExerciseSubtitle({
    required this.group,
    required this.workout,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final names = workout.exerciseList.map((e) => e.name).toList();
    final preview = names.take(2).join(' · ');
    final text = group.isCustom
        ? (preview.isNotEmpty ? 'Custom · $preview' : 'Custom routine')
        : (preview.isNotEmpty ? preview : editorialFocusTag(group));

    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: c.textTertiary,
        fontSize: 11.5,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}
