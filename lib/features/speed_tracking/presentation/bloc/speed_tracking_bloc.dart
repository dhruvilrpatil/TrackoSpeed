import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/error/error_handler.dart';
import '../../../../core/platform/permission_service.dart';
import '../../../../core/platform/gps_service.dart';
import '../../../../core/platform/camera_service.dart';
import '../../../../core/platform/vehicle_detection_service.dart';
import '../../../../core/platform/ocr_service.dart';
import '../../../../core/services/speed_calculator_service.dart';
import '../../../../core/services/vehicle_tracker_service.dart';
import '../../../../core/services/preferences_service.dart';
import '../../../../core/services/adaptive_learning_service.dart';
import '../../../../core/services/dashboard_stats_service.dart';
import '../../domain/usecases/capture_vehicle_usecase.dart';

part 'speed_tracking_event.dart';
part 'speed_tracking_state.dart';

// ===================================================================
//  SpeedTrackingBloc — rebuilt from scratch
//
//  Key design decisions:
//  1. Camera & TFLite are NOT initialised until StartTracking.
//     InitializeTracking only checks permissions.
//  2. Self-pacing detection loop (not Timer.periodic).
//  3. Plate voting system with adaptive threshold.
//  4. AdaptiveLearningService wired up for per-session learning.
// ===================================================================

class SpeedTrackingBloc extends Bloc<SpeedTrackingEvent, SpeedTrackingState> {
  // -- Services --
  final PermissionService permissionService;
  final GpsService gpsService;
  final CameraService cameraService;
  final VehicleDetectionService vehicleDetectionService;
  final OcrService ocrService;
  final SpeedCalculatorService speedCalculatorService;
  final VehicleTrackerService vehicleTrackerService;
  final CaptureVehicleUseCase captureVehicleUseCase;
  final PreferencesService preferencesService;
  final AdaptiveLearningService adaptiveLearningService;
  final DashboardStatsService dashboardStatsService;

  // -- Internal state --
  StreamSubscription<GpsData>? _gpsSubscription;
  bool _detectionActive = false;
  bool _isProcessingFrame = false;
  Uint8List? _lastCapturedFrame;
  int _frameCounter = 0;
  int _improvementCounter = 0;

  /// Plate voting: maps plate text → vote count.
  final Map<String, int> _plateVotes = {};

  /// Pending capture params waiting for plate confirmation.
  CaptureParams? _pendingCaptureParams;

  /// Image bytes of the pending capture (for preview in plate overlay).
  Uint8List? get pendingCaptureImageBytes => _pendingCaptureParams?.imageBytes;

  // -- Dashboard stats accumulators --
  double _sessionMaxSpeed = 0;
  double _sessionSpeedSum = 0;
  int _sessionSpeedCount = 0;
  double _sessionTotalDistance = 0;
  double? _lastLat;
  double? _lastLon;

  SpeedTrackingBloc({
    required this.permissionService,
    required this.gpsService,
    required this.cameraService,
    required this.vehicleDetectionService,
    required this.ocrService,
    required this.speedCalculatorService,
    required this.vehicleTrackerService,
    required this.captureVehicleUseCase,
    required this.preferencesService,
    required this.adaptiveLearningService,
    required this.dashboardStatsService,
  }) : super(SpeedTrackingState.initial()) {
    on<InitializeTracking>(_onInitialize);
    on<RequestPermissions>(_onRequestPermissions);
    on<StartTracking>(_onStartTracking);
    on<StopTracking>(_onStopTracking);
    on<GpsDataReceived>(_onGpsDataReceived);
    on<VehiclesDetected>(_onVehiclesDetected);
    on<PlateDetected>(_onPlateDetected);
    on<ConfirmPlate>(_onConfirmPlate);
    on<CancelCapture>(_onCancelCapture);
    on<ClearCaptureMessage>(_onClearCaptureMessage);
    on<LockTarget>(_onLockTarget);
    on<UnlockTarget>(_onUnlockTarget);
    on<CapturePressed>(_onCapturePressed);
    on<CaptureCompleted>(_onCaptureCompleted);
    on<ToggleFlash>(_onToggleFlash);
    on<OpenSettings>(_onOpenSettings);
    on<ResetTracking>(_onResetTracking);
  }

  // ===========================================================
  //  Initialize — permissions only, NO camera/TFLite
  // ===========================================================

