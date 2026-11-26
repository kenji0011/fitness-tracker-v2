import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Plays crisp workout countdown sounds (3, 2, 1, GO) natively on Android while
/// strictly respecting the phone's Silent / Vibrate / Do Not Disturb mode even
/// when media volume is turned up.
class WorkoutSoundService {
  WorkoutSoundService._();

  static final WorkoutSoundService instance = WorkoutSoundService._();

  static const MethodChannel _channel =
      MethodChannel('com.tempo.fitness/workout_sound');

  Future<bool> playCountdownTick() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    try {
      final played = await _channel.invokeMethod<bool>('playCountdownTick');
      return played ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> playCountdownGo() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    try {
      final played = await _channel.invokeMethod<bool>('playCountdownGo');
      return played ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> stop() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('stop');
    } on MissingPluginException {
      // Ignore in widget tests / non-Android runtimes.
    } on PlatformException {
      // Ignore cleanly.
    }
  }
}
