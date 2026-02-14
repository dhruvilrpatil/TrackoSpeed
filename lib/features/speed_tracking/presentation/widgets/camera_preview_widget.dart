import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:get_it/get_it.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/platform/camera_service.dart';
import '../../../../core/theme/app_theme.dart';

/// Live camera preview widget
///
/// Uses CameraService's controller directly and stays live.
/// Handles camera not initialized gracefully.
class CameraPreviewWidget extends StatefulWidget {
  const CameraPreviewWidget({super.key});

  @override
  State<CameraPreviewWidget> createState() => _CameraPreviewWidgetState();
}

class _CameraPreviewWidgetState extends State<CameraPreviewWidget> {
  CameraService? _cameraService;

  @override
  void initState() {
    super.initState();
    try {
      _cameraService = GetIt.instance<CameraService>();
    } catch (_) {
      // Service not registered — will show fallback UI
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _cameraService?.controller;

    if (controller == null || !controller.value.isInitialized) {
      return _buildPlaceholder('Camera not available');
    }

    // Use CameraPreview widget which shows the live camera feed
    return LayoutBuilder(
      builder: (context, constraints) {
        // Get camera aspect ratio
        final cameraAspectRatio = controller.value.aspectRatio;

        // Fill the available space, centering and cropping as needed
        return ClipRect(
          child: OverflowBox(
            alignment: Alignment.center,
            maxWidth: constraints.maxWidth,
            maxHeight: constraints.maxHeight,
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: constraints.maxWidth,
                height: constraints.maxWidth * cameraAspectRatio,
                child: CameraPreview(controller),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPlaceholder(String message) {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_off, color: AppTheme.textHint, size: 64),
            const SizedBox(height: 16),
            Text(
              message,
              style: GoogleFonts.notoSans(
                color: AppTheme.textSecondary,
                fontSize: 16,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
