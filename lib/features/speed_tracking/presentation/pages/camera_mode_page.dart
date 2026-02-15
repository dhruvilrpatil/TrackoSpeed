import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:get_it/get_it.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/platform/camera_service.dart';
import '../../../../core/platform/gallery_service.dart';
import '../bloc/speed_tracking_bloc.dart';
import '../widgets/camera_preview_widget.dart';
import '../widgets/vehicle_overlay_widget.dart';

/// Camera/AR mode page
/// - Live camera preview
/// - Zoom slider above capture button
/// - Orientation-aware captures
/// - Vehicle overlays only when vehicles are detected
/// - Gallery shows captured photos
class CameraModePage extends StatefulWidget {
  const CameraModePage({super.key});

  @override
  State<CameraModePage> createState() => _CameraModePageState();
}

class _CameraModePageState extends State<CameraModePage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  double _currentZoom = 0.0; // 0.0 = 1x, 1.0 = max zoom
  CameraService? _cameraService;
  bool _showFlash = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    try {
      _cameraService = GetIt.instance<CameraService>();
    } catch (_) {}

    // Ensure tracking is started when entering camera mode
    final bloc = context.read<SpeedTrackingBloc>();
    if (!bloc.state.isTrackingActive) {
      bloc.add(const StartTracking());
    }
  }

  @override
  void dispose() {
    // Stop tracking when leaving AR mode so camera is released
    try {
      context.read<SpeedTrackingBloc>().add(const StopTracking());
    } catch (_) {}
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When app resumes, re-start camera preview if tracking was active
    if (state == AppLifecycleState.resumed) {
      final bloc = context.read<SpeedTrackingBloc>();
      if (bloc.state.isTrackingActive && _cameraService != null) {
        _cameraService!.startPreview();
      }
    } else if (state == AppLifecycleState.paused) {
      // Pause camera preview when app is backgrounded
      _cameraService?.pausePreview();
    }
  }

  void _onZoomChanged(double value) {
    setState(() {
      _currentZoom = value;
    });
    _cameraService?.setZoomLevel(value);
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<SpeedTrackingBloc, SpeedTrackingState>(
      listenWhen: (prev, curr) =>
          (prev.lastCaptureMessage != curr.lastCaptureMessage &&
              curr.lastCaptureMessage != null) ||
          (prev.isCapturing != curr.isCapturing && curr.isCapturing),
      buildWhen: (prev, curr) =>
          prev.cameraReady != curr.cameraReady ||
          prev.trackedVehicles != curr.trackedVehicles ||
          prev.lockedTarget != curr.lockedTarget ||
          prev.userSpeedKmh != curr.userSpeedKmh ||
          prev.isCapturing != curr.isCapturing ||
          prev.captureCount != curr.captureCount ||
          prev.gpsValid != curr.gpsValid ||
          prev.flashEnabled != curr.flashEnabled ||
          prev.detectedPlate != curr.detectedPlate ||
          prev.confidenceScore != curr.confidenceScore ||
          prev.showPlateConfirmation != curr.showPlateConfirmation ||
          prev.pendingPlateNumber != curr.pendingPlateNumber ||
          prev.frameWidth != curr.frameWidth ||
          prev.frameHeight != curr.frameHeight,
      listener: (context, state) {
        // Trigger flash on capture start
        if (state.isCapturing && !_showFlash) {
          setState(() => _showFlash = true);
          Future.delayed(const Duration(milliseconds: 250), () {
            if (mounted) setState(() => _showFlash = false);
          });
        }
        if (state.lastCaptureMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                state.lastCaptureMessage!,
                style: GoogleFonts.notoSans(decoration: TextDecoration.none),
              ),
              backgroundColor: state.lastCapturePath != null
                  ? AppTheme.successColor
                  : AppTheme.errorColor,
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.all(16),
            ),
          );
        }
      },
      builder: (context, state) {
        return Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            fit: StackFit.expand,
            children: [
              // Camera preview
              _buildCameraPreview(state),

              // Vehicle detection overlays — only when vehicles detected
              if (state.trackedVehicles.isNotEmpty)
                RepaintBoundary(
                  child: VehicleOverlayWidget(
                    vehicles: state.trackedVehicles,
                    lockedTarget: state.lockedTarget,
                    confidenceScore: state.confidenceScore,
                    plateText: state.detectedPlate,
                    detectionFrameWidth: state.frameWidth.toDouble(),
                    detectionFrameHeight: state.frameHeight.toDouble(),
                    onVehicleTap: (id) {
                      context.read<SpeedTrackingBloc>().add(LockTarget(id));
                    },
                  ),
                ),

              // Speed overlay box
              _buildSpeedOverlayBox(state),

              // Top bar
              _buildTopBar(context, state),

              // Zoom slider + bottom controls
              _buildBottomSection(context, state),

              // Capture flash
              if (_showFlash) _buildCaptureFlash(),

              // Plate confirmation overlay
              if (state.showPlateConfirmation)
                _buildPlateConfirmationOverlay(context, state),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCameraPreview(SpeedTrackingState state) {
    if (!state.cameraReady) {
      return Container(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: AppTheme.primaryColor),
              const SizedBox(height: 16),
              Text(
                'Initializing Camera...',
                style: GoogleFonts.notoSans(
                  color: Colors.white,
                  fontSize: 16,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return const CameraPreviewWidget();
  }

  Widget _buildSpeedOverlayBox(SpeedTrackingState state) {
    final isTracking = state.isTrackingActive;
    final speed = isTracking ? state.userSpeedKmh : 0.0;
    final displaySpeed = isTracking ? '${speed.toInt()} km/h' : '-- km/h';

    // Positioned above the bottom section (zoom+controls ≈ 180px)
    // so it never overlaps with other UI.
    return Positioned(
      bottom: 210,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.red.withValues(alpha: 0.4),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.speed, color: Colors.white, size: 24),
              const SizedBox(width: 8),
              Text(
                displaySpeed,
                style: GoogleFonts.notoSans(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, SpeedTrackingState state) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 8,
          left: 16,
          right: 16,
          bottom: 12,
        ),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.black87, Colors.transparent],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Row(
          children: [
            _buildCircleButton(
              icon: Icons.arrow_back,
              onTap: () => Navigator.of(context).pop(),
            ),
            const Spacer(),
            // GPS indicator
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.satellite_alt,
                    color: state.gpsValid
                        ? AppTheme.successColor
                        : AppTheme.errorColor,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    state.gpsValid ? 'GPS OK' : 'No GPS',
                    style: GoogleFonts.notoSans(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (state.captureCount > 0)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.camera_alt, color: Colors.white, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      '${state.captureCount}',
                      style: GoogleFonts.notoSans(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(width: 8),
            _buildCircleButton(
              icon: state.flashEnabled ? Icons.flash_on : Icons.flash_off,
              onTap: () =>
                  context.read<SpeedTrackingBloc>().add(const ToggleFlash()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomSection(BuildContext context, SpeedTrackingState state) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          bottom: MediaQuery.of(context).padding.bottom + 16,
          top: 12,
        ),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.transparent, Colors.black87],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Zoom slider
            _buildZoomSlider(),
            const SizedBox(height: 16),
            // Capture controls row
            _buildCaptureControls(context, state),
          ],
        ),
      ),
    );
  }

  /// Zoom slider with 1x–10x labels
  Widget _buildZoomSlider() {
    final zoomLabel = '${(1.0 + _currentZoom * 9.0).toStringAsFixed(1)}x';
    return Row(
      children: [
        Text(
          '1x',
          style: GoogleFonts.notoSans(
            color: Colors.white70,
            fontSize: 12,
            decoration: TextDecoration.none,
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: AppTheme.primaryColor,
              inactiveTrackColor: Colors.white24,
              thumbColor: Colors.white,
              overlayColor: AppTheme.primaryColor.withValues(alpha: 0.2),
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            ),
            child: Slider(
              value: _currentZoom,
              min: 0.0,
              max: 1.0,
              onChanged: _onZoomChanged,
            ),
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            zoomLabel,
            textAlign: TextAlign.center,
            style: GoogleFonts.notoSans(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCaptureControls(BuildContext context, SpeedTrackingState state) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Gallery button
        _buildSideButton(
          icon: Icons.photo_library,
          label: 'Gallery',
          badge: state.captureCount > 0 ? '${state.captureCount}' : null,
          onTap: () => _showCaptureGallery(context, state),
        ),

        // Capture button
        GestureDetector(
          onTap: state.isCapturing
              ? null
              : () {
                  // Capture with current device orientation
                  context.read<SpeedTrackingBloc>().add(const CapturePressed());
                },
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 4),
              boxShadow: [
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.3),
                  blurRadius: 12,
                ),
              ],
            ),
            child: Container(
              margin: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: state.isCapturing ? Colors.grey : Colors.white,
              ),
              child: state.isCapturing
                  ? const Padding(
                      padding: EdgeInsets.all(18),
                      child: CircularProgressIndicator(
                        color: AppTheme.primaryColor,
                        strokeWidth: 3,
                      ),
                    )
                  : const Icon(Icons.camera_alt,
                      color: Colors.black87, size: 28),
            ),
          ),
        ),

        // Lock target
        _buildSideButton(
          icon: state.lockedTarget != null
              ? Icons.gps_fixed
              : Icons.gps_not_fixed,
          label: state.lockedTarget != null ? 'Unlock' : 'Lock',
          onTap: () {
            final bloc = context.read<SpeedTrackingBloc>();
            if (state.lockedTarget != null) {
              bloc.add(const UnlockTarget());
            } else if (state.trackedVehicles.isNotEmpty) {
              bloc.add(const LockTarget());
            }
          },
        ),
      ],
    );
  }

  Widget _buildSideButton({
    required IconData icon,
    required String label,
    String? badge,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(icon, color: Colors.white, size: 28),
              if (badge != null)
                Positioned(
                  top: -6,
                  right: -10,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      badge,
                      style: GoogleFonts.notoSans(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.notoSans(
              fontSize: 11,
              color: Colors.white70,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCircleButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.black54,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white30, width: 1),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }

  Widget _buildCaptureFlash() {
    return AnimatedOpacity(
      opacity: _showFlash ? 0.7 : 0.0,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      child: Container(color: Colors.white),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  Plate Confirmation Overlay
  // ═══════════════════════════════════════════════════════════════

  Widget _buildPlateConfirmationOverlay(
    BuildContext context,
    SpeedTrackingState state,
  ) {
    final plateText = state.pendingPlateNumber ?? '';
    final hasPlate = plateText.isNotEmpty;
    final controller = TextEditingController(text: plateText);

    // Force dark theme for this overlay — camera page is always dark
    return Positioned.fill(
      child: Theme(
        data: AppTheme.darkTheme,
        child: Container(
          color: Colors.black54,
          child: Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 32),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.surfaceColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.primaryColor, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryColor.withValues(alpha: 0.3),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.directions_car,
                    color: AppTheme.primaryColor,
                    size: 40,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    hasPlate ? 'Plate Detected' : 'Enter Plate Number',
                    style: GoogleFonts.notoSans(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    hasPlate
                        ? 'Confirm or correct the plate number:'
                        : 'Enter the vehicle plate number below:',
                    style: GoogleFonts.notoSans(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Editable plate text field
                  Material(
                    color: Colors.transparent,
                    child: TextField(
                      controller: controller,
                      textAlign: TextAlign.center,
                      textCapitalization: TextCapitalization.characters,
                      style: GoogleFonts.notoSans(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 2,
                      ),
                      cursorColor: AppTheme.primaryColor,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: AppTheme.cardColor,
                        hintText: hasPlate ? null : 'e.g. MH34AB1234',
                        hintStyle: GoogleFonts.notoSans(
                          fontSize: 20,
                          color: Colors.white30,
                          letterSpacing: 2,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: AppTheme.primaryColor,
                            width: 2,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 14,
                          horizontal: 16,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      // Cancel
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            context
                                .read<SpeedTrackingBloc>()
                                .add(const CancelCapture());
                          },
                          icon: const Icon(Icons.close, size: 18),
                          label: Text(
                            'Cancel',
                            style: GoogleFonts.notoSans(fontSize: 14),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white70,
                            side: const BorderSide(color: Colors.white30),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Confirm
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            final confirmed = controller.text.trim();
                            context
                                .read<SpeedTrackingBloc>()
                                .add(ConfirmPlate(confirmed));
                          },
                          icon: const Icon(Icons.check, size: 18),
                          label: Text(
                            'Confirm',
                            style: GoogleFonts.notoSans(fontSize: 14),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Open captures in the device's native gallery app
  void _showCaptureGallery(BuildContext context, SpeedTrackingState state) async {
    if (state.lastCapturePath == null && state.captureCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No captures yet. Tap the capture button to take a photo.',
            style: GoogleFonts.notoSans(decoration: TextDecoration.none),
          ),
          backgroundColor: AppTheme.warningColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final galleryService = GetIt.I<GalleryService>();

    // If we have a last capture path, open that specific image in gallery
    if (state.lastCapturePath != null) {
      final opened = await galleryService.openInGallery(state.lastCapturePath!);
      if (!opened && context.mounted) {
        // Fallback: try opening the album
        await galleryService.openAlbum();
      }
    } else {
      // No specific path — open the TrackoSpeed album
      await galleryService.openAlbum();
    }
  }


}
