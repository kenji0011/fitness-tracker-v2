import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/local_profile.dart';
import 'tempo_rust_db.dart';

class LocalBackupEntry {
  final String fileName;
  final String filePath;
  final DateTime modifiedAt;
  final int sizeBytes;

  const LocalBackupEntry({
    required this.fileName,
    required this.filePath,
    required this.modifiedAt,
    required this.sizeBytes,
  });
}

/// Offline JSON backup & restore for Tempo's active local profile
/// (body metrics, daily activity, completed workouts, exercise PRs, settings).
class LocalBackupService {
  static Future<Directory> _backupDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'tempo_backups'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Exports the active profile's fitness records into a timestamped JSON file.
  static Future<({String fileName, String filePath, int recordCount})>
      exportProfileBackup(LocalProfile profile) async {
    final db = TempoRustDb.instance;
    final pid = profile.id;

    final results = await Future.wait([
      db.getBodyMetricHistory(pid, 'weight', limit: 500),
      db.getBodyMetricHistory(pid, 'sleep', limit: 500),
      db.getBodyMetricHistory(pid, 'waist', limit: 500),
      db.getBodyMetricHistory(pid, 'water', limit: 500),
      db.getDailyActivityHistory(pid, limit: 365),
      db.getCompletedWorkouts(pid, limit: 500),
      db.getExerciseRecords(pid),
      db.getSetting('weight_unit_$pid'),
      db.getSetting('sleep_goal_hrs_$pid'),
      db.getSetting('water_goal_ml_$pid'),
      db.getSetting('summary_features_$pid'),
      db.getSetting('custom_workouts_v1_$pid'),
    ]);

    final weightPts = results[0] as List<BodyMetricPoint>;
    final sleepPts = results[1] as List<BodyMetricPoint>;
    final waistPts = results[2] as List<BodyMetricPoint>;
    final waterPts = results[3] as List<BodyMetricPoint>;
    final daily = results[4] as List<LocalDailyActivity>;
    final workouts = results[5] as List<LocalCompletedWorkout>;
    final exercises = results[6] as List<LocalExerciseRecord>;

    final payload = <String, dynamic>{
      'schema': 'tempo_backup_v1',
      'exportedAt': DateTime.now().toIso8601String(),
      'profile': {
        'displayName': profile.displayName,
        'gender': profile.gender,
        'age': profile.age,
        'heightCm': profile.heightCm,
        'weightKg': profile.weightKg,
        'dailyCaloriesGoal': profile.dailyCaloriesGoal,
        'dailyStepsGoal': profile.dailyStepsGoal,
        'dailyMinutesGoal': profile.dailyMinutesGoal,
      },
      'settings': {
        'weight_unit': results[7],
        'sleep_goal_hrs': results[8],
        'water_goal_ml': results[9],
        'summary_features': results[10],
        'custom_workouts_v1': results[11],
      },
      'bodyMetrics': {
        'weight': weightPts
            .map((e) => {'v': e.value, 't': e.recordedAt.toIso8601String()})
            .toList(),
        'sleep': sleepPts
            .map((e) => {'v': e.value, 't': e.recordedAt.toIso8601String()})
            .toList(),
        'waist': waistPts
            .map((e) => {'v': e.value, 't': e.recordedAt.toIso8601String()})
            .toList(),
        'water': waterPts
            .map((e) => {'v': e.value, 't': e.recordedAt.toIso8601String()})
            .toList(),
      },
      'dailyActivity': daily
          .map(
            (d) => {
              'dateKey': d.dateKey,
              'steps': d.steps,
              'calories': d.calories,
              'minutes': d.minutes,
              'workoutsCount': d.workoutsCount,
            },
          )
          .toList(),
      'completedWorkouts': workouts
          .map(
            (w) => {
              'workoutId': w.workoutId,
              'title': w.title,
              'durationLabel': w.durationLabel,
              'exercisesLabel': w.exercisesLabel,
              'level': w.level,
              'bodyFocus': w.bodyFocus,
              'journeyId': w.journeyId,
              'journeyName': w.journeyName,
              'actualDurationSec': w.actualDurationSec,
              'expectedDurationSec': w.expectedDurationSec,
              'caloriesBurned': w.caloriesBurned,
              'completedAt': w.completedAt.toIso8601String(),
            },
          )
          .toList(),
      'exerciseRecords': exercises
          .map(
            (r) => {
              'exerciseName': r.exerciseName,
              'workoutId': r.workoutId,
              'weightUsed': r.weightUsed,
              'repsPerformed': r.repsPerformed,
              'setsPerformed': r.setsPerformed,
              'bodyFocus': r.bodyFocus,
              'level': r.level,
              'journeyId': r.journeyId,
              'journeyName': r.journeyName,
              'primaryGoal': r.primaryGoal,
              'goalTags': r.goalTags,
            },
          )
          .toList(),
    };

    final totalCount = weightPts.length +
        sleepPts.length +
        waistPts.length +
        waterPts.length +
        daily.length +
        workouts.length +
        exercises.length;

    final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final fileName = 'Tempo_Backup_$stamp.json';
    final jsonStr = const JsonEncoder.withIndent('  ').convert(payload);

    if (kIsWeb) {
      return (fileName: fileName, filePath: '', recordCount: totalCount);
    }

    final dir = await _backupDir();
    final destPath = p.join(dir.path, fileName);
    await File(destPath).writeAsString(jsonStr, flush: true);

    return (fileName: fileName, filePath: destPath, recordCount: totalCount);
  }

