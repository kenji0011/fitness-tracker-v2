import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/workout_model.dart';

/// Reason an exercise check-off is currently gated by [WorkoutAntiCheatEngine].
enum ExerciseLockReason {
  /// Session timer has not been started yet.
  notStarted,

  /// Minimum active effort since the previous verified exercise has not elapsed.
  cooldownRemaining,
}

/// Evaluation snapshot for checking off a specific exercise index.
@immutable
class ExerciseCheckGate {
  final bool allowed;
  final ExerciseLockReason? reason;
  final int requiredSeconds;
  final int elapsedSinceMarkSeconds;
  final int remainingSeconds;
  final double progress;

  const ExerciseCheckGate({
    required this.allowed,
    required this.reason,
    required this.requiredSeconds,
    required this.elapsedSinceMarkSeconds,
    required this.remainingSeconds,
    required this.progress,
  });

  String guidanceText() {
    if (allowed) return 'Ready to mark done';
    return switch (reason) {
      ExerciseLockReason.notStarted => 'Start the session timer first',
      ExerciseLockReason.cooldownRemaining =>
        'Keep going, ${remainingSeconds}s left to verify',
      null => 'Ready to mark done',
    };
  }
}

/// Evaluation snapshot for unlocking full workout completion.
@immutable
class WorkoutCompletionGate {
  final bool canComplete;
  final bool hasStarted;
  final int verifiedCount;
  final int totalExercises;
  final int missingExercises;
  final int elapsedSeconds;
  final int minWorkoutSeconds;
  final int remainingTotalSeconds;
  final double overallProgress;

  const WorkoutCompletionGate({
    required this.canComplete,
    required this.hasStarted,
    required this.verifiedCount,
    required this.totalExercises,
    required this.missingExercises,
    required this.elapsedSeconds,
    required this.minWorkoutSeconds,
    required this.remainingTotalSeconds,
    required this.overallProgress,
  });

  /// Concise plain-English CTA / lock subtitle (zero bullets or emojis).
  String statusLabel() {
    if (canComplete) {
      return 'Complete Workout ($verifiedCount/$totalExercises)';
    }
    if (!hasStarted) {
      return 'Start session to unlock completion';
    }
    if (missingExercises > 0 && remainingTotalSeconds > 0) {
      final exWord = missingExercises == 1 ? 'exercise' : 'exercises';
      return '$missingExercises $exWord left, ${_fmtShort(remainingTotalSeconds)} min';
    }
    if (missingExercises > 0) {
      final exWord = missingExercises == 1 ? 'exercise' : 'exercises';
      return 'Verify $missingExercises remaining $exWord';
    }
    return '${_fmtShort(remainingTotalSeconds)} active time left to verify';
  }

  static String _fmtShort(int sec) {
    final s = sec.clamp(0, 86400);
    final m = s ~/ 60;
    final rem = s % 60;
    if (m == 0) return '${rem}s';
    if (rem == 0) return '${m}m';
    return '${m}m ${rem}s';
  }
}

/// Tamper-resistant, monotonic-clock anti-cheat engine for guided Tempo
/// workouts (Balanced strictness).
///
/// Prevents instant-click completions and rapid checkbox spam by requiring:
/// 1. Active session timer driven by Dart's monotonic [Stopwatch] (immune to
///    Android system clock changes).
/// 2. Minimum active effort per exercise: `clamp(0.25 * ex.duration, 20..45s)`.
/// 3. 100% of exercises verified AND total monotonic elapsed time >=
///    `clamp(0.35 * totalExpectedSeconds, 60..600s)`.
/// 4. Proportional calorie calculation strictly bound to verified work and real
///    active effort.
class WorkoutAntiCheatEngine {
  final Workout workout;
  final Stopwatch _stopwatch;
  final int Function()? _elapsedOverrideSeconds;

  bool _hasStarted = false;
  bool _isRunning = false;
  int _lastVerifiedMarkSec = 0;
  final Set<int> _verifiedIndices = <int>{};

