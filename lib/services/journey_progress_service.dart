import '../data/fitness_journey_workouts.dart';
import '../models/local_profile.dart';
import 'tempo_rust_db.dart';
import 'workout_goal_service.dart';

class JourneyProgressSnapshot {
  final int completedWorkoutsCount;
  final int cheatedWorkoutsCount;
  final int cleanWorkoutsCount;
  final int totalWorkoutsCount;
  final int completionCount;
  final int repeatCompletionCount;
  final double progressRatio;
  final double progressPercent;
  final String status;
  final bool hasStarted;
  final bool isCompleted;
  final DateTime? startedAt;
  final String? nextWorkoutId;

  const JourneyProgressSnapshot({
    required this.completedWorkoutsCount,
    required this.cheatedWorkoutsCount,
    required this.cleanWorkoutsCount,
    required this.totalWorkoutsCount,
    required this.completionCount,
    required this.repeatCompletionCount,
    required this.progressRatio,
    required this.progressPercent,
    required this.status,
    required this.hasStarted,
    required this.isCompleted,
    required this.startedAt,
    required this.nextWorkoutId,
  });
}

class JourneyProgressService {
  static String? _resolveJourneyWorkoutKey({
    required LocalCompletedWorkout item,
    required Set<String> journeyWorkoutIds,
    required Map<String, String> workoutIdByTitle,
  }) {
    if (journeyWorkoutIds.contains(item.workoutId)) {
      return item.workoutId;
    }
    return workoutIdByTitle[item.title];
  }

  static Future<JourneyProgressSnapshot> syncJourneyProgressForProfile({
    required String profileId,
    required String journeyId,
    required String journeyName,
    bool isSelected = true,
    bool markStarted = false,
    DateTime? startedAtOverride,
  }) async {
    final db = TempoRustDb.instance;
    final journeyWorkouts = getJourneyWorkouts(journeyId);
    final journeyWorkoutIds = journeyWorkouts.map((w) => w.id).toSet();
    final workoutIdByTitle = {
      for (final workout in journeyWorkouts) workout.title: workout.id,
    };
    final totalWorkoutsCount = journeyWorkouts.length;

    final existingList =
        await db.getJourneyProgress(profileId, journeyId: journeyId);
    final existing = existingList.isNotEmpty ? existingList.first : null;

    final previousStatus = existing?.status ?? 'not_started';
    final restartingCompletedJourney =
        markStarted && previousStatus == 'completed';

    int completionCount = existing?.completionCount ??
        (previousStatus == 'completed' ? 1 : 0);

    DateTime? activeCycleStartedAt =
        existing?.activeCycleStartedAt ?? existing?.startedAt;
    if (restartingCompletedJourney) {
      activeCycleStartedAt = DateTime.now();
    } else if (markStarted && activeCycleStartedAt == null) {
      activeCycleStartedAt = startedAtOverride ?? DateTime.now();
    }

    final completedItems = await db.getCompletedWorkouts(profileId, limit: 500);
    final completedWorkoutKeys = <String>{};
    final cheatedWorkoutKeys = <String>{};
    final cleanWorkoutKeys = <String>{};

    for (final item in completedItems) {
      if (activeCycleStartedAt != null &&
          item.completedAt.isBefore(activeCycleStartedAt)) {
        continue;
      }
      final workoutKey = _resolveJourneyWorkoutKey(
        item: item,
        journeyWorkoutIds: journeyWorkoutIds,
        workoutIdByTitle: workoutIdByTitle,
      );
      if (workoutKey == null) continue;
      completedWorkoutKeys.add(workoutKey);
      if (item.isCheated) {
        cheatedWorkoutKeys.add(workoutKey);
      } else {
        cleanWorkoutKeys.add(workoutKey);
      }
    }

    final completedWorkoutsCount = completedWorkoutKeys.length;
    final cheatedWorkoutsCount = cheatedWorkoutKeys.length;
    final cleanWorkoutsCount = cleanWorkoutKeys.length;

    final hasStarted = markStarted ||
        completedWorkoutsCount > 0 ||
        previousStatus == 'in_progress' ||
        previousStatus == 'completed';
    final isCompleted =
        totalWorkoutsCount > 0 && completedWorkoutsCount >= totalWorkoutsCount;

    if (isCompleted &&
        (!restartingCompletedJourney && previousStatus != 'completed')) {
      completionCount++;
    }

    final resolvedStartedAt = startedAtOverride ??
        activeCycleStartedAt ??
        existing?.startedAt ??
        (hasStarted ? DateTime.now() : null);

    final progressRatio = totalWorkoutsCount == 0
        ? 0.0
        : (completedWorkoutsCount / totalWorkoutsCount).clamp(0.0, 1.0);
    final progressPercent =
        double.parse((progressRatio * 100).toStringAsFixed(1));
    final status = isCompleted
        ? 'completed'
        : (hasStarted ? 'in_progress' : 'not_started');

    String? nextWorkoutId;
    for (final workout in journeyWorkouts) {
      if (!completedWorkoutKeys.contains(workout.id)) {
        nextWorkoutId = workout.id;
        break;
      }
    }

    await db.upsertJourneyProgress(
      LocalJourneyProgress(
        profileId: profileId,
        journeyId: journeyId,
        journeyName: journeyName,
        isSelected: isSelected,
        isCompleted: isCompleted,
        completedWorkoutsCount: completedWorkoutsCount,
        cheatedWorkoutsCount: cheatedWorkoutsCount,
        cleanWorkoutsCount: cleanWorkoutsCount,
        totalWorkoutsCount: totalWorkoutsCount,
        completionCount: completionCount,
        progressPercent: progressPercent,
        status: status,
        startedAt: resolvedStartedAt,
        activeCycleStartedAt: resolvedStartedAt,
        completedAt: isCompleted ? DateTime.now() : null,
        nextWorkoutId: isCompleted ? null : nextWorkoutId,
      ),
    );

    if (isSelected) {
      await db.updateProfile(
        id: profileId,
        fitnessGoal: goalForJourneyId(journeyId),
        selectedJourneyId: journeyId,
        selectedJourneyName: journeyName,
      );
    }

    return JourneyProgressSnapshot(
      completedWorkoutsCount: completedWorkoutsCount,
      cheatedWorkoutsCount: cheatedWorkoutsCount,
      cleanWorkoutsCount: cleanWorkoutsCount,
      totalWorkoutsCount: totalWorkoutsCount,
      completionCount: completionCount,
      repeatCompletionCount: completionCount > 0 ? completionCount - 1 : 0,
      progressRatio: progressRatio,
      progressPercent: progressPercent,
      status: status,
      hasStarted: hasStarted,
      isCompleted: isCompleted,
      startedAt: resolvedStartedAt,
      nextWorkoutId: nextWorkoutId,
    );
  }
}
