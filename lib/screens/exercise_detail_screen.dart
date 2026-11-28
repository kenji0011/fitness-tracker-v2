import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/local_profile.dart';
import '../models/workout_model.dart';
import '../services/active_profile_provider.dart';
import '../services/tempo_rust_db.dart';
import '../services/video_mapping_service.dart';
import '../services/weight_unit_helper.dart';
import '../services/workout_goal_service.dart';
import '../theme/app_colors.dart';
import '../widgets/liquid_glass_surface.dart';
import '../widgets/tempo_liquid_video_player.dart';
import '../widgets/tempo_sliver_header.dart';
import '../widgets/tempo_toast.dart';

class ExerciseDetailScreen extends StatefulWidget {
  final Exercise exercise;
  final Workout workout;

  const ExerciseDetailScreen({
    super.key,
    required this.exercise,
    required this.workout,
  });

  @override
  State<ExerciseDetailScreen> createState() => _ExerciseDetailScreenState();
}

class _ExerciseDetailScreenState extends State<ExerciseDetailScreen> {
  final _weightCtrl = TextEditingController(text: '20.0');
  final _repsCtrl = TextEditingController(text: '10');
  final _setsCtrl = TextEditingController(text: '3');

  bool _saving = false;
  String _weightUnit = 'kg';
  List<LocalExerciseRecord> _history = [];

  double _weightValue = 20.0;
  int _setsValue = 3;
  int _repsValue = 10;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  String? _resolveVideoAsset() {
    return widget.exercise.customVideoAsset ??
        VideoMappingService.getVideoPath(
          widget.exercise.name,
          journeyName: widget.workout.journeyName,
          workoutTitle: widget.workout.title,
        );
  }

  Future<void> _loadHistory() async {
    final pid = context.read<ActiveProfileProvider>().activeProfileId;
    if (pid == null) return;
    final results = await Future.wait([
      TempoRustDb.instance.getExerciseRecords(
        pid,
        exerciseName: widget.exercise.name,
      ),
      WeightUnitHelper.loadUnit(pid),
    ]);
    final list = results[0] as List<LocalExerciseRecord>;
    final unit = results[1] as String;
    if (!mounted) return;
    setState(() {
      _weightUnit = unit;
      _history = list;
      if (list.isNotEmpty) {
        if (list.first.weightUsed > 0) {
          _weightValue = WeightUnitHelper.toDisplay(
            list.first.weightUsed,
            unit,
          );
          _weightCtrl.text = _formatWeight(_weightValue);
        } else {
          _weightValue = unit == 'lb' ? 45.0 : 20.0;
          _weightCtrl.text = _formatWeight(_weightValue);
        }
        _setsValue = list.first.setsPerformed.clamp(1, 20);
        _repsValue = list.first.repsPerformed.clamp(1, 100);
        _setsCtrl.text = '$_setsValue';
        _repsCtrl.text = '$_repsValue';
      } else {
        _weightValue = unit == 'lb' ? 45.0 : 20.0;
        _weightCtrl.text = _formatWeight(_weightValue);
      }
    });
  }

  String _formatWeight(double v) {
    return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  }

  void _stepWeight(double delta) {
    HapticFeedback.selectionClick();
    final next = (_weightValue + delta).clamp(0.0, 999.0);
    setState(() {
      _weightValue = next;
      _weightCtrl.text = _formatWeight(next);
    });
  }

  void _stepSets(int delta) {
    HapticFeedback.selectionClick();
    final next = (_setsValue + delta).clamp(1, 20);
    setState(() {
      _setsValue = next;
      _setsCtrl.text = '$next';
    });
  }

  void _stepReps(int delta) {
    HapticFeedback.selectionClick();
    final next = (_repsValue + delta).clamp(1, 100);
    setState(() {
      _repsValue = next;
      _repsCtrl.text = '$next';
    });
  }

