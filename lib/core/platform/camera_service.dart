import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';
import 'package:dartz/dartz.dart';

import '../error/failures.dart';
import '../error/error_handler.dart';

/// Camera frame data
class CameraFrame {
  final Uint8List bytes;
  final int width;
  final int height;
  final DateTime timestamp;

  const CameraFrame({
    required this.bytes,
    required this.width,
    required this.height,
    required this.timestamp,
  });
}

/// Service for camera functionality
///
/// Manages camera lifecycle, preview, and frame capture.
/// Handles camera errors gracefully without crashing.
class CameraService with ErrorHandlerMixin {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isInitialized = false;
  bool _isCapturing = false;

  final StreamController<CameraFrame> _frameController =
      StreamController<CameraFrame>.broadcast();

  /// Stream of camera frames for processing
  Stream<CameraFrame> get frameStream => _frameController.stream;

  /// Camera controller for preview widget
  CameraController? get controller => _controller;

  /// Whether camera is initialized and ready
  bool get isInitialized => _isInitialized && _controller?.value.isInitialized == true;

  /// Whether camera is currently capturing
  bool get isCapturing => _isCapturing;

  /// Available cameras
  List<CameraDescription> get cameras => _cameras;

  /// Initialize camera system
  ///
  /// Idempotent: if the camera is already initialized and the controller
  /// is healthy, returns immediately without creating a duplicate.
  Future<Result<void>> initialize() async {
    // Guard: skip if already successfully initialized
    if (_isInitialized && _controller != null && _controller!.value.isInitialized) {
      return const Right(null);
    }

    try {
      // Dispose any leftover controller to prevent native camera leaks
      if (_controller != null) {
        try {
          await _controller!.dispose();
        } catch (_) {}
        _controller = null;
        _isInitialized = false;
      }

      // Get available cameras
      _cameras = await availableCameras();

      if (_cameras.isEmpty) {
        return const Left(CameraFailure(
          message: 'No cameras available on this device',
          code: 'NO_CAMERAS',
        ));
      }

      // Find back camera (preferred for vehicle tracking)
      final backCamera = _cameras.firstWhere(
        (cam) => cam.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras.first,
      );

      // Initialize controller with medium resolution — high causes
      // takePicture() to produce huge JPEGs that freeze the preview.
      // TFLite only needs 300×300 so medium (480p) is more than enough.
      _controller = CameraController(
        backCamera,
        ResolutionPreset.medium,
        enableAudio: false, // No audio needed
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _controller!.initialize();

      // Configure camera for vehicle tracking
      await _configureCamera();

      _isInitialized = true;
      GlobalErrorHandler.logInfo('Camera initialized successfully');

      return const Right(null);
    } catch (e, stackTrace) {
      GlobalErrorHandler.handleError(e, stackTrace: stackTrace, context: 'Initialize camera');
      _isInitialized = false;
      return Left(CameraFailure(
        message: 'Failed to initialize camera: $e',
        originalError: e,
        stackTrace: stackTrace,
      ));
    }
  }

  /// Configure camera settings for optimal vehicle tracking
  Future<void> _configureCamera() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    try {
      // Set focus mode to continuous auto-focus
      await _controller!.setFocusMode(FocusMode.auto);
    } catch (e) {
      GlobalErrorHandler.logWarning('Could not set focus mode: $e');
    }

    try {
      // Set exposure mode to auto
      await _controller!.setExposureMode(ExposureMode.auto);
    } catch (e) {
      GlobalErrorHandler.logWarning('Could not set exposure mode: $e');
    }

    try {
      // Enable flash if available (for low light)
      await _controller!.setFlashMode(FlashMode.off);
    } catch (e) {
      GlobalErrorHandler.logWarning('Could not set flash mode: $e');
    }
  }

  /// Start camera preview
  Future<Result<void>> startPreview() async {
    if (!_isInitialized || _controller == null) {
      final initResult = await initialize();
      if (initResult.isLeft()) {
        return initResult;
      }
    }

    try {
      if (!_controller!.value.isPreviewPaused) {
        // Preview already running
        return const Right(null);
      }

      await _controller!.resumePreview();
      return const Right(null);
    } catch (e, stackTrace) {
      GlobalErrorHandler.handleError(e, stackTrace: stackTrace, context: 'Start preview');
      return Left(CameraFailure(
        message: 'Failed to start camera preview: $e',
        originalError: e,
        stackTrace: stackTrace,
      ));
    }
  }

  /// Pause camera preview
  Future<void> pausePreview() async {
    try {
      await _controller?.pausePreview();
    } catch (e) {
      GlobalErrorHandler.handleError(e, context: 'Pause preview');
    }
  }

