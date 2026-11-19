import 'package:chewie/chewie.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../models/local_profile.dart';
import '../models/workout_model.dart';
import '../services/active_profile_provider.dart';
import '../services/tempo_rust_db.dart';
import '../services/video_mapping_service.dart';
import '../services/workout_goal_service.dart';
import '../theme/app_colors.dart';
import '../widgets/liquid_glass_surface.dart';
import '../widgets/tempo_sliver_header.dart';

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
  final _weightCtrl = TextEditingController();
  final _repsCtrl = TextEditingController(text: '10');
  final _setsCtrl = TextEditingController(text: '3');

  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  bool _videoError = false;
  bool _saving = false;
  List<LocalExerciseRecord> _history = [];

  @override
  void initState() {
    super.initState();
    _initVideo();
    _loadHistory();
  }

  Future<void> _initVideo() async {
    final path = widget.exercise.customVideoAsset ??
        VideoMappingService.getVideoPath(
          widget.exercise.name,
          journeyName: widget.workout.journeyName,
          workoutTitle: widget.workout.title,
        );
    if (path == null || path.isEmpty) {
      if (mounted) setState(() => _videoError = true);
      return;
    }

    try {
      final controller = VideoPlayerController.asset(path);
      await controller.initialize();
      final chewie = ChewieController(
        videoPlayerController: controller,
        autoPlay: true,
        looping: true,
        showControls: true,
        aspectRatio: controller.value.aspectRatio > 0
            ? controller.value.aspectRatio
            : 16 / 9,
      );
      if (!mounted) {
        controller.dispose();
        chewie.dispose();
        return;
      }
      setState(() {
        _videoController = controller;
        _chewieController = chewie;
      });
    } catch (_) {
      if (mounted) setState(() => _videoError = true);
    }
  }

  Future<void> _loadHistory() async {
    final pid = context.read<ActiveProfileProvider>().activeProfileId;
    if (pid == null) return;
    final list = await TempoRustDb.instance.getExerciseRecords(
      pid,
      exerciseName: widget.exercise.name,
    );
    if (mounted) {
      setState(() {
        _history = list;
        if (list.isNotEmpty && _weightCtrl.text.isEmpty && list.first.weightUsed > 0) {
          _weightCtrl.text = list.first.weightUsed.toStringAsFixed(1);
        }
      });
    }
  }

  Future<void> _logSet() async {
    final profileProvider = context.read<ActiveProfileProvider>();
    final pid = profileProvider.activeProfileId;
    if (pid == null) return;

    final weight = double.tryParse(_weightCtrl.text.trim()) ?? 0.0;
    final reps = int.tryParse(_repsCtrl.text.trim()) ?? 10;
    final sets = int.tryParse(_setsCtrl.text.trim()) ?? 3;

    setState(() => _saving = true);
    try {
      await TempoRustDb.instance.logExerciseRecord(
        profileId: pid,
        exerciseName: widget.exercise.name,
        workoutId: widget.workout.id,
        weightUsed: widget.exercise.requiresWeightInput ? weight : 0.0,
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Exercise set logged locally!')),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not log exercise: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _chewieController?.dispose();
    _videoController?.dispose();
    _weightCtrl.dispose();
    _repsCtrl.dispose();
    _setsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);

    return Scaffold(
      backgroundColor: c.scaffold,
      body: CustomScrollView(
        slivers: [
          TempoSliverHeader(
            title: widget.exercise.name,
            showBackButton: true,
            onBack: () => Navigator.of(context).pop(false),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            sliver: SliverList.list(
              children: [
                // Video Demonstration Card
          ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Container(
              height: 220,
              color: Colors.black,
              child: _chewieController != null
                  ? Chewie(controller: _chewieController!)
                  : Center(
                      child: _videoError
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  CupertinoIcons.film,
                                  color: Colors.white54,
                                  size: 36,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  widget.exercise.name,
                                  style: const TextStyle(color: Colors.white70),
                                ),
                              ],
                            )
                          : const CupertinoActivityIndicator(
                              color: Colors.white,
                            ),
                    ),
            ),
          ),
          const SizedBox(height: 16),

          AppleCard(
            borderRadius: 24,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        (widget.workout.journeyName != null &&
                                widget.workout.journeyName!.isNotEmpty)
                            ? '${widget.workout.journeyName!} · ${widget.workout.bodyFocus}'
                            : widget.workout.bodyFocus,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2.5,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: c.cardBorder),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        widget.workout.level,
                        style: TextStyle(
                          color: c.textSecondary,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  widget.exercise.name,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  widget.exercise.description,
                  style: TextStyle(
                    color: c.textSecondary,
                    fontSize: 14,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 18),
                Divider(height: 1, color: c.divider),
                const SizedBox(height: 16),
                Row(
                  children: [
                    if (widget.exercise.requiresWeightInput) ...[
                      Expanded(
                        child: _field('Weight (kg)', _weightCtrl, '20', c),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(child: _field('Sets', _setsCtrl, '3', c)),
                    const SizedBox(width: 10),
                    Expanded(child: _field('Reps', _repsCtrl, '10', c)),
                  ],
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: c.accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: _saving ? null : _logSet,
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Log Set & Mark Done',
                            style: TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),

          if (_history.isNotEmpty) ...[
            Text(
              'Previous Logs',
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 10),
            AppleCard(
              borderRadius: 22,
              padding: EdgeInsets.zero,
              child: Column(
                children: List.generate(
                  _history.take(8).length,
                  (i) {
                    final rec = _history[i];
                    final isLast = i == _history.take(8).length - 1;
                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 14,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                DateFormat('MMM d, yyyy')
                                    .format(rec.recordedAt.toLocal()),
                                style: TextStyle(
                                  color: c.textSecondary,
                                  fontSize: 13.5,
                                ),
                              ),
                              Text(
                                rec.weightUsed > 0
                                    ? '${rec.weightUsed.toStringAsFixed(1)} kg · ${rec.setsPerformed}×${rec.repsPerformed}'
                                    : '${rec.setsPerformed} sets × ${rec.repsPerformed} reps',
                                style: TextStyle(
                                  color: c.textPrimary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
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
                            padding: const EdgeInsets.symmetric(horizontal: 18),
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

  Widget _field(
    String label,
    TextEditingController ctrl,
    String hint,
    AppColors c,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: c.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: TextStyle(
            color: c.textPrimary,
            fontWeight: FontWeight.w700,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: c.textHint),
          ),
        ),
      ],
    );
  }
}
