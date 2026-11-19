import '../data/exercise_data2.dart';
import '../data/fitness_journey_workouts.dart';
import '../models/workout_model.dart';
import 'tempo_rust_db.dart';
import 'workout_goal_service.dart';

class ProgressTrackingService {
  final TempoRustDb _db = TempoRustDb.instance;
  final String? _explicitProfileId;

  ProgressTrackingService({String? profileId}) : _explicitProfileId = profileId;

  final List<Workout> _knownWorkouts = [
    ...exerciseWorkouts,
    ...fitnessJourneyWorkoutsById.values.expand((workouts) => workouts),
  ];

  Future<String?> _resolveProfileId() async {
    if (_explicitProfileId != null && _explicitProfileId.isNotEmpty) {
      return _explicitProfileId;
    }
    return _db.getSetting('active_profile_id');
  }

  Future<List<DateTime>> getCompletedWorkoutDates() async {
    final pid = await _resolveProfileId();
    if (pid == null || pid.isEmpty) return [];

    final items = await _db.getCompletedWorkouts(pid, limit: 500);
    return items
        .where((w) => !w.isCheated)
        .map((w) => w.completedAt)
        .toList();
  }

  Future<List<ExerciseRecord>> getExerciseRecords() async {
    final pid = await _resolveProfileId();
    if (pid == null || pid.isEmpty) return [];

    final localRecords = await _db.getExerciseRecords(pid);
    final records = localRecords.map((r) {
      final base = ExerciseRecord(
        exerciseName: r.exerciseName,
        weightUsed: r.weightUsed,
        repsPerformed: r.repsPerformed,
        setsPerformed: r.setsPerformed,
        timestamp: r.recordedAt,
        workoutId: r.workoutId,
        bodyFocus: r.bodyFocus,
        level: r.level,
        journeyId: r.journeyId,
        journeyName: r.journeyName,
        primaryGoal: r.primaryGoal,
        goalTags: r.goalTags.map(normalizeGoalType).toSet().toList(),
      );
      return _enrichRecord(base);
    }).toList();

    records.sort((a, b) {
      final aTime = a.timestamp;
      final bTime = b.timestamp;
      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      return bTime.compareTo(aTime);
    });
    return records;
  }

  Future<int> getLongestStreak() async {
    final pid = await _resolveProfileId();
    if (pid == null || pid.isEmpty) return 0;
    try {
      final summary = await _db.getDashboardSummary(pid);
      return summary.longestStreak;
    } catch (_) {
      return 0;
    }
  }

  Future<int> getCurrentStreak() async {
    final pid = await _resolveProfileId();
    if (pid == null || pid.isEmpty) return 0;
    try {
      final summary = await _db.getDashboardSummary(pid);
      return summary.currentStreak;
    } catch (_) {
      return 0;
    }
  }

  Future<ExerciseRecord?> getHighestWeightRecord() async {
    final records = await getExerciseRecords();
    if (records.isEmpty) return null;

    ExerciseRecord? highest;
    for (final record in records) {
      if (highest == null || record.weightUsed > highest.weightUsed) {
        highest = record;
      }
    }
    return highest;
  }

  Future<String?> getRecommendedGoalType() async {
    final pid = await _resolveProfileId();
    if (pid == null || pid.isEmpty) return null;

    final profile = await _db.getProfile(pid);
    if (profile == null) return null;
    return resolvePreferredGoalFromUserData(profile.toLegacyUserMap());
  }

  Future<List<ExerciseRecord>> getExerciseRecordsByCategory(
    String category,
  ) async {
    final allRecords = await getExerciseRecords();
    if (category == 'All') return allRecords;
    return allRecords
        .where((record) => _matchesCategory(record, category))
        .toList(growable: false);
  }

  Future<List<ExerciseRecord>> getExerciseRecordsByDifficulty(
    String difficulty,
  ) async {
    final allRecords = await getExerciseRecords();
    if (difficulty == 'All') return allRecords;
    return allRecords
        .where((record) => _matchesDifficulty(record, difficulty))
        .toList(growable: false);
  }

  Future<List<ExerciseRecord>> getExerciseRecordsByGoal(String goalType) async {
    final allRecords = await getExerciseRecords();
    if (goalType == 'All') return allRecords;
    final normalizedGoal = normalizeGoalType(goalType);
    return allRecords
        .where((record) => _matchesGoal(record, normalizedGoal))
        .toList(growable: false);
  }

  Future<List<String>> getCompletedExerciseNames() async {
    final records = await getExerciseRecords();
    return records.map((r) => r.exerciseName).toSet().toList();
  }

