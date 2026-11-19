import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/local_profile.dart';

typedef _TempoDispatchNative =
    ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8>, ffi.Pointer<Utf8>);
typedef _TempoDispatchDart =
    ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8>, ffi.Pointer<Utf8>);
typedef _TempoFreeNative = ffi.Void Function(ffi.Pointer<Utf8>);
typedef _TempoFreeDart = void Function(ffi.Pointer<Utf8>);

/// Local database gateway powered by the native Rust `tempo_core` (rusqlite) library.
/// On mobile/desktop with native library bundled, every call executes directly in Rust SQLite.
/// On web or host unit-test environments without the native shared object, transparently
/// falls back to a local JSON store so tests and previews still work seamlessly.
class TempoRustDb {
  TempoRustDb._();
  static final TempoRustDb instance = TempoRustDb._();

  bool _initialized = false;
  bool _usingRustNative = false;
  _TempoDispatchDart? _dispatch;
  _TempoFreeDart? _freeString;

  // Fallback state (only used when native Rust shared library is unavailable, e.g. Web/test)
  _FallbackLocalStore? _fallback;

  bool get isUsingRustNative => _usingRustNative;

  Future<void> init({String? customDbPath}) async {
    if (_initialized) return;

    if (!kIsWeb) {
      final lib = _tryLoadNativeLib();
      if (lib != null) {
        _dispatch = lib
            .lookup<ffi.NativeFunction<_TempoDispatchNative>>('tempo_dispatch')
            .asFunction();
        _freeString = lib
            .lookup<ffi.NativeFunction<_TempoFreeNative>>('tempo_free_string')
            .asFunction();
        _usingRustNative = true;

        String dbPath;
        if (customDbPath != null) {
          dbPath = customDbPath;
        } else {
          final docsDir = await getApplicationDocumentsDirectory();
          dbPath = p.join(docsDir.path, 'tempo_fitness.db');
        }
        _invokeRust('init_db', {'dbPath': dbPath});
        _initialized = true;
        debugPrint('TempoRustDb initialized with native Rust SQLite at $dbPath');
        return;
      }
    }

    _fallback = await _FallbackLocalStore.load();
    _usingRustNative = false;
    _initialized = true;
    debugPrint('TempoRustDb running with local JSON fallback store');
  }

  ffi.DynamicLibrary? _tryLoadNativeLib() {
    try {
      if (Platform.isAndroid || Platform.isLinux) {
        return ffi.DynamicLibrary.open('libtempo_core.so');
      } else if (Platform.isIOS) {
        return ffi.DynamicLibrary.process();
      } else if (Platform.isMacOS) {
        return ffi.DynamicLibrary.open('libtempo_core.dylib');
      } else if (Platform.isWindows) {
        return ffi.DynamicLibrary.open('tempo_core.dll');
      }
    } catch (e) {
      debugPrint('Native libtempo_core not found on this target: $e');
    }
    return null;
  }

  dynamic _invokeRust(String method, Map<String, dynamic> payload) {
    final mPtr = method.toNativeUtf8();
    final pPtr = jsonEncode(payload).toNativeUtf8();
    try {
      final resPtr = _dispatch!(mPtr, pPtr);
      try {
        final raw = resPtr.toDartString();
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        if (decoded['ok'] != true) {
          throw Exception(decoded['error'] ?? 'Rust DB error in $method');
        }
        return decoded['data'];
      } finally {
        _freeString!(resPtr);
      }
    } finally {
      calloc.free(mPtr);
      calloc.free(pPtr);
    }
  }

  Future<dynamic> _call(String method, Map<String, dynamic> payload) async {
    if (!_initialized) {
      await init();
    }
    if (_usingRustNative) {
      return _invokeRust(method, payload);
    }
    return _fallback!.dispatch(method, payload);
  }

  static String todayKey([DateTime? date]) =>
      DateFormat('yyyy-MM-dd').format(date ?? DateTime.now());

  // --- Profiles & PIN ---

