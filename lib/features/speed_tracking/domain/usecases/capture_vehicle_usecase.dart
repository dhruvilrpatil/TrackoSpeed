import 'dart:typed_data';
import 'package:dartz/dartz.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/error/error_handler.dart';
import '../entities/capture_entity.dart';
import '../repositories/capture_repository.dart';

/// Parameters for capture use case
class CaptureParams {
  final Uint8List imageBytes;
  final double estimatedVehicleSpeed;
  final double userSpeed;
  final double relativeSpeed;
  final double? gpsAccuracy;
  final double? confidenceScore;
  final String sessionId;
  final String? plateNumber;
  final String? vehicleClass;
  final Map<String, double>? boundingBox;

  const CaptureParams({
    required this.imageBytes,
    required this.estimatedVehicleSpeed,
    required this.userSpeed,
    required this.relativeSpeed,
    this.gpsAccuracy,
    this.confidenceScore,
    required this.sessionId,
    this.plateNumber,
    this.vehicleClass,
    this.boundingBox,
  });
}

/// Use case for capturing vehicle with speed data
///
/// Orchestrates:
/// 1. Creating capture entity
/// 2. Saving processed image to gallery
/// 3. Storing metadata in database
class CaptureVehicleUseCase with ErrorHandlerMixin {
  final CaptureRepository repository;

  CaptureVehicleUseCase({required this.repository});

  /// Execute the capture
  Future<Result<CaptureEntity>> call(CaptureParams params) async {
    try {
      // Create capture entity with current timestamp
      final captureEntity = CaptureEntity(
        plateNumber: params.plateNumber,
        estimatedVehicleSpeed: params.estimatedVehicleSpeed,
        userSpeed: params.userSpeed,
        relativeSpeed: params.relativeSpeed,
        gpsAccuracy: params.gpsAccuracy,
        confidenceScore: params.confidenceScore,
        imagePath: '', // Will be set by repository
        timestamp: DateTime.now(),
        sessionId: params.sessionId,
        vehicleClass: params.vehicleClass,
        boundingBox: params.boundingBox,
      );

      // Save capture (handles image + database)
      final result = await repository.saveCapture(
        imageBytes: params.imageBytes,
        captureData: captureEntity,
      );

      result.fold(
        (failure) {
          GlobalErrorHandler.logWarning('Capture failed: ${failure.message}');
        },
        (entity) {
          GlobalErrorHandler.logInfo('Capture saved: ${entity.imagePath}');
        },
      );

      return result;
    } catch (e, stackTrace) {
      GlobalErrorHandler.handleError(e, stackTrace: stackTrace, context: 'CaptureVehicleUseCase');
      return Left(UnknownFailure(
        message: 'Failed to capture vehicle: $e',
        originalError: e,
        stackTrace: stackTrace,
      ));
    }
  }
}

