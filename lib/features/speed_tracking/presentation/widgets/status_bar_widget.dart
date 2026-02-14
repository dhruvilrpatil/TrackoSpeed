import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';

/// Status bar widget showing GPS status, capture count, etc.
class StatusBarWidget extends StatelessWidget {
  final bool gpsValid;
  final double gpsAccuracy;
  final bool isTracking;
  final int captureCount;
  final bool flashEnabled;
  final VoidCallback onFlashToggle;

  const StatusBarWidget({
    super.key,
    required this.gpsValid,
    required this.gpsAccuracy,
    required this.isTracking,
    required this.captureCount,
    required this.flashEnabled,
    required this.onFlashToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withOpacity(0.7),
            Colors.transparent,
          ],
        ),
      ),
      child: Row(
        children: [
          // App title
          const Text(
            'TrackoSpeed',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),

          // GPS indicator
          _buildStatusChip(
            icon: gpsValid ? Icons.gps_fixed : Icons.gps_not_fixed,
            label: gpsValid
                ? '${gpsAccuracy.toInt()}m'
                : 'No GPS',
            color: gpsValid ? AppTheme.successColor : AppTheme.errorColor,
          ),
          const SizedBox(width: 12),

          // Tracking indicator
          if (isTracking)
            _buildStatusChip(
              icon: Icons.circle,
              label: 'REC',
              color: AppTheme.errorColor,
              iconSize: 10,
              animated: true,
            ),
          const SizedBox(width: 12),

          // Capture count
          if (captureCount > 0)
            _buildStatusChip(
              icon: Icons.photo_camera,
              label: '$captureCount',
              color: AppTheme.primaryColor,
            ),
          const SizedBox(width: 12),

          // Flash toggle
          GestureDetector(
            onTap: onFlashToggle,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: flashEnabled
                    ? AppTheme.warningColor.withOpacity(0.3)
                    : AppTheme.cardColor.withOpacity(0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                flashEnabled ? Icons.flash_on : Icons.flash_off,
                color: flashEnabled
                    ? AppTheme.warningColor
                    : AppTheme.textSecondary,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip({
    required IconData icon,
    required String label,
    required Color color,
    double iconSize = 14,
    bool animated = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          animated
              ? _AnimatedDot(color: color, size: iconSize)
              : Icon(icon, color: color, size: iconSize),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedDot extends StatefulWidget {
  final Color color;
  final double size;

  const _AnimatedDot({required this.color, required this.size});

  @override
  State<_AnimatedDot> createState() => _AnimatedDotState();
}

class _AnimatedDotState extends State<_AnimatedDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: 0.3 + (_controller.value * 0.7),
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color,
            ),
          ),
        );
      },
    );
  }
}

