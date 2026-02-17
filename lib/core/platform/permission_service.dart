import 'package:permission_handler/permission_handler.dart';
import 'package:dartz/dartz.dart';

import '../error/failures.dart';
import '../error/error_handler.dart';

/// Permission types used by the application
enum AppPermission {
  camera,
  location,
  storage,
  sensors,
}

/// Result of permission request
class PermissionResult {
  final AppPermission permission;
  final bool isGranted;
  final bool isPermanentlyDenied;
  final String message;

  const PermissionResult({
    required this.permission,
    required this.isGranted,
    this.isPermanentlyDenied = false,
    this.message = '',
  });
}

/// Service for handling all permission requests
///
/// Provides user-friendly explanations for why each permission is needed
/// and handles all denial scenarios gracefully.
class PermissionService with ErrorHandlerMixin {
  /// Permission explanations for user dialog
  static const Map<AppPermission, String> _permissionExplanations = {
    AppPermission.camera:
      'Camera access is required to detect and track vehicles in real-time. '
      'This allows the app to identify vehicles and estimate their speed.',
    AppPermission.location:
      'Location access is required to measure your vehicle\'s speed using GPS. '
      'This speed is used to calculate the relative speed of other vehicles.',
    AppPermission.storage:
      'Storage access is required to save captured images with speed information '
      'to your device\'s photo gallery.',
    AppPermission.sensors:
      'Sensor access improves speed accuracy by using device motion data. '
      'This is optional but recommended for better results.',
  };

  /// Get explanation for a permission
  String getExplanation(AppPermission permission) {
    return _permissionExplanations[permission] ?? 'Permission required for app functionality.';
  }

  /// Check if a single permission is granted
  Future<bool> isGranted(AppPermission permission) async {
    try {
      final status = await _getPermissionStatus(permission);
      return status.isGranted;
    } catch (e) {
      GlobalErrorHandler.handleError(e, context: 'Check permission: $permission');
      return false;
    }
  }

  /// Check multiple permissions at once
  Future<Map<AppPermission, bool>> checkMultiple(List<AppPermission> permissions) async {
    final results = <AppPermission, bool>{};

    for (final permission in permissions) {
      results[permission] = await isGranted(permission);
    }

    return results;
  }

  /// Request a single permission
  Future<Result<PermissionResult>> request(AppPermission permission) async {
    try {
      final nativePermission = _mapToNativePermission(permission);

      // Check current status first
      var status = await nativePermission.status;

      // If already granted, return success
      if (status.isGranted) {
        return Right(PermissionResult(
          permission: permission,
          isGranted: true,
          message: 'Permission already granted',
        ));
      }

      // If permanently denied, can't request again
      if (status.isPermanentlyDenied) {
        return Right(PermissionResult(
          permission: permission,
          isGranted: false,
          isPermanentlyDenied: true,
          message: 'Permission permanently denied. Please enable in Settings.',
        ));
      }

      // Request the permission
      status = await nativePermission.request();

      return Right(PermissionResult(
        permission: permission,
        isGranted: status.isGranted,
        isPermanentlyDenied: status.isPermanentlyDenied,
        message: status.isGranted
          ? 'Permission granted'
          : 'Permission denied by user',
      ));
    } catch (e, stackTrace) {
      GlobalErrorHandler.handleError(e, stackTrace: stackTrace, context: 'Request permission');
      return Left(PermissionFailure(
        message: 'Failed to request permission: $e',
        permissionType: permission.name,
        originalError: e,
        stackTrace: stackTrace,
      ));
    }
  }

  /// Request all required permissions for the app
  Future<Result<Map<AppPermission, PermissionResult>>> requestAll() async {
    try {
      final results = <AppPermission, PermissionResult>{};

      // Request in order of importance
      final requiredPermissions = [
        AppPermission.camera,
        AppPermission.location,
        AppPermission.storage,
      ];

      for (final permission in requiredPermissions) {
        final result = await request(permission);
        result.fold(
          (failure) {
            results[permission] = PermissionResult(
              permission: permission,
              isGranted: false,
              message: failure.message,
            );
          },
          (permResult) {
            results[permission] = permResult;
          },
        );

        // Small delay between requests to avoid overwhelming user
        await Future.delayed(const Duration(milliseconds: 100));
      }

      // Request optional permissions
      final optionalResult = await request(AppPermission.sensors);
      optionalResult.fold(
        (_) {}, // Ignore failure for optional permission
        (permResult) => results[AppPermission.sensors] = permResult,
      );

      return Right(results);
    } catch (e, stackTrace) {
      GlobalErrorHandler.handleError(e, stackTrace: stackTrace, context: 'Request all permissions');
      return Left(PermissionFailure(
        message: 'Failed to request permissions: $e',
        permissionType: 'all',
        originalError: e,
        stackTrace: stackTrace,
      ));
    }
  }

  /// Check if all required permissions are granted
  Future<bool> areAllRequiredGranted() async {
    try {
      final camera = await isGranted(AppPermission.camera);
      final location = await isGranted(AppPermission.location);
      final storage = await isGranted(AppPermission.storage);

      return camera && location && storage;
    } catch (e) {
      GlobalErrorHandler.handleError(e, context: 'Check all permissions');
      return false;
    }
  }

  /// Open app settings for manual permission configuration
  Future<bool> openSettings() async {
    try {
      return await openAppSettings();
    } catch (e) {
      GlobalErrorHandler.handleError(e, context: 'Open settings');
      return false;
    }
  }

  /// Get detailed status of all permissions
  Future<Map<AppPermission, PermissionStatus>> getAllStatuses() async {
    final statuses = <AppPermission, PermissionStatus>{};

    for (final permission in AppPermission.values) {
      try {
        statuses[permission] = await _getPermissionStatus(permission);
      } catch (e) {
        statuses[permission] = PermissionStatus.denied;
      }
    }

    return statuses;
  }

  /// Map app permission to native permission
  Permission _mapToNativePermission(AppPermission permission) {
    switch (permission) {
      case AppPermission.camera:
        return Permission.camera;
      case AppPermission.location:
        return Permission.locationWhenInUse;
      case AppPermission.storage:
        // Use photos permission for Android 13+
        return Permission.photos;
      case AppPermission.sensors:
        return Permission.sensors;
    }
  }

  /// Get native permission status
  Future<PermissionStatus> _getPermissionStatus(AppPermission permission) async {
    final nativePermission = _mapToNativePermission(permission);
    return await nativePermission.status;
  }
}

