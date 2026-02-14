import 'package:uuid/uuid.dart';
import '../error/error_handler.dart';
import '../platform/vehicle_detection_service.dart';

/// Tracked vehicle with persistent ID across frames
class TrackedVehicle {
  final String trackingId;
  final DetectedVehicle detection;
  final double estimatedSpeed;
  final int frameCount;
  final DateTime firstSeen;
  final DateTime lastSeen;
  final bool isLocked; // User has locked onto this vehicle

  const TrackedVehicle({
    required this.trackingId,
    required this.detection,
    required this.estimatedSpeed,
    required this.frameCount,
    required this.firstSeen,
    required this.lastSeen,
    this.isLocked = false,
  });

  TrackedVehicle copyWith({
    String? trackingId,
    DetectedVehicle? detection,
    double? estimatedSpeed,
    int? frameCount,
    DateTime? firstSeen,
    DateTime? lastSeen,
    bool? isLocked,
  }) {
    return TrackedVehicle(
      trackingId: trackingId ?? this.trackingId,
      detection: detection ?? this.detection,
      estimatedSpeed: estimatedSpeed ?? this.estimatedSpeed,
      frameCount: frameCount ?? this.frameCount,
      firstSeen: firstSeen ?? this.firstSeen,
      lastSeen: lastSeen ?? this.lastSeen,
      isLocked: isLocked ?? this.isLocked,
    );
  }

  /// Age in milliseconds since last update
  int get ageMs => DateTime.now().difference(lastSeen).inMilliseconds;

  /// Whether this track is stale and should be removed
  bool get isStale => ageMs > 2000; // 2 seconds without update

  @override
  String toString() => 'TrackedVehicle($trackingId, speed:${estimatedSpeed.toInt()} km/h, frames:$frameCount)';
}

/// Service for tracking vehicles across frames
///
/// Uses IoU (Intersection over Union) matching to associate detections
/// across consecutive frames and maintain persistent tracking IDs.
class VehicleTrackerService with ErrorHandlerMixin {
  final _uuid = const Uuid();

  // Active tracks
  final Map<String, TrackedVehicle> _activeTracks = {};

  // Configuration
  static const double _iouThreshold = 0.15; // Lower IoU for better matching across frames
  static const int _maxTracks = 20;
  static const int _staleThresholdMs = 2000;
  static const int _lockedStaleThresholdMs = 5000; // Locked targets persist much longer

  /// Maximum centroid distance (as fraction of image diagonal) for
  /// centroid-based matching when IoU is low (fast-moving vehicles).
  static const double _centroidDistThreshold = 0.20;

  /// Even larger centroid search radius for locked targets so they
  /// are re-matched even after significant movement.
  static const double _lockedCentroidDistThreshold = 0.35;

  /// Smoothing factor for locked target bounding box (0 = no smoothing, 1 = freeze).
  /// Interpolates between previous and new bbox to avoid jitter.
  static const double _lockedBboxSmoothing = 0.35;

  // Locked target
  String? _lockedTargetId;

  /// Get all active tracked vehicles
  List<TrackedVehicle> get activeTracks => _activeTracks.values.toList();

  /// Get the locked target if any
  TrackedVehicle? get lockedTarget {
    if (_lockedTargetId == null) return null;
    return _activeTracks[_lockedTargetId];
  }

  /// Whether a target is currently locked
  bool get hasLockedTarget => _lockedTargetId != null && _activeTracks.containsKey(_lockedTargetId);

