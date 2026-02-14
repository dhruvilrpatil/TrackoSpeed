import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/services/vehicle_tracker_service.dart';

// ── Constants ────────────────────────────────────────────────────

/// Minimum detection confidence to draw a bounding box.
const double _minDisplayConfidence = 0.40;

/// A vehicle must be tracked for at least this many consecutive frames
/// before its box appears.
const int _minFrameCount = 2;

/// Minimum bounding‐box area as fraction of the full frame.
/// Tiny boxes (< 0.5 % of frame) are too far or likely noise.
const double _minAreaFraction = 0.005;

/// Allowed vehicle classes — only Cars, Buses, Trucks, and Bikes.
const Set<String> _vehicleClassNames = {
  'car', 'truck', 'bus', 'motorcycle', 'motorbike', 'bicycle', 'bike',
};

// ── Main widget ──────────────────────────────────────────────────

/// Draws animated bounding boxes **only** over detected vehicles.
///
/// Key rules:
/// - Box appears only after the vehicle has been tracked ≥ [_minFrameCount]
///   frames AND confidence ≥ [_minDisplayConfidence].
/// - Box size comes from the actual detection bounding box (dynamic).
/// - Plate number is shown only when it looks like a full plate.
/// - A three‐dot "calculating…" animation appears while speed is 0.
/// - Labels are clamped inside the screen so nothing overlaps.
class VehicleOverlayWidget extends StatelessWidget {
  final List<TrackedVehicle> vehicles;
  final TrackedVehicle? lockedTarget;
  final double confidenceScore;
  final String? plateText;
  final double detectionFrameWidth;
  final double detectionFrameHeight;
  final void Function(String trackingId)? onVehicleTap;

  const VehicleOverlayWidget({
    super.key,
    required this.vehicles,
    this.lockedTarget,
    this.confidenceScore = 0.5,
    this.plateText,
    this.detectionFrameWidth = 1280,
    this.detectionFrameHeight = 720,
    this.onVehicleTap,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final frameArea = w * h;

        final displayable = vehicles.where((v) {
          // ── gate 0: reject native-side fallback stubs
          if (v.detection.isFallback) return false;
          // ── gate 1: vehicle class
          final cls = v.detection.className.toLowerCase();
          if (!_vehicleClassNames.contains(cls)) return false;
          // ── gate 2: confidence
          if (v.detection.confidence < _minDisplayConfidence) return false;
          // ── gate 3: positive area
          if (v.detection.boundingBox.area <= 0) return false;
          // ── gate 4: minimum screen‐area fraction
          final box = v.detection.boundingBox;
          final screenW = box.width * (w / detectionFrameWidth);
          final screenH = box.height * (h / detectionFrameHeight);
          if ((screenW * screenH) / frameArea < _minAreaFraction) return false;
          // ── gate 5: tracked for enough frames
          if (v.frameCount < _minFrameCount) return false;
          return true;
        }).toList();

        return Stack(
          clipBehavior: Clip.hardEdge,
          children: displayable.map((vehicle) {
            final isLocked =
                lockedTarget?.trackingId == vehicle.trackingId;
            return _VehicleBox(
              key: ValueKey(vehicle.trackingId),
              vehicle: vehicle,
              isLocked: isLocked,
              containerWidth: w,
              containerHeight: h,
              detectionFrameWidth: detectionFrameWidth,
              detectionFrameHeight: detectionFrameHeight,
              plateText: isLocked ? plateText : null,
              onTap: () => onVehicleTap?.call(vehicle.trackingId),
            );
          }).toList(),
        );
      },
    );
  }
}

// ═════════════════════════════════════════════════════════════════
// Single animated vehicle box
// ═════════════════════════════════════════════════════════════════
class _VehicleBox extends StatelessWidget {
  final TrackedVehicle vehicle;
  final bool isLocked;
  final double containerWidth;
  final double containerHeight;
  final double detectionFrameWidth;
  final double detectionFrameHeight;
  final String? plateText;
  final VoidCallback? onTap;

