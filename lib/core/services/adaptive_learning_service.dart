import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';
import '../error/error_handler.dart';

/// Self-improving AI engine that learns from every session.
///
/// Tracks performance metrics across sessions and continuously tunes
/// the detection, OCR, and speed-estimation pipelines so the app gets
/// smarter and more accurate the more it is used.
///
/// **What it adapts:**
/// 1. **Speed calibration** – compares vision-based speed with GPS ground
///    truth and auto-tunes the px→km/h scaling factor.
/// 2. **OCR confidence** – tracks plate-read success rate and adjusts
///    the vote threshold + crop padding to maximise hit rate.
/// 3. **Detection sensitivity** – tracks how often detections appear/
///    disappear and adjusts the confidence floor.
/// 4. **EMA smoothing** – adapts the speed-smoothing alpha based on
///    the variance of recent readings.
/// 5. **Frame timing** – learns the optimal inter-frame delay for the
///    device's hardware.
///
/// All learned parameters persist to SharedPreferences so the AI
/// retains its improvements across app restarts.
class AdaptiveLearningService with ErrorHandlerMixin {
  // ═══════════════════════════════════════════════════════════════
  //  Persistence keys
  // ═══════════════════════════════════════════════════════════════
  static const _prefix = 'adaptive_';

  // Speed calibration
  static const _keySpeedScaleFactor = '${_prefix}speed_scale_factor';
  static const _keySpeedErrorSum = '${_prefix}speed_error_sum';
  static const _keySpeedSampleCount = '${_prefix}speed_sample_count';
  static const _keyAreaScaleFactor = '${_prefix}area_scale_factor';

  // EMA adaptation
  static const _keyEmaAlpha = '${_prefix}ema_alpha';
  static const _keySpeedVarianceSum = '${_prefix}speed_variance_sum';
  static const _keyVarianceSamples = '${_prefix}variance_samples';

  // OCR adaptation
  static const _keyOcrSuccessCount = '${_prefix}ocr_success_count';
  static const _keyOcrTotalCount = '${_prefix}ocr_total_count';
  static const _keyPlateVoteThreshold = '${_prefix}plate_vote_threshold';
  static const _keyOcrCropPadX = '${_prefix}ocr_crop_pad_x';
  static const _keyOcrCropPadBot = '${_prefix}ocr_crop_pad_bot';

  // Detection adaptation
  static const _keyDetectionFlickerCount = '${_prefix}det_flicker_count';
  static const _keyDetectionStableCount = '${_prefix}det_stable_count';
  static const _keyDetectionConfFloor = '${_prefix}det_conf_floor';

  // Session stats
  static const _keyTotalSessions = '${_prefix}total_sessions';
  static const _keyTotalFrames = '${_prefix}total_frames';
  static const _keyFrameDelayMs = '${_prefix}frame_delay_ms';
  static const _keyLastImproveTime = '${_prefix}last_improve_time';

  // ═══════════════════════════════════════════════════════════════
  //  Runtime state (current session)
  // ═══════════════════════════════════════════════════════════════
  bool _loaded = false;

  // Speed calibration
  double _speedScaleFactor = 0.035; // default px→km/h
  double _areaScaleFactor = 0.8; // default area→km/h
  double _sessionSpeedErrorSum = 0;
  int _sessionSpeedSamples = 0;
  double _lifetimeSpeedErrorSum = 0;
  int _lifetimeSpeedSampleCount = 0;

  // EMA adaptation
  double _emaAlpha = 0.15;
  final List<double> _recentSpeedDeltas = [];
  double _lifetimeVarianceSum = 0;
  int _lifetimeVarianceSamples = 0;

  // OCR adaptation
  int _ocrSuccessCount = 0;
  int _ocrTotalCount = 0;
  int _plateVoteThreshold = 2;
  double _ocrCropPadX = 0.05;
  double _ocrCropPadBot = 0.10;
  int _sessionOcrSuccess = 0;
  int _sessionOcrTotal = 0;

  // Detection adaptation
  int _detFlickerCount = 0;
  int _detStableCount = 0;
  double _detConfFloor = 0.3;
  int _lastDetCount = 0;
  int _sessionFlickers = 0;
  int _sessionStable = 0;

