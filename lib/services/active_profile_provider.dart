import 'package:flutter/foundation.dart';

import '../models/local_profile.dart';
import 'tempo_rust_db.dart';

class ActiveProfileProvider extends ChangeNotifier {
  static const String _activeProfileKey = 'active_profile_id';
  static const String _hasSeenIntroKey = 'has_seen_intro_v1';

  final TempoRustDb _db = TempoRustDb.instance;

  List<LocalProfile> _profiles = [];
  LocalProfile? _activeProfile;
  bool _isLoading = true;
  bool _hasSeenIntro = false;
  int _dataVersion = 0;

  List<LocalProfile> get profiles => List.unmodifiable(_profiles);
  LocalProfile? get activeProfile => _activeProfile;
  String? get activeProfileId => _activeProfile?.id;
  bool get isLoading => _isLoading;
  bool get hasSeenIntro => _hasSeenIntro;
  bool get hasProfiles => _profiles.isNotEmpty;
  int get dataVersion => _dataVersion;

  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    await _db.init();
    final startup = await Future.wait([
      _db.listProfiles(),
      _db.getSetting(_hasSeenIntroKey),
      _db.getSetting(_activeProfileKey),
    ]);
    _profiles = startup[0] as List<LocalProfile>;
    _hasSeenIntro = (startup[1] as String?) == 'true';

    final savedId = startup[2] as String?;
    if (savedId != null && savedId.isNotEmpty) {
      _activeProfile = _profiles
          .where((profile) => profile.id == savedId)
          .firstOrNull;
    }
    if (_activeProfile == null && _profiles.length == 1) {
      _activeProfile = _profiles.first;
      await _db.setSetting(_activeProfileKey, _activeProfile!.id);
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> refreshProfiles() async {
    _profiles = await _db.listProfiles();
    if (_activeProfile != null) {
      _activeProfile = _profiles
          .where((p) => p.id == _activeProfile!.id)
          .firstOrNull;
    }
    _dataVersion++;
    notifyListeners();
  }

  void notifyDataChanged() {
    _dataVersion++;
    notifyListeners();
  }

  Future<void> completeIntro() async {
    if (_hasSeenIntro) return;
    _hasSeenIntro = true;
    await _db.setSetting(_hasSeenIntroKey, 'true');
    notifyListeners();
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
    bool activateImmediately = true,
  }) async {
    final created = await _db.createProfile(
      displayName: displayName,
      pin: pin,
      avatarPath: avatarPath,
      gender: gender,
      birthdate: birthdate,
      age: age,
      heightCm: heightCm,
      weightKg: weightKg,
      waistCm: waistCm,
      sleepHours: sleepHours,
      fitnessGoal: fitnessGoal,
      hasCompletedProfile: true,
    );
    _profiles = await _db.listProfiles();
    if (activateImmediately) {
      _activeProfile = created;
      await _db.setSetting(_activeProfileKey, created.id);
    }
    _dataVersion++;
    notifyListeners();
    return created;
  }

  Future<bool> switchProfileWithPin(String profileId, String pin) async {
    final valid = await _db.verifyPin(profileId, pin);
    if (!valid) return false;

    final target = await _db.getProfile(profileId);
    if (target == null) return false;

    _activeProfile = target;
    await _db.setSetting(_activeProfileKey, target.id);
    _profiles = await _db.listProfiles();
    _dataVersion++;
    notifyListeners();
    return true;
  }

  Future<void> updateActiveProfile({
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
    int? dailyCaloriesGoal,
    int? dailyMinutesGoal,
    int? dailyWorkoutsGoal,
    int? dailyStepsGoal,
  }) async {
    final current = _activeProfile;
    if (current == null) return;

    final updated = await _db.updateProfile(
      id: current.id,
      displayName: displayName,
      avatarPath: avatarPath,
      gender: gender,
      birthdate: birthdate,
      age: age,
      heightCm: heightCm,
      weightKg: weightKg,
      waistCm: waistCm,
      sleepHours: sleepHours,
      fitnessGoal: fitnessGoal,
      dailyCaloriesGoal: dailyCaloriesGoal,
      dailyMinutesGoal: dailyMinutesGoal,
      dailyWorkoutsGoal: dailyWorkoutsGoal,
      dailyStepsGoal: dailyStepsGoal,
    );
    _activeProfile = updated;
    _profiles = await _db.listProfiles();
    _dataVersion++;
    notifyListeners();
  }

  Future<bool> changePin({
    required String profileId,
    required String currentPin,
    required String newPin,
  }) async {
    return _db.updateProfilePin(
      profileId: profileId,
      currentPin: currentPin,
      newPin: newPin,
    );
  }

  Future<void> deleteProfile(String profileId) async {
    await _db.deleteProfile(profileId);
    _profiles = await _db.listProfiles();
    if (_activeProfile?.id == profileId) {
      _activeProfile = null;
      await _db.setSetting(_activeProfileKey, '');
    }
    _dataVersion++;
    notifyListeners();
  }

  Future<void> lockSession() async {
    _activeProfile = null;
    await _db.setSetting(_activeProfileKey, '');
    notifyListeners();
  }
}