  Future<void> _logSet() async {
    final profileProvider = context.read<ActiveProfileProvider>();
    final pid = profileProvider.activeProfileId;
    if (pid == null) return;

    final rawWeight = double.tryParse(_weightCtrl.text.trim()) ?? _weightValue;
    final weightKg = WeightUnitHelper.fromDisplay(rawWeight, _weightUnit);
    final reps = (int.tryParse(_repsCtrl.text.trim()) ?? _repsValue).clamp(1, 200);
    final sets = (int.tryParse(_setsCtrl.text.trim()) ?? _setsValue).clamp(1, 50);

    setState(() => _saving = true);
    try {
      await TempoRustDb.instance.logExerciseRecord(
        profileId: pid,
        exerciseName: widget.exercise.name,
        workoutId: widget.workout.id,
        weightUsed: widget.exercise.requiresWeightInput ? weightKg : 0.0,
        repsPerformed: reps,
        setsPerformed: sets,
        bodyFocus: widget.workout.bodyFocus,
        level: widget.workout.level,
        journeyId: widget.workout.journeyId ?? '',
        journeyName: widget.workout.journeyName ?? '',
        primaryGoal: inferPrimaryGoalForWorkout(widget.workout),
        goalTags: inferGoalTagsForWorkout(widget.workout),
      );
      profileProvider.notifyDataChanged();
      if (mounted) {
        HapticFeedback.mediumImpact();
        showTempoToast(context, 'Exercise set logged');
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showTempoToast(context, 'Could not log exercise: $e', isError: true);
      }
    }
  }

  String _formatDuration(int sec) {
    final m = sec ~/ 60;
    final s = sec % 60;
    if (m == 0) return '${s}s';
    if (s == 0) return '${m}m';
    return '${m}m ${s}s';
  }

