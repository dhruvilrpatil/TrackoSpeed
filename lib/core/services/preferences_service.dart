import 'package:shared_preferences/shared_preferences.dart';

/// Service for managing app preferences and first launch detection
class PreferencesService {
  static const String _keyFirstLaunch = 'first_launch';
  static const String _keyPermissionsRequested = 'permissions_requested';
  static const String _keyDarkMode = 'dark_mode';

  /// Check if this is the first launch
  Future<bool> isFirstLaunch() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_keyFirstLaunch) ?? true;
    } catch (e) {
      return true;
    }
  }

  /// Mark that the app has been launched
  Future<void> setFirstLaunchComplete() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyFirstLaunch, false);
    } catch (e) {
      // Ignore error
    }
  }

  /// Check if permissions have been requested
  Future<bool> hasRequestedPermissions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_keyPermissionsRequested) ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Mark that permissions have been requested
  Future<void> setPermissionsRequested() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyPermissionsRequested, true);
    } catch (e) {
      // Ignore error
    }
  }

  /// Get dark mode preference (default: true = dark)
  Future<bool> isDarkMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_keyDarkMode) ?? true;
    } catch (e) {
      return true;
    }
  }

  /// Save dark mode preference
  Future<void> setDarkMode(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyDarkMode, value);
    } catch (e) {
      // Ignore error
    }
  }

  /// Reset first launch flag (for testing)
  Future<void> resetFirstLaunch() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyFirstLaunch, true);
      await prefs.setBool(_keyPermissionsRequested, false);
    } catch (e) {
      // Ignore error
    }
  }
}
