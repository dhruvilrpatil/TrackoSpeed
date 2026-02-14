import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';

/// Capture button widget with animation
class CaptureButtonWidget extends StatefulWidget {
  final bool isEnabled;
  final bool isCapturing;
  final VoidCallback onCapture;

  const CaptureButtonWidget({
    super.key,
    required this.isEnabled,
    required this.isCapturing,
    required this.onCapture,
  });

  @override
  State<CaptureButtonWidget> createState() => _CaptureButtonWidgetState();
}

class _CaptureButtonWidgetState extends State<CaptureButtonWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.9).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    if (widget.isEnabled && !widget.isCapturing) {
      _controller.forward();
    }
  }

  void _onTapUp(TapUpDetails details) {
    _controller.reverse();
    if (widget.isEnabled && !widget.isCapturing) {
      widget.onCapture();
    }
  }

  void _onTapCancel() {
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: child,
          );
        },
        child: Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: widget.isEnabled && !widget.isCapturing
                ? AppStyles.captureButtonGradient
                : null,
            color: widget.isCapturing
                ? AppTheme.warningColor
                : (!widget.isEnabled ? AppTheme.textHint : null),
            border: Border.all(
              color: Colors.white,
              width: 4,
            ),
            boxShadow: [
              BoxShadow(
                color: widget.isEnabled
                    ? AppTheme.errorColor.withOpacity(0.4)
                    : Colors.transparent,
                blurRadius: 16,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Center(
            child: widget.isCapturing
                ? const SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 3,
                    ),
                  )
                : Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.2),
                    ),
                    child: const Icon(
                      Icons.camera,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

