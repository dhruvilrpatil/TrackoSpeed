import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:dartz/dartz.dart';

import '../error/failures.dart';
import '../error/error_handler.dart';

/// Result of gallery save operation
class GallerySaveResult {
  final bool success;
  final String path;
  final String message;

  const GallerySaveResult({
    required this.success,
    required this.path,
    required this.message,
  });

  factory GallerySaveResult.fromMap(Map<dynamic, dynamic> map) {
    return GallerySaveResult(
      success: map['success'] as bool? ?? false,
      path: map['path'] as String? ?? '',
      message: map['message'] as String? ?? '',
    );
  }
}

/// Service for saving images to device gallery
class GalleryService with ErrorHandlerMixin {
  static const MethodChannel _channel = MethodChannel('com.trackospeed/gallery_save');

  /// Save image to gallery
  Future<Result<GallerySaveResult>> saveImage({
    required Uint8List imageBytes,
    String? fileName,
  }) async {
    try {
      final actualFileName = fileName ?? _generateFileName();

      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'saveImage',
        {
          'imageBytes': imageBytes,
          'fileName': actualFileName,
        },
      );

      if (result == null) {
        return const Left(StorageFailure(
          message: 'Failed to save image - no response',
          code: 'NO_RESPONSE',
        ));
      }

      final saveResult = GallerySaveResult.fromMap(result);

      if (!saveResult.success) {
        return Left(StorageFailure(
          message: saveResult.message,
          code: 'SAVE_FAILED',
        ));
      }

      GlobalErrorHandler.logInfo('Image saved: ${saveResult.path}');
      return Right(saveResult);
    } on PlatformException catch (e, stackTrace) {
      GlobalErrorHandler.handleError(e, stackTrace: stackTrace, context: 'Save to gallery');
      return Left(StorageFailure(
        message: 'Failed to save image: ${e.message}',
        code: e.code,
        originalError: e,
        stackTrace: stackTrace,
      ));
    } catch (e, stackTrace) {
      GlobalErrorHandler.handleError(e, stackTrace: stackTrace, context: 'Save to gallery');
      return Left(StorageFailure(
        message: 'Unexpected error saving image: $e',
        originalError: e,
        stackTrace: stackTrace,
      ));
    }
  }

  /// Save image with metadata
  Future<Result<GallerySaveResult>> saveImageWithMetadata({
    required Uint8List imageBytes,
    String? fileName,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final actualFileName = fileName ?? _generateFileName();

      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'saveImageWithMetadata',
        {
          'imageBytes': imageBytes,
          'fileName': actualFileName,
          'metadata': metadata,
        },
      );

      if (result == null) {
        return const Left(StorageFailure(
          message: 'Failed to save image with metadata',
          code: 'NO_RESPONSE',
        ));
      }

      final saveResult = GallerySaveResult.fromMap(result);

      if (!saveResult.success) {
        return Left(StorageFailure(
          message: saveResult.message,
          code: 'SAVE_FAILED',
        ));
      }

      return Right(saveResult);
    } on PlatformException catch (e, stackTrace) {
      GlobalErrorHandler.handleError(e, stackTrace: stackTrace, context: 'Save with metadata');
      return Left(StorageFailure(
        message: 'Failed to save image: ${e.message}',
        code: e.code,
        originalError: e,
        stackTrace: stackTrace,
      ));
    } catch (e, stackTrace) {
      GlobalErrorHandler.handleError(e, stackTrace: stackTrace, context: 'Save with metadata');
      return Left(StorageFailure(
        message: 'Unexpected error: $e',
        originalError: e,
        stackTrace: stackTrace,
      ));
    }
  }

  /// Get album path
  Future<String> getAlbumPath() async {
    try {
      final path = await _channel.invokeMethod<String>('getAlbumPath');
      return path ?? 'Pictures/TrackoSpeed';
    } catch (e) {
      GlobalErrorHandler.handleError(e, context: 'Get album path');
      return 'Pictures/TrackoSpeed';
    }
  }

  /// Open image in device gallery app
  Future<bool> openInGallery(String path) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'openInGallery',
        {'path': path},
      );
      return result ?? false;
    } on PlatformException catch (e, stackTrace) {
      GlobalErrorHandler.handleError(e, stackTrace: stackTrace, context: 'Open in gallery');
      return false;
    } catch (e, stackTrace) {
      GlobalErrorHandler.handleError(e, stackTrace: stackTrace, context: 'Open in gallery');
      return false;
    }
  }

  /// Open TrackoSpeed album in device gallery app
  Future<bool> openAlbum() async {
    try {
      final result = await _channel.invokeMethod<bool>('openAlbum');
      return result ?? false;
    } on PlatformException catch (e, stackTrace) {
      GlobalErrorHandler.handleError(e, stackTrace: stackTrace, context: 'Open album');
      return false;
    } catch (e, stackTrace) {
      GlobalErrorHandler.handleError(e, stackTrace: stackTrace, context: 'Open album');
      return false;
    }
  }

  /// Generate unique filename for captures
  String _generateFileName() {
    final now = DateTime.now();
    final timestamp = '${now.year}${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';
    return 'TrackoSpeed_$timestamp.jpg';
  }
}