  // Session stats
  int _totalSessions = 0;
  int _totalFrames = 0;
  int _frameDelayMs = 300;
  int _sessionFrames = 0;
  final List<int> _frameProcessingTimes = [];

  // ═══════════════════════════════════════════════════════════════
  //  Getters — these are what other services read
  // ═══════════════════════════════════════════════════════════════

  /// Learned px-per-sec → km/h scaling factor for speed calculation.
  double get speedScaleFactor => _speedScaleFactor;

  /// Learned area-change → km/h scaling factor.
  double get areaScaleFactor => _areaScaleFactor;

  /// Learned EMA smoothing alpha for speed readout.
  double get emaAlpha => _emaAlpha;

  /// Learned plate-vote threshold.
  int get plateVoteThreshold => _plateVoteThreshold;

  /// Learned OCR crop horizontal padding (fraction of box width).
  double get ocrCropPadX => _ocrCropPadX;

  /// Learned OCR crop bottom padding (fraction of box height).
  double get ocrCropPadBot => _ocrCropPadBot;

  /// Learned detection confidence floor.
  double get detectionConfidenceFloor => _detConfFloor;

  /// Learned optimal frame delay in milliseconds.
  int get frameDelayMs => _frameDelayMs;

  /// Total sessions the AI has learned from.
  int get totalSessions => _totalSessions;

  /// Total frames processed across all sessions.
  int get totalFrames => _totalFrames + _sessionFrames;

  /// Current session OCR hit rate (0..1).
  double get sessionOcrHitRate =>
      _sessionOcrTotal > 0 ? _sessionOcrSuccess / _sessionOcrTotal : 0;

  /// Lifetime OCR hit rate (0..1).
  double get lifetimeOcrHitRate =>
      _ocrTotalCount > 0 ? _ocrSuccessCount / _ocrTotalCount : 0;

  /// Average speed estimation error (km/h) across lifetime.
  double get lifetimeSpeedError => _lifetimeSpeedSampleCount > 0
      ? _lifetimeSpeedErrorSum / _lifetimeSpeedSampleCount
      : 0;

  /// Summary of all learned parameters for display/debugging.
  Map<String, dynamic> get learnedParameters => {
        'speedScale': _speedScaleFactor.toStringAsFixed(5),
        'areaScale': _areaScaleFactor.toStringAsFixed(3),
        'emaAlpha': _emaAlpha.toStringAsFixed(3),
        'plateVoteThreshold': _plateVoteThreshold,
        'ocrPadX': '${(_ocrCropPadX * 100).toStringAsFixed(1)}%',
        'ocrPadBot': '${(_ocrCropPadBot * 100).toStringAsFixed(1)}%',
        'detConfFloor': _detConfFloor.toStringAsFixed(2),
        'frameDelayMs': _frameDelayMs,
        'totalSessions': _totalSessions,
        'totalFrames': totalFrames,
        'ocrHitRate': '${(lifetimeOcrHitRate * 100).toStringAsFixed(1)}%',
        'avgSpeedError': '${lifetimeSpeedError.toStringAsFixed(1)} km/h',
      };

  // ═══════════════════════════════════════════════════════════════
  //  Initialization — load learned state from disk
  // ═══════════════════════════════════════════════════════════════

  /// Load all persisted learned parameters. Call once at app startup.
  Future<void> initialize() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();

      _speedScaleFactor =
          prefs.getDouble(_keySpeedScaleFactor) ?? 0.035;
      _areaScaleFactor =
          prefs.getDouble(_keyAreaScaleFactor) ?? 0.8;
      _lifetimeSpeedErrorSum =
          prefs.getDouble(_keySpeedErrorSum) ?? 0;
      _lifetimeSpeedSampleCount =
          prefs.getInt(_keySpeedSampleCount) ?? 0;

      _emaAlpha = prefs.getDouble(_keyEmaAlpha) ?? 0.15;
      _lifetimeVarianceSum =
          prefs.getDouble(_keySpeedVarianceSum) ?? 0;
      _lifetimeVarianceSamples =
          prefs.getInt(_keyVarianceSamples) ?? 0;

