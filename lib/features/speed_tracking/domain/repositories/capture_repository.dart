import 'dart:typed_data';

import '../../../../core/error/failures.dart';
import '../entities/capture_entity.dart';

/// Repository interface for capture operations
///
/// Follows repository pattern for clean architecture.
/// Implementation handles database and gallery operations.
abstract class CaptureRepository {
  /// Save a capture with processed image
  Future<Result<CaptureEntity>> saveCapture({
    required Uint8List imageBytes,
    required CaptureEntity captureData,
  });

  /// Get all captures
  Future<Result<List<CaptureEntity>>> getAllCaptures();

  /// Get captures by session
  Future<Result<List<CaptureEntity>>> getCapturesBySession(String sessionId);

  /// Get captures by date range
  Future<Result<List<CaptureEntity>>> getCapturesByDateRange(
    DateTime start,
    DateTime end,
  );

  /// Get single capture by ID
  Future<Result<CaptureEntity?>> getCaptureById(int id);

  /// Delete a capture
  Future<Result<void>> deleteCapture(int id);

  /// Delete all captures
  Future<Result<void>> deleteAllCaptures();

  /// Get capture count
  Future<Result<int>> getCaptureCount();

  /// Get statistics
  Future<Result<CaptureStatistics>> getStatistics();
}

/// Statistics for captures
class CaptureStatistics {
  final int totalCaptures;
  final double averageSpeed;
  final double maxSpeed;
  final double minSpeed;
  final int platesRecognized;
  final DateTime? firstCapture;
  final DateTime? lastCapture;

  const CaptureStatistics({
    required this.totalCaptures,
    required this.averageSpeed,
    required this.maxSpeed,
    required this.minSpeed,
    required this.platesRecognized,
    this.firstCapture,
    this.lastCapture,
  });

  factory CaptureStatistics.empty() {
    return const CaptureStatistics(
      totalCaptures: 0,
      averageSpeed: 0,
      maxSpeed: 0,
      minSpeed: 0,
      platesRecognized: 0,
    );
  }
}

