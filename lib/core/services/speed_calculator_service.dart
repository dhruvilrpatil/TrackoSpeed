import 'dart:math' as math;
import '../error/error_handler.dart';
import '../platform/vehicle_detection_service.dart';
import 'adaptive_learning_service.dart';

/// Speed calculation result
class SpeedCalculationResult {
  final double userSpeedKmh;
  final double relativeSpeedKmh;
  final double targetSpeedKmh;
  final double confidence;
  final SpeedDirection direction;
  final double displacementPx; // pixels the vehicle moved between frames

  const SpeedCalculationResult({
    required this.userSpeedKmh,
    required this.relativeSpeedKmh,
    required this.targetSpeedKmh,
    required this.confidence,
    required this.direction,
    this.displacementPx = 0,
  });

  @override
  String toString() =>
      'SpeedCalc(user:${userSpeedKmh.toInt()}, rel:${relativeSpeedKmh.toInt()}, '
      'target:${targetSpeedKmh.toInt()} km/h, disp:${displacementPx.toInt()}px)';
}

/// Direction of relative movement
enum SpeedDirection {
  approaching, // Target moving towards us (closing distance)
  receding, // Target moving away from us
  parallel, // Moving sideways across the frame
  stationary, // Relative speed near zero
  unknown,
}

/// Frame-by-frame speed calculation service.
///
/// Measures how many pixels each tracked vehicle displaces per frame,
/// combines bounding-box area change (depth proxy) with centroid
/// displacement (lateral movement), and applies exponential smoothing
/// plus a multi-frame median filter for accurate, stable speed readout.
///
/// Works both when the user is moving (GPS baseline + relative) and
/// when the user is stationary (pure optical-flow displacement).
class SpeedCalculatorService with ErrorHandlerMixin {
  // ── Adaptive learning integration ──────────────────────────────
  /// Optional reference to the adaptive learning service.
  /// When set, the speed calculator uses AI-learned parameters
  /// instead of hardcoded defaults.
  AdaptiveLearningService? _learningService;

  /// Attach the adaptive learning service for AI-tuned parameters.
  void attachLearningService(AdaptiveLearningService service) {
    _learningService = service;
  }

  // ── Configuration (defaults, overridden by adaptive learning) ──
  /// Minimum delta between frames (ms) to avoid division by near-zero.
  static const int _minFrameDeltaMs = 50;

  /// Default px→km/h scaling (used when no learning service attached).
  static const double _defaultPxPerSecToKmh = 0.035;

  /// Default area→km/h scaling.
  static const double _defaultAreaChangeToKmh = 0.8;

  /// Default EMA alpha.
  static const double _defaultEmaAlpha = 0.15;

  /// AI-tuned or default px→km/h.
  double get _pxPerSecToKmh =>
      _learningService?.speedScaleFactor ?? _defaultPxPerSecToKmh;

  /// AI-tuned or default area→km/h.
  double get _areaChangeToKmh =>
      _learningService?.areaScaleFactor ?? _defaultAreaChangeToKmh;

  /// AI-tuned or default EMA alpha.
  double get _emaAlpha =>
      _learningService?.emaAlpha ?? _defaultEmaAlpha;

  /// Below this relative speed (km/h) the vehicle is considered stationary.
  static const double _stationaryThreshold = 5.0;

  /// Base minimum pixel displacement per frame to count as real movement.
  /// Scaled dynamically by bounding box area.
  static const double _baseMinDisplacementPx = 6.0;

  /// Maximum reasonable target speed (km/h) – clamps wild outliers.
  static const double _maxTargetSpeed = 250.0;

  /// Number of recent speed samples to keep for median filtering.
  static const int _medianWindowSize = 5;

  // ── Per-vehicle history ────────────────────────────────────────
  /// Stores previous frame data per trackingId so each vehicle has
  /// its own independent state.
  final Map<String, _FrameRecord> _history = {};

  /// EMA-smoothed speed per vehicle.
  final Map<String, double> _smoothedSpeed = {};