      _ocrSuccessCount = prefs.getInt(_keyOcrSuccessCount) ?? 0;
      _ocrTotalCount = prefs.getInt(_keyOcrTotalCount) ?? 0;
      _plateVoteThreshold =
          prefs.getInt(_keyPlateVoteThreshold) ?? 2;
      _ocrCropPadX = prefs.getDouble(_keyOcrCropPadX) ?? 0.05;
      _ocrCropPadBot = prefs.getDouble(_keyOcrCropPadBot) ?? 0.10;

      _detFlickerCount = prefs.getInt(_keyDetectionFlickerCount) ?? 0;
      _detStableCount = prefs.getInt(_keyDetectionStableCount) ?? 0;
      _detConfFloor =
          prefs.getDouble(_keyDetectionConfFloor) ?? 0.3;

      _totalSessions = prefs.getInt(_keyTotalSessions) ?? 0;
      _totalFrames = prefs.getInt(_keyTotalFrames) ?? 0;
      _frameDelayMs = (prefs.getInt(_keyFrameDelayMs) ?? 300).clamp(200, 800);

      _loaded = true;
      GlobalErrorHandler.logDebug(
        'AdaptiveLearning loaded: sessions=$_totalSessions '
        'frames=$_totalFrames speedScale=$_speedScaleFactor '
        'ema=$_emaAlpha ocrRate=${lifetimeOcrHitRate.toStringAsFixed(2)} '
        'detFloor=$_detConfFloor frameDelay=$_frameDelayMs',
      );
    } catch (e) {
      GlobalErrorHandler.logDebug('AdaptiveLearning load failed: $e');
      _loaded = true; // use defaults
    }
  }

  // ═══════════════════════════════════════════════════════════════
  //  Feed methods — call these during tracking to feed data
  // ═══════════════════════════════════════════════════════════════

  /// Feed a speed observation for calibration.
  ///
  /// [relativeSpeedKmh] – vision-estimated relative speed (target vs user)
  /// [gpsSpeedKmh]      – ground-truth GPS speed of the user
  /// [targetSpeedKmh]   – estimated target vehicle speed
  ///
  /// The AI uses cases where vision estimates can be validated:
  /// - When user passes a stationary object, relative speed ≈ GPS speed
  /// - Signed errors let the AI know whether vision over- or under-estimates
  void feedSpeedObservation({
    required double relativeSpeedKmh,
    required double gpsSpeedKmh,
    required double targetSpeedKmh,
  }) {
    // Only calibrate when GPS is reliable (user moving > 10 km/h)
    // and vision produced a non-trivial reading
    if (gpsSpeedKmh < 10 || relativeSpeedKmh.abs() < 1) return;

    // Best calibration signal: when the target appears stationary
    // (e.g. parked car being passed), the vision-estimated relative
    // speed should equal the user's GPS speed.
    // We track signed error: positive = vision overestimates.
    final signedError = relativeSpeedKmh.abs() - gpsSpeedKmh;
    final absError = signedError.abs();

    _sessionSpeedErrorSum += signedError; // signed for direction
    _sessionSpeedSamples++;

    // Track absolute speed deltas for EMA variance adaptation
    _recentSpeedDeltas.add(absError);
    if (_recentSpeedDeltas.length > 50) {
      _recentSpeedDeltas.removeAt(0);
    }

    _sessionFrames++;
  }

  /// Feed a frame processing time for frame-delay optimisation.
  void feedFrameTiming(int processingTimeMs) {
    _frameProcessingTimes.add(processingTimeMs);
    if (_frameProcessingTimes.length > 100) {
      _frameProcessingTimes.removeAt(0);
    }
    _sessionFrames++;
  }

  /// Feed an OCR result — success or failure.
  void feedOcrResult({required bool success}) {
    _sessionOcrTotal++;
    if (success) _sessionOcrSuccess++;
  }

  /// Feed a user plate correction result.
  ///
  /// [wasCorrect] — true if the AI-detected plate matched what the user
  /// confirmed, false if the user had to type a different plate.
  /// When wrong, the AI widens OCR crop padding and lowers vote threshold
  /// so it captures more plate area next time. When correct, it tightens
  /// the crop and raises the threshold for precision.
  void feedPlateCorrection({required bool wasCorrect}) {
    _sessionOcrTotal++;
    if (wasCorrect) {
      _sessionOcrSuccess++;

      // AI was correct — slightly tighten crop for precision
      _ocrCropPadX = (_ocrCropPadX - 0.003).clamp(0.02, 0.12);
      _ocrCropPadBot = (_ocrCropPadBot - 0.003).clamp(0.05, 0.18);

      // Can demand more votes since reads are reliable
      if (_plateVoteThreshold < 4) {
        _plateVoteThreshold++;
      }
    } else {
      // AI was wrong — widen crop so OCR has more area to read from
      _ocrCropPadX = (_ocrCropPadX + 0.008).clamp(0.02, 0.12);
      _ocrCropPadBot = (_ocrCropPadBot + 0.008).clamp(0.05, 0.18);

      // Lower vote threshold so partial reads aren't discarded
      if (_plateVoteThreshold > 1) {
        _plateVoteThreshold--;
      }
    }

    GlobalErrorHandler.logDebug(
      'AI plate correction: wasCorrect=$wasCorrect → '
      'ocrPadX=$_ocrCropPadX ocrPadBot=$_ocrCropPadBot '
      'voteThreshold=$_plateVoteThreshold',
    );

    // Persist immediately so the correction is never lost
    _persist();
  }

  /// Feed detection stability info.
  ///
  /// [vehicleCount] – number of vehicles detected this frame.
  /// Call every frame; the service tracks frame-to-frame flicker.
  void feedDetectionStability(int vehicleCount) {
    // Flicker = detection count changed from previous frame
    if (_sessionFrames > 0 && vehicleCount != _lastDetCount) {
      _sessionFlickers++;
    } else {
      _sessionStable++;
    }
    _lastDetCount = vehicleCount;
    _sessionFrames++;
  }

  // ═══════════════════════════════════════════════════════════════
  //  Improve — run the self-improvement cycle
  // ═══════════════════════════════════════════════════════════════

  /// Run the AI self-improvement cycle. Call this:
  /// - At end of each tracking session (StopTracking)
  /// - Periodically during long sessions (every ~200 frames)
  ///
  /// Analyses accumulated data and adjusts all tunable parameters.
  Future<void> improveAndPersist() async {
    try {
      _totalSessions++;

      // ── 1. Speed calibration ───────────────────────────────────
      _improveSpeedCalibration();

      // ── 2. EMA adaptation ──────────────────────────────────────
      _improveEmaAlpha();

      // ── 3. OCR adaptation ──────────────────────────────────────
      _improveOcrParameters();

      // ── 4. Detection adaptation ────────────────────────────────
      _improveDetectionSensitivity();

      // ── 5. Frame timing optimisation ───────────────────────────
      _improveFrameTiming();

      // ── Persist everything ─────────────────────────────────────
      await _persist();

      // ── Reset session accumulators ─────────────────────────────
      _resetSessionState();

      GlobalErrorHandler.logDebug(
        'AI improved: speedScale=$_speedScaleFactor '
        'ema=$_emaAlpha ocrPadX=$_ocrCropPadX '
        'ocrPadBot=$_ocrCropPadBot detFloor=$_detConfFloor '
        'delay=$_frameDelayMs plateVotes=$_plateVoteThreshold',
      );
    } catch (e) {
      GlobalErrorHandler.logDebug('AI improve failed: $e');
    }
  }

  // ─── Speed calibration ─────────────────────────────────────────

  void _improveSpeedCalibration() {
    if (_sessionSpeedSamples < 10) return; // need enough data

    // Merge session data into lifetime
    _lifetimeSpeedErrorSum += _sessionSpeedErrorSum;
    _lifetimeSpeedSampleCount += _sessionSpeedSamples;

    // Mean signed error: positive = vision overestimates, negative = underestimates
    final meanSignedError =
        _lifetimeSpeedErrorSum / _lifetimeSpeedSampleCount;

    // If average absolute error > 5 km/h, the scale factor needs adjustment.
    // We nudge it in the direction that would reduce the error.
    // Learning rate decays with more sessions → converges.
    if (meanSignedError.abs() > 5.0) {
      final learningRate = 0.01 / math.sqrt(math.max(1.0, _totalSessions.toDouble()));
      // Positive mean error = vision overestimates → decrease scale
      // Negative mean error = vision underestimates → increase scale
      final correction = meanSignedError > 0
          ? -learningRate
          : learningRate;
      _speedScaleFactor =
          (_speedScaleFactor + correction).clamp(0.015, 0.060);

      // Also adjust area scale factor proportionally
      _areaScaleFactor =
          (_areaScaleFactor + correction * 10).clamp(0.3, 1.5);
    }
  }

  // ─── EMA alpha adaptation ─────────────────────────────────────

  void _improveEmaAlpha() {
    if (_recentSpeedDeltas.length < 10) return;

    // Calculate variance of recent speed deltas
    final mean = _recentSpeedDeltas.reduce((a, b) => a + b) /
        _recentSpeedDeltas.length;
    final variance = _recentSpeedDeltas
            .map((d) => (d - mean) * (d - mean))
            .reduce((a, b) => a + b) /
        _recentSpeedDeltas.length;

    // Merge into lifetime
    _lifetimeVarianceSum += variance;
    _lifetimeVarianceSamples++;
    final lifetimeAvgVariance =
        _lifetimeVarianceSum / _lifetimeVarianceSamples;

    // High variance → lower alpha (more smoothing to reduce jitter)
    // Low variance  → higher alpha (more responsive, readings are stable)
    if (lifetimeAvgVariance > 100) {
      // Very noisy — smooth aggressively
      _emaAlpha = (_emaAlpha - 0.005).clamp(0.05, 0.30);
    } else if (lifetimeAvgVariance < 20) {
      // Very stable — can be more responsive
      _emaAlpha = (_emaAlpha + 0.005).clamp(0.05, 0.30);
    }
    // In between → no change (already optimal)
  }

  // ─── OCR adaptation ───────────────────────────────────────────

  void _improveOcrParameters() {
    // Merge session into lifetime
    _ocrSuccessCount += _sessionOcrSuccess;
    _ocrTotalCount += _sessionOcrTotal;

    if (_ocrTotalCount < 5) return; // need enough data

    final hitRate = _ocrSuccessCount / _ocrTotalCount;

    // If hit rate is too low, slightly increase crop padding
    // to give OCR more area (but cap it to avoid reading outside box)
    if (hitRate < 0.15) {
      _ocrCropPadX = (_ocrCropPadX + 0.01).clamp(0.02, 0.12);
      _ocrCropPadBot = (_ocrCropPadBot + 0.01).clamp(0.05, 0.18);
    }
    // If hit rate is good, slightly tighten the crop for precision
    else if (hitRate > 0.40) {
      _ocrCropPadX = (_ocrCropPadX - 0.005).clamp(0.02, 0.12);
      _ocrCropPadBot = (_ocrCropPadBot - 0.005).clamp(0.05, 0.18);
    }

    // Vote threshold: if plates are read frequently and consistently,
    // we can require more votes for higher accuracy.
    // If plates are rarely read, lower the threshold so we don't miss them.
    if (hitRate > 0.50 && _plateVoteThreshold < 4) {
      _plateVoteThreshold++;
    } else if (hitRate < 0.10 && _plateVoteThreshold > 1) {
      _plateVoteThreshold--;
    }
  }

  // ─── Detection sensitivity ────────────────────────────────────

  void _improveDetectionSensitivity() {
    // Merge session into lifetime
    _detFlickerCount += _sessionFlickers;
    _detStableCount += _sessionStable;

    final totalDet = _detFlickerCount + _detStableCount;
    if (totalDet < 50) return;

    final flickerRate = _detFlickerCount / totalDet;

    // High flicker → detections are noisy → raise confidence floor
    if (flickerRate > 0.40) {
      _detConfFloor = (_detConfFloor + 0.02).clamp(0.20, 0.55);
    }
    // Low flicker → detections are stable → can lower confidence floor
    // to catch more vehicles
    else if (flickerRate < 0.15) {
      _detConfFloor = (_detConfFloor - 0.01).clamp(0.20, 0.55);
    }
  }

  // ─── Frame timing optimisation ────────────────────────────────

  void _improveFrameTiming() {
    if (_frameProcessingTimes.length < 20) return;

    // Find the 90th percentile processing time
    final sorted = List<int>.from(_frameProcessingTimes)..sort();
    final p90 = sorted[(sorted.length * 0.9).toInt()];

    // We want the frame delay to be at least p90 + 100ms buffer
    // but not less than 200ms or more than 800ms.
    final idealDelay = (p90 + 100).clamp(200, 800);

    // Blend towards ideal (don't jump instantly)
    _frameDelayMs =
        ((_frameDelayMs * 0.7 + idealDelay * 0.3).round()).clamp(200, 800);
  }

  // ═══════════════════════════════════════════════════════════════
  //  Persistence
  // ═══════════════════════════════════════════════════════════════

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.setDouble(_keySpeedScaleFactor, _speedScaleFactor);
      await prefs.setDouble(_keyAreaScaleFactor, _areaScaleFactor);
      await prefs.setDouble(_keySpeedErrorSum, _lifetimeSpeedErrorSum);
      await prefs.setInt(_keySpeedSampleCount, _lifetimeSpeedSampleCount);

      await prefs.setDouble(_keyEmaAlpha, _emaAlpha);
      await prefs.setDouble(_keySpeedVarianceSum, _lifetimeVarianceSum);
      await prefs.setInt(_keyVarianceSamples, _lifetimeVarianceSamples);

      await prefs.setInt(_keyOcrSuccessCount, _ocrSuccessCount);
      await prefs.setInt(_keyOcrTotalCount, _ocrTotalCount);
      await prefs.setInt(_keyPlateVoteThreshold, _plateVoteThreshold);
      await prefs.setDouble(_keyOcrCropPadX, _ocrCropPadX);
      await prefs.setDouble(_keyOcrCropPadBot, _ocrCropPadBot);

      await prefs.setInt(_keyDetectionFlickerCount, _detFlickerCount);
      await prefs.setInt(_keyDetectionStableCount, _detStableCount);
      await prefs.setDouble(_keyDetectionConfFloor, _detConfFloor);

      _totalFrames += _sessionFrames;
      await prefs.setInt(_keyTotalSessions, _totalSessions);
      await prefs.setInt(_keyTotalFrames, _totalFrames);
      await prefs.setInt(_keyFrameDelayMs, _frameDelayMs);
      await prefs.setString(_keyLastImproveTime,
          DateTime.now().toIso8601String());
    } catch (e) {
      GlobalErrorHandler.logDebug('AdaptiveLearning persist failed: $e');
    }
  }

  void _resetSessionState() {
    _sessionSpeedErrorSum = 0;
    _sessionSpeedSamples = 0;
    _sessionOcrSuccess = 0;
    _sessionOcrTotal = 0;
    _sessionFlickers = 0;
    _sessionStable = 0;
    _sessionFrames = 0;
    _recentSpeedDeltas.clear();
    _frameProcessingTimes.clear();
  }

  /// Reset all learned parameters to factory defaults (for testing).
  Future<void> resetToDefaults() async {
    _speedScaleFactor = 0.035;
    _areaScaleFactor = 0.8;
    _emaAlpha = 0.15;
    _plateVoteThreshold = 2;
    _ocrCropPadX = 0.05;
    _ocrCropPadBot = 0.10;
    _detConfFloor = 0.3;
    _frameDelayMs = 300;
    _lifetimeSpeedErrorSum = 0;
    _lifetimeSpeedSampleCount = 0;
    _lifetimeVarianceSum = 0;
    _lifetimeVarianceSamples = 0;
    _ocrSuccessCount = 0;
    _ocrTotalCount = 0;
    _detFlickerCount = 0;
    _detStableCount = 0;
    _totalSessions = 0;
    _totalFrames = 0;
    _resetSessionState();
    await _persist();
  }
}
