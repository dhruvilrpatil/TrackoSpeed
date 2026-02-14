import 'dart:async';
import 'package:flutter_compass/flutter_compass.dart';

/// Service for getting device compass heading
class CompassService {
  Stream<double>? _compassStream;

  /// Get compass heading stream (0-360 degrees)
  Stream<double> get headingStream {
    _compassStream ??= FlutterCompass.events?.map((event) {
      return event.heading ?? 0.0;
    }) ?? Stream.value(0.0);
    return _compassStream!;
  }

  /// Get compass direction as string (N, NE, E, SE, S, SW, W, NW)
  String getDirectionString(double heading) {
    if (heading >= 337.5 || heading < 22.5) return 'N';
    if (heading >= 22.5 && heading < 67.5) return 'NE';
    if (heading >= 67.5 && heading < 112.5) return 'E';
    if (heading >= 112.5 && heading < 157.5) return 'SE';
    if (heading >= 157.5 && heading < 202.5) return 'S';
    if (heading >= 202.5 && heading < 247.5) return 'SW';
    if (heading >= 247.5 && heading < 292.5) return 'W';
    if (heading >= 292.5 && heading < 337.5) return 'NW';
    return 'N';
  }

  /// Get formatted compass string (e.g., "NW 315°")
  String getCompassString(double heading) {
    final direction = getDirectionString(heading);
    final degrees = heading.round();
    return '$direction $degrees°';
  }

  /// Check if compass is available on device
  Future<bool> isAvailable() async {
    try {
      final events = FlutterCompass.events;
      return events != null;
    } catch (e) {
      return false;
    }
  }

  /// Dispose resources
  void dispose() {
    _compassStream = null;
  }
}

