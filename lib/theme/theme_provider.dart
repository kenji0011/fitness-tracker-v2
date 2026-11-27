import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider with ChangeNotifier {
  static const String _prefKey = 'tempo_theme_mode_v1';

  ThemeMode _themeMode = ThemeMode.light;
  bool _loaded = false;

  ThemeProvider({bool autoLoad = true}) {
    if (autoLoad) {
      initialize();
    }
  }

  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;

  Future<void> initialize() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefKey);
      if (saved == 'system' && _themeMode != ThemeMode.system) {
        _themeMode = ThemeMode.system;
        notifyListeners();
      } else if (saved == 'dark' && _themeMode != ThemeMode.dark) {
        _themeMode = ThemeMode.dark;
        notifyListeners();
      } else if (saved == 'light' && _themeMode != ThemeMode.light) {
        _themeMode = ThemeMode.light;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> toggleTheme(bool isDark) async {
    await setThemeMode(isDark ? ThemeMode.dark : ThemeMode.light);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = switch (mode) {
        ThemeMode.system => 'system',
        ThemeMode.dark => 'dark',
        ThemeMode.light => 'light',
      };
      await prefs.setString(_prefKey, encoded);
    } catch (_) {}
  }
}
