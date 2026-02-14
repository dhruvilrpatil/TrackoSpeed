import 'package:shared_preferences/shared_preferences.dart';

/// Persists dashboard statistics (AVG, MAX, DIST) across app launches.
class DashboardStatsService {
  static const String _keyAvgSpeed = 'dashboard_avg_speed';
  static const String _keyMaxSpeed = 'dashboard_max_speed';
  static const String _keyTotalDistance = 'dashboard_total_distance';

  /// Load persisted stats. Returns a map with avgSpeed, maxSpeed, totalDistance.
  Future<DashboardStats> loadStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return DashboardStats(
        avgSpeed: prefs.getDouble(_keyAvgSpeed) ?? 0.0,
        maxSpeed: prefs.getDouble(_keyMaxSpeed) ?? 0.0,
        totalDistance: prefs.getDouble(_keyTotalDistance) ?? 0.0,
      );
    } catch (_) {
      return DashboardStats.empty();
    }
  }

  /// Save current stats to persistent storage.
  Future<void> saveStats(DashboardStats stats) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_keyAvgSpeed, stats.avgSpeed);
      await prefs.setDouble(_keyMaxSpeed, stats.maxSpeed);
      await prefs.setDouble(_keyTotalDistance, stats.totalDistance);
    } catch (_) {
      // Silently fail
    }
  }

  /// Clear persisted stats (e.g. on reset).
  Future<void> clearStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyAvgSpeed);
      await prefs.remove(_keyMaxSpeed);
      await prefs.remove(_keyTotalDistance);
    } catch (_) {
      // Silently fail
    }
  }
}

/// Immutable container for dashboard statistics.
class DashboardStats {
  final double avgSpeed;
  final double maxSpeed;
  final double totalDistance;

  const DashboardStats({
    required this.avgSpeed,
    required this.maxSpeed,
    required this.totalDistance,
  });

  factory DashboardStats.empty() => const DashboardStats(
        avgSpeed: 0.0,
        maxSpeed: 0.0,
        totalDistance: 0.0,
      );
}
