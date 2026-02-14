import 'dart:typed_data';
import 'package:dartz/dartz.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/error/error_handler.dart';
import '../../../../core/platform/gallery_service.dart';
import '../../../../core/platform/image_processing_service.dart';
import '../../../../core/platform/vehicle_detection_service.dart';
import '../../domain/entities/capture_entity.dart';
import '../../domain/repositories/capture_repository.dart';
import '../datasources/capture_local_datasource.dart';

/// Implementation of CaptureRepository
class CaptureRepositoryImpl implements CaptureRepository {
  final CaptureLocalDataSource localDataSource;
  final GalleryService galleryService;
  final ImageProcessingService imageProcessingService;

  CaptureRepositoryImpl({
    required this.localDataSource,
    required this.galleryService,
    required this.imageProcessingService,
  });

  @override
  Future<Result<CaptureEntity>> saveCapture({
    required Uint8List imageBytes,
    required CaptureEntity captureData,
  }) async {
    try {
      // Render overlay on the image if bounding box data is available
      Uint8List finalBytes = imageBytes;
      if (captureData.boundingBox != null) {
        final box = captureData.boundingBox!;
        final overlayResult = await imageProcessingService.renderOverlay(
          imageBytes: imageBytes,
          boundingBox: BoundingBox(
            left: box['left'] ?? 0,
            top: box['top'] ?? 0,
            right: box['right'] ?? 0,
            bottom: box['bottom'] ?? 0,
          ),
          speed: captureData.estimatedVehicleSpeed,
          plateNumber: captureData.plateNumber,
          userSpeed: captureData.userSpeed,
          confidence: captureData.confidenceScore ?? 0,
          timestamp: captureData.timestamp.toIso8601String(),
        );
        overlayResult.fold(
          (failure) {
            GlobalErrorHandler.logWarning('Overlay render failed: ${failure.message}');
          },
          (processed) {
            finalBytes = processed;
          },
        );
      }

      // Save image to gallery
      final saveResult = await galleryService.saveImage(imageBytes: finalBytes);

      String imagePath = '';
      saveResult.fold(
        (failure) {
          GlobalErrorHandler.logWarning('Gallery save failed: ${failure.message}');
          // Continue anyway - we'll save metadata even if image save fails
        },
        (result) {
          imagePath = result.path;
        },
      );

      // Update capture with image path
      final captureWithPath = captureData.copyWith(imagePath: imagePath);

      // Save to database
      try {
        final id = await localDataSource.insertCapture(captureWithPath);
        final savedCapture = captureWithPath.copyWith(id: id);

        GlobalErrorHandler.logInfo('Capture saved: id=$id, path=$imagePath');
        return Right(savedCapture);
      } catch (e, stackTrace) {
        GlobalErrorHandler.handleError(e, stackTrace: stackTrace, context: 'Save capture to DB');
        return Left(DatabaseFailure(
          message: 'Failed to save capture to database: $e',
          originalError: e,
          stackTrace: stackTrace,
        ));
      }
    } catch (e, stackTrace) {
      GlobalErrorHandler.handleError(e, stackTrace: stackTrace, context: 'Save capture');
      return Left(UnknownFailure(
        message: 'Failed to save capture: $e',
        originalError: e,
        stackTrace: stackTrace,
      ));
    }
  }

  @override
  Future<Result<List<CaptureEntity>>> getAllCaptures() async {
    try {
      final captures = await localDataSource.getAllCaptures();
      return Right(captures);
    } catch (e, stackTrace) {
      GlobalErrorHandler.handleError(e, stackTrace: stackTrace, context: 'Get all captures');
      return Left(DatabaseFailure(
        message: 'Failed to get captures: $e',
        originalError: e,
        stackTrace: stackTrace,
      ));
    }
  }

  @override
  Future<Result<List<CaptureEntity>>> getCapturesBySession(String sessionId) async {
    try {
      final captures = await localDataSource.getCapturesBySession(sessionId);
      return Right(captures);
    } catch (e, stackTrace) {
      GlobalErrorHandler.handleError(e, stackTrace: stackTrace, context: 'Get captures by session');
      return Left(DatabaseFailure(
        message: 'Failed to get captures by session: $e',
        originalError: e,
        stackTrace: stackTrace,
      ));
    }
  }