  Future<void> _onInitialize(
    InitializeTracking event,
    Emitter<SpeedTrackingState> emit,
  ) async {
    try {
      emit(state.copyWith(status: TrackingStatus.initializing));

      // Load persisted dashboard stats from last session
      final savedStats = await dashboardStatsService.loadStats();
      emit(state.copyWith(
        dashboardAvgSpeed: savedStats.avgSpeed,
        dashboardMaxSpeed: savedStats.maxSpeed,
        dashboardTotalDistance: savedStats.totalDistance,
      ));

      final permStatus = await _checkPermissions();
      emit(state.copyWith(permissions: permStatus));

      final hasRequestedPermissions =
          await preferencesService.hasRequestedPermissions();

      if (!permStatus.allGranted && !hasRequestedPermissions) {
        emit(state.copyWith(status: TrackingStatus.permissionsRequired));
        return;
      } else if (!permStatus.allGranted && hasRequestedPermissions) {
        emit(state.copyWith(
          status: TrackingStatus.idle,
          errorMessage: 'Some permissions not granted. Limited functionality.',
        ));
        return;
      }

      // All permissions OK → idle. Camera is NOT started here.
      emit(state.copyWith(status: TrackingStatus.idle));
    } catch (e, stackTrace) {
      GlobalErrorHandler.handleError(e, stackTrace: stackTrace, context: 'Initialize tracking');
      emit(state.copyWith(
        status: TrackingStatus.error,
        errorMessage: 'Initialization failed: $e',
      ));
    }
  }

  Future<PermissionStatus> _checkPermissions() async {
    final camera = await permissionService.isGranted(AppPermission.camera);
    final location = await permissionService.isGranted(AppPermission.location);
    final storage = await permissionService.isGranted(AppPermission.storage);
    return PermissionStatus(camera: camera, location: location, storage: storage);
  }

  Future<void> _onRequestPermissions(
    RequestPermissions event,
    Emitter<SpeedTrackingState> emit,
  ) async {
    try {
      final results = await permissionService.requestAll();
      await preferencesService.setPermissionsRequested();

      results.fold(
        (failure) {
          emit(state.copyWith(
            status: TrackingStatus.idle,
            errorMessage: failure.message,
          ));
        },
        (permResults) {
          final permStatus = PermissionStatus(
            camera: permResults[AppPermission.camera]?.isGranted ?? false,
            location: permResults[AppPermission.location]?.isGranted ?? false,
            storage: permResults[AppPermission.storage]?.isGranted ?? false,
          );

          emit(state.copyWith(permissions: permStatus));

          if (permStatus.allGranted) {
            add(const InitializeTracking());
          } else {
            emit(state.copyWith(status: TrackingStatus.idle));
          }
        },
      );
    } catch (e, stackTrace) {
      GlobalErrorHandler.handleError(e, stackTrace: stackTrace, context: 'Request permissions');
      emit(state.copyWith(errorMessage: 'Permission request failed'));
    }
  }

  // ===========================================================
  //  Start Tracking — camera + TFLite init + GPS + detection
  // ===========================================================

  Future<void> _onStartTracking(
    StartTracking event,
    Emitter<SpeedTrackingState> emit,
  ) async {
    try {
      // Check permissions
      final permStatus = await _checkPermissions();
      emit(state.copyWith(permissions: permStatus));

      if (!permStatus.camera || !permStatus.location) {
        final hasRequested = await preferencesService.hasRequestedPermissions();
        if (!hasRequested) {
          emit(state.copyWith(status: TrackingStatus.permissionsRequired));
          return;
        }
      }

      emit(state.copyWith(status: TrackingStatus.initializing));

      // 1. Initialize camera (only now, not at app startup)
      if (!cameraService.isInitialized) {
        final cameraResult = await cameraService.initialize();
        cameraResult.fold(
          (failure) {
            GlobalErrorHandler.logWarning('Camera init failed: ${failure.message}');
            emit(state.copyWith(
              errorMessage: 'Camera failed: ${failure.message}',
            ));
          },
          (_) {
            emit(state.copyWith(cameraReady: true));
          },
        );
      } else {
        emit(state.copyWith(cameraReady: true));
      }

      // 2. Initialize TFLite detection model
      await vehicleDetectionService.initialize();

      // 3. Start GPS tracking
      final gpsResult = await gpsService.startTracking();
      gpsResult.fold(
        (failure) {
          emit(state.copyWith(errorMessage: 'GPS start failed: ${failure.message}'));
        },
        (_) {
          _gpsSubscription?.cancel();
          _gpsSubscription = gpsService.gpsStream.listen((gpsData) {
            if (!isClosed) {
              add(GpsDataReceived(
                speedKmh: gpsData.speedKmh,
                accuracy: gpsData.accuracy,
                latitude: gpsData.latitude,
                longitude: gpsData.longitude,
              ));
            }
          });
        },
      );

      // 4. Start camera preview
      await cameraService.startPreview();

      // 5. Reset session accumulators
      _frameCounter = 0;
      _improvementCounter = 0;
      _plateVotes.clear();
      _sessionMaxSpeed = 0;
      _sessionSpeedSum = 0;
      _sessionSpeedCount = 0;
      _sessionTotalDistance = 0;
      _lastLat = null;
      _lastLon = null;

      // 6. Start self-pacing detection loop
      _detectionActive = true;
      _runDetectionLoop();

      emit(state.copyWith(status: TrackingStatus.tracking));
    } catch (e, stackTrace) {
      GlobalErrorHandler.handleError(e, stackTrace: stackTrace, context: 'Start tracking');
      emit(state.copyWith(
        status: TrackingStatus.error,
        errorMessage: 'Failed to start tracking',
      ));
    }
  }

