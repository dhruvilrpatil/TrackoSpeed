import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';

/// Widget for displaying user and target vehicle speeds
class SpeedDisplayWidget extends StatelessWidget {
  final double userSpeedKmh;
  final double targetSpeedKmh;
  final double relativeSpeedKmh;
  final double confidence;
  final String? plateNumber;
  final bool hasLockedTarget;

  const SpeedDisplayWidget({
    super.key,
    required this.userSpeedKmh,
    required this.targetSpeedKmh,
    required this.relativeSpeedKmh,
    required this.confidence,
    this.plateNumber,
    this.hasLockedTarget = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // User speed card
        Expanded(
          child: _buildSpeedCard(
            title: 'YOUR SPEED',
            speed: userSpeedKmh,
            icon: Icons.directions_car,
            isPrimary: false,
          ),
        ),
        const SizedBox(width: 12),
        // Target speed card
        Expanded(
          child: _buildSpeedCard(
            title: hasLockedTarget ? 'TARGET SPEED' : 'DETECTED',
            speed: targetSpeedKmh,
            icon: hasLockedTarget ? Icons.gps_fixed : Icons.remove_red_eye,
            isPrimary: true,
            plateNumber: plateNumber,
            confidence: confidence,
            relativeSpeed: relativeSpeedKmh,
          ),
        ),
      ],
    );
  }

  Widget _buildSpeedCard({
    required String title,
    required double speed,
    required IconData icon,
    required bool isPrimary,
    String? plateNumber,
    double? confidence,
    double? relativeSpeed,
  }) {
    final speedColor = AppTheme.getSpeedColor(speed);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardColor.withOpacity(0.9),
        borderRadius: BorderRadius.circular(16),
        border: isPrimary
            ? Border.all(color: speedColor.withOpacity(0.5), width: 2)
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Row(
            children: [
              Icon(icon, color: AppTheme.textSecondary, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Speed value
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                speed.toInt().toString(),
                style: TextStyle(
                  color: isPrimary ? speedColor : AppTheme.textPrimary,
                  fontSize: isPrimary ? 48 : 40,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                  height: 1,
                ),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  'km/h',
                  style: TextStyle(
                    color: isPrimary ? speedColor.withOpacity(0.7) : AppTheme.textHint,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),

          // Additional info for target
          if (isPrimary && (relativeSpeed != null || plateNumber != null)) ...[
            const SizedBox(height: 8),
//don3
            // Relative speed
            if (relativeSpeed != null && relativeSpeed.abs() > 1)
              Row(
                children: [
                  Icon(
                    relativeSpeed > 0 ? Icons.trending_up : Icons.trending_down,
                    color: relativeSpeed > 0 ? AppTheme.errorColor : AppTheme.successColor,
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${relativeSpeed > 0 ? '+' : ''}${relativeSpeed.toInt()} km/h',
                    style: TextStyle(
                      color: relativeSpeed > 0 ? AppTheme.errorColor : AppTheme.successColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    relativeSpeed > 0 ? 'approaching' : 'receding',
                    style: const TextStyle(
                      color: AppTheme.textHint,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),

            // Plate number
            if (plateNumber != null && plateNumber.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.yellow.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.yellow.withOpacity(0.5)),
                ),
                child: Text(
                  plateNumber,
                  style: const TextStyle(
                    color: Colors.yellow,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                    letterSpacing: 2,
                  ),
                ),
              ),
            ],

            // Confidence
            if (confidence != null && confidence > 0) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Text(
                    'Confidence: ',
                    style: TextStyle(color: AppTheme.textHint, fontSize: 10),
                  ),
                  Text(
                    '${(confidence * 100).toInt()}%',
                    style: TextStyle(
                      color: confidence > 0.7 ? AppTheme.successColor : AppTheme.warningColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}

