import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:dartz/dartz.dart';

import '../error/failures.dart';
import '../error/error_handler.dart';
import 'vehicle_detection_service.dart';

/// Service for image processing - drawing overlays on captured images
class ImageProcessingService with ErrorHandlerMixin {
  static const MethodChannel _channel = MethodChannel('com.trackospeed/image_processing');

  /// Render overlay on single image with vehicle data
  Future<Result<Uint8List>> renderOverlay({
    required Uint8List imageBytes,
    required BoundingBox boundingBox,
    required double speed,
    String? plateNumber,
    double userSpeed = 0,
    String? timestamp,
    double confidence = 0,
  }) async {
    try {
      final result = await _channel.invokeMethod<Uint8List>(
        'renderOverlay',
        {
          'imageBytes': imageBytes,
          'boundingBox': boundingBox.toMap(),
          'speed': speed,
          'plateNumber': plateNumber,
          'userSpeed': userSpeed,
          'timestamp': timestamp ?? DateTime.now().toIso8601String(),
          'confidence': confidence,
        },
      );

      if (result == null) {
        // Return original image if processing fails
        return Right(imageBytes);
      }

      return Right(result);
    } on PlatformException catch (e, stackTrace) {
      GlobalErrorHandler.handleError(e, stackTrace: stackTrace, context: 'Render overlay');
      // Return original image on failure
      return Right(imageBytes);
    } catch (e, stackTrace) {
      GlobalErrorHandler.handleError(e, stackTrace: stackTrace, context: 'Render overlay');
      return Right(imageBytes);
    }
  }

  /// Render multiple vehicle overlays on single image
  Future<Result<Uint8List>> renderMultipleOverlays({
    required Uint8List imageBytes,
    required List<VehicleOverlayData> vehicles,
    double userSpeed = 0,
    String? timestamp,
  }) async {
    try {
      final vehicleData = vehicles.map((v) => v.toMap()).toList();

      final result = await _channel.invokeMethod<Uint8List>(
        'renderMultipleOverlays',
        {
          'imageBytes': imageBytes,
          'vehicles': vehicleData,
          'userSpeed': userSpeed,
          'timestamp': timestamp ?? DateTime.now().toIso8601String(),
        },
      );

      if (result == null) {
        return Right(imageBytes);
      }

      return Right(result);
    } on PlatformException catch (e, stackTrace) {
      GlobalErrorHandler.handleError(e, stackTrace: stackTrace, context: 'Render multiple overlays');
      return Right(imageBytes);
    } catch (e, stackTrace) {
      GlobalErrorHandler.handleError(e, stackTrace: stackTrace, context: 'Render multiple overlays');
      return Right(imageBytes);
    }
  }
}

/// Data for rendering vehicle overlay
class VehicleOverlayData {
  final BoundingBox boundingBox;
  final double speed;
  final String? plateNumber;
  final double confidence;

  const VehicleOverlayData({
    required this.boundingBox,
    required this.speed,
    this.plateNumber,
    this.confidence = 0,
  });

  Map<String, dynamic> toMap() => {
    'boundingBox': boundingBox.toMap(),
    'speed': speed,
    'plateNumber': plateNumber,
    'confidence': confidence,
  };
}