  // ===========================================================
  //  Self-pacing detection loop
  //
  //  Instead of Timer.periodic (which piles up if frames are slow),
  //  we process one frame, wait the adaptive delay, then process
  //  the next. The loop exits when _detectionActive is set to false.
  // ===========================================================

  Future<void> _runDetectionLoop() async {
    while (_detectionActive && !isClosed) {
      if (state.status != TrackingStatus.tracking &&
          state.status != TrackingStatus.capturing) {
        await Future.delayed(const Duration(milliseconds: 200));
        continue;
      }

      // Skip during plate confirmation to avoid flicker
      if (state.showPlateConfirmation) {
        await Future.delayed(const Duration(milliseconds: 200));
        continue;
      }

      await _processFrame();

      // Wait adaptive delay before next frame
      final delay = adaptiveLearningService.frameDelayMs;
      await Future.delayed(Duration(milliseconds: delay));
    }
  }

  Future<void> _processFrame() async {
    if (_isProcessingFrame) return;
    if (isClosed) return;

    _isProcessingFrame = true;
    _frameCounter++;
    _improvementCounter++;

    final stopwatch = Stopwatch()..start();

    try {
      final frameResult = await cameraService.captureFrame();

      frameResult.fold(
        (failure) {
          // Silently skip — camera may momentarily be unavailable
        },
        (frame) async {
          if (frame.bytes.isEmpty) return;
          _lastCapturedFrame = frame.bytes;

          try {
            final detectionResult =
                await vehicleDetectionService.detectVehiclesWithTimeout(
              frame.bytes,
            );

            detectionResult.fold(
              (failure) {},
              (result) {
                if (!isClosed) {
                  final imgW = result.imageWidth > 0 ? result.imageWidth : frame.width;
                  final imgH = result.imageHeight > 0 ? result.imageHeight : frame.height;

                  // Filter out fallback detections
                  final real = result.vehicles.where((v) => !v.isFallback).toList();

                  // Apply adaptive confidence floor
                  final confFloor = adaptiveLearningService.detectionConfidenceFloor;
                  final filtered = real.where((v) => v.confidence >= confFloor).toList();

                  if (filtered.isNotEmpty) {
                    add(VehiclesDetected(filtered, imageWidth: imgW, imageHeight: imgH));
                  } else if (state.trackedVehicles.isNotEmpty) {
                    add(VehiclesDetected(const [], imageWidth: imgW, imageHeight: imgH));
                  }

                  // Feed detection stability to AI
                  adaptiveLearningService.feedDetectionStability(filtered.length);
                }
              },
            );

            // Run OCR every 3rd frame when vehicles are visible
            if (_frameCounter % 3 == 0 &&
                state.trackedVehicles.isNotEmpty &&
                _lastCapturedFrame != null &&
                !isClosed) {
              try {
                // Use the locked target or the first tracked vehicle's bbox for OCR
                final ocrTarget = state.lockedTarget ??
                    state.trackedVehicles.first;
                final bbox = ocrTarget.detection.boundingBox;
                final ocrResult = await ocrService
                    .recognizePlateInRegion(
                      imageBytes: _lastCapturedFrame!,
                      left: bbox.left.toInt(),
                      top: bbox.top.toInt(),
                      right: bbox.right.toInt(),
                      bottom: bbox.bottom.toInt(),
                    );
                ocrResult.fold(
                  (_) {
                    adaptiveLearningService.feedOcrResult(success: false);
                  },
                  (result) {
                    if (result.success &&
                        result.plateNumber.isNotEmpty &&
                        !isClosed) {
                      adaptiveLearningService.feedOcrResult(success: true);
                      add(PlateDetected(result.plateNumber));
                    } else {
                      adaptiveLearningService.feedOcrResult(success: false);
                    }
                  },
                );
              } catch (_) {
                // OCR failure is non-fatal
              }
            }
          } catch (detectionError) {
            GlobalErrorHandler.logDebug(
                'Detection error (non-fatal): $detectionError');
          }
        },
      );
    } catch (e) {
      GlobalErrorHandler.logDebug('Frame processing error: $e');
    } finally {
      stopwatch.stop();
      adaptiveLearningService.feedFrameTiming(stopwatch.elapsedMilliseconds);
      _isProcessingFrame = false;

      // Run AI improvement cycle every ~200 frames
      if (_improvementCounter >= 200) {
        _improvementCounter = 0;
        adaptiveLearningService.improveAndPersist();
      }
    }
  }

