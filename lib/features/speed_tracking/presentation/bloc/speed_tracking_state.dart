part of 'speed_tracking_bloc.dart';

class PermissionStatus extends Equatable {
  final bool camera;
  final bool location;
  final bool storage;

  const PermissionStatus({
    this.camera = false,
    this.location = false,
    this.storage = false,
  });

  bool get allGranted => camera && location && storage;

  PermissionStatus copyWith({bool? camera, bool? location, bool? storage}) {
    return PermissionStatus(
      camera: camera ?? this.camera,
      location: location ?? this.location,
      storage: storage ?? this.storage,
    );
  }

  @override
  List<Object?> get props => [camera, location, storage];
}

enum TrackingStatus {
  idle,
  initializing,
  permissionsRequired,
  tracking,
  capturing,
  error,
}

class SpeedTrackingState extends Equatable {
  final TrackingStatus status;
  final PermissionStatus permissions;
  final String sessionId;

  final double userSpeedKmh;
  final double gpsAccuracy;
  final bool gpsValid;

  final List<TrackedVehicle> trackedVehicles;
  final TrackedVehicle? lockedTarget;
  final double targetSpeedKmh;
  final double relativeSpeedKmh;
  final String? detectedPlate;
  final double confidenceScore;

  final bool cameraReady;
  final bool flashEnabled;

  final int frameWidth;
  final int frameHeight;

  final bool isCapturing;
  final String? lastCaptureMessage;
  final String? lastCapturePath;
  final int captureCount;

  /// When true the plate-confirmation overlay is visible.
  final bool showPlateConfirmation;

  /// The AI-detected plate text awaiting user confirmation.
  final String? pendingPlateNumber;

  final String? errorMessage;

  // ── Persisted dashboard stats ──
  final double dashboardAvgSpeed;
  final double dashboardMaxSpeed;
  final double dashboardTotalDistance;

  const SpeedTrackingState({
    this.status = TrackingStatus.idle,
    this.permissions = const PermissionStatus(),
    this.sessionId = '',
    this.userSpeedKmh = 0,
    this.gpsAccuracy = 999,
    this.gpsValid = false,
    this.trackedVehicles = const [],
    this.lockedTarget,
    this.targetSpeedKmh = 0,
    this.relativeSpeedKmh = 0,
    this.detectedPlate,
    this.confidenceScore = 0,
    this.cameraReady = false,
    this.flashEnabled = false,
    this.frameWidth = 1280,
    this.frameHeight = 720,
    this.isCapturing = false,
    this.lastCaptureMessage,
    this.lastCapturePath,
    this.captureCount = 0,
    this.showPlateConfirmation = false,
    this.pendingPlateNumber,
    this.errorMessage,
    this.dashboardAvgSpeed = 0,
    this.dashboardMaxSpeed = 0,
    this.dashboardTotalDistance = 0,
  });

  factory SpeedTrackingState.initial() {
    return SpeedTrackingState(sessionId: const Uuid().v4());
  }

  /// Whether tracking has started (speed should show actual value vs "--")
  bool get isTrackingActive => status == TrackingStatus.tracking || status == TrackingStatus.capturing;

  SpeedTrackingState copyWith({
    TrackingStatus? status,
    PermissionStatus? permissions,
    String? sessionId,
    double? userSpeedKmh,
    double? gpsAccuracy,
    bool? gpsValid,
    List<TrackedVehicle>? trackedVehicles,
    TrackedVehicle? lockedTarget,
    bool clearLockedTarget = false,
    double? targetSpeedKmh,
    double? relativeSpeedKmh,
    String? detectedPlate,
    bool clearDetectedPlate = false,
    double? confidenceScore,
    bool? cameraReady,
    bool? flashEnabled,
    int? frameWidth,
    int? frameHeight,
    bool? isCapturing,
    String? lastCaptureMessage,
    bool clearLastCaptureMessage = false,
    String? lastCapturePath,
    bool clearLastCapturePath = false,
    int? captureCount,
    bool? showPlateConfirmation,
    String? pendingPlateNumber,
    bool clearPendingPlateNumber = false,
    String? errorMessage,
    bool clearErrorMessage = false,
    double? dashboardAvgSpeed,
    double? dashboardMaxSpeed,
    double? dashboardTotalDistance,
  }) {
    return SpeedTrackingState(
      status: status ?? this.status,
      permissions: permissions ?? this.permissions,
      sessionId: sessionId ?? this.sessionId,
      userSpeedKmh: userSpeedKmh ?? this.userSpeedKmh,
      gpsAccuracy: gpsAccuracy ?? this.gpsAccuracy,
      gpsValid: gpsValid ?? this.gpsValid,
      trackedVehicles: trackedVehicles ?? this.trackedVehicles,
      lockedTarget: clearLockedTarget ? null : (lockedTarget ?? this.lockedTarget),
      targetSpeedKmh: targetSpeedKmh ?? this.targetSpeedKmh,
      relativeSpeedKmh: relativeSpeedKmh ?? this.relativeSpeedKmh,
      detectedPlate: clearDetectedPlate ? null : (detectedPlate ?? this.detectedPlate),
      confidenceScore: confidenceScore ?? this.confidenceScore,
      cameraReady: cameraReady ?? this.cameraReady,
      flashEnabled: flashEnabled ?? this.flashEnabled,
      frameWidth: frameWidth ?? this.frameWidth,
      frameHeight: frameHeight ?? this.frameHeight,
      isCapturing: isCapturing ?? this.isCapturing,
      lastCaptureMessage: clearLastCaptureMessage ? null : (lastCaptureMessage ?? this.lastCaptureMessage),
      lastCapturePath: clearLastCapturePath ? null : (lastCapturePath ?? this.lastCapturePath),
      captureCount: captureCount ?? this.captureCount,
      showPlateConfirmation: showPlateConfirmation ?? this.showPlateConfirmation,
      pendingPlateNumber: clearPendingPlateNumber ? null : (pendingPlateNumber ?? this.pendingPlateNumber),
      errorMessage: clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      dashboardAvgSpeed: dashboardAvgSpeed ?? this.dashboardAvgSpeed,
      dashboardMaxSpeed: dashboardMaxSpeed ?? this.dashboardMaxSpeed,
      dashboardTotalDistance: dashboardTotalDistance ?? this.dashboardTotalDistance,
    );
  }

  @override
  List<Object?> get props => [
    status, permissions, sessionId, userSpeedKmh, gpsAccuracy, gpsValid,
    trackedVehicles, lockedTarget, targetSpeedKmh, relativeSpeedKmh,
    detectedPlate, confidenceScore, cameraReady, flashEnabled,
    frameWidth, frameHeight,
    isCapturing, lastCaptureMessage, lastCapturePath, captureCount,
    showPlateConfirmation, pendingPlateNumber, errorMessage,
    dashboardAvgSpeed, dashboardMaxSpeed, dashboardTotalDistance,
  ];
}