  @override
  void dispose() {
    _weightCtrl.dispose();
    _repsCtrl.dispose();
    _setsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final videoPath = _resolveVideoAsset();
    final weightStep = _weightUnit == 'lb' ? 5.0 : 2.5;

    return Scaffold(
      backgroundColor: c.scaffold,
      body: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          TempoSliverHeader(
            title: widget.exercise.name,
            showBackButton: true,
            onBack: () => Navigator.of(context).pop(false),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 36),
            sliver: SliverList.list(
              children: [
                // 1. Unified Impeller-Native Liquid Glass Video Player
                TempoLiquidVideoPlayer(
                  assetPath: videoPath,
                  exerciseName: widget.exercise.name,
                  autoPlay: true,
                  initialLooping: true,
                  borderRadius: 24,
                ),
                const SizedBox(height: 16),

                // 2. Liquid Glass Exercise Overview & 1-Hand Stepper Logger
                LiquidGlassSurface(
                  borderRadius: 26,
                  blurEnabled: false,
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Tags Row (zero bullets)
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          _MetaTag(
                            label: (widget.workout.journeyName != null &&
                                    widget.workout.journeyName!.isNotEmpty)
                                ? widget.workout.journeyName!
                                : widget.workout.bodyFocus,
                            c: c,
                          ),
                          _MetaTag(
                            label: widget.workout.level,
                            accent: true,
                            c: c,
                          ),
                          _MetaTag(
                            label: _formatDuration(widget.exercise.duration),
                            c: c,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        widget.exercise.name,
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.35,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        widget.exercise.description,
                        style: TextStyle(
                          color: c.textSecondary,
                          fontSize: 13.5,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Divider(height: 1, color: c.divider),
                      const SizedBox(height: 16),

                      // 1-Hand Liquid Glass Pill Stepper Controls
                      if (widget.exercise.requiresWeightInput) ...[
                        _GlassStepperRow(
                          label: 'Weight',
                          unit: _weightUnit,
                          controller: _weightCtrl,
                          decimal: true,
                          decrementKey: const ValueKey('step_weight_minus'),
                          incrementKey: const ValueKey('step_weight_plus'),
                          onDecrement: () => _stepWeight(-weightStep),
                          onIncrement: () => _stepWeight(weightStep),
                          onManualChanged: (v) {
                            final parsed = double.tryParse(v);
                            if (parsed != null) _weightValue = parsed;
                          },
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Divider(height: 1, color: c.divider),
                        ),
                      ],
                      _GlassStepperRow(
                        label: 'Sets',
                        unit: 'sets',
                        controller: _setsCtrl,
                        decimal: false,
                        decrementKey: const ValueKey('step_sets_minus'),
                        incrementKey: const ValueKey('step_sets_plus'),
                        onDecrement: () => _stepSets(-1),
                        onIncrement: () => _stepSets(1),
                        onManualChanged: (v) {
                          final parsed = int.tryParse(v);
                          if (parsed != null) _setsValue = parsed;
                        },
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Divider(height: 1, color: c.divider),
                      ),
                      _GlassStepperRow(
                        label: 'Reps',
                        unit: 'reps',
                        controller: _repsCtrl,
                        decimal: false,
                        decrementKey: const ValueKey('step_reps_minus'),
                        incrementKey: const ValueKey('step_reps_plus'),
                        onDecrement: () => _stepReps(-1),
                        onIncrement: () => _stepReps(1),
                        onManualChanged: (v) {
                          final parsed = int.tryParse(v);
                          if (parsed != null) _repsValue = parsed;
                        },
                      ),
                      const SizedBox(height: 18),
                      TempoBouncyButton(
                        key: const ValueKey('exercise_log_cta'),
                        height: 52,
                        onPressed: _saving ? null : _logSet,
                        child: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Log Set & Mark Done'),
                      ),
                    ],
                  ),
                ),

                // 3. Clean Grouped Previous Logs Card
                if (_history.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                    child: Text(
                      'Previous Logs',
                      style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.25,
                      ),
                    ),
                  ),
                  AppleCard(
                    borderRadius: 22,
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: List.generate(
                        _history.take(8).length,
                        (idx) {
                          final item = _history[idx];
                          final dt = item.recordedAt.toLocal();
                          final isLast = idx == _history.take(8).length - 1;
                          return Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 13,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        DateFormat('MMM d, h:mm a').format(dt),
                                        style: TextStyle(
                                          color: c.textSecondary,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                    if (item.weightUsed > 0) ...[
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 9,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: c.accent.withValues(
                                            alpha: c.isDark ? 0.20 : 0.11,
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(99),
                                        ),
                                        child: Text(
                                          WeightUnitHelper.format(
                                            item.weightUsed,
                                            _weightUnit,
                                          ),
                                          style: TextStyle(
                                            color: c.accent,
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w700,
                                            fontFeatures: const [
                                              FontFeature.tabularFigures(),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                    Text(
                                      '${item.setsPerformed} × ${item.repsPerformed}',
                                      style: TextStyle(
                                        color: c.textPrimary,
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w700,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (!isLast)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  child: Divider(height: 1, color: c.divider),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaTag extends StatelessWidget {
  final String label;
  final bool accent;
  final AppColors c;

  const _MetaTag({
    required this.label,
    required this.c,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
      decoration: BoxDecoration(
        color: accent
            ? c.accent.withValues(alpha: c.isDark ? 0.22 : 0.12)
            : (c.isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.05)),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: accent ? c.accent : c.textSecondary,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _GlassStepperRow extends StatelessWidget {
  final String label;
  final String unit;
  final TextEditingController controller;
  final bool decimal;
  final Key decrementKey;
  final Key incrementKey;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;
  final ValueChanged<String> onManualChanged;

  const _GlassStepperRow({
    required this.label,
    required this.unit,
    required this.controller,
    required this.decimal,
    required this.decrementKey,
    required this.incrementKey,
    required this.onDecrement,
    required this.onIncrement,
    required this.onManualChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.15,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  unit,
                  style: TextStyle(
                    color: c.textTertiary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          // Unified Liquid Glass Stepper Pill Capsule housing - / value / +
          TempoTouchLightEffect(
            borderRadius: 999,
            emitLight: false,
            receiveScatter: true,
            intensity: 0.9,
            child: CustomPaint(
              foregroundPainter: LiquidGlassRimPainter(
                borderRadius: 999,
                isDark: c.isDark,
                intensity: 0.78,
                strokeWidth: 1.0,
                showTopMeniscus: false,
              ),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: c.isDark
                      ? Colors.white.withValues(alpha: 0.075)
                      : Colors.black.withValues(alpha: 0.048),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TempoGlassCircleButton(
                      key: decrementKey,
                      size: 36,
                      enableBlur: false,
                      tooltip: 'Decrease $label',
                      icon: Icon(
                        CupertinoIcons.minus,
                        color: c.textPrimary,
                        size: 15,
                      ),
                      onPressed: onDecrement,
                    ),
                    SizedBox(
                      width: 68,
                      child: TextField(
                        controller: controller,
                        textAlign: TextAlign.center,
                        keyboardType:
                            TextInputType.numberWithOptions(decimal: decimal),
                        onChanged: onManualChanged,
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 17.5,
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                        decoration: const InputDecoration(
                          isDense: true,
                          filled: false,
                          fillColor: Colors.transparent,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 4),
                        ),
                      ),
                    ),
                    TempoGlassCircleButton(
                      key: incrementKey,
                      size: 36,
                      enableBlur: false,
                      tooltip: 'Increase $label',
                      icon: Icon(
                        CupertinoIcons.plus,
                        color: c.textPrimary,
                        size: 15,
                      ),
                      onPressed: onIncrement,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
