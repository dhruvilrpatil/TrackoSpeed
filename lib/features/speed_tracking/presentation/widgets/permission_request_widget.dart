import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_theme.dart';
import '../bloc/speed_tracking_bloc.dart';

/// Modern permission request widget with gradient accents and animated feel
class PermissionRequestWidget extends StatelessWidget {
  final PermissionStatus permissions;
  final VoidCallback onRequestPermissions;
  final VoidCallback onOpenSettings;

  const PermissionRequestWidget({
    super.key,
    required this.permissions,
    required this.onRequestPermissions,
    required this.onOpenSettings,
  });

  bool get _allGranted =>
      permissions.camera && permissions.location && permissions.storage;

  int get _grantedCount =>
      (permissions.camera ? 1 : 0) +
      (permissions.location ? 1 : 0) +
      (permissions.storage ? 1 : 0);

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF1A1A2E),
            Color(0xFF24243E),
            Color(0xFF1A1A2E),
          ],
        ),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: screenHeight - MediaQuery.of(context).padding.top - 60,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 20),

                // App icon / brand header
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppTheme.primaryColor,
                        AppTheme.secondaryColor,
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryColor.withOpacity(0.4),
                        blurRadius: 30,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.speed_rounded,
                    size: 48,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 24),

                // Title
                Text(
                  'TrackoSpeed',
                  style: GoogleFonts.montserrat(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 1.2,
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Real-time vehicle speed detection',
                  style: GoogleFonts.notoSans(
                    fontSize: 14,
                    color: AppTheme.textSecondary,
                    decoration: TextDecoration.none,
                  ),
                ),

                const SizedBox(height: 36),

                // Subtitle
                Text(
                  'To get started, please allow the\nfollowing permissions',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.notoSans(
                    fontSize: 16,
                    color: Colors.white.withOpacity(0.85),
                    height: 1.5,
                    decoration: TextDecoration.none,
                  ),
                ),

                const SizedBox(height: 28),

                // Progress indicator
                _buildProgressBar(),

                const SizedBox(height: 28),

                // Permission cards
                _buildPermissionCard(
                  icon: Icons.videocam_rounded,
                  title: 'Camera Access',
                  description:
                      'Point your camera at vehicles to detect and track their speed in real-time using AI.',
                  isGranted: permissions.camera,
                  accentColor: AppTheme.teal,
                ),
                const SizedBox(height: 12),
                _buildPermissionCard(
                  icon: Icons.my_location_rounded,
                  title: 'Location Access',
                  description:
                      'GPS is used to calculate your own speed and calibrate vehicle speed measurements.',
                  isGranted: permissions.location,
                  accentColor: AppTheme.cyan,
                ),
                const SizedBox(height: 12),
                _buildPermissionCard(
                  icon: Icons.photo_library_rounded,
                  title: 'Storage Access',
                  description:
                      'Save captured photos with speed overlays directly to your device gallery.',
                  isGranted: permissions.storage,
                  accentColor: const Color(0xFF80CBC4),
                ),

                const SizedBox(height: 36),

                // Grant button
                Container(
                  width: double.infinity,
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: _allGranted
                        ? const LinearGradient(
                            colors: [
                              AppTheme.successColor,
                              Color(0xFF4CAF50),
                            ],
                          )
                        : const LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              AppTheme.primaryColor,
                              AppTheme.secondaryColor,
                            ],
                          ),
                    boxShadow: [
                      BoxShadow(
                        color: (_allGranted
                                ? AppTheme.successColor
                                : AppTheme.primaryColor)
                            .withOpacity(0.4),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: onRequestPermissions,
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _allGranted
                                  ? Icons.check_circle_rounded
                                  : Icons.shield_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              _allGranted
                                  ? 'All Permissions Granted'
                                  : 'Grant Permissions',
                              style: GoogleFonts.notoSans(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Settings link
                TextButton.icon(
                  onPressed: onOpenSettings,
                  icon: Icon(
                    Icons.settings_rounded,
                    size: 18,
                    color: AppTheme.textSecondary.withOpacity(0.7),
                  ),
                  label: Text(
                    'Open App Settings',
                    style: GoogleFonts.notoSans(
                      fontSize: 13,
                      color: AppTheme.textSecondary.withOpacity(0.7),
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),

                // Privacy note
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.lock_rounded,
                      size: 14,
                      color: AppTheme.textHint.withOpacity(0.6),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Your data stays on your device',
                      style: GoogleFonts.notoSans(
                        fontSize: 11,
                        color: AppTheme.textHint.withOpacity(0.6),
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProgressBar() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Permissions',
              style: GoogleFonts.notoSans(
                fontSize: 12,
                color: AppTheme.textSecondary,
                decoration: TextDecoration.none,
              ),
            ),
            Text(
              '$_grantedCount / 3 granted',
              style: GoogleFonts.notoSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _allGranted
                    ? AppTheme.successColor
                    : AppTheme.primaryColor,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: _grantedCount / 3.0,
            minHeight: 6,
            backgroundColor: AppTheme.cardColor,
            valueColor: AlwaysStoppedAnimation<Color>(
              _allGranted ? AppTheme.successColor : AppTheme.primaryColor,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPermissionCard({
    required IconData icon,
    required String title,
    required String description,
    required bool isGranted,
    required Color accentColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isGranted
            ? AppTheme.successColor.withOpacity(0.08)
            : AppTheme.cardColor.withOpacity(0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isGranted
              ? AppTheme.successColor.withOpacity(0.3)
              : accentColor.withOpacity(0.15),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: isGranted
                  ? AppTheme.successColor.withOpacity(0.15)
                  : accentColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              icon,
              color: isGranted ? AppTheme.successColor : accentColor,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.notoSans(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: GoogleFonts.notoSans(
                    color: AppTheme.textSecondary.withOpacity(0.85),
                    fontSize: 12,
                    height: 1.4,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Icon(
              isGranted
                  ? Icons.check_circle_rounded
                  : Icons.circle_outlined,
              key: ValueKey(isGranted),
              color: isGranted
                  ? AppTheme.successColor
                  : AppTheme.textHint.withOpacity(0.4),
              size: 26,
            ),
          ),
        ],
      ),
    );
  }
}

