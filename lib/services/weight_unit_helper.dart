import 'tempo_rust_db.dart';

/// Centralized `kg` <-> `lb` conversion & persistence helper so weight units
/// stay 100% synced across Summary, Weight, Profile, Exercise PRs, Progress,
/// Log Health Data, and Progress Album.
class WeightUnitHelper {
  static const double kgToLb = 2.20462262;

  static Future<String> loadUnit(String? profileId) async {
    if (profileId == null || profileId.isEmpty) return 'kg';
    final saved = await TempoRustDb.instance.getSetting('weight_unit_$profileId');
    return saved == 'lb' ? 'lb' : 'kg';
  }

  static Future<void> saveUnit(String profileId, String unit) async {
    final normalized = unit == 'lb' ? 'lb' : 'kg';
    await TempoRustDb.instance.setSetting('weight_unit_$profileId', normalized);
  }

  static double toDisplay(double kg, String unit) =>
      unit == 'lb' ? kg * kgToLb : kg;

  static double fromDisplay(double value, String unit) =>
      unit == 'lb' ? value / kgToLb : value;

  static String format(
    double kg,
    String unit, {
    int decimals = 1,
    bool includeSpace = true,
  }) {
    final v = toDisplay(kg, unit).toStringAsFixed(decimals);
    return includeSpace ? '$v $unit' : '$v$unit';
  }
}
