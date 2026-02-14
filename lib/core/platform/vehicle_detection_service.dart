import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:dartz/dartz.dart';

import '../error/failures.dart';
import '../error/error_handler.dart';

/// Bounding box for detected vehicle
class BoundingBox {
  final double left;
  final double top;
  final double right;
  final double bottom;

  const BoundingBox({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  double get width => right - left;
  double get height => bottom - top;
  double get centerX => (left + right) / 2;
  double get centerY => (top + bottom) / 2;
  double get area => width * height;

  factory BoundingBox.fromMap(Map<dynamic, dynamic> map) {
    return BoundingBox(
      left: (map['left'] as num?)?.toDouble() ?? 0,
      top: (map['top'] as num?)?.toDouble() ?? 0,
      right: (map['right'] as num?)?.toDouble() ?? 100,
      bottom: (map['bottom'] as num?)?.toDouble() ?? 100,
    );
  }

  Map<String, double> toMap() => {
    'left': left,
    'top': top,
    'right': right,
    'bottom': bottom,
  };

  @override
  String toString() => 'BoundingBox(l:${left.toInt()}, t:${top.toInt()}, r:${right.toInt()}, b:${bottom.toInt()})';
}

/// Detected vehicle information
class DetectedVehicle {
  final int classId;
  final String className;
  final double confidence;
  final BoundingBox boundingBox;
  final bool isFallback;
  final String? trackingId;

  const DetectedVehicle({
    required this.classId,
    required this.className,
    required this.confidence,
    required this.boundingBox,
    this.isFallback = false,
    this.trackingId,
  });

  factory DetectedVehicle.fromMap(Map<dynamic, dynamic> map) {
    return DetectedVehicle(
      classId: map['classId'] as int? ?? 0,
      className: map['className'] as String? ?? 'vehicle',
      confidence: (map['confidence'] as num?)?.toDouble() ?? 0,
      boundingBox: BoundingBox.fromMap(map['boundingBox'] as Map<dynamic, dynamic>? ?? {}),
      isFallback: map['isFallback'] as bool? ?? false,
    );
  }

  DetectedVehicle copyWith({
    int? classId,
    String? className,
    double? confidence,
    BoundingBox? boundingBox,
    bool? isFallback,
    String? trackingId,
  }) {
    return DetectedVehicle(
      classId: classId ?? this.classId,
      className: className ?? this.className,
      confidence: confidence ?? this.confidence,
      boundingBox: boundingBox ?? this.boundingBox,
      isFallback: isFallback ?? this.isFallback,
      trackingId: trackingId ?? this.trackingId,
    );
  }

  @override
  String toString() => 'DetectedVehicle($className, conf:${(confidence*100).toInt()}%, $boundingBox)';
}

/// Result of a detection call, includes vehicles and actual image dimensions
class DetectionResult {
  final List<DetectedVehicle> vehicles;
  final int imageWidth;
  final int imageHeight;

  const DetectionResult({
    required this.vehicles,
    required this.imageWidth,
    required this.imageHeight,
  });

  static const empty = DetectionResult(vehicles: [], imageWidth: 0, imageHeight: 0);
}

/// Service for vehicle detection using platform channel to native TensorFlow Lite
class VehicleDetectionService with ErrorHandlerMixin {
  static const MethodChannel _channel = MethodChannel('com.trackospeed/vehicle_detection');

  bool _isModelLoaded = false;

  /// Whether the ML model is loaded and ready
  bool get isModelLoaded => _isModelLoaded;

  /// Initialize the detection service
  Future<Result<void>> initialize() async {
    try {
      final isLoaded = await _channel.invokeMethod<bool>('isModelLoaded');
      _isModelLoaded = isLoaded ?? false;

      if (!_isModelLoaded) {
        // Try to reload model
        final reloadResult = await _channel.invokeMethod<bool>('reloadModel');
        _isModelLoaded = reloadResult ?? false;
      }

      GlobalErrorHandler.logInfo('Vehicle detection initialized: $_isModelLoaded');
      return const Right(null);
    } catch (e, stackTrace) {
      GlobalErrorHandler.handleError(e, stackTrace: stackTrace, context: 'Init vehicle detection');
      // Don't fail - service will use fallback detection
      return const Right(null);
    }
  }

  /// Detect vehicles in image — returns vehicles + actual image dimensions
  Future<Result<DetectionResult>> detectVehicles(Uint8List imageBytes) async {
    try {
      // Native now returns a Map with "detections", "imageWidth", "imageHeight"
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'detectVehicles',
        {'imageBytes': imageBytes},
      );

      if (result == null) {
        return const Right(DetectionResult(vehicles: [], imageWidth: 0, imageHeight: 0));
      }

      final detectionsList = result['detections'] as List<dynamic>? ?? [];
      final imageWidth = (result['imageWidth'] as num?)?.toInt() ?? 0;
      final imageHeight = (result['imageHeight'] as num?)?.toInt() ?? 0;

      final vehicles = detectionsList
          .map((item) => DetectedVehicle.fromMap(item as Map<dynamic, dynamic>))
          .toList();

      GlobalErrorHandler.logDebug('Detected ${vehicles.length} vehicles (img: ${imageWidth}x$imageHeight)');
      return Right(DetectionResult(
        vehicles: vehicles,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
      ));
    } on PlatformException catch (e, stackTrace) {
      GlobalErrorHandler.handleError(e, stackTrace: stackTrace, context: 'Detect vehicles');
      return Left(DetectionFailure(
        message: 'Vehicle detection failed: ${e.message}',
        code: e.code,
        originalError: e,
        stackTrace: stackTrace,
      ));
    } catch (e, stackTrace) {
      GlobalErrorHandler.handleError(e, stackTrace: stackTrace, context: 'Detect vehicles');
      return Left(DetectionFailure(
        message: 'Unexpected detection error: $e',
        originalError: e,
        stackTrace: stackTrace,
      ));
    }
  }

  /// Detect vehicles with timeout
  Future<Result<DetectionResult>> detectVehiclesWithTimeout(
    Uint8List imageBytes, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    try {
      final result = await detectVehicles(imageBytes).timeout(
        timeout,
        onTimeout: () {
          GlobalErrorHandler.logWarning('Vehicle detection timeout');
          return const Right<Failure, DetectionResult>(
            DetectionResult(vehicles: [], imageWidth: 0, imageHeight: 0),
          );
        },
      );
      return result;
    } catch (e, stackTrace) {
      GlobalErrorHandler.handleError(e, stackTrace: stackTrace, context: 'Detect with timeout');
      return const Right(DetectionResult(vehicles: [], imageWidth: 0, imageHeight: 0));
    }
  }

  /// Reload ML model
  Future<bool> reloadModel() async {
    try {
      final result = await _channel.invokeMethod<bool>('reloadModel');
      _isModelLoaded = result ?? false;
      return _isModelLoaded;
    } catch (e) {
      GlobalErrorHandler.handleError(e, context: 'Reload model');
      return false;
    }
  }

  /// Get the primary/largest detected vehicle
  DetectedVehicle? getPrimaryVehicle(List<DetectedVehicle> vehicles) {
    if (vehicles.isEmpty) return null;

    // Sort by bounding box area (largest first) and confidence
    final sorted = List<DetectedVehicle>.from(vehicles)
      ..sort((a, b) {
        // Prioritize larger, more confident detections
        final scoreA = a.boundingBox.area * a.confidence;
        final scoreB = b.boundingBox.area * b.confidence;
        return scoreB.compareTo(scoreA);
      });

    return sorted.first;
  }
}