  /// Update tracks with new detections
  List<TrackedVehicle> updateTracks(
    List<DetectedVehicle> detections, {
    Map<String, double>? speedEstimates,
  }) {
    try {
      final now = DateTime.now();

      // Remove stale tracks (locked targets get a longer grace period)
      _removeStale();

      // Match detections to existing tracks
      final matchedDetections = <int>{};
      final updatedTracks = <String, TrackedVehicle>{};

      // ── Phase 1: match LOCKED target first (highest priority) ──
      if (_lockedTargetId != null && _activeTracks.containsKey(_lockedTargetId)) {
        final lockedTrack = _activeTracks[_lockedTargetId]!;
        int? bestIdx;
        double bestScore = 0;

        for (var i = 0; i < detections.length; i++) {
          if (matchedDetections.contains(i)) continue;

          // Combined score: IoU + class match + size similarity
          double score = 0;
          final iou = _calculateIoU(lockedTrack.detection.boundingBox, detections[i].boundingBox);
          score += iou * 2.0; // IoU is heavily weighted

          // Class match bonus
          if (lockedTrack.detection.className == detections[i].className) {
            score += 0.3;
          }

          // Size similarity bonus (ratio of areas)
          final areaRatio = _areaSimilarity(lockedTrack.detection.boundingBox, detections[i].boundingBox);
          score += areaRatio * 0.3;

          // Centroid proximity bonus
          final centDist = _centroidDistance(lockedTrack.detection.boundingBox, detections[i].boundingBox);
          if (centDist < _lockedCentroidDistThreshold) {
            score += (1.0 - centDist / _lockedCentroidDistThreshold) * 0.4;
          }

          if (score > bestScore) {
            bestScore = score;
            bestIdx = i;
          }
        }

        // Accept match if score is reasonable (even a weak match is better for locked target)
        if (bestIdx != null && bestScore > 0.15) {
          matchedDetections.add(bestIdx);
          final detection = detections[bestIdx];
          final speed = speedEstimates?[_lockedTargetId!] ?? lockedTrack.estimatedSpeed;

          // Smooth the bounding box for locked targets to avoid jitter
          final smoothedBbox = _smoothBoundingBox(
            lockedTrack.detection.boundingBox,
            detection.boundingBox,
            _lockedBboxSmoothing,
          );

          updatedTracks[_lockedTargetId!] = lockedTrack.copyWith(
            detection: detection.copyWith(
              trackingId: _lockedTargetId,
              boundingBox: smoothedBbox,
            ),
            estimatedSpeed: speed,
            frameCount: lockedTrack.frameCount + 1,
            lastSeen: now,
          );
        } else {
          // No match — keep locked track alive with old bbox (will go stale eventually)
          updatedTracks[_lockedTargetId!] = lockedTrack;
        }
      }

      // ── Phase 2: match remaining (non-locked) tracks ──
      for (final entry in _activeTracks.entries) {
        final trackId = entry.key;
        final track = entry.value;
        if (trackId == _lockedTargetId) continue; // already handled

        // Find best matching detection using IoU
        int? bestMatchIndex;
        double bestIoU = _iouThreshold;

        for (var i = 0; i < detections.length; i++) {
          if (matchedDetections.contains(i)) continue;

          final iou = _calculateIoU(track.detection.boundingBox, detections[i].boundingBox);
          if (iou > bestIoU) {
            bestIoU = iou;
            bestMatchIndex = i;
          }
        }

        // Centroid-distance fallback for fast-moving vehicles whose
        // boxes barely overlap between frames.
        if (bestMatchIndex == null) {
          double bestCentroidScore = double.infinity;
          for (var i = 0; i < detections.length; i++) {
            if (matchedDetections.contains(i)) continue;
            final dist = _centroidDistance(
                track.detection.boundingBox, detections[i].boundingBox);
            // Also check class match — only same vehicle type
            if (track.detection.className == detections[i].className &&
                dist < _centroidDistThreshold &&
                dist < bestCentroidScore) {
              bestCentroidScore = dist;
              bestMatchIndex = i;
            }
          }
        }

        if (bestMatchIndex != null) {
          // Update existing track
          matchedDetections.add(bestMatchIndex);
          final detection = detections[bestMatchIndex];
          final speed = speedEstimates?[trackId] ?? track.estimatedSpeed;

          updatedTracks[trackId] = track.copyWith(
            detection: detection.copyWith(trackingId: trackId),
            estimatedSpeed: speed,
            frameCount: track.frameCount + 1,
            lastSeen: now,
          );
        } else if (!track.isStale) {
          // Keep track even without match (might reappear)
          updatedTracks[trackId] = track;
        }
      }

      // Create new tracks for unmatched detections
      for (var i = 0; i < detections.length; i++) {
        if (matchedDetections.contains(i)) continue;
        if (updatedTracks.length >= _maxTracks) break;

        final trackId = _uuid.v4().substring(0, 8);
        final detection = detections[i].copyWith(trackingId: trackId);

        updatedTracks[trackId] = TrackedVehicle(
          trackingId: trackId,
          detection: detection,
          estimatedSpeed: 0,
          frameCount: 1,
          firstSeen: now,
          lastSeen: now,
        );
      }

      _activeTracks
        ..clear()
        ..addAll(updatedTracks);

      return _activeTracks.values.toList();
    } catch (e) {
      GlobalErrorHandler.handleError(e, context: 'Update tracks');
      return _activeTracks.values.toList();
    }
  }

  /// Lock onto a specific vehicle
  void lockTarget(String trackingId) {
    if (_activeTracks.containsKey(trackingId)) {
      _lockedTargetId = trackingId;
      _activeTracks[trackingId] = _activeTracks[trackingId]!.copyWith(isLocked: true);
      GlobalErrorHandler.logInfo('Locked onto vehicle: $trackingId');
    }
  }