  /// Capture a single frame as JPEG bytes
  ///
  /// Uses takePicture() which writes a JPEG to disk. If a previous
  /// capture is still in progress, waits up to 2 seconds for it to
  /// finish instead of immediately failing. This prevents the
  /// self-pacing detection loop from missing frames due to the
  /// _isCapturing guard.
  Future<Result<CameraFrame>> captureFrame() async {
    if (!isInitialized || _controller == null) {
      return const Left(CameraFailure(
        message: 'Camera not initialized',
        code: 'NOT_INITIALIZED',
      ));
    }

    // If already capturing, wait up to 2s for the previous capture to finish
    if (_isCapturing) {
      int waited = 0;
      while (_isCapturing && waited < 2000) {
        await Future.delayed(const Duration(milliseconds: 50));
        waited += 50;
      }
      if (_isCapturing) {
        return const Left(CameraFailure(
          message: 'Capture timed out waiting for previous frame',
          code: 'CAPTURE_TIMEOUT',
        ));
      }
    }

    _isCapturing = true;

    try {
      // Take picture and get file
      final XFile imageFile = await _controller!.takePicture();

      // Read bytes from file
      final bytes = await imageFile.readAsBytes();

      // NOTE: We no longer use previewSize for frame dimensions.
      // The native detection code now returns the actual decoded image
      // dimensions (after EXIF rotation), which are used instead.
      // We still provide previewSize as a fallback.
      final previewSize = _controller!.value.previewSize;

      final frame = CameraFrame(
        bytes: bytes,
        width: previewSize?.width.toInt() ?? 1920,
        height: previewSize?.height.toInt() ?? 1080,
        timestamp: DateTime.now(),
      );

      // Emit to stream
      if (!_frameController.isClosed) {
        _frameController.add(frame);
      }

      return Right(frame);
    } catch (e, stackTrace) {
      GlobalErrorHandler.handleError(e, stackTrace: stackTrace, context: 'Capture frame');
      return Left(CameraFailure(
        message: 'Failed to capture frame: $e',
        originalError: e,
        stackTrace: stackTrace,
      ));
    } finally {
      _isCapturing = false;
    }
  }

  /// Start image stream for real-time processing
  Future<Result<void>> startImageStream(
    void Function(CameraImage image) onImage,
  ) async {
    if (!isInitialized || _controller == null) {
      return const Left(CameraFailure(
        message: 'Camera not initialized',
        code: 'NOT_INITIALIZED',
      ));
    }

    try {
      await _controller!.startImageStream(onImage);
      return const Right(null);
    } catch (e, stackTrace) {
      GlobalErrorHandler.handleError(e, stackTrace: stackTrace, context: 'Start image stream');
      return Left(CameraFailure(
        message: 'Failed to start image stream: $e',
        originalError: e,
        stackTrace: stackTrace,
      ));
    }
  }

  /// Stop image stream
  Future<void> stopImageStream() async {
    try {
      await _controller?.stopImageStream();
    } catch (e) {
      GlobalErrorHandler.handleError(e, context: 'Stop image stream');
    }
  }

  /// Switch between front and back camera
  Future<Result<void>> switchCamera() async {
    if (_cameras.length < 2) {
      return const Left(CameraFailure(
        message: 'Only one camera available',
        code: 'SINGLE_CAMERA',
      ));
    }

    try {
      final currentDirection = _controller?.description.lensDirection;
      final newCamera = _cameras.firstWhere(
        (cam) => cam.lensDirection != currentDirection,
        orElse: () => _cameras.first,
      );

      await _controller?.dispose();

      _controller = CameraController(
        newCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _controller!.initialize();
      await _configureCamera();

      return const Right(null);
    } catch (e, stackTrace) {
      GlobalErrorHandler.handleError(e, stackTrace: stackTrace, context: 'Switch camera');
      return Left(CameraFailure(
        message: 'Failed to switch camera: $e',
        originalError: e,
        stackTrace: stackTrace,
      ));
    }
  }

  /// Set zoom level (0.0 to 1.0)
  Future<void> setZoomLevel(double zoom) async {
    if (!isInitialized || _controller == null) return;

    try {
      final minZoom = await _controller!.getMinZoomLevel();
      final maxZoom = await _controller!.getMaxZoomLevel();
      final targetZoom = minZoom + (maxZoom - minZoom) * zoom.clamp(0.0, 1.0);
      await _controller!.setZoomLevel(targetZoom);
    } catch (e) {
      GlobalErrorHandler.handleError(e, context: 'Set zoom level');
    }
  }

  /// Toggle flash/torch
  Future<void> toggleFlash() async {
    if (!isInitialized || _controller == null) return;

    try {
      final currentMode = _controller!.value.flashMode;
      final newMode = currentMode == FlashMode.off ? FlashMode.torch : FlashMode.off;
      await _controller!.setFlashMode(newMode);
    } catch (e) {
      GlobalErrorHandler.handleError(e, context: 'Toggle flash');
    }
  }

  /// Dispose camera resources
  Future<void> dispose() async {
    try {
      await _controller?.dispose();
      _controller = null;
      _isInitialized = false;
      _frameController.close();
    } catch (e) {
      GlobalErrorHandler.handleError(e, context: 'Dispose camera');
    }
  }
}

