import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:dartz/dartz.dart';

import '../error/failures.dart';
import '../error/error_handler.dart';

/// GPS position data with speed information
class GpsData {
  final double latitude;
  final double longitude;
  final double speedMps;     // Speed in meters per second
  final double speedKmh;     // Speed in km/h
  final double accuracy;     // Accuracy in meters
  final double altitude;
  final double heading;      // Direction of travel (degrees)
  final DateTime timestamp;
  final bool isValid;

  const GpsData({
    required this.latitude,
    required this.longitude,
    required this.speedMps,
    required this.speedKmh,
    required this.accuracy,
    required this.altitude,
    required this.heading,
    required this.timestamp,
    this.isValid = true,
  });

  /// Create from Geolocator Position
  factory GpsData.fromPosition(Position position) {
    final speedMps = position.speed >= 0 ? position.speed : 0.0;
    return GpsData(
      latitude: position.latitude,
      longitude: position.longitude,
      speedMps: speedMps,
      speedKmh: speedMps * 3.6, // Convert m/s to km/h
      accuracy: position.accuracy,
      altitude: position.altitude,
      heading: position.heading,
      timestamp: position.timestamp,
      isValid: position.accuracy < 50, // Consider accurate if < 50m
    );
  }

  /// Create empty/invalid GPS data
  factory GpsData.empty() {
    return GpsData(
      latitude: 0,
      longitude: 0,
      speedMps: 0,
      speedKmh: 0,
      accuracy: 999,
      altitude: 0,
      heading: 0,
      timestamp: DateTime.now(),
      isValid: false,
    );
  }

  /// Copy with new values
  GpsData copyWith({
    double? latitude,
    double? longitude,
    double? speedMps,
    double? speedKmh,
    double? accuracy,
    double? altitude,
    double? heading,
    DateTime? timestamp,
    bool? isValid,
  }) {
    return GpsData(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      speedMps: speedMps ?? this.speedMps,
      speedKmh: speedKmh ?? this.speedKmh,
      accuracy: accuracy ?? this.accuracy,
      altitude: altitude ?? this.altitude,
      heading: heading ?? this.heading,
      timestamp: timestamp ?? this.timestamp,
      isValid: isValid ?? this.isValid,
    );
  }

  @override
  String toString() {
    return 'GpsData(lat: $latitude, lon: $longitude, speed: ${speedKmh.toStringAsFixed(1)} km/h, accuracy: ${accuracy.toStringAsFixed(1)}m)';
  }
}

/// Service for GPS/Location functionality
///
/// Provides continuous speed updates from device GPS.
/// Handles location service availability and permission states.
class GpsService with ErrorHandlerMixin {
  StreamSubscription<Position>? _positionSubscription;
  final StreamController<GpsData> _gpsController = StreamController<GpsData>.broadcast();

  GpsData _lastKnownData = GpsData.empty();
  bool _isTracking = false;

  // Kalman filter state for speed smoothing
  double _estimatedSpeed = 0;
  double _errorEstimate = 1;
  static const double _processNoise = 0.08;
  static const double _measurementNoise = 0.4;

  // Position-based speed validation
  double _prevLat = 0;
  double _prevLon = 0;
  DateTime? _prevTimestamp;

  /// Stream of GPS data updates
  Stream<GpsData> get gpsStream => _gpsController.stream;

  /// Last known GPS data
  GpsData get lastKnownData => _lastKnownData;

  /// Whether GPS tracking is active
  bool get isTracking => _isTracking;

  /// Check if location services are enabled
  Future<bool> isLocationServiceEnabled() async {
    try {
      return await Geolocator.isLocationServiceEnabled();
    } catch (e) {
      GlobalErrorHandler.handleError(e, context: 'Check location service');
      return false;
    }
  }

  /// Get current position once
  Future<Result<GpsData>> getCurrentPosition() async {
    try {
      final serviceEnabled = await isLocationServiceEnabled();
      if (!serviceEnabled) {
        return const Left(LocationFailure(
          message: 'Location services are disabled',
          code: 'SERVICE_DISABLED',
        ));
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
        timeLimit: const Duration(seconds: 10),
      );

      final gpsData = GpsData.fromPosition(position);
      _lastKnownData = gpsData;

      return Right(gpsData);
    } catch (e, stackTrace) {
      GlobalErrorHandler.handleError(e, stackTrace: stackTrace, context: 'Get current position');
      return Left(LocationFailure(
        message: 'Failed to get current position: $e',
        originalError: e,
        stackTrace: stackTrace,
      ));
    }
  }