  /// Recent raw speed samples per vehicle (for median filtering).
  final Map<String, List<double>> _speedWindow = {};

  // ── Public API ─────────────────────────────────────────────────

  /// Calculate target vehicle speed by comparing bounding box between
  /// the current and previous frame.
  ///
  /// [userSpeedKmh]    – user's GPS speed
  /// [detectedVehicle] – current detection
  /// [imageWidth], [imageHeight] – camera frame dimensions
  /// [trackingId]      – persistent ID from VehicleTrackerService
  SpeedCalculationResult calculateSpeed({
    required double userSpeedKmh,
    required DetectedVehicle detectedVehicle,
    required int imageWidth,
    required int imageHeight,
    String? trackingId,
  }) {
    try {
      final id = trackingId ?? detectedVehicle.trackingId ?? '_default';
      final box = detectedVehicle.boundingBox;
      final now = DateTime.now();

      // Guard against zero/negative dimensions
      if (box.width <= 0 || box.height <= 0 || imageWidth <= 0 || imageHeight <= 0) {
        return _fallbackResult(userSpeedKmh);
      }

      final prev = _history[id];

      // First frame for this vehicle – store and return estimate.
      if (prev == null) {
        _history[id] = _FrameRecord(box: box, time: now);
        _smoothedSpeed[id] = userSpeedKmh;
        return SpeedCalculationResult(
          userSpeedKmh: userSpeedKmh,
          relativeSpeedKmh: 0,
          targetSpeedKmh: userSpeedKmh,
          confidence: 0.25,
          direction: SpeedDirection.unknown,
        );
      }

      final dtMs = now.difference(prev.time).inMilliseconds;
      if (dtMs < _minFrameDeltaMs) {
        // Too soon – return last known value.
        final lastSmoothed = _smoothedSpeed[id] ?? userSpeedKmh;
        return SpeedCalculationResult(
          userSpeedKmh: userSpeedKmh,
          relativeSpeedKmh: lastSmoothed - userSpeedKmh,
          targetSpeedKmh: lastSmoothed,
          confidence: 0.5,
          direction: _direction(lastSmoothed - userSpeedKmh),
        );
      }

      final dtSec = dtMs / 1000.0;

      // ── 1. Centroid displacement (lateral / vertical movement) ──
      final dxPx = box.centerX - prev.box.centerX; // positive = moving right
      final dyPx = box.centerY - prev.box.centerY; // positive = moving down
      final displacementPx = math.sqrt(dxPx * dxPx + dyPx * dyPx);

      // Dynamic dead-zone: scale by bounding box area fraction.
      // Closer vehicles (larger box) have smaller detection jitter relative
      // to their size, so we can use a tighter threshold for them.
      final boxAreaFraction = box.area / (imageWidth * imageHeight);
      final dynamicDeadzone = _baseMinDisplacementPx *
          (1.0 + (0.02 - boxAreaFraction.clamp(0.0, 0.3)) * 20).clamp(0.5, 3.0);

      // Dead-zone: ignore tiny displacements that are just detection noise
      if (displacementPx < dynamicDeadzone && userSpeedKmh < 3.0) {
        // User stationary + negligible displacement → vehicle is stationary
        _history[id] = _FrameRecord(box: box, time: now);
        final prevSmoothed2 = _smoothedSpeed[id] ?? 0;
        // Decay towards zero
        final smoothed2 = 0.10 * 0.0 + 0.90 * prevSmoothed2;
        _smoothedSpeed[id] = smoothed2;
        return SpeedCalculationResult(
          userSpeedKmh: userSpeedKmh,
          relativeSpeedKmh: 0,
          targetSpeedKmh: smoothed2,
          confidence: 0.5,
          direction: SpeedDirection.stationary,
          displacementPx: displacementPx,
        );
      }
      final pxPerSec = displacementPx / dtSec;

      // Scale by frame size so it works on any resolution.
      final diagPx = math.sqrt(
          imageWidth.toDouble() * imageWidth.toDouble() +
              imageHeight.toDouble() * imageHeight.toDouble());
      final normDisplacement = pxPerSec / diagPx; // 0..~1 per second

      // Convert normalised displacement to km/h.
      final lateralSpeedKmh = normDisplacement * diagPx * _pxPerSecToKmh;

      // ── 2. Depth change via area ratio ─────────────────────────
      final prevArea = prev.box.area;
      final currArea = box.area;
      double depthSpeedKmh = 0;
      if (prevArea > 0 && currArea > 0) {
        final areaChangePct = ((currArea - prevArea) / prevArea) * 100.0;
        // Adaptive threshold: farther vehicles (smaller box) have
        // smaller area changes, so we lower the threshold for them.
        // Close vehicles (large box fraction > 10%) keep the 2% threshold.
        final adaptiveAreaThreshold = boxAreaFraction > 0.10
            ? 2.0
            : (2.0 - (0.10 - boxAreaFraction) * 15.0).clamp(0.8, 2.0);
        if (areaChangePct.abs() > adaptiveAreaThreshold) {
          depthSpeedKmh = areaChangePct.abs() * _areaChangeToKmh / dtSec;
        }
      }

      // ── 3. Combine into relative speed ─────────────────────────
      // Weight: lateral displacement gets 65%, depth gets 35%.
      // Depth (area change) is noisier, so gets lower weight.
      var rawRelative = lateralSpeedKmh * 0.65 + depthSpeedKmh * 0.35;

      // Determine direction.
      final areaGrew = currArea > prevArea * 1.03; // 3% threshold (was 2%)
      final areaShrunk = currArea < prevArea * 0.97; // 3% threshold (was 2%)
      final isSideways = displacementPx > 15 && !areaGrew && !areaShrunk;
      SpeedDirection dir;
      if (isSideways) {
        dir = SpeedDirection.parallel;
      } else if (areaGrew) {
        dir = SpeedDirection.approaching;
      } else if (areaShrunk) {
        dir = SpeedDirection.receding;
      } else if (rawRelative < _stationaryThreshold) {
        dir = SpeedDirection.stationary;
      } else {
        dir = SpeedDirection.unknown;
      }

      // Sign convention: positive relative = target faster than user.
      if (dir == SpeedDirection.receding) rawRelative = -rawRelative;

      // ── 4. Target speed calculation ────────────────────────────
      final bool userStationary = userSpeedKmh < 3.0;
      double targetSpeed;

      if (userStationary) {
        // User standing still – displacement IS the vehicle's own speed.
        targetSpeed = rawRelative.abs();
      } else {
        switch (dir) {
          case SpeedDirection.approaching:
            targetSpeed = userSpeedKmh + rawRelative.abs();
            break;
          case SpeedDirection.receding:
            targetSpeed = (userSpeedKmh - rawRelative.abs()).clamp(0, _maxTargetSpeed);
            break;
          case SpeedDirection.parallel:
            // Lateral pass – use GPS as baseline; displacement gives delta.
            targetSpeed = userSpeedKmh + rawRelative.abs() * 0.5;
            if ((targetSpeed - userSpeedKmh).abs() < userSpeedKmh * 0.15) {
              targetSpeed = userSpeedKmh; // within 15% → same speed
            }
            break;
          case SpeedDirection.stationary:
          case SpeedDirection.unknown:
            targetSpeed = userSpeedKmh;
            break;
        }
      }

      targetSpeed = targetSpeed.clamp(0, _maxTargetSpeed);

      // ── 5. Median filter over recent samples ───────────────────
      // Reject outliers by keeping last N raw speeds and taking the median.
      final window = _speedWindow.putIfAbsent(id, () => []);
      window.add(targetSpeed);
      if (window.length > _medianWindowSize) {
        window.removeAt(0);
      }
      final medianSpeed = _median(window);

      // ── 6. EMA smoothing on the median-filtered value ──────────
      final prevSmoothed = _smoothedSpeed[id] ?? medianSpeed;

      // Adaptive alpha: use faster response when speed changes significantly
      // (> 20 km/h jump), slower when stable.
      final speedDelta = (medianSpeed - prevSmoothed).abs();
      final adaptiveAlpha = speedDelta > 20 ? 0.35 : _emaAlpha;

      final smoothed = adaptiveAlpha * medianSpeed + (1 - adaptiveAlpha) * prevSmoothed;
      _smoothedSpeed[id] = smoothed;

      // ── 7. Confidence ──────────────────────────────────────────
      final confidence = _calcConfidence(
        detection: detectedVehicle.confidence,
        box: box,
        imgW: imageWidth,
        imgH: imageHeight,
        dtMs: dtMs,
        displacement: displacementPx,
      );

      // ── 8. Update history ──────────────────────────────────────
      _history[id] = _FrameRecord(box: box, time: now);

      return SpeedCalculationResult(
        userSpeedKmh: userSpeedKmh,
        relativeSpeedKmh: rawRelative,
        targetSpeedKmh: smoothed,
        confidence: confidence,
        direction: dir,
        displacementPx: displacementPx,
      );
    } catch (e) {
      GlobalErrorHandler.handleError(e, context: 'Speed calculation');
      return _fallbackResult(userSpeedKmh);
    }
  }

