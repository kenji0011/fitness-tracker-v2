import '../data/exercise_data2.dart';
import '../data/fitness_journey_workouts.dart';
import '../models/workout_model.dart';
import 'tempo_rust_db.dart';

class WorkoutHistoryService {
  final TempoRustDb _db = TempoRustDb.instance;
  final String? _explicitProfileId;

  WorkoutHistoryService({String? profileId}) : _explicitProfileId = profileId;

  Future<String?> _resolveProfileId() async {
    if (_explicitProfileId != null && _explicitProfileId.isNotEmpty) {
      return _explicitProfileId;
    }
    return _db.getSetting('active_profile_id');
  }

  Future<List<WorkoutHistory>> getWorkoutHistory({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final pid = await _resolveProfileId();
    if (pid == null || pid.isEmpty) return [];

    final allKnown = [
      ...exerciseWorkouts,
      ...fitnessJourneyWorkoutsById.values.expand((w) => w),
    ];

    final completed = await _db.getCompletedWorkouts(pid, limit: 300);
    final history = <WorkoutHistory>[];

    for (final item in completed) {
      if (startDate != null && item.completedAt.isBefore(startDate)) continue;
      if (endDate != null && item.completedAt.isAfter(endDate)) continue;

      final workout = allKnown.firstWhere(
        (w) => w.id == item.workoutId || w.title == item.title,
        orElse: () => Workout(
          id: item.workoutId.isEmpty ? 'unknown' : item.workoutId,
          title: item.title,
          duration: item.durationLabel.isEmpty ? '20 min' : item.durationLabel,
          exercises: item.exercisesLabel.isEmpty ? 'Workout' : item.exercisesLabel,
          level: item.level.isEmpty ? 'Intermediate' : item.level,
          bodyFocus: item.bodyFocus.isEmpty ? 'Full Body' : item.bodyFocus,
          videoAsset: 'assets/default_picture.jpg',
          thumbnailAsset: 'assets/default_picture.jpg',
          exerciseList: const [],
        ),
      );

      history.add(
        WorkoutHistory(
          id: item.id,
          workout: workout,
          completedAt: item.completedAt,
          actualDuration: item.actualDurationSec,
          expectedDuration: item.expectedDurationSec,
          isCheated: item.isCheated,
        ),
      );
    }

    history.sort((a, b) => b.completedAt.compareTo(a.completedAt));
    return history;
  }

  Future<List<ExerciseHistoryRecord>> getExerciseHistory(
    String exerciseName,
  ) async {
    final pid = await _resolveProfileId();
    if (pid == null || pid.isEmpty) return [];

    final records =
        await _db.getExerciseRecords(pid, exerciseName: exerciseName);
    return records
        .map(
          (r) => ExerciseHistoryRecord(
            exerciseName: r.exerciseName,
            weightUsed: r.weightUsed,
            repsPerformed: r.repsPerformed,
            setsPerformed: r.setsPerformed,
            timestamp: r.recordedAt,
            workoutId: r.workoutId,
          ),
        )
        .toList();
  }

  Future<List<String>> getAllCompletedExercises() async {
    final pid = await _resolveProfileId();
    if (pid == null || pid.isEmpty) return [];

    final records = await _db.getExerciseRecords(pid);
    return records.map((r) => r.exerciseName).toSet().toList();
  }
}

class WorkoutHistory {
  final String id;
  final Workout workout;
  final DateTime completedAt;
  final int actualDuration;
  final int expectedDuration;
  final bool isCheated;

  WorkoutHistory({
    required this.id,
    required this.workout,
    required this.completedAt,
    required this.actualDuration,
    required this.expectedDuration,
    required this.isCheated,
  });
}

class ExerciseHistoryRecord {
  final String exerciseName;
  final double weightUsed;
  final int repsPerformed;
  final int setsPerformed;
  final DateTime? timestamp;
  final String workoutId;

  ExerciseHistoryRecord({
    required this.exerciseName,
    required this.weightUsed,
    required this.repsPerformed,
    required this.setsPerformed,
    this.timestamp,
    required this.workoutId,
  });
}