  // ===========================================================
  //  Stop Tracking — cleanup + AI learn
  // ===========================================================

  Future<void> _onStopTracking(
    StopTracking event,
    Emitter<SpeedTrackingState> emit,
  ) async {
    _detectionActive = false;

    _gpsSubscription?.cancel();
    _gpsSubscription = null;

    await gpsService.stopTracking();
    await cameraService.pausePreview();

    // Run AI improvement at end of session
    await adaptiveLearningService.improveAndPersist();

    // Persist dashboard stats so they survive app restart
    final avgSpeed = _sessionSpeedCount > 0
        ? _sessionSpeedSum / _sessionSpeedCount
        : state.dashboardAvgSpeed;
    final maxSpeed = _sessionMaxSpeed > 0
        ? _sessionMaxSpeed
        : state.dashboardMaxSpeed;
    final totalDist = _sessionTotalDistance > 0
        ? _sessionTotalDistance
        : state.dashboardTotalDistance;
    await dashboardStatsService.saveStats(DashboardStats(
      avgSpeed: avgSpeed,
      maxSpeed: maxSpeed,
      totalDistance: totalDist,
    ));

    speedCalculatorService.reset();
    vehicleTrackerService.reset();
    _plateVotes.clear();
    _pendingCaptureParams = null;

    // Reset session accumulators
    _sessionMaxSpeed = 0;
    _sessionSpeedSum = 0;
    _sessionSpeedCount = 0;
    _sessionTotalDistance = 0;
    _lastLat = null;
    _lastLon = null;

    emit(state.copyWith(
      status: TrackingStatus.idle,
      trackedVehicles: [],
      clearLockedTarget: true,
      clearDetectedPlate: true,
      clearPendingPlateNumber: true,
      showPlateConfirmation: false,
      userSpeedKmh: 0,
      targetSpeedKmh: 0,
      relativeSpeedKmh: 0,
      dashboardAvgSpeed: avgSpeed,
      dashboardMaxSpeed: maxSpeed,
      dashboardTotalDistance: totalDist,
    ));
  }

  // ===========================================================
  //  GPS
  // ===========================================================

  void _onGpsDataReceived(
    GpsDataReceived event,
    Emitter<SpeedTrackingState> emit,
  ) {
    final speed = event.speedKmh;

    // Accumulate stats only when actively tracking with valid GPS
    if (state.isTrackingActive && event.accuracy < 50 && speed > 0) {
      _sessionSpeedSum += speed;
      _sessionSpeedCount++;
      if (speed > _sessionMaxSpeed) _sessionMaxSpeed = speed;

      // Calculate distance via Haversine from last known position
      if (_lastLat != null && _lastLon != null) {
        final dist = _haversineKm(
          _lastLat!, _lastLon!, event.latitude, event.longitude,
        );
        // Only add if distance is reasonable (< 1 km per update, filters GPS jumps)
        if (dist < 1.0) {
          _sessionTotalDistance += dist;
        }
      }
      _lastLat = event.latitude;
      _lastLon = event.longitude;

      final avgSpeed = _sessionSpeedCount > 0
          ? _sessionSpeedSum / _sessionSpeedCount
          : 0.0;

      emit(state.copyWith(
        userSpeedKmh: speed,
        gpsAccuracy: event.accuracy,
        gpsValid: true,
        dashboardAvgSpeed: avgSpeed,
        dashboardMaxSpeed: _sessionMaxSpeed,
        dashboardTotalDistance: _sessionTotalDistance,
      ));
    } else {
      emit(state.copyWith(
        userSpeedKmh: speed,
        gpsAccuracy: event.accuracy,
        gpsValid: event.accuracy < 50,
      ));
    }
  }

