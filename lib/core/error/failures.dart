import 'package:dartz/dartz.dart';

/// Base failure class for all application failures
///
/// Using sealed classes pattern for exhaustive failure handling
abstract class Failure {
  final String message;
  final String? code;
  final dynamic originalError;
  final StackTrace? stackTrace;

  const Failure({
    required this.message,
    this.code,
    this.originalError,
    this.stackTrace,
  });

  @override
  String toString() => 'Failure(message: $message, code: $code)';
}

/// Permission-related failures
class PermissionFailure extends Failure {
  final String permissionType;

  const PermissionFailure({
    required super.message,
    required this.permissionType,
    super.code,
    super.originalError,
    super.stackTrace,
  });
}

/// Camera-related failures
class CameraFailure extends Failure {
  const CameraFailure({
    required super.message,
    super.code,
    super.originalError,
    super.stackTrace,
  });
}

/// GPS/Location-related failures
class LocationFailure extends Failure {
  const LocationFailure({
    required super.message,
    super.code,
    super.originalError,
    super.stackTrace,
  });
}

/// Database-related failures
class DatabaseFailure extends Failure {
  const DatabaseFailure({
    required super.message,
    super.code,
    super.originalError,
    super.stackTrace,
  });
}

/// ML/Detection-related failures
class DetectionFailure extends Failure {
  const DetectionFailure({
    required super.message,
    super.code,
    super.originalError,
    super.stackTrace,
  });
}

/// OCR-related failures
class OcrFailure extends Failure {
  const OcrFailure({
    required super.message,
    super.code,
    super.originalError,
    super.stackTrace,
  });
}

/// Image processing failures
class ImageProcessingFailure extends Failure {
  const ImageProcessingFailure({
    required super.message,
    super.code,
    super.originalError,
    super.stackTrace,
  });
}

/// Storage/Gallery save failures
class StorageFailure extends Failure {
  const StorageFailure({
    required super.message,
    super.code,
    super.originalError,
    super.stackTrace,
  });
}

/// Platform channel failures
class PlatformChannelFailure extends Failure {
  const PlatformChannelFailure({
    required super.message,
    super.code,
    super.originalError,
    super.stackTrace,
  });
}

/// Network-related failures (future use)
class NetworkFailure extends Failure {
  const NetworkFailure({
    required super.message,
    super.code,
    super.originalError,
    super.stackTrace,
  });
}

/// Unknown/unexpected failures
class UnknownFailure extends Failure {
  const UnknownFailure({
    super.message = 'An unexpected error occurred',
    super.code,
    super.originalError,
    super.stackTrace,
  });
}

/// Type alias for Either with Failure
typedef Result<T> = Either<Failure, T>;

/// Extension methods for Result type
extension ResultExtensions<T> on Result<T> {
  /// Get value or default if failure
  T getOrElse(T defaultValue) {
    return fold((_) => defaultValue, (value) => value);
  }

  /// Get value or null if failure
  T? getOrNull() {
    return fold((_) => null, (value) => value);
  }

  /// Check if result is success
  bool get isSuccess => isRight();

  /// Check if result is failure
  bool get isFailure => isLeft();

  /// Get failure message or empty string
  String get failureMessage {
    return fold((failure) => failure.message, (_) => '');
  }

  /// Transform success value
  Result<R> mapSuccess<R>(R Function(T value) transform) {
    return map(transform);
  }

  /// Handle both cases with callbacks
  void handle({
    required void Function(Failure failure) onFailure,
    required void Function(T value) onSuccess,
  }) {
    fold(onFailure, onSuccess);
  }
}

/// Utility function to wrap async operations with error handling
Future<Result<T>> safeCall<T>(Future<T> Function() operation) async {
  try {
    final result = await operation();
    return Right(result);
  } catch (e, stackTrace) {
    return Left(UnknownFailure(
      message: e.toString(),
      originalError: e,
      stackTrace: stackTrace,
    ));
  }
}

/// Utility function to wrap sync operations with error handling
Result<T> safeSyncCall<T>(T Function() operation) {
  try {
    final result = operation();
    return Right(result);
  } catch (e, stackTrace) {
    return Left(UnknownFailure(
      message: e.toString(),
      originalError: e,
      stackTrace: stackTrace,
    ));
  }
}

