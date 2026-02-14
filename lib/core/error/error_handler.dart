import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

/// Global error handler for the application
///
/// Ensures all errors are logged and handled gracefully without crashing.
class GlobalErrorHandler {
  static final Logger _logger = Logger(
    printer: PrettyPrinter(
      methodCount: 5,
      errorMethodCount: 8,
      lineLength: 120,
      colors: true,
      printEmojis: true,
    ),
  );

  /// Handle Flutter framework errors
  static void handleFlutterError(FlutterErrorDetails details) {
    try {
      _logger.e(
        'Flutter Error',
        error: details.exception,
        stackTrace: details.stack,
      );

      // In debug mode, also print to console
      if (kDebugMode) {
        FlutterError.dumpErrorToConsole(details);
      }

      // Could add crash reporting service here (e.g., Firebase Crashlytics)
      _reportError(details.exception, details.stack);
    } catch (e) {
      // Fallback if error handling itself fails
      debugPrint('Error in error handler: $e');
    }
  }

  /// Handle uncaught errors from the zone
  static void handleUncaughtError(Object error, StackTrace stackTrace) {
    try {
      _logger.e(
        'Uncaught Error',
        error: error,
        stackTrace: stackTrace,
      );

      // Could add crash reporting service here
      _reportError(error, stackTrace);
    } catch (e) {
      debugPrint('Error in uncaught error handler: $e');
    }
  }

  /// Handle expected errors (for logging purposes)
  static void handleError(
    Object error, {
    StackTrace? stackTrace,
    String? context,
  }) {
    try {
      _logger.e(
        context ?? 'Application Error',
        error: error,
        stackTrace: stackTrace,
      );
    } catch (e) {
      debugPrint('Error logging failed: $e');
    }
  }

  /// Log warning messages
  static void logWarning(String message, {dynamic data}) {
    try {
      _logger.w(message);
      if (data != null && kDebugMode) {
        debugPrint('Warning data: $data');
      }
    } catch (e) {
      debugPrint('Warning log failed: $e');
    }
  }

  /// Log info messages
  static void logInfo(String message, {dynamic data}) {
    try {
      _logger.i(message);
      if (data != null && kDebugMode) {
        debugPrint('Info data: $data');
      }
    } catch (e) {
      debugPrint('Info log failed: $e');
    }
  }

  /// Log debug messages (only in debug mode)
  static void logDebug(String message, {dynamic data}) {
    if (!kDebugMode) return;

    try {
      _logger.d(message);
      if (data != null) {
        debugPrint('Debug data: $data');
      }
    } catch (e) {
      debugPrint('Debug log failed: $e');
    }
  }

  /// Report error to external service (placeholder)
  static void _reportError(Object error, StackTrace? stackTrace) {
    // TODO: Implement crash reporting service integration
    // Examples: Firebase Crashlytics, Sentry, etc.

    if (kDebugMode) {
      debugPrint('Error would be reported: $error');
    }
  }
}

/// Mixin for classes that need error handling capabilities
mixin ErrorHandlerMixin {
  /// Safely execute an async operation with error handling
  Future<T?> safeAsync<T>(
    Future<T> Function() operation, {
    T? defaultValue,
    String? context,
  }) async {
    try {
      return await operation();
    } catch (e, stackTrace) {
      GlobalErrorHandler.handleError(
        e,
        stackTrace: stackTrace,
        context: context,
      );
      return defaultValue;
    }
  }

  /// Safely execute a sync operation with error handling
  T? safeSync<T>(
    T Function() operation, {
    T? defaultValue,
    String? context,
  }) {
    try {
      return operation();
    } catch (e, stackTrace) {
      GlobalErrorHandler.handleError(
        e,
        stackTrace: stackTrace,
        context: context,
      );
      return defaultValue;
    }
  }
}