  /// Haversine distance in kilometres between two lat/lon pairs.
  static double _haversineKm(
    double lat1, double lon1, double lat2, double lon2,
  ) {
    const R = 6371.0; // Earth radius in km
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(lat1)) *
            math.cos(_deg2rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  static double _deg2rad(double deg) => deg * (math.pi / 180.0);

  // ===========================================================
  //  Vehicle Detection
  // ===========================================================

  void _onVehiclesDetected(
    VehiclesDetected event,
    Emitter<SpeedTrackingState> emit,
  ) {
    // Update frame dimensions
    if (event.imageWidth > 0 && event.imageHeight > 0) {
      if (event.imageWidth != state.frameWidth ||
          event.imageHeight != state.frameHeight) {
        emit(state.copyWith(
          frameWidth: event.imageWidth,
          frameHeight: event.imageHeight,
        ));
      }
    }

    final tracks = vehicleTrackerService.updateTracks(event.vehicles);

    for (final track in tracks) {
      final speedResult = speedCalculatorService.calculateSpeed(
        userSpeedKmh: state.userSpeedKmh,
        detectedVehicle: track.detection,
        imageWidth: state.frameWidth,
        imageHeight: state.frameHeight,
        trackingId: track.trackingId,
      );
      vehicleTrackerService.updateSpeed(track.trackingId, speedResult.targetSpeedKmh);

      // Feed speed observations to AI — relative speed is the vision-
      // estimated quantity that can be calibrated against GPS ground truth
      adaptiveLearningService.feedSpeedObservation(
        relativeSpeedKmh: speedResult.relativeSpeedKmh,
        gpsSpeedKmh: state.userSpeedKmh,
        targetSpeedKmh: speedResult.targetSpeedKmh,
      );
    }

    speedCalculatorService.pruneHistory(
      tracks.map((t) => t.trackingId).toSet(),
    );

    final updatedTracks = vehicleTrackerService.activeTracks;
    final lockedTarget = vehicleTrackerService.lockedTarget;

    double targetSpeed = 0;
    double relativeSpeed = 0;
    double confidence = 0;

    if (lockedTarget != null) {
      targetSpeed = lockedTarget.estimatedSpeed;
      relativeSpeed = targetSpeed - state.userSpeedKmh;
      confidence = lockedTarget.detection.confidence;
    } else if (updatedTracks.isNotEmpty) {
      final primary = updatedTracks.reduce((a, b) =>
          a.detection.boundingBox.area > b.detection.boundingBox.area ? a : b);
      targetSpeed = primary.estimatedSpeed;
      relativeSpeed = targetSpeed - state.userSpeedKmh;
      confidence = primary.detection.confidence;
    }

    emit(state.copyWith(
      trackedVehicles: updatedTracks,
      lockedTarget: lockedTarget,
      targetSpeedKmh: targetSpeed,
      relativeSpeedKmh: relativeSpeed,
      confidenceScore: confidence,
    ));
  }

  // ===========================================================
  //  Plate Voting + Confirmation
  // ===========================================================

  void _onPlateDetected(
    PlateDetected event,
    Emitter<SpeedTrackingState> emit,
  ) {
    final plate = event.plateText.trim().toUpperCase();
    if (plate.isEmpty) return;

    _plateVotes[plate] = (_plateVotes[plate] ?? 0) + 1;

    final threshold = adaptiveLearningService.plateVoteThreshold;

    String? bestPlate;
    int bestVotes = 0;
    _plateVotes.forEach((text, count) {
      if (count > bestVotes) {
        bestVotes = count;
        bestPlate = text;
      }
    });

    if (bestPlate != null && bestVotes >= threshold) {
      final current = state.detectedPlate ?? '';
      if (bestPlate!.length >= current.length || bestVotes > threshold) {
        emit(state.copyWith(detectedPlate: bestPlate));
      }
    }
  }

  void _onConfirmPlate(
    ConfirmPlate event,
    Emitter<SpeedTrackingState> emit,
  ) {
    final aiPlate = state.pendingPlateNumber ?? '';
    final userPlate = event.confirmedPlate.trim().toUpperCase();

    adaptiveLearningService.feedPlateCorrection(
      wasCorrect: aiPlate == userPlate,
    );

    emit(state.copyWith(
      detectedPlate: userPlate,
      showPlateConfirmation: false,
      clearPendingPlateNumber: true,
    ));

    if (_pendingCaptureParams != null) {
      final p = _pendingCaptureParams!;
      final params = CaptureParams(
        imageBytes: p.imageBytes,
        estimatedVehicleSpeed: p.estimatedVehicleSpeed,
        userSpeed: p.userSpeed,
        relativeSpeed: p.relativeSpeed,
        gpsAccuracy: p.gpsAccuracy,
        confidenceScore: p.confidenceScore,
        sessionId: p.sessionId,
        plateNumber: userPlate,
        vehicleClass: p.vehicleClass,
        boundingBox: p.boundingBox,
      );
      _pendingCaptureParams = null;
      _finalizeCaptureWithParams(params);
    }
  }

  void _onCancelCapture(
    CancelCapture event,
    Emitter<SpeedTrackingState> emit,
  ) {
    _pendingCaptureParams = null;
    emit(state.copyWith(
      showPlateConfirmation: false,
      clearPendingPlateNumber: true,
      isCapturing: false,
      status: TrackingStatus.tracking,
    ));
  }

  void _onClearCaptureMessage(
    ClearCaptureMessage event,
    Emitter<SpeedTrackingState> emit,
  ) {
    emit(state.copyWith(clearLastCaptureMessage: true));
  }

  // ===========================================================
  //  Lock / Unlock Target
  // ===========================================================

  void _onLockTarget(LockTarget event, Emitter<SpeedTrackingState> emit) {
    if (event.trackingId != null) {
      vehicleTrackerService.lockTarget(event.trackingId!);
    } else {
      vehicleTrackerService.lockPrimaryTarget();
    }
    final lockedTarget = vehicleTrackerService.lockedTarget;
    emit(state.copyWith(lockedTarget: lockedTarget));
  }

  void _onUnlockTarget(UnlockTarget event, Emitter<SpeedTrackingState> emit) {
    vehicleTrackerService.unlockTarget();
    emit(state.copyWith(clearLockedTarget: true, clearDetectedPlate: true));
    _plateVotes.clear();
  }

  // ===========================================================
  //  Capture
  // ===========================================================

  Future<void> _onCapturePressed(
    CapturePressed event,
    Emitter<SpeedTrackingState> emit,
  ) async {
    if (state.isCapturing) return;
    if (isClosed) return;

    emit(state.copyWith(isCapturing: true, status: TrackingStatus.capturing));

    try {
      Uint8List? imageBytes;
      try {
        final frameResult = await cameraService.captureFrame();
        frameResult.fold(
          (failure) {
            imageBytes = _lastCapturedFrame;
          },
          (frame) {
            imageBytes = frame.bytes;
          },
        );
      } catch (_) {
        imageBytes = _lastCapturedFrame;
      }

      if (imageBytes == null || imageBytes!.isEmpty) {
        add(const CaptureCompleted(
            success: false, message: 'No image available'));
        return;
      }

      final targetVehicle = state.lockedTarget ??
          (state.trackedVehicles.isNotEmpty
              ? state.trackedVehicles.first
              : null);

      // Try OCR for plate — multiple strategies
      String? plateNumber;

      // Strategy 1: OCR on vehicle bounding box region
      if (targetVehicle != null) {
        try {
          final bbox = targetVehicle.detection.boundingBox;
          final ocrResult =
              await ocrService.recognizePlateInRegion(
                imageBytes: imageBytes!,
                left: bbox.left.toInt(),
                top: bbox.top.toInt(),
                right: bbox.right.toInt(),
                bottom: bbox.bottom.toInt(),
              );
          ocrResult.fold(
            (_) {},
            (result) {
              if (result.success && result.plateNumber.isNotEmpty) {
                plateNumber = result.plateNumber;
              }
            },
          );
        } catch (_) {}
      }

      // Strategy 2: Full-image OCR fallback if region OCR found nothing
      if (plateNumber == null || plateNumber!.isEmpty) {
        try {
          final fullOcr = await ocrService.recognizePlate(imageBytes!);
          fullOcr.fold(
            (_) {},
            (result) {
              if (result.success && result.plateNumber.isNotEmpty) {
                plateNumber = result.plateNumber;
              }
            },
          );
        } catch (_) {}
      }

      // Strategy 3: Use plate from continuous detection loop
      if (plateNumber == null || plateNumber!.isEmpty) {
        final loopPlate = state.detectedPlate;
        if (loopPlate != null && loopPlate.isNotEmpty) {
          plateNumber = loopPlate;
        }
      }

      final params = CaptureParams(
        imageBytes: imageBytes!,
        estimatedVehicleSpeed: state.targetSpeedKmh,
        userSpeed: state.userSpeedKmh,
        relativeSpeed: state.relativeSpeedKmh,
        gpsAccuracy: state.gpsAccuracy,
        confidenceScore: state.confidenceScore,
        sessionId: state.sessionId,
        plateNumber: plateNumber,
        vehicleClass: targetVehicle?.detection.className,
        boundingBox: targetVehicle != null
            ? {
                'left': targetVehicle.detection.boundingBox.left,
                'top': targetVehicle.detection.boundingBox.top,
                'right': targetVehicle.detection.boundingBox.right,
                'bottom': targetVehicle.detection.boundingBox.bottom,
              }
            : null,
      );

      // Always show plate confirmation overlay so user can enter/correct plate
      _pendingCaptureParams = params;
      emit(state.copyWith(
        showPlateConfirmation: true,
        pendingPlateNumber: plateNumber ?? '',
        detectedPlate: plateNumber ?? '',
      ));
    } catch (e, stackTrace) {
      GlobalErrorHandler.handleError(e, stackTrace: stackTrace, context: 'Capture');
      add(CaptureCompleted(success: false, message: 'Capture failed: $e'));
    }
  }

  void _finalizeCaptureWithParams(CaptureParams params) async {
    try {
      final captureResult = await captureVehicleUseCase.call(params);

      captureResult.fold(
        (failure) {
          add(CaptureCompleted(success: false, message: failure.message));
        },
        (entity) {
          add(CaptureCompleted(
            success: true,
            message: 'Capture saved!',
            imagePath: entity.imagePath,
          ));
        },
      );
    } catch (e) {
      add(CaptureCompleted(success: false, message: 'Capture failed: $e'));
    }
  }

  void _onCaptureCompleted(
    CaptureCompleted event,
    Emitter<SpeedTrackingState> emit,
  ) {
    final validPath = (event.imagePath != null && event.imagePath!.isNotEmpty)
        ? event.imagePath
        : state.lastCapturePath;

    emit(state.copyWith(
      isCapturing: false,
      status: TrackingStatus.tracking,
      lastCaptureMessage: event.message,
      lastCapturePath: validPath,
      captureCount: event.success ? state.captureCount + 1 : state.captureCount,
    ));

    Future.delayed(const Duration(seconds: 3), () {
      if (!isClosed) {
        add(const ClearCaptureMessage());
      }
    });
  }

  // ===========================================================
  //  Misc
  // ===========================================================

  Future<void> _onToggleFlash(
    ToggleFlash event,
    Emitter<SpeedTrackingState> emit,
  ) async {
    await cameraService.toggleFlash();
    emit(state.copyWith(flashEnabled: !state.flashEnabled));
  }

  Future<void> _onOpenSettings(
    OpenSettings event,
    Emitter<SpeedTrackingState> emit,
  ) async {
    await permissionService.openSettings();
  }

  void _onResetTracking(
    ResetTracking event,
    Emitter<SpeedTrackingState> emit,
  ) {
    speedCalculatorService.reset();
    vehicleTrackerService.reset();
    _plateVotes.clear();
    _pendingCaptureParams = null;
    emit(SpeedTrackingState.initial().copyWith(
      permissions: state.permissions,
    ));
  }

  // ===========================================================
  //  Dispose
  // ===========================================================

  @override
  Future<void> close() async {
    _detectionActive = false;
    _gpsSubscription?.cancel();
    await gpsService.stopTracking();
    await cameraService.dispose();
    return super.close();
  }
}
