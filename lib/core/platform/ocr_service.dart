import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:dartz/dartz.dart';

import '../error/failures.dart';
import '../error/error_handler.dart';

/// OCR recognition result
class OcrResult {
  final bool success;
  final String plateNumber;
  final double confidence;
  final String? rawText;
  final String message;

  const OcrResult({
    required this.success,
    required this.plateNumber,
    required this.confidence,
    this.rawText,
    required this.message,
  });

  factory OcrResult.fromMap(Map<dynamic, dynamic> map) {
    return OcrResult(
      success: map['success'] as bool? ?? false,
      plateNumber: map['plateNumber'] as String? ?? '',
      confidence: (map['confidence'] as num?)?.toDouble() ?? 0,
      rawText: map['rawText'] as String?,
      message: map['message'] as String? ?? '',
    );
  }

  factory OcrResult.empty() {
    return const OcrResult(
      success: false,
      plateNumber: '',
      confidence: 0,
      message: 'No plate detected',
    );
  }
}

/// Service for OCR/License plate recognition
class OcrService with ErrorHandlerMixin {
  static const MethodChannel _channel = MethodChannel('com.trackospeed/ocr');

  /// Recognize license plate from full image
  Future<Result<OcrResult>> recognizePlate(Uint8List imageBytes) async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'recognizePlate',
        {'imageBytes': imageBytes},
      );

      if (result == null) {
        return Right(OcrResult.empty());
      }

      final ocrResult = OcrResult.fromMap(result);

      if (ocrResult.success) {
        GlobalErrorHandler.logDebug('Plate recognized: ${ocrResult.plateNumber}');
      }

      return Right(ocrResult);
    } on PlatformException catch (e, stackTrace) {
      GlobalErrorHandler.handleError(e, stackTrace: stackTrace, context: 'Recognize plate');
      return Right(OcrResult.empty());
    } catch (e, stackTrace) {
      GlobalErrorHandler.handleError(e, stackTrace: stackTrace, context: 'Recognize plate');
      return Right(OcrResult.empty());
    }
  }

  /// Recognize license plate within specific region
  Future<Result<OcrResult>> recognizePlateInRegion({
    required Uint8List imageBytes,
    required int left,
    required int top,
    required int right,
    required int bottom,
  }) async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'recognizePlateInRegion',
        {
          'imageBytes': imageBytes,
          'region': {
            'left': left,
            'top': top,
            'right': right,
            'bottom': bottom,
          },
        },
      );

      if (result == null) {
        return Right(OcrResult.empty());
      }

      return Right(OcrResult.fromMap(result));
    } on PlatformException catch (e, stackTrace) {
      GlobalErrorHandler.handleError(e, stackTrace: stackTrace, context: 'Recognize in region');
      return Right(OcrResult.empty());
    } catch (e, stackTrace) {
      GlobalErrorHandler.handleError(e, stackTrace: stackTrace, context: 'Recognize in region');
      return Right(OcrResult.empty());
    }
  }

  /// Recognize license plate with timeout
  Future<Result<OcrResult>> recognizePlateWithTimeout(
    Uint8List imageBytes, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    try {
      final result = await recognizePlate(imageBytes).timeout(
        timeout,
        onTimeout: () {
          GlobalErrorHandler.logWarning('OCR timeout');
          return Right(OcrResult.empty());
        },
      );
      return result;
    } catch (e, stackTrace) {
      GlobalErrorHandler.handleError(e, stackTrace: stackTrace, context: 'OCR with timeout');
      return Right(OcrResult.empty());
    }
  }
}