  const _VehicleBox({
    super.key,
    required this.vehicle,
    required this.isLocked,
    required this.containerWidth,
    required this.containerHeight,
    required this.detectionFrameWidth,
    required this.detectionFrameHeight,
    this.plateText,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final box = vehicle.detection.boundingBox;

    // Scale detection-frame pixel coords to overlay container coords.
    final double sx = containerWidth  / detectionFrameWidth;
    final double sy = containerHeight / detectionFrameHeight;

    final left = (box.left * sx).clamp(0.0, containerWidth - 24);
    final top = (box.top * sy).clamp(0.0, containerHeight - 24);
    final width = (box.width * sx).clamp(24.0, containerWidth - left);
    final height = (box.height * sy).clamp(24.0, containerHeight - top);

    final color = isLocked
        ? const Color(0xFFFF1744)
        : _colorForConfidence(vehicle.detection.confidence);
    final borderW = isLocked ? 3.5 : 2.0;

    // Clamp label positions to keep them inside the screen.
    final speedTagTop = (top - 34).clamp(0.0, containerHeight - 28);
    final classTagTop =
        (top + height + 6).clamp(0.0, containerHeight - 20);

    final showPlate = _isPlateComplete(plateText);
    final speedLoading = vehicle.estimatedSpeed <= 0 && vehicle.frameCount < 8;

    // Locked targets get longer animation for smoother visual tracking
    final animDuration = isLocked
        ? const Duration(milliseconds: 300)
        : const Duration(milliseconds: 180);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // ── bounding box ──
        AnimatedPositioned(
          duration: animDuration,
          curve: Curves.easeOutCubic,
          left: left,
          top: top,
          width: width,
          height: height,
          child: GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.translucent,
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _BoxPainter(
                  color: color,
                  borderWidth: borderW,
                  showCorners: true,
                  fillAlpha: isLocked ? 0.14 : 0.04,
                  cornerLength: isLocked ? 20.0 : 14.0,
                ),
              ),
            ),
          ),
        ),

        // ── locked glow border (extra outer glow for locked target) ──
        if (isLocked)
          AnimatedPositioned(
            duration: animDuration,
            curve: Curves.easeOutCubic,
            left: left - 3,
            top: top - 3,
            width: width + 6,
            height: height + 6,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: const Color(0xFFFF1744).withValues(alpha: 0.4),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFF1744).withValues(alpha: 0.35),
                      blurRadius: 16,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
            ),
          ),

        // ── speed tag (above box) ──
        AnimatedPositioned(
          duration: animDuration,
          curve: Curves.easeOutCubic,
          left: left,
          top: speedTagTop,
          child: _SpeedTag(
            speed: vehicle.estimatedSpeed,
            isLoading: speedLoading,
            isLocked: isLocked,
            color: color,
          ),
        ),

        // ── class + plate tag (below box) ──
        AnimatedPositioned(
          duration: animDuration,
          curve: Curves.easeOutCubic,
          left: left,
          top: classTagTop,
          child: _ClassTag(
            className: vehicle.detection.className,
            plateText: showPlate ? plateText : null,
            color: color,
            confidence: vehicle.detection.confidence,
          ),
        ),
      ],
    );
  }

  /// A plate is "complete" when it has ≥ 4 alphanumeric chars.
  /// (lowered from 6 so that plates like "MH48AW2767" always pass)
  static bool _isPlateComplete(String? plate) {
    if (plate == null || plate.isEmpty) return false;
    final cleaned = plate.replaceAll(RegExp(r'[\s\-\.]'), '');
    if (cleaned.length < 4) return false;
    // Must have at least 1 letter and 1 digit
    if (!RegExp(r'[A-Za-z]').hasMatch(cleaned)) return false;
    if (!RegExp(r'[0-9]').hasMatch(cleaned)) return false;
    return true;
  }

  Color _colorForConfidence(double c) {
    if (c >= 0.75) return AppTheme.boundingBoxPrimary;
    if (c >= 0.55) return AppTheme.boundingBoxSecondary;
    return AppTheme.boundingBoxTertiary;
  }
}

// ═════════════════════════════════════════════════════════════════
// Speed tag chip (with optional "loading" dots)
// ═════════════════════════════════════════════════════════════════
class _SpeedTag extends StatelessWidget {
  final double speed;
  final bool isLoading;
  final bool isLocked;
  final Color color;

  const _SpeedTag({
    required this.speed,
    required this.isLoading,
    required this.isLocked,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(6),
        border: isLocked
            ? Border.all(color: const Color(0xFFFF1744).withValues(alpha: 0.6), width: 1)
            : null,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: isLocked ? 0.6 : 0.4),
            blurRadius: isLocked ? 12 : 8,
            offset: const Offset(0, 2),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isLocked) ...[
            const Icon(Icons.gps_fixed, color: Colors.white, size: 12),
            const SizedBox(width: 4),
          ],
          if (isLoading) ...[
            const _PulsingSpeedLoader(),
          ] else ...[
            Text(
              '${speed.toInt()} km/h',
              style: GoogleFonts.notoSans(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                decoration: TextDecoration.none,
                height: 1.2,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════
// Pulsing speed loader — animated "calculating" indicator inside box
// ═════════════════════════════════════════════════════════════════
class _PulsingSpeedLoader extends StatefulWidget {
  const _PulsingSpeedLoader();

  @override
  State<_PulsingSpeedLoader> createState() => _PulsingSpeedLoaderState();
}

class _PulsingSpeedLoaderState extends State<_PulsingSpeedLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Pulsing text
            Opacity(
              opacity: 0.5 + (_ctrl.value * 0.5),
              child: Text(
                '-- km/h',
                style: GoogleFonts.notoSans(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  decoration: TextDecoration.none,
                  height: 1.2,
                ),
              ),
            ),
            const SizedBox(width: 5),
            // Animated dots
            ...List.generate(3, (i) {
              final phase = (_ctrl.value + i * 0.25) % 1.0;
              final opacity = (phase < 0.5)
                  ? (phase * 2.0)
                  : (2.0 - phase * 2.0);
              return Container(
                width: 4,
                height: 4,
                margin: const EdgeInsets.only(left: 2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: opacity.clamp(0.25, 1.0)),
                ),
              );
            }),
          ],
        );
      },
    );
  }
}

