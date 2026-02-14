import 'package:flutter/material.dart';
import '../services/preferences_service.dart';

/// Lightweight theme mode notifier.
/// Persists the choice via [PreferencesService].
class ThemeProvider extends ChangeNotifier {
  final PreferencesService _prefs;
  bool _isDarkMode = true;

  ThemeProvider(this._prefs);

  bool get isDarkMode => _isDarkMode;
  ThemeMode get themeMode => _isDarkMode ? ThemeMode.dark : ThemeMode.light;

  /// Load persisted preference – call once at startup.
  Future<void> init() async {
    _isDarkMode = await _prefs.isDarkMode();
    notifyListeners();
  }

  /// Toggle and persist.
  Future<void> toggle() async {
    _isDarkMode = !_isDarkMode;
    notifyListeners();
    await _prefs.setDarkMode(_isDarkMode);
  }

  /// Set explicit value.
  Future<void> setDarkMode(bool value) async {
    if (_isDarkMode == value) return;
    _isDarkMode = value;
    notifyListeners();
    await _prefs.setDarkMode(value);
  }
}