  /// Compute the median of a list of doubles.
  double _median(List<double> values) {
    if (values.isEmpty) return 0;
    if (values.length == 1) return values[0];
    final sorted = List<double>.from(values)..sort();
    final mid = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[mid];
    return (sorted[mid - 1] + sorted[mid]) / 2.0;
  }

  // ── Helpers ────────────────────────────────────────────────────

  SpeedCalculationResult _fallbackResult(double userSpeed) {
    return SpeedCalculationResult(
      userSpeedKmh: userSpeed,
      relativeSpeedKmh: 0,
      targetSpeedKmh: userSpeed,
      confidence: 0.1,
      direction: SpeedDirection.unknown,
    );
  }

  SpeedDirection _direction(double rel) {
    if (rel.abs() < _stationaryThreshold) return SpeedDirection.stationary;
    return rel > 0 ? SpeedDirection.approaching : SpeedDirection.receding;
  }

  double _calcConfidence({
    required double detection,
    required BoundingBox box,
    required int imgW,
    required int imgH,
    required int dtMs,
    required double displacement,
  }) {
    var c = detection;

    // Penalise small boxes (far-away vehicles → noisier speed estimate).
    final areaRatio = box.area / (imgW * imgH);
    if (areaRatio < 0.02) {
      c *= 0.5;
    } else if (areaRatio < 0.05) {
      c *= 0.7;
    }

    // Penalise edge-of-frame boxes (partial visibility).
    final marginX = imgW * 0.08;
    final marginY = imgH * 0.08;
    if (box.left < marginX || box.right > imgW - marginX ||
        box.top < marginY || box.bottom > imgH - marginY) {
      c *= 0.8;
    }

    // Reward consistent frame timing (near 300 ms target — matches the
    // actual self-pacing detection loop interval).
    final dtDeviationMs = (dtMs - 300).abs();
    if (dtDeviationMs > 150) c *= 0.85;

    // Very large displacements in a single frame are suspicious.
    if (displacement > imgW * 0.4) c *= 0.5;

    return c.clamp(0.1, 1.0);
  }

  /// Evict history for vehicles that are no longer tracked.
  void pruneHistory(Set<String> activeIds) {
    _history.removeWhere((id, _) => !activeIds.contains(id));
    _smoothedSpeed.removeWhere((id, _) => !activeIds.contains(id));
    _speedWindow.removeWhere((id, _) => !activeIds.contains(id));
  }

  /// Reset all calculation state.
  void reset() {
    _history.clear();
    _smoothedSpeed.clear();
    _speedWindow.clear();
  }
}

/// Internal frame record for a single vehicle across frames.
class _FrameRecord {
  final BoundingBox box;
  final DateTime time;
  const _FrameRecord({required this.box, required this.time});
}