  ExerciseRecord _enrichRecord(ExerciseRecord record) {
    final workout = _findWorkoutForRecord(record);
    if (workout == null) {
      final normalizedPrimaryGoal = record.primaryGoal.trim().isNotEmpty
          ? normalizeGoalType(record.primaryGoal)
          : generalFitnessGoal;
      final normalizedGoalTags = record.goalTags.isNotEmpty
          ? record.goalTags.map(normalizeGoalType).toSet().toList()
          : <String>[normalizedPrimaryGoal];

      return record.copyWith(
        primaryGoal: normalizedPrimaryGoal,
        goalTags: normalizedGoalTags,
      );
    }

    return record.copyWith(
      bodyFocus: record.bodyFocus.trim().isNotEmpty
          ? record.bodyFocus
          : workout.bodyFocus,
      level: record.level.trim().isNotEmpty ? record.level : workout.level,
      journeyId: record.journeyId.trim().isNotEmpty
          ? record.journeyId
          : (workout.journeyId ?? ''),
      journeyName: record.journeyName.trim().isNotEmpty
          ? record.journeyName
          : (workout.journeyName ?? ''),
      primaryGoal: inferPrimaryGoalForWorkout(workout),
      goalTags: inferGoalTagsForWorkout(workout),
    );
  }

  Workout? _findWorkoutForRecord(ExerciseRecord record) {
    for (final workout in _knownWorkouts) {
      if (workout.id == record.workoutId) return workout;
    }
    for (final workout in _knownWorkouts) {
      if (workout.exerciseList.any((e) => e.name == record.exerciseName)) {
        return workout;
      }
    }
    return null;
  }

  bool _matchesCategory(ExerciseRecord record, String category) {
    final normalizedCategory = category.toLowerCase().trim();
    final normalizedFocus = record.bodyFocus.toLowerCase().trim();
    if (normalizedFocus.contains(normalizedCategory) ||
        normalizedCategory.contains(normalizedFocus)) {
      return true;
    }
    if (normalizedCategory == 'arms') {
      return const {'arm', 'arms', 'triceps', 'biceps', 'forearms'}
          .contains(normalizedFocus);
    }
    if (normalizedCategory == 'abs') {
      return normalizedFocus == 'abs' || normalizedFocus == 'core';
    }
    return false;
  }

  bool _matchesDifficulty(ExerciseRecord record, String difficulty) {
    final d = difficulty.toLowerCase().trim();
    final l = record.level.toLowerCase().trim();
    return l.contains(d) || d.contains(l);
  }

  bool _matchesGoal(ExerciseRecord record, String goalType) {
    if (record.primaryGoal.trim().isNotEmpty &&
        normalizeGoalType(record.primaryGoal) == goalType) {
      return true;
    }
    return record.goalTags.map(normalizeGoalType).contains(goalType);
  }
}

class ExerciseRecord {
  final String exerciseName;
  final double weightUsed;
  final int repsPerformed;
  final int setsPerformed;
  final DateTime? timestamp;
  final String workoutId;
  final String bodyFocus;
  final String level;
  final String journeyId;
  final String journeyName;
  final String primaryGoal;
  final List<String> goalTags;

  ExerciseRecord({
    required this.exerciseName,
    required this.weightUsed,
    required this.repsPerformed,
    required this.setsPerformed,
    this.timestamp,
    required this.workoutId,
    this.bodyFocus = '',
    this.level = '',
    this.journeyId = '',
    this.journeyName = '',
    this.primaryGoal = '',
    this.goalTags = const [],
  });

  ExerciseRecord copyWith({
    String? exerciseName,
    double? weightUsed,
    int? repsPerformed,
    int? setsPerformed,
    DateTime? timestamp,
    String? workoutId,
    String? bodyFocus,
    String? level,
    String? journeyId,
    String? journeyName,
    String? primaryGoal,
    List<String>? goalTags,
  }) {
    return ExerciseRecord(
      exerciseName: exerciseName ?? this.exerciseName,
      weightUsed: weightUsed ?? this.weightUsed,
      repsPerformed: repsPerformed ?? this.repsPerformed,
      setsPerformed: setsPerformed ?? this.setsPerformed,
      timestamp: timestamp ?? this.timestamp,
      workoutId: workoutId ?? this.workoutId,
      bodyFocus: bodyFocus ?? this.bodyFocus,
      level: level ?? this.level,
      journeyId: journeyId ?? this.journeyId,
      journeyName: journeyName ?? this.journeyName,
      primaryGoal: primaryGoal ?? this.primaryGoal,
      goalTags: goalTags ?? this.goalTags,
    );
  }
}
