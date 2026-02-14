part of 'speed_tracking_bloc.dart';

// ═══════════════════════════════════════════════════════════════════
//  Speed Tracking Events — rebuilt from scratch
// ═══════════════════════════════════════════════════════════════════

abstract class SpeedTrackingEvent extends Equatable {
  const SpeedTrackingEvent();
  @override
  List<Object?> get props => [];
}

/// Initialize — checks permissions only. Camera/TFLite are NOT touched.
class InitializeTracking extends SpeedTrackingEvent {
  const InitializeTracking();
}

/// Request all required permissions from the OS.
class RequestPermissions extends SpeedTrackingEvent {
  const RequestPermissions();
}

/// Start active tracking — camera + TFLite init + GPS + detection loop.
class StartTracking extends SpeedTrackingEvent {
  const StartTracking();
}

/// Stop active tracking — cleanup camera, GPS, detection.
class StopTracking extends SpeedTrackingEvent {
  const StopTracking();
}

/// GPS data received from the location service.
class GpsDataReceived extends SpeedTrackingEvent {
  final double speedKmh;
  final double accuracy;
  final double latitude;
  final double longitude;

  const GpsDataReceived({
    required this.speedKmh,
    required this.accuracy,
    required this.latitude,
    required this.longitude,
  });

  @override
  List<Object?> get props => [speedKmh, accuracy, latitude, longitude];
}

/// Vehicles detected in a camera frame.
/// Includes actual image dimensions so overlays are pixel-accurate.
class VehiclesDetected extends SpeedTrackingEvent {
  final List<DetectedVehicle> vehicles;
  final int imageWidth;
  final int imageHeight;

  const VehiclesDetected(this.vehicles, {this.imageWidth = 0, this.imageHeight = 0});

  @override
  List<Object?> get props => [vehicles, imageWidth, imageHeight];
}

/// A license plate was detected by OCR — enters the voting pipeline.
class PlateDetected extends SpeedTrackingEvent {
  final String plateText;
  const PlateDetected(this.plateText);
  @override
  List<Object?> get props => [plateText];
}

/// User confirms or edits the AI-detected plate number.
class ConfirmPlate extends SpeedTrackingEvent {
  final String confirmedPlate;
  const ConfirmPlate(this.confirmedPlate);
  @override
  List<Object?> get props => [confirmedPlate];
}

/// User cancels the plate confirmation overlay.
class CancelCapture extends SpeedTrackingEvent {
  const CancelCapture();
}

/// Clear the last capture snackbar message after timeout.
class ClearCaptureMessage extends SpeedTrackingEvent {
  const ClearCaptureMessage();
}

/// Lock onto a specific vehicle for tracking.
class LockTarget extends SpeedTrackingEvent {
  final String? trackingId;
  const LockTarget([this.trackingId]);
  @override
  List<Object?> get props => [trackingId];
}

/// Unlock the currently tracked vehicle.
class UnlockTarget extends SpeedTrackingEvent {
  const UnlockTarget();
}

/// Capture button pressed — triggers photo + speed overlay save.
class CapturePressed extends SpeedTrackingEvent {
  const CapturePressed();
}

/// Capture completed (success or failure).
class CaptureCompleted extends SpeedTrackingEvent {
  final bool success;
  final String? message;
  final String? imagePath;

  const CaptureCompleted({
    required this.success,
    this.message,
    this.imagePath,
  });

  @override
  List<Object?> get props => [success, message, imagePath];
}

/// Toggle camera flash / torch.
class ToggleFlash extends SpeedTrackingEvent {
  const ToggleFlash();
}

/// Open system settings (for permissions).
class OpenSettings extends SpeedTrackingEvent {
  const OpenSettings();
}

/// Reset all tracking state to initial.
class ResetTracking extends SpeedTrackingEvent {
  const ResetTracking();
}