  WorkoutAntiCheatEngine({
    required this.workout,
    Stopwatch? stopwatch,
    int Function()? elapsedSecondsProvider,
  })  : _stopwatch = stopwatch ?? Stopwatch(),
        _elapsedOverrideSeconds = elapsedSecondsProvider;

  bool get hasStarted => _hasStarted;
  bool get isRunning => _isRunning;
  Set<int> get verifiedIndices => Set<int>.unmodifiable(_verifiedIndices);
  int get verifiedCount => _verifiedIndices.length;
  int get totalExercises => workout.exerciseList.length;

  /// Total active monotonic seconds accrued in this session.
  int get elapsedSeconds {
    final override = _elapsedOverrideSeconds;
    if (override != null) {
      return _hasStarted ? math.max(0, override()) : 0;
    }
    return _stopwatch.elapsed.inSeconds;
  }

  /// Sum of expected exercise durations across the workout (in seconds).
  int get expectedTotalSeconds {
    if (workout.exerciseList.isNotEmpty) {
      final sum = workout.exerciseList.fold<int>(
        0,
        (acc, ex) => acc + math.max(30, ex.duration),
      );
      if (sum > 0) return sum;
    }
    final match = RegExp(r'\d+').firstMatch(workout.duration);
    final mins = match != null ? (int.tryParse(match.group(0)!) ?? 20) : 20;
    return math.max(60, mins * 60);
  }

  /// Balanced minimum overall active duration required before completion.
  int get minWorkoutSeconds {
    if (workout.exerciseList.isEmpty) return 60;
    final raw = (expectedTotalSeconds * 0.35).round();
    final minPerExSum = workout.exerciseList.fold<int>(
      0,
      (acc, ex) => acc + minSecondsForExercise(ex),
    );
    // Never require less than the minimum achievable via honest per-exercise pacing,
    // while capping at 600s (10 min) so long routines stay fair for fast lifters.
    return math.max(raw, minPerExSum).clamp(60, 600);
  }

  /// Balanced per-exercise minimum effort (`25%` of duration, clamped `20..45s`).
  int minSecondsForExercise(Exercise exercise) {
    final base = math.max(20, exercise.duration);
    return (base * 0.25).round().clamp(20, 45);
  }

  /// Index of the next unfinished exercise, or `null` if all are verified.
  int? get activeExerciseIndex {
    for (int i = 0; i < workout.exerciseList.length; i++) {
      if (!_verifiedIndices.contains(i)) return i;
    }
    return null;
  }

  void start() {
    _hasStarted = true;
    _isRunning = true;
    if (_elapsedOverrideSeconds == null) {
      _stopwatch.start();
    }
  }

  void pause() {
    if (!_hasStarted) return;
    _isRunning = false;
    if (_elapsedOverrideSeconds == null) {
      _stopwatch.stop();
    }
  }

  void resume() {
    if (!_hasStarted) {
      start();
      return;
    }
    _isRunning = true;
    if (_elapsedOverrideSeconds == null) {
      _stopwatch.start();
    }
  }

  void reset() {
    _hasStarted = false;
    _isRunning = false;
    _lastVerifiedMarkSec = 0;
    _verifiedIndices.clear();
    if (_elapsedOverrideSeconds == null) {
      _stopwatch
        ..stop()
        ..reset();
    }
  }

  bool isExerciseVerified(int index) => _verifiedIndices.contains(index);

