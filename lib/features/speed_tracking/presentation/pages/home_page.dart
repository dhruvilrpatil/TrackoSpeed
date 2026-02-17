import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_theme.dart';
import '../bloc/speed_tracking_bloc.dart';
import '../widgets/speed_display_widget.dart';
import '../widgets/camera_preview_widget.dart';
import '../widgets/vehicle_overlay_widget.dart';
import '../widgets/capture_button_widget.dart';
import '../widgets/permission_request_widget.dart';
import '../widgets/status_bar_widget.dart';

/// Home page - main tracking interface
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Initialize tracking when page loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SpeedTrackingBloc>().add(const InitializeTracking());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final bloc = context.read<SpeedTrackingBloc>();

    if (state == AppLifecycleState.paused) {
      // Only stop if actively tracking — avoids heavy cleanup when the
      // user simply opens Gmail from Settings or switches apps briefly.
      if (bloc.state.isTrackingActive) {
        bloc.add(const StopTracking());
      }
    } else if (state == AppLifecycleState.resumed) {
      // Only re-initialize if in an error or uninitialized state.
      // Skips the expensive camera + TFLite re-init when resuming from
      // external apps (Gmail, gallery, etc.) which caused ANR.
      final status = bloc.state.status;
      if (status != TrackingStatus.tracking &&
          status != TrackingStatus.idle &&
          status != TrackingStatus.capturing) {
        bloc.add(const InitializeTracking());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: BlocConsumer<SpeedTrackingBloc, SpeedTrackingState>(
        listener: _handleStateChanges,
        builder: (context, state) {
          return SafeArea(
            child: _buildContent(context, state),
          );
        },
      ),
    );
  }

  void _handleStateChanges(BuildContext context, SpeedTrackingState state) {
    // Show capture feedback
    if (state.lastCaptureMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                state.lastCapturePath != null
                    ? Icons.check_circle
                    : Icons.error,
                color: state.lastCapturePath != null
                    ? AppTheme.successColor
                    : AppTheme.errorColor,
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(state.lastCaptureMessage!)),
            ],
          ),
          backgroundColor: AppTheme.cardColor,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }

    // Show errors
    if (state.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: AppTheme.errorColor),
              const SizedBox(width: 12),
              Expanded(child: Text(state.errorMessage!)),
            ],
          ),
          backgroundColor: AppTheme.cardColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _buildContent(BuildContext context, SpeedTrackingState state) {
    // Show permission request if needed
    if (state.status == TrackingStatus.permissionsRequired) {
      return PermissionRequestWidget(
        permissions: state.permissions,
        onRequestPermissions: () {
          context.read<SpeedTrackingBloc>().add(const RequestPermissions());
        },
        onOpenSettings: () {
          context.read<SpeedTrackingBloc>().add(const OpenSettings());
        },
      );
    }

    // Show loading during initialization
    if (state.status == TrackingStatus.initializing) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppTheme.primaryColor),
            SizedBox(height: 24),
            Text(
              'Initializing...',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ],
        ),
      );
    }

    // Main tracking interface
    return Stack(
      children: [
        // Camera preview (full screen)
        const Positioned.fill(
          child: CameraPreviewWidget(),
        ),

        // Gradient overlay for readability
        Positioned.fill(
          child: IgnorePointer(
            child: Container(
              decoration: const BoxDecoration(
                gradient: AppStyles.overlayGradient,
              ),
            ),
          ),
        ),

        // Vehicle detection overlays
        if (state.status == TrackingStatus.tracking ||
            state.status == TrackingStatus.capturing)
          Positioned.fill(
            child: VehicleOverlayWidget(
              vehicles: state.trackedVehicles,
              lockedTarget: state.lockedTarget,
              onVehicleTap: (trackingId) {
                context.read<SpeedTrackingBloc>().add(LockTarget(trackingId));
              },
            ),
          ),

        // Top status bar
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: StatusBarWidget(
            gpsValid: state.gpsValid,
            gpsAccuracy: state.gpsAccuracy,
            isTracking: state.status == TrackingStatus.tracking,
            captureCount: state.captureCount,
            flashEnabled: state.flashEnabled,
            onFlashToggle: () {
              context.read<SpeedTrackingBloc>().add(const ToggleFlash());
            },
          ),
        ),

        // Speed display (user + target)
        Positioned(
          top: 80,
          left: 16,
          right: 16,
          child: SpeedDisplayWidget(
            userSpeedKmh: state.userSpeedKmh,
            targetSpeedKmh: state.targetSpeedKmh,
            relativeSpeedKmh: state.relativeSpeedKmh,
            confidence: state.confidenceScore,
            plateNumber: state.detectedPlate,
            hasLockedTarget: state.lockedTarget != null,
          ),
        ),

        // Bottom controls
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: _buildBottomControls(context, state),
        ),
      ],
    );
  }

  Widget _buildBottomControls(BuildContext context, SpeedTrackingState state) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black.withOpacity(0.7),
          ],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Locked target indicator
          if (state.lockedTarget != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withOpacity(0.3),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.primaryColor),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock, color: AppTheme.primaryColor, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'Target Locked',
                    style: TextStyle(
                      color: AppTheme.primaryColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {
                      context.read<SpeedTrackingBloc>().add(const UnlockTarget());
                    },
                    child: const Icon(Icons.close, color: AppTheme.primaryColor, size: 16),
                  ),
                ],
              ),
            ),

          // Main controls row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Start/Stop tracking button
              _buildControlButton(
                icon: state.status == TrackingStatus.tracking
                    ? Icons.stop
                    : Icons.play_arrow,
                label: state.status == TrackingStatus.tracking
                    ? 'Stop'
                    : 'Start',
                onTap: () {
                  if (state.status == TrackingStatus.tracking) {
                    context.read<SpeedTrackingBloc>().add(const StopTracking());
                  } else {
                    context.read<SpeedTrackingBloc>().add(const StartTracking());
                  }
                },
                color: state.status == TrackingStatus.tracking
                    ? AppTheme.errorColor
                    : AppTheme.successColor,
              ),

              // Capture button (center, larger)
              CaptureButtonWidget(
                isEnabled: state.status == TrackingStatus.tracking &&
                           !state.isCapturing,
                isCapturing: state.isCapturing,
                onCapture: () {
                  context.read<SpeedTrackingBloc>().add(const CapturePressed());
                },
              ),

              // Lock target button
              _buildControlButton(
                icon: state.lockedTarget != null
                    ? Icons.lock
                    : Icons.lock_open,
                label: 'Lock',
                onTap: () {
                  if (state.lockedTarget != null) {
                    context.read<SpeedTrackingBloc>().add(const UnlockTarget());
                  } else {
                    context.read<SpeedTrackingBloc>().add(const LockTarget());
                  }
                },
                color: state.lockedTarget != null
                    ? AppTheme.primaryColor
                    : AppTheme.textSecondary,
                enabled: state.trackedVehicles.isNotEmpty,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color color = AppTheme.textPrimary,
    bool enabled = true,
  }) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Opacity(
        opacity: enabled ? 1.0 : 0.5,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppTheme.cardColor,
                shape: BoxShape.circle,
                border: Border.all(color: color.withOpacity(0.5)),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