  @override
  Future<Result<List<CaptureEntity>>> getCapturesByDateRange(DateTime start, DateTime end) async {
    try {
      final captures = await localDataSource.getCapturesByDateRange(start, end);
      return Right(captures);
    } catch (e, stackTrace) {
      GlobalErrorHandler.handleError(e, stackTrace: stackTrace, context: 'Get captures by date');
      return Left(DatabaseFailure(
        message: 'Failed to get captures by date range: $e',
        originalError: e,
        stackTrace: stackTrace,
      ));
    }
  }

  @override
  Future<Result<CaptureEntity?>> getCaptureById(int id) async {
    try {
      final capture = await localDataSource.getCaptureById(id);
      return Right(capture);
    } catch (e, stackTrace) {
      GlobalErrorHandler.handleError(e, stackTrace: stackTrace, context: 'Get capture by id');
      return Left(DatabaseFailure(
        message: 'Failed to get capture: $e',
        originalError: e,
        stackTrace: stackTrace,
      ));
    }
  }

  @override
  Future<Result<void>> deleteCapture(int id) async {
    try {
      await localDataSource.deleteCapture(id);
      return const Right(null);
    } catch (e, stackTrace) {
      GlobalErrorHandler.handleError(e, stackTrace: stackTrace, context: 'Delete capture');
      return Left(DatabaseFailure(
        message: 'Failed to delete capture: $e',
        originalError: e,
        stackTrace: stackTrace,
      ));
    }
  }

  @override
  Future<Result<void>> deleteAllCaptures() async {
    try {
      await localDataSource.deleteAllCaptures();
      return const Right(null);
    } catch (e, stackTrace) {
      GlobalErrorHandler.handleError(e, stackTrace: stackTrace, context: 'Delete all captures');
      return Left(DatabaseFailure(
        message: 'Failed to delete all captures: $e',
        originalError: e,
        stackTrace: stackTrace,
      ));
    }
  }

  @override
  Future<Result<int>> getCaptureCount() async {
    try {
      final count = await localDataSource.getCaptureCount();
      return Right(count);
    } catch (e, stackTrace) {
      GlobalErrorHandler.handleError(e, stackTrace: stackTrace, context: 'Get capture count');
      return Left(DatabaseFailure(
        message: 'Failed to get capture count: $e',
        originalError: e,
        stackTrace: stackTrace,
      ));
    }
  }

  @override
  Future<Result<CaptureStatistics>> getStatistics() async {
    try {
      final captures = await localDataSource.getAllCaptures();

      if (captures.isEmpty) {
        return Right(CaptureStatistics.empty());
      }

      final speeds = captures.map((c) => c.estimatedVehicleSpeed).toList();
      final avgSpeed = speeds.reduce((a, b) => a + b) / speeds.length;
      final maxSpeed = speeds.reduce((a, b) => a > b ? a : b);
      final minSpeed = speeds.reduce((a, b) => a < b ? a : b);
      final platesRecognized = captures.where((c) => c.plateNumber != null && c.plateNumber!.isNotEmpty).length;

      final sortedByDate = List<CaptureEntity>.from(captures)
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

      return Right(CaptureStatistics(
        totalCaptures: captures.length,
        averageSpeed: avgSpeed,
        maxSpeed: maxSpeed,
        minSpeed: minSpeed,
        platesRecognized: platesRecognized,
        firstCapture: sortedByDate.first.timestamp,
        lastCapture: sortedByDate.last.timestamp,
      ));
    } catch (e, stackTrace) {
      GlobalErrorHandler.handleError(e, stackTrace: stackTrace, context: 'Get statistics');
      return Left(DatabaseFailure(
        message: 'Failed to get statistics: $e',
        originalError: e,
        stackTrace: stackTrace,
      ));
    }
  }
}