  Future<List<LocalProfile>> listProfiles() async {
    final data = await _call('list_profiles', {});
    return (data as List<dynamic>)
        .map((e) => LocalProfile.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<LocalProfile?> getProfile(String id) async {
    final data = await _call('get_profile', {'id': id});
    if (data == null) return null;
    return LocalProfile.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<LocalProfile> createProfile({
    required String displayName,
    required String pin,
    String avatarPath = '',
    String gender = '',
    String birthdate = '',
    int age = 0,
    double heightCm = 0,
    double weightKg = 0,
    double waistCm = 0,
    double sleepHours = 0,
    String fitnessGoal = 'general_fitness',
    int dailyCaloriesGoal = 2500,
    int dailyMinutesGoal = 60,
    int dailyWorkoutsGoal = 3,
    int dailyStepsGoal = 10000,
    bool hasCompletedProfile = true,
  }) async {
    final data = await _call('create_profile', {
      'displayName': displayName,
      'pin': pin,
      'avatarPath': avatarPath,
      'gender': gender,
      'birthdate': birthdate,
      'age': age,
      'heightCm': heightCm,
      'weightKg': weightKg,
      'waistCm': waistCm,
      'sleepHours': sleepHours,
      'fitnessGoal': fitnessGoal,
      'dailyCaloriesGoal': dailyCaloriesGoal,
      'dailyMinutesGoal': dailyMinutesGoal,
      'dailyWorkoutsGoal': dailyWorkoutsGoal,
      'dailyStepsGoal': dailyStepsGoal,
      'hasCompletedProfile': hasCompletedProfile,
    });
    return LocalProfile.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<bool> verifyPin(String profileId, String pin) async {
    final data = await _call('verify_pin', {
      'profileId': profileId,
      'pin': pin,
    });
    return (data as Map<String, dynamic>)['valid'] == true;
  }

  Future<bool> updateProfilePin({
    required String profileId,
    required String currentPin,
    required String newPin,
  }) async {
    final data = await _call('update_profile_pin', {
      'profileId': profileId,
      'currentPin': currentPin,
      'newPin': newPin,
    });
    return (data as Map<String, dynamic>)['updated'] == true;
  }

  Future<LocalProfile> updateProfile({
    required String id,
    String? displayName,
    String? avatarPath,
    String? gender,
    String? birthdate,
    int? age,
    double? heightCm,
    double? weightKg,
    double? waistCm,
    double? sleepHours,
    String? fitnessGoal,
    String? selectedJourneyId,
    String? selectedJourneyName,
    int? dailyCaloriesGoal,
    int? dailyMinutesGoal,
    int? dailyWorkoutsGoal,
    int? dailyStepsGoal,
    bool? hasCompletedProfile,
  }) async {
    final payload = <String, dynamic>{'id': id};
    if (displayName != null) payload['displayName'] = displayName;
    if (avatarPath != null) payload['avatarPath'] = avatarPath;
    if (gender != null) payload['gender'] = gender;
    if (birthdate != null) payload['birthdate'] = birthdate;
    if (age != null) payload['age'] = age;
    if (heightCm != null) payload['heightCm'] = heightCm;
    if (weightKg != null) payload['weightKg'] = weightKg;
    if (waistCm != null) payload['waistCm'] = waistCm;
    if (sleepHours != null) payload['sleepHours'] = sleepHours;
    if (fitnessGoal != null) payload['fitnessGoal'] = fitnessGoal;
    if (selectedJourneyId != null) {
      payload['selectedJourneyId'] = selectedJourneyId;
    }
    if (selectedJourneyName != null) {
      payload['selectedJourneyName'] = selectedJourneyName;
    }
    if (dailyCaloriesGoal != null) {
      payload['dailyCaloriesGoal'] = dailyCaloriesGoal;
    }
    if (dailyMinutesGoal != null) {
      payload['dailyMinutesGoal'] = dailyMinutesGoal;
    }
    if (dailyWorkoutsGoal != null) {
      payload['dailyWorkoutsGoal'] = dailyWorkoutsGoal;
    }
    if (dailyStepsGoal != null) payload['dailyStepsGoal'] = dailyStepsGoal;
    if (hasCompletedProfile != null) {
      payload['hasCompletedProfile'] = hasCompletedProfile;
    }

    final data = await _call('update_profile', payload);
    return LocalProfile.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<bool> deleteProfile(String profileId) async {
    final data = await _call('delete_profile', {'profileId': profileId});
    return (data as Map<String, dynamic>)['deleted'] == true;
  }

  // --- Settings ---

  Future<String?> getSetting(String key) async {
    final data = await _call('get_setting', {'key': key});
    return (data as Map<String, dynamic>)['value']?.toString();
  }

  Future<void> setSetting(String key, String value) async {
    await _call('set_setting', {'key': key, 'value': value});
  }

  // --- Dashboard & Activity ---

  Future<LocalDashboardSummary> getDashboardSummary(
    String profileId, {
    String? dateKey,
  }) async {
    final data = await _call('get_dashboard_summary', {
      'profileId': profileId,
      'dateKey': dateKey ?? todayKey(),
    });
    return LocalDashboardSummary.fromJson(
      Map<String, dynamic>.from(data as Map),
    );
  }

  Future<LocalDailyActivity> upsertDailyActivity({
    required String profileId,
    String? dateKey,
    int? steps,
    int? calories,
    int? minutes,
    int? workoutsCount,
    bool increment = false,
  }) async {
    final payload = <String, dynamic>{
      'profileId': profileId,
      'dateKey': dateKey ?? todayKey(),
      'increment': increment,
    };
    if (steps != null) payload['steps'] = steps;
    if (calories != null) payload['calories'] = calories;
    if (minutes != null) payload['minutes'] = minutes;
    if (workoutsCount != null) payload['workoutsCount'] = workoutsCount;

    final data = await _call('upsert_daily_activity', payload);
    return LocalDailyActivity.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<List<LocalDailyActivity>> getDailyActivityHistory(
    String profileId, {
    int limit = 30,
  }) async {
    final data = await _call('get_daily_activity_history', {
      'profileId': profileId,
      'limit': limit,
    });
    return (data as List<dynamic>)
        .map(
          (e) =>
              LocalDailyActivity.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList();
  }

  // --- Body Metrics ---

  Future<LocalProfile> logBodyMetric({
    required String profileId,
    required String metricType, // weight | waist | sleep | height
    required double value,
    DateTime? recordedAt,
  }) async {
    final data = await _call('log_body_metric', {
      'profileId': profileId,
      'metricType': metricType,
      'value': value,
      if (recordedAt != null) 'recordedAt': recordedAt.toUtc().toIso8601String(),
    });
    return LocalProfile.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<List<BodyMetricPoint>> getBodyMetricHistory(
    String profileId,
    String metricType, {
    int limit = 60,
  }) async {
    final data = await _call('get_body_metric_history', {
      'profileId': profileId,
      'metricType': metricType,
      'limit': limit,
    });
    return (data as List<dynamic>)
        .map(
          (e) => BodyMetricPoint.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList();
  }

  // --- Workouts & Exercises ---

  Future<LocalCompletedWorkout> logCompletedWorkout({
    required String profileId,
    required String workoutId,
    required String title,
    String durationLabel = '',
    String exercisesLabel = '',
    String level = '',
    String bodyFocus = '',
    String journeyId = '',
    String journeyName = '',
    int actualDurationSec = 0,
    int expectedDurationSec = 0,
    int caloriesBurned = 0,
    bool isCheated = false,
    DateTime? completedAt,
  }) async {
    final data = await _call('log_completed_workout', {
      'profileId': profileId,
      'workoutId': workoutId,
      'title': title,
      'durationLabel': durationLabel,
      'exercisesLabel': exercisesLabel,
      'level': level,
      'bodyFocus': bodyFocus,
      'journeyId': journeyId,
      'journeyName': journeyName,
      'actualDurationSec': actualDurationSec,
      'expectedDurationSec': expectedDurationSec,
      'caloriesBurned': caloriesBurned,
      'isCheated': isCheated,
      'dateKey': todayKey(completedAt),
      if (completedAt != null)
        'completedAt': completedAt.toUtc().toIso8601String(),
    });
    return LocalCompletedWorkout.fromJson(
      Map<String, dynamic>.from(data as Map),
    );
  }

  Future<List<LocalCompletedWorkout>> getCompletedWorkouts(
    String profileId, {
    int limit = 200,
  }) async {
    final data = await _call('get_completed_workouts', {
      'profileId': profileId,
      'limit': limit,
    });
    return (data as List<dynamic>)
        .map(
          (e) => LocalCompletedWorkout.fromJson(
            Map<String, dynamic>.from(e as Map),
          ),
        )
        .toList();
  }

  Future<LocalExerciseRecord> logExerciseRecord({
    required String profileId,
    required String exerciseName,
    String workoutId = '',
    double weightUsed = 0,
    int repsPerformed = 0,
    int setsPerformed = 0,
    String bodyFocus = '',
    String level = '',
    String journeyId = '',
    String journeyName = '',
    String primaryGoal = '',
    List<String> goalTags = const [],
    DateTime? recordedAt,
  }) async {
    final data = await _call('log_exercise_record', {
      'profileId': profileId,
      'exerciseName': exerciseName,
      'workoutId': workoutId,
      'weightUsed': weightUsed,
      'repsPerformed': repsPerformed,
      'setsPerformed': setsPerformed,
      'bodyFocus': bodyFocus,
      'level': level,
      'journeyId': journeyId,
      'journeyName': journeyName,
      'primaryGoal': primaryGoal,
      'goalTags': goalTags,
      if (recordedAt != null) 'recordedAt': recordedAt.toUtc().toIso8601String(),
    });
    return LocalExerciseRecord.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<List<LocalExerciseRecord>> getExerciseRecords(
    String profileId, {
    String? exerciseName,
  }) async {
    final data = await _call('get_exercise_records', {
      'profileId': profileId,
      if (exerciseName != null) 'exerciseName': exerciseName,
    });
    return (data as List<dynamic>)
        .map(
          (e) =>
              LocalExerciseRecord.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList();
  }

  // --- Journey Progress ---

  Future<LocalJourneyProgress> upsertJourneyProgress(
    LocalJourneyProgress progress,
  ) async {
    final data = await _call('upsert_journey_progress', progress.toJson());
    return LocalJourneyProgress.fromJson(
      Map<String, dynamic>.from(data as Map),
    );
  }

  Future<List<LocalJourneyProgress>> getJourneyProgress(
    String profileId, {
    String? journeyId,
  }) async {
    final data = await _call('get_journey_progress', {
      'profileId': profileId,
      if (journeyId != null) 'journeyId': journeyId,
    });
    return (data as List<dynamic>)
        .map(
          (e) => LocalJourneyProgress.fromJson(
            Map<String, dynamic>.from(e as Map),
          ),
        )
        .toList();
  }

  // --- Progress Photos ---

  Future<LocalProgressPhoto> addProgressPhoto({
    required String profileId,
    required String filePath,
    String caption = '',
    String category = 'General',
    double? weightKg,
    DateTime? takenAt,
  }) async {
    final data = await _call('add_progress_photo', {
      'profileId': profileId,
      'filePath': filePath,
      'caption': caption,
      'category': category,
      if (weightKg != null) 'weightKg': weightKg,
      if (takenAt != null) 'takenAt': takenAt.toUtc().toIso8601String(),
    });
    return LocalProgressPhoto.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<List<LocalProgressPhoto>> listProgressPhotos(String profileId) async {
    final data = await _call('list_progress_photos', {'profileId': profileId});
    return (data as List<dynamic>)
        .map(
          (e) =>
              LocalProgressPhoto.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList();
  }

  Future<bool> deleteProgressPhoto(String photoId) async {
    final data = await _call('delete_progress_photo', {'photoId': photoId});
    return (data as Map<String, dynamic>)['deleted'] == true;
  }
}

/// Pure-Dart SharedPreferences fallback strictly for Web / host widget tests
/// when the compiled native Rust shared library is not present on the host OS.
class _FallbackLocalStore {
  static const _storageKey = 'tempo_fallback_db_v1';
  final SharedPreferences _prefs;
  final Map<String, dynamic> _db;
  final _uuid = const Uuid();

  _FallbackLocalStore._(this._prefs, this._db);

  static Future<_FallbackLocalStore> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    Map<String, dynamic> db;
    if (raw != null && raw.isNotEmpty) {
      db = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } else {
      db = {
        'profiles': <dynamic>[],
        'daily_activity': <dynamic>[],
        'body_metrics_history': <dynamic>[],
        'completed_workouts': <dynamic>[],
        'exercise_records': <dynamic>[],
        'journey_progress': <dynamic>[],
        'progress_photos': <dynamic>[],
        'settings': <String, dynamic>{},
        'seq': 1,
      };
    }
    return _FallbackLocalStore._(prefs, db);
  }

  Future<void> _save() async {
    await _prefs.setString(_storageKey, jsonEncode(_db));
  }

  int _nextId() {
    final next = ((_db['seq'] as num?)?.toInt() ?? 1) + 1;
    _db['seq'] = next;
    return next;
  }

  double _bmi(double h, double w) {
    if (h < 50 || h > 300 || w < 15 || w > 450) return 0;
    final hm = h / 100.0;
    return double.parse((w / (hm * hm)).toStringAsFixed(1));
  }

  Future<dynamic> dispatch(String method, Map<String, dynamic> payload) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final profiles = (_db['profiles'] as List).cast<Map<String, dynamic>>();

    switch (method) {
      case 'list_profiles':
        return profiles.map((p) => {...p, 'hasPin': (p['pin'] ?? '').toString().isNotEmpty}).toList();
      case 'get_profile':
        final id = payload['id'];
        final found = profiles.where((p) => p['id'] == id).firstOrNull;
        return found == null ? null : {...found, 'hasPin': (found['pin'] ?? '').toString().isNotEmpty};
      case 'create_profile':
        final h = (payload['heightCm'] as num?)?.toDouble() ?? 0;
        final w = (payload['weightKg'] as num?)?.toDouble() ?? 0;
        final prof = <String, dynamic>{
          'id': _uuid.v4(),
          'displayName': (payload['displayName'] ?? '').toString().trim(),
          'avatarPath': (payload['avatarPath'] ?? '').toString(),
          'pin': (payload['pin'] ?? '').toString().trim(),
          'hasPin': (payload['pin'] ?? '').toString().trim().isNotEmpty,
          'gender': (payload['gender'] ?? '').toString(),
          'birthdate': (payload['birthdate'] ?? '').toString(),
          'age': (payload['age'] as num?)?.toInt() ?? 0,
          'heightCm': h,
          'weightKg': w,
          'waistCm': (payload['waistCm'] as num?)?.toDouble() ?? 0,
          'sleepHours': (payload['sleepHours'] as num?)?.toDouble() ?? 0,
          'bmi': _bmi(h, w),
          'fitnessGoal': (payload['fitnessGoal'] ?? 'general_fitness').toString(),
          'selectedJourneyId': '',
          'selectedJourneyName': '',
          'dailyCaloriesGoal': (payload['dailyCaloriesGoal'] as num?)?.toInt() ?? 2500,
          'dailyMinutesGoal': (payload['dailyMinutesGoal'] as num?)?.toInt() ?? 60,
          'dailyWorkoutsGoal': (payload['dailyWorkoutsGoal'] as num?)?.toInt() ?? 3,
          'dailyStepsGoal': (payload['dailyStepsGoal'] as num?)?.toInt() ?? 10000,
          'hasCompletedProfile': payload['hasCompletedProfile'] == true,
          'createdAt': now,
          'updatedAt': now,
        };
        profiles.add(prof);
        await _save();
        return prof;
      case 'verify_pin':
        final found = profiles.where((p) => p['id'] == payload['profileId']).firstOrNull;
        if (found == null) throw Exception('Profile not found');
        return {'valid': (found['pin'] ?? '') == (payload['pin'] ?? '')};
      case 'update_profile_pin':
        final found = profiles.where((p) => p['id'] == payload['profileId']).firstOrNull;
        if (found == null) throw Exception('Profile not found');
        if ((found['pin'] ?? '') != (payload['currentPin'] ?? '')) {
          throw Exception('Current PIN is incorrect');
        }
        found['pin'] = payload['newPin'];
        found['updatedAt'] = now;
        await _save();
        return {'updated': true};
      case 'update_profile':
        final found = profiles.where((p) => p['id'] == payload['id']).firstOrNull;
        if (found == null) throw Exception('Profile not found');
        for (final entry in payload.entries) {
          if (entry.key != 'id') found[entry.key] = entry.value;
        }
        found['bmi'] = _bmi(
          (found['heightCm'] as num?)?.toDouble() ?? 0,
          (found['weightKg'] as num?)?.toDouble() ?? 0,
        );
        found['updatedAt'] = now;
        await _save();
        return {...found, 'hasPin': (found['pin'] ?? '').toString().isNotEmpty};
      case 'delete_profile':
        final pid = payload['profileId'];
        profiles.removeWhere((p) => p['id'] == pid);
        for (final key in [
          'daily_activity',
          'body_metrics_history',
          'completed_workouts',
          'exercise_records',
          'journey_progress',
          'progress_photos',
        ]) {
          (_db[key] as List).removeWhere((e) => e['profileId'] == pid);
        }
        await _save();
        return {'deleted': true};
      case 'get_setting':
        return {'value': (_db['settings'] as Map)[payload['key']]};
      case 'set_setting':
        (_db['settings'] as Map)[payload['key']] = payload['value'];
        await _save();
        return {'saved': true};
      case 'upsert_daily_activity':
        final list = (_db['daily_activity'] as List).cast<Map<String, dynamic>>();
        final pid = payload['profileId'];
        final dk = payload['dateKey'];
        var item = list.where((e) => e['profileId'] == pid && e['dateKey'] == dk).firstOrNull;
        if (item == null) {
          item = {
            'profileId': pid,
            'dateKey': dk,
            'steps': 0,
            'calories': 0,
            'minutes': 0,
            'workoutsCount': 0,
            'updatedAt': now,
          };
          list.add(item);
        }
        final inc = payload['increment'] == true;
        for (final k in ['steps', 'calories', 'minutes', 'workoutsCount']) {
          if (payload[k] != null) {
            final v = (payload[k] as num).toInt();
            item[k] = inc ? ((item[k] as num).toInt() + v) : v;
          }
        }
        item['updatedAt'] = now;
        await _save();
        return item;
      case 'get_daily_activity_history':
        final list = (_db['daily_activity'] as List)
            .cast<Map<String, dynamic>>()
            .where((e) => e['profileId'] == payload['profileId'])
            .toList()
          ..sort((a, b) => (a['dateKey'] as String).compareTo(b['dateKey'] as String));
        return list;
      case 'log_body_metric':
        final pid = payload['profileId'];
        final metric = payload['metricType'].toString();
        final val = (payload['value'] as num).toDouble();
        if (metric != 'height') {
          (_db['body_metrics_history'] as List).add({
            'id': _nextId(),
            'profileId': pid,
            'metricType': metric,
            'value': val,
            'recordedAt': payload['recordedAt'] ?? now,
          });
        }
        final found = profiles.where((p) => p['id'] == pid).first;
        if (metric == 'weight') found['weightKg'] = val;
        if (metric == 'height') found['heightCm'] = val;
        if (metric == 'waist') found['waistCm'] = val;
        if (metric == 'sleep') found['sleepHours'] = val;
        found['bmi'] = _bmi(
          (found['heightCm'] as num?)?.toDouble() ?? 0,
          (found['weightKg'] as num?)?.toDouble() ?? 0,
        );
        found['updatedAt'] = now;
        await _save();
        return found;
      case 'get_body_metric_history':
        return (_db['body_metrics_history'] as List)
            .cast<Map<String, dynamic>>()
            .where((e) =>
                e['profileId'] == payload['profileId'] &&
                e['metricType'] == payload['metricType'])
            .toList();
      case 'log_completed_workout':
        final item = {
          ...payload,
          'id': _uuid.v4(),
          'completedAt': payload['completedAt'] ?? now,
        };
        (_db['completed_workouts'] as List).add(item);
        if (payload['isCheated'] != true) {
          await dispatch('upsert_daily_activity', {
            'profileId': payload['profileId'],
            'dateKey': payload['dateKey'] ?? TempoRustDb.todayKey(),
            'calories': payload['caloriesBurned'] ?? 0,
            'minutes': (((payload['actualDurationSec'] as num?)?.toInt() ?? 60) ~/ 60).clamp(1, 600),
            'workoutsCount': 1,
            'increment': true,
          });
        }
        await _save();
        return item;
      case 'get_completed_workouts':
        final list = (_db['completed_workouts'] as List)
            .cast<Map<String, dynamic>>()
            .where((e) => e['profileId'] == payload['profileId'])
            .toList()
          ..sort((a, b) => (b['completedAt'] as String).compareTo(a['completedAt'] as String));
        return list;
      case 'log_exercise_record':
        final rec = {
          ...payload,
          'id': _nextId(),
          'recordedAt': payload['recordedAt'] ?? now,
        };
        (_db['exercise_records'] as List).add(rec);
        await _save();
        return rec;
      case 'get_exercise_records':
        return (_db['exercise_records'] as List)
            .cast<Map<String, dynamic>>()
            .where((e) =>
                e['profileId'] == payload['profileId'] &&
                (payload['exerciseName'] == null ||
                    e['exerciseName'] == payload['exerciseName']))
            .toList();
      case 'upsert_journey_progress':
        final list = (_db['journey_progress'] as List).cast<Map<String, dynamic>>();
        if (payload['isSelected'] == true) {
          for (final j in list.where((e) => e['profileId'] == payload['profileId'])) {
            j['isSelected'] = false;
          }
        }
        list.removeWhere((e) =>
            e['profileId'] == payload['profileId'] &&
            e['journeyId'] == payload['journeyId']);
        final saved = {...payload, 'updatedAt': now};
        list.add(saved);
        await _save();
        return saved;
      case 'get_journey_progress':
        return (_db['journey_progress'] as List)
            .cast<Map<String, dynamic>>()
            .where((e) =>
                e['profileId'] == payload['profileId'] &&
                (payload['journeyId'] == null ||
                    e['journeyId'] == payload['journeyId']))
            .toList();
      case 'add_progress_photo':
        final photo = {
          ...payload,
          'id': _uuid.v4(),
          'takenAt': payload['takenAt'] ?? now,
        };
        (_db['progress_photos'] as List).add(photo);
        await _save();
        return photo;
      case 'list_progress_photos':
        final list = (_db['progress_photos'] as List)
            .cast<Map<String, dynamic>>()
            .where((e) => e['profileId'] == payload['profileId'])
            .toList()
          ..sort((a, b) => (b['takenAt'] as String).compareTo(a['takenAt'] as String));
        return list;
      case 'delete_progress_photo':
        (_db['progress_photos'] as List).removeWhere((e) => e['id'] == payload['photoId']);
        await _save();
        return {'deleted': true};
      case 'get_dashboard_summary':
        final pid = payload['profileId'].toString();
        final dk = (payload['dateKey'] ?? TempoRustDb.todayKey()).toString();
        final prof = profiles.where((p) => p['id'] == pid).first;
        final history = (await dispatch('get_daily_activity_history', {'profileId': pid})) as List;
        final today = history.where((e) => e['dateKey'] == dk).firstOrNull ??
            {
              'dateKey': dk,
              'steps': 0,
              'calories': 0,
              'minutes': 0,
              'workoutsCount': 0,
              'updatedAt': now,
            };
        final workouts = (await dispatch('get_completed_workouts', {'profileId': pid})) as List;
        final photos = (await dispatch('list_progress_photos', {'profileId': pid})) as List;
        return {
          'profile': prof,
          'today': today,
          'dailyHistory': history,
          'weightHistory': await dispatch('get_body_metric_history', {'profileId': pid, 'metricType': 'weight'}),
          'waistHistory': await dispatch('get_body_metric_history', {'profileId': pid, 'metricType': 'waist'}),
          'sleepHistory': await dispatch('get_body_metric_history', {'profileId': pid, 'metricType': 'sleep'}),
          'currentStreak': workouts.isEmpty ? 0 : 1,
          'longestStreak': workouts.isEmpty ? 0 : 1,
          'totalWorkouts': workouts.where((w) => w['isCheated'] != true).length,
          'recentWorkouts': workouts.take(10).toList(),
          'latestPhotoPath': photos.isEmpty ? null : photos.first['filePath'],
        };
      default:
        throw Exception('Unknown fallback method: $method');
    }
  }
}