  /// Lock onto the primary (largest/closest) vehicle
  void lockPrimaryTarget() {
    if (_activeTracks.isEmpty) return;

    // Find primary target (largest bounding box, highest confidence)
    TrackedVehicle? primary;
    double bestScore = 0;

    for (final track in _activeTracks.values) {
      final area = track.detection.boundingBox.area;
      final confidence = track.detection.confidence;
      final score = area * confidence;

      if (score > bestScore) {
        bestScore = score;
        primary = track;
      }
    }

    if (primary != null) {
      lockTarget(primary.trackingId);
    }
  }

  /// Unlock current target
  void unlockTarget() {
    if (_lockedTargetId != null && _activeTracks.containsKey(_lockedTargetId)) {
      _activeTracks[_lockedTargetId!] = _activeTracks[_lockedTargetId!]!.copyWith(isLocked: false);
    }
    _lockedTargetId = null;
    GlobalErrorHandler.logInfo('Target unlocked');
  }

  /// Get track by ID
  TrackedVehicle? getTrack(String trackingId) {
    return _activeTracks[trackingId];
  }

  /// Update speed for a specific track
  void updateSpeed(String trackingId, double speed) {
    if (_activeTracks.containsKey(trackingId)) {
      _activeTracks[trackingId] = _activeTracks[trackingId]!.copyWith(
        estimatedSpeed: speed,
      );
    }
  }

  /// Calculate IoU between two bounding boxes
  double _calculateIoU(BoundingBox box1, BoundingBox box2) {
    final intersectLeft = box1.left > box2.left ? box1.left : box2.left;
    final intersectTop = box1.top > box2.top ? box1.top : box2.top;
    final intersectRight = box1.right < box2.right ? box1.right : box2.right;
    final intersectBottom = box1.bottom < box2.bottom ? box1.bottom : box2.bottom;

    final intersectWidth = (intersectRight - intersectLeft).clamp(0, double.infinity);
    final intersectHeight = (intersectBottom - intersectTop).clamp(0, double.infinity);
    final intersectArea = intersectWidth * intersectHeight;

    final area1 = box1.area;
    final area2 = box2.area;
    final unionArea = area1 + area2 - intersectArea;

    if (unionArea <= 0) return 0;
    return intersectArea / unionArea;
  }

  /// Calculate normalised centroid distance between two bounding boxes.
  /// Returns a value in [0, ~1.4] representing how far apart the centers
  /// are relative to the image diagonal (assuming coords are in pixels).
  double _centroidDistance(BoundingBox box1, BoundingBox box2) {
    final dx = box1.centerX - box2.centerX;
    final dy = box1.centerY - box2.centerY;
    final dist = (dx * dx + dy * dy);
    // Normalise by approximate image diagonal squared
    // Using box sizes as proxy for image scale
    final avgSize = ((box1.width + box1.height + box2.width + box2.height) / 4);
    if (avgSize <= 0) return double.infinity;
    return dist / (avgSize * avgSize * 100); // scaled to ~0..1 range
  }

  /// Remove stale tracks (locked targets get a longer grace period)
  void _removeStale() {
    _activeTracks.removeWhere((id, track) {
      if (id == _lockedTargetId) {
        // Locked target gets extended lifetime
        return track.ageMs > _lockedStaleThresholdMs;
      }
      return track.ageMs > _staleThresholdMs;
    });
  }

  /// Smoothly interpolate between old and new bounding boxes.
  /// [smoothing] controls how much of the OLD position to keep (0 = fully new, 1 = fully old).
  BoundingBox _smoothBoundingBox(BoundingBox old, BoundingBox detected, double smoothing) {
    return BoundingBox(
      left:   old.left   * smoothing + detected.left   * (1 - smoothing),
      top:    old.top    * smoothing + detected.top    * (1 - smoothing),
      right:  old.right  * smoothing + detected.right  * (1 - smoothing),
      bottom: old.bottom * smoothing + detected.bottom * (1 - smoothing),
    );
  }

  /// Return a similarity score for two bounding box areas (0 = very different, 1 = identical).
  double _areaSimilarity(BoundingBox a, BoundingBox b) {
    final areaA = a.area;
    final areaB = b.area;
    if (areaA <= 0 || areaB <= 0) return 0;
    final ratio = areaA < areaB ? areaA / areaB : areaB / areaA;
    return ratio; // 0..1
  }

  /// Clear all tracks
  void reset() {
    _activeTracks.clear();
    _lockedTargetId = null;
  }
}