  /// Lists local Tempo backup JSON files newest-first.
  static Future<List<LocalBackupEntry>> listBackups() async {
    if (kIsWeb) return const [];
    final dir = await _backupDir();
    final entries = <LocalBackupEntry>[];
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.json')) {
        final stat = await entity.stat();
        entries.add(
          LocalBackupEntry(
            fileName: p.basename(entity.path),
            filePath: entity.path,
            modifiedAt: stat.modified,
            sizeBytes: stat.size,
          ),
        );
      }
    }
    entries.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    return entries;
  }

  /// Restores metrics, daily activity, workouts, PRs, and settings from a backup JSON file.
  static Future<int> restoreBackupFile({
    required String profileId,
    required String filePath,
  }) async {
    final raw = await File(filePath).readAsString();
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic> ||
        decoded['schema'] != 'tempo_backup_v1') {
      throw const FormatException('Invalid Tempo backup file');
    }

    final db = TempoRustDb.instance;
    int restored = 0;

    final settings = decoded['settings'];
    if (settings is Map) {
      Future<void> restoreKey(String src, String dst) async {
        final v = settings[src];
        if (v is String && v.isNotEmpty) {
          await db.setSetting(dst, v);
        }
      }

      await restoreKey('weight_unit', 'weight_unit_$profileId');
      await restoreKey('sleep_goal_hrs', 'sleep_goal_hrs_$profileId');
      await restoreKey('water_goal_ml', 'water_goal_ml_$profileId');
      await restoreKey('summary_features', 'summary_features_$profileId');
      await restoreKey('custom_workouts_v1', 'custom_workouts_v1_$profileId');
    }

    final bodyMetrics = decoded['bodyMetrics'];
    if (bodyMetrics is Map) {
      for (final type in ['weight', 'sleep', 'waist', 'water']) {
        final list = bodyMetrics[type];
        if (list is List) {
          for (final item in list) {
            if (item is Map) {
              final v = (item['v'] as num?)?.toDouble();
              final t = DateTime.tryParse((item['t'] ?? '').toString());
              if (v != null && v > 0) {
                await db.logBodyMetric(
                  profileId: profileId,
                  metricType: type,
                  value: v,
                  recordedAt: t,
                );
                restored++;
              }
            }
          }
        }
      }
    }

    final daily = decoded['dailyActivity'];
    if (daily is List) {
      for (final item in daily) {
        if (item is Map) {
          final dateKey = (item['dateKey'] ?? '').toString();
          if (dateKey.isEmpty) continue;
          await db.upsertDailyActivity(
            profileId: profileId,
            dateKey: dateKey,
            steps: (item['steps'] as num?)?.toInt(),
            calories: (item['calories'] as num?)?.toInt(),
            minutes: (item['minutes'] as num?)?.toInt(),
            workoutsCount: (item['workoutsCount'] as num?)?.toInt(),
          );
          restored++;
        }
      }
    }

    final exercises = decoded['exerciseRecords'];
    if (exercises is List) {
      for (final item in exercises) {
        if (item is Map) {
          final name = (item['exerciseName'] ?? '').toString();
          if (name.isEmpty) continue;
          await db.logExerciseRecord(
            profileId: profileId,
            exerciseName: name,
            workoutId: (item['workoutId'] ?? '').toString(),
            weightUsed: (item['weightUsed'] as num?)?.toDouble() ?? 0,
            repsPerformed: (item['repsPerformed'] as num?)?.toInt() ?? 10,
            setsPerformed: (item['setsPerformed'] as num?)?.toInt() ?? 3,
            bodyFocus: (item['bodyFocus'] ?? '').toString(),
            level: (item['level'] ?? '').toString(),
            journeyId: (item['journeyId'] ?? '').toString(),
            journeyName: (item['journeyName'] ?? '').toString(),
            primaryGoal: (item['primaryGoal'] ?? '').toString(),
            goalTags: (item['goalTags'] as List? ?? const [])
                .map((e) => e.toString())
                .toList(),
          );
          restored++;
        }
      }
    }

    return restored;
  }
}