  /// Evaluates whether [index] can currently be checked off as verified.
  ExerciseCheckGate canCheckExercise(int index) {
    if (index < 0 || index >= workout.exerciseList.length) {
      return const ExerciseCheckGate(
        allowed: false,
        reason: ExerciseLockReason.notStarted,
        requiredSeconds: 20,
        elapsedSinceMarkSeconds: 0,
        remainingSeconds: 20,
        progress: 0.0,
      );
    }

    final req = minSecondsForExercise(workout.exerciseList[index]);
    if (_verifiedIndices.contains(index)) {
      return ExerciseCheckGate(
        allowed: true,
        reason: null,
        requiredSeconds: req,
        elapsedSinceMarkSeconds: req,
        remainingSeconds: 0,
        progress: 1.0,
      );
    }

    if (!_hasStarted) {
      return ExerciseCheckGate(
        allowed: false,
        reason: ExerciseLockReason.notStarted,
        requiredSeconds: req,
        elapsedSinceMarkSeconds: 0,
        remainingSeconds: req,
        progress: 0.0,
      );
    }

    final sinceMark = math.max(0, elapsedSeconds - _lastVerifiedMarkSec);
    final remaining = math.max(0, req - sinceMark);
    final progress = req > 0 ? (sinceMark / req).clamp(0.0, 1.0) : 1.0;

    if (remaining > 0) {
      return ExerciseCheckGate(
        allowed: false,
        reason: ExerciseLockReason.cooldownRemaining,
        requiredSeconds: req,
        elapsedSinceMarkSeconds: sinceMark,
        remainingSeconds: remaining,
        progress: progress,
      );
    }

    return ExerciseCheckGate(
      allowed: true,
      reason: null,
      requiredSeconds: req,
      elapsedSinceMarkSeconds: sinceMark,
      remainingSeconds: 0,
      progress: 1.0,
    );
  }

  /// Attempts to mark [index] verified. Returns the gate result; when allowed,
  /// records the exercise as verified and advances `_lastVerifiedMarkSec`.
  ExerciseCheckGate tryVerifyExercise(int index) {
    final gate = canCheckExercise(index);
    if (!gate.allowed) return gate;
    if (_verifiedIndices.add(index)) {
      _lastVerifiedMarkSec = elapsedSeconds;
    }
    return gate;
  }

  /// Unmarks a previously verified exercise without wiping accrued active time.
  void unverifyExercise(int index) {
    _verifiedIndices.remove(index);
  }

  /// Evaluates overall workout completion readiness.
  WorkoutCompletionGate evaluateCompletion() {
    final total = workout.exerciseList.length;
    final verified = _verifiedIndices.length;
    final missing = math.max(0, total - verified);
    final elapsed = elapsedSeconds;
    final minTotal = minWorkoutSeconds;
    final remainingTime = math.max(0, minTotal - elapsed);

    final exRatio = total == 0 ? 1.0 : (verified / total).clamp(0.0, 1.0);
    final timeRatio =
        minTotal == 0 ? 1.0 : (elapsed / minTotal).clamp(0.0, 1.0);
    final overall = (exRatio * 0.6 + timeRatio * 0.4).clamp(0.0, 1.0);

    final canComplete =
        _hasStarted && missing == 0 && remainingTime == 0 && total > 0;

    return WorkoutCompletionGate(
      canComplete: canComplete,
      hasStarted: _hasStarted,
      verifiedCount: verified,
      totalExercises: total,
      missingExercises: missing,
      elapsedSeconds: elapsed,
      minWorkoutSeconds: minTotal,
      remainingTotalSeconds: remainingTime,
      overallProgress: overall,
    );
  }

  /// Proportional calorie estimate strictly tied to verified exercises and real
  /// active effort so short or early-ended workouts never farm inflated kcal.
  int estimateVerifiedCalories({required double kcalPerMin}) {
    if (!_hasStarted || elapsedSeconds <= 0) return 0;
    final total = workout.exerciseList.length;
    final expected = math.max(60, expectedTotalSeconds);
    final baseFullKcal = (expected / 60.0) * kcalPerMin;

    // Combine verified exercise fraction with active time ratio so both real
    // work and real duration scale calories fairly.
    final verifiedRatio = total == 0
        ? 1.0
        : (_verifiedIndices.length / total).clamp(0.0, 1.0);
    final timeRatio = (elapsedSeconds / expected).clamp(0.0, 1.35);

    if (_verifiedIndices.isEmpty) {
      // Early-ended before checking off a movement: only award strict active-minute burn.
      return ((elapsedSeconds / 60.0) * kcalPerMin * 0.65).round().clamp(0, 600);
    }

    final effectiveFactor =
        (verifiedRatio * 0.55 + math.min(timeRatio, verifiedRatio + 0.25) * 0.45)
            .clamp(0.05, 1.35);
    return math.max(1, (baseFullKcal * effectiveFactor).round());
  }
}
