import 'progress_tracking_service.dart';
import 'tempo_rust_db.dart';
import 'workout_goal_service.dart';
import 'workout_history_service.dart';

class FitnessChatContext {
  const FitnessChatContext({
    required this.displayName,
    required this.goalLabel,
    required this.summaryLines,
  });

  final String? displayName;
  final String goalLabel;
  final List<String> summaryLines;

  String toPromptBlock() {
    final buffer = StringBuffer();
    buffer.writeln('User context:');
    if (displayName != null && displayName!.trim().isNotEmpty) {
      buffer.writeln('- name: ${displayName!.trim()}');
    }
    buffer.writeln('- primary_goal: $goalLabel');
    for (final line in summaryLines) {
      buffer.writeln('- $line');
    }
    return buffer.toString().trimRight();
  }
}

class FitnessChatContextService {
  FitnessChatContextService({
    ProgressTrackingService? progressTrackingService,
    WorkoutHistoryService? workoutHistoryService,
  })  : _progressTrackingService =
            progressTrackingService ?? ProgressTrackingService(),
        _workoutHistoryService =
            workoutHistoryService ?? WorkoutHistoryService();

  final ProgressTrackingService _progressTrackingService;
  final WorkoutHistoryService _workoutHistoryService;

  Future<FitnessChatContext> buildContext() async {
    final db = TempoRustDb.instance;
    final pid = await db.getSetting('active_profile_id');
    if (pid == null || pid.isEmpty) {
      return const FitnessChatContext(
        displayName: null,
        goalLabel: 'General Fitness',
        summaryLines: ['no active local profile selected'],
      );
    }

    final profile = await db.getProfile(pid);
    if (profile == null) {
      return const FitnessChatContext(
        displayName: null,
        goalLabel: 'General Fitness',
        summaryLines: ['profile not found'],
      );
    }

    final summaryLines = <String>[];
    if (profile.age > 0) summaryLines.add('age: ${profile.age}');
    if (profile.heightCm > 0) {
      summaryLines.add('height_cm: ${profile.heightCm.toStringAsFixed(0)}');
    }
    if (profile.weightKg > 0) {
      summaryLines.add('weight_kg: ${profile.weightKg.toStringAsFixed(1)}');
    }
    if (profile.bmi > 0) {
      summaryLines.add('bmi: ${profile.bmi.toStringAsFixed(1)}');
    }

    final longestStreak = await _progressTrackingService.getLongestStreak();
    if (longestStreak > 0) {
      summaryLines.add('longest_streak_days: $longestStreak');
    }

    final highestWeightRecord =
        await _progressTrackingService.getHighestWeightRecord();
    if (highestWeightRecord != null && highestWeightRecord.weightUsed > 0) {
      summaryLines.add(
        'highest_weight_record: ${highestWeightRecord.exerciseName} ${highestWeightRecord.weightUsed.toStringAsFixed(1)} kg',
      );
    }

    final recentWorkouts = await _workoutHistoryService.getWorkoutHistory();
    for (final workout in recentWorkouts.take(3)) {
      final d = workout.completedAt;
      summaryLines.add(
        'recent_workout: ${workout.workout.title} on ${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
      );
    }

    if (summaryLines.isEmpty) {
      summaryLines.add('local offline profile ready');
    }

    return FitnessChatContext(
      displayName: profile.displayName,
      goalLabel: goalLabel(profile.fitnessGoal),
      summaryLines: summaryLines,
    );
  }
}