// ═════════════════════════════════════════════════════════════════
// Class name + optional plate label
// ═════════════════════════════════════════════════════════════════
class _ClassTag extends StatelessWidget {
  final String className;
  final String? plateText;
  final Color color;
  final double confidence;

  const _ClassTag({
    required this.className,
    this.plateText,
    required this.color,
    this.confidence = 0.0,
  });

  @override
  Widget build(BuildContext context) {
    final label = plateText != null
        ? '${_vehicleLabel(className)} · $plateText'
        : _vehicleLabel(className);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.cardColor.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_vehicleIcon(className), color: color, size: 10),
          const SizedBox(width: 4),
          Text(
            label,
            maxLines: 1,
            style: GoogleFonts.notoSans(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.none,
              height: 1.3,
            ),
          ),
          if (confidence > 0) ...[
            const SizedBox(width: 4),
            Text(
              '${(confidence * 100).toInt()}%',
              style: GoogleFonts.notoSans(
                color: color.withValues(alpha: 0.7),
                fontSize: 9,
                fontWeight: FontWeight.w500,
                decoration: TextDecoration.none,
                height: 1.3,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Get human-readable vehicle label
  static String _vehicleLabel(String className) {
    switch (className.toLowerCase()) {
      case 'car':
        return 'CAR';
      case 'truck':
        return 'TRUCK';
      case 'bus':
        return 'BUS';
      case 'motorcycle':
      case 'motorbike':
      case 'bike':
        return 'BIKE';
      case 'bicycle':
        return 'BICYCLE';
      default:
        return className.toUpperCase();
    }
  }

  /// Get icon for vehicle type
  static IconData _vehicleIcon(String className) {
    switch (className.toLowerCase()) {
      case 'car':
        return Icons.directions_car;
      case 'truck':
        return Icons.local_shipping;
      case 'bus':
        return Icons.directions_bus;
      case 'motorcycle':
      case 'motorbike':
      case 'bike':
        return Icons.two_wheeler;
      case 'bicycle':
        return Icons.pedal_bike;
      default:
        return Icons.directions_car;
    }
  }
}

// ═════════════════════════════════════════════════════════════════
// Box painter with optional corner brackets
// ═════════════════════════════════════════════════════════════════
class _BoxPainter extends CustomPainter {
  final Color color;
  final double borderWidth;
  final bool showCorners;
  final double fillAlpha;
  final double cornerLength;

  _BoxPainter({
    required this.color,
    required this.borderWidth,
    required this.showCorners,
    required this.fillAlpha,
    this.cornerLength = 14.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final rr = RRect.fromRectAndRadius(rect, const Radius.circular(6));

    // Semi-transparent fill
    if (fillAlpha > 0) {
      canvas.drawRRect(
        rr,
        Paint()..color = color.withValues(alpha: fillAlpha),
      );
    }

    // Dashed-style border (thin lines along the edges)
    canvas.drawRRect(
      rr,
      Paint()
        ..color = color.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    // Corner brackets — always shown for a polished look
    if (showCorners) {
      final p = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth
        ..strokeCap = StrokeCap.round;
      final c = (size.width * 0.15).clamp(10.0, cornerLength);

      // Top-left
      canvas.drawLine(Offset(0, c), Offset.zero, p);
      canvas.drawLine(const Offset(0, 0), Offset(c, 0), p);
      // Top-right
      canvas.drawLine(Offset(size.width - c, 0), Offset(size.width, 0), p);
      canvas.drawLine(Offset(size.width, 0), Offset(size.width, c), p);
      // Bottom-left
      canvas.drawLine(Offset(0, size.height - c), Offset(0, size.height), p);
      canvas.drawLine(Offset(0, size.height), Offset(c, size.height), p);
      // Bottom-right
      canvas.drawLine(
          Offset(size.width - c, size.height), Offset(size.width, size.height), p);
      canvas.drawLine(
          Offset(size.width, size.height - c), Offset(size.width, size.height), p);
    }
  }

  @override
  bool shouldRepaint(_BoxPainter old) =>
      old.color != color ||
      old.borderWidth != borderWidth ||
      old.showCorners != showCorners ||
      old.fillAlpha != fillAlpha ||
      old.cornerLength != cornerLength;
}

