import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_theme.dart';
import '../bloc/speed_tracking_bloc.dart';
import '../widgets/permission_request_widget.dart';

/// Dashboard page - Speedometer with real logic
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  @override
  void initState() {
    super.initState();
    // Trigger initialization (permission check) on first load
    context.read<SpeedTrackingBloc>().add(const InitializeTracking());
  }

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SpeedTrackingBloc, SpeedTrackingState>(
      // Only rebuild for properties the dashboard actually displays.
      // Without this filter, the detection loop (5-10 state emissions/sec)
      // causes the dashboard to rebuild behind the camera page, hammering
      // the UI thread and causing ANR when AR mode is active.
      buildWhen: (prev, curr) =>
          prev.status != curr.status ||
          prev.userSpeedKmh.toInt() != curr.userSpeedKmh.toInt() ||
          prev.gpsValid != curr.gpsValid ||
          prev.permissions != curr.permissions ||
          prev.errorMessage != curr.errorMessage ||
          prev.dashboardAvgSpeed.toInt() != curr.dashboardAvgSpeed.toInt() ||
          prev.dashboardMaxSpeed.toInt() != curr.dashboardMaxSpeed.toInt() ||
          prev.dashboardTotalDistance != curr.dashboardTotalDistance,
      builder: (context, state) {
        // Show permission request screen when permissions are needed
        if (state.status == TrackingStatus.permissionsRequired) {
          return Scaffold(
            backgroundColor: AppTheme.backgroundColor,
            body: PermissionRequestWidget(
              permissions: state.permissions,
              onRequestPermissions: () {
                context.read<SpeedTrackingBloc>().add(const RequestPermissions());
              },
              onOpenSettings: () {
                context.read<SpeedTrackingBloc>().add(const OpenSettings());
              },
            ),
          );
        }

        return Container(
          decoration: BoxDecoration(
            gradient: _isDark
                ? AppStyles.dashboardGradient
                : AppStyles.dashboardGradientLight,
          ),
          child: SafeArea(
            child: Column(
              children: [
                _buildHeader(context, state),
                const SizedBox(height: 8),
                _buildViewToggle(context),
                const SizedBox(height: 16),
                Expanded(child: _buildSpeedometer(context, state)),
                const SizedBox(height: 8),
                _buildStatistics(context, state),
                const SizedBox(height: 16),
                _buildTrackingButton(context, state),
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, SpeedTrackingState state) {
    final textColor = _isDark ? AppTheme.textPrimary : AppTheme.textDark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Dashboard',
                style: GoogleFonts.notoSans(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: state.gpsValid ? AppTheme.successColor : AppTheme.errorColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'GPS ${state.gpsValid ? "Active" : "Inactive"}',
                    style: GoogleFonts.notoSans(
                      fontSize: 14,
                      color: textColor.withOpacity(0.7),
                      fontWeight: FontWeight.w500,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: _isDark
                  ? Colors.white.withOpacity(0.1)
                  : Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: IconButton(
              icon: Icon(Icons.settings, color: AppTheme.teal),
              onPressed: () => Navigator.of(context).pushNamed('/settings'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildViewToggle(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: (_isDark ? Colors.white : Colors.black).withOpacity(0.08),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: (_isDark ? Colors.white : AppTheme.teal).withOpacity(0.15),
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Row(
            children: [
              Expanded(
                child: _buildToggleButton(label: 'Digital', isSelected: true, onTap: () {}),
              ),
              Expanded(
                child: _buildToggleButton(
                  label: 'AR Mode',
                  isSelected: false,
                  onTap: () => Navigator.of(context).pushNamed('/camera'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToggleButton({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final textColor = _isDark ? AppTheme.textPrimary : AppTheme.textDark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          gradient: isSelected
              ? const LinearGradient(
                  colors: [AppTheme.teal, AppTheme.cyan],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isSelected ? null : Colors.transparent,
          borderRadius: BorderRadius.circular(25),
          boxShadow: isSelected
              ? [BoxShadow(color: AppTheme.teal.withOpacity(0.2), blurRadius: 6, offset: const Offset(0, 3))]
              : [],
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: GoogleFonts.notoSans(
            fontSize: 14,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            color: isSelected ? const Color(0xFF000000) : textColor.withOpacity(0.5),
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }

  Widget _buildSpeedometer(BuildContext context, SpeedTrackingState state) {
    final isTracking = state.isTrackingActive;
    final speed = isTracking ? state.userSpeedKmh : 0.0;
    final displayText = isTracking ? speed.toInt().toString() : '--';
    final textColor = _isDark ? AppTheme.textPrimary : AppTheme.textDark;

    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Speedometer gauge
          SizedBox(
            width: 280,
            height: 280,
            child: CustomPaint(
              painter: SpeedometerPainter(
                speed: speed,
                maxSpeed: 200,
                isActive: isTracking,
                isDark: _isDark,
              ),
            ),
          ),
          // Speed value
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                displayText,
                style: GoogleFonts.notoSans(
                  fontSize: 80,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                  height: 1,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'KM/H',
                style: GoogleFonts.notoSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.teal,
                  letterSpacing: 2,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatistics(BuildContext context, SpeedTrackingState state) {
    final isTracking = state.isTrackingActive;
    final avgText = state.dashboardAvgSpeed > 0
        ? '${state.dashboardAvgSpeed.toInt()}'
        : (isTracking ? '0' : '--');
    final maxText = state.dashboardMaxSpeed > 0
        ? '${state.dashboardMaxSpeed.toInt()}'
        : (isTracking ? '0' : '--');
    final distText = state.dashboardTotalDistance > 0
        ? state.dashboardTotalDistance.toStringAsFixed(1)
        : (isTracking ? '0.0' : '--');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(child: _buildStatCard(icon: Icons.speed, label: 'AVG', value: avgText)),
          const SizedBox(width: 12),
          Expanded(child: _buildStatCard(icon: Icons.arrow_upward, label: 'MAX', value: maxText)),
          const SizedBox(width: 12),
          Expanded(child: _buildStatCard(icon: Icons.show_chart, label: 'DIST', value: distText)),
        ],
      ),
    );
  }

  Widget _buildStatCard({required IconData icon, required String label, required String value}) {
    final textColor = _isDark ? AppTheme.textPrimary : AppTheme.textDark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: _isDark
                  ? [Colors.white.withOpacity(0.08), Colors.white.withOpacity(0.04)]
                  : [Colors.white.withOpacity(0.7), Colors.white.withOpacity(0.5)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: (_isDark ? Colors.white : AppTheme.teal).withOpacity(0.15),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(_isDark ? 0.3 : 0.08),
                blurRadius: 10,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            children: [
              Icon(icon, color: AppTheme.cyan, size: 28),
              const SizedBox(height: 8),
              Text(
                label,
                style: GoogleFonts.notoSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: textColor.withOpacity(0.6),
                  letterSpacing: 1,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: GoogleFonts.notoSans(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTrackingButton(BuildContext context, SpeedTrackingState state) {
    final isTracking = state.isTrackingActive;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (isTracking) {
              context.read<SpeedTrackingBloc>().add(const StopTracking());
            } else {
              context.read<SpeedTrackingBloc>().add(const StartTracking());
            }
          },
          borderRadius: BorderRadius.circular(30),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppTheme.teal, AppTheme.cyan],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.teal.withOpacity(0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(isTracking ? Icons.stop : Icons.play_arrow, color: const Color(0xFF000000), size: 28),
                const SizedBox(width: 12),
                Text(
                  isTracking ? 'Stop Tracking' : 'Start Tracking',
                  style: GoogleFonts.notoSans(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF000000),
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Realistic speedometer gauge painter with tick marks and needle
class SpeedometerPainter extends CustomPainter {
  final double speed;
  final double maxSpeed;
  final bool isActive;
  final bool isDark;

  SpeedometerPainter({
    required this.speed,
    required this.maxSpeed,
    this.isActive = false,
    this.isDark = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    const strokeWidth = 14.0;

    // Arc goes from 135° to 405° (270° sweep)
    const startAngle = 135.0 * math.pi / 180;
    const sweepAngle = 270.0 * math.pi / 180;

    // Background arc
    final bgPaint = Paint()
      ..color = (isDark ? Colors.white : Colors.black).withOpacity(0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - strokeWidth / 2),
      startAngle,
      sweepAngle,
      false,
      bgPaint,
    );

    // Draw tick marks
    _drawTicks(canvas, center, radius, startAngle, sweepAngle);

    if (!isActive) return;

    // Progress arc colored by speed
    final speedRatio = (speed / maxSpeed).clamp(0.0, 1.0);
    final progressSweep = sweepAngle * speedRatio;

    Color arcColor;
    if (speed < 30) {
      arcColor = AppTheme.speedLow;
    } else if (speed < 80) {
      arcColor = AppTheme.speedMedium;
    } else {
      arcColor = AppTheme.speedHigh;
    }

    final progressPaint = Paint()
      ..color = arcColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - strokeWidth / 2),
      startAngle,
      progressSweep,
      false,
      progressPaint,
    );

    // No needle — user requested removal. Only arc + ticks are shown.
  }

  void _drawTicks(Canvas canvas, Offset center, double radius, double startAngle, double sweepAngle) {
    final tickColor = isDark ? AppTheme.textPrimary : AppTheme.textDark;
    final tickPaint = Paint()
      ..color = tickColor.withOpacity(0.2)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    final majorTickPaint = Paint()
      ..color = tickColor.withOpacity(0.4)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    // 10 major segments (0, 20, 40 ... 200)
    for (int i = 0; i <= 40; i++) {
      final angle = startAngle + (sweepAngle * i / 40);
      final isMajor = i % 4 == 0;
      final innerRadius = radius - (isMajor ? 35 : 28);
      final outerRadius = radius - 20;

      final start = Offset(
        center.dx + innerRadius * math.cos(angle),
        center.dy + innerRadius * math.sin(angle),
      );
      final end = Offset(
        center.dx + outerRadius * math.cos(angle),
        center.dy + outerRadius * math.sin(angle),
      );

      canvas.drawLine(start, end, isMajor ? majorTickPaint : tickPaint);
    }
  }

  @override
  bool shouldRepaint(SpeedometerPainter oldDelegate) {
    return oldDelegate.speed != speed || oldDelegate.maxSpeed != maxSpeed || oldDelegate.isActive != isActive || oldDelegate.isDark != isDark;
  }
}