  /// Start continuous GPS tracking
  Future<Result<void>> startTracking() async {
    if (_isTracking) {
      return const Right(null);
    }

    try {
      final serviceEnabled = await isLocationServiceEnabled();
      if (!serviceEnabled) {
        return const Left(LocationFailure(
          message: 'Location services are disabled',
          code: 'SERVICE_DISABLED',
        ));
      }

      // Configure location settings for high accuracy speed tracking
      const locationSettings = LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0, // Update on any movement
      );

      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen(
        _onPositionUpdate,
        onError: _onPositionError,
        cancelOnError: false,
      );

      _isTracking = true;
      GlobalErrorHandler.logInfo('GPS tracking started');

      return const Right(null);
    } catch (e, stackTrace) {
      GlobalErrorHandler.handleError(e, stackTrace: stackTrace, context: 'Start GPS tracking');
      return Left(LocationFailure(
        message: 'Failed to start GPS tracking: $e',
        originalError: e,
        stackTrace: stackTrace,
      ));
    }
  }

  /// Stop GPS tracking
  Future<void> stopTracking() async {
    try {
      await _positionSubscription?.cancel();
      _positionSubscription = null;
      _isTracking = false;
      GlobalErrorHandler.logInfo('GPS tracking stopped');
    } catch (e) {
      GlobalErrorHandler.handleError(e, context: 'Stop GPS tracking');
    }
  }

  /// Handle position updates with position-based speed cross-validation
  void _onPositionUpdate(Position position) {
    try {
      var gpsData = GpsData.fromPosition(position);

      // Cross-validate: compute speed from position delta and compare
      // with the sensor-reported speed. Use the more reliable one.
      double reportedSpeed = gpsData.speedKmh;
      double? positionSpeed;

      if (_prevTimestamp != null && _prevLat != 0 && _prevLon != 0) {
        final dtSec = gpsData.timestamp.difference(_prevTimestamp!).inMilliseconds / 1000.0;
        if (dtSec > 0.3 && dtSec < 10) {
          final distMeters = Geolocator.distanceBetween(
            _prevLat, _prevLon, gpsData.latitude, gpsData.longitude,
          );
          positionSpeed = (distMeters / dtSec) * 3.6; // m/s → km/h

          // If position-derived speed drastically disagrees with sensor
          // speed (by more than 30 km/h), prefer the lower one (sensor
          // glitches tend to spike high, not low).
          if ((positionSpeed - reportedSpeed).abs() > 30) {
            reportedSpeed = math.min(positionSpeed, reportedSpeed);
          }
          // When both agree roughly, average them for stability
          else if (positionSpeed > 2.0 && reportedSpeed > 2.0) {
            reportedSpeed = reportedSpeed * 0.7 + positionSpeed * 0.3;
          }
        }
      }

      _prevLat = gpsData.latitude;
      _prevLon = gpsData.longitude;
      _prevTimestamp = gpsData.timestamp;

      // Apply Kalman filter for speed smoothing
      final smoothedSpeed = _applyKalmanFilter(reportedSpeed);
      gpsData = gpsData.copyWith(speedKmh: smoothedSpeed);

      _lastKnownData = gpsData;

      if (!_gpsController.isClosed) {
        _gpsController.add(gpsData);
      }
    } catch (e) {
      GlobalErrorHandler.handleError(e, context: 'Process position update');
    }
  }

  /// Handle position errors
  void _onPositionError(dynamic error) {
    GlobalErrorHandler.handleError(error, context: 'GPS position stream error');

    // Emit invalid data to indicate GPS issues
    if (!_gpsController.isClosed) {
      _gpsController.add(GpsData.empty());
    }
  }

  /// Apply Kalman filter for speed smoothing
  ///
  /// This reduces GPS noise and provides smoother speed readings.
  /// Includes a dead-zone: speeds below 2 km/h are treated as 0
  /// to prevent GPS drift from showing 1 km/h when stationary.
  double _applyKalmanFilter(double measurement) {
    // Dead-zone: GPS noise at standstill typically reads 0.3–0.8 m/s
    // (≈ 1–3 km/h).  Clamp raw values below 2 km/h to 0.
    if (measurement < 2.0) {
      measurement = 0.0;
    }

    // Prediction update
    final priorErrorEstimate = _errorEstimate + _processNoise;

    // Measurement update
    final kalmanGain = priorErrorEstimate / (priorErrorEstimate + _measurementNoise);
    _estimatedSpeed = _estimatedSpeed + kalmanGain * (measurement - _estimatedSpeed);
    _errorEstimate = (1 - kalmanGain) * priorErrorEstimate;

    // Final dead-zone after filtering – if the smoothed value
    // is still negligible, force it to zero.
    if (_estimatedSpeed < 1.5) {
      _estimatedSpeed = 0.0;
    }

    // Ensure non-negative speed
    return _estimatedSpeed.clamp(0, 300); // Max 300 km/h
  }

  /// Calculate distance between two points in meters
  double calculateDistance(
    double startLat,
    double startLon,
    double endLat,
    double endLon,
  ) {
    try {
      return Geolocator.distanceBetween(startLat, startLon, endLat, endLon);
    } catch (e) {
      return 0;
    }
  }

  /// Open device location settings
  Future<bool> openLocationSettings() async {
    try {
      return await Geolocator.openLocationSettings();
    } catch (e) {
      GlobalErrorHandler.handleError(e, context: 'Open location settings');
      return false;
    }
  }

  /// Dispose resources
  void dispose() {
    stopTracking();
    _gpsController.close();
  }
}


